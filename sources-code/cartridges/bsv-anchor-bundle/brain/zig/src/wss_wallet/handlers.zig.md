---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet/handlers.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.451380+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet/handlers.zig

```zig
// JSON-RPC method handlers for the wss_wallet endpoint, extracted
// from src/wss_wallet.zig as Phase 3 of the modularize.  Pure code
// motion: no behaviour change.
//
// Each handler takes the standard quartet:
//   session: *SessionState
//   backend: *Backend
//   id_val:  std.json.Value
//   params:  std.json.Value
//
// And emits a JSON-RPC response (success or error) via writeResultRaw /
// writeError (both from types.zig).  Handlers are pub so wss_wallet.zig's
// handleJsonRpc dispatcher and the reactor's handleReactorJsonRpc both
// reach them via `handlers.handleX` (file-local aliases).

const std = @import("std");
const types = @import("types.zig");
const helm_event_broker = @import("helm_event_broker");
const cell_query_handler = @import("cell_query_handler");
const verb_dispatcher = @import("verb_dispatcher");
const manifest_registry = @import("manifest_registry");
const oddjobz_attention_handler = @import("oddjobz_attention_handler");

const SessionState = types.SessionState;
const Backend = types.Backend;
const HELM_TOPICS = types.HELM_TOPICS;
const MAX_HELM_TOPICS_PER_SUB = types.MAX_HELM_TOPICS_PER_SUB;
const MAX_HELM_TOPIC_LEN = types.MAX_HELM_TOPIC_LEN;
const MAX_HELM_FETCH_LIMIT = types.MAX_HELM_FETCH_LIMIT;
const helmEventCallback = types.helmEventCallback;
const writeError = types.writeError;
const writeResultRaw = types.writeResultRaw;
const jsonEncodeString = types.jsonEncodeString;
const dispatchToCartridge = types.dispatchToCartridge;

pub fn handleHelmSubscribe(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
) !void {
    const allocator = session.allocator;
    const broker = backend.helm_broker orelse {
        return writeError(session, id_val, -32603, "helm broker unavailable on this server");
    };

    if (params != .object) {
        return writeError(session, id_val, -32602, "helm.subscribe params must be an object");
    }
    const topics_val = params.object.get("topics") orelse {
        return writeError(session, id_val, -32602, "helm.subscribe missing 'topics' array");
    };
    if (topics_val != .array) {
        return writeError(session, id_val, -32602, "helm.subscribe 'topics' must be an array of strings");
    }
    if (topics_val.array.items.len == 0) {
        return writeError(session, id_val, -32602, "helm.subscribe 'topics' must not be empty");
    }
    if (topics_val.array.items.len > MAX_HELM_TOPICS_PER_SUB) {
        return writeError(session, id_val, -32602, "helm.subscribe 'topics' exceeds maximum");
    }

    // Pre-validate every entry against the known topic set BEFORE
    // any allocation.  This keeps the per-entry-allocation cleanup
    // path simple — once we begin duping strings, every early return
    // must free what's already owned.
    for (topics_val.array.items) |item| {
        if (item != .string) {
            return writeError(session, id_val, -32602, "helm.subscribe 'topics' must be strings");
        }
        if (item.string.len == 0 or item.string.len > MAX_HELM_TOPIC_LEN) {
            return writeError(session, id_val, -32602, "helm.subscribe topic length out of range");
        }
        var matched = false;
        for (HELM_TOPICS) |known| {
            if (std.mem.eql(u8, item.string, known)) {
                matched = true;
                break;
            }
        }
        if (!matched) {
            return writeError(session, id_val, -32602, "helm.subscribe unknown topic");
        }
    }

    // Allocate owned topic storage now that every entry has been
    // shape-validated.
    const owned_storage = try allocator.alloc([]u8, topics_val.array.items.len);
    errdefer allocator.free(owned_storage);
    var allocated: usize = 0;
    errdefer {
        var i: usize = 0;
        while (i < allocated) : (i += 1) allocator.free(owned_storage[i]);
    }
    for (topics_val.array.items, 0..) |item, i| {
        owned_storage[i] = try allocator.dupe(u8, item.string);
        allocated = i + 1;
    }

    // Build the const-slice view the callback iterates over.
    const view = try allocator.alloc([]const u8, owned_storage.len);
    errdefer allocator.free(view);
    for (owned_storage, 0..) |t, i| view[i] = t;

    // Replace any prior subscription before assigning new state.
    session.unsubscribeAndFree(broker);

    // Assign storage, register, then write the success response.
    session.helm_topics_storage = owned_storage;
    session.helm_topics = view;
    const sub_id = broker.subscribe(.{
        .state = session,
        .callback = helmEventCallback,
    }) catch {
        // Roll back the topic storage on subscribe failure.
        session.freeTopics();
        return writeError(session, id_val, -32603, "helm.subscribe broker registration failed");
    };
    session.helm_sub_id = sub_id;

    // Build {"subscribed":true,"topics":[...]} body.
    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"subscribed\":true,\"topics\":[");
    for (view, 0..) |t, i| {
        if (i != 0) try body.append(allocator, ',');
        try jsonEncodeString(allocator, &body, t);
    }
    try body.append(allocator, ']');
    try body.append(allocator, '}');
    return writeResultRaw(session, id_val, body.items);
}

pub fn handleHelmUnsubscribe(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
) !void {
    const broker = backend.helm_broker orelse {
        return writeError(session, id_val, -32603, "helm broker unavailable on this server");
    };
    session.unsubscribeAndFree(broker);
    return writeResultRaw(session, id_val, "{\"unsubscribed\":true}");
}

// ─── Sovereign-push D.1 — helm.fetch_since RPC ──────────────────────
//
// Request shape:
//   {"jsonrpc":"2.0","method":"helm.fetch_since",
//    "params":{"since_ts":<i64>,"limit":<u32?>},"id":<id>}
//
// Response shape:
//   {"result":{"events":[
//     {"event_id":"...","ts":<i64>,"kind":"<type>","payload":{...}},
//     ...
//   ],"next_cursor_ts":<i64>}}
//
// Server caps `limit` at MAX_HELM_FETCH_LIMIT.  Events are returned in
// publish order, oldest first.  When the broker has nothing newer than
// `since_ts`, `events` is empty and `next_cursor_ts` echoes the input.

pub fn handleHelmFetchSince(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
) !void {
    const allocator = session.allocator;
    const broker = backend.helm_broker orelse {
        return writeError(session, id_val, -32603, "helm broker unavailable on this server");
    };

    if (params != .object) {
        return writeError(session, id_val, -32602, "helm.fetch_since params must be an object");
    }
    const since_val = params.object.get("since_ts") orelse {
        return writeError(session, id_val, -32602, "helm.fetch_since missing 'since_ts'");
    };
    if (since_val != .integer) {
        return writeError(session, id_val, -32602, "helm.fetch_since 'since_ts' must be an integer");
    }
    if (since_val.integer < 0) {
        return writeError(session, id_val, -32602, "helm.fetch_since 'since_ts' must be non-negative");
    }
    var limit: u32 = MAX_HELM_FETCH_LIMIT;
    if (params.object.get("limit")) |limit_val| {
        if (limit_val != .integer) {
            return writeError(session, id_val, -32602, "helm.fetch_since 'limit' must be an integer");
        }
        if (limit_val.integer < 1) {
            return writeError(session, id_val, -32602, "helm.fetch_since 'limit' must be >= 1");
        }
        const clamped: u32 = if (limit_val.integer > @as(i64, MAX_HELM_FETCH_LIMIT))
            MAX_HELM_FETCH_LIMIT
        else
            @intCast(limit_val.integer);
        limit = clamped;
    }

    var cursor: i64 = since_val.integer;
    const events = broker.fetchSince(allocator, since_val.integer, limit, &cursor) catch
        return writeError(session, id_val, -32603, "helm.fetch_since broker error");
    defer allocator.free(events);

    // Build the response body.  The `payload` field is interpolated
    // verbatim (it's already-encoded JSON from the publisher).
    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"events\":[");
    for (events, 0..) |ev, i| {
        if (i != 0) try body.append(allocator, ',');
        try body.appendSlice(allocator, "{\"event_id\":\"");
        try body.appendSlice(allocator, &ev.event_id);
        try body.appendSlice(allocator, "\",\"ts\":");
        const ts_str = try std.fmt.allocPrint(allocator, "{d}", .{ev.ts});
        defer allocator.free(ts_str);
        try body.appendSlice(allocator, ts_str);
        try body.appendSlice(allocator, ",\"kind\":");
        try jsonEncodeString(allocator, &body, ev.type);
        try body.appendSlice(allocator, ",\"payload\":");
        try body.appendSlice(allocator, ev.payload_json);
        try body.append(allocator, '}');
    }
    try body.appendSlice(allocator, "],\"next_cursor_ts\":");
    const cur_str = try std.fmt.allocPrint(allocator, "{d}", .{cursor});
    defer allocator.free(cur_str);
    try body.appendSlice(allocator, cur_str);
    try body.append(allocator, '}');
    return writeResultRaw(session, id_val, body.items);
}

// ─── Generic cell.query / cell.get ───────────────────────────────────
//
// JSON-RPC method dispatch for the typeHash-keyed read primitive. The
// brain knows nothing about specific extensions here — typeHashes are
// resolved by cell_query_handler.zig's registry. Experiences add their
// own typeHashes to that registry as they bring view-stores online.

pub fn handleCellQuery(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
) !void {
    const allocator = session.allocator;
    const handler = backend.cell_query orelse {
        return writeError(session, id_val, -32603, "cell.query seam unavailable on this server");
    };

    if (params != .object) {
        return writeError(session, id_val, -32602, "cell.query params must be an object");
    }
    const type_hash_val = params.object.get("typeHash") orelse {
        return writeError(session, id_val, -32602, "cell.query: missing 'typeHash'");
    };
    if (type_hash_val != .string) {
        return writeError(session, id_val, -32602, "cell.query: 'typeHash' must be a string");
    }
    const type_hash = type_hash_val.string;

    // filter is optional. When present, serialise to JSON so the handler
    // can re-parse against the typed-store helper's expected shape.
    var filter_json: ?[]u8 = null;
    defer if (filter_json) |fj| allocator.free(fj);

    if (params.object.get("filter")) |filter_val| {
        if (filter_val != .object) {
            return writeError(session, id_val, -32602, "cell.query: 'filter' must be an object");
        }
        filter_json = std.json.Stringify.valueAlloc(allocator, filter_val, .{}) catch {
            return writeError(session, id_val, -32603, "cell.query: serialise filter failed");
        };
    }

    const body = handler.query(allocator, type_hash, filter_json) catch |err| {
        const code: i32 = switch (err) {
            error.invalid_params, error.invalid_filter, error.invalid_cell_ref => -32602,
            error.unknown_type_hash => -32602,
            error.store_unavailable, error.out_of_memory => -32603,
        };
        const msg = switch (err) {
            error.invalid_params => "cell.query: invalid params",
            error.invalid_filter => "cell.query: filter does not match any known projection for this typeHash",
            error.invalid_cell_ref => "cell.query: invalid cellRef (must be 64 lowercase hex)",
            error.unknown_type_hash => "cell.query: typeHash not registered",
            error.store_unavailable => "cell.query: required view-store is not wired",
            error.out_of_memory => "cell.query: out of memory",
        };
        return writeError(session, id_val, code, msg);
    };
    defer allocator.free(body);
    return writeResultRaw(session, id_val, body);
}

/// C4 PR-J4 — attention.poll: namespace-scoped attention signal feed.
/// params { namespaces: [ "<ns>", … ], limit?: int }. The caller passes the
/// in-scope namespaces (in-cartridge → [that one]; shell → [shell, …opt-ins]);
/// the brain merges the in-scope sources. Result = JSON array of signals.
pub fn handleAttentionPoll(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
) !void {
    const allocator = session.allocator;
    const handler = backend.attention orelse {
        return writeError(session, id_val, -32603, "attention.poll seam unavailable on this server");
    };
    if (params != .object) {
        return writeError(session, id_val, -32602, "attention.poll params must be an object");
    }
    const ns_val = params.object.get("namespaces") orelse {
        return writeError(session, id_val, -32602, "attention.poll: missing 'namespaces'");
    };
    if (ns_val != .array) {
        return writeError(session, id_val, -32602, "attention.poll: 'namespaces' must be an array of strings");
    }
    var ns_list = std.ArrayList([]const u8){};
    defer ns_list.deinit(allocator);
    for (ns_val.array.items) |item| {
        if (item != .string) {
            return writeError(session, id_val, -32602, "attention.poll: namespaces must be strings");
        }
        ns_list.append(allocator, item.string) catch {
            return writeError(session, id_val, -32603, "attention.poll: out of memory");
        };
    }
    var limit: usize = 50;
    if (params.object.get("limit")) |lv| {
        if (lv == .integer and lv.integer > 0) limit = @intCast(lv.integer);
    }
    const body = handler.poll(allocator, ns_list.items, limit) catch |err| {
        const code: i32 = switch (err) {
            error.invalid_params => -32602,
            error.out_of_memory, error.source_error => -32603,
        };
        const msg = switch (err) {
            error.invalid_params => "attention.poll: invalid params",
            error.out_of_memory => "attention.poll: out of memory",
            error.source_error => "attention.poll: an attention source failed",
        };
        return writeError(session, id_val, code, msg);
    };
    defer allocator.free(body);
    return writeResultRaw(session, id_val, body);
}

/// C4 PR-J5 — ratify.submit: namespace-routed ratification. params
/// { namespace, proposal_id, sir_program, payload_hint }. Resolves the
/// cartridge's registered graph builder by namespace and returns its wire blob
/// (for oddjobz: `{proposal_id, cellIds:{…}, persistedAt}`). The builder owns
/// idempotency + persistence. `oddjobz.ratify_proposal` remains a back-compat
/// alias that reaches the same handler instance.
pub fn handleRatifySubmit(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
) !void {
    const allocator = session.allocator;
    const handler = backend.ratify orelse {
        return writeError(session, id_val, -32603, "ratify.submit seam unavailable on this server (was --enable-repl set?)");
    };
    if (params != .object) {
        return writeError(session, id_val, -32602, "ratify.submit params must be an object");
    }
    const ns_val = params.object.get("namespace") orelse {
        return writeError(session, id_val, -32602, "ratify.submit: missing 'namespace'");
    };
    if (ns_val != .string or ns_val.string.len == 0) {
        return writeError(session, id_val, -32602, "ratify.submit: 'namespace' must be a non-empty string");
    }
    // Stringify the params so the builder can re-parse with full ownership of
    // the substring slices (same reason as oddjobz.ratify_proposal).
    const params_json = std.json.Stringify.valueAlloc(allocator, params, .{}) catch {
        return writeError(session, id_val, -32603, "ratify.submit serialise failed");
    };
    defer allocator.free(params_json);

    const body = handler.submit(allocator, ns_val.string, params_json) catch |err| {
        const code: i32 = switch (err) {
            error.no_builder => -32601,
            error.builder_failed => -32000,
            error.out_of_memory => -32603,
        };
        const msg = switch (err) {
            error.no_builder => "ratify.submit: no builder registered for that namespace",
            error.builder_failed => "ratify.submit: graph builder rejected the proposal",
            error.out_of_memory => "ratify.submit: out of memory",
        };
        return writeError(session, id_val, code, msg);
    };
    defer allocator.free(body);
    return writeResultRaw(session, id_val, body);
}

pub fn handleCellGet(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
) !void {
    const allocator = session.allocator;
    const handler = backend.cell_query orelse {
        return writeError(session, id_val, -32603, "cell.get seam unavailable on this server");
    };

    if (params != .object) {
        return writeError(session, id_val, -32602, "cell.get params must be an object");
    }
    const type_hash_val = params.object.get("typeHash") orelse {
        return writeError(session, id_val, -32602, "cell.get: missing 'typeHash'");
    };
    if (type_hash_val != .string) {
        return writeError(session, id_val, -32602, "cell.get: 'typeHash' must be a string");
    }
    const type_hash = type_hash_val.string;

    // The typed getters in oddjobz_query_handler expect their own params
    // shape (cellRef / siteRef / customerRef etc.). Pass through the
    // original params object verbatim so each getter applies its own
    // validation.
    const params_json = std.json.Stringify.valueAlloc(allocator, params, .{}) catch {
        return writeError(session, id_val, -32603, "cell.get: serialise params failed");
    };
    defer allocator.free(params_json);

    const body = handler.get(allocator, type_hash, params_json) catch |err| {
        const code: i32 = switch (err) {
            error.invalid_params, error.invalid_filter, error.invalid_cell_ref => -32602,
            error.unknown_type_hash => -32602,
            error.store_unavailable, error.out_of_memory => -32603,
        };
        const msg = switch (err) {
            error.invalid_params => "cell.get: invalid params",
            error.invalid_filter => "cell.get: filter not applicable to single-cell get",
            error.invalid_cell_ref => "cell.get: invalid cellRef (must be 64 lowercase hex)",
            error.unknown_type_hash => "cell.get: typeHash not registered",
            error.store_unavailable => "cell.get: required view-store is not wired",
            error.out_of_memory => "cell.get: out of memory",
        };
        return writeError(session, id_val, code, msg);
    };
    defer allocator.free(body);
    return writeResultRaw(session, id_val, body);
}

// ─── Generic verb.dispatch ───────────────────────────────────────────
//
// Routes a declared extension action verb through the registered
// walker. The brain knows nothing about specific extensions here —
// walkers are registered at boot by extension-specific wiring (see
// cli.zig for the ratify walker registration). Field shells use this
// uniform method instead of per-verb JSON-RPC names; legacy per-verb
// names (e.g. `oddjobz.ratify_proposal`) continue to work alongside.

pub fn handleVerbDispatch(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
) !void {
    const allocator = session.allocator;
    const registry = backend.verb_registry orelse {
        return writeError(session, id_val, -32603, "verb.dispatch seam unavailable on this server");
    };

    if (params != .object) {
        return writeError(session, id_val, -32602, "verb.dispatch params must be an object");
    }
    const ext_v = params.object.get("extensionId") orelse {
        return writeError(session, id_val, -32602, "verb.dispatch: missing 'extensionId'");
    };
    if (ext_v != .string or ext_v.string.len == 0) {
        return writeError(session, id_val, -32602, "verb.dispatch: 'extensionId' must be a non-empty string");
    }
    const verb_v = params.object.get("verb") orelse {
        return writeError(session, id_val, -32602, "verb.dispatch: missing 'verb'");
    };
    if (verb_v != .string or verb_v.string.len == 0) {
        return writeError(session, id_val, -32602, "verb.dispatch: 'verb' must be a non-empty string");
    }

    // The walker expects a stringified JSON `params` payload it can re-
    // parse with its own ownership semantics. When the caller omits
    // `params` (a no-arg verb call) we hand over `{}`.
    const inner_params_v = params.object.get("params");
    const params_json: []u8 = blk: {
        if (inner_params_v) |v| {
            if (v != .object) {
                return writeError(session, id_val, -32602, "verb.dispatch: 'params' must be an object");
            }
            break :blk std.json.Stringify.valueAlloc(allocator, v, .{}) catch {
                return writeError(session, id_val, -32603, "verb.dispatch: serialise params failed");
            };
        }
        break :blk allocator.dupe(u8, "{}") catch {
            return writeError(session, id_val, -32603, "verb.dispatch: out of memory");
        };
    };
    defer allocator.free(params_json);

    const body = registry.dispatch(
        allocator,
        ext_v.string,
        verb_v.string,
        params_json,
    ) catch |err| {
        const code: i32 = switch (err) {
            error.walker_not_found => -32601,
            error.invalid_params => -32602,
            error.walker_failed, error.out_of_memory => -32603,
        };
        const msg = switch (err) {
            error.walker_not_found => "verb.dispatch: no walker registered for (extensionId, verb)",
            error.invalid_params => "verb.dispatch: walker rejected params",
            error.walker_failed => "verb.dispatch: walker failed",
            error.out_of_memory => "verb.dispatch: out of memory",
        };
        return writeError(session, id_val, code, msg);
    };
    defer allocator.free(body);
    return writeResultRaw(session, id_val, body);
}

// ─── manifest.install / .list / .uninstall ───────────────────────────
//
// Runtime extension installation. The PWA shell calls
// `manifest.install` after verifying a bundle locally; the brain
// records the manifest so other paired shells (and the brain's own
// dispatch / query layers) see the installed extension.
//
// In-memory registry only in this iteration; LMDB persistence is the
// follow-up. The API stays stable across that change.

pub fn handleManifestInstall(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
) !void {
    const allocator = session.allocator;
    const registry = backend.manifest_registry orelse {
        return writeError(session, id_val, -32603, "manifest.install seam unavailable on this server");
    };

    if (params != .object) {
        return writeError(session, id_val, -32602, "manifest.install params must be an object");
    }
    const obj = params.object;

    const ext_v = obj.get("extensionId") orelse {
        return writeError(session, id_val, -32602, "manifest.install: missing 'extensionId'");
    };
    if (ext_v != .string or ext_v.string.len == 0) {
        return writeError(session, id_val, -32602, "manifest.install: 'extensionId' must be a non-empty string");
    }
    const ver_v = obj.get("version") orelse {
        return writeError(session, id_val, -32602, "manifest.install: missing 'version'");
    };
    if (ver_v != .string or ver_v.string.len == 0) {
        return writeError(session, id_val, -32602, "manifest.install: 'version' must be a non-empty string");
    }
    const src_v = obj.get("source") orelse {
        return writeError(session, id_val, -32602, "manifest.install: missing 'source'");
    };
    if (src_v != .string) {
        return writeError(session, id_val, -32602, "manifest.install: 'source' must be a string");
    }
    const manifest_v = obj.get("manifest") orelse {
        return writeError(session, id_val, -32602, "manifest.install: missing 'manifest' object");
    };
    if (manifest_v != .object) {
        return writeError(session, id_val, -32602, "manifest.install: 'manifest' must be an object");
    }

    const signer_pubkey: []const u8 = if (obj.get("signerPubkey")) |spv|
        (if (spv == .string) spv.string else "")
    else
        "";

    const manifest_json = std.json.Stringify.valueAlloc(allocator, manifest_v, .{}) catch {
        return writeError(session, id_val, -32603, "manifest.install: serialise manifest failed");
    };
    defer allocator.free(manifest_json);

    registry.install(
        ext_v.string,
        ver_v.string,
        src_v.string,
        manifest_json,
        signer_pubkey,
    ) catch |err| {
        const code: i32 = switch (err) {
            error.duplicate_extension_id => -32602,
            error.not_found => -32603,
            error.invalid_payload => -32602,
            error.out_of_memory => -32603,
            error.persist_failed => -32603,
        };
        const msg = switch (err) {
            error.duplicate_extension_id => "manifest.install: extensionId already installed (uninstall first to upgrade)",
            error.not_found => "manifest.install: not_found (internal)",
            error.invalid_payload => "manifest.install: invalid payload",
            error.out_of_memory => "manifest.install: out of memory",
            error.persist_failed => "manifest.install: registry log persist failed",
        };
        return writeError(session, id_val, code, msg);
    };

    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"installed\":true,\"extensionId\":");
    try jsonEncodeString(allocator, &body, ext_v.string);
    try body.append(allocator, '}');
    return writeResultRaw(session, id_val, body.items);
}

pub fn handleManifestList(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
) !void {
    _ = params; // list takes no args
    const allocator = session.allocator;
    const registry = backend.manifest_registry orelse {
        return writeError(session, id_val, -32603, "manifest.list seam unavailable on this server");
    };

    const body = registry.renderList(allocator) catch |err| switch (err) {
        error.out_of_memory => return writeError(session, id_val, -32603, "manifest.list: out of memory"),
        error.persist_failed => return writeError(session, id_val, -32603, "manifest.list: registry log persist failed"),
        error.duplicate_extension_id, error.not_found, error.invalid_payload =>
            return writeError(session, id_val, -32603, "manifest.list: internal error"),
    };
    defer allocator.free(body);
    return writeResultRaw(session, id_val, body);
}

pub fn handleManifestUninstall(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
) !void {
    const allocator = session.allocator;
    const registry = backend.manifest_registry orelse {
        return writeError(session, id_val, -32603, "manifest.uninstall seam unavailable on this server");
    };
    if (params != .object) {
        return writeError(session, id_val, -32602, "manifest.uninstall params must be an object");
    }
    const ext_v = params.object.get("extensionId") orelse {
        return writeError(session, id_val, -32602, "manifest.uninstall: missing 'extensionId'");
    };
    if (ext_v != .string or ext_v.string.len == 0) {
        return writeError(session, id_val, -32602, "manifest.uninstall: 'extensionId' must be a non-empty string");
    }
    registry.uninstall(ext_v.string) catch |err| {
        const code: i32 = switch (err) {
            error.not_found => -32602,
            else => -32603,
        };
        const msg = switch (err) {
            error.not_found => "manifest.uninstall: extensionId not installed",
            else => "manifest.uninstall: internal error",
        };
        return writeError(session, id_val, code, msg);
    };

    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"uninstalled\":true,\"extensionId\":");
    try jsonEncodeString(allocator, &body, ext_v.string);
    try body.append(allocator, '}');
    return writeResultRaw(session, id_val, body.items);
}

// ─── Tier 2P Phase B — oddjobz attention RPCs ───────────────────────

pub const OddjobzAttentionVerb = enum {
    list_messages,
    list_dispatch_decisions,
    poll_attention_signals,
};

pub fn handleOddjobzAttention(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
    verb: OddjobzAttentionVerb,
) !void {
    const allocator = session.allocator;
    const handler = backend.oddjobz_attention orelse {
        // DLDC-W.2.2 — cartridge route fallback via @tagName(verb).
        if (try dispatchToCartridge(session, backend, id_val, "oddjobz", @tagName(verb), params)) return;
        return writeError(session, id_val, -32603, "oddjobz attention seam unavailable on this server");
    };

    const params_json = std.json.Stringify.valueAlloc(allocator, params, .{}) catch {
        return writeError(session, id_val, -32603, "oddjobz attention: serialise failed");
    };
    defer allocator.free(params_json);

    const body = switch (verb) {
        .list_messages => handler.listMessages(allocator, params_json),
        .list_dispatch_decisions => handler.listDispatchDecisions(allocator, params_json),
        .poll_attention_signals => handler.pollAttentionSignals(allocator, params_json),
    } catch |err| {
        const code: i32 = switch (err) {
            error.invalid_params => -32602,
            error.out_of_memory => -32603,
            error.io_error => -32603,
        };
        const msg = switch (err) {
            error.invalid_params => "oddjobz attention: invalid params",
            error.out_of_memory => "oddjobz attention: out of memory",
            error.io_error => "oddjobz attention: JSONL read error",
        };
        return writeError(session, id_val, code, msg);
    };
    defer allocator.free(body);
    return writeResultRaw(session, id_val, body);
}

```
