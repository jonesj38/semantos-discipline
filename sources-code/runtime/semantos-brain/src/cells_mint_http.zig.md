---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cells_mint_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.248517+00:00
---

# runtime/semantos-brain/src/cells_mint_http.zig

```zig
// BRAIN-GENERIC-MINT-VERB M1 — generic cell-mint HTTP endpoint (acceptor).
//
// One HTTP path that mints any cartridge's cellType, gated by the
// cartridge's declared capability, validated against the cellType's
// declared payloadSchema (M2), persisted via the brain's CellStore,
// and fan-out via the helm event broker.
//
// Spec: docs/design/BRAIN-GENERIC-MINT-VERB.md
//
// Wire shape:
//
//   POST /api/v1/cells
//   Authorization: Bearer <hex64>
//   Content-Type: application/json
//   Body: {
//     "typeHashHex": "<64 hex chars>",
//     "payload":     <arbitrary JSON object — opaque to acceptor>,
//     "capabilityProof": <optional structured field; bearer is the proof
//                        for v0.1.0 per Q-mint-3 = B + OI-1>
//   }
//
//   201 → {"cellId":"<sha256 of cell bytes>","persistedAt":<unix-ms>}
//   400 → {"error":"bad_request","hint":"..."}        // parse / shape
//   401 → {"error":"bearer_invalid"}
//   403 → {"error":"capability_denied","hint":"..."}  // cap not held
//   404 → {"error":"unknown_type_hash"}               // registry miss
//   405 → {"error":"method_not_allowed"}
//   413 → {"error":"payload_too_large"}
//   500 → {"error":"persist_failed"} | "publish_failed" etc.
//
// This module owns:
//   - the route prefix constant
//   - pure helpers (decodeTypeHashHex, parseRequestBody) — testable
//     in isolation without any HTTP or LMDB plumbing
//   - the Acceptor struct (vtable wrappers for registry + bearer +
//     cell store + helm broker), used by the reactor in
//     site_server/reactor.zig
//
// The reactor variant of the handler (`reactor.zig::handleCellsMint`)
// is the live caller; the std.http.Server-shape variant lives in
// site_server/reactor.zig too.

const std = @import("std");

const cell_store_mod = @import("cell_store");
const bearer_tokens = @import("bearer_tokens");
const cartridge_cell_registry = @import("cartridge_cell_registry");
const helm_event_broker = @import("helm_event_broker");
const identity_certs = @import("identity_certs");

pub const ROUTE: []const u8 = "/api/v1/cells";
pub const TYPE_HASH_HEX_LEN: usize = 64;
pub const MAX_BODY_BYTES: usize = 64 * 1024; // 64 KiB — well above any
// realistic mint payload; mirrors attachments_upload_http's body cap shape.

pub const Error = error{
    bad_request,
    bearer_invalid,
    capability_denied,
    unknown_type_hash,
    payload_too_large,
    persist_failed,
    publish_failed,
    out_of_memory,
};

/// Parsed shape of the POST body. `payload` is borrowed from the inbound
/// buffer; valid for the lifetime of the request.
pub const MintRequest = struct {
    type_hash: [32]u8,
    payload_json: []const u8,
    /// OI-1 placeholder: when the eventual cert+capability+challenge
    /// proof structure lands, this holds the raw proof bytes for the
    /// auth layer. v0.1.0 callers may omit it (bearer + per-cartridge
    /// capability is the gate). The field is captured here so M1's
    /// wire format is forward-compatible — adding `capabilityProof`
    /// later is a no-op for existing 201-passing requests.
    capability_proof_raw: ?[]const u8,
    /// C10 PR-2d (2026-05-28) — optional precondition opcode stream
    /// (base64-encoded). When present, the canonical mint pipeline
    /// evaluates these bytes through PolicyRuntime.evaluate in
    /// `.real_executor` mode (cell-engine 2-PDA) BEFORE persistence.
    /// Rejection short-circuits the mint with `kernel_rejected_locally`.
    /// Absent = current default-permit path unchanged.  See
    /// docs/design/REAL-EXECUTOR-WIRE.md §2 + matrix C10-B.
    opcode_bytes_b64: ?[]const u8 = null,
    /// C7-B Option A (2026-06-04) — optional operator signature over
    /// `sha256(canonicaliseCellPayload(payload))`, 64-byte compact r‖s.
    /// When present (with `signer_cert_id_hex`), the mint handler
    /// verifies it against the signer cert's pubkey BEFORE assembling,
    /// so the operator cryptographically authorises the mint (sovereign
    /// slice). Absent = bearer-only path unchanged.
    signature: ?[64]u8 = null,
    /// Hex cert-id of the signer (passed to `CertStore.get`). Present
    /// iff `signature` is present.
    signer_cert_id_hex: ?[]const u8 = null,
};

/// Decode 64 hex chars into a 32-byte typeHash. Returns null on bad input.
/// Pure mirror of `cell_raw_http.decodeHashHex` — kept as its own function
/// here so the module is self-contained and the dependency surface stays
/// narrow (cell_raw_http imports bearer_tokens + cell_store via the
/// Acceptor struct, but the pure parsers do not).
pub fn decodeTypeHashHex(hex_in: []const u8) ?[32]u8 {
    if (hex_in.len != TYPE_HASH_HEX_LEN) return null;
    var out: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        const hi: u8 = nibble(hex_in[i * 2]) orelse return null;
        const lo: u8 = nibble(hex_in[i * 2 + 1]) orelse return null;
        out[i] = (hi << 4) | lo;
    }
    return out;
}

fn nibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

/// Top-level JSON shape we accept on the mint POST body. Used with
/// `std.json.parseFromSlice` to get strict shape validation.
const RequestEnvelope = struct {
    typeHashHex: []const u8,
    /// JSON-object payload. The brain JSON-stringifies this and stores
    /// the UTF-8 bytes in the cell's payload section. EXACTLY ONE of
    /// `payload` or `payloadBytesHex` must be present.
    payload: ?std.json.Value = null,
    /// PR-8b-viii — hex-encoded raw payload bytes. When provided, the
    /// brain decodes the hex into binary bytes and stores those verbatim
    /// in the cell's payload section. This is the path handler scripts
    /// (PR-8b-ii / PR-8b-iii) need so the binary wire format at fixed
    /// offsets reaches `OP_READPAYLOAD` correctly. Handlers that read
    /// `payload[1..33]` etc. would otherwise see JSON-stringified text.
    /// EXACTLY ONE of `payload` or `payloadBytesHex` must be present.
    payloadBytesHex: ?[]const u8 = null,
    capabilityProof: ?std.json.Value = null,
    /// C10 PR-2d — optional base64-encoded precondition opcode stream.
    /// Default-permit when absent so existing PWA callers don't break.
    /// When present, evaluated via PolicyRuntime.evaluate(.real_executor).
    opcode_bytes_b64: ?[]const u8 = null,
    /// C7-B Option A — operator signature (64-byte r‖s as 128 hex chars)
    /// + signer cert-id hex. Both present or both absent.
    signatureHex: ?[]const u8 = null,
    signerCertIdHex: ?[]const u8 = null,
};

/// Parse the inbound POST body. Returns `error.bad_request` for any of:
///   - malformed JSON
///   - missing typeHashHex
///   - typeHashHex with wrong length / non-hex chars
///   - missing payload
///   - payload not an object (mint payloads MUST be objects — arrays /
///     scalars / null are rejected; cartridges that want list/scalar
///     state model it as a single-field object per cellType convention)
///
/// The returned `MintRequest.payload_json` is a NEWLY-allocated slice
/// containing the canonical serialised payload (re-stringified through
/// std.json) — this gives downstream persist a stable byte sequence to
/// embed and hash regardless of whitespace / key-order in the inbound
/// body. Caller owns the slice and frees via `allocator`.
///
/// `capability_proof_raw` is similarly re-stringified when present.
pub fn parseRequestBody(allocator: std.mem.Allocator, body: []const u8) Error!MintRequest {
    if (body.len == 0) return error.bad_request;
    if (body.len > MAX_BODY_BYTES) return error.payload_too_large;

    const parsed = std.json.parseFromSlice(RequestEnvelope, allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch return error.bad_request;
    defer parsed.deinit();

    const type_hash = decodeTypeHashHex(parsed.value.typeHashHex) orelse
        return error.bad_request;

    // PR-8b-viii — EXACTLY ONE of `payload` (JSON object → stringified)
    // or `payloadBytesHex` (hex → raw bytes) must be present.
    const have_payload = parsed.value.payload != null;
    const have_bytes = parsed.value.payloadBytesHex != null;
    if (have_payload == have_bytes) return error.bad_request;

    var payload_owned: []u8 = undefined;
    if (have_payload) {
        // Payload must be an object — guards against scalar/array/null
        // cells sneaking past the schema-validator (M2) which assumes
        // object shape.
        if (parsed.value.payload.? != .object) return error.bad_request;

        // Re-stringify the payload via std.json so persisted bytes are
        // canonical and stable across cosmetic variations in the inbound JSON.
        // valueAlloc is the canonical brain pattern (mirrors signed_bundle.zig,
        // intent_cell_lmdb_store.zig, voice_extract_http.zig).
        payload_owned = std.json.Stringify.valueAlloc(allocator, parsed.value.payload.?, .{}) catch
            return error.out_of_memory;
    } else {
        // PR-8b-viii — hex-decode the raw payload bytes. Length must be
        // even (each byte = 2 hex chars); the decoded byte count is
        // bounded by the same MAX_BODY_BYTES envelope and the downstream
        // 768-byte payload budget enforced in substrate_entity.
        const hex = parsed.value.payloadBytesHex.?;
        if (hex.len % 2 != 0) return error.bad_request;
        const byte_len = hex.len / 2;
        payload_owned = allocator.alloc(u8, byte_len) catch return error.out_of_memory;
        errdefer allocator.free(payload_owned);
        var i: usize = 0;
        while (i < byte_len) : (i += 1) {
            const hi = nibble(hex[i * 2]) orelse return error.bad_request;
            const lo = nibble(hex[i * 2 + 1]) orelse return error.bad_request;
            payload_owned[i] = (hi << 4) | lo;
        }
    }
    errdefer allocator.free(payload_owned);

    var proof_owned: ?[]const u8 = null;
    if (parsed.value.capabilityProof) |proof| {
        proof_owned = std.json.Stringify.valueAlloc(allocator, proof, .{}) catch
            return error.out_of_memory;
    }
    errdefer if (proof_owned) |p| allocator.free(p);

    // C10 PR-2d — copy opcode_bytes_b64 into an owned slice so its
    // lifetime detaches from `parsed` (which is deinit'd by defer above).
    var opcode_owned: ?[]const u8 = null;
    if (parsed.value.opcode_bytes_b64) |opc| {
        opcode_owned = allocator.dupe(u8, opc) catch return error.out_of_memory;
    }
    errdefer if (opcode_owned) |o| allocator.free(o);

    // C7-B Option A — optional operator signature. `signatureHex` (128
    // hex → 64-byte r‖s) + `signerCertIdHex` must be BOTH present or BOTH
    // absent; one without the other is a malformed sovereign mint.
    const have_sig = parsed.value.signatureHex != null;
    const have_signer = parsed.value.signerCertIdHex != null;
    if (have_sig != have_signer) return error.bad_request;
    var signature: ?[64]u8 = null;
    var signer_cert_id_owned: ?[]const u8 = null;
    if (have_sig) {
        const sig_hex = parsed.value.signatureHex.?;
        if (sig_hex.len != 128) return error.bad_request;
        var sig: [64]u8 = undefined;
        var si: usize = 0;
        while (si < 64) : (si += 1) {
            const hi = nibble(sig_hex[si * 2]) orelse return error.bad_request;
            const lo = nibble(sig_hex[si * 2 + 1]) orelse return error.bad_request;
            sig[si] = (hi << 4) | lo;
        }
        signature = sig;
        signer_cert_id_owned = allocator.dupe(u8, parsed.value.signerCertIdHex.?) catch
            return error.out_of_memory;
    }

    return .{
        .type_hash = type_hash,
        .payload_json = payload_owned,
        .capability_proof_raw = proof_owned,
        .opcode_bytes_b64 = opcode_owned,
        .signature = signature,
        .signer_cert_id_hex = signer_cert_id_owned,
    };
}

/// Free a MintRequest's owned slices. Pairs with `parseRequestBody`.
pub fn deinitRequest(allocator: std.mem.Allocator, req: *const MintRequest) void {
    allocator.free(req.payload_json);
    if (req.capability_proof_raw) |p| allocator.free(p);
    if (req.opcode_bytes_b64) |o| allocator.free(o);
    if (req.signer_cert_id_hex) |c| allocator.free(c);
}

/// Acceptor — borrowed vtable wrappers + boot-populated registry handle.
/// The handler in site_server/reactor.zig holds one of these for the
/// lifetime of the server. None of the pointed-to objects are owned
/// here; the brain main() outlives the acceptor.
///
/// PR-8b-ix — public-shape outcome of the optional cell-script handler
/// dispatch hook the reactor calls via `Acceptor.dispatch_input_cell_fn`.
/// Mirrors `cells_mint_handler.DispatchOutcome` but lives here so
/// `cells_mint_http` doesn't have to import `cells_mint_handler`
/// (which would close the dep loop, since cells_mint_handler already
/// imports cells_mint_http for the shared parser).
pub const DispatchOutcomeOpaque = union(enum) {
    /// No handler registered for this typeHash — caller should persist
    /// the input cell as a plain substrate cell and return 201.
    skipped,
    /// Handler ran to truthy completion. `emitted_count` reports how many
    /// brain-emitted + script-emitted cells were persisted via
    /// `cell_store.put` inside the dispatch path (separate from the
    /// input cell, which the caller persists at step 8 of the reactor).
    success: struct { emitted_count: u32 },
    /// Handler ran but returned falsy / trapped / emitted outside the
    /// allowlist. Caller should respond 400 + map the reason into the
    /// rejection body.
    rejection: []const u8,
    /// Infrastructure failure (allocation, cell-store write, executor
    /// trap that isn't "script said no"). Caller should respond 500.
    internal_error: []const u8,
};

/// `cell_store` is the persistence seam (same one cell_raw_http reads
/// from). `bearer_tokens` gates pre-flight auth. `broker` is the helm
/// event broker the handler publishes `cells.<cartridge-id>.minted`
/// events to (Q-mint-5 = B: single NATS-canonical publish, downstream
/// subscribers fan out). The cartridge cellType registry is module-scope
/// state (see `cartridge_cell_registry.zig`), not held here — boot
/// wires it before the server starts accepting.
pub const Acceptor = struct {
    cell_store: *const cell_store_mod.CellStore,
    bearer_tokens: *bearer_tokens.TokenStore,
    broker: *helm_event_broker.Broker,
    /// C7-B Option A — optional cert store for verifying operator
    /// signatures on sovereign mints. Null = no verification available
    /// (a sig-bearing mint then 401s; bearer-only mints are unaffected).
    /// Wired in cli/serve.zig once `cert_store` is up.
    certs: ?*identity_certs.CertStore = null,
    /// PR-8b-ix — optional cell-script handler dispatch hook. When
    /// non-null, the reactor calls this after encoding the input cell
    /// (substrate_entity.encodeFromTypeHash) and BEFORE persisting,
    /// so the HTTP `POST /api/v1/cells` path runs the SAME handler
    /// pipeline the REPL `cells mint` verb runs: lookup the script-
    /// handler registry, build per-script Context via the composite
    /// ScriptContextBuilder, execute the bytecode, walk the stack for
    /// emitted cells + persist them. Null preserves pre-PR-8b-ix
    /// behaviour (no handler dispatch — input cell is persisted as a
    /// substrate cell only, MNCA Context builder never fires,
    /// sign.request never emitted). The MNCA anchor smoke (PR-8b-vii)
    /// depends on this being wired in `serve.zig`.
    dispatch_input_cell_fn: ?*const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        type_hash: *const [32]u8,
        cartridge_id: []const u8,
        input_cell: *const [1024]u8,
    ) DispatchOutcomeOpaque = null,
    /// State pointer threaded into `dispatch_input_cell_fn`. Holds the
    /// `*cells_mint_handler.Handler` (or any equivalent dispatcher
    /// carrier) the thunk casts back to.
    dispatch_ctx: ?*anyopaque = null,

    /// PR-anchor-on-mint — when true, the reactor calls
    /// `anchor_emitter.AnchorEmitter.initWithBroker(.bsv, broker).emit()`
    /// after `cell_store.put` succeeds, publishing a `cell.created`
    /// event on the shared broker. The
    /// `anchor_queue_writer.AnchorQueueWriter` subscriber (attached in
    /// `serve.zig` when `BRAIN_ANCHOR_QUEUE_PATH` is set) appends a
    /// JSONL entry the `anchor-runner.ts` cartridge process tails +
    /// broadcasts via Metanet Desktop.
    ///
    /// Closes the gap Bridget Doran flagged 2026-06-03: the legacy
    /// `cell_handler.zig` (typed-object path) already wires
    /// AnchorEmitter via `initWithBroker(.bsv)`, but the generic
    /// `/api/v1/cells` mint path the cleavage apparatus shipped on
    /// top of (PR-8b-ix) doesn't — so NP OS substrate cells minted
    /// via that path get persisted but never anchored. Auto-anchor
    /// is orthogonal to the cleavage handler-dispatch hook above:
    /// the same mint can BOTH run a handler script AND auto-anchor;
    /// they're independent dimensions.
    ///
    /// Off by default to preserve existing test/legacy-config
    /// behaviour. Operators flip this on in `serve.zig` when they
    /// want the simple "every cell anchors" pipeline.
    auto_anchor_on_mint: bool = false,
};

/// Resolve a typeHash to its registered cellType metadata. Thin wrapper
/// that surfaces the registry miss as our `Error.unknown_type_hash` so
/// callers can pattern-match on a single error set.
pub fn resolveCellType(type_hash: *const [32]u8) Error!cartridge_cell_registry.CellTypeEntry {
    return cartridge_cell_registry.lookup(type_hash) orelse error.unknown_type_hash;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure parsers. Live-handler conformance lives in the
// reactor test suite (which can wire a real CellStore + bearer store).
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "decodeTypeHashHex — round-trip" {
    const hex = "0011223344556677889900aabbccddeeff00112233445566778899aabbccddee";
    const got = decodeTypeHashHex(hex) orelse @panic("expected Some");
    try testing.expectEqual(@as(u8, 0x00), got[0]);
    try testing.expectEqual(@as(u8, 0x11), got[1]);
    try testing.expectEqual(@as(u8, 0xff), got[16]);
    try testing.expectEqual(@as(u8, 0xee), got[31]);
}

test "decodeTypeHashHex — rejects wrong length" {
    try testing.expectEqual(@as(?[32]u8, null), decodeTypeHashHex(""));
    try testing.expectEqual(@as(?[32]u8, null), decodeTypeHashHex("abc"));
    try testing.expectEqual(@as(?[32]u8, null), decodeTypeHashHex("ab" ** 31));
    try testing.expectEqual(@as(?[32]u8, null), decodeTypeHashHex("ab" ** 33));
}

test "decodeTypeHashHex — rejects non-hex chars" {
    try testing.expectEqual(@as(?[32]u8, null), decodeTypeHashHex("g0" ** 32));
    try testing.expectEqual(@as(?[32]u8, null), decodeTypeHashHex("z" ** 64));
}

test "parseRequestBody — happy path" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":{"field":"value","n":42}}
    ;
    var req = try parseRequestBody(testing.allocator, body);
    defer deinitRequest(testing.allocator, &req);
    try testing.expectEqual(@as(u8, 0xab), req.type_hash[0]);
    try testing.expectEqual(@as(u8, 0xab), req.type_hash[31]);
    // Re-stringified payload should contain the field name + value.
    try testing.expect(std.mem.indexOf(u8, req.payload_json, "\"field\":\"value\"") != null);
    try testing.expect(std.mem.indexOf(u8, req.payload_json, "\"n\":42") != null);
    try testing.expectEqual(@as(?[]const u8, null), req.capability_proof_raw);
}

test "parseRequestBody — captures capabilityProof when present" {
    const body =
        \\{"typeHashHex":"
    ++ ("cd" ** 32) ++
        \\","payload":{"k":"v"},"capabilityProof":{"kind":"bearer","cert":"abc"}}
    ;
    var req = try parseRequestBody(testing.allocator, body);
    defer deinitRequest(testing.allocator, &req);
    const proof = req.capability_proof_raw orelse @panic("expected proof");
    try testing.expect(std.mem.indexOf(u8, proof, "\"kind\":\"bearer\"") != null);
}

// ── C7-B Option A — operator-signature parse tests ────────────────────

test "parseRequestBody — captures operator signature + cert id when present" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":{"rawText":"letting go"},"signatureHex":"
    ++ ("11" ** 64) ++
        \\","signerCertIdHex":"deadbeef"}
    ;
    var req = try parseRequestBody(testing.allocator, body);
    defer deinitRequest(testing.allocator, &req);
    const sig = req.signature orelse @panic("expected signature");
    try testing.expectEqual(@as(u8, 0x11), sig[0]);
    try testing.expectEqual(@as(u8, 0x11), sig[63]);
    try testing.expectEqualStrings("deadbeef", req.signer_cert_id_hex.?);
}

test "parseRequestBody — sig without certId (and vice versa) is rejected" {
    const sig_only =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":{"k":"v"},"signatureHex":"
    ++ ("11" ** 64) ++
        \\"}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, sig_only));
    const cert_only =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":{"k":"v"},"signerCertIdHex":"deadbeef"}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, cert_only));
}

test "parseRequestBody — rejects malformed signatureHex length" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":{"k":"v"},"signatureHex":"abcd","signerCertIdHex":"dd"}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — rejects malformed JSON" {
    const bad = "{ not valid json";
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, bad));
}

test "parseRequestBody — rejects empty body" {
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, ""));
}

test "parseRequestBody — rejects body over MAX_BODY_BYTES" {
    const huge = "x" ** (MAX_BODY_BYTES + 1);
    try testing.expectError(error.payload_too_large, parseRequestBody(testing.allocator, huge));
}

// ── PR-8b-viii — payloadBytesHex tests ────────────────────────────────

test "parseRequestBody — payloadBytesHex: round-trip raw bytes" {
    // 139-byte payload (mnca.anchor size) — version 1 + 32 zero hash + ...
    // For test purposes, use a 4-byte payload "DEADBEEF".
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payloadBytesHex":"deadbeef"}
    ;
    var req = try parseRequestBody(testing.allocator, body);
    defer deinitRequest(testing.allocator, &req);
    try testing.expectEqual(@as(usize, 4), req.payload_json.len);
    try testing.expectEqual(@as(u8, 0xde), req.payload_json[0]);
    try testing.expectEqual(@as(u8, 0xad), req.payload_json[1]);
    try testing.expectEqual(@as(u8, 0xbe), req.payload_json[2]);
    try testing.expectEqual(@as(u8, 0xef), req.payload_json[3]);
}

test "parseRequestBody — payloadBytesHex: rejects when both payload and payloadBytesHex present" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":{"k":"v"},"payloadBytesHex":"00"}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — rejects when neither payload nor payloadBytesHex present" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\"}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — payloadBytesHex: rejects odd-length hex" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payloadBytesHex":"abc"}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — payloadBytesHex: rejects non-hex chars" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payloadBytesHex":"gg"}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — payloadBytesHex: empty hex yields zero-length payload" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payloadBytesHex":""}
    ;
    var req = try parseRequestBody(testing.allocator, body);
    defer deinitRequest(testing.allocator, &req);
    try testing.expectEqual(@as(usize, 0), req.payload_json.len);
}

test "parseRequestBody — rejects bad typeHashHex length" {
    const body =
        \\{"typeHashHex":"abc","payload":{"k":"v"}}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — rejects non-hex typeHash" {
    const body =
        \\{"typeHashHex":"
    ++ ("gg" ** 32) ++
        \\","payload":{"k":"v"}}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — rejects missing typeHashHex" {
    const body =
        \\{"payload":{"k":"v"}}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — rejects missing payload" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\"}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — rejects scalar payload (must be object)" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":"just a string"}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — rejects array payload (must be object)" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":[1,2,3]}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — rejects null payload" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":null}
    ;
    try testing.expectError(error.bad_request, parseRequestBody(testing.allocator, body));
}

test "parseRequestBody — ignores unknown top-level fields" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":{"k":"v"},"extra":"ignored","idempotencyKey":"abc"}
    ;
    var req = try parseRequestBody(testing.allocator, body);
    defer deinitRequest(testing.allocator, &req);
    try testing.expectEqual(@as(u8, 0xab), req.type_hash[0]);
}

test "parseRequestBody — opcode_bytes_b64 absent → null (default-permit)" {
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":{"k":"v"}}
    ;
    var req = try parseRequestBody(testing.allocator, body);
    defer deinitRequest(testing.allocator, &req);
    try testing.expectEqual(@as(?[]const u8, null), req.opcode_bytes_b64);
}

test "parseRequestBody — opcode_bytes_b64 captured + owned" {
    // C10 PR-2d: "UQ==" is OP_1 (0x51) base64-encoded.  When PolicyRuntime
    // evaluates this, it pushes 1 onto the stack → truthy → permit.
    const body =
        \\{"typeHashHex":"
    ++ ("ab" ** 32) ++
        \\","payload":{"k":"v"},"opcode_bytes_b64":"UQ=="}
    ;
    var req = try parseRequestBody(testing.allocator, body);
    defer deinitRequest(testing.allocator, &req);
    const opc = req.opcode_bytes_b64 orelse @panic("expected opcode bytes");
    try testing.expectEqualStrings("UQ==", opc);
}

test "resolveCellType — surfaces registry miss as unknown_type_hash" {
    cartridge_cell_registry.resetForTest();
    var miss: [32]u8 = undefined;
    @memset(&miss, 0xFF);
    try testing.expectError(error.unknown_type_hash, resolveCellType(&miss));
}

test "resolveCellType — returns entry when registered" {
    cartridge_cell_registry.resetForTest();
    var h: [32]u8 = undefined;
    @memset(&h, 0xAA);
    try cartridge_cell_registry.register(.{
        .type_hash = h,
        .cartridge_id = "betterment",
        .cell_type_name = "practice.release",
        .linearity = .LINEAR,
        .capability_name = "BETTERMENT_INQUIRY",
        .payload_schema_raw = null,
    });
    const entry = try resolveCellType(&h);
    try testing.expectEqualStrings("betterment", entry.cartridge_id);
    try testing.expectEqualStrings("practice.release", entry.cell_type_name);
}

```
