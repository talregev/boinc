// Spike B — WebGPU compute shader (WGSL). Must stay bit-for-bit identical to kernel.js `step()`.
// One invocation per element: xorshift32 iterated params.y times. u32 arithmetic wraps mod 2^32,
// matching JS 32-bit bitwise ops, so the GPU output equals the CPU reference exactly.

@group(0) @binding(0) var<storage, read>       inp    : array<u32>;
@group(0) @binding(1) var<storage, read_write> outp   : array<u32>;
@group(0) @binding(2) var<uniform>             params : vec2<u32>;   // x = count, y = iterations

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
    let i = gid.x;
    if (i >= params.x) { return; }

    var x : u32 = inp[i];
    let k : u32 = params.y;
    for (var j : u32 = 0u; j < k; j = j + 1u) {
        x = x ^ (x << 13u);
        x = x ^ (x >> 17u);
        x = x ^ (x << 5u);
    }
    outp[i] = x;
}
