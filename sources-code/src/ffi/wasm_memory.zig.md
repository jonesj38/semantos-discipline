---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/wasm_memory.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.403773+00:00
---

# src/ffi/wasm_memory.zig

```zig
// Semantos FFI — WASM Memory Helpers
// Phase 30E: Host-side memory management for WASM linear memory.
//
// These exported functions let the host allocate and free buffers in WASM
// linear memory. The copy-in/copy-out pattern:
//   1. Host calls semantos_alloc(size) → gets pointer in WASM memory
//   2. Host writes data to that pointer via memory view
//   3. Host calls a kernel function with the pointer
//   4. Host reads result from WASM memory
//   5. Host calls semantos_dealloc(ptr, size) to free

const std = @import("std");
const builtin = @import("builtin");

/// The allocator used for WASM memory management.
/// On wasm32 targets, uses the WASM-specific allocator that grows linear memory.
/// On native targets (for testing), falls back to page_allocator.
const wasm_alloc = if (builtin.target.cpu.arch == .wasm32)
    std.heap.wasm_allocator
else
    std.heap.page_allocator;

/// Allocate `size` bytes in WASM linear memory.
/// Returns a pointer to the allocated buffer, or null on failure.
/// The host must call semantos_dealloc to free this memory.
pub export fn semantos_alloc(size: usize) callconv(.c) ?[*]u8 {
    if (size == 0) return null;
    const slice = wasm_alloc.alloc(u8, size) catch return null;
    return slice.ptr;
}

/// Free a buffer previously allocated by semantos_alloc.
/// No-op if ptr is null or size is zero.
pub export fn semantos_dealloc(ptr: ?[*]u8, size: usize) callconv(.c) void {
    if (ptr == null or size == 0) return;
    const p = ptr.?;
    // On WASM, wasm_allocator tracks allocations. On native, page_allocator
    // requires page-aligned pointers. We use @alignCast only when safe.
    if (builtin.target.cpu.arch == .wasm32) {
        wasm_alloc.free(p[0..size]);
    } else {
        // Native fallback: only free page-aligned pointers
        const addr = @intFromPtr(p);
        if (addr % std.heap.page_size_min == 0) {
            const aligned: [*]align(std.heap.page_size_min) u8 = @alignCast(p);
            std.heap.page_allocator.free(aligned[0..size]);
        }
    }
}

```
