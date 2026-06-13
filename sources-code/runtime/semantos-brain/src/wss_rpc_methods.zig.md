---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/wss_rpc_methods.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.231104+00:00
---

# runtime/semantos-brain/src/wss_rpc_methods.zig

```zig
//! Substrate RPC method handlers — the brain's own (non-cartridge) methods on
//! the unified `/api/v1/rpc` channel. Each is a thin RpcHandleFn adapter over an
//! existing in-process handler, so the WSS channel reuses the HTTP surface's
//! logic verbatim rather than duplicating it. cmdServe pre-registers these on
//! the RpcRegistry at boot; cartridges add their own methods over the seam.
//!
//! M0 surface: `cell.query` (typeHash projection) and `repl.eval` (FSM verb
//! dispatch). M1.7 adds `cells.mint` (generic cell write); B3 adds `cell.get`
//! (single-cell-by-ref read) — all on the same pattern.

const std = @import("std");
const rpc = @import("wss_rpc_registry");
const cell_query_handler = @import("cell_query_handler");
const repl = @import("repl");
const cells_mint_http = @import("cells_mint_http");
const cells_mint_core = @import("cells_mint_core");

// ─────────────────────────────────────────────────────────────────────
// cell.query — params { typeHash: string, filter?: object }
//   result: the decoder's collection envelope verbatim, e.g. {"jobs":[…]}.
// state: *const cell_query_handler.Handler
// ─────────────────────────────────────────────────────────────────────

pub fn cellQuery(
    state: *anyopaque,
    params_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!rpc.RpcResult {
    const handler: *const cell_query_handler.Handler = @ptrCast(@alignCast(state));

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch
        return badRequest("params must be a JSON object");
    defer parsed.deinit();
    if (parsed.value != .object) return badRequest("params must be a JSON object");
    const obj = parsed.value.object;

    const type_hash = switch (obj.get("typeHash") orelse return badRequest("missing typeHash")) {
        .string => |s| s,
        else => return badRequest("typeHash must be a string"),
    };

    // Optional filter object → re-serialized JSON the decoder evaluates.
    var filter_json: ?[]const u8 = null;
    if (obj.get("filter")) |fv| {
        if (fv != .null) {
            filter_json = std.json.Stringify.valueAlloc(allocator, fv, .{}) catch
                return badRequest("filter not serializable");
        }
    }

    const body = handler.query(allocator, type_hash, filter_json) catch |err| {
        return .{ .err = .{ .code = cellQueryErrCode(err), .message = @errorName(err) } };
    };
    return .{ .ok = body };
}

fn cellQueryErrCode(err: cell_query_handler.CellQueryError) []const u8 {
    return switch (err) {
        error.unknown_type_hash => "not_found",
        error.invalid_params, error.invalid_filter, error.invalid_cell_ref => "bad_request",
        error.store_unavailable, error.out_of_memory => "internal",
    };
}

// ─────────────────────────────────────────────────────────────────────
// cell.get — params { typeHash: string, cellRef|cellId|<legacy ref>: "<64hex>" }
//   result: the decoder's singular envelope verbatim, e.g. {"job":{…}} (or
//   {"job":null} when the ref isn't found). `Handler.get` extracts the ref
//   itself (first 64-hex string value in the params object), so we only pull
//   `typeHash` here and hand it the raw params for ref extraction.
// state: *const cell_query_handler.Handler
// ─────────────────────────────────────────────────────────────────────

pub fn cellGet(
    state: *anyopaque,
    params_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!rpc.RpcResult {
    const handler: *const cell_query_handler.Handler = @ptrCast(@alignCast(state));

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch
        return badRequest("params must be a JSON object");
    defer parsed.deinit();
    if (parsed.value != .object) return badRequest("params must be a JSON object");

    const type_hash = switch (parsed.value.object.get("typeHash") orelse return badRequest("missing typeHash")) {
        .string => |s| s,
        else => return badRequest("typeHash must be a string"),
    };

    const body = handler.get(allocator, type_hash, params_json) catch |err| {
        return .{ .err = .{ .code = cellQueryErrCode(err), .message = @errorName(err) } };
    };
    return .{ .ok = body };
}

// ─────────────────────────────────────────────────────────────────────
// repl.eval — params { cmd: string }
//   result: {"result":"<repl output>","exit":"continue"|"quit"}
// state: *repl.Session
// ─────────────────────────────────────────────────────────────────────

pub fn replEval(
    state: *anyopaque,
    params_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!rpc.RpcResult {
    const session: *repl.Session = @ptrCast(@alignCast(state));

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch
        return badRequest("params must be a JSON object");
    defer parsed.deinit();
    if (parsed.value != .object) return badRequest("params must be a JSON object");
    const cmd = switch (parsed.value.object.get("cmd") orelse return badRequest("missing cmd")) {
        .string => |s| s,
        else => return badRequest("cmd must be a string"),
    };

    var out_buf: std.ArrayList(u8) = .{};
    defer out_buf.deinit(allocator);
    var out: repl.Output = .{ .buffer = &out_buf, .allocator = allocator };
    const exit = repl.handleLine(session, &out, cmd) catch |err| {
        return .{ .err = .{ .code = "internal", .message = @errorName(err) } };
    };

    // {"result":<json-string of output>,"exit":"continue"|"quit"}
    const out_str = try std.json.Stringify.valueAlloc(allocator, std.json.Value{ .string = out_buf.items }, .{});
    defer allocator.free(out_str);
    const exit_str = switch (exit) {
        .quit => "quit",
        .@"continue" => "continue",
    };
    const body = try std.fmt.allocPrint(allocator, "{{\"result\":{s},\"exit\":\"{s}\"}}", .{ out_str, exit_str });
    return .{ .ok = body };
}

// ─────────────────────────────────────────────────────────────────────
// cells.mint — params is the SAME envelope the HTTP `POST /api/v1/cells`
//   body uses: { typeHashHex, payload | payloadBytesHex, signatureHex?, … }.
//   result: {"cellId","cartridgeId","cellType","persistedAt"} — byte-identical
//   shape to the HTTP 201 body (cellId is deterministic over the cell bytes,
//   so a parity check can assert {cellId,cartridgeId,cellType} match across
//   transports). Auth is bound at the socket upgrade; this registers with
//   `required_cap = cap.brain.admin` (the HTTP route is admin-gated).
// state: *const cells_mint_http.Acceptor
// ─────────────────────────────────────────────────────────────────────

pub fn cellsMint(
    state: *anyopaque,
    params_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!rpc.RpcResult {
    const acceptor: *const cells_mint_http.Acceptor = @ptrCast(@alignCast(state));

    // Reuse the HTTP path's parser verbatim — `params_json` is the same
    // envelope shape as the HTTP body, so no shape can drift between them.
    var mint_req = cells_mint_http.parseRequestBody(allocator, params_json) catch |err| switch (err) {
        cells_mint_http.Error.payload_too_large => return .{ .err = .{ .code = "bad_request", .message = "payload_too_large" } },
        cells_mint_http.Error.out_of_memory => return .{ .err = .{ .code = "internal", .message = "out_of_memory" } },
        else => return badRequest("params must be {typeHashHex,payload}"),
    };
    defer cells_mint_http.deinitRequest(allocator, &mint_req);

    const entry = cells_mint_http.resolveCellType(&mint_req.type_hash) catch
        return .{ .err = .{ .code = "not_found", .message = "unknown_type_hash" } };

    switch (cells_mint_core.mintCellCore(acceptor, &mint_req, entry, allocator)) {
        .created => |c| {
            const body = try std.fmt.allocPrint(
                allocator,
                "{{\"cellId\":\"{s}\",\"cartridgeId\":\"{s}\",\"cellType\":\"{s}\",\"persistedAt\":{d}}}",
                .{ c.cell_hash_hex[0..64], c.cartridge_id, c.cell_type_name, c.persisted_at },
            );
            return .{ .ok = body };
        },
        // The HTTP path renders structured detail (field/expectedType/reason/
        // hint) into its JSON body; the RPC err frame carries code + message,
        // so we surface the error_tag as the message (mirrors cellQuery's
        // code+@errorName posture).
        .failed => |f| return .{ .err = .{ .code = f.rpcCode(), .message = f.error_tag } },
    }
}

// ─────────────────────────────────────────────────────────────────────

fn badRequest(msg: []const u8) rpc.RpcResult {
    return .{ .err = .{ .code = "bad_request", .message = msg } };
}

// ─────────────────────────────────────────────────────────────────────
const testing = std.testing;

test "cellQuery: bad params shapes" {
    const a = testing.allocator;
    // Construct a Handler with undefined backing — we only exercise the
    // pre-query param validation, which returns before touching the store.
    var handler: cell_query_handler.Handler = undefined;
    const r1 = try cellQuery(@ptrCast(&handler), "not json", a);
    try testing.expectEqualStrings("bad_request", r1.err.code);
    const r2 = try cellQuery(@ptrCast(&handler), "{\"nope\":1}", a);
    try testing.expectEqualStrings("bad_request", r2.err.code);
    try testing.expectEqualStrings("missing typeHash", r2.err.message);
}

test "cellGet: bad params shapes" {
    const a = testing.allocator;
    // Same pre-dispatch validation contract as cellQuery: malformed JSON and a
    // missing typeHash both return before the handler touches the store.
    var handler: cell_query_handler.Handler = undefined;
    const r1 = try cellGet(@ptrCast(&handler), "not json", a);
    try testing.expectEqualStrings("bad_request", r1.err.code);
    const r2 = try cellGet(@ptrCast(&handler), "{\"nope\":1}", a);
    try testing.expectEqualStrings("bad_request", r2.err.code);
    try testing.expectEqualStrings("missing typeHash", r2.err.message);
    const r3 = try cellGet(@ptrCast(&handler), "{\"typeHash\":42}", a);
    try testing.expectEqualStrings("bad_request", r3.err.code);
    try testing.expectEqualStrings("typeHash must be a string", r3.err.message);
}

```
