---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cell_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.224646+00:00
---

# runtime/semantos-brain/src/cell_handler.zig

```zig
// cell_handler.zig — generic cell-create dispatcher resource.
// admin-create-cell Phase D.3.
//
// Resource name: "cell"
// Commands:
//   create  — encode a pre-validated cell payload and persist it
//
// The handler receives a JSON envelope with a pre-built cell_payload
// string. Field-level validation, schema lookup, typeHash enrichment,
// and payload construction are the caller's responsibility (admin_cmds
// does this before dispatching). The handler's job is: verify shape,
// encode the payload into a 1024-byte cell (entity_tag 0x10 =
// "generic cartridge cell"), call cell_store.put, return the hash.
//
// This design keeps the handler thin and reusable across transports
// (REPL, HTTP, signed_bundle). Per-cartridge substrate-teeth rules
// (FundRelease.qualifyingPurpose, ReportingObligation discharge) are
// handled by separate per-cartridge walkers, not here.
//
// Args shape for cell.create:
//   {
//     "cell_payload":     "<JSON string — the cell's self-describing content>",
//     "opcode_bytes_b64": "<base64 — OPTIONAL precondition script>"   (§11.10 order 2d)
//   }
//
// The cell_payload is embedded verbatim as the cell's body. It should
// be a self-describing JSON object containing at minimum cartridge_id,
// type_name, and fields. admin_cmds.zig builds this from the operator's
// REPL input + the schema's typeHash/linearity metadata.
//
// §11.10 order 2d — opcode_bytes_b64 is a forward-compat opt-in.  When
// present, the brain's PolicyRuntime evaluates the script as a write
// precondition; rejection blocks the LMDB persist.  Generic cells today
// (admin REPL, cartridge walkers) omit this field, so behaviour is
// unchanged for every existing caller.  Cells gated by script
// preconditions (future protocol evolution) opt in by sending the field.
// Backend = kernel_zig syntactic shim today; swaps to real executor.zig
// under order 2e — interface-preserving.

const std = @import("std");
const dispatcher = @import("dispatcher");
const cell_store_mod = @import("cell_store");
const entity_cell = @import("entity_cell");
// §11.10 order 2d — brain's PolicyRuntime seam for opcode preconditions.
// See runtime/semantos-brain/src/policy_runtime.zig header for shape
// mirror against packages/policy-runtime/src/types.ts.
const policy_runtime = @import("policy_runtime");
// §11.10 order 2d follow-up (task #20) — canonical 256-byte cell format
// seam.  When the payload carries a recognised cartridge_id+type_name,
// we encode through substrate_entity (kernel-readable, K1/K3 enforceable).
// Otherwise fall back to entity_cell (legacy 16-byte header, opaque to
// the kernel).  See docs/prd/ENTITY-CELL-DECOMMISSION.md §3 + R2.
const substrate_entity = @import("substrate_entity");
// §11.10 order 3a step 2 — brain's AnchorEmitter seam.  After every
// successful cell_store.put we enqueue an on-chain anchor (best-effort;
// anchor failures DO NOT fail the cell.create — anchoring is a
// post-write side effect, not a precondition).  Stub backend today
// (synthesises a deterministic txid for traceability); real backend
// bridges to cartridges/wallet-headers under task #16.
const anchor_emitter = @import("anchor_emitter");
// §11.10 order 3a step 3 PR-3a-bridge-2b — broker handle threaded so
// the anchor seam can flip from .stub to .bsv.  Production callers
// construct the Handler via initWithBroker; tests use init() and stay
// on .stub.
const helm_event_broker = @import("helm_event_broker");

pub const RESOURCE_NAME = "cell";

pub const ENTITY_TAG_GENERIC_CARTRIDGE: u32 = 0x10;

pub const HandlerError = error{
    invalid_args,
    payload_too_large,
    store_error,
    out_of_memory,
};

pub const Handler = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    mu: std.Thread.Mutex,
    /// Borrowed broker handle for .bsv-mode AnchorEmitter.  Null means
    /// .stub mode (deterministic synthetic txid; no on-chain effects).
    /// Production wiring lives at cli/serve.zig which constructs the
    /// Handler via initWithBroker.
    broker: ?*helm_event_broker.Broker = null,

    pub fn init(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
    ) Handler {
        return .{
            .allocator = allocator,
            .cell_store = cell_store,
            .mu = .{},
            .broker = null,
        };
    }

    /// §11.10 order 3a PR-3a-bridge-2b — construct a Handler whose
    /// AnchorEmitter call dispatches to .bsv mode (publishes
    /// `cell.created` on the broker for the wallet-headers cartridge
    /// subscriber to consume).  Pass the process-scoped broker handle
    /// from cli/serve.zig.
    pub fn initWithBroker(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        broker: *helm_event_broker.Broker,
    ) Handler {
        return .{
            .allocator = allocator,
            .cell_store = cell_store,
            .mu = .{},
            .broker = broker,
        };
    }

    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
            .audit_reads = false,
            .is_read_fn = isRead,
        };
    }
};

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "create")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "list")) return .{ .require = "cap.brain.admin" };
    return error.unknown_command;
}

pub fn isRead(cmd: []const u8) bool {
    if (std.mem.eql(u8, cmd, "list")) return true;
    return false;
}

fn handle(
    state: ?*anyopaque,
    _: *const dispatcher.DispatchContext,
    cmd: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    if (std.mem.eql(u8, cmd, "create")) return handleCreate(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "list")) return handleList(self, allocator, args_json);
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// cell.create
// ─────────────────────────────────────────────────────────────────────

const CreateArgs = struct {
    cell_payload: []const u8,
    /// §11.10 order 2d — optional precondition opcode stream (base64).
    /// When present, evaluated via PolicyRuntime before LMDB persistence;
    /// rejection short-circuits the write.  Absent = current path
    /// (straight encode + put) unchanged for every existing caller.
    opcode_bytes_b64: ?[]const u8 = null,
};

fn handleCreate(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const parsed = std.json.parseFromSlice(CreateArgs, allocator, args_json, .{
        .ignore_unknown_fields = true,
    }) catch return HandlerError.invalid_args;
    defer parsed.deinit();

    const payload = parsed.value.cell_payload;
    if (payload.len == 0) return HandlerError.invalid_args;
    if (payload.len > entity_cell.MAX_PAYLOAD_BYTES) return HandlerError.payload_too_large;

    // §11.10 order 2d — opcode precondition gate.  Evaluated via the
    // brain's PolicyRuntime so the backend (syntactic shim today; real
    // executor.zig under order 2e) can swap without changing this call
    // site.  Generic cell.create has no cert/cap binding in its envelope
    // today — those land via DispatchContext when order 1 (Dispatcher
    // Phase 1) wires cert auth; until then the syntactic-shim backend
    // ignores context entirely.
    if (parsed.value.opcode_bytes_b64) |b64| {
        const decoded = decodeBase64(allocator, b64) catch
            return HandlerError.invalid_args;
        defer allocator.free(decoded);

        // C10 PR-2c (2026-05-28): flip to .real_executor mode so the cell
        // engine's 2-PDA actually enforces declared preconditions instead
        // of just frame-validating the opcode bytes. Per
        // docs/design/REAL-EXECUTOR-WIRE.md §2 + matrix C10-A.
        // Existing .syntactic_shim stays callable via PR-2e fallback.
        var rt = policy_runtime.PolicyRuntime.initWithMode(allocator, .real_executor);
        const policy_ctx = policy_runtime.PolicyContext{
            .actor = .{ .cert_id = "", .capabilities = &[_]u32{} },
            .co_actor = null,
        };
        const policy_result = rt.evaluate(decoded, policy_ctx) catch
            return writeRejection(
                allocator,
                "kernel_local_exec_failed",
                "brain-side PolicyRuntime infrastructure error",
                null,
            );
        if (!policy_result.ok) {
            return writeRejection(
                allocator,
                "kernel_rejected_locally",
                "PolicyRuntime rejected the opcode precondition stream",
                policy_result.rejection_code,
            );
        }
    }

    // §11.10 order 2d follow-up — try canonical 256-byte format first
    // (kernel-readable). If the payload doesn't declare a recognised
    // cartridge_id+type_name OR exceeds the substrate payload budget
    // (768 bytes), fall back to legacy entity_cell encoding (kernel-
    // opaque). See docs/prd/ENTITY-CELL-DECOMMISSION.md §3.
    const cell = encodeWithSubstrateOrFallback(payload) catch
        return HandlerError.payload_too_large;

    const hash = self.cell_store.put(&cell) catch return HandlerError.store_error;

    // §11.10 order 3a — anchor the just-persisted cell.  Best-effort:
    // failures / skips do NOT fail the cell.create.  When the Handler
    // was constructed via initWithBroker (production via cli/serve.zig),
    // this dispatches to .bsv mode → publishes "cell.created" on the
    // broker → wallet-headers cartridge subscriber broadcasts the BSV
    // tx asynchronously.  When constructed via init() (tests / REPL
    // smokes), stays on .stub mode → deterministic synthetic txid for
    // observability.
    //
    // type_hash extraction: if encodeWithSubstrateOrFallback took the
    // substrate path (canonical 256-byte header), bytes [30..62] are
    // the cell's type_hash.  Detect via the magic prefix (MAGIC_1
    // 0xDEADBEEF LE at offset 0, MAGIC_2 0xCAFEBABE LE at offset 4 —
    // same encoding substrate_entity.zig writes).  Legacy fallback
    // cells leave type_hash as zeros; emitBsv rejects with
    // type_hash_missing in .bsv mode, which is the correct behaviour
    // (anchoring a cell without a canonical typeHash gives the wallet
    // no derivation domain).
    var anchor_ctx: anchor_emitter.AnchorContext = .{
        .cell_hash = hash,
        .entity_tag = ENTITY_TAG_GENERIC_CARTRIDGE,
        .cartridge_id = "generic",
    };
    if (cell.len >= 8) {
        const magic_1 = std.mem.readInt(u32, cell[0..4], .little);
        const magic_2 = std.mem.readInt(u32, cell[4..8], .little);
        if (magic_1 == 0xDEADBEEF and magic_2 == 0xCAFEBABE) {
            @memcpy(&anchor_ctx.type_hash, cell[30..62]);
        }
    }
    var anchor_em = if (self.broker) |broker|
        anchor_emitter.AnchorEmitter.initWithBroker(self.allocator, .bsv, broker)
    else
        anchor_emitter.AnchorEmitter.init(self.allocator, .stub);
    _ = anchor_em.emit(anchor_ctx);

    var hex: [64]u8 = undefined;
    for (hash, 0..) |byte, i| {
        hex[i * 2] = "0123456789abcdef"[byte >> 4];
        hex[i * 2 + 1] = "0123456789abcdef"[byte & 0x0f];
    }

    const result_json = std.fmt.allocPrint(
        allocator,
        "{{\"ok\":true,\"cell_hash\":\"{s}\",\"payload_bytes\":{d}}}",
        .{ hex[0..64], payload.len },
    ) catch return HandlerError.out_of_memory;

    return dispatcher.Result.ownedPayload(allocator, result_json);
}

// ─────────────────────────────────────────────────────────────────────
// cell.list — scan all generic cartridge cells, filter by
// cartridge_id and/or type_name.
// ─────────────────────────────────────────────────────────────────────

const ListArgs = struct {
    cartridge_id: ?[]const u8 = null,
    type_name: ?[]const u8 = null,
};

fn handleList(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const parsed = std.json.parseFromSlice(ListArgs, allocator, args_json, .{
        .ignore_unknown_fields = true,
    }) catch return HandlerError.invalid_args;
    defer parsed.deinit();

    const filter_cartridge = parsed.value.cartridge_id;
    const filter_type = parsed.value.type_name;

    const cursor = self.cell_store.cursorOpen() catch return HandlerError.store_error;
    defer self.cell_store.cursorClose(cursor);

    var result_buf: std.ArrayList(u8) = .empty;
    errdefer result_buf.deinit(allocator);
    try result_buf.appendSlice(allocator, "{\"ok\":true,\"cells\":[");

    var count: usize = 0;
    while (self.cell_store.cursorPull(cursor) catch null) |cell| {
        const tag = entity_cell.cellEntityTag(cell);
        if (tag != ENTITY_TAG_GENERIC_CARTRIDGE) continue;

        const payload = entity_cell.cellPayload(cell);
        if (payload.len == 0) continue;

        const inner = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch continue;
        defer inner.deinit();
        if (inner.value != .object) continue;
        const obj = inner.value.object;

        const cell_cartridge = if (obj.get("cartridge_id")) |v| (if (v == .string) v.string else null) else null;
        const cell_type = if (obj.get("type_name")) |v| (if (v == .string) v.string else null) else null;

        if (filter_cartridge) |fc| {
            const cc = cell_cartridge orelse continue;
            if (!std.mem.eql(u8, cc, fc)) continue;
        }
        if (filter_type) |ft| {
            const ct = cell_type orelse continue;
            if (!std.mem.eql(u8, ct, ft)) continue;
        }

        // Compute cell hash (SHA-256 of the 1024 bytes).
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(cell);
        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        var hex: [64]u8 = undefined;
        for (hash, 0..) |byte, i| {
            hex[i * 2] = "0123456789abcdef"[byte >> 4];
            hex[i * 2 + 1] = "0123456789abcdef"[byte & 0x0f];
        }

        if (count > 0) try result_buf.append(allocator, ',');
        try result_buf.appendSlice(allocator, "{\"cell_hash\":\"");
        try result_buf.appendSlice(allocator, &hex);
        try result_buf.appendSlice(allocator, "\",\"payload\":");
        try result_buf.appendSlice(allocator, payload);
        try result_buf.append(allocator, '}');
        count += 1;
    }

    try result_buf.appendSlice(allocator, "],\"count\":");
    var count_buf: [16]u8 = undefined;
    const count_str = std.fmt.bufPrint(&count_buf, "{d}", .{count}) catch "0";
    try result_buf.appendSlice(allocator, count_str);
    try result_buf.append(allocator, '}');

    return dispatcher.Result.ownedPayload(allocator, try result_buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// §11.10 order 2d helpers — opcode-precondition support.
// ─────────────────────────────────────────────────────────────────────

/// §11.10 order 2d follow-up (task #20): try to encode `payload` in the
/// canonical 256-byte cell format via `substrate_entity` when the
/// payload declares a recognised `cartridge_id` + `type_name`.  Fall
/// back to the legacy 16-byte entity_cell format otherwise.
///
/// Resolution rules (option B(a) per ENTITY-CELL-DECOMMISSION.md §9):
///   1. Extract `"cartridge_id":"VAL"` + `"type_name":"VAL"` from the
///      payload via a simple substring scan (cheap; sufficient for
///      first-level JSON fields populated by admin_cmds.zig).
///   2. Build `"{cartridge_id}.{type_name}"` and look up via
///      `substrate_entity.specByTypePath`.  Matches built-in oddjobz
///      specs + cartridge-registered specs (P3a).
///   3. If spec found AND `payload.len <= PAYLOAD_BUDGET` (768),
///      encode through `substrate_entity.encodeEntity` (kernel-readable).
///   4. Otherwise — unregistered cartridge OR payload too large for
///      canonical — fall back to `entity_cell.encodeCell` (legacy).
///      This is the "load-bearing fallback" per the audit; preserves
///      forward-compat for cartridges that haven't registered specs
///      yet (e.g. Bridget's NP OS while she's building).
///
/// Future: when STRUCTURED-TYPEHASH-CANONICAL lands (task #27), the
/// resolution surface may shift to type_hash-direct lookup; this
/// helper is the call site to re-touch (~10 lines).
fn encodeWithSubstrateOrFallback(payload: []const u8) entity_cell.EncodeError![entity_cell.CELL_BYTES]u8 {
    if (payload.len <= substrate_entity.PAYLOAD_BUDGET) {
        if (resolveSpecFromPayload(payload)) |spec| {
            const state = substrate_entity.extractStateOrStatus(payload);
            const linearity = substrate_entity.linearityFor(spec.tag, state);
            // owner_id zero-filled — generic cell.create has no caller
            // cert binding today.  When BRAIN-DISPATCHER-UNIFICATION
            // Phase 1 wires cert auth through DispatchContext, owner_id
            // becomes derivable from ctx.auth.cert.  Until then, audit
            // surfaces unowned cells the same way the per-store stores
            // already do (e.g. customers_store_lmdb.zig line 36).
            return substrate_entity.encodeEntity(.{
                .spec = spec,
                .linearity = linearity,
                .owner_id = [_]u8{0} ** 16,
                .payload_json = payload,
            }) catch |err| switch (err) {
                error.payload_too_large => return entity_cell.encodeCell(
                    ENTITY_TAG_GENERIC_CARTRIDGE,
                    payload,
                ),
            };
        }
    }
    // No spec OR payload exceeds canonical budget — legacy fallback.
    return entity_cell.encodeCell(ENTITY_TAG_GENERIC_CARTRIDGE, payload);
}

/// Resolve a substrate_entity spec from a cell.create payload by
/// extracting `cartridge_id` + `type_name` and looking up the
/// resulting `"{cartridge_id}.{type_name}"` type path.  Returns null
/// if either field is missing or the type path isn't registered.
fn resolveSpecFromPayload(payload: []const u8) ?substrate_entity.EntityTypeSpec {
    const cartridge_id = extractJsonStringField(payload, "cartridge_id") orelse return null;
    const type_name = extractJsonStringField(payload, "type_name") orelse return null;
    // Build "{cartridge_id}.{type_name}" on the stack — bounded by
    // the substring buffer below.  Max realistic size is small
    // (cartridge ids + type names are short identifiers).
    var path_buf: [256]u8 = undefined;
    if (cartridge_id.len + 1 + type_name.len > path_buf.len) return null;
    @memcpy(path_buf[0..cartridge_id.len], cartridge_id);
    path_buf[cartridge_id.len] = '.';
    @memcpy(path_buf[cartridge_id.len + 1 ..][0..type_name.len], type_name);
    const type_path = path_buf[0 .. cartridge_id.len + 1 + type_name.len];
    return substrate_entity.specByTypePath(type_path);
}

/// Extract `"field":"VALUE"` from a JSON string.  Returns a borrowed
/// slice into `json` pointing at the value bytes, or null if the field
/// isn't found.  Lightweight substring scan — no allocator, no full
/// JSON parse.  Sufficient for first-level string fields where the
/// caller controls the JSON shape (cell.create's payload structure is
/// set by admin_cmds.zig).  Does not handle escaped quotes inside the
/// value; cartridge_id + type_name are short identifiers without
/// escapes, so the simplification is sound for this call site.
fn extractJsonStringField(json: []const u8, field: []const u8) ?[]const u8 {
    // Build the needle: `"FIELD":"`.  Bounded stack buffer.
    var needle_buf: [128]u8 = undefined;
    const needle_len = field.len + 4; // `"`, `"`, `:`, `"`
    if (needle_len > needle_buf.len) return null;
    needle_buf[0] = '"';
    @memcpy(needle_buf[1 .. 1 + field.len], field);
    needle_buf[1 + field.len] = '"';
    needle_buf[2 + field.len] = ':';
    needle_buf[3 + field.len] = '"';
    const needle = needle_buf[0..needle_len];

    const start = std.mem.indexOf(u8, json, needle) orelse return null;
    const value_start = start + needle_len;
    if (value_start >= json.len) return null;
    const value_end_rel = std.mem.indexOfScalar(u8, json[value_start..], '"') orelse return null;
    return json[value_start..][0..value_end_rel];
}

/// Decode base64 input.  Caller frees the returned slice.  Returns
/// `error.invalid_base64` if the input isn't valid base64; the caller
/// maps this to whatever its error convention is (cell.create surfaces
/// it as `invalid_args`).
fn decodeBase64(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const max_len = decoder.calcSizeForSlice(input) catch return error.invalid_base64;
    const out = try allocator.alloc(u8, max_len);
    errdefer allocator.free(out);
    decoder.decode(out, input) catch return error.invalid_base64;
    return out;
}

/// Build a structured rejection response for a policy / precondition
/// failure.  Mirrors the intent_cells failure shape (`{ok:false, error,
/// hint, rejection_code?}`) so callers can pattern-match on the same
/// keys regardless of which cartridge handler rejected.
fn writeRejection(
    allocator: std.mem.Allocator,
    error_kind: []const u8,
    hint: []const u8,
    rejection_code: ?[]const u8,
) !dispatcher.Result {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"ok\":false,\"error\":\"");
    try buf.appendSlice(allocator, error_kind);
    try buf.appendSlice(allocator, "\",\"hint\":\"");
    try buf.appendSlice(allocator, hint);
    try buf.append(allocator, '"');
    if (rejection_code) |rc| {
        try buf.appendSlice(allocator, ",\"rejection_code\":\"");
        try buf.appendSlice(allocator, rc);
        try buf.append(allocator, '"');
    }
    try buf.append(allocator, '}');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure-function coverage for the §11.10 order 2d helpers.
// Full handler coverage (cell_store side effects) belongs in a
// conformance test under tests/ — out of scope for this PR.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "decodeBase64: round-trip" {
    const decoded = try decodeBase64(testing.allocator, "aGVsbG8=");
    defer testing.allocator.free(decoded);
    try testing.expectEqualStrings("hello", decoded);
}

test "decodeBase64: rejects invalid input" {
    try testing.expectError(error.invalid_base64, decodeBase64(testing.allocator, "!!!"));
}

test "writeRejection: emits {ok:false, error, hint} for policy_runtime path" {
    var result = try writeRejection(
        testing.allocator,
        "kernel_rejected_locally",
        "PolicyRuntime rejected the opcode precondition stream",
        "invalid_pushdata",
    );
    defer result.deinit();
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"ok\":false") != null);
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"error\":\"kernel_rejected_locally\"") != null);
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"rejection_code\":\"invalid_pushdata\"") != null);
}

test "writeRejection: omits rejection_code when null" {
    var result = try writeRejection(
        testing.allocator,
        "kernel_local_exec_failed",
        "infrastructure error",
        null,
    );
    defer result.deinit();
    try testing.expect(std.mem.indexOf(u8, result.payload, "rejection_code") == null);
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"error\":\"kernel_local_exec_failed\"") != null);
}

// ─────────────────────────────────────────────────────────────────────
// §11.10 order 2d follow-up (task #20) — substrate_entity dual-path
// helper coverage.  Pure-function tests; no cell_store fixture needed.
// ─────────────────────────────────────────────────────────────────────

test "extractJsonStringField: finds first-level string field" {
    const json =
        \\{"cartridge_id":"oddjobz","type_name":"customer","fields":{"name":"alice"}}
    ;
    try testing.expectEqualStrings("oddjobz", extractJsonStringField(json, "cartridge_id").?);
    try testing.expectEqualStrings("customer", extractJsonStringField(json, "type_name").?);
}

test "extractJsonStringField: returns null for missing field" {
    const json =
        \\{"cartridge_id":"oddjobz"}
    ;
    try testing.expect(extractJsonStringField(json, "missing") == null);
}

test "resolveSpecFromPayload: oddjobz built-in type → canonical spec" {
    const json =
        \\{"cartridge_id":"oddjobz","type_name":"customer","fields":{}}
    ;
    const spec = resolveSpecFromPayload(json).?;
    try testing.expectEqualStrings("oddjobz.customer", spec.type_path);
    try testing.expectEqual(substrate_entity.TAG_CUSTOMER, spec.tag);
}

test "resolveSpecFromPayload: unregistered cartridge → null" {
    const json =
        \\{"cartridge_id":"npos","type_name":"Grant","fields":{}}
    ;
    try testing.expect(resolveSpecFromPayload(json) == null);
}

test "resolveSpecFromPayload: missing cartridge_id → null" {
    const json =
        \\{"type_name":"customer","fields":{}}
    ;
    try testing.expect(resolveSpecFromPayload(json) == null);
}

test "encodeWithSubstrateOrFallback: registered type → canonical 256-byte header (magic present)" {
    const json =
        \\{"cartridge_id":"oddjobz","type_name":"customer","fields":{"name":"alice"},"state":"active"}
    ;
    const cell = try encodeWithSubstrateOrFallback(json);
    // substrate_entity writes magic as u32 LE values:
    //   cell[0..4] = LE(0xDEADBEEF) = EF BE AD DE
    //   cell[4..8] = LE(0xCAFEBABE) = BE BA FE CA
    // (NB: differs from cell.zig's raw-bytes MAGIC_BYTES sequence; this
    // matches substrate_entity.zig's actual encoding — see that file's
    // OFFSET_MAGIC_1/2 writes.  Substrate-wide magic format reconciliation
    // is out of scope for this PR — see STRUCTURED-TYPEHASH program.)
    try testing.expectEqual(@as(u8, 0xEF), cell[0]);
    try testing.expectEqual(@as(u8, 0xBE), cell[1]);
    try testing.expectEqual(@as(u8, 0xAD), cell[2]);
    try testing.expectEqual(@as(u8, 0xDE), cell[3]);
    try testing.expectEqual(@as(u8, 0xBE), cell[4]);
    try testing.expectEqual(@as(u8, 0xBA), cell[5]);
}

test "encodeWithSubstrateOrFallback: unregistered type → legacy entity_cell (no canonical magic)" {
    const json =
        \\{"cartridge_id":"npos","type_name":"Grant","fields":{}}
    ;
    const cell = try encodeWithSubstrateOrFallback(json);
    // Legacy entity_cell header is tag(u32 LE) at offset 0; for the
    // GENERIC_CARTRIDGE tag (0x10) the first byte is 0x10.
    try testing.expectEqual(@as(u8, 0x10), cell[0]); // ENTITY_TAG_GENERIC_CARTRIDGE
    try testing.expect(cell[0] != 0xEF); // not canonical substrate_entity magic
}


```
