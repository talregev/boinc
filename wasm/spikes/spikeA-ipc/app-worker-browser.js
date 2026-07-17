'use strict';
// Spike A — browser Web Worker version of the science app (mirror of app-worker.js for Node).
// Receives the shared SharedArrayBuffer via postMessage, then talks to the client only through
// the APP_CLIENT_SHM channels. Requires the page to be cross-origin isolated (COOP/COEP) so that
// SharedArrayBuffer is available.
importScripts('shm.js');
const { Shm } = self.SpikeShm;

let shm, fraction = 0, cpuTime = 0, checkpointCpuTime = 0, running = true, lastHeartbeat = 0, tick = 0;

function statusXml(state) {
    return `<fraction_done>${fraction}</fraction_done>` +
           `<cpu_time>${cpuTime.toFixed(3)}</cpu_time>` +
           `<checkpoint_cpu_time>${checkpointCpuTime.toFixed(3)}</checkpoint_cpu_time>` +
           `<state>${state}</state>`;
}

self.onmessage = (e) => {
    if (e.data && e.data.sab) {
        shm = new Shm(e.data.sab);
        lastHeartbeat = Date.now();
        tick = setInterval(loop, 50);
    }
};

function loop() {
    if (!running) return;
    let msg;
    while ((msg = shm.receive('CONTROL_REQ')) !== null) {
        if (msg.includes('<quit/>')) {
            shm.send('APP_STATUS', statusXml('exiting'));
            while (!shm.send('CONTROL_REPLY', '<ack>quit</ack>')) {}
            running = false; clearInterval(tick);
            self.postMessage({ type: 'exited', fraction, cpuTime });
            return;
        }
        if (msg.includes('<checkpoint/>')) {
            checkpointCpuTime = cpuTime;
            while (!shm.send('CONTROL_REPLY', '<ack>checkpoint</ack>')) {}
        }
    }
    while ((msg = shm.receive('HEARTBEAT')) !== null) {
        if (msg.includes('<heartbeat/>')) lastHeartbeat = Date.now();
    }
    if (Date.now() - lastHeartbeat > 2000) {
        running = false; clearInterval(tick);
        self.postMessage({ type: 'orphaned' });
        return;
    }
    fraction = Math.min(1, Math.round((fraction + 0.1) * 10000) / 10000);
    cpuTime += 0.05;
    shm.send('APP_STATUS', statusXml('running'));
}
