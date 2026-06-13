---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/pask_interaction_producer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.253143+00:00
---

# runtime/semantos-brain/src/pask_interaction_producer.zig

```zig
// M3.9 — PaskInteractionProducer: emits pask_interact_run observations to
// the `pask-interactions` Pravega stream via PravegatClient.writeEvent.
//
// Event JSON schema:
//   {
//     "kind": "pask_interaction",
//     "primary_cell_id": "<64-hex-char>",
//     "related_cell_ids": ["<64-hex>", ...],
//     "effective_strength": <f64>,
//     "now_ms": <u64>,
//     "seq": <u64>
//   }
//
// Routing key = hex(primary_cell_id[0..8]) — first 16 hex chars of the
// primary cell's 32-byte hash (preserves per-primary ordering in Pravega).
//
// Usage:
//   var producer = PaskInteractionProducer.init(alloc, &client, "pask-interactions");
//   defer producer.deinit();
//   try producer.emitInteraction(&primary_cell_id, related_ids, strength, now_ms);

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;

pub const PaskInteractionProducer = struct {
    allocator: std.mem.Allocator,
    /// Non-owning pointer — caller keeps PravegatClient alive.
    client: *PravegatClient,
    /// Pravega stream name (e.g. "pask-interactions"). Not owned.
    stream: []const u8,
    /// Monotonically-increasing event sequence counter; starts at 0.
    sequence: u64,

    /// Initialise the producer. Does not connect.
    pub fn init(
        allocator: std.mem.Allocator,
        client: *PravegatClient,
        stream: []const u8,
    ) PaskInteractionProducer {
        return .{
            .allocator = allocator,
            .client = client,
            .stream = stream,
            .sequence = 0,
        };
    }

    /// No heap allocations held by the producer itself.
    pub fn deinit(self: *PaskInteractionProducer) void {
        _ = self;
    }

    // ─── Public API ──────────────────────────────────────────────────────────

    /// Call after each pask_interact_run to emit the interaction event.
    ///
    /// primary_cell_id   — 32-byte cell hash identifying the primary node.
    /// related_cell_ids  — slice of 32-byte hashes for related nodes.
    /// effective_strength — the float strength value passed to pask_interact_run.
    /// now_ms            — millisecond timestamp.
    ///
    /// Routing key = first 16 hex chars of primary_cell_id.
    pub fn emitInteraction(
        self: *PaskInteractionProducer,
        primary_cell_id: *const [32]u8,
        related_cell_ids: []const [32]u8,
        effective_strength: f64,
        now_ms: u64,
    ) !void {
        const payload = try self.buildPayload(
            primary_cell_id,
            related_cell_ids,
            effective_strength,
            now_ms,
        );
        defer self.allocator.free(payload);

        // Routing key = first 16 hex chars of primary_cell_id.
        const routing_key = routingKey(primary_cell_id);

        try self.client.writeEvent(self.stream, &routing_key, payload);
    }

    /// Build the event JSON payload without emitting. Increments sequence.
    /// Caller must free the returned slice with `producer.allocator`.
    pub fn buildPayload(
        self: *PaskInteractionProducer,
        primary_cell_id: *const [32]u8,
        related_cell_ids: []const [32]u8,
        effective_strength: f64,
        now_ms: u64,
    ) ![]u8 {
        const seq = self.sequence;
        self.sequence += 1;

        // Encode primary_cell_id as 64 lowercase hex chars.
        const primary_hex = std.fmt.bytesToHex(primary_cell_id.*, .lower);

        // Build the related_cell_ids JSON array.
        // Each entry is 64 hex chars + surrounding quotes + optional comma.
        // Worst case: n * (2 + 64 + 1) + 2 brackets = n*67 + 2.
        const related_arr = try buildRelatedArray(self.allocator, related_cell_ids);
        defer self.allocator.free(related_arr);

        return std.fmt.allocPrint(
            self.allocator,
            "{{\"kind\":\"pask_interaction\",\"primary_cell_id\":\"{s}\",\"related_cell_ids\":{s},\"effective_strength\":{d},\"now_ms\":{d},\"seq\":{d}}}",
            .{
                primary_hex,
                related_arr,
                effective_strength,
                now_ms,
                seq,
            },
        );
    }

    // ─── Internal helpers ────────────────────────────────────────────────────

    /// Build a JSON array string for the related_cell_ids slice.
    /// Returns a heap-allocated string; caller must free.
    fn buildRelatedArray(
        allocator: std.mem.Allocator,
        related: []const [32]u8,
    ) ![]u8 {
        if (related.len == 0) {
            return allocator.dupe(u8, "[]");
        }

        // Each entry: `"<64 hex chars>"` (68 chars) + `,` between entries.
        // Total = 2 (brackets) + n * 66 (quoted hex) + (n-1) commas.
        // In Zig 0.15 the allocator is passed to each ArrayList method.
        var list: std.ArrayList(u8) = .{};
        errdefer list.deinit(allocator);

        try list.append(allocator, '[');
        for (related, 0..) |cell_id, i| {
            if (i > 0) try list.append(allocator, ',');
            try list.append(allocator, '"');
            const hex = std.fmt.bytesToHex(cell_id, .lower);
            try list.appendSlice(allocator, &hex);
            try list.append(allocator, '"');
        }
        try list.append(allocator, ']');

        return list.toOwnedSlice(allocator);
    }

    /// Compute the 16-char routing key (hex of first 8 bytes of cell id).
    fn routingKey(cell_id: *const [32]u8) [16]u8 {
        const prefix: *const [8]u8 = cell_id[0..8];
        return std.fmt.bytesToHex(prefix.*, .lower);
    }
};

```
