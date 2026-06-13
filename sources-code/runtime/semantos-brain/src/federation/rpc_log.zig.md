---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/federation/rpc_log.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.283345+00:00
---

# runtime/semantos-brain/src/federation/rpc_log.zig

```zig
// M7.2/M7.3 — RpcLog: in-memory ring buffer of remote-routed call stubs.
//
// The actual network transport is out of scope for M7.2/M7.3.  RpcLog
// records every operation that would have been sent to a remote peer so
// that tests can assert on routing logic without a real network.

pub const RpcEntry = struct {
    pub const Op = enum(u8) {
        write_output,
        read_output,
        write_header,
        read_header,
        rollback,
        write_state,
        read_state,
    };

    op: Op,
    slot: u32,
    peer_id: [32]u8,
};

pub const RpcLog = struct {
    entries: [1024]RpcEntry,
    count: usize,

    pub fn init() RpcLog {
        return .{
            .entries = undefined,
            .count = 0,
        };
    }

    /// Append an entry.  If the ring is full, drop the oldest entry (shift
    /// everything down by one, losing entries[0]).
    pub fn append(self: *RpcLog, entry: RpcEntry) void {
        if (self.count < 1024) {
            self.entries[self.count] = entry;
            self.count += 1;
        } else {
            // Ring full: drop oldest.
            var i: usize = 0;
            while (i < 1023) : (i += 1) {
                self.entries[i] = self.entries[i + 1];
            }
            self.entries[1023] = entry;
        }
    }

    /// Return the live slice of entries.
    pub fn slice(self: *const RpcLog) []const RpcEntry {
        return self.entries[0..self.count];
    }

    /// Clear all entries.
    pub fn clear(self: *RpcLog) void {
        self.count = 0;
    }
};

```
