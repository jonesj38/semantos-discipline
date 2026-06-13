---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/repl/extra_cmds.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.296383+00:00
---

# runtime/semantos-brain/src/repl/extra_cmds.zig

```zig
// Operator-facing REPL cmd verbs (extension, intent_cells, site_config)
// extracted from src/repl.zig as Phase 3 of the modularize.
// (C4 PR-J6: the leads verbs were deleted along with the orphaned leads resource.)

const std = @import("std");
const types = @import("types.zig");
const Output = @import("repl_output").Output; // C4 PR-R1 — concrete writer
const dispatcher_mod = @import("dispatcher");
const audit_log_mod = @import("audit_log");
const tenant_manifest_mod = @import("tenant_manifest");
const extension_quarantine_mod = @import("extension_quarantine");
const intent_cells_store_fs_mod = @import("intent_cells_store_fs");
const intent_cells_handler_mod = @import("intent_cells_handler");
const site_config_handler_mod = @import("site_config_handler");

const Session = types.Session;
const matches = types.matches;
const ReplError = types.ReplError;

// ─────────────────────────────────────────────────────────────────────
// D-W2 Phase 4 — REPL `extension quarantine list|evaluate|remove`
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
//   §7 Phase 4 + cli.zig's cmdExtensionQuarantine.
//
// Same semantics as the CLI verbs; the REPL surface is convenience
// for operators driving in-place.  The verbs read/write the same
// `<data_dir>/extension-quarantine.json` index + `<data_dir>/
// extensions/<ns>/<ver>/meta.json` files.
//
// The REPL session has access to the running daemon's dispatcher
// via session.dispatcher (when set) — so quarantine/unmark calls
// flip the in-memory flag synchronously rather than only writing
// to disk.  The CLI form is detached from the daemon and writes
// to disk only; the REPL form is the live-update path.
// ─────────────────────────────────────────────────────────────────────

pub fn cmdExtension(session: *Session, out: *const Output, args: []const []const u8) !void {
    if (args.len < 2 or !matches(args[0], "quarantine")) {
        try out.print("usage: extension quarantine list | evaluate <namespace> | remove <namespace>\n", .{});
        return;
    }
    const sub = args[1];
    const data_dir = session.cfg.shell.data_dir;
    if (matches(sub, "list")) {
        try cmdExtensionQuarantineList(session.allocator, out, data_dir);
        return;
    }
    if (matches(sub, "evaluate")) {
        if (args.len < 3) {
            try out.print("usage: extension quarantine evaluate <namespace>\n", .{});
            return;
        }
        try cmdExtensionQuarantineEvaluate(session, out, args[2], data_dir);
        return;
    }
    if (matches(sub, "remove")) {
        if (args.len < 3) {
            try out.print("usage: extension quarantine remove <namespace>\n", .{});
            return;
        }
        try cmdExtensionQuarantineRemove(session, out, args[2], data_dir);
        return;
    }
    try out.print("unknown extension subcommand: {s}\n", .{sub});
}

pub fn cmdExtensionQuarantineList(allocator: std.mem.Allocator, out: *const Output, data_dir: []const u8) !void {
    const records = extension_quarantine_mod.loadLatestRecords(allocator, data_dir) catch |err| {
        try out.print("extension quarantine list: {s}\n", .{@errorName(err)});
        return;
    };
    defer extension_quarantine_mod.freeRecords(allocator, records);

    if (records.len == 0) {
        try out.print("(no quarantine records)\n", .{});
        return;
    }
    try out.print("{d} record(s):\n", .{records.len});
    for (records) |r| {
        const pk_prefix = if (r.signer_pubkey_hex.len >= 12) r.signer_pubkey_hex[0..12] else r.signer_pubkey_hex;
        try out.print("  {s}@{s} state={s} reason={s} pubkey={s} at={d}\n", .{
            r.extension_name, r.version, r.state.name(), r.reason.name(), pk_prefix, r.quarantined_at,
        });
    }
}

pub fn cmdExtensionQuarantineEvaluate(
    session: *Session,
    out: *const Output,
    namespace: []const u8,
    data_dir: []const u8,
) !void {
    // Resolve manifest from the data_dir.  REPL doesn't take flag args
    // so we always fall back to the canonical path.
    const allocator = session.allocator;
    const manifest_path = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(manifest_path);
    var manifest = tenant_manifest_mod.loadFromPath(allocator, manifest_path) catch |err| {
        try out.print("extension quarantine evaluate: failed to load manifest at {s}: {s}\n", .{ manifest_path, @errorName(err) });
        return;
    };
    defer manifest.deinit();

    const outcome = extension_quarantine_mod.evaluateQuarantine(
        allocator,
        data_dir,
        namespace,
        manifest.trusted_signers,
        session.dispatcher,
        session.audit,
    ) catch |err| {
        try out.print("extension quarantine evaluate: {s}\n", .{@errorName(err)});
        return;
    };

    try out.print("evaluate {s}: state={s} transitioned_to_active={s} no_op={s}\n  detail: {s}\n", .{
        namespace,
        outcome.state.name(),
        if (outcome.transitioned_to_active) "true" else "false",
        if (outcome.no_op) "true" else "false",
        outcome.detail,
    });
}

pub fn cmdExtensionQuarantineRemove(
    session: *Session,
    out: *const Output,
    namespace: []const u8,
    data_dir: []const u8,
) !void {
    const allocator = session.allocator;
    const records = extension_quarantine_mod.loadLatestRecords(allocator, data_dir) catch |err| {
        try out.print("extension quarantine remove: {s}\n", .{@errorName(err)});
        return;
    };
    defer extension_quarantine_mod.freeRecords(allocator, records);

    var matched: ?extension_quarantine_mod.QuarantineRecord = null;
    for (records) |r| {
        if (std.mem.eql(u8, r.extension_name, namespace)) {
            matched = r;
            break;
        }
    }
    if (matched == null) {
        try out.print("extension quarantine remove: no record for `{s}`\n", .{namespace});
        return;
    }
    if (matched.?.state == .active) {
        try out.print("extension quarantine remove: `{s}` is currently active.\n", .{namespace});
        return;
    }

    const removal = extension_quarantine_mod.QuarantineRecord{
        .extension_name = matched.?.extension_name,
        .version = matched.?.version,
        .signer_pubkey_hex = matched.?.signer_pubkey_hex,
        .state = .removed,
        .quarantined_at = std.time.timestamp(),
        .reason = .operator_remove,
        .original_install_path = matched.?.original_install_path,
        .previous_state = matched.?.state,
    };

    extension_quarantine_mod.hardRemove(
        allocator,
        data_dir,
        removal,
        session.dispatcher,
        session.audit,
    ) catch |err| {
        try out.print("extension quarantine remove: {s}\n", .{@errorName(err)});
        return;
    };

    try out.print("Removed {s} (version {s}) — bundle deleted, dispatcher unmarked, index record appended.\n", .{
        namespace,
        matched.?.version,
    });
}

// ─────────────────────────────────────────────────────────────────────
// Phase 3 — `submit-intent-cell` / `find intent-cells` / `find
// intent-cell <id>` REPL verbs.
//
// Reference: docs/spec/oddjobz-intent-cell-v1.md.
//
// `submit-intent-cell --envelope <base64-of-envelope-json>` is the
// load-bearing typed-NL transport.  The mobile half of this PR
// renders an outbox row's `payloadJson` (already a full envelope
// conforming to the spec) as `submit-intent-cell --envelope
// <base64(payloadJson)>` for the REPL transport — so we expect a
// base64-encoded envelope here, NOT raw JSON.  Base64 sidesteps the
// splitArgs tokenizer's whitespace + double-quote-stripping pain
// (operators / outbox flush adapters both win).
//
// Verbs:
//   submit-intent-cell --envelope <base64-of-envelope-json>
//   find intent-cells [--hat <id>] [--since <iso>] [--limit N]
//   find intent-cell <cell-id>
// ─────────────────────────────────────────────────────────────────────

pub fn cmdIntentCellsSubmit(session: *Session, out: *const Output, args: []const []const u8) !void {
    const disp = session.dispatcher orelse {
        try out.print("submit-intent-cell: no dispatcher attached to this REPL session.\n", .{});
        return;
    };

    var envelope_b64: []const u8 = "";
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--envelope") and i + 1 < args.len) {
            envelope_b64 = args[i + 1];
            i += 1;
        }
    }
    if (envelope_b64.len == 0) {
        try out.print("usage: submit-intent-cell --envelope <base64-of-envelope-json>\n", .{});
        return;
    }

    // Base64-decode once on the REPL side; the dispatcher gets the
    // raw envelope JSON wrapped as `{envelope_json:"<...>"}`.
    const decoder = std.base64.standard.Decoder;
    const max_len = decoder.calcSizeForSlice(envelope_b64) catch {
        try out.print("submit-intent-cell: --envelope value is not valid base64\n", .{});
        return;
    };
    const envelope_json = session.allocator.alloc(u8, max_len) catch return ReplError.out_of_memory;
    defer session.allocator.free(envelope_json);
    decoder.decode(envelope_json, envelope_b64) catch {
        try out.print("submit-intent-cell: --envelope value is not valid base64\n", .{});
        return;
    };

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(session.allocator);
    try buf.appendSlice(session.allocator, "{\"envelope_json\":");
    {
        const enc = try std.json.Stringify.valueAlloc(session.allocator, envelope_json, .{});
        defer session.allocator.free(enc);
        try buf.appendSlice(session.allocator, enc);
    }
    try buf.append(session.allocator, '}');

    return dispatchIntentCells(session, disp, out, "submit", buf.items);
}

pub fn cmdIntentCellsFind(session: *Session, out: *const Output, args: []const []const u8) !void {
    const disp = session.dispatcher orelse {
        try out.print("find intent-cells: no dispatcher attached to this REPL session.\n", .{});
        return;
    };

    var hat_filter: ?[]const u8 = null;
    var since_filter: ?[]const u8 = null;
    var limit_filter: ?usize = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--hat") and i + 1 < args.len) {
            hat_filter = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--since") and i + 1 < args.len) {
            since_filter = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--limit") and i + 1 < args.len) {
            limit_filter = std.fmt.parseInt(usize, args[i + 1], 10) catch null;
            i += 1;
        }
    }

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(session.allocator);
    try buf.append(session.allocator, '{');
    var wrote_any = false;
    if (hat_filter) |s| {
        try buf.appendSlice(session.allocator, "\"hat_id\":");
        const enc = try std.json.Stringify.valueAlloc(session.allocator, s, .{});
        defer session.allocator.free(enc);
        try buf.appendSlice(session.allocator, enc);
        wrote_any = true;
    }
    if (since_filter) |s| {
        if (wrote_any) try buf.append(session.allocator, ',');
        try buf.appendSlice(session.allocator, "\"since\":");
        const enc = try std.json.Stringify.valueAlloc(session.allocator, s, .{});
        defer session.allocator.free(enc);
        try buf.appendSlice(session.allocator, enc);
        wrote_any = true;
    }
    if (limit_filter) |n| {
        if (wrote_any) try buf.append(session.allocator, ',');
        try buf.print(session.allocator, "\"limit\":{d}", .{n});
    }
    try buf.append(session.allocator, '}');

    return dispatchIntentCells(session, disp, out, "find", buf.items);
}

pub fn cmdIntentCellsFindById(session: *Session, out: *const Output, id: []const u8) !void {
    const disp = session.dispatcher orelse {
        try out.print("find intent-cell: no dispatcher attached to this REPL session.\n", .{});
        return;
    };
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(session.allocator);
    try buf.appendSlice(session.allocator, "{\"cell_id\":");
    const enc = try std.json.Stringify.valueAlloc(session.allocator, id, .{});
    defer session.allocator.free(enc);
    try buf.appendSlice(session.allocator, enc);
    try buf.append(session.allocator, '}');
    return dispatchIntentCells(session, disp, out, "find_by_id", buf.items);
}

fn dispatchIntentCells(
    session: *Session,
    disp: *dispatcher_mod.Dispatcher,
    out: *const Output,
    cmd: []const u8,
    args_json: []const u8,
) !void {
    _ = session;
    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "intent_cells", cmd, args_json) catch |err| {
        try out.print("intent_cells.{s}: dispatch failed: {s}\n", .{ cmd, @errorName(err) });
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) {
        try out.print("{s}\n", .{result.payload});
    }
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-5 — `site config show / set / validate` REPL verbs.
//
// Reference: docs/canon/deliverables.yml D-O5.followup-5.
//
// Each verb dispatches through `session.dispatcher`'s `site_config`
// resource (see resources/site_config_handler.zig).  Output is piped
// verbatim — `show` returns the on-disk JSON inside a `{domain, json,
// size, mtime_unix}` envelope; `set` returns `{ok:true,written_at:N}`
// on success or a typed error on validation failure; `validate` is
// `set` with `dry_run:true`, returning `{ok:true,dry_run:true}` on
// success.
//
// REPL UX caveats:
//   • The splitArgs tokenizer is whitespace-only.  `site config set
//     <domain> <json>` therefore requires the JSON blob to contain no
//     unescaped spaces.  In practice operators using this verb are
//     piping pre-minified JSON; the helm SPA editor (the primary
//     surface) bypasses this entirely.
//   • The `<json>` is a single argument — everything after the domain
//     gets concatenated back together with single-space separators on
//     the way out, so newline-formatted JSON dropped into the REPL
//     loses its whitespace but stays valid.
// ─────────────────────────────────────────────────────────────────────

pub fn cmdSiteConfigShow(session: *Session, out: *const Output, args: []const []const u8) !void {
    if (args.len < 1) {
        try out.print("usage: site config show <domain>\n", .{});
        return;
    }
    const disp = session.dispatcher orelse {
        try out.print("site config show: no dispatcher attached to this REPL session.\n", .{});
        return;
    };
    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(session.allocator);
    try args_buf.appendSlice(session.allocator, "{\"domain\":");
    {
        const enc = try std.json.Stringify.valueAlloc(session.allocator, args[0], .{});
        defer session.allocator.free(enc);
        try args_buf.appendSlice(session.allocator, enc);
    }
    try args_buf.append(session.allocator, '}');
    return dispatchSiteConfig(session, disp, out, "read", args_buf.items);
}

pub fn cmdSiteConfigSet(session: *Session, out: *const Output, args: []const []const u8) !void {
    if (args.len < 2) {
        try out.print("usage: site config set <domain> <json>\n", .{});
        try out.print("       (json must be a single whitespace-free token; the helm SPA editor is the primary surface)\n", .{});
        return;
    }
    const disp = session.dispatcher orelse {
        try out.print("site config set: no dispatcher attached to this REPL session.\n", .{});
        return;
    };
    const json_blob = try joinRest(session.allocator, args[1..]);
    defer session.allocator.free(json_blob);

    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(session.allocator);
    try args_buf.appendSlice(session.allocator, "{\"domain\":");
    {
        const enc = try std.json.Stringify.valueAlloc(session.allocator, args[0], .{});
        defer session.allocator.free(enc);
        try args_buf.appendSlice(session.allocator, enc);
    }
    try args_buf.appendSlice(session.allocator, ",\"json\":");
    {
        const enc = try std.json.Stringify.valueAlloc(session.allocator, json_blob, .{});
        defer session.allocator.free(enc);
        try args_buf.appendSlice(session.allocator, enc);
    }
    try args_buf.append(session.allocator, '}');
    return dispatchSiteConfig(session, disp, out, "write", args_buf.items);
}

pub fn cmdSiteConfigValidate(session: *Session, out: *const Output, args: []const []const u8) !void {
    if (args.len < 2) {
        try out.print("usage: site config validate <domain> <json>\n", .{});
        return;
    }
    const disp = session.dispatcher orelse {
        try out.print("site config validate: no dispatcher attached to this REPL session.\n", .{});
        return;
    };
    const json_blob = try joinRest(session.allocator, args[1..]);
    defer session.allocator.free(json_blob);

    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(session.allocator);
    try args_buf.appendSlice(session.allocator, "{\"domain\":");
    {
        const enc = try std.json.Stringify.valueAlloc(session.allocator, args[0], .{});
        defer session.allocator.free(enc);
        try args_buf.appendSlice(session.allocator, enc);
    }
    try args_buf.appendSlice(session.allocator, ",\"dry_run\":true,\"json\":");
    {
        const enc = try std.json.Stringify.valueAlloc(session.allocator, json_blob, .{});
        defer session.allocator.free(enc);
        try args_buf.appendSlice(session.allocator, enc);
    }
    try args_buf.append(session.allocator, '}');
    return dispatchSiteConfig(session, disp, out, "write", args_buf.items);
}

/// Concatenate trailing-arg tokens with single-space separators.  The
/// REPL splitArgs tokeniser splits on whitespace, so a pasted JSON
/// blob that survives shell quoting still arrives as N tokens we have
/// to glue back together.  The result still loses whitespace inside
/// the JSON, but JSON parsers are insensitive to that.
fn joinRest(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    if (parts.len == 0) return try allocator.dupe(u8, "");
    var total: usize = 0;
    for (parts) |p| total += p.len + 1; // +1 for separator
    var buf = try allocator.alloc(u8, total - 1);
    var pos: usize = 0;
    for (parts, 0..) |p, i| {
        if (i != 0) {
            buf[pos] = ' ';
            pos += 1;
        }
        @memcpy(buf[pos..][0..p.len], p);
        pos += p.len;
    }
    return buf;
}

fn dispatchSiteConfig(
    session: *Session,
    disp: *dispatcher_mod.Dispatcher,
    out: *const Output,
    cmd: []const u8,
    args_json: []const u8,
) !void {
    _ = session;
    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "site_config", cmd, args_json) catch |err| {
        try out.print("site_config.{s}: dispatch failed: {s}\n", .{ cmd, @errorName(err) });
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) {
        try out.print("{s}\n", .{result.payload});
    }
}

/// Unblocker #39 — REPL `cells mint <json>` verb.
///
/// Routes through the dispatcher's `cells` resource → `mint` command
/// (registered in serve.zig via
/// `cells_mint_handler.Handler.resourceHandler`). The HTTP path
/// reaches the same handler via `reactor.zig`'s POST /api/v1/cells +
/// the PR-8b-ix `dispatch_input_cell_fn` thunk, so REPL + HTTP both
/// run the full pipeline (Context builder → handler script → extra
/// cells push → emits-allowlist walker).
///
/// JSON-with-whitespace caveat: the splitArgs tokeniser splits on
/// whitespace, so a pasted JSON body that survives shell quoting
/// arrives as N tokens. `joinRest` glues them back with single
/// spaces; JSON parsers are insensitive to that. Operators wanting
/// to avoid the tokenising hassle can paste base64'd JSON + use a
/// helper (deferred — for now, ensure your JSON arg has no
/// whitespace before pasting).
///
/// Usage:
///   cells mint {"typeHashHex":"<64hex>","payload":{...}}
///   cells mint {"typeHashHex":"<64hex>","payloadBytesHex":"<hex>"}
pub fn cmdCellsMint(session: *Session, out: *const Output, args: []const []const u8) !void {
    if (args.len < 1) {
        try out.print("usage: cells mint <json>\n", .{});
        try out.print("       json shape: {{\"typeHashHex\":\"<64hex>\",(\"payload\":{{...}}|\"payloadBytesHex\":\"<hex>\")}}\n", .{});
        return;
    }
    const disp = session.dispatcher orelse {
        try out.print("cells mint: no dispatcher attached to this REPL session.\n", .{});
        return;
    };
    const json_blob = try joinRest(session.allocator, args);
    defer session.allocator.free(json_blob);

    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "cells", "mint", json_blob) catch |err| {
        try out.print("cells.mint: dispatch failed: {s}\n", .{@errorName(err)});
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) {
        try out.print("{s}\n", .{result.payload});
    }
}

```
