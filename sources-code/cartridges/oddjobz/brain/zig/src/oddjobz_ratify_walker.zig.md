---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/oddjobz_ratify_walker.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.549013+00:00
---

# cartridges/oddjobz/brain/zig/src/oddjobz_ratify_walker.zig

```zig
// Walker adapter — adapts the existing oddjobz_ratify_handler.Handler
// onto the generic verb_dispatcher.Walker contract.
//
// This is the seed proof that the dispatcher architecture works:
//   • oddjobz_ratify_handler keeps its existing direct entry point
//     (the `oddjobz.ratify_proposal` JSON-RPC method continues to work
//     as before — no breaking change to clients on that path)
//   • This adapter registers it as a uniform `verb.dispatch` target so
//     experiences (and future shells) can drive ratification via the
//     generic dispatcher with `{extensionId: "oddjobz", verb: "ratify_proposal"}`
//   • Future extensions follow this exact pattern — write a walker
//     that wraps your typed handler, register it at brain boot, your
//     verb is now callable through the uniform dispatcher

const std = @import("std");
const oddjobz_ratify_handler = @import("oddjobz_ratify_handler");
const verb_dispatcher = @import("verb_dispatcher");

/// Walker callback — pulls the handler back out of the opaque ctx and
/// invokes handleRatify, then serialises the RatifyResult into the same
/// JSON shape as `handleOddjobzRatifyProposal` produces in wss_wallet.zig.
pub fn walker(
    allocator: std.mem.Allocator,
    ctx: *anyopaque,
    params_json: []const u8,
) verb_dispatcher.DispatchError![]u8 {
    const handler: *oddjobz_ratify_handler.Handler = @ptrCast(@alignCast(ctx));

    var result = handler.handleRatify(allocator, params_json) catch |err| switch (err) {
        error.invalid_params,
        error.invalid_proposal_id,
        error.invalid_sir_program,
        error.unsupported_action,
        => return verb_dispatcher.DispatchError.invalid_params,
        error.store_append_failed,
        error.persist_failed,
        => return verb_dispatcher.DispatchError.walker_failed,
        error.out_of_memory => return verb_dispatcher.DispatchError.out_of_memory,
    };
    defer result.deinit();

    return serializeResult(allocator, &result) catch |err| switch (err) {
        error.OutOfMemory => verb_dispatcher.DispatchError.out_of_memory,
    };
}

/// Build the `{proposal_id, cellIds: {...}, persistedAt}` JSON body —
/// matches the wire shape `oddjobz.ratify_proposal` already emits, so
/// existing clients see identical bytes whether they call via the
/// legacy method or the new `verb.dispatch` route.
fn serializeResult(
    allocator: std.mem.Allocator,
    result: *const oddjobz_ratify_handler.RatifyResult,
) ![]u8 {
    var body: std.ArrayList(u8) = .{};
    errdefer body.deinit(allocator);

    try body.appendSlice(allocator, "{\"proposal_id\":");
    try appendJsonString(allocator, &body, result.proposal_id);
    try body.appendSlice(allocator, ",\"cellIds\":{\"site\":");
    if (result.site_cell_id) |s| {
        try appendJsonString(allocator, &body, s);
    } else {
        try body.appendSlice(allocator, "null");
    }
    try body.appendSlice(allocator, ",\"customers\":[");
    for (result.customer_cell_ids, 0..) |cid, i| {
        if (i != 0) try body.append(allocator, ',');
        try appendJsonString(allocator, &body, cid);
    }
    try body.appendSlice(allocator, "],\"job\":");
    if (result.job_cell_id) |s| {
        try appendJsonString(allocator, &body, s);
    } else {
        try body.appendSlice(allocator, "null");
    }
    try body.appendSlice(allocator, ",\"attachments\":[");
    for (result.attachment_cell_ids, 0..) |cid, i| {
        if (i != 0) try body.append(allocator, ',');
        try appendJsonString(allocator, &body, cid);
    }
    try body.appendSlice(allocator, "]},\"persistedAt\":");
    const ts_str = try std.fmt.allocPrint(allocator, "{d}", .{result.persisted_at});
    defer allocator.free(ts_str);
    try body.appendSlice(allocator, ts_str);
    try body.append(allocator, '}');

    return body.toOwnedSlice(allocator);
}

/// Minimal JSON-safe string emit — escapes the four characters that
/// must be escaped for a well-formed JSON string. Cell-id hex strings
/// and proposal_id strings are ASCII so this is sufficient for the
/// ratify walker's output shape.
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

// C4 PR-J5b — `registerInto` (verb_registry registration) was removed: ratify
// no longer routes through `verb.dispatch`. The `walker` fn above is reused by
// the generic `ratify.submit` builder (serve registers it as the "oddjobz"
// RatifyBuilder.submit thunk), so this file stays — only the verb_registry
// registration is gone.

```
