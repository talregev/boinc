// Spike A — faithful emulation of BOINC's APP_CLIENT_SHM (see lib/app_ipc.h / lib/shmem.cpp)
// over a SharedArrayBuffer, to prove the browser process/IPC model can replace SysV shared memory.
//
// Native BOINC: client <-> app communicate through APP_CLIENT_SHM, an array of MSG_CHANNELs.
// Each MSG_CHANNEL is a fixed byte buffer where buf[0] != 0 means "a message is present";
// the writer refuses to overwrite an unread message (send_msg), the reader copies the string
// then sets buf[0] = 0 (get_msg). fork()+SysV-shmem give the cross-process shared memory.
//
// Browser mapping (this file): ONE SharedArrayBuffer, one fixed region per channel:
//     [ Int32 flag | Int32 len | payload bytes (UTF-8, up to PAYLOAD_CAP) ]
// Atomics on `flag` provide the happens-before ordering that SysV shmem gave us natively.
// This is exactly what a wasm client (main thread) and a wasm science app (Web Worker) would use.
//
// UMD: usable from Node (require('./shm')) and the browser (<script>/importScripts -> self.SpikeShm).
(function (root, factory) {
    if (typeof module !== 'undefined' && module.exports) module.exports = factory();
    else root.SpikeShm = factory();
})(typeof self !== 'undefined' ? self : this, function () {
    'use strict';

    const CHANNELS = ['CONTROL_REQ', 'CONTROL_REPLY', 'APP_STATUS', 'HEARTBEAT'];
    const PAYLOAD_CAP = 1016;                    // keep each channel at 1024 B, like BOINC MSG_CHANNEL_SIZE
    const HEADER_I32 = 2;                         // flag(4) + len(4)
    const CHANNEL_BYTES = HEADER_I32 * 4 + PAYLOAD_CAP;   // 1024
    const FLAG = 0, LEN = 1;                      // Int32 offsets within a channel

    const Enc = typeof TextEncoder !== 'undefined' ? TextEncoder : require('util').TextEncoder;
    const Dec = typeof TextDecoder !== 'undefined' ? TextDecoder : require('util').TextDecoder;

    function makeSAB() {
        return new SharedArrayBuffer(CHANNELS.length * CHANNEL_BYTES);
    }

    class Shm {
        constructor(sab) {
            this.sab = sab;
            this.bytes = new Uint8Array(sab);
            this.i32 = new Int32Array(sab);
            this.enc = new Enc();
            this.dec = new Dec();
        }
        _byteBase(ch) {
            const idx = CHANNELS.indexOf(ch);
            if (idx < 0) throw new Error('unknown channel: ' + ch);
            return idx * CHANNEL_BYTES;
        }
        _i32Base(ch) { return this._byteBase(ch) / 4; }

        hasMsg(ch) { return Atomics.load(this.i32, this._i32Base(ch) + FLAG) === 1; }

        // returns false if the channel still holds an unread message (matches MSG_CHANNEL::send_msg)
        send(ch, str) {
            const ib = this._i32Base(ch);
            if (Atomics.load(this.i32, ib + FLAG) === 1) return false;
            const buf = this.enc.encode(str);
            if (buf.length > PAYLOAD_CAP) throw new Error('message too large for channel');
            this.bytes.set(buf, this._byteBase(ch) + HEADER_I32 * 4);
            Atomics.store(this.i32, ib + LEN, buf.length);
            Atomics.store(this.i32, ib + FLAG, 1);     // publish flag last (reader sees len first)
            Atomics.notify(this.i32, ib + FLAG);
            return true;
        }

        // returns the message string, or null if the channel is empty (matches MSG_CHANNEL::get_msg)
        receive(ch) {
            const ib = this._i32Base(ch);
            if (Atomics.load(this.i32, ib + FLAG) !== 1) return null;
            const len = Atomics.load(this.i32, ib + LEN);
            const start = this._byteBase(ch) + HEADER_I32 * 4;
            const str = this.dec.decode(this.bytes.slice(start, start + len));
            Atomics.store(this.i32, ib + FLAG, 0);     // consume
            return str;
        }
    }

    return { CHANNELS, makeSAB, Shm };
});
