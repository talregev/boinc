# WASM BOINC demo server: extends the official boinc-server-docker apache image to serve the wasm
# client + register the wasm sample app, so a browser can run real BOINC work against a real server.
#
# Build context is the REPO ROOT (see docker-compose.yml) so we can COPY the freshly built client and
# app artifacts. Build them first:
#     wasm/ci_configure_client.sh && wasm/ci_make.sh   # -> client/boinc_client.{js,wasm}
#     wasm/sample_app/build_app.sh                      # -> wasm/sample_app/app.{js,wasm}
#
# Use the plain :latest image (not -defaultargs): it carries the ONBUILD triggers meant for
# extension, which create the boincadm user + PROJECT_ROOT from the build args passed by compose.
FROM boinc/server_apache:latest

# COOP/COEP for the client page (SharedArrayBuffer) — needs mod_headers.
RUN a2enmod headers
COPY wasm/server/apache-wasm.conf /etc/apache2/conf-enabled/wasm.conf

# The wasm client page (served same-origin at /wasm) + the built client runtime. boincadm-owned so
# the registration script can drop account.txt (the demo account key) here at startup.
COPY wasm/server/client/index.html            /wasm-client/index.html
COPY client/boinc_client.js client/boinc_client.wasm  /wasm-client/
RUN chown -R boincadm:boincadm /wasm-client

# The app version files the registration script stages into the project.
#   /wasm      : the CPU sample app (plan_class '')
#   /wasm-gpu  : the WebGPU app (plan_class 'webgpu') — same app, GPU-typed version
#   plan_class_spec.xml : makes the scheduler match the generic 'webgpu' coproc type
COPY wasm/sample_app/app.js wasm/sample_app/app.wasm  /wasm/
COPY wasm/gpu_app/app.js    wasm/gpu_app/app.wasm     /wasm-gpu/
COPY wasm/server/plan_class_spec.xml                  /wasm-plan_class_spec.xml

# Register the app + create a workunit at startup (idempotent, waits for the project).
COPY wasm/server/register_wasm_app.sh /wasm-register.sh
COPY wasm/server/supervisor-wasm.conf /etc/supervisor/conf.d/zz-wasm-register.conf
RUN chmod +x /wasm-register.sh
