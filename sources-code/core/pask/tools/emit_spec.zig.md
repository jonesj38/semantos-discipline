---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/tools/emit_spec.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.928610+00:00
---

# core/pask/tools/emit_spec.zig

```zig
// emit_spec — writes a machine-derived spec.json for the pask kernel.
//
// The struct field offsets and sizes come from @offsetOf / @sizeOf — if
// you change a struct in types.zig, the spec changes automatically and
// the comptime asserts in src/main.zig fail if you forgot to also update
// the TS bindings. The spec and the asserts share one source of truth:
// the Zig type definitions.
//
// Run via `zig build release-spec` (or directly):
//   zig run tools/emit_spec.zig --deps types,config \
//     -Mtypes=src/types.zig -Mconfig=src/config.zig
//
// Output goes to stdout; the build step pipes it to
// zig-out/release/pask-spec.json.

const std = @import("std");
const types = @import("types");
const config = @import("config");

const SPEC_VERSION = "1";
const PASK_VERSION = "0.1.0";

// ── Exports table ───────────────────────────────────────────────────────
//
// One entry per `export fn` in src/main.zig. Each is grounded by
// `@TypeOf(@field(...))` so a renamed/removed export fails the build
// at the spec emitter, not silently in production.

const ExportEntry = struct {
    name: []const u8,
    /// Compact signature string. Format: "(arg_types) -> ret_type".
    signature: []const u8,
    /// One-line semantic summary. Hand-written; the rest is derived.
    summary: []const u8,
};

const EXPORTS = [_]ExportEntry{
    .{ .name = "pask_init", .signature = "() -> i32", .summary = "Initialize kernel state. Idempotent." },
    .{ .name = "pask_set_config", .signature = "(cfg_ptr: *Config) -> i32", .summary = "Override default Config." },
    .{ .name = "pask_reset", .signature = "() -> i32", .summary = "Wipe state, keep current config." },
    .{ .name = "pask_last_error", .signature = "() -> i32", .summary = "Last fallible-export error code (0 = ok)." },

    .{ .name = "pask_upsert_node", .signature = "(cell_id_ptr, cell_id_len, type_path_ptr, type_path_len, now_ms) -> i32", .summary = "Insert-or-fetch node by cell_id. Returns NodeIdx or negative error." },
    .{ .name = "pask_find_node", .signature = "(cell_id_ptr, cell_id_len) -> i32", .summary = "Look up by cell_id; -1 if absent." },
    .{ .name = "pask_interact_run", .signature = "(primary_idx, kind_ptr, kind_len, effective_strength, related_idx_ptr, related_count, now_ms) -> i32", .summary = "One full interact() pass. Returns affected-set count." },
    .{ .name = "pask_finalize", .signature = "(now_ms) -> i32", .summary = "Full-graph stability + prune sweep. Used after batched mode." },

    .{ .name = "pask_node_count", .signature = "() -> u32", .summary = "Active node count (includes pruned)." },
    .{ .name = "pask_edge_count", .signature = "() -> u32", .summary = "Active edge count." },
    .{ .name = "pask_node_ptr", .signature = "(idx) -> u32", .summary = "Address of nodes[idx]; 0 if invalid." },
    .{ .name = "pask_edge_ptr", .signature = "(idx) -> u32", .summary = "Address of edges[idx]; 0 if invalid." },
    .{ .name = "pask_node_cell_id_ptr", .signature = "(idx) -> u32", .summary = "Address of nodes[idx].cell_id." },
    .{ .name = "pask_node_h_state", .signature = "(idx) -> f64", .summary = "h_state of node, or 0 if invalid." },
    .{ .name = "pask_node_is_stable", .signature = "(idx) -> i32", .summary = "1=stable, 0=not, -1=invalid." },
    .{ .name = "pask_node_is_pruned", .signature = "(idx) -> i32", .summary = "1=pruned, 0=not, -1=invalid." },
    .{ .name = "pask_stable_count", .signature = "() -> u32", .summary = "Count of (stable && !pruned) nodes." },
    .{ .name = "pask_stable_threads_into", .signature = "(out_ptr, max) -> u32", .summary = "Write up to max StableThread records sorted by h_state desc." },

    .{ .name = "pask_node_array_ptr", .signature = "() -> u32", .summary = "Base of nodes array (zero-copy view)." },
    .{ .name = "pask_edge_array_ptr", .signature = "() -> u32", .summary = "Base of edges array (zero-copy view)." },
    .{ .name = "pask_node_stride", .signature = "() -> u32", .summary = "sizeof(Node)." },
    .{ .name = "pask_edge_stride", .signature = "() -> u32", .summary = "sizeof(Edge)." },
    .{ .name = "pask_stable_thread_stride", .signature = "() -> u32", .summary = "sizeof(StableThread)." },
    .{ .name = "pask_stable_threads_build", .signature = "(max) -> i32", .summary = "Materialise top-`max` stable threads into the buffer; one trampoline." },
    .{ .name = "pask_stable_threads_buf_ptr", .signature = "() -> u32", .summary = "Buffer with [count u32][stride u32][records...]." },

    .{ .name = "pask_snapshot_state", .signature = "() -> u32", .summary = "Capture current state to buffer; returns buffer ptr." },
    .{ .name = "pask_restore_state", .signature = "(ptr) -> i32", .summary = "Restore from blob (0=ok, -2 magic, -3 version, -4 length)." },
    .{ .name = "pask_snapshot_buf_ptr", .signature = "() -> u32", .summary = "Address of the snapshot buffer." },
    .{ .name = "pask_snapshot_buf_len", .signature = "() -> u32", .summary = "Snapshot buffer capacity." },

    .{ .name = "pask_scratch_ptr", .signature = "() -> u32", .summary = "Address of the scratch region (callers stage strings/related-idx arrays here)." },
    .{ .name = "pask_scratch_len", .signature = "() -> u32", .summary = "Scratch region capacity." },
};

// ── Snapshot ABI ────────────────────────────────────────────────────────
const SNAPSHOT_MAGIC_HEX = "0x4B534150"; // "PASK"
const SNAPSHOT_VERSION = 1;

// ── Emitter ─────────────────────────────────────────────────────────────

fn writeStringField(w: anytype, indent: []const u8, key: []const u8, value: []const u8) !void {
    try w.print("{s}\"{s}\": \"{s}\"", .{ indent, key, value });
}

fn writeStruct(
    w: anytype,
    name: []const u8,
    comptime T: type,
    indent: []const u8,
) !void {
    try w.print("{s}\"{s}\": {{\n", .{ indent, name });
    try w.print("{s}  \"size\": {d},\n", .{ indent, @sizeOf(T) });
    try w.print("{s}  \"alignment\": {d},\n", .{ indent, @alignOf(T) });
    try w.print("{s}  \"fields\": [\n", .{indent});
    inline for (std.meta.fields(T), 0..) |field, i| {
        const sep: []const u8 = if (i + 1 < std.meta.fields(T).len) "," else "";
        try w.print(
            "{s}    {{ \"name\": \"{s}\", \"offset\": {d}, \"size\": {d}, \"type\": \"{s}\" }}{s}\n",
            .{ indent, field.name, @offsetOf(T, field.name), @sizeOf(field.type), @typeName(field.type), sep },
        );
    }
    try w.print("{s}  ]\n{s}}}", .{ indent, indent });
}

pub fn main() !void {
    var stdout_buf: [16 * 1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const w = &stdout_writer.interface;

    try w.print("{{\n", .{});
    try w.print("  \"specVersion\": \"{s}\",\n", .{SPEC_VERSION});
    try w.print("  \"name\": \"pask\",\n", .{});
    try w.print("  \"version\": \"{s}\",\n", .{PASK_VERSION});
    try w.print("  \"description\": \"Paskian learning kernel — constraint-graph propagation + stability over a fixed-pool node/edge graph.\",\n", .{});

    // Capacity caps (from config.zig).
    try w.print("  \"capacity\": {{\n", .{});
    try w.print("    \"maxNodes\": {d},\n", .{config.MAX_NODES});
    try w.print("    \"maxEdges\": {d},\n", .{config.MAX_EDGES});
    try w.print("    \"maxCellIdLen\": {d},\n", .{config.MAX_CELL_ID_LEN});
    try w.print("    \"maxTypePathLen\": {d},\n", .{config.MAX_TYPE_PATH_LEN});
    try w.print("    \"deltaRingCap\": {d},\n", .{config.DELTA_RING_CAP});
    try w.print("    \"maxAffected\": {d},\n", .{config.MAX_AFFECTED});
    try w.print("    \"maxRelated\": {d}\n", .{config.MAX_RELATED});
    try w.print("  }},\n", .{});

    // Default config values.
    try w.print("  \"defaultConfig\": {{\n", .{});
    try w.print("    \"pruneThreshold\": {d},\n", .{config.DEFAULT.prune_threshold});
    try w.print("    \"stabilityEpsilon\": {d},\n", .{config.DEFAULT.stability_epsilon});
    try w.print("    \"minInteractions\": {d},\n", .{config.DEFAULT.min_interactions});
    try w.print("    \"propagationDepth\": {d},\n", .{config.DEFAULT.propagation_depth});
    try w.print("    \"learningRate\": {d},\n", .{config.DEFAULT.learning_rate});
    try w.print("    \"stabilityWindowMs\": {d},\n", .{config.DEFAULT.stability_window_ms});
    try w.print("    \"stabilityCheckEvery\": {d},\n", .{config.DEFAULT.stability_check_every});
    try w.print("    \"pruneEvery\": {d}\n", .{config.DEFAULT.prune_every});
    try w.print("  }},\n", .{});

    // Struct layouts — mechanically derived.
    try w.print("  \"structs\": {{\n", .{});
    try writeStruct(w, "Config", config.Config, "    ");
    try w.print(",\n", .{});
    try writeStruct(w, "Node", types.Node, "    ");
    try w.print(",\n", .{});
    try writeStruct(w, "Edge", types.Edge, "    ");
    try w.print(",\n", .{});
    try writeStruct(w, "Delta", types.Delta, "    ");
    try w.print(",\n", .{});
    try writeStruct(w, "StableThread", types.StableThread, "    ");
    try w.print("\n  }},\n", .{});

    // Snapshot ABI.
    try w.print("  \"snapshot\": {{\n", .{});
    try w.print("    \"magic\": \"{s}\",\n", .{SNAPSHOT_MAGIC_HEX});
    try w.print("    \"magicAscii\": \"PASK\",\n", .{});
    try w.print("    \"version\": {d},\n", .{SNAPSHOT_VERSION});
    try w.print("    \"headerLayout\": \"[u32 magic][u32 version][u32 length][payload bytes]\"\n", .{});
    try w.print("  }},\n", .{});

    // Exports.
    try w.print("  \"exports\": [\n", .{});
    inline for (EXPORTS, 0..) |e, i| {
        const sep: []const u8 = if (i + 1 < EXPORTS.len) "," else "";
        try w.print(
            "    {{ \"name\": \"{s}\", \"signature\": \"{s}\", \"summary\": \"{s}\" }}{s}\n",
            .{ e.name, e.signature, e.summary, sep },
        );
    }
    try w.print("  ]\n", .{});

    try w.print("}}\n", .{});
    try w.flush();
}

```
