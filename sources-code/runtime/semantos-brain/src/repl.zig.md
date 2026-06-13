---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/repl.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.258473+00:00
---

# runtime/semantos-brain/src/repl.zig

```zig
// Phase Brain 3 — TUI REPL.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 3).
//
// Operator-facing line-based shell.  Reads commands from stdin (or any
// reader the caller supplies for tests), dispatches to a small set of
// command handlers, prints responses to stdout (or a captured buffer).
// History persists to `<data-dir>/history`.
//
// D-W1 Phase 0 (this PR): repl is the **first transport** to drive the
// new brain dispatcher.  When `Session.dispatcher` is non-null,
// `handleLine` parses the operator's typed line into a (resource, cmd,
// args) triple and routes the three migrated commands — `status`,
// `help`/`?`, `exit`/`quit` — through `dispatcher.dispatch` with
// `AuthContext.in_process_root`.  The shim handler for the `repl`
// resource (registered via `registerReplShims`) calls the existing
// cmdStatus/cmdHelp paths internally on a captured buffer; the captured
// bytes pass through verbatim to the operator's writer, so output is
// byte-identical to the pre-Phase-0 direct-call path.
//
// All other repl commands (modules, audit, call, hash, history, clear,
// deferred-engine commands, unknown) keep the legacy direct-dispatch
// path until their migration deliverables land in Phase 1+ per
// docs/design/BRAIN-DISPATCHER-UNIFICATION.md §8.
//
// Scope decisions for v0.1:
//
//   • No raw-mode terminal handling.  Operators wanting up-arrow recall
//     can wrap with `rlwrap`.  Tab completion + arrow-key history are
//     deferred to Brain 3.5; they need raw mode + a small line-editor
//     library and aren't on the critical path for "operator can
//     interact with the wallet".
//
//   • Commands fall in two tiers:
//       - **Diagnostic / direct-WASM** (ship now): help, status,
//         modules, audit, call, hash, history, clear, exit.
//       - **Engine-surface** (deferred to Brain 3.5+ — need wallet-engine
//         BRC-100 method calls or richer kernel exports):
//         identity, balance, send, anchor, policy, recover, sync.
//     The deferred commands print "not yet wired" with a pointer to
//     the Brain 3.5 doc — better than silently missing.
//
//   • `call <module> <export>` works only in wasmtime-enabled builds.
//     v0.1 supports no-arg exports returning a single i32; richer
//     arg parsing lands when more interesting kernel exports surface.

const std = @import("std");
const build_options = @import("build_options");
const config_mod = @import("config");
const audit_log_mod = @import("audit_log");
const broker_mod = @import("broker");
const instance_manager = @import("instance_manager");
const module_loader = @import("module_loader");
const runner_mod = @import("runner");
const header_store_mod = @import("header_store");
const wasmtime_backend = @import("wasmtime_backend");
const dispatcher_mod = @import("dispatcher");
const verb_schema = @import("verb_schema"); // C4 PR-R2 — generic-verb REPL path
const do_verb_registry = @import("do_verb_registry"); // DO-1 — `do <verb> <resource> <target>` grammar
// D-W1 Phase 1 Part 2 + Phase 1 follow-up — `device list / revoke /
// pair / claim` REPL verbs dispatch into the same identity_certs +
// device_pair surface the CLI hits.
const identity_certs_mod = @import("identity_certs");
const identity_certs_handler_mod = @import("identity_certs_handler");
const bkds_mod = @import("bkds");
const bsvz_mod = @import("bsvz");
const device_pair_mod = @import("device_pair");
// D-W2 Phase 4 — REPL mirrors for `extension quarantine list/
// evaluate/remove`.  Pattern matches the existing `device list/pair/
// revoke` surface.  See BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
// §7 Phase 4 + cli.zig's cmdExtensionQuarantine.
const extension_quarantine_mod = @import("extension_quarantine");
const tenant_manifest_mod = @import("tenant_manifest");
// C4 PR-J6 — the `leads` REPL verbs + the `leads` dispatcher resource were
// deleted (orphaned, superseded by job.v2 state:"lead"; a lead is created via
// `add job ... state:lead` / ratify, not a separate leads store).
// Phase 3 — typed `submit-intent-cell --envelope <base64-json>`,
// `find intent-cells [--hat X] [--since iso] [--limit N]`,
// `find intent-cell <cell-id>` REPL verbs route through the
// dispatcher's `intent_cells` resource.  See docs/spec/oddjobz-
// intent-cell-v1.md for the wire format.
const intent_cells_store_fs_mod = @import("intent_cells_store_fs");
const intent_cells_handler_mod = @import("intent_cells_handler");

// Phase 1 of the repl.zig modularize — public types extracted to
// src/repl/types.zig.  Re-exported here so external callers (the
// cli.cmdRepl glue, tests) keep reaching them as `repl.X`.
const types = @import("repl/types.zig");
pub const ReplError = types.ReplError;
pub const Session = types.Session;
pub const NamedInstance = types.NamedInstance;
pub const Output = types.Output;
pub const ReplExit = types.ReplExit;

// admin-create-cell Phase B — generic, cartridge-agnostic verbs
// (admin create-cell ...) that operate on any cartridge's declared
// types via the schema reader in src/cartridge_schema.zig. The
// REPL skeleton lands here; persistence wires in Phase D.
const admin_cmds = @import("repl/admin_cmds.zig");
const cmdAdmin = admin_cmds.cmdAdmin;

// C4 PR-R3h — the oddjobz resource cmd verbs all moved to the cartridge's
// ReplVerbRegistry; only the conversation-turns substrate verb (`find turns`)
// remains brain-native (renamed src/repl/oddjobz_cmds.zig → conv_turns_cmd.zig).
const conv_turns_cmd = @import("repl/conv_turns_cmd.zig");
const cmdConvTurnsFind = conv_turns_cmd.cmdConvTurnsFind;

// Phase 3 — extension / intent_cells / site_config REPL verbs
// extracted to src/repl/extra_cmds.zig. (C4 PR-J6: the leads verbs were deleted.)
const extra_cmds = @import("repl/extra_cmds.zig");
const cmdExtension = extra_cmds.cmdExtension;
const cmdExtensionQuarantineList = extra_cmds.cmdExtensionQuarantineList;
const cmdExtensionQuarantineEvaluate = extra_cmds.cmdExtensionQuarantineEvaluate;
const cmdExtensionQuarantineRemove = extra_cmds.cmdExtensionQuarantineRemove;
const cmdIntentCellsSubmit = extra_cmds.cmdIntentCellsSubmit;
const cmdIntentCellsFind = extra_cmds.cmdIntentCellsFind;
const cmdIntentCellsFindById = extra_cmds.cmdIntentCellsFindById;
const cmdSiteConfigShow = extra_cmds.cmdSiteConfigShow;
const cmdSiteConfigSet = extra_cmds.cmdSiteConfigSet;
const cmdSiteConfigValidate = extra_cmds.cmdSiteConfigValidate;
const cmdCellsMint = extra_cmds.cmdCellsMint;

// Phase 4 — device + headers REPL verbs extracted to src/repl/device_cmds.zig.
const device_cmds = @import("repl/device_cmds.zig");
const cmdDevice = device_cmds.cmdDevice;
const cmdHeaders = device_cmds.cmdHeaders;

// Phase 5 — LLM completion REPL verb extracted to src/repl/llm_cmds.zig.
// `llm complete <scope> <base64-args>` routes AI requests through the
// brain's llm_complete_handler (with per-scope rate-limiting + budget
// tracking) instead of calling the Anthropic API from the client side.
// Removes ANTHROPIC_API_KEY from the mobile APK.
const llm_cmds = @import("repl/llm_cmds.zig");
const cmdLlm = llm_cmds.cmdLlm;

// ─────────────────────────────────────────────────────────────────────
// Public entry points
// ─────────────────────────────────────────────────────────────────────

/// Process one line of input. Returns `quit` if the loop should exit.
/// Callers (the actual REPL loop in main.zig + tests) drive this with
/// captured I/O.
pub fn handleLine(
    session: *Session,
    out: *const Output,
    line: []const u8,
) !ReplExit {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return .@"continue";

    var args_buf: [16][]const u8 = undefined;
    const argc = splitArgs(trimmed, &args_buf);
    if (argc == 0) return .@"continue";

    const cmd = args_buf[0];
    const rest = args_buf[1..argc];

    // D-W1 Phase 0 — when a dispatcher is configured, route the three
    // migrated commands (status, help, exit) through it.  The shim
    // handler internally calls cmdStatus / cmdHelp / writes "bye."
    // and returns the rendered bytes via Result.payload, which we
    // print verbatim — output is byte-identical to the legacy path.
    if (session.dispatcher) |disp| {
        if (asReplDispatcherRoute(cmd)) |route| {
            return try dispatchRepl(disp, out, route.cmd);
        }
    }

    if (matches(cmd, "help") or matches(cmd, "?")) {
        try cmdHelp(session, out);
        return .@"continue";
    }
    if (matches(cmd, "exit") or matches(cmd, "quit")) {
        try out.print("bye.\n", .{});
        return .quit;
    }
    if (matches(cmd, "status")) {
        try cmdStatus(session, out);
        return .@"continue";
    }
    if (matches(cmd, "modules")) {
        try cmdModules(session, out);
        return .@"continue";
    }
    if (matches(cmd, "audit")) {
        try cmdAudit(session, out, rest);
        return .@"continue";
    }
    if (matches(cmd, "call")) {
        try cmdCall(session, out, rest);
        return .@"continue";
    }
    // The shell-native substrate query primitive (find → cell.query). Available
    // for ANY cartridge-registered cell type; the body `find` becomes.
    if (matches(cmd, "query")) {
        try cmdQuery(session, out, rest);
        return .@"continue";
    }
    if (matches(cmd, "hash")) {
        try cmdHash(session, out, rest);
        return .@"continue";
    }
    if (matches(cmd, "history")) {
        try cmdHistory(session, out, rest);
        return .@"continue";
    }
    if (matches(cmd, "clear")) {
        // ANSI clear screen + cursor home.
        try out.print("\x1b[2J\x1b[H", .{});
        return .@"continue";
    }

    // D-W1 Phase 1 Part 2 — `device list` / `device revoke <id>`
    // dispatch through the session's identity_certs handler when one is
    // attached.  When the dispatcher (or the cert handler) isn't wired
    // (e.g. legacy fixtures) we print a hint pointing at `brain device`.
    if (matches(cmd, "device")) {
        try cmdDevice(session, out, rest);
        return .@"continue";
    }

    // D-W2 Phase 4 — REPL mirrors of `brain extension quarantine
    // list/evaluate/remove`.  Same disk-side semantics; different
    // surface for operators driving from the live REPL.
    if (matches(cmd, "extension")) {
        try cmdExtension(session, out, rest);
        return .@"continue";
    }

    // admin-create-cell Phase B — generic verbs operating on any
    // installed cartridge's declared types via the schema reader.
    // Phase B prints stub output; Phase D wires persistence.
    if (matches(cmd, "admin")) {
        try cmdAdmin(session, out, rest);
        return .@"continue";
    }

    // D-W1 Phase 2 — `headers tip` mirrors `brain headers tip`.  Reads
    // the session's borrowed header_store directly rather than going
    // through dispatch (the REPL's in_process_root auth bypass makes
    // the seam behaviourally equivalent — the dispatch wrapper would
    // just add an audit line; the cap.none check passes either way).
    // Output is byte-identical to the CLI form so an operator
    // switching between `brain headers tip` (terminal) and `headers tip`
    // (REPL) sees the same line shape.
    if (matches(cmd, "headers")) {
        try cmdHeaders(session, out, rest);
        return .@"continue";
    }







    // C4 PR-J6 — the typed `leads` REPL verbs (find leads / find lead / add lead
    // / ratify|reject|defer|transition lead) were deleted along with the orphaned
    // `leads` dispatcher resource. A lead is now a job.v2 in state "lead" — use
    // the `job` verbs (e.g. `add job … state:lead`) + the ratify pipeline.

    // D-OJ-conv-turns-query — conversation turns query verbs.
    //   find turns job <id>    → resolve job cellHash, query Postgres turns
    //   find turns conv <id>   → query turns by conversationId directly
    // Requires --oddjobz-conv-turns-query-script at serve time.
    if (matches(cmd, "find") and rest.len >= 2 and matches(rest[0], "turns")) {
        if (matches(rest[1], "job") and rest.len >= 3) {
            try cmdConvTurnsFind(session, out, "job", rest[2]);
            return .@"continue";
        }
        if (matches(rest[1], "conv") and rest.len >= 3) {
            try cmdConvTurnsFind(session, out, "conv", rest[2]);
            return .@"continue";
        }
        try out.print("usage: find turns job <id>  |  find turns conv <conversation-id>\n", .{});
        return .@"continue";
    }

    // Phase 3 — typed-NL intent-cell verbs.  `submit-intent-cell
    // --envelope <base64-json>` accepts a base64-encoded envelope
    // (operator-friendly: lets us paste JSON without escaping shell
    // hell), wraps it as `{"envelope_json":"<decoded>"}`, dispatches
    // through `intent_cells.submit`.  `find intent-cells [--hat X]
    // [--since iso] [--limit N]` and `find intent-cell <cell-id>`
    // route through `intent_cells.find` and `intent_cells.find_by_id`.
    if (matches(cmd, "submit-intent-cell")) {
        try cmdIntentCellsSubmit(session, out, rest);
        return .@"continue";
    }
    if (matches(cmd, "find") and rest.len >= 1 and matches(rest[0], "intent-cells")) {
        try cmdIntentCellsFind(session, out, rest[1..]);
        return .@"continue";
    }
    if (matches(cmd, "find") and rest.len >= 2 and matches(rest[0], "intent-cell")) {
        try cmdIntentCellsFindById(session, out, rest[1]);
        return .@"continue";
    }

    // D-O5.followup-5 — `site config show <domain>` / `site config set
    // <domain> <json>` / `site config validate <domain> <json>` REPL
    // verbs route through the dispatcher's `site_config` resource.
    // The helm SPA editor view is the primary surface for `set`; the
    // REPL form exists so an operator can drop into a daemon and
    // poke at the config without booting a browser.  Raw JSON in the
    // REPL is awkward (whitespace bites the splitArgs tokenizer) —
    // operators wanting to author by hand can use `brain site init` +
    // `brain site route_add` from sites_handler instead.  This verb is
    // for read-and-paste workflows: pipe `site config show` output
    // into a file, edit, paste back as `site config set <domain>
    // <json>`.
    if (matches(cmd, "site") and rest.len >= 2 and matches(rest[0], "config") and matches(rest[1], "show")) {
        try cmdSiteConfigShow(session, out, rest[2..]);
        return .@"continue";
    }
    if (matches(cmd, "site") and rest.len >= 2 and matches(rest[0], "config") and matches(rest[1], "set")) {
        try cmdSiteConfigSet(session, out, rest[2..]);
        return .@"continue";
    }
    if (matches(cmd, "site") and rest.len >= 2 and matches(rest[0], "config") and matches(rest[1], "validate")) {
        try cmdSiteConfigValidate(session, out, rest[2..]);
        return .@"continue";
    }

    // Unblocker #39 — `cells mint <json>` routes through the
    // dispatcher's `cells` resource registered by the brain's mint
    // handler in serve.zig. Mirrors the HTTP path that reactor.zig
    // reaches via the PR-8b-ix `dispatch_input_cell_fn` thunk, so
    // both surfaces run the full pipeline (Context builder →
    // handler script → extra cells push → emits walker).
    //
    // Pre-PR-39 the dispatcher resource was registered but
    // unreachable from the REPL (the cmd parser fell through to
    // "unknown command: cells"). Now operators can mint substrate
    // cells without standing up an HTTP client.
    if (matches(cmd, "cells") and rest.len >= 1 and matches(rest[0], "mint")) {
        try cmdCellsMint(session, out, rest[1..]);
        return .@"continue";
    }

    // Phase 5 — `llm complete <scope> <base64-args>` AI proxy verb.
    // Routes requests through the brain's llm_complete_handler so the
    // mobile APK and helm do not need to hold an ANTHROPIC_API_KEY.
    if (matches(cmd, "llm")) {
        try cmdLlm(session, out, rest);
        return .@"continue";
    }

    // Engine-surface commands deferred to Brain 3.5.
    if (isDeferredEngineCommand(cmd)) {
        try out.print("`{s}` is on the Brain 3.5 roadmap (engine surface).\n", .{cmd});
        try out.print("Use `call <module> <export>` to invoke wasmtime exports today.\n", .{});
        return .@"continue";
    }

    // DO-1 — the `do` operator-action grammar: `do <verb> <resource> <target>
    // [k=v…]`. Routes through the do_verb_registry → dispatcher (cap/audit). Bare
    // `do` or an unknown triple prints the registered verbs.
    if (matches(cmd, "do")) {
        if (try tryDoVerb(session, out, rest)) return .@"continue";
    }

    // C4 PR-R3 — cartridge-registered REPL verb forms (`find jobs`, `jobs quote`).
    // Consulted after the (shrinking) hardcoded branches; as R3 deletes each
    // hardcoded oddjobz branch, the cartridge's registered verb takes over.
    if (rest.len >= 1 and session.dispatcher != null) {
        if (session.repl_verb_registry) |reg| {
            if (reg.find(cmd, rest[0])) |v| {
                try v.handler(session.allocator, session.dispatcher.?, out, rest[1..]);
                return .@"continue";
            }
        }
    }

    // C4 PR-R2 — generic `<resource> <verb> [--k v|k=v|positional]` path. Any
    // dispatcher resource that self-describes its verbs (verbs_fn) is REPL-
    // driveable with no per-cartridge verb code in the brain. Runs AFTER the
    // legacy sugar branches (which use the `<verb> <resource>` form, e.g.
    // `find jobs`), so it only catches the generic `<resource> <verb>` form.
    if (rest.len >= 1) {
        if (try tryGenericVerb(session, out, cmd, rest[0], rest[1..])) return .@"continue";
    }

    try out.print("unknown command: {s}\n", .{cmd});
    try out.print("type `help` for the list.\n", .{});
    return .@"continue";
}

/// C4 PR-R2 — generic `<resource> <verb> [args]` dispatch. Returns true if it
/// handled the line (recognized resource): resolves the resource's verb schema
/// (verbs_fn), parses `args` into the dispatch envelope, dispatches, and prints
/// the result. Returns false if `resource` isn't a registered self-describing
/// resource, so handleLine falls through to "unknown command".
fn tryGenericVerb(
    session: *Session,
    out: *const Output,
    resource: []const u8,
    verb: []const u8,
    args: []const []const u8,
) !bool {
    const disp = session.dispatcher orelse return false;
    const rh = disp.findHandler(resource) orelse return false;
    const specs = rh.verbs();
    if (specs.len == 0) return false; // resource doesn't self-describe → not generic-driveable
    const vspec = verb_schema.findVerb(specs, verb) orelse {
        try out.print("{s}: unknown verb '{s}'\n", .{ resource, verb });
        return true;
    };
    const json = verb_schema.buildEnvelope(session.allocator, vspec, args) catch |err| {
        try out.print("{s} {s}: bad args ({s})\n", .{ resource, verb, @errorName(err) });
        return true;
    };
    defer session.allocator.free(json);

    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, resource, verb, json) catch |err| {
        try out.print("{s}.{s}: dispatch failed: {s}\n", .{ resource, verb, @errorName(err) });
        return true;
    };
    defer result.deinit();
    if (result.payload.len > 0) try out.print("{s}\n", .{result.payload});
    return true;
}

/// DO-1 — the `do` operator-action grammar. `toks` is the line minus the leading
/// `do`: `[verb, resource, target, k=v…]`. Looks the triple up in the
/// do_verb_registry and dispatches its read command through the dispatcher
/// (cap-gated + audited). Bare `do` / short / unknown triples print the
/// registered verbs. Returns true once it has produced output (always, when a
/// registry is present), so handleLine doesn't fall through to "unknown command".
fn tryDoVerb(
    session: *Session,
    out: *const Output,
    toks: []const []const u8,
) !bool {
    const disp = session.dispatcher orelse return false;
    const reg = session.do_verb_registry orelse return false;

    if (toks.len < 3) {
        try printDoVerbs(out, reg);
        return true;
    }
    const dv = reg.find(toks[0], toks[1], toks[2]) orelse {
        try out.print("unknown do verb: do {s} {s} {s}\n", .{ toks[0], toks[1], toks[2] });
        try printDoVerbs(out, reg);
        return true;
    };

    // DO-2 — no k=v args → read_command (show); k=v args → write_command (set).
    var command = dv.read_command;
    var json: []const u8 = "{}";
    var owned_json: ?[]u8 = null;
    defer if (owned_json) |j| session.allocator.free(j);
    if (toks.len > 3) {
        if (dv.write_command.len == 0) {
            try out.print("do {s} {s} {s}: read-only (no set form)\n", .{ dv.verb, dv.resource, dv.target });
            return true;
        }
        owned_json = buildDoArgsJson(session.allocator, toks[3..]) catch |err| {
            try out.print("do {s} {s} {s}: bad args ({s}) — use k=v (single-token values)\n", .{ dv.verb, dv.resource, dv.target, @errorName(err) });
            return true;
        };
        json = owned_json.?;
        command = dv.write_command;
    }

    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, dv.dispatch_resource, command, json) catch |err| {
        try out.print("do {s} {s} {s}: dispatch failed: {s}\n", .{ dv.verb, dv.resource, dv.target, @errorName(err) });
        return true;
    };
    defer result.deinit();
    if (result.payload.len > 0) try out.print("{s}\n", .{result.payload});
    return true;
}

/// DO-2 — build a JSON object from `do` k=v args: `[enabled=false, endpoint=/x]`
/// → `{"enabled":"false","endpoint":"/x"}` (all string values; the handler
/// coerces). Single-token values only (the REPL line splitter is space-based);
/// multi-word copy goes through a direct JSON dispatch. A token without `=` errors.
fn buildDoArgsJson(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '{');
    var first = true;
    for (args) |tok| {
        const eq = std.mem.indexOfScalar(u8, tok, '=') orelse return error.bad_arg;
        if (!first) try buf.append(allocator, ',');
        first = false;
        try appendJsonStr(allocator, &buf, tok[0..eq]);
        try buf.append(allocator, ':');
        try appendJsonStr(allocator, &buf, tok[eq + 1 ..]);
    }
    try buf.append(allocator, '}');
    return buf.toOwnedSlice(allocator);
}

fn appendJsonStr(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    const enc = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(enc);
    try buf.appendSlice(allocator, enc);
}

fn printDoVerbs(out: *const Output, reg: *const do_verb_registry.DoVerbRegistry) !void {
    const verbs = reg.all();
    if (verbs.len == 0) {
        try out.print("no `do` verbs registered.\n", .{});
        return;
    }
    try out.print("do verbs (operator actions):\n", .{});
    for (verbs) |v| {
        try out.print("  do {s} {s} {s}  — {s}\n", .{ v.verb, v.resource, v.target, v.summary });
    }
}

const matches = types.matches;

fn isDeferredEngineCommand(cmd: []const u8) bool {
    const deferred = [_][]const u8{
        "identity", "balance", "send", "anchor",
        "policy",   "recover", "sync",
    };
    for (deferred) |d| {
        if (matches(cmd, d)) return true;
    }
    return false;
}

/// Split a trimmed line into whitespace-separated tokens with double-
/// quote support. Returns the number of tokens written to `out_args`.
/// Tokens are slices into the input — the caller must keep `line` alive
/// for the dispatch. Quoted tokens point into the inside of the quotes
/// (the quote characters themselves are stripped from the slice).
/// Public for conformance testing; not part of the dispatch surface.
pub fn splitArgs(line: []const u8, out_args: [][]const u8) usize {
    // Whitespace tokeniser with double-quote support. A `"..."` group
    // is one token even if it contains spaces; the quotes themselves
    // are stripped from the resulting slice. Single quotes are NOT
    // special (operators paste JSON as-is). Escapes inside quotes are
    // out of scope — pasting a literal `"` inside a quoted string is
    // not supported; if you need it, dispatch over HTTP-REPL where the
    // payload is JSON. Mismatched (unclosed) quotes fall through: the
    // partial token runs to end-of-line. This matches shell-style
    // tolerance and keeps the dispatch path forgiving — the typed
    // resource will surface a domain error if the args make no sense.
    var n: usize = 0;
    var i: usize = 0;
    while (i < line.len and n < out_args.len) {
        // skip whitespace
        while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
        if (i >= line.len) break;
        if (line[i] == '"') {
            // quoted token — content runs from the byte after the opening
            // quote until the matching `"` or end-of-line (unclosed).
            i += 1;
            const start = i;
            while (i < line.len and line[i] != '"') i += 1;
            out_args[n] = line[start..i];
            // step over the closing quote when present
            if (i < line.len) i += 1;
            n += 1;
        } else {
            const start = i;
            while (i < line.len and line[i] != ' ' and line[i] != '\t') i += 1;
            out_args[n] = line[start..i];
            n += 1;
        }
    }
    return n;
}

// ─────────────────────────────────────────────────────────────────────
// Command implementations
// ─────────────────────────────────────────────────────────────────────

const HELP_TEXT =
    \\brain REPL — sovereign-node host shell
    \\
    \\Commands:
    \\  help                    list commands
    \\  status                  show broker + module + tip state
    \\  modules                 list loaded modules + hashes + state
    \\  audit [N]               tail last N audit-log lines (default 20)
    \\  call <mod> <export>     invoke a wasmtime export (no-arg, returns i32)
    \\  hash <file>             SHA-256 of a WASM file
    \\  history [N]             show last N commands (default 20)
    \\  clear                   clear screen
    \\  device list             list root + child identity certs (D-W1 P1.2)
    \\  device pair <name> [caps]  build + sign 5-min one-shot pairing payload (D-W1 P1.followup)
    \\  device claim <token>    LAB FIXTURE: simulate device side of pair handshake
    \\  device revoke <id>      revoke a child cert by id (D-W1 P1.2)
    \\  headers tip             show current header chain tip (D-W1 P2)
    \\  find turns job|conv <id>  query conversation turns (Postgres via bun)
    \\  <resource> <verb> [--k v]  generic dispatch — drives ANY registered
    \\                          dispatcher resource (jobs/customers/visits/quotes/
    \\                          estimates/invoices/attachments + cartridge verbs).
    \\                          e.g. `jobs find --state lead`, `customers find_by_id <id>`.
    \\                          Cartridge-registered verb forms (find jobs, add
    \\                          customer, jobs quote …) are listed under
    \\                          "Cartridge verbs" below.
    \\  site config show <domain>
    \\                          read on-disk site.json for the given domain (D-O5.followup-5)
    \\  site config set <domain> <json>
    \\                          atomically replace site.json with the supplied blob (validates first)
    \\  site config validate <domain> <json>
    \\                          dry-run validation only (no disk write)
    \\  llm complete <scope> <base64-args>
    \\                          route AI text completion through brain
    \\                          (removes ANTHROPIC_API_KEY from APK/helm)
    \\                          base64-args = base64(JSON {prompt,
    \\                          system_prompt?, max_tokens?, temperature?})
    \\  llm vision <scope> <base64-args>
    \\                          route AI vision (image→text) through brain
    \\                          base64-args = base64(JSON {image_b64,
    \\                          media_type?, prompt?, system_prompt?,
    \\                          max_tokens?})
    \\  exit / quit             leave REPL
    \\
    \\Reserved for Brain 3.5+ (engine surface):
    \\  identity, balance, send, anchor, policy, recover, sync
    \\
;

pub fn cmdHelp(session: *Session, out: *const Output) !void {
    try out.print("{s}", .{HELP_TEXT});
    // C4 PR-R4 — derived cartridge-verb help. The brain hardcodes no cartridge
    // verb names; it lists whatever the cartridge registered at boot.
    if (session.repl_verb_registry) |reg| {
        const verbs = reg.all();
        if (verbs.len > 0) {
            try out.print("\nCartridge verbs (registered at boot):\n", .{});
            for (verbs) |v| {
                try out.print("  {s} {s}\n", .{ v.cmd, v.resource });
            }
        }
    }
}

pub fn cmdStatus(session: *Session, out: *const Output) !void {
    try out.print("config:           {s}\n", .{session.cfg.shell.data_dir});
    try out.print("audit log:        {s}\n", .{session.audit_path});
    try out.print("modules loaded:   {d}\n", .{session.instances.len});
    try out.print("wasmtime:         {s}\n", .{
        if (session.runner.wasmtimeEnabled()) "enabled" else "disabled",
    });
    if (session.header_store.tip()) |tip| {
        try out.print("header store tip: height {d}\n", .{tip.height});
    } else {
        try out.print("header store tip: empty\n", .{});
    }
}

pub fn cmdModules(session: *Session, out: *const Output) !void {
    if (session.manager.list().len == 0) {
        try out.print("(no modules loaded)\n", .{});
        return;
    }
    try out.print("name              state    sha256\n", .{});
    try out.print("-------------------------------------------------\n", .{});
    for (session.manager.list()) |inst| {
        var hex_buf: [64]u8 = undefined;
        const hex = bytesToHex(&inst.loaded.sha256, &hex_buf);
        try out.print("{s: <17} {s: <8} {s}\n", .{
            inst.name,
            stateLabel(inst.state),
            hex[0..16], // first 8 bytes of hash for readability
        });
    }
}

fn stateLabel(s: instance_manager.ModuleState) []const u8 {
    return switch (s) {
        .LOADED => "LOADED",
        .RUNNING => "RUNNING",
        .STOPPED => "STOPPED",
        .CRASHED => "CRASHED",
    };
}

pub fn cmdAudit(session: *Session, out: *const Output, args: []const []const u8) !void {
    const n: usize = blk: {
        if (args.len == 0) break :blk 20;
        break :blk std.fmt.parseInt(usize, args[0], 10) catch {
            try out.print("audit: bad count `{s}`\n", .{args[0]});
            return;
        };
    };
    // Read the audit file; print last N \n-delimited lines.
    const file = std.fs.cwd().openFile(session.audit_path, .{}) catch |err| {
        try out.print("audit: {s} ({s})\n", .{ session.audit_path, @errorName(err) });
        return;
    };
    defer file.close();
    const stat = file.stat() catch {
        try out.print("audit: stat failed\n", .{});
        return;
    };
    if (stat.size == 0) {
        try out.print("(audit log empty)\n", .{});
        return;
    }
    // Cap read at 1MB — for v0.1, anything more is probably operational
    // mismanagement and a `tail -n N <path>` is the right tool.
    const cap: usize = 1024 * 1024;
    const read_size: usize = @min(@as(usize, @intCast(stat.size)), cap);
    if (read_size < stat.size) {
        try out.print("(audit log truncated to last {d} bytes; use `tail -n {d} {s}` for more)\n",
            .{ read_size, n, session.audit_path });
    }
    if (read_size > stat.size - read_size) {
        // Read from end — seek backwards.
        file.seekTo(@intCast(@as(u64, @intCast(stat.size)) - read_size)) catch {};
    }
    const buf = try session.allocator.alloc(u8, read_size);
    defer session.allocator.free(buf);
    _ = file.readAll(buf) catch {};

    // Walk backward, count \n, take last N+1 newlines (or the whole buf
    // if fewer).
    var count: usize = 0;
    var start: usize = buf.len;
    while (start > 0) {
        if (buf[start - 1] == '\n') {
            count += 1;
            if (count > n) break;
        }
        start -= 1;
    }
    try out.print("{s}", .{buf[start..]});
}

/// `query <noun> [filterKey value ...]` — the shell-native substrate query
/// primitive. Resolves <noun> (collection_key / alias / 64-hex typeHash) via the
/// cell_decoder_registry and runs cell.query, printing the raw JSON envelope.
/// Cartridge-agnostic: works for every registered cell type, in the shell and
/// over `repl.eval`. This is the body `find` becomes (find → cell.query).
///   query customers                       → {"customers":[ …raw cells ]}
///   query jobs siteRef <hex>              → {"jobs":[ …jobs at that site ]}
pub fn cmdQuery(session: *Session, out: *const Output, args: []const []const u8) !void {
    const handler = session.cell_query_handler orelse {
        try out.print("query: not wired (no cell.query handler in this session)\n", .{});
        return;
    };
    if (args.len == 0) {
        try out.print("usage: query <noun> [filterKey value ...]\n", .{});
        return;
    }
    const noun = args[0];

    // Build an optional filter object from the remaining key/value pairs.
    // Values are spliced verbatim (hex-safe; not a general JSON escaper — this
    // is an operator-facing eyeball surface, refs are 64-hex).
    var filter_buf = std.ArrayList(u8){};
    defer filter_buf.deinit(session.allocator);
    const have_filter = args.len >= 3;
    if (have_filter) {
        try filter_buf.append(session.allocator, '{');
        var i: usize = 1;
        var first = true;
        while (i + 1 < args.len) : (i += 2) {
            if (!first) try filter_buf.append(session.allocator, ',');
            first = false;
            try filter_buf.append(session.allocator, '"');
            try filter_buf.appendSlice(session.allocator, args[i]);
            try filter_buf.appendSlice(session.allocator, "\":\"");
            try filter_buf.appendSlice(session.allocator, args[i + 1]);
            try filter_buf.append(session.allocator, '"');
        }
        try filter_buf.append(session.allocator, '}');
    }
    const filter: ?[]const u8 = if (have_filter) filter_buf.items else null;

    const body = handler.query(session.allocator, noun, filter) catch |err| {
        try out.print("query error: {s}\n", .{@errorName(err)});
        return;
    };
    defer session.allocator.free(body);
    try out.print("{s}\n", .{body});
}

pub fn cmdCall(session: *Session, out: *const Output, args: []const []const u8) !void {
    if (args.len < 2) {
        try out.print("usage: call <module> <export>\n", .{});
        return;
    }
    if (!session.runner.wasmtimeEnabled()) {
        try out.print("call: wasmtime not enabled — rebuild with `-Denable-wasmtime=true`\n", .{});
        return;
    }
    const mod_name = args[0];
    const export_name = args[1];

    var named: ?*const NamedInstance = null;
    for (session.instances) |*ni| {
        if (std.mem.eql(u8, ni.name, mod_name)) {
            named = ni;
            break;
        }
    }
    if (named == null) {
        try out.print("call: no loaded module named `{s}`\n", .{mod_name});
        return;
    }

    // The wasmtime call surface is in the real backend. In stub mode we
    // never reach here (we returned above). In real mode, wasmtime_backend
    // resolves to wasmtime_runner_real which exposes `c`.
    if (!build_options.enable_wasmtime) return;

    const c = wasmtime_backend.c;
    const ctx = c.wasmtime_store_context(named.?.instance.store);
    var exp: c.wasmtime_extern_t = undefined;
    if (!c.wasmtime_instance_export_get(ctx, @constCast(&named.?.instance.instance), export_name.ptr, export_name.len, &exp)) {
        try out.print("call: no export `{s}` on module `{s}`\n", .{ export_name, mod_name });
        return;
    }
    if (exp.kind != c.WASMTIME_EXTERN_FUNC) {
        try out.print("call: export `{s}` is not a function\n", .{export_name});
        return;
    }
    var results: [1]c.wasmtime_val_t = undefined;
    var trap: ?*c.wasm_trap_t = null;
    const err = c.wasmtime_func_call(ctx, &exp.of.func, null, 0, &results, 1, &trap);
    if (err != null) {
        c.wasmtime_error_delete(err);
        try out.print("call: wasm error\n", .{});
        return;
    }
    if (trap != null) {
        c.wasm_trap_delete(trap);
        try out.print("call: wasm trapped\n", .{});
        return;
    }
    try out.print("=> {d}\n", .{results[0].of.i32});
}

pub fn cmdHash(session: *Session, out: *const Output, args: []const []const u8) !void {
    if (args.len < 1) {
        try out.print("usage: hash <file>\n", .{});
        return;
    }
    const path = args[0];
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        try out.print("hash: open {s}: {s}\n", .{ path, @errorName(err) });
        return;
    };
    defer file.close();
    const stat = file.stat() catch {
        try out.print("hash: stat failed\n", .{});
        return;
    };
    if (stat.size > module_loader.MAX_MODULE_BYTES) {
        try out.print("hash: file too large\n", .{});
        return;
    }
    const buf = try session.allocator.alloc(u8, stat.size);
    defer session.allocator.free(buf);
    _ = file.readAll(buf) catch {};
    const h = module_loader.computeSha256(buf);
    var hex_buf: [64]u8 = undefined;
    const hex = bytesToHex(&h, &hex_buf);
    try out.print("{s}  {s}\n", .{ hex, path });
}

pub fn cmdHistory(session: *Session, out: *const Output, args: []const []const u8) !void {
    const n: usize = blk: {
        if (args.len == 0) break :blk 20;
        break :blk std.fmt.parseInt(usize, args[0], 10) catch 20;
    };
    const path = try historyPath(session.allocator, session.cfg.shell.data_dir);
    defer session.allocator.free(path);
    const file = std.fs.cwd().openFile(path, .{}) catch {
        try out.print("(no history yet)\n", .{});
        return;
    };
    defer file.close();
    const stat = file.stat() catch return;
    if (stat.size == 0) {
        try out.print("(history empty)\n", .{});
        return;
    }
    const cap: usize = 256 * 1024;
    const read_size: usize = @min(@as(usize, @intCast(stat.size)), cap);
    file.seekTo(@as(u64, @intCast(stat.size)) - read_size) catch {};
    const buf = try session.allocator.alloc(u8, read_size);
    defer session.allocator.free(buf);
    _ = file.readAll(buf) catch return;

    var count: usize = 0;
    var start: usize = buf.len;
    while (start > 0) {
        if (buf[start - 1] == '\n') {
            count += 1;
            if (count > n) break;
        }
        start -= 1;
    }
    try out.print("{s}", .{buf[start..]});
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-1 / D-O5m.followup-4 — `find jobs`, `find job <id>`,
// `add job ...` REPL verbs.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8;
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5 (helm jobs view).
//
// Each verb dispatches through `session.dispatcher`'s `jobs` resource
// — same in-process root-scope auth context as `repl.status` /
// `repl.help` shims.  Output is JSON-encoded by `jobs_handler` and
// piped through `out.print` verbatim, so both helms (loom-svelte
// JobList + oddjobz-mobile JobsRepository) consume the typed branch
// when the response starts with `[` or `{`.
//
// When the dispatcher is null (legacy fixtures or test harnesses that
// don't wire one), each verb prints a hint pointing at `brain repl`
// from a freshly-bootstrapped daemon — the same shape `cmdDevice`
// uses for missing cert_store.
// ─────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────
// History persistence
// ─────────────────────────────────────────────────────────────────────

pub fn historyPath(allocator: std.mem.Allocator, data_dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ data_dir, "history" });
}

/// Append one command line to the history file. Errors are non-fatal
/// — the REPL keeps going if persistence fails.
pub fn appendHistory(allocator: std.mem.Allocator, data_dir: []const u8, line: []const u8) void {
    const path = historyPath(allocator, data_dir) catch return;
    defer allocator.free(path);
    if (std.fs.path.dirname(path)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }
    const file = std.fs.cwd().createFile(path, .{ .truncate = false, .read = false }) catch return;
    defer file.close();
    file.seekFromEnd(0) catch return;
    file.writeAll(line) catch return;
    file.writeAll("\n") catch return;
}

// ─────────────────────────────────────────────────────────────────────
// Hex helper
// ─────────────────────────────────────────────────────────────────────

fn bytesToHex(bytes: []const u8, out: []u8) []const u8 {
    const charset = "0123456789abcdef";
    var i: usize = 0;
    while (i < bytes.len and i * 2 + 1 < out.len) : (i += 1) {
        out[i * 2 + 0] = charset[(bytes[i] >> 4) & 0xf];
        out[i * 2 + 1] = charset[bytes[i] & 0xf];
    }
    return out[0 .. i * 2];
}

// ─────────────────────────────────────────────────────────────────────
// D-W1 Phase 0 — in-process dispatcher transport.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §4, §5.1, §8.
//
// `repl` is the first transport to drive the new dispatcher.  Three
// resource commands are migrated in this PR:
//
//   repl.status — runs cmdStatus, returns rendered text
//   repl.help   — runs cmdHelp, returns rendered text
//   repl.exit   — emits "bye." and signals the loop to terminate
//
// All three are SHIM handlers — they call the existing pre-Phase-0
// implementations on a captured buffer, then bundle the bytes into a
// `dispatcher.Result.payload`.  This preserves byte-identical output
// for the operator's interactive shell.
//
// Capabilities: `repl.status` and `repl.exit` declare specific caps
// (`cap.brain.repl.status`, `cap.brain.repl.exit`) — required by remote
// transports in Phase 1+ but bypassed here because the REPL transport
// always presents `AuthContext.in_process_root`.  `repl.help` declares
// `.none` (operator should always be able to read help).
//
// TODO(D-W1 Phase 1+): migrate modules / audit / call / hash / history
// / clear and the deferred-engine commands the same way.  Per
// BRAIN-DISPATCHER-UNIFICATION.md §8, those move alongside their owning
// resources (modules → modules.list, audit → audit.tail, headers →
// headers.tip, etc.).
// ─────────────────────────────────────────────────────────────────────

const ReplRoute = struct {
    /// The dispatcher cmd name (always with `repl` resource).
    cmd: []const u8,
};

/// Map a typed REPL command to its dispatcher route, if any.  Only the
/// three Phase-0 migrations resolve here; the rest of `handleLine`'s
/// if-chain handles everything else.
fn asReplDispatcherRoute(cmd: []const u8) ?ReplRoute {
    if (matches(cmd, "status")) return .{ .cmd = "status" };
    if (matches(cmd, "help") or matches(cmd, "?")) return .{ .cmd = "help" };
    if (matches(cmd, "exit") or matches(cmd, "quit")) return .{ .cmd = "exit" };
    return null;
}

/// Build the in-process DispatchContext, dispatch, render the result
/// payload to `out`, and translate `Result.quit` into a `ReplExit`.
fn dispatchRepl(
    disp: *dispatcher_mod.Dispatcher,
    out: *const Output,
    cmd_name: []const u8,
) !ReplExit {
    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{
            .request_id = "",
            .transport_label = "in_process",
        },
    };
    var result = disp.dispatch(&ctx, "repl", cmd_name, "{}") catch |err| {
        // Defensive — the in-process repl transport shouldn't ever hit
        // an auth/cap denial because root scope bypasses cap checks.
        // If we somehow do, surface it without crashing the REPL.
        try out.print("repl: dispatch failed: {s}\n", .{@errorName(err)});
        return .@"continue";
    };
    defer result.deinit();
    if (result.payload.len > 0) {
        try out.print("{s}", .{result.payload});
    }
    return if (result.quit) .quit else .@"continue";
}

/// Capability declaration for the `repl` resource.  Phase 0 wires the
/// three migrated cmds; the rest are unknown_command until their
/// migration phase.
fn replShimCapForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher_mod.CapDeclError!dispatcher_mod.CapDecl {
    if (std.mem.eql(u8, cmd, "status")) return .{ .require = "cap.brain.repl.status" };
    if (std.mem.eql(u8, cmd, "help")) return .none;
    if (std.mem.eql(u8, cmd, "exit")) return .{ .require = "cap.brain.repl.exit" };
    return error.unknown_command;
}

/// Shim handler for the `repl` resource.  Captures cmdStatus / cmdHelp
/// output into a heap buffer and returns it as the dispatcher Result
/// payload.  The in-process transport prints the payload verbatim.
fn replShimHandle(
    state: ?*anyopaque,
    _: *const dispatcher_mod.DispatchContext,
    cmd: []const u8,
    _: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher_mod.Result {
    const session: *Session = @ptrCast(@alignCast(state.?));

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    const captured = Output{ .buffer = &buf, .allocator = allocator };

    if (std.mem.eql(u8, cmd, "status")) {
        try cmdStatus(session, &captured);
        const slice = try buf.toOwnedSlice(allocator);
        return dispatcher_mod.Result.ownedPayload(allocator, slice);
    }
    if (std.mem.eql(u8, cmd, "help")) {
        try cmdHelp(session, &captured);
        const slice = try buf.toOwnedSlice(allocator);
        return dispatcher_mod.Result.ownedPayload(allocator, slice);
    }
    if (std.mem.eql(u8, cmd, "exit")) {
        try captured.print("bye.\n", .{});
        const slice = try buf.toOwnedSlice(allocator);
        return .{
            .payload = slice,
            .allocator = allocator,
            .quit = true,
        };
    }
    // Should not reach here — replShimCapForCmd would have rejected.
    return error.unknown_command;
}

/// Register the `repl` resource on the supplied dispatcher with `session`
/// as the shim handler's state.  Caller is responsible for keeping the
/// Session at a stable address for the dispatcher's lifetime.
pub fn registerReplShims(disp: *dispatcher_mod.Dispatcher, session: *Session) !void {
    try disp.register(.{
        .name = "repl",
        .state = @ptrCast(session),
        .cap_for_cmd_fn = replShimCapForCmd,
        .handle_fn = replShimHandle,
    });
}


```
