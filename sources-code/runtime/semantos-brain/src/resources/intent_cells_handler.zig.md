---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/resources/intent_cells_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.294833+00:00
---

# runtime/semantos-brain/src/resources/intent_cells_handler.zig

```zig
// Phase 3 — typed `intent_cells` dispatcher resource.
//
// Reference: docs/spec/oddjobz-intent-cell-v1.md (the canonical
//            wire-format + error-shape contract this handler
//            implements);
//            runtime/semantos-brain/src/resources/leads_handler.zig (the closest
//            structural analogue: per-call arena, mutex-guarded entry
//            points, broker emission with operator-attention=true,
//            audit-log pairing);
//            runtime/semantos-brain/src/intent_cells_store_fs.zig (the persistence
//            sink this handler fronts);
//            runtime/semantos-brain/src/policy_runtime.zig (the brain's
//            PolicyRuntime seam called from `submit`; §11.10 order 2c.
//            Its backend today is runtime/semantos-brain/src/kernel_zig.zig
//            syntactic shim — swaps to real executor.zig under order 2e).
//
// Resource: `intent_cells`.  Verbs:
//   submit       — { envelope_json: "<full envelope JSON as string>" }
//                                                cap = cap.oddjobz.write_customer
//                                              The architectural heart:
//                                              parse + validate envelope,
//                                              resolve certId, validate
//                                              hat-chain binding, decode
//                                              opcode bytes, re-execute
//                                              kernel locally, persist
//                                              the cell with brain's local
//                                              kernel values, emit
//                                              `intent_cell.created` with
//                                              requires_operator_attention
//                                              = true, audit-log.
//   find         — { hat_id?, since?, limit? } →  [IntentCellRecord, ...]
//                                                cap = cap.oddjobz.read_jobs
//   find_by_id   — { cell_id }                →  IntentCellRecord
//                                                cap = cap.oddjobz.read_jobs
//                                              (or {error:"not_found",
//                                               cell_id:"..."} on miss)
//
// Concurrency: a single mutex (`mu`) serialises all entry points
// against the live store.  Same shape as leads_handler.zig — the
// poll-based reactor is single-threaded so the mutex is for cross-
// transport contention (REPL + Unix socket + HTTP all funnel through
// the same dispatcher).

const std = @import("std");
const dispatcher = @import("dispatcher");
// W0.3: intent cells now stored in LMDB via IntentCellLmdbStore.
// intent_cells_store_fs is kept as an import only for the constants
// (MAX_* field lengths, renderIsoTimestamp) used by the envelope parser
// and the submit pipeline.  The store itself is IntentCellLmdbStore.
const intent_cells_store_fs = @import("intent_cells_store_fs");
const intent_cell_lmdb_store = @import("intent_cell_lmdb_store");
const helm_event_broker = @import("helm_event_broker");
const audit_log = @import("audit_log");
const identity_certs = @import("identity_certs");
// §11.10 order 2c (2026-05-25) — replaced direct kernel_zig import with
// the brain's PolicyRuntime seam.  Cartridge handlers call PolicyRuntime
// so the backend (syntactic shim today; real executor.zig under order 2e)
// can swap without touching call sites.  See policy_runtime.zig header
// for the shape mirror against packages/policy-runtime/src/types.ts.
const policy_runtime = @import("policy_runtime");
// §11.10 order 3a step 2 — anchor every persisted intent cell.  Best-
// effort: after a successful store.create, brain enqueues an anchor
// request via AnchorEmitter.  Failures DO NOT fail submit — the cell
// is durably persisted regardless; anchor is a post-write side effect.
// Stub backend today; real backend bridges to cartridges/wallet-headers
// under task #16.
const anchor_emitter = @import("anchor_emitter");

pub const RESOURCE_NAME = "intent_cells";

/// Phase 1 cap reuse (per spec): submit reuses `cap.oddjobz.write_
/// customer` until a dedicated `cap.oddjobz.submit_intent` lands.
/// Reads reuse `cap.oddjobz.read_jobs`.
pub const CAP_READ_INTENT_CELLS: []const u8 = "cap.oddjobz.read_jobs";
pub const CAP_SUBMIT_INTENT: []const u8 = "cap.oddjobz.write_customer";

/// Spec-shape error tokens.  Each one round-trips into the response
/// payload's `error` field; mobile's outbox flush adapter pattern-
/// matches on the literal token to decide retry vs discard.
pub const ERR_ENVELOPE_INVALID: []const u8 = "envelope_invalid";
pub const ERR_CERT_UNKNOWN: []const u8 = "cert_unknown";
pub const ERR_CERT_BINDING_MISMATCH: []const u8 = "cert_binding_mismatch";
pub const ERR_KERNEL_REJECTED_LOCALLY: []const u8 = "kernel_rejected_locally";
pub const ERR_KERNEL_LOCAL_EXEC_FAILED: []const u8 = "kernel_local_exec_failed";
pub const ERR_CELL_ID_IN_USE: []const u8 = "cell_id_in_use_with_different_contents";
pub const ERR_PERSISTENCE_FAILED: []const u8 = "persistence_failed";

/// Constants pulled in from the spec for runtime validation.
pub const ENVELOPE_KIND: []const u8 = "oddjobz.intent_cell.v1";
pub const ENVELOPE_VERSION: i64 = 1;
pub const MAX_OPCODE_BYTES: usize = 10_240; // 10 KiB

/// §11.10 order 3a PR-3a-bridge-2b — stable type_hash the AnchorEmitter
/// passes to the wallet-headers cartridge for BRC-42 anchor-key
/// derivation.  Computed once at module load as
/// `SHA-256(ENVELOPE_KIND)` so all intent_cells share one derivation
/// domain — the cartridge can spend any historical intent-cell anchor
/// by iterating the per-typehash anchor index counter (per
/// cell-anchor.ts deriveCellAnchorSk).
///
/// Intent cells today use intent_cell_lmdb_store.encodeCell which
/// writes only a PHASE_ACTION byte at the legacy header offset — no
/// canonical typeHash field.  Synthesising a stable type_hash here
/// keeps the wallet's anchor-key family deterministic without
/// requiring intent_cell_lmdb_store to grow a canonical header.
const INTENT_CELL_TYPE_HASH: [32]u8 = computeIntentCellTypeHash();

fn computeIntentCellTypeHash() [32]u8 {
    @setEvalBranchQuota(10_000);
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(ENVELOPE_KIND, &out, .{});
    return out;
}

pub const HandlerError = error{
    invalid_args,
    out_of_memory,
    store_error,
};

/// State carried alongside the resource registration.
pub const Handler = struct {
    allocator: std.mem.Allocator,
    // W0.3: store is now IntentCellLmdbStore (phase-0x06 LMDB cells).
    store: *intent_cell_lmdb_store.IntentCellLmdbStore,
    cert_store: ?*identity_certs.CertStore,
    mu: std.Thread.Mutex,
    broker: ?*helm_event_broker.Broker,
    audit: ?*audit_log.AuditLog,

    pub fn init(
        allocator: std.mem.Allocator,
        store: *intent_cell_lmdb_store.IntentCellLmdbStore,
    ) Handler {
        return initWithDeps(allocator, store, null, null, null);
    }

    pub fn initWithDeps(
        allocator: std.mem.Allocator,
        store: *intent_cell_lmdb_store.IntentCellLmdbStore,
        cert_store: ?*identity_certs.CertStore,
        broker: ?*helm_event_broker.Broker,
        audit: ?*audit_log.AuditLog,
    ) Handler {
        return .{
            .allocator = allocator,
            .store = store,
            .cert_store = cert_store,
            .mu = .{},
            .broker = broker,
            .audit = audit,
        };
    }

    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "submit")) return .{ .require = CAP_SUBMIT_INTENT };
    if (std.mem.eql(u8, cmd, "find")) return .{ .require = CAP_READ_INTENT_CELLS };
    if (std.mem.eql(u8, cmd, "find_by_id")) return .{ .require = CAP_READ_INTENT_CELLS };
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Dispatch entry point
// ─────────────────────────────────────────────────────────────────────

fn handle(
    state: ?*anyopaque,
    ctx: *const dispatcher.DispatchContext,
    cmd: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    _ = ctx;
    if (std.mem.eql(u8, cmd, "submit")) return handleSubmit(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "find")) return handleFind(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "find_by_id")) return handleFindById(self, allocator, args_json);
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// `intent_cells.submit` — the architectural heart
// ─────────────────────────────────────────────────────────────────────

/// Parsed envelope held briefly during the submit pipeline.  All
/// string fields are slices into the dispatcher's per-call args_json
/// (or the parsed JSON arena), so the handler must finish persistence
/// before the call returns and the parent allocator clears.
const ParsedEnvelope = struct {
    cell_id: []const u8,
    opcode_bytes_b64: []const u8,
    hat_id: []const u8,
    cert_id: []const u8,
    correlation_id: []const u8,
    /// Verbatim phone-side `kernelResult` JSON object, for drift
    /// analysis storage.
    kernel_result_json: []const u8,
    intent_summary: []const u8,
    intent_action: []const u8,
    intent_taxonomy_json: []const u8,
    /// Wave 9 follow-up — optional producer-resolved entity + money
    /// refs (jobId / customerId / amount / currency). Empty string
    /// when the producer didn't supply `originalIntent.targetJson`.
    /// Stored as-is alongside the cell; the intent_action_router
    /// reads `jobId` from this when present to skip the
    /// `intent_summary` substring heuristic. Maximum encoded length
    /// `MAX_INTENT_TARGET_BYTES` (defined in intent_cells_store_fs).
    intent_target_json: []const u8,
};

const SubmitFailure = struct {
    error_kind: []const u8,
    hint: []const u8,
    /// Optional structured detail body (already-formatted JSON
    /// without surrounding braces — the writer wraps it).  Null =
    /// no detail.
    detail_json: ?[]const u8 = null,
};

fn handleSubmit(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    // Step 1: parse args { envelope_json: "<string>" }.
    const envelope_json = parseSubmitArgs(allocator, args_json) catch {
        return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "submit requires {\"envelope_json\":\"<envelope as JSON string>\"}",
        });
    };
    defer allocator.free(envelope_json);

    // Step 2: parse + validate envelope.
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        envelope_json,
        .{},
    ) catch {
        return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope is not valid JSON",
        });
    };
    defer parsed.deinit();

    var env = parseEnvelope(parsed.value) catch |err| switch (err) {
        error.envelope_not_object => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope must be a JSON object",
        }),
        error.bad_kind => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope.kind must equal \"" ++ ENVELOPE_KIND ++ "\"",
        }),
        error.bad_version => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope.version must equal 1",
        }),
        error.missing_or_invalid_cell_id => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope.cellId missing / wrong type / wrong length",
        }),
        error.missing_or_invalid_opcode_bytes => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope.opcodeBytes missing / wrong type / oversized",
        }),
        error.missing_or_invalid_hat_id => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope.hatId missing / wrong type",
        }),
        error.missing_or_invalid_cert_id => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope.certId missing / wrong type",
        }),
        error.missing_or_invalid_correlation_id => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope.correlationId missing / wrong type",
        }),
        error.missing_or_invalid_kernel_result => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope.kernelResult missing / not an object / phone reported ok=false",
        }),
        error.missing_or_invalid_original_intent => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope.originalIntent missing / shape wrong",
        }),
    };

    // Re-stringify the inner kernelResult object for storage (drift
    // analysis).  Always non-null after a successful parseEnvelope.
    const kernel_result_value = parsed.value.object.get("kernelResult").?;
    env.kernel_result_json = std.json.Stringify.valueAlloc(
        allocator,
        kernel_result_value,
        .{},
    ) catch return HandlerError.out_of_memory;
    defer allocator.free(env.kernel_result_json);

    // Step 3+4: resolve certId and verify hatId matches its chain
    // binding (root → own id; child → parent_cert_id).  Both checks
    // delegate to the brain primitive `identity_certs.CertStore.
    // verifyCertHatBinding` — one entry point so every cartridge that
    // carries cert+hat in its envelope (oddjobz today; tessera/jambox/
    // future) calls the same logic instead of re-implementing the
    // lookup + chain rule.  See UNIFICATION-ROADMAP §11.10 Gap A.
    if (self.cert_store) |cs| {
        cs.verifyCertHatBinding(env.cert_id, env.hat_id) catch |err| switch (err) {
            identity_certs.CertError.cert_not_found => return writeFailure(allocator, .{
                .error_kind = ERR_CERT_UNKNOWN,
                .hint = "certId not found in cert store",
            }),
            identity_certs.CertError.hat_binding_mismatch => return writeFailure(allocator, .{
                .error_kind = ERR_CERT_BINDING_MISMATCH,
                .hint = "hatId does not match chain binding for certId",
            }),
            else => return err,
        };
    }
    // When `cert_store` is null (test fixtures), skip cert validation
    // entirely.  Tests opt into cert-aware paths by passing a real
    // store via `initWithDeps`.

    // Step 5: decode opcodeBytes from base64.  Reject if invalid or
    // > MAX_OPCODE_BYTES (10 KiB).
    const decoded = decodeBase64(allocator, env.opcode_bytes_b64) catch {
        return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope.opcodeBytes is not valid base64",
        });
    };
    defer allocator.free(decoded);
    if (decoded.len > MAX_OPCODE_BYTES) {
        return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "decoded opcode stream exceeds 10 KiB",
        });
    }

    // Step 6: re-execute locally via the brain's PolicyRuntime seam.
    // Phase 1 lenient policy — require local result.ok == true; do NOT
    // enforce opcount/gas equality with the envelope.  Infrastructure
    // failures bubble up as PolicyRuntimeError → ERR_KERNEL_LOCAL_EXEC_FAILED.
    //
    // §11.10 order 2e PR-2b — backend is now the real cell-engine 2-PDA
    // executor (Todd-confirmed first consumer per design doc §6 #4).
    // .real_executor enforces deterministic predicate semantics: a
    // truthy top-of-stack at the end of the lock script = accept; any
    // ExecuteError variant = structured reject with @errorName as the
    // rejection_code token.
    //
    // Phase 1 limitations (see policy_runtime.zig evaluateReal doc-
    // comment + design doc §2 D3): tx_context = null, context.fields
    // ignored.  Today's intent_cell smoke fixtures don't invoke
    // OP_CHECKSIG or OP_READPAYLOAD, so no behavioural regression.
    // OP_CHECKCAPABILITY wiring lands with Phase 2 (task #16).
    //
    // Wire-compat: "invalid_pushdata" is the one token both backends
    // emit, so PR #641 cell_handler reject fixtures keep matching
    // through PR-2c's cell_handler flip.
    var rt = policy_runtime.PolicyRuntime.initWithMode(allocator, .real_executor);
    const policy_ctx = policy_runtime.PolicyContext{
        .actor = .{
            .cert_id = env.cert_id,
            // Oddjobz intent-cell envelopes don't carry capability ids
            // today (the cell-engine doesn't enforce OP_CHECKCAPABILITY
            // yet).  Empty slice is the spec-conformant value until the
            // envelope grows a capabilities field under order 2e.
            .capabilities = &[_]u32{},
        },
        // Single-authorizer; oddjobz has no dual-auth envelope today.
        .co_actor = null,
    };
    const policy_result = rt.evaluate(decoded, policy_ctx) catch {
        return writeFailure(allocator, .{
            .error_kind = ERR_KERNEL_LOCAL_EXEC_FAILED,
            .hint = "brain-side PolicyRuntime infrastructure error",
        });
    };
    if (!policy_result.ok) {
        // Surface both the phone's claim + the brain's local result.
        var detail: std.ArrayList(u8) = .{};
        defer detail.deinit(allocator);
        try detail.appendSlice(allocator, "\"phone_kernel_result\":");
        try detail.appendSlice(allocator, env.kernel_result_json);
        try detail.appendSlice(allocator, ",\"brain_local_result\":");
        try writePolicyResultJson(allocator, &detail, policy_result);
        return writeFailure(allocator, .{
            .error_kind = ERR_KERNEL_REJECTED_LOCALLY,
            .hint = "brain re-execution rejected the opcode stream",
            .detail_json = detail.items,
        });
    }

    // Step 7: build IntentCellRecord with brain's local kernel values
    // (per spec: brain stores its own values; phone's claim recorded
    // separately for drift analysis).
    const received_at = intent_cells_store_fs.renderIsoTimestamp(allocator, std.time.timestamp()) catch
        return HandlerError.out_of_memory;
    defer allocator.free(received_at);

    // W0.3: IntentCellRecord is re-exported from intent_cell_lmdb_store.
    //
    // §11.10 order 2c counter mapping: PolicyResult mirrors the TS shape
    // which surfaces only `gas` (opcodes consumed).  The IntentCellRecord
    // wire fields (opcount/stack_depth/gas_used) predate the seam; map as:
    //   opcount     = policy_result.gas (semantically opcount-equivalent)
    //   stack_depth = 0 — documented syntactic-shim-mode lossiness; the
    //                 shim's prior value was already "approximate" per
    //                 kernel_zig.zig:237-241 and not load-bearing.  When
    //                 order 2e wires the real executor, stack_depth (or a
    //                 successor field on PolicyResult) reappears.
    //   gas_used    = policy_result.gas (same source)
    // Phone-side stack_depth survives intact via env.kernel_result_json
    // for drift analysis; the brain just no longer publishes its own.
    const record = intent_cell_lmdb_store.IntentCellRecord{
        .cell_id = env.cell_id,
        .hat_id = env.hat_id,
        .cert_id = env.cert_id,
        .correlation_id = env.correlation_id,
        .opcount = @intCast(policy_result.gas),
        .stack_depth = 0,
        .gas_used = @intCast(policy_result.gas),
        .kernel_ok = policy_result.ok,
        .phone_kernel_result_json = env.kernel_result_json,
        .opcode_bytes_b64 = env.opcode_bytes_b64,
        .intent_summary = env.intent_summary,
        .intent_action = env.intent_action,
        .intent_taxonomy_json = env.intent_taxonomy_json,
        .received_at = received_at,
    };

    // Step 8: store.create with idempotency branching.
    const outcome = self.store.create(record) catch |err| switch (err) {
        intent_cell_lmdb_store.StoreError.cell_id_in_use_with_different_contents => return writeFailure(allocator, .{
            .error_kind = ERR_CELL_ID_IN_USE,
            .hint = "cellId already exists with different envelope contents",
        }),
        intent_cell_lmdb_store.StoreError.persistence_failed => return writeFailure(allocator, .{
            .error_kind = ERR_PERSISTENCE_FAILED,
            .hint = "failed to persist intent cell to LMDB",
        }),
        intent_cell_lmdb_store.StoreError.invalid_cell_id,
        => return writeFailure(allocator, .{
            .error_kind = ERR_ENVELOPE_INVALID,
            .hint = "envelope field exceeded length envelope or was empty",
        }),
        else => return HandlerError.store_error,
    };

    // Step 9: emit helm broker event (best-effort).
    if (outcome == .created) {
        emitIntentCellCreated(self, env) catch {};

        // §11.10 order 3a step 2 — anchor the newly persisted cell.
        // Compute the canonical 1024-byte cell bytes from the record
        // (encodeCell is pure; exposed for exactly this purpose) and
        // SHA-256 them to get the cell hash AnchorEmitter expects.
        // Skip on .already_exists — that cell was previously anchored
        // (or scheduled to be) on its first write; re-anchoring would
        // be a duplicate.  Anchor failures DO NOT fail submit.
        const cell_bytes = intent_cell_lmdb_store.encodeCell(record);
        var anchor_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&cell_bytes, &anchor_hash, .{});
        // §11.10 order 3a PR-3a-bridge-2b — broker-bearing flip.
        // When self.broker is wired (production via cli/serve.zig
        // initWithDeps), the emitter publishes "cell.created" on the
        // broker so the wallet-headers cartridge subscriber can
        // broadcast the BSV anchor tx.  Tests construct the Handler
        // without a broker and stay on .stub mode.
        var anchor_em = if (self.broker) |broker|
            anchor_emitter.AnchorEmitter.initWithBroker(allocator, .bsv, broker)
        else
            anchor_emitter.AnchorEmitter.init(allocator, .stub);
        _ = anchor_em.emit(.{
            .cell_hash = anchor_hash,
            // Stable type_hash for the oddjobz.intent_cell.v1 family.
            // See INTENT_CELL_TYPE_HASH at module scope for derivation.
            .type_hash = INTENT_CELL_TYPE_HASH,
            // Oddjobz intent cells don't carry an entity_tag at the
            // envelope layer; the persisted cell uses PHASE_ACTION
            // (0x06) in the commerce-phase header byte.  Surface here
            // for observability — anchor routing keys on type_hash.
            .entity_tag = intent_cell_lmdb_store.PHASE_ACTION,
            .cartridge_id = "oddjobz",
            .correlation_id = env.correlation_id,
        });
    }

    // Step 10: audit-log the accepted cell.
    if (self.audit) |a| {
        const detail = std.fmt.allocPrint(
            allocator,
            "intent_cells.submit cell_id={s} status={s}",
            .{ env.cell_id, switch (outcome) {
                .created => "accepted",
                .already_exists => "already_exists",
            } },
        ) catch "";
        defer if (detail.len > 0) allocator.free(detail);
        a.record(allocator, .{
            .module = "intent_cells",
            .op = "submit",
            .result = .ok,
            .detail = detail,
        }) catch {};
    }

    // Build the success response.
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"cellId\":");
    try writeJsonString(allocator, &buf, env.cell_id);
    try buf.appendSlice(allocator, ",\"status\":\"");
    try buf.appendSlice(allocator, switch (outcome) {
        .created => "accepted",
        .already_exists => "already_exists",
    });
    try buf.appendSlice(allocator, "\"}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn parseSubmitArgs(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const v = obj.get("envelope_json") orelse return error.invalid_args;
    if (v != .string) return error.invalid_args;
    return try allocator.dupe(u8, v.string);
}

const EnvelopeParseError = error{
    envelope_not_object,
    bad_kind,
    bad_version,
    missing_or_invalid_cell_id,
    missing_or_invalid_opcode_bytes,
    missing_or_invalid_hat_id,
    missing_or_invalid_cert_id,
    missing_or_invalid_correlation_id,
    missing_or_invalid_kernel_result,
    missing_or_invalid_original_intent,
};

fn parseEnvelope(value: std.json.Value) EnvelopeParseError!ParsedEnvelope {
    if (value != .object) return error.envelope_not_object;
    const obj = value.object;

    const kind_v = obj.get("kind") orelse return error.bad_kind;
    if (kind_v != .string) return error.bad_kind;
    if (!std.mem.eql(u8, kind_v.string, ENVELOPE_KIND)) return error.bad_kind;

    const version_v = obj.get("version") orelse return error.bad_version;
    if (version_v != .integer) return error.bad_version;
    if (version_v.integer != ENVELOPE_VERSION) return error.bad_version;

    const cell_id_v = obj.get("cellId") orelse return error.missing_or_invalid_cell_id;
    if (cell_id_v != .string) return error.missing_or_invalid_cell_id;
    if (cell_id_v.string.len == 0 or cell_id_v.string.len > intent_cells_store_fs.MAX_CELL_ID_BYTES) {
        return error.missing_or_invalid_cell_id;
    }

    const opcode_bytes_v = obj.get("opcodeBytes") orelse return error.missing_or_invalid_opcode_bytes;
    if (opcode_bytes_v != .string) return error.missing_or_invalid_opcode_bytes;
    if (opcode_bytes_v.string.len > intent_cells_store_fs.MAX_OPCODE_BYTES_B64) {
        return error.missing_or_invalid_opcode_bytes;
    }

    const hat_id_v = obj.get("hatId") orelse return error.missing_or_invalid_hat_id;
    if (hat_id_v != .string) return error.missing_or_invalid_hat_id;
    if (hat_id_v.string.len == 0 or hat_id_v.string.len > intent_cells_store_fs.MAX_HAT_ID_BYTES) {
        return error.missing_or_invalid_hat_id;
    }

    const cert_id_v = obj.get("certId") orelse return error.missing_or_invalid_cert_id;
    if (cert_id_v != .string) return error.missing_or_invalid_cert_id;
    if (cert_id_v.string.len == 0 or cert_id_v.string.len > intent_cells_store_fs.MAX_CERT_ID_BYTES) {
        return error.missing_or_invalid_cert_id;
    }

    const corr_v = obj.get("correlationId") orelse return error.missing_or_invalid_correlation_id;
    if (corr_v != .string) return error.missing_or_invalid_correlation_id;
    if (corr_v.string.len == 0 or corr_v.string.len > intent_cells_store_fs.MAX_CORRELATION_ID_BYTES) {
        return error.missing_or_invalid_correlation_id;
    }

    // kernelResult: object with required fields.  Phone MUST report
    // ok=true (refused-rejected cells never reach the outbox per spec).
    // Re-serialise for storage.
    const kernel_v = obj.get("kernelResult") orelse return error.missing_or_invalid_kernel_result;
    if (kernel_v != .object) return error.missing_or_invalid_kernel_result;
    const kobj = kernel_v.object;
    const kok_v = kobj.get("ok") orelse return error.missing_or_invalid_kernel_result;
    if (kok_v != .bool) return error.missing_or_invalid_kernel_result;
    if (!kok_v.bool) return error.missing_or_invalid_kernel_result;

    const oi_v = obj.get("originalIntent") orelse return error.missing_or_invalid_original_intent;
    if (oi_v != .object) return error.missing_or_invalid_original_intent;
    const oi_obj = oi_v.object;
    const summary_v = oi_obj.get("summary") orelse return error.missing_or_invalid_original_intent;
    if (summary_v != .string) return error.missing_or_invalid_original_intent;
    if (summary_v.string.len == 0 or summary_v.string.len > intent_cells_store_fs.MAX_INTENT_SUMMARY_BYTES) {
        return error.missing_or_invalid_original_intent;
    }
    const action_v = oi_obj.get("action") orelse return error.missing_or_invalid_original_intent;
    if (action_v != .string) return error.missing_or_invalid_original_intent;
    if (action_v.string.len == 0 or action_v.string.len > intent_cells_store_fs.MAX_INTENT_ACTION_BYTES) {
        return error.missing_or_invalid_original_intent;
    }
    const taxonomy_v = oi_obj.get("taxonomyJson") orelse return error.missing_or_invalid_original_intent;
    if (taxonomy_v != .string) return error.missing_or_invalid_original_intent;
    if (taxonomy_v.string.len > intent_cells_store_fs.MAX_INTENT_TAXONOMY_BYTES) {
        return error.missing_or_invalid_original_intent;
    }

    // Wave 9 follow-up — optional `originalIntent.targetJson`. Absent
    // is fine (legacy producers); when present, the value must be a
    // string within the size cap. We don't validate JSON shape here —
    // the router parses + falls back on parse failure.
    const target_str: []const u8 = blk: {
        const t_v = oi_obj.get("targetJson") orelse break :blk "";
        if (t_v != .string) return error.missing_or_invalid_original_intent;
        if (t_v.string.len > intent_cells_store_fs.MAX_INTENT_TARGET_BYTES) {
            return error.missing_or_invalid_original_intent;
        }
        break :blk t_v.string;
    };

    return .{
        .cell_id = cell_id_v.string,
        .opcode_bytes_b64 = opcode_bytes_v.string,
        .hat_id = hat_id_v.string,
        .cert_id = cert_id_v.string,
        .correlation_id = corr_v.string,
        .kernel_result_json = "", // Filled in below by the caller-helper.
        .intent_summary = summary_v.string,
        .intent_action = action_v.string,
        .intent_taxonomy_json = taxonomy_v.string,
        .intent_target_json = target_str,
    };
}

fn decodeBase64(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const max_len = decoder.calcSizeForSlice(input) catch return error.invalid_base64;
    const out = try allocator.alloc(u8, max_len);
    errdefer allocator.free(out);
    decoder.decode(out, input) catch return error.invalid_base64;
    return out;
}

// ─────────────────────────────────────────────────────────────────────
// `intent_cells.find` — { hat_id?, since?, limit? } → [...]
// ─────────────────────────────────────────────────────────────────────

const FindFilter = struct {
    hat_id: ?[]u8 = null,
    since: ?[]u8 = null,
    limit: ?usize = null,

    fn deinit(self: *FindFilter, allocator: std.mem.Allocator) void {
        if (self.hat_id) |s| allocator.free(s);
        if (self.since) |s| allocator.free(s);
    }
};

fn parseFindArgs(allocator: std.mem.Allocator, args_json: []const u8) !FindFilter {
    if (args_json.len == 0) return .{};
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch
        return .{};
    defer parsed.deinit();
    if (parsed.value != .object) return .{};
    const obj = parsed.value.object;

    var hat_owned: ?[]u8 = null;
    if (obj.get("hat_id")) |v| {
        if (v == .string and v.string.len > 0 and v.string.len <= intent_cells_store_fs.MAX_HAT_ID_BYTES) {
            hat_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (hat_owned) |s| allocator.free(s);

    var since_owned: ?[]u8 = null;
    if (obj.get("since")) |v| {
        if (v == .string and v.string.len > 0 and v.string.len <= 64) {
            since_owned = try allocator.dupe(u8, v.string);
        }
    }
    errdefer if (since_owned) |s| allocator.free(s);

    var limit: ?usize = null;
    if (obj.get("limit")) |v| {
        if (v == .integer and v.integer > 0) {
            limit = @intCast(v.integer);
        }
    }
    return .{ .hat_id = hat_owned, .since = since_owned, .limit = limit };
}

fn handleFind(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    var filter = parseFindArgs(allocator, args_json) catch return HandlerError.out_of_memory;
    defer filter.deinit(allocator);

    // W0.3: list() returns []OwnedRecord; each item must be deinit'd.
    const items = self.store.list(allocator, .{
        .hat_id = filter.hat_id,
        .since = filter.since,
        .limit = filter.limit,
    }) catch return HandlerError.store_error;
    defer {
        for (items) |*item| item.deinit(allocator);
        allocator.free(items);
    }

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.append(allocator, '[');
    for (items, 0..) |row, i| {
        if (i != 0) try buf.append(allocator, ',');
        try writeRecordJson(allocator, &buf, row.record);
    }
    try buf.append(allocator, ']');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// `intent_cells.find_by_id`
// ─────────────────────────────────────────────────────────────────────

fn parseFindByIdArgs(allocator: std.mem.Allocator, args_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;
    const v = obj.get("cell_id") orelse obj.get("cellId") orelse return error.invalid_args;
    if (v != .string) return error.invalid_args;
    if (v.string.len == 0 or v.string.len > intent_cells_store_fs.MAX_CELL_ID_BYTES) {
        return error.invalid_args;
    }
    return try allocator.dupe(u8, v.string);
}

fn handleFindById(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const id = parseFindByIdArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer allocator.free(id);

    // W0.3: findById now takes allocator and returns StoreError!?OwnedRecord.
    const maybe_owned = self.store.findById(allocator, id) catch return HandlerError.store_error;

    if (maybe_owned == null) {
        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);
        try buf.appendSlice(allocator, "{\"error\":\"not_found\",\"cell_id\":");
        try writeJsonString(allocator, &buf, id);
        try buf.append(allocator, '}');
        return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
    }

    const owned = maybe_owned.?;
    defer owned.deinit(allocator);

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try writeRecordJson(allocator, &buf, owned.record);
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// Broker emit
// ─────────────────────────────────────────────────────────────────────

fn emitIntentCellCreated(self: *Handler, env: ParsedEnvelope) !void {
    const broker = self.broker orelse return;
    const allocator = self.allocator;

    const ts_ms = std.time.milliTimestamp();

    var payload: std.ArrayList(u8) = .{};
    defer payload.deinit(allocator);
    try payload.appendSlice(allocator, "{\"cell_id\":");
    try writeJsonString(allocator, &payload, env.cell_id);
    try payload.appendSlice(allocator, ",\"hat_id\":");
    try writeJsonString(allocator, &payload, env.hat_id);
    try payload.appendSlice(allocator, ",\"intent_summary\":");
    try writeJsonString(allocator, &payload, env.intent_summary);
    try payload.appendSlice(allocator, ",\"intent_action\":");
    try writeJsonString(allocator, &payload, env.intent_action);
    // ODDJOBZ-ESTIMATE-ROM-INGRESS Slice 3 — surface the
    // already-captured originalIntent.targetJson (jobId/amount/
    // costMin/costMax/currency) on the broker event so the
    // intent_action_router can mint an accepted Estimate from a ROM
    // accept. Empty string when the producer supplied none — the
    // router treats that as "no figure, transition only" (the
    // existing figure-less behaviour, unchanged).
    try payload.appendSlice(allocator, ",\"intent_target_json\":");
    try writeJsonString(allocator, &payload, env.intent_target_json);
    try payload.appendSlice(allocator, ",\"requires_operator_attention\":true");
    try payload.print(allocator, ",\"ts\":{d}", .{ts_ms});
    try payload.append(allocator, '}');

    broker.publish(.{
        .type = "intent_cell.created",
        .payload_json = payload.items,
        .requires_operator_attention = true,
    });

    if (self.audit) |a| {
        a.record(allocator, .{
            .module = "helm.broker",
            .op = "publish",
            .result = .ok,
            .detail = "intent_cell.created",
        }) catch {};
    }
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

fn writeFailure(allocator: std.mem.Allocator, f: SubmitFailure) !dispatcher.Result {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"error\":");
    try writeJsonString(allocator, &buf, f.error_kind);
    try buf.appendSlice(allocator, ",\"hint\":");
    try writeJsonString(allocator, &buf, f.hint);
    if (f.detail_json) |d| {
        try buf.appendSlice(allocator, ",\"detail\":{");
        try buf.appendSlice(allocator, d);
        try buf.append(allocator, '}');
    }
    try buf.append(allocator, '}');
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn writePolicyResultJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    r: policy_runtime.PolicyResult,
) !void {
    // Emits the historic `brain_local_result` wire JSON shape (ok /
    // opcount / stackDepth / gasUsed / errorKind) regardless of which
    // PolicyRuntime backend produced `r`.  See §11.10 order 2c counter
    // mapping above for the synthesis rules (stack_depth is fixed at 0
    // under the syntactic-shim backend; restored when order 2e lands).
    try out.append(allocator, '{');
    try out.appendSlice(allocator, "\"ok\":");
    try out.appendSlice(allocator, if (r.ok) "true" else "false");
    try out.print(allocator, ",\"opcount\":{d}", .{r.gas});
    try out.appendSlice(allocator, ",\"stackDepth\":0");
    try out.print(allocator, ",\"gasUsed\":{d}", .{r.gas});
    try out.appendSlice(allocator, ",\"errorKind\":");
    if (r.rejection_code) |k| {
        try writeJsonString(allocator, out, k);
    } else {
        try out.appendSlice(allocator, "null");
    }
    try out.append(allocator, '}');
}

fn writeRecordJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    r: intent_cell_lmdb_store.IntentCellRecord,
) !void {
    try out.appendSlice(allocator, "{\"cell_id\":");
    try writeJsonString(allocator, out, r.cell_id);
    try out.appendSlice(allocator, ",\"hat_id\":");
    try writeJsonString(allocator, out, r.hat_id);
    try out.appendSlice(allocator, ",\"cert_id\":");
    try writeJsonString(allocator, out, r.cert_id);
    try out.appendSlice(allocator, ",\"correlation_id\":");
    try writeJsonString(allocator, out, r.correlation_id);
    try out.print(allocator, ",\"opcount\":{d}", .{r.opcount});
    try out.print(allocator, ",\"stack_depth\":{d}", .{r.stack_depth});
    try out.print(allocator, ",\"gas_used\":{d}", .{r.gas_used});
    try out.appendSlice(allocator, ",\"kernel_ok\":");
    try out.appendSlice(allocator, if (r.kernel_ok) "true" else "false");
    try out.appendSlice(allocator, ",\"phone_kernel_result_json\":");
    try writeJsonString(allocator, out, r.phone_kernel_result_json);
    try out.appendSlice(allocator, ",\"opcode_bytes_b64\":");
    try writeJsonString(allocator, out, r.opcode_bytes_b64);
    try out.appendSlice(allocator, ",\"intent_summary\":");
    try writeJsonString(allocator, out, r.intent_summary);
    try out.appendSlice(allocator, ",\"intent_action\":");
    try writeJsonString(allocator, out, r.intent_action);
    try out.appendSlice(allocator, ",\"intent_taxonomy_json\":");
    try writeJsonString(allocator, out, r.intent_taxonomy_json);
    try out.appendSlice(allocator, ",\"received_at\":");
    try writeJsonString(allocator, out, r.received_at);
    try out.append(allocator, '}');
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure validator logic.  Full handler conformance lives
// in tests/intent_cells_handler_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

fn parseValueForTest(allocator: std.mem.Allocator, json_text: []const u8) !std.json.Parsed(std.json.Value) {
    return try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
}

test "parseEnvelope: rejects wrong kind" {
    const allocator = std.testing.allocator;
    var p = try parseValueForTest(allocator,
        \\{"kind":"oddjobz.something_else.v1","version":1,"cellId":"c1",
        \\ "opcodeBytes":"AA==","hatId":"h","certId":"c","correlationId":"x",
        \\ "kernelResult":{"ok":true,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":null},
        \\ "originalIntent":{"summary":"s","action":"a","taxonomyJson":"{}"}}
    );
    defer p.deinit();
    try std.testing.expectError(error.bad_kind, parseEnvelope(p.value));
}

test "parseEnvelope: rejects wrong version" {
    const allocator = std.testing.allocator;
    var p = try parseValueForTest(allocator,
        \\{"kind":"oddjobz.intent_cell.v1","version":2,"cellId":"c1",
        \\ "opcodeBytes":"AA==","hatId":"h","certId":"c","correlationId":"x",
        \\ "kernelResult":{"ok":true,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":null},
        \\ "originalIntent":{"summary":"s","action":"a","taxonomyJson":"{}"}}
    );
    defer p.deinit();
    try std.testing.expectError(error.bad_version, parseEnvelope(p.value));
}

test "parseEnvelope: rejects ok=false in kernelResult" {
    const allocator = std.testing.allocator;
    var p = try parseValueForTest(allocator,
        \\{"kind":"oddjobz.intent_cell.v1","version":1,"cellId":"c1",
        \\ "opcodeBytes":"AA==","hatId":"h","certId":"c","correlationId":"x",
        \\ "kernelResult":{"ok":false,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":"x"},
        \\ "originalIntent":{"summary":"s","action":"a","taxonomyJson":"{}"}}
    );
    defer p.deinit();
    try std.testing.expectError(error.missing_or_invalid_kernel_result, parseEnvelope(p.value));
}

test "parseEnvelope: accepts well-formed envelope" {
    const allocator = std.testing.allocator;
    var p = try parseValueForTest(allocator,
        \\{"kind":"oddjobz.intent_cell.v1","version":1,
        \\ "cellId":"cell-000010-deadbeef-12345678",
        \\ "opcodeBytes":"AA==","hatId":"hat-001",
        \\ "certId":"cert-001","correlationId":"00000000-0000-4000-8000-000000000001",
        \\ "kernelResult":{"ok":true,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":null},
        \\ "originalIntent":{"summary":"Find wattle","action":"find","taxonomyJson":"{\"what\":\"jobs\"}"}}
    );
    defer p.deinit();
    const env = try parseEnvelope(p.value);
    try std.testing.expectEqualStrings("cell-000010-deadbeef-12345678", env.cell_id);
    try std.testing.expectEqualStrings("find", env.intent_action);
    try std.testing.expectEqualStrings("Find wattle", env.intent_summary);
}

test "parseEnvelope: rejects missing fields" {
    const allocator = std.testing.allocator;
    var p = try parseValueForTest(allocator,
        \\{"kind":"oddjobz.intent_cell.v1","version":1}
    );
    defer p.deinit();
    try std.testing.expectError(error.missing_or_invalid_cell_id, parseEnvelope(p.value));
}

test "decodeBase64: round-trip" {
    const allocator = std.testing.allocator;
    const decoded = try decodeBase64(allocator, "aGVsbG8=");
    defer allocator.free(decoded);
    try std.testing.expectEqualStrings("hello", decoded);
}

test "decodeBase64: rejects invalid input" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.invalid_base64, decodeBase64(allocator, "!!!"));
}

```
