// A real BOINC *GPU* science app for the wasm client. It uses the standard libboinc_api exactly
// like a CPU app (boinc_init / boinc_resolve_filename / boinc_fraction_done / boinc_finish), but the
// crunch runs on the GPU via WebGPU: a WGSL compute shader (per-element xorshift32, iterated K times)
// dispatched from the app's Web Worker. This is the same kernel proven bit-for-bit in Spike B, so a
// correct GPU run folds to checksum 0x27a723a9 (N=1<<20, K=256) — verifiable end-to-end through the
// BOINC pipeline (scheduler -> download -> run in Worker -> upload -> report).
//
// WebGPU's API is async (requestAdapter/requestDevice/mapAsync are promises); the app is built with
// -sASYNCIFY so EM_ASYNC_JS can await them and return results to synchronous C.
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <emscripten.h>
#include "boinc_api.h"
#include "filesys.h"

// Reference kernel on the CPU (wasm), bit-identical to the WGSL shader below and to Spike B: the same
// deterministic input, the same per-element xorshift32. Used both as an in-browser CPU baseline for a
// GPU-vs-CPU benchmark and as an independent correctness check on the GPU result.
static uint32_t cpu_checksum(int n, int k) {
    uint32_t c = 0;
    for (int i = 0; i < n; i++) {
        uint32_t x = (uint32_t)((uint64_t)i * 2654435761ull + 1ull);   // Knuth multiplicative
        for (int j = 0; j < k; j++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; }
        c ^= x;
    }
    return c;
}

// Set up WebGPU: request an adapter+device, upload the deterministic input, build the compute
// pipeline. Stashes GPU state on Module.gpu. Returns 1 on success, 0 if no usable GPU.
EM_ASYNC_JS(int, wasm_gpu_init, (int n, int k), {
    if (!(typeof navigator !== 'undefined' && navigator.gpu)) return 0;
    const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!adapter) return 0;
    let info = {}; try { info = adapter.info || {}; } catch (e) {}
    const device = await adapter.requestDevice();
    const WGSL =
        '@group(0) @binding(0) var<storage, read>       inp    : array<u32>;\n' +
        '@group(0) @binding(1) var<storage, read_write> outp   : array<u32>;\n' +
        '@group(0) @binding(2) var<uniform>             params : vec2<u32>;\n' +
        '@compute @workgroup_size(64)\n' +
        'fn main(@builtin(global_invocation_id) gid : vec3<u32>) {\n' +
        '  let i = gid.x; if (i >= params.x) { return; }\n' +
        '  var x : u32 = inp[i]; let kk : u32 = params.y;\n' +
        '  for (var j : u32 = 0u; j < kk; j = j + 1u) {\n' +
        '    x = x ^ (x << 13u); x = x ^ (x >> 17u); x = x ^ (x << 5u);\n' +
        '  }\n' +
        '  outp[i] = x;\n' +
        '}';
    const input = new Uint32Array(n);
    for (let i = 0; i < n; i++) input[i] = ((i * 2654435761) + 1) >>> 0;   // Knuth multiplicative
    const bytes = n * 4;
    const inBuf  = device.createBuffer({ size: bytes, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
    const outBuf = device.createBuffer({ size: bytes, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC });
    const rdBuf  = device.createBuffer({ size: bytes, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });
    const parBuf = device.createBuffer({ size: 16, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
    device.queue.writeBuffer(inBuf, 0, input);
    device.queue.writeBuffer(parBuf, 0, new Uint32Array([n, k, 0, 0]));
    const mod = device.createShaderModule({ code: WGSL });
    const pipeline = device.createComputePipeline({ layout: 'auto', compute: { module: mod, entryPoint: 'main' } });
    const bind = device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [
        { binding: 0, resource: { buffer: inBuf } },
        { binding: 1, resource: { buffer: outBuf } },
        { binding: 2, resource: { buffer: parBuf } } ] });
    Module.gpu = { device, inBuf, outBuf, rdBuf, parBuf, pipeline, bind, n, bytes,
                   info: [info.vendor||"?", info.architecture||"?", info.device||"?"].join('/') };
    return 1;
});

// One compute dispatch (one full pass over all n elements). Idempotent: re-running overwrites outBuf
// with the same result, so the checksum is stable regardless of how many rounds we run.
EM_ASYNC_JS(void, wasm_gpu_dispatch, (), {
    const g = Module.gpu;
    const enc = g.device.createCommandEncoder();
    const pass = enc.beginComputePass();
    pass.setPipeline(g.pipeline); pass.setBindGroup(0, g.bind);
    pass.dispatchWorkgroups(Math.ceil(g.n / 64)); pass.end();
    g.device.queue.submit([enc.finish()]);
    await g.device.queue.onSubmittedWorkDone();
});

// Copy the GPU output back and fold it to a single u32 checksum.
EM_ASYNC_JS(unsigned int, wasm_gpu_readback, (), {
    const g = Module.gpu;
    const enc = g.device.createCommandEncoder();
    enc.copyBufferToBuffer(g.outBuf, 0, g.rdBuf, 0, g.bytes);
    g.device.queue.submit([enc.finish()]);
    await g.rdBuf.mapAsync(GPUMapMode.READ);
    const out = new Uint32Array(g.rdBuf.getMappedRange().slice(0));
    g.rdBuf.unmap();
    let c = 0; for (let i = 0; i < out.length; i++) c = (c ^ out[i]) >>> 0;
    return c >>> 0;
});

// Copy the adapter description (vendor/arch/device) into a C buffer for logging + the result file.
EM_JS(void, wasm_gpu_info, (char* buf, int len), {
    const s = (Module.gpu && Module.gpu.info) || 'unknown';
    stringToUTF8(s, buf, len);
});

int main() {
    int retval = boinc_init();
    if (retval) { fprintf(stderr, "gpu_app: boinc_init failed: %d\n", retval); return retval; }

    const int N = 1 << 20;   // 1,048,576 elements
    const int K = 256;       // xorshift iterations per element

    boinc_fraction_done(0.0);
    if (!wasm_gpu_init(N, K)) {
        fprintf(stderr, "gpu_app: no usable WebGPU adapter\n");
        char out_path[512];
        boinc_resolve_filename("out", out_path, sizeof(out_path));
        FILE* f = boinc_fopen(out_path, "w");
        if (f) { fprintf(f, "webgpu result: NO GPU AVAILABLE\n"); fclose(f); }
        boinc_finish(1);
        return 1;
    }

    char info[256] = {0};
    wasm_gpu_info(info, sizeof(info));
    fprintf(stderr, "gpu_app: WebGPU adapter = %s\n", info);

    // GPU: run many dispatches so the run is substantial and progress is visible. Each dispatch is a
    // full pass over all N elements; re-running is idempotent, so the checksum is stable. The loop
    // wall-time is the GPU compute time (each dispatch awaits onSubmittedWorkDone).
    const int REP = 64;
    double gpu_t0 = emscripten_get_now();
    for (int r = 0; r < REP; r++) {
        wasm_gpu_dispatch();
        boinc_fraction_done((double)(r + 1) / REP);
    }
    unsigned int gpu_cksum = wasm_gpu_readback();
    double gpu_ms = emscripten_get_now() - gpu_t0;

    // CPU (wasm) baseline: one pass over all N elements, for a same-environment GPU-vs-CPU comparison
    // and an independent check that the GPU produced the correct bits.
    double cpu_t0 = emscripten_get_now();
    unsigned int cpu_cksum = cpu_checksum(N, K);
    double cpu_ms = emscripten_get_now() - cpu_t0;

    double gpu_rate = (double)REP * N * K / 1e6 / (gpu_ms / 1000.0);   // M kernel-iters/s
    double cpu_rate = (double)N * K / 1e6 / (cpu_ms / 1000.0);
    bool match = (gpu_cksum == cpu_cksum);
    fprintf(stderr, "gpu_app: GPU 0x%08x (%.0f Mi/s), CPU 0x%08x (%.0f Mi/s), match=%d\n",
        gpu_cksum, gpu_rate, cpu_cksum, cpu_rate, match);

    char out_path[512];
    boinc_resolve_filename("out", out_path, sizeof(out_path));
    FILE* f = boinc_fopen(out_path, "w");
    if (f) {
        fprintf(f, "webgpu result: checksum=0x%08x\n", gpu_cksum);
        fprintf(f, "kernel: xorshift32 N=%d K=%d REP=%d\n", N, K, REP);
        fprintf(f, "adapter: %s\n", info);
        fprintf(f, "correctness: GPU==CPU bit-for-bit = %s (cpu=0x%08x)\n", match ? "YES" : "NO", cpu_cksum);
        fprintf(f, "benchmark: GPU %.0f M-iter/s vs CPU(wasm) %.0f M-iter/s = %.1fx\n",
            gpu_rate, cpu_rate, gpu_rate / cpu_rate);
        fclose(f);
    }

    boinc_finish(match ? 0 : 1);   // fail the task if the GPU result is wrong. does not return
    return 0;
}
