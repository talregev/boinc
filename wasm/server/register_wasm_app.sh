#!/bin/bash
# Register the wasm sample app on a boinc-server-docker project and create a workunit. Runs inside
# the apache container as boincadm (see the supervisord hook in the Dockerfile). Idempotent: it
# waits for the project to be ready, then registers the app + one workunit only if not already done.
#
# This encodes the manual Stage 7.3 steps (see wasm/phase7-plan.md) so the whole server — able to
# serve the wasm CPU app to a browser client — comes up with a single `docker compose up`.
set -e
PROJECT=${PROJECT_ROOT:-/home/boincadm/project}
PLATFORM=i686-pc-linux-gnu   # the wasm client reports this (the build's HOSTTYPE)
APP=sample

cd "$PROJECT" 2>/dev/null || { echo "[wasm-register] project dir not ready"; exit 0; }

# Wait until the project DB + tools are ready (makeproject-step3 has run).
for i in $(seq 1 60); do
    [ -f config.xml ] && [ -x bin/xadd ] && bin/xadd >/dev/null 2>&1 && break
    sleep 2
done

# Read DB creds from config.xml
DBH=$(grep -oE '<db_host>[^<]*' config.xml | cut -d'>' -f2)
DBN=$(grep -oE '<db_name>[^<]*' config.xml | cut -d'>' -f2)
DBU=$(grep -oE '<db_user>[^<]*' config.xml | cut -d'>' -f2)
DBP=$(grep -oE '<db_passwd>[^<]*' config.xml | cut -d'>' -f2)
mysql_q() { mysql -h "$DBH" -u"$DBU" -p"$DBP" "$DBN" -N -e "$1" 2>/dev/null; }

# Install the plan-class spec so the scheduler can match the generic 'webgpu' coproc type and send a
# GPU-typed app version. Idempotent (plain copy). Presence of this file switches the scheduler to
# plan_class_spec for non-empty plan classes; the empty (CPU) plan class is unaffected.
if [ -f /wasm-plan_class_spec.xml ]; then
    cp /wasm-plan_class_spec.xml "$PROJECT/plan_class_spec.xml"
    echo "[wasm-register] installed plan_class_spec.xml (webgpu plan class)"
fi

# Register the app only if not already done (idempotent); account creation below runs regardless.
if [ "$(mysql_q "select count(*) from app_version where plan_class='' and appid=(select id from app where name='$APP');")" = "0" ]; then

echo "[wasm-register] generating a code-signing keypair"
# The compose does NOT mount /dev/null over the private key, so this is a real writable key.
bin/crypt_prog -genkey 1024 keys/code_sign_private keys/code_sign_public >/dev/null 2>&1 || true

echo "[wasm-register] adding app '$APP'"
if ! grep -q "<name>$APP</name>" project.xml; then
    sed -i "s#</boinc>#    <app>\n        <name>$APP</name>\n        <user_friendly_name>WASM Sample</user_friendly_name>\n    </app>\n</boinc>#" project.xml
fi
bin/xadd >/dev/null 2>&1 || true

echo "[wasm-register] staging app version ($APP 1.0 $PLATFORM): app.js (main) + app.wasm"
VDIR="apps/$APP/1.0/$PLATFORM"
mkdir -p "$VDIR"
cp /wasm/app.js   "$VDIR/app.js"
cp /wasm/app.wasm "$VDIR/app.wasm"
cat > "$VDIR/version.xml" <<EOF
<version>
    <file>
        <physical_name>app.js</physical_name>
        <main_program/>
    </file>
    <file>
        <physical_name>app.wasm</physical_name>
    </file>
</version>
EOF
echo "[wasm-register] staging GPU-typed app version ($APP 1.0 ${PLATFORM}__webgpu): WebGPU app.js + app.wasm"
# Same platform, plan_class 'webgpu'. The BOINC convention is a "<platform>__<plan_class>" version
# dir; version.xml names the plan class. update_versions signs + registers it as a second app version
# of the same app, so a host reporting the 'webgpu' coproc gets this GPU version and others get CPU.
# Unique physical filenames (app_gpu.*): BOINC files are immutable + project-global by physical name,
# so the GPU version can't reuse the CPU version's app.js/app.wasm. The WebGPU app is built as
# app_gpu.js/app_gpu.wasm (see wasm/gpu_app/build_app.sh) so its Emscripten loader finds its own wasm.
GDIR="apps/$APP/1.0/${PLATFORM}__webgpu"
mkdir -p "$GDIR"
cp /wasm-gpu/app_gpu.js   "$GDIR/app_gpu.js"
cp /wasm-gpu/app_gpu.wasm "$GDIR/app_gpu.wasm"
cat > "$GDIR/version.xml" <<EOF
<version>
    <plan_class>webgpu</plan_class>
    <file>
        <physical_name>app_gpu.js</physical_name>
        <main_program/>
    </file>
    <file>
        <physical_name>app_gpu.wasm</physical_name>
    </file>
</version>
EOF
yes | bin/update_versions >/dev/null 2>&1 || true

echo "[wasm-register] creating templates + input + workunit"
mkdir -p templates
cat > templates/${APP}_in.xml <<EOF
<file_info>
    <number>0</number>
</file_info>
<workunit>
    <file_ref>
        <file_number>0</file_number>
        <open_name>in</open_name>
        <copy_file/>
    </file_ref>
    <rsc_fpops_est>1000000000</rsc_fpops_est>
    <rsc_fpops_bound>100000000000</rsc_fpops_bound>
    <rsc_memory_bound>134217728</rsc_memory_bound>
    <rsc_disk_bound>134217728</rsc_disk_bound>
    <delay_bound>86400</delay_bound>
</workunit>
EOF
cat > templates/${APP}_out.xml <<EOF
<file_info>
    <name><OUTFILE_0/></name>
    <generated_locally/>
    <upload_when_present/>
    <max_nbytes>1000000</max_nbytes>
    <url><UPLOAD_URL/></url>
</file_info>
<result>
    <file_ref>
        <file_name><OUTFILE_0/></file_name>
        <open_name>out</open_name>
        <copy_file/>
    </file_ref>
</result>
EOF
echo "wasm input payload" > /tmp/${APP}_input.txt
bin/stage_file --copy /tmp/${APP}_input.txt >/dev/null 2>&1 || true
bin/create_work --appname "$APP" --wu_name ${APP}_wu_1 \
    --wu_template templates/${APP}_in.xml --result_template templates/${APP}_out.xml \
    ${APP}_input.txt >/dev/null 2>&1 || true

echo "[wasm-register] done: app_version=$(mysql_q "select count(*) from app_version;") results=$(mysql_q "select count(*) from result;")"
else
    echo "[wasm-register] app '$APP' already registered; skipping app registration"
fi

# Pre-create a demo account and expose its key at /wasm/account.txt so the browser client can attach
# without the user typing credentials. Wait for Apache+PHP to be serving, then call create_account.php.
if [ ! -s /wasm-client/account.txt ]; then
    EMAIL="demo@wasm.test"; PW="wasmdemo"
    HASH=$(printf '%s' "${PW}${EMAIL}" | md5sum | cut -d' ' -f1)
    for i in $(seq 1 30); do
        OUT=$(curl -s "http://127.0.0.1/boincserver/create_account.php?email_addr=${EMAIL}&passwd_hash=${HASH}&user_name=demo" 2>/dev/null)
        AUTH=$(echo "$OUT" | grep -oE '<authenticator>[^<]+' | cut -d'>' -f2)
        if [ -n "$AUTH" ]; then echo "$AUTH" > /wasm-client/account.txt; echo "[wasm-register] demo account key written"; break; fi
        sleep 2
    done
fi
