---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/region_tick_producer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.264032+00:00
---

# runtime/semantos-brain/src/region_tick_producer.zig

```zig
// M3.3 — RegionTickProducer: 20 Hz region tick stream producer.
//
// The World Host calls maybeTick() from its event loop every poll cycle
// (~10 ms).  maybeTick gates on interval_ms (default 50 ms = 20 Hz) so
// only one event is emitted per interval regardless of how often it is called.
//
// Each tick carries the Merkle root hash of the region state at emission time.
// The Merkle root is 32 bytes (SHA-256) encoded as 64-char lowercase hex.
//
// Event format (application/json):
//   {
//     "region_id": "<region_id>",
//     "tick":      <tick_count>,
//     "ts_ms":     <now_ms>,
//     "merkle_root": "<64-char lowercase hex>"
//   }
//
// Routing key: region_id (passed to PravegatClient.writeEvent).

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;

pub const RegionTickProducer = struct {
    allocator: std.mem.Allocator,
    client: *PravegatClient,
    /// Stream name, e.g. "region-ticks". Caller owns; must outlive producer.
    stream: []const u8,
    /// Region identifier, e.g. "world-0". Caller owns; must outlive producer.
    region_id: []const u8,
    /// Tick interval in milliseconds (50 ms → 20 Hz).
    interval_ms: u64,
    /// Number of ticks emitted so far. Starts at 0.
    tick_count: u64,
    /// Timestamp (ms since epoch) of the last emitted tick. Starts at 0.
    last_tick_ms: u64,

    /// Initialise a RegionTickProducer.
    /// `client`, `stream`, and `region_id` must outlive the producer.
    pub fn init(
        allocator: std.mem.Allocator,
        client: *PravegatClient,
        stream: []const u8,
        region_id: []const u8,
        interval_ms: u64,
    ) RegionTickProducer {
        return RegionTickProducer{
            .allocator = allocator,
            .client = client,
            .stream = stream,
            .region_id = region_id,
            .interval_ms = interval_ms,
            .tick_count = 0,
            .last_tick_ms = 0,
        };
    }

    /// Release any resources held by this producer.
    /// Currently a no-op (no heap-allocated members); present for symmetry and
    /// forward compatibility.
    pub fn deinit(self: *RegionTickProducer) void {
        _ = self;
    }

    /// Call from the event loop on every poll cycle.
    /// Emits one tick event to the Pravega stream if `interval_ms` has elapsed
    /// since the last emission.
    ///
    /// `now_ms`      — current wall-clock time in milliseconds (monotonic or POSIX).
    /// `merkle_root` — 32-byte SHA-256 of the current region state.
    pub fn maybeTick(
        self: *RegionTickProducer,
        now_ms: u64,
        merkle_root: *const [32]u8,
    ) !void {
        // Gate: only fire if at least interval_ms has elapsed since last tick.
        if (now_ms < self.last_tick_ms + self.interval_ms) {
            return; // too soon — do nothing
        }

        const payload = try self.buildTickPayload(self.allocator, now_ms, merkle_root);
        defer self.allocator.free(payload);

        try self.client.writeEvent(self.stream, self.region_id, payload);

        self.tick_count += 1;
        self.last_tick_ms = now_ms;
    }

    /// Build the tick JSON payload. Caller must free the returned slice with `allocator`.
    pub fn buildTickPayload(
        self: *RegionTickProducer,
        allocator: std.mem.Allocator,
        now_ms: u64,
        merkle_root: *const [32]u8,
    ) ![]u8 {
        // Encode merkle_root as 64-char lowercase hex.
        const hex_buf = std.fmt.bytesToHex(merkle_root.*, .lower);

        return std.fmt.allocPrint(
            allocator,
            "{{\"region_id\":\"{s}\",\"tick\":{d},\"ts_ms\":{d},\"merkle_root\":\"{s}\"}}",
            .{ self.region_id, self.tick_count, now_ms, hex_buf },
        );
    }
};

```
