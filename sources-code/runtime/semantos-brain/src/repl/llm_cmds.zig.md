---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/repl/llm_cmds.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.296964+00:00
---

# runtime/semantos-brain/src/repl/llm_cmds.zig

```zig
// LLM REPL commands — `llm complete <scope> <base64-args>`.
//
// These verbs let the mobile field app and Svelte helm dispatch AI
// requests through the brain rather than calling the Anthropic API
// directly.  The immediate win: removes ANTHROPIC_API_KEY from the
// Android APK; the long-term win: all rate-limiting / budget-tracking
// lives in one place (llm_complete_handler.zig).
//
// Wire format (client side):
//
//   cmd = "llm complete <scope> <base64-args>"
//   base64-args = base64(UTF-8 JSON)
//   JSON = {"prompt":"...","system_prompt":"...","max_tokens":N,"temperature":N}
//
// The REPL layer:
//   1. base64-decodes the args JSON
//   2. injects the <scope> field into the decoded object
//   3. dispatches with .in_process_root auth →  "llm" resource,
//      "complete" command (llm_complete_handler.handleComplete)
//   4. prints the result payload verbatim
//      → {"text":"...","model":"...","tokens_used":N}
//
// The result payload is the raw JSON string the REPL caller receives
// back in ReplOk.result — the Flutter ReplClient and Svelte client
// both parse it on their side without further transformation here.
//
// Future sub-commands (vision, transcribe) follow the same pattern.

const std = @import("std");
const types = @import("types.zig");
const dispatcher_mod = @import("dispatcher");

const Session = types.Session;
const matches = types.matches;
const ReplError = types.ReplError;

/// Entry point for all `llm <sub-command>` REPL verbs.
/// `args` = tokens after "llm" (i.e. rest[] from handleLine).
pub fn cmdLlm(session: *Session, out: anytype, args: []const []const u8) !void {
    if (args.len < 1) {
        try out.print("usage: llm complete <scope> <base64-args>\n       llm vision  <scope> <base64-args>\n", .{});
        return;
    }
    if (matches(args[0], "complete")) {
        return cmdLlmComplete(session, out, args[1..]);
    }
    if (matches(args[0], "vision")) {
        return cmdLlmVision(session, out, args[1..]);
    }
    try out.print("llm: unknown sub-command '{s}'\n  usage: llm complete|vision <scope> <base64-args>\n", .{args[0]});
}

// ─────────────────────────────────────────────────────────────────────
// `llm complete <scope> <base64-args>`
// ─────────────────────────────────────────────────────────────────────

fn cmdLlmComplete(session: *Session, out: anytype, args: []const []const u8) !void {
    if (args.len < 2) {
        try out.print("usage: llm complete <scope> <base64-args>\n", .{});
        return;
    }
    const scope = args[0];
    const b64 = args[1];

    const disp = session.dispatcher orelse {
        try out.print("llm complete: no dispatcher attached (start brain with --enable-repl).\n", .{});
        return;
    };

    // ── Base64-decode the args payload ────────────────────────────────
    const decoder = std.base64.standard.Decoder;
    const max_len = decoder.calcSizeForSlice(b64) catch {
        try out.print("llm complete: args is not valid base64\n", .{});
        return;
    };
    const decoded = session.allocator.alloc(u8, max_len) catch return ReplError.out_of_memory;
    defer session.allocator.free(decoded);
    decoder.decode(decoded, b64) catch {
        try out.print("llm complete: args is not valid base64\n", .{});
        return;
    };

    // ── Inject "scope" into the decoded JSON object ───────────────────
    // The decoded bytes are a JSON object from the client.  We need to
    // add the "scope" field before handing off to the dispatcher.
    // Strategy: trim trailing whitespace, verify the object closes with
    // `}`, append `,"scope":"<scope>"}`.  This avoids a full parse/re-
    // serialize round-trip for what is a well-known trusted client
    // payload.  The handler's parseCompleteArgs validates the full
    // object on arrival anyway.
    const trimmed = std.mem.trimRight(u8, decoded, " \t\r\n");
    if (trimmed.len == 0 or trimmed[trimmed.len - 1] != '}') {
        try out.print("llm complete: args is not a JSON object\n", .{});
        return;
    }
    const scope_enc = std.json.Stringify.valueAlloc(session.allocator, scope, .{}) catch
        return ReplError.out_of_memory;
    defer session.allocator.free(scope_enc);

    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(session.allocator);
    // Everything before the closing `}`.
    try args_buf.appendSlice(session.allocator, trimmed[0 .. trimmed.len - 1]);
    try args_buf.appendSlice(session.allocator, ",\"scope\":");
    try args_buf.appendSlice(session.allocator, scope_enc);
    try args_buf.append(session.allocator, '}');

    // ── Dispatch ──────────────────────────────────────────────────────
    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "llm", "complete", args_buf.items) catch |err| {
        try out.print("llm.complete: {s}\n", .{@errorName(err)});
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) {
        try out.print("{s}\n", .{result.payload});
    }
}

// ─────────────────────────────────────────────────────────────────────
// `llm vision <scope> <base64-args>`
//
// base64-args = base64({"image_b64":"<raw-image-as-base64>",
//                       "media_type":"image/jpeg",
//                       "prompt":"...",         // optional
//                       "system_prompt":"...",  // optional
//                       "max_tokens":N})        // optional
//
// Dispatches to the "llm" resource "vision" command in
// llm_complete_handler — same rate-limiting/budget logic, but the
// HTTP body uses the Anthropic multipart content array (image + text
// blocks) instead of a plain text user message.
// ─────────────────────────────────────────────────────────────────────

fn cmdLlmVision(session: *Session, out: anytype, args: []const []const u8) !void {
    if (args.len < 2) {
        try out.print("usage: llm vision <scope> <base64-args>\n", .{});
        return;
    }
    const scope = args[0];
    const b64 = args[1];

    const disp = session.dispatcher orelse {
        try out.print("llm vision: no dispatcher attached (start brain with --enable-repl).\n", .{});
        return;
    };

    // Base64-decode the args payload.
    const decoder = std.base64.standard.Decoder;
    const max_len = decoder.calcSizeForSlice(b64) catch {
        try out.print("llm vision: args is not valid base64\n", .{});
        return;
    };
    const decoded = session.allocator.alloc(u8, max_len) catch return ReplError.out_of_memory;
    defer session.allocator.free(decoded);
    decoder.decode(decoded, b64) catch {
        try out.print("llm vision: args is not valid base64\n", .{});
        return;
    };

    // Inject "scope" into the decoded JSON object — same approach as
    // cmdLlmComplete.
    const trimmed = std.mem.trimRight(u8, decoded, " \t\r\n");
    if (trimmed.len == 0 or trimmed[trimmed.len - 1] != '}') {
        try out.print("llm vision: args is not a JSON object\n", .{});
        return;
    }
    const scope_enc = std.json.Stringify.valueAlloc(session.allocator, scope, .{}) catch
        return ReplError.out_of_memory;
    defer session.allocator.free(scope_enc);

    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(session.allocator);
    try args_buf.appendSlice(session.allocator, trimmed[0 .. trimmed.len - 1]);
    try args_buf.appendSlice(session.allocator, ",\"scope\":");
    try args_buf.appendSlice(session.allocator, scope_enc);
    try args_buf.append(session.allocator, '}');

    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "llm", "vision", args_buf.items) catch |err| {
        try out.print("llm.vision: {s}\n", .{@errorName(err)});
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) {
        try out.print("{s}\n", .{result.payload});
    }
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

test "cmdLlm prints usage for missing sub-command" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    var out: types.Output = .{ .buffer = &buf, .allocator = std.testing.allocator };
    var session = types.Session{
        .allocator = std.testing.allocator,
        // These fields are optional for this test path; the verb fails
        // before touching them.
        .cfg = undefined,
        .audit_path = "",
        .audit = undefined,
        .broker = undefined,
        .manager = undefined,
        .runner = undefined,
        .instances = &.{},
        .header_store = undefined,
    };
    try cmdLlm(&session, &out, &.{});
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage:") != null);
}

test "cmdLlm prints error for unknown sub-command" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    var out: types.Output = .{ .buffer = &buf, .allocator = std.testing.allocator };
    var session = types.Session{
        .allocator = std.testing.allocator,
        .cfg = undefined,
        .audit_path = "",
        .audit = undefined,
        .broker = undefined,
        .manager = undefined,
        .runner = undefined,
        .instances = &.{},
        .header_store = undefined,
    };
    try cmdLlm(&session, &out, &.{"bogus"});
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "unknown sub-command") != null);
}

test "cmdLlmComplete prints usage when args < 2" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    var out: types.Output = .{ .buffer = &buf, .allocator = std.testing.allocator };
    var session = types.Session{
        .allocator = std.testing.allocator,
        .cfg = undefined,
        .audit_path = "",
        .audit = undefined,
        .broker = undefined,
        .manager = undefined,
        .runner = undefined,
        .instances = &.{},
        .header_store = undefined,
    };
    // "llm complete" with only scope, no b64
    try cmdLlm(&session, &out, &.{ "complete", "my-scope" });
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "usage:") != null);
}

test "cmdLlmComplete prints error when no dispatcher" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);
    var out: types.Output = .{ .buffer = &buf, .allocator = std.testing.allocator };
    var session = types.Session{
        .allocator = std.testing.allocator,
        .cfg = undefined,
        .audit_path = "",
        .audit = undefined,
        .broker = undefined,
        .manager = undefined,
        .runner = undefined,
        .instances = &.{},
        .header_store = undefined,
        // dispatcher = null (the default)
    };
    // Provide valid base64 of a JSON object so we get past the decode step.
    // base64('{"prompt":"hi"}') = "eyJwcm9tcHQiOiJoaSJ9"
    const b64 = "eyJwcm9tcHQiOiJoaSJ9";
    try cmdLlm(&session, &out, &.{ "complete", "my-scope", b64 });
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "no dispatcher") != null);
}

// NOTE: testing the base64-decode error path ("not valid base64") requires
// a live dispatcher to be attached (the dispatcher null-check runs first).
// Integration coverage lives in tests/repl_conformance.zig.

```
