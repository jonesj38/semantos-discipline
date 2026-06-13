---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet/types.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.451019+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet/types.zig

```zig
// Shared public types for the wss_wallet endpoint, extracted from
// src/wss_wallet.zig as the foundation for further modularization.
// Pure code motion: no behaviour change.
//
// Owns: protocol-level constants, error set, Backend struct (the
// host-borrowed pointers a session needs), Network enum, HELM_TOPICS
// allowlist, HandshakeResult, the HELM cap constants.
//
// Deliberately omitted (deferred until handler/reactor extraction):
//   • SessionState — its methods call jsonEncodeString + wss_codec
//     in helmEventCallback; promoting them all together is the next
//     phase.
//   • helmEventCallback / eventTypeMatchesTopics / topicPlural — same
//     reason; bundled with SessionState in the next phase.

const std = @import("std");
const bearer_tokens = @import("bearer_tokens");
const helm_event_broker = @import("helm_event_broker");
const wss_codec = @import("wss_codec");
const cell_query_handler = @import("cell_query_handler");
const attention_poll_handler = @import("attention_poll_handler");
const ratify_submit_handler = @import("ratify_submit_handler");
const verb_dispatcher = @import("verb_dispatcher");
const manifest_registry = @import("manifest_registry");
const oddjobz_attention_handler = @import("oddjobz_attention_handler");
const sni_domain_map = @import("sni_domain_map");

/// Maximum WS frame payload accepted from a client. BRC-100 envelopes
/// rarely exceed a few KB; 64 KiB is comfortable headroom and bounds
/// the per-connection memory footprint.
pub const MAX_PAYLOAD_BYTES: usize = 64 * 1024;

pub const SessionError = error{
    out_of_memory,
    write_failed,
    read_failed,
    protocol,
};

pub const ServerVersion = struct {
    version: []const u8 = "brain-0.1",
    protocol: []const u8 = "brc-100",
    server: []const u8 = "brain",
};

pub const Network = enum {
    mainnet,
    testnet,

    pub fn asString(self: Network) []const u8 {
        return switch (self) {
            .mainnet => "mainnet",
            .testnet => "testnet",
        };
    }
};

/// State a wallet WSS session needs from its host. Bearer tokens for
/// auth, network for getNetwork. Pointers borrowed; caller owns
/// lifetimes.
pub const Backend = struct {
    tokens: *bearer_tokens.TokenStore,
    network: Network = .mainnet,
    /// Optional — when set, identifies which token authenticated the
    /// session in audit logs. Populated by site_server post-auth.
    authenticated_token_id: ?u64 = null,
    /// D-O5.followup-4 — process-scoped helm event broker.  Optional:
    /// when null the helm.subscribe RPC returns
    /// `{"error":{"code":-32603,"message":"helm broker unavailable"}}`
    /// (the daemon was started without a broker — typical when the
    /// REPL backend isn't enabled).
    helm_broker: ?*helm_event_broker.Broker = null,
    /// Generic cell.query / cell.get JSON-RPC seam.
    cell_query: ?*cell_query_handler.Handler = null,
    /// Generic verb.dispatch registry.
    verb_registry: ?*verb_dispatcher.Registry = null,
    /// Manifest registry.
    manifest_registry: ?*manifest_registry.Registry = null,
    /// Tier 2P Phase B — oddjobz attention seam.
    oddjobz_attention: ?*oddjobz_attention_handler.Handler = null,
    /// C4 PR-J4 — generic namespace-scoped attention poll (attention.poll).
    attention: ?*attention_poll_handler.Handler = null,
    /// C4 PR-J5 — generic namespace-routed ratify (ratify.submit). Resolves the
    /// cartridge's registered graph builder by namespace.
    ratify: ?*ratify_submit_handler.Handler = null,
    /// W7.4 — hosted-operator mode.  When non-null, incoming WSS upgrades
    /// on brain.<domain> use SNI+cert auth instead of bearer tokens.
    operator_domain_map: ?*const sni_domain_map.DomainMap = null,
    /// Brain data directory used to locate per-operator cert stores at
    /// `<operator_data_dir>/operators/<op_pkh16>/identity-certs.log`.
    operator_data_dir: []const u8 = "",
};

/// D-O5.followup-4 — list of topics the helm subscribes to.
pub const HELM_TOPICS = [_][]const u8{
    "jobs",
    "customers",
    "visits",
    "quotes",
    "invoices",
    "attachments",
    // Tier 3 typed-NL pipeline emits `intent_cell.created` (singular
    // event-type prefix), maps to `intent_cells` (plural) via
    // topicPlural() — so the allowlist must include the plural.
    "intent_cells",
};

/// Maximum number of distinct topics a single helm.subscribe call may
/// supply.  Defends against runaway client-side payloads.
pub const MAX_HELM_TOPICS_PER_SUB: usize = 16;
/// Maximum length of a single topic string (defensive cap mirroring
/// HELM_TOPICS' shape).
pub const MAX_HELM_TOPIC_LEN: usize = 32;

/// Sovereign-push D.1 — server-side cap on `helm.fetch_since` page
/// size when the client omits `limit` or asks for too many.  Sized
/// below MAX_PAYLOAD_BYTES so even maximum-sized payloads fit one
/// frame.
pub const MAX_HELM_FETCH_LIMIT: u32 = 256;

pub const HandshakeResult = enum {
    /// Request was an /api/v1/wallet upgrade — caller should now drop
    /// out of std.http.Server and call `serveSession` on the raw stream.
    upgraded,
    /// Request was not for /api/v1/wallet — caller should fall through
    /// to normal HTTP routing.
    not_a_wallet_upgrade,
    /// Request was for /api/v1/wallet but failed (bad headers / bad
    /// auth / not a websocket upgrade). Response already written; caller
    /// should close the connection.
    rejected,
};

/// Per-connection state the helm.subscribe RPC + helm.event notifier
/// path need.  Constructed at the top of `serveSession` and passed
/// through to handleJsonRpc; cleaned up before returning.
///
/// The write_mu mutex serialises stream-side writes between the frame
/// loop's response writes and the broker's notification writes.  Both
/// the JSON-RPC dispatch and the `helm.event` callback acquire it
/// before calling wss_codec.writeFrame.
pub const SessionState = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    write_mu: std.Thread.Mutex,
    helm_sub_id: ?helm_event_broker.SubscriberId = null,
    helm_topics: ?[]const []const u8 = null,
    helm_topics_storage: ?[][]u8 = null,

    /// Free any heap-allocated topics state.  Idempotent.
    pub fn freeTopics(self: *SessionState) void {
        if (self.helm_topics_storage) |storage| {
            for (storage) |t| self.allocator.free(t);
            self.allocator.free(storage);
            self.helm_topics_storage = null;
        }
        if (self.helm_topics) |topics| {
            self.allocator.free(topics);
            self.helm_topics = null;
        }
    }

    /// Detach from the broker (if subscribed) and free topics state.
    pub fn unsubscribeAndFree(self: *SessionState, broker: *helm_event_broker.Broker) void {
        if (self.helm_sub_id) |id| {
            broker.unsubscribe(id);
            self.helm_sub_id = null;
        }
        self.freeTopics();
    }
};

/// Broker callback bound at helm.subscribe time.  Writes the event as
/// a `helm.event` JSON-RPC notification frame to the connection's
/// stream.  Filters on the connection's topic set; events whose type
/// prefix doesn't match any subscribed topic are silently dropped.
pub fn helmEventCallback(state: ?*anyopaque, event: helm_event_broker.Event) void {
    const session: *SessionState = @ptrCast(@alignCast(state.?));
    if (!eventTypeMatchesTopics(event.type, session.helm_topics)) return;

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(session.allocator);
    buf.appendSlice(session.allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"helm.event\",\"params\":{\"type\":") catch return;
    jsonEncodeString(session.allocator, &buf, event.type) catch return;
    buf.appendSlice(session.allocator, ",\"data\":") catch return;
    buf.appendSlice(session.allocator, event.payload_json) catch return;
    buf.appendSlice(session.allocator, "}}") catch return;

    session.write_mu.lock();
    defer session.write_mu.unlock();
    wss_codec.writeFrame(session.stream, .text, buf.items) catch return;
}

/// True if `event_type` matches any element of `topics`.  The match
/// rule: event type's leading dotted segment equals a topic.
pub fn eventTypeMatchesTopics(event_type: []const u8, topics: ?[]const []const u8) bool {
    if (topics == null) return false;
    const dot_idx = std.mem.indexOfScalar(u8, event_type, '.') orelse return false;
    const prefix = event_type[0..dot_idx];
    const plural = topicPlural(prefix) orelse return false;
    for (topics.?) |t| {
        if (std.mem.eql(u8, t, plural)) return true;
    }
    return false;
}

pub fn topicPlural(singular: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, singular, "job")) return "jobs";
    if (std.mem.eql(u8, singular, "customer")) return "customers";
    if (std.mem.eql(u8, singular, "visit")) return "visits";
    if (std.mem.eql(u8, singular, "quote")) return "quotes";
    if (std.mem.eql(u8, singular, "invoice")) return "invoices";
    if (std.mem.eql(u8, singular, "attachment")) return "attachments";
    if (std.mem.eql(u8, singular, "intent_cell")) return "intent_cells";
    return null;
}

/// Frame-write helper that acquires `session.write_mu` before calling
/// `wss_codec.writeFrame`.  Used by every handler that writes a
/// response + by the helm.event broker callback so the two paths
/// can't interleave on the same stream.
pub fn lockedWriteFrame(
    session: *SessionState,
    opcode: wss_codec.Opcode,
    payload: []const u8,
) wss_codec.FrameError!void {
    session.write_mu.lock();
    defer session.write_mu.unlock();
    return wss_codec.writeFrame(session.stream, opcode, payload);
}

pub fn lockedWriteClose(session: *SessionState, status: u16, reason: []const u8) void {
    session.write_mu.lock();
    defer session.write_mu.unlock();
    wss_codec.writeClose(session.stream, status, reason) catch {};
}

/// Emit a JSON-RPC success-result frame.  Caller supplies the `id`
/// from the inbound request (so the round-trip echoes properly) and
/// the result JSON (raw — already encoded).
pub fn writeResultRaw(
    session: *SessionState,
    id: std.json.Value,
    result_json: []const u8,
) !void {
    const allocator = session.allocator;
    const id_json = try std.json.Stringify.valueAlloc(allocator, id, .{});
    defer allocator.free(id_json);
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try buf.appendSlice(allocator, id_json);
    try buf.appendSlice(allocator, ",\"result\":");
    try buf.appendSlice(allocator, result_json);
    try buf.append(allocator, '}');
    try lockedWriteFrame(session, .text, buf.items);
}

/// Emit a JSON-RPC error frame with a code + message string.
pub fn writeError(
    session: *SessionState,
    id: std.json.Value,
    code: i32,
    message: []const u8,
) !void {
    const allocator = session.allocator;
    const id_json = try std.json.Stringify.valueAlloc(allocator, id, .{});
    defer allocator.free(id_json);
    var head_buf: [64]u8 = undefined;
    const head = try std.fmt.bufPrint(&head_buf, ",\"error\":{{\"code\":{d},\"message\":", .{code});
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try buf.appendSlice(allocator, id_json);
    try buf.appendSlice(allocator, head);
    try jsonEncodeString(allocator, &buf, message);
    try buf.appendSlice(allocator, "}}");
    try lockedWriteFrame(session, .text, buf.items);
}

/// DLDC-W.2 — dispatch-to-cartridge fallback helper.
///
/// Reference: docs/audits/2026-05-16-dlba-2-wallet-coupling-tightening.md
///            (DECISION-PENDING-8 option (a) resolution).
///
/// Each oddjobz/WSITE call site in the wallet has shape
///   `const handler = backend.X orelse { return writeError(...); };`
/// where `X` is an optional handler pointer. After D-Decouple-Wallet,
/// the optional handler is one path; the OTHER path routes through the
/// verb_dispatcher registry when a cartridge has registered the
/// corresponding walker. Call sites consume this helper as:
///
///   const handler = backend.oddjobz_attention orelse {
///       if (try dispatchToCartridge(session, backend, id_val,
///               "oddjobz", "<verb>", params)) return;
///       return writeError(session, id_val, -32603,
///           "oddjobz attention seam unavailable on this server");
///   };
///
/// Returns `true` if the helper handled the response (either succeeded
/// or wrote an error frame); the caller should `return` immediately in
/// that case. Returns `false` if no cartridge route was available (no
/// verb_registry, or `walker_not_found`), so the caller falls through
/// to write the V1 "seam unavailable" error.
///
/// V1 PRESERVATION: when `backend.<X>` (the typed handler) is wired, this
/// helper is NEVER called — the call site's Path A executes verbatim. The
/// dispatcher route is the migration fallback that activates once the
/// cartridge ships AND the V1 hardcoded handler is unwired from brain-core
/// boot. (C4 PR-J5b: ratify itself no longer uses this pattern — it routes
/// through the generic `ratify.submit` builder registry instead.)
pub fn dispatchToCartridge(
    session: *SessionState,
    backend: *Backend,
    id_val: std.json.Value,
    extension_id: []const u8,
    verb: []const u8,
    params: std.json.Value,
) !bool {
    const reg = backend.verb_registry orelse return false;

    if (params != .object) {
        try writeError(session, id_val, -32602, "params must be an object");
        return true;
    }

    const allocator = session.allocator;
    const params_json = std.json.Stringify.valueAlloc(allocator, params, .{}) catch {
        try writeError(session, id_val, -32603, "params serialise failed");
        return true;
    };
    defer allocator.free(params_json);

    const result = reg.dispatch(allocator, extension_id, verb, params_json) catch |err| {
        switch (err) {
            // No walker for this (extension_id, verb) — fall through so
            // the caller writes the V1 "seam unavailable" error.
            verb_dispatcher.DispatchError.walker_not_found => return false,
            verb_dispatcher.DispatchError.invalid_params => {
                try writeError(session, id_val, -32602, "cartridge dispatch: invalid params");
                return true;
            },
            verb_dispatcher.DispatchError.walker_failed => {
                try writeError(session, id_val, -32603, "cartridge dispatch: walker failed");
                return true;
            },
            verb_dispatcher.DispatchError.out_of_memory => {
                try writeError(session, id_val, -32603, "cartridge dispatch: out of memory");
                return true;
            },
        }
    };
    defer allocator.free(result);
    try writeResultRaw(session, id_val, result);
    return true;
}

/// Parse `Authorization: Bearer <hex64>` (or lowercase variant).
/// Returns the 64-char hex token or null if header is malformed.
pub fn parseBearerHeader(value: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, value, " \t");
    if (!std.mem.startsWith(u8, trimmed, "Bearer ") and !std.mem.startsWith(u8, trimmed, "bearer ")) {
        return null;
    }
    const tok = std.mem.trim(u8, trimmed[7..], " \t");
    if (tok.len != 64) return null;
    if (!isHex64(tok)) return null;
    return tok;
}

/// Extract a `?bearer=<hex64>` token from a request target like
/// `/api/v1/wallet?bearer=<hex>` (note: target includes the `?`).
/// See also parseBearerQueryString — takes just the query-string slice.
pub fn parseBearerQuery(target: []const u8) ?[]const u8 {
    const q = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    const qs = target[q + 1 ..];
    var it = std.mem.splitScalar(u8, qs, '&');
    while (it.next()) |pair| {
        if (std.mem.startsWith(u8, pair, "bearer=")) {
            const v = pair[7..];
            if (v.len != 64) return null;
            if (!isHex64(v)) return null;
            return v;
        }
    }
    return null;
}

/// True iff `s` is exactly 64 hex chars [0-9a-fA-F].
pub fn isHex64(s: []const u8) bool {
    if (s.len != 64) return false;
    for (s) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
        if (!ok) return false;
    }
    return true;
}

/// Case-insensitive substring search.  Used by the WS upgrade path to
/// check `Connection: ... Upgrade ...` headers.
pub fn asciiContainsCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

/// JSON-encode a string into `out` (writes `"…"` with proper escapes).
/// Used by every handler that emits JSON-RPC responses.
pub fn jsonEncodeString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    s: []const u8,
) !void {
    try out.append(allocator, '"');
    for (s) |c| switch (c) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        0x08 => try out.appendSlice(allocator, "\\b"),
        0x0c => try out.appendSlice(allocator, "\\f"),
        0...0x07, 0x0b, 0x0e...0x1f => {
            var buf: [8]u8 = undefined;
            const slice = try std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c});
            try out.appendSlice(allocator, slice);
        },
        else => try out.append(allocator, c),
    };
    try out.append(allocator, '"');
}

```
