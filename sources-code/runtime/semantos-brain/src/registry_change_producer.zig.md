---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/registry_change_producer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.212798+00:00
---

# runtime/semantos-brain/src/registry_change_producer.zig

```zig
// M6.3 — RegistryChangeProducer: emit octave_registry mutations to Pravega.
//
// Every insert/update to `octave_registry` emits a JSON event to the
// `registry-changes` Pravega stream via PravegatClient.writeEvent.
// Events are routed by the first 4 hex chars of cell_id.
//
// Wire format (JSON):
//   {
//     "kind":         "insert"|"update"|"state_change",
//     "cell_id":      "<hex>",
//     "domain_flag":  <u32>,
//     "new_state":    "<state>",
//     "octave_level": <0|1|2>,
//     "ts_ms":        <u64>,
//     "seq":          <u64>
//   }
//
// Routing key: first 4 hex chars of cell_id_hex (e.g. "ab12").
// seq is incremented only after a successful writeEvent.

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;

pub const ChangeKind = enum {
    insert,
    update,
    state_change,

    pub fn wireName(self: ChangeKind) []const u8 {
        return switch (self) {
            .insert => "insert",
            .update => "update",
            .state_change => "state_change",
        };
    }
};

pub const RegistryChangeProducer = struct {
    allocator: std.mem.Allocator,
    /// Non-owning pointer — caller keeps PravegatClient alive.
    client: *PravegatClient,
    /// Pravega stream name (e.g. "registry-changes"). Not owned.
    stream: []const u8,
    /// Monotonic sequence; starts at 0. Incremented after successful writeEvent.
    seq: u64,

    /// Initialise. `client` and `stream` must outlive the producer.
    pub fn init(
        allocator: std.mem.Allocator,
        client: *PravegatClient,
        stream: []const u8,
    ) RegistryChangeProducer {
        return .{
            .allocator = allocator,
            .client = client,
            .stream = stream,
            .seq = 0,
        };
    }

    /// No-op — no owned heap allocations.
    pub fn deinit(self: *RegistryChangeProducer) void {
        _ = self;
    }

    /// Emit a registry change event.
    /// `cell_id_hex`: hex encoding of the 32-byte cell_id (64 chars).
    /// Routing key = first 4 hex chars of cell_id_hex.
    /// seq is incremented only after a successful writeEvent.
    pub fn emitChange(
        self: *RegistryChangeProducer,
        kind: ChangeKind,
        cell_id_hex: []const u8,
        domain_flag: u32,
        new_state: []const u8,
        octave_level: u8,
        ts_ms: u64,
    ) !void {
        // Build payload using current seq without consuming it via buildPayload.
        const payload = try self.buildPayloadRaw(kind, cell_id_hex, domain_flag, new_state, octave_level, ts_ms, self.seq);
        defer self.allocator.free(payload);

        // Routing key = first 4 hex chars of cell_id.
        const routing_key = if (cell_id_hex.len >= 4) cell_id_hex[0..4] else cell_id_hex;

        try self.client.writeEvent(self.stream, routing_key, payload);
        self.seq += 1;
    }

    /// Build JSON payload without emitting. Caller must free.
    /// seq field = current self.seq (before increment).
    /// Increments self.seq so repeated calls yield seq 0, 1, 2, ...
    pub fn buildPayload(
        self: *RegistryChangeProducer,
        kind: ChangeKind,
        cell_id_hex: []const u8,
        domain_flag: u32,
        new_state: []const u8,
        octave_level: u8,
        ts_ms: u64,
    ) ![]u8 {
        const current_seq = self.seq;
        self.seq += 1;
        return self.buildPayloadRaw(kind, cell_id_hex, domain_flag, new_state, octave_level, ts_ms, current_seq);
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    fn buildPayloadRaw(
        self: *RegistryChangeProducer,
        kind: ChangeKind,
        cell_id_hex: []const u8,
        domain_flag: u32,
        new_state: []const u8,
        octave_level: u8,
        ts_ms: u64,
        seq: u64,
    ) ![]u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "{{\"kind\":\"{s}\",\"cell_id\":\"{s}\",\"domain_flag\":{d},\"new_state\":\"{s}\",\"octave_level\":{d},\"ts_ms\":{d},\"seq\":{d}}}",
            .{
                kind.wireName(),
                cell_id_hex,
                domain_flag,
                new_state,
                octave_level,
                ts_ms,
                seq,
            },
        );
    }
};

```
