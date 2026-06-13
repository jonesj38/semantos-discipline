---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/allocator.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.980096+00:00
---

# core/cell-engine/src/allocator.zig

```zig
// Arena allocator for script execution.
// Allocate during execution, free all at once when script completes.
// No individual frees in hot paths.

pub const ScriptArena = struct {
    buffer: []u8,
    offset: usize,

    pub fn init(buffer: []u8) ScriptArena {
        return .{ .buffer = buffer, .offset = 0 };
    }

    /// Bump-allocate `size` bytes. Returns null if exhausted.
    pub fn alloc(self: *ScriptArena, size: usize) ?[]u8 {
        if (self.offset + size > self.buffer.len) return null;
        const start = self.offset;
        self.offset += size;
        return self.buffer[start..self.offset];
    }

    /// Free all allocations at once.
    pub fn reset(self: *ScriptArena) void {
        self.offset = 0;
    }

    /// Remaining capacity in bytes.
    pub fn remaining(self: *const ScriptArena) usize {
        return self.buffer.len - self.offset;
    }
};

```
