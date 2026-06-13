---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/pask_replay_tool.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.262894+00:00
---

# runtime/semantos-brain/src/pask_replay_tool.zig

```zig
// M3.10 — PaskReplayTool: Pravega stream replay → Pask snapshot derivation.
//
// Subscribes to the `pask-interactions` Pravega stream from genesis,
// replays all events through an in-process Pask Store (not WASM), and
// returns a snapshot byte-identical to the live pask_snapshot_state.
//
// This validates the Pask kernel's determinism property: replaying the same
// ordered event log always produces the same snapshot.
//
// Snapshot format (matches pask/src/main.zig):
//   [u32 magic   = 0x4B534150 "PASK" little-endian]
//   [u32 version = 1]
//   [u32 length  = @sizeOf(Store)]
//   [length bytes of Store image]

const std = @import("std");
const pravega_subscriber = @import("pravega_subscriber");
const pask_store = @import("pask_store");
const pask_config = @import("pask_config");
const pask_types = @import("pask_types");
const pask_propagation = @import("pask_propagation");
const pask_stability = @import("pask_stability");
const pask_pruner = @import("pask_pruner");

const PravegatSubscriber = pravega_subscriber.PravegatSubscriber;
const Store = pask_store.Store;
const Affected = pask_propagation.Affected;

const SNAPSHOT_MAGIC: u32 = 0x4B534150;
const SNAPSHOT_VERSION: u32 = 1;
const SNAPSHOT_HEADER_SIZE: usize = 12;

pub const ReplayResult = struct {
    events_processed: u64,
    /// Snapshot bytes: 12-byte header + Store image. Owned by caller (allocator.free).
    snapshot: []u8,
};

pub const PaskReplayTool = struct {
    allocator: std.mem.Allocator,
    subscriber: *PravegatSubscriber,

    pub fn init(allocator: std.mem.Allocator, subscriber: *PravegatSubscriber) PaskReplayTool {
        return .{
            .allocator = allocator,
            .subscriber = subscriber,
        };
    }

    /// No-op — we hold no owned resources beyond what the caller passed in.
    pub fn deinit(self: *PaskReplayTool) void {
        _ = self;
    }

    /// Replay all events from the named Pravega stream.
    ///
    /// 1. Opens a fresh subscription (createReaderGroup + createReader).
    /// 2. Initialises an in-memory Pask Store.
    /// 3. Reads events until readNext returns null (end-of-stream).
    /// 4. Applies each event to the store.
    /// 5. Produces a snapshot and returns it.
    ///
    /// The returned ReplayResult.snapshot slice is owned by the caller and
    /// must be freed via allocator.free(result.snapshot).
    pub fn replayFromGenesis(
        self: *PaskReplayTool,
        stream_name: []const u8,
    ) !ReplayResult {
        // 1. Subscribe.
        var handle = try self.subscriber.subscribe(stream_name);
        defer handle.deinit();

        // 2. Initialise a fresh Store.
        var store: Store = undefined;
        store.init(pask_config.DEFAULT);

        var affected: Affected = undefined;
        affected.init();

        var interaction_tick: u64 = 0;
        var events_processed: u64 = 0;

        // 3. Read until end of stream.
        while (true) {
            const maybe_event = try self.subscriber.readNext(&handle);
            if (maybe_event == null) break;
            const event_json = maybe_event.?;
            defer self.allocator.free(event_json);

            // 4. Parse and apply.
            try applyEvent(self.allocator, &store, &affected, event_json, &interaction_tick);
            events_processed += 1;
        }

        // 5. Produce snapshot.
        const snapshot = try buildSnapshot(self.allocator, &store);
        return ReplayResult{
            .events_processed = events_processed,
            .snapshot = snapshot,
        };
    }
};

// ── Event parsing ────────────────────────────────────────────────────────────

/// Apply a single JSON event (from the pask-interactions stream) to the store.
/// Mirrors the pask_interact_run export logic in core/pask/src/main.zig.
fn applyEvent(
    alloc: std.mem.Allocator,
    store: *Store,
    affected: *Affected,
    json: []const u8,
    interaction_tick: *u64,
) !void {
    // Parse with std.json — we need: primary_cell_id, related_cell_ids[],
    // effective_strength, now_ms. The seq field is read but not used for
    // store mutations (the kernel does not store seq).
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json, .{});
    defer parsed.deinit();

    const root = parsed.value.object;

    const primary_cell_id = root.get("primary_cell_id").?.string;

    const effective_strength: f64 = switch (root.get("effective_strength").?) {
        .float => |f| f,
        .integer => |n| @floatFromInt(n),
        else => return error.InvalidStrength,
    };

    const now_ms: u64 = switch (root.get("now_ms").?) {
        .integer => |n| @intCast(n),
        else => return error.InvalidNowMs,
    };

    if (!std.math.isFinite(effective_strength)) return error.InvalidStrength;

    // Upsert primary node (type_path = empty string, matching WASM kernel).
    const primary_idx = try store.upsertNode(primary_cell_id, "", now_ms);

    // Reset affected set for this interaction.
    affected.init();
    _ = try affected.add(primary_idx);

    // Process related cells: upsert nodes, create edges, update weights.
    const related_arr = root.get("related_cell_ids").?.array;
    for (related_arr.items) |item| {
        const related_id = item.string;
        const related_idx = try store.upsertNode(related_id, "", now_ms);
        const edge_idx = try store.upsertEdge(primary_idx, related_idx, now_ms);
        const weight_delta = effective_strength * store.cfg.learning_rate;
        store.updateEdgeWeight(edge_idx, weight_delta, now_ms);
        store.recordDelta(edge_idx, weight_delta, now_ms);
        _ = try affected.add(related_idx);
    }

    // Update primary node state.
    store.updateNodeState(primary_idx, effective_strength, now_ms);

    // Propagation (k iterations of localUpdate + expandRegion).
    try pask_propagation.propagate(store, affected, now_ms);

    interaction_tick.* += 1;

    // Stability check (every N ticks, matching pask_interact_run).
    if (store.cfg.stability_check_every > 0 and
        interaction_tick.* % store.cfg.stability_check_every == 0)
    {
        var i: u32 = 0;
        while (i < affected.count) : (i += 1) {
            _ = pask_stability.checkNode(store, affected.members[i], now_ms);
        }
    }

    // Prune (every N ticks, matching pask_interact_run).
    if (store.cfg.prune_every > 0 and
        interaction_tick.* % store.cfg.prune_every == 0)
    {
        _ = pask_pruner.pruneOnce(store, now_ms);
    }
}

// ── Snapshot builder ─────────────────────────────────────────────────────────

fn buildSnapshot(alloc: std.mem.Allocator, store: *const Store) ![]u8 {
    const store_size: u32 = @intCast(@sizeOf(Store));
    const total = SNAPSHOT_HEADER_SIZE + store_size;
    const buf = try alloc.alloc(u8, total);

    std.mem.writeInt(u32, buf[0..4], SNAPSHOT_MAGIC, .little);
    std.mem.writeInt(u32, buf[4..8], SNAPSHOT_VERSION, .little);
    std.mem.writeInt(u32, buf[8..12], store_size, .little);

    const store_bytes = std.mem.asBytes(store);
    @memcpy(buf[SNAPSHOT_HEADER_SIZE..][0..store_bytes.len], store_bytes);
    return buf;
}

```
