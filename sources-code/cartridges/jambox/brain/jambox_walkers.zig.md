---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/brain/jambox_walkers.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.578311+00:00
---

# cartridges/jambox/brain/jambox_walkers.zig

```zig
// Jambox walker adapters — the brain-side write-seam handlers for
// jam_experience action verbs.
//
// Reference:
//   docs/design/PLATFORM-WALLET-SHELL-EXPLORATION.md §16 (multi-extension proof)
//   runtime/semantos-brain/src/verb_dispatcher.zig (the WalkerFn contract)
//   runtime/semantos-brain/src/oddjobz_ratify_walker.zig (the seed walker pattern)
//   packages/jam_experience/assets/manifest.json (the verb vocabulary)
//
// Status — Phase 1 (this push):
//
//   The walkers validate intent params and return a structured JSON
//   acknowledgement, but DO NOT yet mint jam cells. There are no jam
//   typed view-stores on the brain today (cell_query_handler returns
//   store_unavailable for jam typeHashes); cell minting lands when
//   those stores arrive.
//
//   What this Phase proves is the END-TO-END plumbing for a SECOND
//   extension: the field shell calls verb.dispatch({extensionId:
//   "jambox", verb: "launch_clip"}); the brain routes to a jambox-
//   specific walker; the walker returns a typed result. Same shape as
//   oddjobz.ratify_proposal. Zero new brain dispatch code per walker
//   beyond the registration call.
//
// Phase 2 (when jam typed stores exist):
//
//   - launchClipWalker writes a `jam.intent.launch_clip.v1` cell with
//     {clipId, launchAt, launchedBy} and bumps the jam.clip cell's
//     state field via the store's atomic update.
//   - recordTakeWalker writes a `jam.take.v1` cell with the captured
//     audio reference (cellRef of the audio blob) and links it to
//     the active jam.world.
//   - The walker contract stays the same — only the body changes.

const std = @import("std");
const verb_dispatcher = @import("verb_dispatcher");
const jam_clip_state_store = @import("jam_clip_state_store");

/// Shared state for jambox walkers. Holds a clock function for
/// deterministic timestamping (real callers pass `realClock` from
/// cli.zig; tests pass a pinned constant) plus optional pointers to
/// the typed view-stores walkers will use when minting cells.
///
/// Phase 2 (this iteration): jam_clip_store is wired. The walker
/// records `launch_clip` transitions through it when present and
/// includes the recorded state in the result. Other stores (jam.world,
/// jam.take, jam.pattern, jam.arrangement) follow the same shape as
/// they come online; the State struct grows entries without changing
/// the WalkerFn contract.
pub const State = struct {
    /// Returns Unix seconds. Deterministic in tests; cli.zig wires the
    /// production clock.
    clock_fn: *const fn () i64,

    /// Optional jam.clip state store. When non-null, `launchClipWalker`
    /// records the transition and surfaces the resulting state in the
    /// response. When null the walker stays placeholder-only.
    jam_clip_store: ?*jam_clip_state_store.Store = null,
    // Phase 2 (next): jam_world_store, jam_take_store, jam_pattern_store,
    // jam_arrangement_store.
};

// ─── launch_clip walker ──────────────────────────────────────────────

pub fn launchClipWalker(
    allocator: std.mem.Allocator,
    ctx: *anyopaque,
    params_json: []const u8,
) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch {
        return verb_dispatcher.DispatchError.invalid_params;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return verb_dispatcher.DispatchError.invalid_params;
    const obj = parsed.value.object;

    const clip_id_v = obj.get("clipId") orelse return verb_dispatcher.DispatchError.invalid_params;
    if (clip_id_v != .string or clip_id_v.string.len == 0) {
        return verb_dispatcher.DispatchError.invalid_params;
    }

    // Optional fields — recorded if present but not required.
    const launched_by: ?[]const u8 = if (obj.get("launchedByPlayer")) |v|
        if (v == .string) v.string else null
    else
        null;

    const queued_at = state.clock_fn();

    // Phase 2 wiring: if the jam.clip state store is attached, record
    // the transition. The store's clock is independent (it timestamps
    // its own writes) so the walker doesn't need to coordinate.
    var recorded_state_name: ?[]const u8 = null;
    if (state.jam_clip_store) |store| {
        _ = store.appendStateTransition(
            clip_id_v.string,
            .queued,
            launched_by orelse "",
        ) catch |err| switch (err) {
            error.invalid_clip_id => return verb_dispatcher.DispatchError.invalid_params,
            error.out_of_memory => return verb_dispatcher.DispatchError.out_of_memory,
        };
        recorded_state_name = "queued";
    }

    return buildLaunchClipResult(
        allocator,
        clip_id_v.string,
        launched_by,
        queued_at,
        recorded_state_name,
    ) catch |err| switch (err) {
        error.OutOfMemory => verb_dispatcher.DispatchError.out_of_memory,
    };
}

fn buildLaunchClipResult(
    allocator: std.mem.Allocator,
    clip_id: []const u8,
    launched_by: ?[]const u8,
    queued_at: i64,
    recorded_state: ?[]const u8,
) ![]u8 {
    var body: std.ArrayList(u8) = .{};
    errdefer body.deinit(allocator);

    try body.appendSlice(allocator, "{\"status\":\"queued\",\"extensionId\":\"jambox\",\"verb\":\"launch_clip\",\"clipId\":");
    try appendJsonString(allocator, &body, clip_id);
    if (launched_by) |lb| {
        try body.appendSlice(allocator, ",\"launchedByPlayer\":");
        try appendJsonString(allocator, &body, lb);
    }
    try body.appendSlice(allocator, ",\"queuedAt\":");
    const ts_str = try std.fmt.allocPrint(allocator, "{d}", .{queued_at});
    defer allocator.free(ts_str);
    try body.appendSlice(allocator, ts_str);
    if (recorded_state) |rs| {
        try body.appendSlice(allocator, ",\"recordedState\":");
        try appendJsonString(allocator, &body, rs);
        try body.append(allocator, '}');
    } else {
        try body.appendSlice(
            allocator,
            ",\"note\":\"jam.clip store not attached \\u2014 placeholder ack; attach jam_clip_state_store at boot to record transitions\"}",
        );
    }
    return body.toOwnedSlice(allocator);
}

// ─── record_take walker ──────────────────────────────────────────────

pub fn recordTakeWalker(
    allocator: std.mem.Allocator,
    ctx: *anyopaque,
    params_json: []const u8,
) verb_dispatcher.DispatchError![]u8 {
    const state: *State = @ptrCast(@alignCast(ctx));

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch {
        return verb_dispatcher.DispatchError.invalid_params;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return verb_dispatcher.DispatchError.invalid_params;
    const obj = parsed.value.object;

    // trackId is optional — recording covers all tracks by default.
    const track_id: ?[]const u8 = if (obj.get("trackId")) |v|
        if (v == .string and v.string.len > 0) v.string else null
    else
        null;

    const captured_at = state.clock_fn();

    return buildRecordTakeResult(allocator, track_id, captured_at) catch |err| switch (err) {
        error.OutOfMemory => verb_dispatcher.DispatchError.out_of_memory,
    };
}

fn buildRecordTakeResult(
    allocator: std.mem.Allocator,
    track_id: ?[]const u8,
    captured_at: i64,
) ![]u8 {
    var body: std.ArrayList(u8) = .{};
    errdefer body.deinit(allocator);

    try body.appendSlice(allocator, "{\"status\":\"capturing\",\"extensionId\":\"jambox\",\"verb\":\"record_take\",\"trackId\":");
    if (track_id) |t| {
        try appendJsonString(allocator, &body, t);
    } else {
        try body.appendSlice(allocator, "null");
    }
    try body.appendSlice(allocator, ",\"capturedAt\":");
    const ts_str = try std.fmt.allocPrint(allocator, "{d}", .{captured_at});
    defer allocator.free(ts_str);
    try body.appendSlice(allocator, ts_str);
    try body.appendSlice(
        allocator,
        ",\"note\":\"jam.take store not yet wired \\u2014 placeholder ack; cell minting lands in Phase 2\"}",
    );
    return body.toOwnedSlice(allocator);
}

// ─── Registration ────────────────────────────────────────────────────

/// Register every jambox walker into [registry]. CLI calls this at
/// brain boot alongside the oddjobz_ratify walker registration.
pub fn registerAll(
    registry: *verb_dispatcher.Registry,
    state: *State,
) !void {
    try registry.register(.{
        .extension_id = "jambox",
        .verb = "launch_clip",
        .walker_fn = launchClipWalker,
        .ctx = @ptrCast(state),
    });
    try registry.register(.{
        .extension_id = "jambox",
        .verb = "record_take",
        .walker_fn = recordTakeWalker,
        .ctx = @ptrCast(state),
    });
    // Phase 2 will add: stop_clip, launch_scene, promote_take,
    // capture_gesture, edit_pattern, twist_macro, mute_track,
    // unmute_track, set_tempo, set_key, grant_permission,
    // revoke_permission, invite_player — same shape, more walkers.
}

// ─── JSON helpers ────────────────────────────────────────────────────

fn appendJsonString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    s: []const u8,
) !void {
    try out.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            else => try out.append(allocator, c),
        }
    }
    try out.append(allocator, '"');
}

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

fn fixedClock() i64 {
    return 1747100000;
}

test "launchClipWalker validates params and returns structured ack" {
    var state = State{ .clock_fn = fixedClock };
    const params = "{\"clipId\":\"clip-abc\",\"launchedByPlayer\":\"player-1\"}";
    const result = try launchClipWalker(testing.allocator, &state, params);
    defer testing.allocator.free(result);
    // Spot-check the result body shape.
    try testing.expect(std.mem.indexOf(u8, result, "\"verb\":\"launch_clip\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"clipId\":\"clip-abc\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"launchedByPlayer\":\"player-1\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"queuedAt\":1747100000") != null);
}

test "launchClipWalker records transition when jam.clip store is attached" {
    var store = jam_clip_state_store.Store.init(testing.allocator, fixedClock);
    defer store.deinit();
    var state = State{ .clock_fn = fixedClock, .jam_clip_store = &store };

    const params = "{\"clipId\":\"clip-xyz\",\"launchedByPlayer\":\"player-2\"}";
    const result = try launchClipWalker(testing.allocator, &state, params);
    defer testing.allocator.free(result);

    // The walker's response should include the recorded state and skip
    // the placeholder note.
    try testing.expect(std.mem.indexOf(u8, result, "\"recordedState\":\"queued\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "placeholder ack") == null);

    // The store should now reflect the transition.
    const rec = store.get("clip-xyz").?;
    try testing.expectEqual(jam_clip_state_store.ClipState.queued, rec.state);
    try testing.expectEqualStrings("player-2", rec.actor_player);
}

test "launchClipWalker rejects missing clipId" {
    var state = State{ .clock_fn = fixedClock };
    const params = "{\"launchedByPlayer\":\"player-1\"}";
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        launchClipWalker(testing.allocator, &state, params),
    );
}

test "launchClipWalker rejects non-string clipId" {
    var state = State{ .clock_fn = fixedClock };
    const params = "{\"clipId\":42}";
    try testing.expectError(
        verb_dispatcher.DispatchError.invalid_params,
        launchClipWalker(testing.allocator, &state, params),
    );
}

test "recordTakeWalker accepts no trackId (means all tracks)" {
    var state = State{ .clock_fn = fixedClock };
    const params = "{}";
    const result = try recordTakeWalker(testing.allocator, &state, params);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"verb\":\"record_take\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"trackId\":null") != null);
}

test "recordTakeWalker accepts explicit trackId" {
    var state = State{ .clock_fn = fixedClock };
    const params = "{\"trackId\":\"track-drum\"}";
    const result = try recordTakeWalker(testing.allocator, &state, params);
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"trackId\":\"track-drum\"") != null);
}

test "registerAll registers both walkers" {
    var state = State{ .clock_fn = fixedClock };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    try testing.expectEqual(@as(usize, 2), reg.count());
    try testing.expect(reg.hasExtension("jambox"));

    // Dispatch through the registry to exercise the full path.
    const result = try reg.dispatch(
        testing.allocator,
        "jambox",
        "launch_clip",
        "{\"clipId\":\"c1\"}",
    );
    defer testing.allocator.free(result);
    try testing.expect(std.mem.indexOf(u8, result, "\"clipId\":\"c1\"") != null);
}

test "registerAll rejects duplicate registration" {
    var state = State{ .clock_fn = fixedClock };
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try registerAll(&reg, &state);
    try testing.expectError(error.duplicate_walker, registerAll(&reg, &state));
}

```
