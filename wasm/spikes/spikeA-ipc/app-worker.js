'use strict';
// Spike A — the SCIENCE APP side, running in a Web Worker (here: a Node worker_thread).
// In the real design this is a wasm science app; the only thing that matters for the spike is that
// it talks to the client purely through the shared APP_CLIENT_SHM channels — no fork, no SysV shmem.
//
// It mimics BOINC app-lib behaviour: report fraction_done/cpu_time via APP_STATUS, honour
// process-control requests (checkpoint, quit), and self-exit if the client's heartbeats stop.

const { workerData, parentPort } = require('worker_threads');
const { Shm } = require('./shm');

const shm = new Shm(workerData.sab);

let fraction = 0;
let cpuTime = 0;
let checkpointCpuTime = 0;
let running = true;
let lastHeartbeat = Date.now();

function statusXml(state) {
    return `<fraction_done>${fraction}</fraction_done>` +
           `<cpu_time>${cpuTime.toFixed(3)}</cpu_time>` +
           `<checkpoint_cpu_time>${checkpointCpuTime.toFixed(3)}</checkpoint_cpu_time>` +
           `<state>${state}</state>`;
}

const tick = setInterval(() => {
    if (!running) return;

    // 1. drain process-control requests (client -> app)
    let msg;
    while ((msg = shm.receive('CONTROL_REQ')) !== null) {
        if (msg.includes('<quit/>')) {
            shm.send('APP_STATUS', statusXml('exiting'));
            // retry the reply until the channel is free, so the ack is never lost
            while (!shm.send('CONTROL_REPLY', '<ack>quit</ack>')) {}
            running = false;
            clearInterval(tick);
            parentPort.postMessage({ type: 'exited', fraction, cpuTime });
            return;
        }
        if (msg.includes('<checkpoint/>')) {
            // simulate persisting a checkpoint (future: to OPFS) and record the cpu time of it
            checkpointCpuTime = cpuTime;
            while (!shm.send('CONTROL_REPLY', '<ack>checkpoint</ack>')) {}
        }
    }

    // 2. consume heartbeats; a BOINC app exits if the client stops heartbeating
    while ((msg = shm.receive('HEARTBEAT')) !== null) {
        if (msg.includes('<heartbeat/>')) lastHeartbeat = Date.now();
    }
    if (Date.now() - lastHeartbeat > 15000) {   // generous: tolerate background-tab throttling
        running = false;
        clearInterval(tick);
        parentPort.postMessage({ type: 'orphaned' });
        return;
    }

    // 3. paced, reliable delivery: only advance once the client has consumed the previous status,
    //    so no fraction_done step is ever dropped (robust to a slow/throttled reader).
    if (!shm.hasMsg('APP_STATUS')) {
        fraction = Math.min(1, Math.round((fraction + 0.1) * 10000) / 10000);
        cpuTime += 0.05;
        shm.send('APP_STATUS', statusXml('running'));
    }
}, 50);
