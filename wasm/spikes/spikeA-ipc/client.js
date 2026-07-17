'use strict';
// Spike A — the CLIENT side + the pass/fail test harness.
// In the real design this is the wasm BOINC client (main thread). Here it spawns the app as a
// worker_thread and drives it entirely through the shared APP_CLIENT_SHM channels, proving the
// process/IPC model that replaces fork()+execv()+SysV-shmem (client/app_start.cpp, lib/app_ipc.h).
//
// Success criteria (what "the spike succeeded" means) are asserted in finish():
//   - received a stream of monotonically increasing fraction_done that reaches 1.0
//   - bidirectional control worked: checkpoint requested -> acked, quit requested -> acked
//   - the app exited cleanly (not orphaned, not timed out)
// Exits 0 on success, 1 on any failure, with diagnostics.

const { Worker } = require('worker_threads');
const path = require('path');
const { makeSAB, Shm } = require('./shm');

const sab = makeSAB();
const shm = new Shm(sab);

const observed = [];            // every fraction_done we saw
let checkpointRequested = false, quitSent = false;
let gotCheckpointAck = false, gotQuitAck = false;
let finished = false;

const worker = new Worker(path.join(__dirname, 'app-worker.js'), { workerData: { sab } });
worker.on('message', (m) => {
    if (m.type === 'exited') finish();
    else if (m.type === 'orphaned') fail('app orphaned itself: client failed to heartbeat');
});
worker.on('error', (e) => fail('worker error: ' + (e && e.stack || e)));

// heartbeat every 100ms (BOINC-style keepalive)
const hb = setInterval(() => shm.send('HEARTBEAT', '<heartbeat/>'), 100);

// poll app status + control replies every 20ms
const poll = setInterval(() => {
    let msg, latest = null;
    while ((msg = shm.receive('APP_STATUS')) !== null) latest = msg;   // keep only the newest
    if (latest) {
        const m = latest.match(/<fraction_done>([^<]+)</);
        const f = m ? parseFloat(m[1]) : NaN;
        if (!Number.isNaN(f)) {
            observed.push(f);
            log(`fraction_done=${f.toFixed(2)}`);
            if (f >= 0.5 && !checkpointRequested && shm.send('CONTROL_REQ', '<checkpoint/>')) {
                checkpointRequested = true;
                log('-> requested checkpoint');
            }
            if (f >= 1.0 && checkpointRequested && !quitSent && shm.send('CONTROL_REQ', '<quit/>')) {
                quitSent = true;
                log('-> sent quit');
            }
        }
    }
    drainReplies();
}, 20);

const guard = setTimeout(() => fail('timed out: no clean completion within 10s'), 10000);

function drainReplies() {
    let r;
    while ((r = shm.receive('CONTROL_REPLY')) !== null) {
        if (r.includes('<ack>checkpoint</ack>') && !gotCheckpointAck) { gotCheckpointAck = true; log('<- checkpoint ack'); }
        if (r.includes('<ack>quit</ack>') && !gotQuitAck) { gotQuitAck = true; log('<- quit ack'); }
    }
}

function log(s) { process.stdout.write('  [client] ' + s + '\n'); }
function cleanup() { clearInterval(hb); clearInterval(poll); clearTimeout(guard); }

function fail(reason) {
    if (finished) return; finished = true;
    cleanup();
    console.error('\nSPIKE A: FAILED — ' + reason);
    worker.terminate().finally(() => process.exit(1));
}

function finish() {
    if (finished) return; finished = true;
    cleanup();
    drainReplies();     // final drain: the quit ack may land in the same tick as the exit message

    const problems = [];
    if (observed.length < 5) problems.push(`too few status updates (${observed.length})`);
    if (!observed.every((v, i) => i === 0 || v >= observed[i - 1])) problems.push('fraction_done not monotonic: ' + observed.join(','));
    if (!(Math.max.apply(null, observed) >= 0.999)) problems.push('never reached completion (peak ' + Math.max.apply(null, observed) + ')');
    if (!gotCheckpointAck) problems.push('no checkpoint ack');
    if (!gotQuitAck) problems.push('no quit ack');

    if (problems.length) {
        finished = false;   // let fail() run
        return fail(problems.join('; '));
    }
    console.log('\nSPIKE A: PASSED');
    console.log(`  status updates : ${observed.length} (peak fraction_done ${Math.max.apply(null, observed)})`);
    console.log('  checkpoint handshake : ok');
    console.log('  quit handshake       : ok');
    console.log('  monotonic progress   : ok');
    console.log('  => SharedArrayBuffer can carry the APP_CLIENT_SHM protocol; process model is viable.');
    worker.terminate().finally(() => process.exit(0));
}
