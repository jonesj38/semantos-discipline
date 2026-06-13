---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cells_mint_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.256795+00:00
---

# runtime/semantos-brain/src/cells_mint_handler.zig

```zig
// BRAIN-GENERIC-MINT-VERB M3 — REPL `cells mint` dispatcher resource.
//
// Per the design doc (docs/design/BRAIN-GENERIC-MINT-VERB.md) Q-mint-1
// = C, the REPL surface is a thin wrapper over the same pipeline the
// HTTP handler runs.  Both paths share:
//   - cells_mint_http.parseRequestBody   → body shape validation
//   - cells_mint_http.resolveCellType    → registry lookup
//   - substrate_entity.encodeFromTypeHash → canonical 256-byte header
//   - cell_store.put                      → LMDB persistence
//   - helm_broker.publish                 → `cells.<cartridge-id>.minted`
//
// The HTTP handler in site_server/reactor.zig handles HTTP-shaped
// concerns (bearer headers, status codes, CORS); this resource handles
// dispatcher-shaped concerns (CapDecl, DispatchContext, Result).  The
// substrate logic is identical — no duplication.
//
// REPL wire:
//   cells mint '{"typeHashHex":"<64hex>","payload":{...}}'
//   →  {"ok":true,"cellId":"<64hex>","cartridgeId":"...","cellType":"...","persistedAt":<unix-ms>}
//   →  {"ok":false,"error":"...","hint":"..."}  (on failure)

const std = @import("std");
const dispatcher = @import("dispatcher");
const cell_store_mod = @import("cell_store");
const substrate_entity = @import("substrate_entity");
const cells_mint_http = @import("cells_mint_http");
const cells_mint_validator = @import("cells_mint_validator");
const cartridge_cell_registry = @import("cartridge_cell_registry");
const helm_event_broker = @import("helm_event_broker");
// C10 PR-2d (2026-05-28) — wire mint path through the brain's PolicyRuntime
// so the canonical PWA mint endpoint (POST /api/v1/cells) is gated by the
// cell-engine 2-PDA when callers supply opcode_bytes_b64.  Default-permit
// when absent — non-breaking for existing PWA clients.  See
// docs/design/REAL-EXECUTOR-WIRE.md §2 PR-2d + matrix C10-B.
const policy_runtime = @import("policy_runtime");
// C11 PR4a/4b — cell-script handler dispatcher.
//
// PR4a: load-side. Manifest handler entries are parsed at cartridge
// boot, sha256-verified against scriptHash, and registered in
// `cell_script_handler_registry` (typeHash → HandlerEntry).
//
// PR4b: execution-side (this file). When the mint pipeline sees a
// typeHash with a registered handler, it dispatches the cell-engine
// bytecode via direct `executor.execute()` invocation (chosen over
// extending PolicyRuntime.evaluate so PolicyRuntime stays scoped to
// opcode-precondition evaluation and cell-handler dispatch doesn't
// grow its API). The dispatcher:
//   1. Allocates a fresh PDA + ScriptArena (mirrors PolicyRuntime's
//      per-call lifecycle).
//   2. Pushes the encoded input cell onto the PDA main stack.
//   3. Loads the handler's bytecode and runs `executor.execute()`.
//   4. On truthy result, walks the main stack for any 1024-byte cells
//      that aren't byte-equal to the input cell — those are emitted
//      cells. Each one's typeHash (header bytes 30..62) is checked
//      against the handler's declared `emits[]` allowlist via
//      `cartridge_cell_registry.lookupByName`, then persisted via the
//      cell_store.
//   5. On falsy result or any ExecuteError, the entire mint is
//      rejected — no input cell persisted, no emitted cells persisted.
//
// Capability gating: v1 enforces opcount budget + script-size cap +
// emits allowlist. Per-hostcall capability gating (preventing a
// handler from calling a hostcall not declared in `capabilities[]`)
// is deferred — it requires threading the current handler's capability
// list through host_call_by_name, which is a larger change.
const cell_script_handler_registry = @import("cell_script_handler_registry");
const executor = @import("executor");
const pda_mod = @import("pda");
const allocator_mod = @import("allocator");
const cell_engine_constants = @import("constants");
// PR-3c — boot-register the cell-engine hostcall handlers. These
// modules expose a `register()` function that adds the named
// hostcall to the cell-engine's native dispatch registry; once
// registered, OP_CALLHOST from a handler script can reach them via
// PolicyRuntime's executor.execute path.
//
// PR-3d — per-script execution context construction. The dispatcher
// now calls an optional `ScriptContextBuilder` BEFORE script execution
// (populating an opaque Context struct from intent payload + brain
// state) + `host.setExecutionContext` so OP_CALLHOST handlers see the
// right inputs. After execution the dispatcher tears down the Context.
// See the `ScriptContextBuilder` doc + `cells_mint_spv_context.zig`
// for the bsv-spv-verify-specific implementation.
const host = @import("host");
const host_compute_sighash = @import("host_compute_sighash");
const host_resolve_script_template = @import("host_resolve_script_template");
const host_verify_partial_sig = @import("host_verify_partial_sig");
const host_compute_preimage_hashes = @import("host_compute_preimage_hashes");
const host_assemble_tx = @import("host_assemble_tx");
const host_verify_beef_spv = @import("host_verify_beef_spv");
const host_mnca_verify_transition = @import("host_mnca_verify_transition");

/// Cell size — must match `core/cell-engine/src/constants.zig::CELL_SIZE`.
const CELL_SIZE: u32 = cell_engine_constants.CELL_SIZE;

/// Arena size for script execution. Mirrors PolicyRuntime.ARENA_SIZE.
const HANDLER_ARENA_SIZE: usize = 64 * 1024;

/// Outcome of one cell-script-handler dispatch.
pub const DispatchOutcome = union(enum) {
    /// Script ran to completion with truthy result; any emitted cells
    /// have been persisted (count reported for audit logs).
    success: struct { emitted_count: u32 },
    /// Script ran but returned falsy, or trapped, or tried to emit a
    /// cell outside its declared `emits[]` allowlist. Mint rejected;
    /// no cells persisted. Caller surfaces `reason` to the operator.
    rejection: []const u8,
    /// Infrastructure failure (allocation, cell-store write, etc.).
    /// Distinct from rejection because this is "brain broken,"
    /// not "script said no."
    internal_error: []const u8,
};

/// Dispatch a registered cell-script handler against `input_cell`.
///
/// PR4b execution-side per `docs/design/LINEAR-CELL-SPV-STATE.md` §3.
/// Implementation choice: direct `executor.execute()` invocation
/// (PolicyRuntime stays opcode-precondition-only; cell-handler
/// dispatch has its own per-call PDA/arena lifecycle).
fn dispatchCellScriptHandler(
    self: *Handler,
    allocator: std.mem.Allocator,
    hentry: cell_script_handler_registry.HandlerEntry,
    cartridge_id: []const u8,
    input_cell: *const [CELL_SIZE]u8,
) DispatchOutcome {
    // 1. Set up PDA + arena. Mirrors PolicyRuntime.evaluateReal — heap-
    //    allocated PDA + initInPlace to avoid the ~1.5 MB stack hit;
    //    arena lives long enough to outlast executor.execute().
    const pda = allocator.create(pda_mod.PDA) catch
        return .{ .internal_error = "pda_alloc_failed" };
    defer allocator.destroy(pda);
    pda.initInPlace(hentry.opcount_budget);

    const arena_buf = allocator.alloc(u8, HANDLER_ARENA_SIZE) catch
        return .{ .internal_error = "arena_alloc_failed" };
    defer allocator.free(arena_buf);
    var arena = allocator_mod.ScriptArena.init(arena_buf);

    var ctx = executor.ExecutionContext.init(pda, &arena);

    // 2. Push input cell onto the PDA main stack at slot 0. The script
    //    sees it as the bottom-of-stack item via OP_PICK / OP_OVER etc.
    pda.spushCell(input_cell, CELL_SIZE) catch
        return .{ .internal_error = "input_push_failed" };

    // 2b (PR-3d). Build per-script execution Context if a builder is
    // wired. The Context is opaque from the dispatcher's perspective —
    // its shape is whatever the builder's hostcall-specific module
    // expects (e.g. host_verify_beef_spv.Context for SPV intents).
    // The Context lifetime spans script execution + the stack walk;
    // teardown happens unconditionally via the defer block.
    const exec_ctx_ptr: ?*anyopaque = if (self.context_builder) |builder|
        builder.build_fn(builder.state, input_cell, allocator)
    else
        null;
    defer if (exec_ctx_ptr) |p| {
        if (self.context_builder) |b| b.destroy_fn(b.state, p, allocator);
    };

    if (exec_ctx_ptr) |p| host.setExecutionContext(p);
    // Clear the execution context unconditionally — even when build
    // returned null we want a clean slate so subsequent dispatches
    // start without stale Context leakage. host.setExecutionContext
    // is documented as a single-slot file-scope pointer; clearing in
    // the defer guards against builder-state leaks across requests.
    defer host.setExecutionContext(null);

    // 2c (PR-8b-v). Push brain-built extra cells at PDA slots 1, 2, ...
    // The builder's extra_cells_fn populates them (e.g. the MNCA
    // builder pushes the successor anchor on Valid verdict). The
    // dispatcher's existing emit walker (step 4 below) picks them up
    // alongside any script-emitted cells, gated by hentry.emits[].
    //
    // Lifetime: the slice is borrowed; extra_cells_destroy_fn fires
    // on the defer path to free it.
    const extra_cells_opt: ?[]const [CELL_SIZE]u8 = blk: {
        if (exec_ctx_ptr) |p| if (self.context_builder) |b| if (b.extra_cells_fn) |ecf|
            break :blk ecf(b.state, p, allocator);
        break :blk null;
    };
    defer if (extra_cells_opt) |xs| {
        if (self.context_builder) |b| if (b.extra_cells_destroy_fn) |edf|
            edf(b.state, xs, allocator);
    };
    if (extra_cells_opt) |xs| {
        for (xs) |*cell| {
            pda.spushCell(cell, CELL_SIZE) catch
                return .{ .internal_error = "extra_cell_push_failed" };
        }
    }

    // 3. Load + execute the handler bytecode. loadScript caps at
    //    executor.MAX_SCRIPT_SIZE (10_000 bytes); ExecuteError covers
    //    every trap path (opcount exhaustion, stack over/underflow,
    //    verify, invalid opcode, plexus errors, etc.).
    ctx.loadScript(hentry.script_bytes) catch
        return .{ .rejection = "script_too_large" };

    const truthy = executor.execute(&ctx) catch |err| {
        const code = switch (err) {
            error.execution_limit => "opcount_exhausted",
            error.stack_overflow => "stack_overflow",
            error.stack_underflow => "stack_underflow",
            error.verify_failed => "verify_failed",
            error.invalid_opcode => "invalid_opcode",
            error.disabled_opcode => "disabled_opcode",
            error.invalid_pushdata => "invalid_pushdata",
            error.invalid_script => "invalid_script",
            error.script_too_large => "script_too_large",
            error.nesting_depth_exceeded => "nesting_depth_exceeded",
            error.no_tx_context => "no_tx_context",
            error.not_implemented => "not_implemented",
            else => "script_trap",
        };
        return .{ .rejection = code };
    };

    if (!truthy) return .{ .rejection = "script_returned_falsy" };

    // 4. Walk the main stack for emitted cells. Any 1024-byte slot
    //    that isn't byte-equal to the input cell is treated as an
    //    OP_CELLCREATE emission. Each one's typeHash (header bytes
    //    30..62) must match an entry in `hentry.emits[]` (resolved
    //    through cartridge_cell_registry.lookupByName) — that's the
    //    emits-allowlist gate per LINEAR-CELL-SPV-STATE.md §7.
    var emitted_count: u32 = 0;
    var slot: u32 = 0;
    while (slot < pda.main_sp) : (slot += 1) {
        const slot_len = pda.main_lengths[slot];
        if (slot_len != CELL_SIZE) continue; // not a full cell

        // Skip the input cell if the script left it on the stack.
        if (std.mem.eql(u8, &pda.main_stack[slot], input_cell)) continue;

        // Extract typeHash from header offset 30..62.
        const cell_th: *const [32]u8 = pda.main_stack[slot][30..62];

        // Check emits allowlist. PR-8b-ix — fall through to a global
        // name lookup so handlers can declare cross-cartridge emits in
        // their manifest (e.g. MNCA's transition-intent handler emits
        // `bsv.tx.sign.request`, which lives in bsv-anchor-bundle).
        // The LOCKSCRIPT-CLEAVAGE.md design treats substrate cell
        // types as universally addressable by canonical name; without
        // the fallback, cross-cartridge emits hit this gate even when
        // the manifest declares them correctly.
        var allowed = false;
        for (hentry.emits) |emit_name| {
            const emit_entry = cartridge_cell_registry.lookupByName(cartridge_id, emit_name) orelse
                cartridge_cell_registry.lookupByNameAnyCartridge(emit_name);
            if (emit_entry) |e| {
                if (std.mem.eql(u8, &e.type_hash, cell_th)) {
                    allowed = true;
                    break;
                }
            }
        }
        if (!allowed) return .{ .rejection = "emit_outside_allowlist" };

        // Persist the emitted cell.
        _ = self.cell_store.put(&pda.main_stack[slot]) catch
            return .{ .internal_error = "emit_store_failed" };
        emitted_count += 1;
    }

    return .{ .success = .{ .emitted_count = emitted_count } };
}

/// PR-8b-ix — thunk for `cells_mint_http.Acceptor.dispatch_input_cell_fn`.
///
/// Casts the opaque `ctx` pointer back to `*Handler` and runs the same
/// step 4.5 pipeline `handleMint` uses (registry lookup +
/// `dispatchCellScriptHandler`). The reactor in `site_server/reactor.zig`
/// invokes this between `substrate_entity.encodeFromTypeHash` and
/// `cell_store.put`, so the HTTP `POST /api/v1/cells` path runs the
/// composite ScriptContextBuilder + handler script + extra-cells push +
/// stack walker + emits-allowlist gate exactly the way the REPL
/// `cells mint` path does. `serve.zig` wires this by setting:
///
///     cells_mint_acceptor.dispatch_input_cell_fn = dispatchInputCellThunk;
///     cells_mint_acceptor.dispatch_ctx           = &cells_mint_handler_serve;
///
/// after the composite builder is attached via `setContextBuilder`.
///
/// Returns `.skipped` when no handler is registered for the typeHash —
/// the reactor treats that as "persist the input cell as a plain
/// substrate cell" (preserves pre-PR-8b-ix behaviour for typeHashes
/// with no handler block declared).
pub fn dispatchInputCellThunk(
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    type_hash: *const [32]u8,
    cartridge_id: []const u8,
    input_cell: *const [CELL_SIZE]u8,
) cells_mint_http.DispatchOutcomeOpaque {
    const self: *Handler = @ptrCast(@alignCast(ctx));
    self.mu.lock();
    defer self.mu.unlock();
    const hentry = cell_script_handler_registry.lookup(type_hash) orelse
        return .skipped;
    const outcome = dispatchCellScriptHandler(self, allocator, hentry, cartridge_id, input_cell);
    return switch (outcome) {
        .success => |s| .{ .success = .{ .emitted_count = s.emitted_count } },
        .rejection => |r| .{ .rejection = r },
        .internal_error => |m| .{ .internal_error = m },
    };
}

pub const RESOURCE_NAME = "cells";

pub const HandlerError = error{
    invalid_args,
    payload_too_large,
    unknown_type_hash,
    store_error,
    out_of_memory,
};

// C4 brain-carve PR-E2 — the mint-context-builder machinery moved to the
// light leaf module `mint_context.zig` so cartridge_seam can reference
// MintContextRegistry without importing this ~1500-LOC handler (substrate
// one-way dep gate, #847). Re-exported here as aliases so existing
// references — this file's `context_builder` field + setContextBuilder,
// cells_mint_{mnca,spv}_context, and serve.zig — keep resolving unchanged.
const mint_context = @import("mint_context");
pub const ScriptContextBuilder = mint_context.ScriptContextBuilder;
pub const CompositeContextBuilder = mint_context.CompositeContextBuilder;
pub const MintContextRegistry = mint_context.MintContextRegistry;
pub const MAX_MINT_CONTEXT_BUILDERS = mint_context.MAX_MINT_CONTEXT_BUILDERS;

pub const Handler = struct {
    allocator: std.mem.Allocator,
    cell_store: *const cell_store_mod.CellStore,
    broker: *helm_event_broker.Broker,
    /// PR-3d — optional per-script execution context builder. Null
    /// preserves the pre-PR-3d behavior (no setExecutionContext call,
    /// Context-style hostcalls return their no-context sentinel).
    /// Wired post-init via `setContextBuilder`.
    context_builder: ?ScriptContextBuilder,
    mu: std.Thread.Mutex,

    pub fn init(
        allocator: std.mem.Allocator,
        cell_store: *const cell_store_mod.CellStore,
        broker: *helm_event_broker.Broker,
    ) Handler {
        // PR-3c — register the cell-engine hostcall handlers exactly
        // once per process. The registry is file-scope in the cell-
        // engine `host` module so subsequent inits hit
        // `duplicate_registration` — treated as success since the
        // entry is already there.
        bootRegisterHostCalls() catch |err| {
            std.log.warn("cells_mint: host call registration failed: {s}", .{@errorName(err)});
        };

        return .{
            .allocator = allocator,
            .cell_store = cell_store,
            .broker = broker,
            .context_builder = null,
            .mu = .{},
        };
    }

    /// PR-3d — wire (or unwire) the per-script Context builder. Called
    /// after `init` by the brain's boot path once it has the resources
    /// the builder needs (HeaderStore for SPV, etc.). Pass null to
    /// disable Context construction.
    pub fn setContextBuilder(self: *Handler, builder: ?ScriptContextBuilder) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.context_builder = builder;
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

/// Register every cell-engine hostcall handler the mint pipeline
/// supports. Called from `Handler.init`; idempotent — duplicate
/// registrations are tolerated so multiple Handler instances within
/// a process (tests, dev servers) don't fight over the global
/// registry.
///
/// Companion to the cell-engine-side declarations in
/// `core/cell-engine/src/host_compute_sighash.zig` and the future
/// follow-on hostcall modules (template resolvers, partial-sig
/// verifier, tx assembler) per LOCKSCRIPT-CLEAVAGE.md §8.2.
fn bootRegisterHostCalls() !void {
    host_compute_sighash.register() catch |err| switch (err) {
        error.duplicate_registration => {}, // already registered — OK
        else => return err,
    };
    host_resolve_script_template.register() catch |err| switch (err) {
        error.duplicate_registration => {}, // already registered — OK
        else => return err,
    };
    host_verify_partial_sig.register() catch |err| switch (err) {
        error.duplicate_registration => {}, // already registered — OK
        else => return err,
    };
    host_compute_preimage_hashes.register() catch |err| switch (err) {
        error.duplicate_registration => {}, // already registered — OK
        else => return err,
    };
    host_assemble_tx.register() catch |err| switch (err) {
        error.duplicate_registration => {}, // already registered — OK
        else => return err,
    };
    host_verify_beef_spv.register() catch |err| switch (err) {
        error.duplicate_registration => {}, // already registered — OK
        else => return err,
    };
    host_mnca_verify_transition.register() catch |err| switch (err) {
        error.duplicate_registration => {}, // already registered — OK
        else => return err,
    };
}

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    // Q-mint-3 = B (per-cartridge capability) is enforced at registry
    // lookup time by the HTTP path (when bearer+cert capability surface
    // lands).  The REPL path is operator-local; `cap.brain.admin` is the
    // existing wall for every admin REPL verb and is the right gate here.
    if (std.mem.eql(u8, cmd, "mint")) return .{ .require = "cap.brain.admin" };
    return error.unknown_command;
}

pub fn isRead(cmd: []const u8) bool {
    _ = cmd;
    return false; // mint is always a write
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

    if (std.mem.eql(u8, cmd, "mint")) return handleMint(self, allocator, args_json);
    return error.unknown_command;
}

fn handleMint(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    // Step 1 — parse body via the shared parser. The same routine the
    // HTTP handler uses, so REPL + HTTP accept byte-identical envelopes.
    var req = cells_mint_http.parseRequestBody(allocator, args_json) catch |err| switch (err) {
        cells_mint_http.Error.payload_too_large => return writeRejection(
            allocator,
            "payload_too_large",
            "body exceeds 64 KiB cap",
        ),
        cells_mint_http.Error.out_of_memory => return HandlerError.out_of_memory,
        else => return writeRejection(
            allocator,
            "invalid_args",
            "body must be {typeHashHex,payload}",
        ),
    };
    defer cells_mint_http.deinitRequest(allocator, &req);

    // Step 2 — registry lookup.
    const entry = cells_mint_http.resolveCellType(&req.type_hash) catch {
        return writeRejection(
            allocator,
            "unknown_type_hash",
            "no cellType registered for this typeHash; check cartridge.json cellTypes[]",
        );
    };

    // Step 2b — M2 structural payload validation (when schema declared).
    if (entry.payload_schema_raw) |schema_raw| {
        var validate_arena = std.heap.ArenaAllocator.init(allocator);
        defer validate_arena.deinit();
        var failure: ?cells_mint_validator.ValidationFailure = null;
        cells_mint_validator.validate(
            validate_arena.allocator(),
            schema_raw,
            req.payload_json,
            &failure,
        ) catch |err| switch (err) {
            cells_mint_validator.ValidationError.missing_required_field => {
                const f = failure orelse cells_mint_validator.ValidationFailure{
                    .field_name = "?",
                    .expected_type = "any",
                };
                const hint = std.fmt.allocPrint(
                    allocator,
                    "field {s} required (expected type {s})",
                    .{ f.field_name, f.expected_type },
                ) catch return HandlerError.out_of_memory;
                defer allocator.free(hint);
                return writeRejection(allocator, "missing_required_field", hint);
            },
            cells_mint_validator.ValidationError.wrong_field_type => {
                const f = failure orelse cells_mint_validator.ValidationFailure{
                    .field_name = "?",
                    .expected_type = "?",
                };
                const hint = std.fmt.allocPrint(
                    allocator,
                    "field {s} must be {s}",
                    .{ f.field_name, f.expected_type },
                ) catch return HandlerError.out_of_memory;
                defer allocator.free(hint);
                return writeRejection(allocator, "wrong_field_type", hint);
            },
            else => return writeRejection(
                allocator,
                "schema_validation_failed",
                "internal schema or payload parse failure",
            ),
        };
    }

    // Step 2c — C10 PR-2d kernel-precondition gate.  When the inbound
    // body carried `opcode_bytes_b64`, evaluate it through PolicyRuntime
    // in `.real_executor` mode (cell-engine 2-PDA).  Reject on !ok.
    // Default-permit when absent so existing PWA callers (the V1 slice
    // mint path) keep working unchanged.  Cartridges that want
    // precondition enforcement supply opcode bytes via the mint
    // envelope; future cartridge-loader work will populate them
    // automatically from per-verb manifest entries.
    if (req.opcode_bytes_b64) |b64| {
        const decoded = decodeBase64(allocator, b64) catch
            return writeRejection(
                allocator,
                "invalid_args",
                "opcode_bytes_b64 must be valid base64",
            );
        defer allocator.free(decoded);

        var rt = policy_runtime.PolicyRuntime.initWithMode(allocator, .real_executor);
        const policy_ctx = policy_runtime.PolicyContext{
            // Phase 1: cert/cap binding lands when bearer→cert wiring
            // (T7 from V1 reactor work) reaches this seam.  Empty-cert
            // ctx threads through unchanged so payload-aware opcodes
            // (OP_READPAYLOAD etc.) become enforceable when Phase 2
            // of evaluateReal lands without rewriting this call site.
            .actor = .{ .cert_id = "", .capabilities = &[_]u32{} },
            .co_actor = null,
        };
        const policy_result = rt.evaluate(decoded, policy_ctx) catch
            return writeRejectionWithCode(
                allocator,
                "kernel_local_exec_failed",
                "brain-side PolicyRuntime infrastructure error",
                null,
            );
        if (!policy_result.ok) {
            return writeRejectionWithCode(
                allocator,
                "kernel_rejected_locally",
                "PolicyRuntime rejected the opcode precondition stream",
                policy_result.rejection_code,
            );
        }
    }

    // Step 2d — C11 PR4b: cell-script handler dispatch is deferred to
    // Step 4.5 (after the input cell is encoded). The lookup happens
    // there so the dispatcher can push the encoded 1024-byte cell
    // onto the PDA main stack.

    // Step 3 — map registry Linearity → substrate_entity.LinearityClass.
    //  PERSISTENT → relevant: closest semantic in the legacy kernel
    //  (multi-read, never consumed). When the kernel gains PERSISTENT
    //  this collapses to 1:1.
    //  PR-C11-7e-2f — EPHEMERAL maps to .relevant too. The intent +
    //  result cell pairs (e.g. bsv.spv.verify.intent / .result) are
    //  by definition transient; the substrate currently persists them
    //  identically to PERSISTENT, with true ephemeral storage
    //  semantics (auto-prune after caller reads) deferred to a
    //  follow-up. See cartridge_cell_registry.zig Linearity docs.
    const linearity_class: substrate_entity.LinearityClass = switch (entry.linearity) {
        .LINEAR => .linear,
        .AFFINE => .affine,
        .RELEVANT, .PERSISTENT, .EPHEMERAL => .relevant,
        .DEBUG => .debug,
    };

    // Step 4 — encode the cell. CC-1: owner_id@62 is derived from the caller's
    // signer cert-id (first 16 bytes of the decoded hex) so the canonical cell is
    // OWNER-BOUND — VM-checkable + UTXO-binding-eligible (PushDrop needs a real
    // owner). Back-compat: zero-filled when no signer cert was supplied.
    var owner_id: [16]u8 = [_]u8{0} ** 16;
    if (req.signer_cert_id_hex) |cert_hex| deriveOwnerId(cert_hex, &owner_id);
    const cell = substrate_entity.encodeFromTypeHash(.{
        .type_hash = req.type_hash,
        .linearity = linearity_class,
        .owner_id = owner_id,
        .payload_json = req.payload_json,
    }) catch |err| switch (err) {
        substrate_entity.EncodeError.payload_too_large => return writeRejection(
            allocator,
            "payload_too_large",
            "payload exceeds 768-byte inline budget; octave-1 escalation pending M2 follow-up",
        ),
    };

    // Step 4.5 — C11 PR4b: cell-script handler dispatch. When the cell
    // type declares a handler in its manifest, the bytecode runs through
    // the cell-engine 2-PDA via `dispatchCellScriptHandler` above. The
    // input cell is pushed onto the main stack; any emitted cells left
    // on the stack are persisted post-execution after passing the emits
    // allowlist gate. A rejection here aborts the WHOLE mint — the
    // input cell does NOT get persisted at step 5.
    if (cell_script_handler_registry.lookup(&req.type_hash)) |hentry| {
        const outcome = dispatchCellScriptHandler(
            self,
            allocator,
            hentry,
            entry.cartridge_id,
            &cell,
        );
        switch (outcome) {
            .success => |s| {
                var th_hex: [64]u8 = undefined;
                bytesToHex(&req.type_hash, &th_hex);
                std.log.info(
                    "cells_mint: handler dispatched typeHash=0x{s} cartridge={s} emitted_cells={d}",
                    .{ th_hex[0..64], entry.cartridge_id, s.emitted_count },
                );
            },
            .rejection => |reason| {
                return writeRejection(allocator, "handler_rejected", reason);
            },
            .internal_error => |msg| {
                return writeRejection(allocator, "handler_internal_error", msg);
            },
        }
    }

    // Step 5 — persist.
    const cell_hash = self.cell_store.put(&cell) catch return HandlerError.store_error;

    // Step 6 — broker publish (best-effort; matches HTTP path posture).
    var cell_hash_hex: [64]u8 = undefined;
    bytesToHex(&cell_hash, &cell_hash_hex);
    var subject_buf: [128]u8 = undefined;
    const subject = std.fmt.bufPrint(&subject_buf, "cells.{s}.minted", .{entry.cartridge_id}) catch
        "cells.minted";
    var event_payload_buf: [512]u8 = undefined;
    const event_payload = std.fmt.bufPrint(
        &event_payload_buf,
        "{{\"cellId\":\"{s}\",\"cartridgeId\":\"{s}\",\"cellType\":\"{s}\"}}",
        .{ cell_hash_hex[0..64], entry.cartridge_id, entry.cell_type_name },
    ) catch event_payload_buf[0..0];
    self.broker.publish(.{
        .type = subject,
        .payload_json = event_payload,
    });

    // Step 7 — REPL-shaped response. `ok: true` echoes the resolved
    // metadata so a CLI script can capture the cellId without re-deriving.
    const persisted_at = std.time.milliTimestamp();
    const result_json = std.fmt.allocPrint(
        allocator,
        "{{\"ok\":true,\"cellId\":\"{s}\",\"cartridgeId\":\"{s}\",\"cellType\":\"{s}\",\"persistedAt\":{d}}}",
        .{ cell_hash_hex[0..64], entry.cartridge_id, entry.cell_type_name, persisted_at },
    ) catch return HandlerError.out_of_memory;
    return dispatcher.Result.ownedPayload(allocator, result_json);
}

/// Build a structured rejection response. Mirrors cell_handler.zig's
/// shape (`{ok:false, error, hint}`) so REPL scripts can pattern-match
/// on the same keys regardless of which handler rejected.
fn writeRejection(
    allocator: std.mem.Allocator,
    error_kind: []const u8,
    hint: []const u8,
) !dispatcher.Result {
    const json = std.fmt.allocPrint(
        allocator,
        "{{\"ok\":false,\"error\":\"{s}\",\"hint\":\"{s}\"}}",
        .{ error_kind, hint },
    ) catch return HandlerError.out_of_memory;
    return dispatcher.Result.ownedPayload(allocator, json);
}

/// C10 PR-2d variant — same shape as writeRejection plus an optional
/// `rejection_code` field carrying the executor's token (e.g. `verify_failed`,
/// `invalid_pushdata`).  Mirrors cell_handler.zig's writeRejection signature
/// so the two REPL surfaces emit byte-identical rejection envelopes.
fn writeRejectionWithCode(
    allocator: std.mem.Allocator,
    error_kind: []const u8,
    hint: []const u8,
    rejection_code: ?[]const u8,
) !dispatcher.Result {
    const json = if (rejection_code) |code|
        std.fmt.allocPrint(
            allocator,
            "{{\"ok\":false,\"error\":\"{s}\",\"hint\":\"{s}\",\"rejection_code\":\"{s}\"}}",
            .{ error_kind, hint, code },
        ) catch return HandlerError.out_of_memory
    else
        std.fmt.allocPrint(
            allocator,
            "{{\"ok\":false,\"error\":\"{s}\",\"hint\":\"{s}\"}}",
            .{ error_kind, hint },
        ) catch return HandlerError.out_of_memory;
    return dispatcher.Result.ownedPayload(allocator, json);
}

/// C10 PR-2d — same helper as cell_handler.decodeBase64.  Kept private here
/// to avoid a new dependency module just for one shared function; the two
/// implementations are intentionally identical and tested independently.
fn decodeBase64(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const max_len = decoder.calcSizeForSlice(input) catch return error.invalid_base64;
    const out = try allocator.alloc(u8, max_len);
    errdefer allocator.free(out);
    decoder.decode(out, input) catch return error.invalid_base64;
    return out;
}

fn bytesToHex(bytes: []const u8, out: []u8) void {
    const hex_chars = "0123456789abcdef";
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        out[i * 2] = hex_chars[(bytes[i] >> 4) & 0x0F];
        out[i * 2 + 1] = hex_chars[bytes[i] & 0x0F];
    }
}

/// CC-1 — derive the 16-byte cell ownerId from a signer cert-id hex string
/// (first 16 decoded bytes, zero-padded). Tolerant: stops at the first invalid
/// hex char or 16 bytes, leaving the remainder zero — a malformed/short cert-id
/// degrades to a partial/zero owner rather than failing the mint.
fn deriveOwnerId(cert_id_hex: []const u8, out: *[16]u8) void {
    out.* = [_]u8{0} ** 16;
    const pairs = @min(cert_id_hex.len / 2, out.len);
    var i: usize = 0;
    while (i < pairs) : (i += 1) {
        const hi = hexNibble(cert_id_hex[i * 2]) orelse return;
        const lo = hexNibble(cert_id_hex[i * 2 + 1]) orelse return;
        out[i] = (hi << 4) | lo;
    }
}

fn hexNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure-function coverage. Full handler conformance (REPL
// round-trip with live CellStore + broker) lives in tests/ as it needs
// fixtures we don't construct here.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "CC-1 deriveOwnerId: 16-byte owner from a 32-hex cert-id" {
    var owner: [16]u8 = undefined;
    deriveOwnerId("0123456789abcdef0123456789abcdef", &owner);
    try testing.expectEqual(@as(u8, 0x01), owner[0]);
    try testing.expectEqual(@as(u8, 0xef), owner[15]);
    // a non-zero owner is the whole point — UTXO-binding eligibility.
    try testing.expect(!std.mem.allEqual(u8, &owner, 0));
}

test "CC-1 deriveOwnerId: longer cert-id truncates to first 16 bytes" {
    var owner: [16]u8 = undefined;
    deriveOwnerId("aa" ** 40, &owner); // 40 bytes of 0xaa
    try testing.expect(std.mem.allEqual(u8, &owner, 0xaa));
}

test "CC-1 deriveOwnerId: empty / malformed degrades to zero owner" {
    var owner: [16]u8 = undefined;
    deriveOwnerId("", &owner);
    try testing.expect(std.mem.allEqual(u8, &owner, 0));
    deriveOwnerId("zzzz", &owner);
    try testing.expect(std.mem.allEqual(u8, &owner, 0));
}

test "writeRejection emits {ok:false,error,hint}" {
    var result = try writeRejection(testing.allocator, "unknown_type_hash", "no entry");
    defer result.deinit();
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"ok\":false") != null);
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"error\":\"unknown_type_hash\"") != null);
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"hint\":\"no entry\"") != null);
}

test "bytesToHex pads to 2 chars per byte" {
    var out: [4]u8 = undefined;
    bytesToHex(&[_]u8{ 0x00, 0xff }, &out);
    try testing.expectEqualStrings("00ff", &out);
}

test "bytesToHex round-trip on full 32-byte hash" {
    var hash: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) hash[i] = @intCast(i);
    var hex: [64]u8 = undefined;
    bytesToHex(&hash, &hex);
    try testing.expectEqualStrings(
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
        &hex,
    );
}

test "capForCmd: mint requires cap.brain.admin" {
    const decl = try capForCmd(null, "mint");
    try testing.expectEqualStrings("cap.brain.admin", decl.require);
}

test "capForCmd: unknown command rejected" {
    try testing.expectError(error.unknown_command, capForCmd(null, "unknown"));
}

test "isRead: mint is a write, never a read" {
    try testing.expect(!isRead("mint"));
    try testing.expect(!isRead("anything"));
}

// ─────────────────────────────────────────────────────────────────────
// C10 PR-2d inline tests — pure-function coverage for the kernel-gate
// helpers added to the canonical mint path.  Full handler behaviour
// (registry hit + cell_store.put + broker publish) needs fixtures and
// stays in tests/; here we only exercise the helpers we own.
// ─────────────────────────────────────────────────────────────────────

test "decodeBase64: round-trip OP_1 fixture" {
    // "UQ==" is base64 of 0x51 = OP_1 (the trivially-truthy precondition
    // used as the canonical accept-path smoke).  Reuse here keeps the
    // PR-2d fixture surface aligned across modules.
    const decoded = try decodeBase64(testing.allocator, "UQ==");
    defer testing.allocator.free(decoded);
    try testing.expectEqual(@as(usize, 1), decoded.len);
    try testing.expectEqual(@as(u8, 0x51), decoded[0]);
}

test "decodeBase64: rejects invalid input" {
    try testing.expectError(error.invalid_base64, decodeBase64(testing.allocator, "!!!"));
}

test "writeRejectionWithCode: includes rejection_code when present" {
    var result = try writeRejectionWithCode(
        testing.allocator,
        "kernel_rejected_locally",
        "PolicyRuntime rejected the opcode precondition stream",
        "verify_failed",
    );
    defer result.deinit();
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"ok\":false") != null);
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"error\":\"kernel_rejected_locally\"") != null);
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"rejection_code\":\"verify_failed\"") != null);
}

test "writeRejectionWithCode: omits rejection_code when null" {
    var result = try writeRejectionWithCode(
        testing.allocator,
        "kernel_local_exec_failed",
        "infrastructure error",
        null,
    );
    defer result.deinit();
    try testing.expect(std.mem.indexOf(u8, result.payload, "rejection_code") == null);
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"error\":\"kernel_local_exec_failed\"") != null);
}

test "C10 PR-2d gate: real_executor accepts OP_1 push (truthy top-of-stack)" {
    // End-to-end seam smoke: decode "UQ==" → 0x51 (OP_1) → PolicyRuntime
    // .real_executor evaluates → pushes 1 → top-of-stack truthy → ok=true.
    // This is the canonical "default-permit when opcode_bytes_b64 contains
    // a trivially-true precondition" path the gate block in handleMint
    // takes when a cartridge supplies preconditions but they pass.
    const decoded = try decodeBase64(testing.allocator, "UQ==");
    defer testing.allocator.free(decoded);

    var rt = policy_runtime.PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const ctx = policy_runtime.PolicyContext{
        .actor = .{ .cert_id = "", .capabilities = &[_]u32{} },
        .co_actor = null,
    };
    const r = try rt.evaluate(decoded, ctx);
    try testing.expect(r.ok);
    try testing.expectEqual(@as(?[]const u8, null), r.rejection_code);
}

test "C10 PR-2d gate: real_executor rejects OP_FALSE (verify_failed)" {
    // OP_FALSE = 0x00 = push empty bytes (treated as false top-of-stack
    // by the executor).  This is the canonical "cartridge precondition
    // failed" path the gate block converts into kernel_rejected_locally.
    // "AA==" is base64 of 0x00.
    const decoded = try decodeBase64(testing.allocator, "AA==");
    defer testing.allocator.free(decoded);

    var rt = policy_runtime.PolicyRuntime.initWithMode(testing.allocator, .real_executor);
    const ctx = policy_runtime.PolicyContext{
        .actor = .{ .cert_id = "", .capabilities = &[_]u32{} },
        .co_actor = null,
    };
    const r = try rt.evaluate(decoded, ctx);
    try testing.expect(!r.ok);
    try testing.expectEqualStrings("verify_failed", r.rejection_code.?);
}

// ── C11 PR4b — cell-engine integration smoke tests ────────────────────
//
// These exercise the PDA + arena + executor setup pattern that
// `dispatchCellScriptHandler` uses (steps 1-3 of the dispatcher),
// without the Handler/cell_store integration. Full integration
// tests through the mint pipeline land in a follow-up — they need
// a cell_store stub, which is its own scaffolding work.

test "PR4b cell-engine integration: push input cell + OP_1 script preserves cell on stack" {
    const pda = try testing.allocator.create(pda_mod.PDA);
    defer testing.allocator.destroy(pda);
    pda.initInPlace(1000);

    const arena_buf = try testing.allocator.alloc(u8, HANDLER_ARENA_SIZE);
    defer testing.allocator.free(arena_buf);
    var arena = allocator_mod.ScriptArena.init(arena_buf);

    var ctx = executor.ExecutionContext.init(pda, &arena);

    // Push a fake 1024-byte input cell (filled with 0xAA so we can
    // distinguish it from any emitted cell the script might produce).
    var input_cell: [CELL_SIZE]u8 = [_]u8{0xAA} ** CELL_SIZE;
    try pda.spushCell(&input_cell, CELL_SIZE);
    try testing.expectEqual(@as(u32, 1), pda.sdepth());

    // Run a minimal handler that just pushes OP_1 (truthy marker).
    try ctx.loadScript(&[_]u8{0x51});
    const truthy = try executor.execute(&ctx);
    try testing.expect(truthy);

    // Stack should be: [input_cell (1024 bytes), OP_1 result (1 byte)].
    try testing.expectEqual(@as(u32, 2), pda.sdepth());
    try testing.expectEqual(@as(u32, CELL_SIZE), pda.main_lengths[0]);
}

test "PR4b cell-engine integration: OP_FALSE returns falsy" {
    const pda = try testing.allocator.create(pda_mod.PDA);
    defer testing.allocator.destroy(pda);
    pda.initInPlace(1000);

    const arena_buf = try testing.allocator.alloc(u8, HANDLER_ARENA_SIZE);
    defer testing.allocator.free(arena_buf);
    var arena = allocator_mod.ScriptArena.init(arena_buf);

    var ctx = executor.ExecutionContext.init(pda, &arena);

    // OP_FALSE = 0x00 pushes empty bytes (falsy under isTruthy).
    try ctx.loadScript(&[_]u8{0x00});
    const truthy = try executor.execute(&ctx);
    try testing.expect(!truthy);
    // Dispatcher maps this to .rejection = "script_returned_falsy".
}

test "PR4b cell-engine integration: opcount budget enforces execution_limit" {
    const pda = try testing.allocator.create(pda_mod.PDA);
    defer testing.allocator.destroy(pda);
    pda.initInPlace(3); // budget = 3, script will exceed it

    const arena_buf = try testing.allocator.alloc(u8, HANDLER_ARENA_SIZE);
    defer testing.allocator.free(arena_buf);
    var arena = allocator_mod.ScriptArena.init(arena_buf);

    var ctx = executor.ExecutionContext.init(pda, &arena);

    // 7 × OP_1 exceeds budget=3.
    try ctx.loadScript(&[_]u8{ 0x51, 0x51, 0x51, 0x51, 0x51, 0x51, 0x51 });
    const result = executor.execute(&ctx);
    try testing.expectError(error.execution_limit, result);
    // Dispatcher maps this to .rejection = "opcount_exhausted".
}

// ── PR-3c boot-registration tests ─────────────────────────────────────
//
// These exercise the boot-side wiring of the host_compute_sighash
// hostcall. The per-script Context construction + executor integration
// (so a real OP_CALLHOST during a mint reaches the registered handler)
// is PR-3d / PR-4 work; here we verify the registry side only.

test "PR-3c..PR-8b-i boot: bootRegisterHostCalls registers the full hostcall set" {
    host.resetRegistryForTest();
    try bootRegisterHostCalls();
    // Nine hostcalls expected after PR-8b-i lands:
    //   host_compute_sighash               (PR-3b,   cap.tx.sign)
    //   host_resolve_script_template       (PR-4,    cap.tx.build)
    //   host_verify_partial_sig            (PR-5,    cap.tx.sign)
    //   host_compute_prevouts_hash         (PR-5,    no cap)
    //   host_compute_sequence_hash         (PR-5,    no cap)
    //   host_compute_outputs_hash          (PR-5,    no cap)
    //   host_assemble_tx                   (PR-5b,   cap.tx.build)
    //   host_verify_beef_spv               (PR-7a,   bsv.beef.verify)
    //   host_mnca_verify_transition        (PR-8b-i, cap.mnca.verify)
    try testing.expectEqual(@as(usize, 9), host.registryCountForTest());
}

test "PR-3c boot: bootRegisterHostCalls is idempotent across multiple inits" {
    host.resetRegistryForTest();
    try bootRegisterHostCalls();
    try bootRegisterHostCalls(); // simulate a second Handler.init — must not error
    try bootRegisterHostCalls();
    try testing.expectEqual(@as(usize, 9), host.registryCountForTest());
}

test "PR-8b-i boot: host_mnca_verify_transition resolvable after boot" {
    host.resetRegistryForTest();
    try bootRegisterHostCalls();
    const rc = host.callByName("host_mnca_verify_transition");
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), rc); // no context → sentinel
}

test "PR-4 boot: host_resolve_script_template resolvable after boot" {
    host.resetRegistryForTest();
    try bootRegisterHostCalls();
    // No execution context — resolves the name then returns no-context sentinel.
    const rc = host.callByName("host_resolve_script_template");
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), rc);
}

test "PR-5 boot: host_verify_partial_sig resolvable after boot" {
    host.resetRegistryForTest();
    try bootRegisterHostCalls();
    const rc = host.callByName("host_verify_partial_sig");
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), rc); // no context → sentinel
}

test "PR-5 boot: all three preimage hash hostcalls resolvable after boot" {
    host.resetRegistryForTest();
    try bootRegisterHostCalls();
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), host.callByName("host_compute_prevouts_hash"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), host.callByName("host_compute_sequence_hash"));
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), host.callByName("host_compute_outputs_hash"));
}

test "PR-5b boot: host_assemble_tx resolvable after boot" {
    host.resetRegistryForTest();
    try bootRegisterHostCalls();
    const rc = host.callByName("host_assemble_tx");
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), rc); // no context → sentinel
}

test "PR-7a boot: host_verify_beef_spv resolvable after boot" {
    host.resetRegistryForTest();
    try bootRegisterHostCalls();
    const rc = host.callByName("host_verify_beef_spv");
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), rc); // no context → sentinel
}

test "PR-3c boot: callByName resolves host_compute_sighash after boot (no context → 0xFFFFFFFE)" {
    host.resetRegistryForTest();
    try bootRegisterHostCalls();
    // No execution context set — registry resolves the name, dispatch
    // returns the no-context sentinel.
    const rc = host.callByName("host_compute_sighash");
    try testing.expectEqual(@as(u32, 0xFFFFFFFE), rc);
}

test "PR-3c boot: callByName for unknown name still returns 0xFFFFFFFF after boot" {
    host.resetRegistryForTest();
    try bootRegisterHostCalls();
    const rc = host.callByName("host_definitely_not_registered");
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), rc);
}

// ── PR-3d: ScriptContextBuilder seam tests ────────────────────────────
//
// These verify the dispatcher's seam wiring in isolation: that the
// build_fn is called with the right inputs, that the returned pointer
// gets installed via host.setExecutionContext, and that destroy_fn
// always fires. The bsv-spv-verify-specific builder lives in
// cells_mint_spv_context.zig and has its own tests.

/// Test-only state for the mock builder: records every call so the
/// test can assert it fired with the right inputs.
const MockBuilderState = struct {
    build_called: bool = false,
    destroy_called: bool = false,
    last_input_cell_first_byte: u8 = 0,
    returned_ptr: ?*anyopaque = null,
    return_null: bool = false,
};

const MockSentinel: u32 = 0xDEADBEEF;

fn mockBuild(
    state_any: *anyopaque,
    input_cell: *const [CELL_SIZE]u8,
    allocator: std.mem.Allocator,
) ?*anyopaque {
    const state: *MockBuilderState = @ptrCast(@alignCast(state_any));
    state.build_called = true;
    state.last_input_cell_first_byte = input_cell[0];

    if (state.return_null) return null;

    // Allocate a sentinel u32 — destroy_fn must free it for the
    // testing allocator's leak detector to stay happy.
    const sentinel = allocator.create(u32) catch return null;
    sentinel.* = MockSentinel;
    state.returned_ptr = @ptrCast(sentinel);
    return @ptrCast(sentinel);
}

fn mockDestroy(state_any: *anyopaque, ctx: *anyopaque, allocator: std.mem.Allocator) void {
    const state: *MockBuilderState = @ptrCast(@alignCast(state_any));
    state.destroy_called = true;
    const sentinel: *u32 = @ptrCast(@alignCast(ctx));
    allocator.destroy(sentinel);
}

fn mockBuilder(state: *MockBuilderState) ScriptContextBuilder {
    return .{
        .state = @ptrCast(state),
        .build_fn = mockBuild,
        .destroy_fn = mockDestroy,
    };
}

test "PR-3d seam: ScriptContextBuilder shape exposes build_fn + destroy_fn" {
    var state = MockBuilderState{};
    const builder = mockBuilder(&state);
    try testing.expect(builder.build_fn == mockBuild);
    try testing.expect(builder.destroy_fn == mockDestroy);
    try testing.expect(@intFromPtr(builder.state) == @intFromPtr(&state));
}

test "PR-3d seam: setContextBuilder swaps the builder atomically" {
    // We don't run a real Handler.init here (it needs broker + cell_store
    // wiring beyond this test's scope). Instead we construct a Handler
    // by-field to exercise the setContextBuilder semantics.
    var handler = Handler{
        .allocator = testing.allocator,
        .cell_store = undefined,
        .broker = undefined,
        .context_builder = null,
        .mu = .{},
    };

    var state = MockBuilderState{};
    const builder = mockBuilder(&state);

    handler.setContextBuilder(builder);
    try testing.expect(handler.context_builder != null);
    try testing.expect(handler.context_builder.?.build_fn == mockBuild);

    handler.setContextBuilder(null);
    try testing.expect(handler.context_builder == null);
}

test "PR-3d seam: mock builder build_fn fires + returns a sentinel" {
    var state = MockBuilderState{};
    var cell: [CELL_SIZE]u8 = undefined;
    @memset(&cell, 0);
    cell[0] = 0x7E;

    const result = mockBuild(@ptrCast(&state), &cell, testing.allocator);
    try testing.expect(state.build_called);
    try testing.expectEqual(@as(u8, 0x7E), state.last_input_cell_first_byte);
    try testing.expect(result != null);

    // Verify the returned pointer carries our sentinel.
    const sentinel: *u32 = @ptrCast(@alignCast(result.?));
    try testing.expectEqual(MockSentinel, sentinel.*);

    // Teardown.
    mockDestroy(@ptrCast(&state), result.?, testing.allocator);
    try testing.expect(state.destroy_called);
}

test "PR-3d seam: build_fn returning null is a valid path" {
    var state = MockBuilderState{ .return_null = true };
    var cell: [CELL_SIZE]u8 = undefined;
    @memset(&cell, 0);

    const result = mockBuild(@ptrCast(&state), &cell, testing.allocator);
    try testing.expect(state.build_called);
    try testing.expect(result == null);
    // destroy_fn must NOT be called when build returned null — the
    // dispatcher's defer block predicates on `if (exec_ctx_ptr) |p|`.
    try testing.expect(!state.destroy_called);
}

// ── PR-8b-iv: CompositeContextBuilder tests ───────────────────────────

test "PR-8b-iv composite: first non-null child wins; destroy routes to it" {
    var state_a = MockBuilderState{};
    var state_b = MockBuilderState{};
    const children = [_]ScriptContextBuilder{
        mockBuilder(&state_a),
        mockBuilder(&state_b),
    };
    var composite = CompositeContextBuilder{ .children = &children };
    const builder = composite.toBuilder();

    var cell: [CELL_SIZE]u8 = undefined;
    @memset(&cell, 0);

    const result = builder.build_fn(builder.state, &cell, testing.allocator);
    try testing.expect(result != null);
    try testing.expect(state_a.build_called);
    // Second child should NOT have been called — composite stops at first winner.
    try testing.expect(!state_b.build_called);
    try testing.expectEqual(@as(?usize, 0), composite.last_built_child);

    builder.destroy_fn(builder.state, result.?, testing.allocator);
    try testing.expect(state_a.destroy_called);
    try testing.expect(!state_b.destroy_called);
    // last_built_child resets to null after destroy.
    try testing.expectEqual(@as(?usize, null), composite.last_built_child);
}

test "PR-8b-iv composite: first child returns null → second child runs" {
    var state_a = MockBuilderState{ .return_null = true };
    var state_b = MockBuilderState{};
    const children = [_]ScriptContextBuilder{
        mockBuilder(&state_a),
        mockBuilder(&state_b),
    };
    var composite = CompositeContextBuilder{ .children = &children };
    const builder = composite.toBuilder();

    var cell: [CELL_SIZE]u8 = undefined;
    @memset(&cell, 0);

    const result = builder.build_fn(builder.state, &cell, testing.allocator);
    try testing.expect(result != null);
    try testing.expect(state_a.build_called);
    try testing.expect(state_b.build_called);
    try testing.expectEqual(@as(?usize, 1), composite.last_built_child);

    builder.destroy_fn(builder.state, result.?, testing.allocator);
    try testing.expect(!state_a.destroy_called);
    try testing.expect(state_b.destroy_called);
}

test "PR-8b-iv composite: all children return null → composite returns null" {
    var state_a = MockBuilderState{ .return_null = true };
    var state_b = MockBuilderState{ .return_null = true };
    const children = [_]ScriptContextBuilder{
        mockBuilder(&state_a),
        mockBuilder(&state_b),
    };
    var composite = CompositeContextBuilder{ .children = &children };
    const builder = composite.toBuilder();

    var cell: [CELL_SIZE]u8 = undefined;
    @memset(&cell, 0);

    const result = builder.build_fn(builder.state, &cell, testing.allocator);
    try testing.expect(result == null);
    try testing.expect(state_a.build_called);
    try testing.expect(state_b.build_called);
    try testing.expectEqual(@as(?usize, null), composite.last_built_child);
}

test "PR-8b-iv composite: destroy with no prior build is a defence-in-depth no-op" {
    var state_a = MockBuilderState{};
    const children = [_]ScriptContextBuilder{mockBuilder(&state_a)};
    var composite = CompositeContextBuilder{ .children = &children };
    const builder = composite.toBuilder();

    // No build call; last_built_child stays null.
    var dummy: u32 = 42;
    builder.destroy_fn(builder.state, @ptrCast(&dummy), testing.allocator);
    // No-op — state_a's destroy_fn was NOT called.
    try testing.expect(!state_a.destroy_called);
}

// ── PR-8b-v: extra_cells_fn routing through CompositeContextBuilder ───
//
// MockBuilderState extended via separate mock fns that return a fixed
// 1-cell slice. The composite must route extra_cells through to the
// winning child + skip non-winning children.

var test_extra_cell_storage: [CELL_SIZE]u8 = undefined;
var mock_extra_cells_called: bool = false;
var mock_extra_cells_destroy_called: bool = false;

fn mockExtraCells(
    state_any: *anyopaque,
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
) ?[]const [CELL_SIZE]u8 {
    _ = state_any;
    _ = ctx;
    _ = allocator;
    mock_extra_cells_called = true;
    @memset(&test_extra_cell_storage, 0x77);
    return @as([*]const [CELL_SIZE]u8, @ptrCast(&test_extra_cell_storage))[0..1];
}

fn mockExtraCellsDestroy(
    state_any: *anyopaque,
    extra: []const [CELL_SIZE]u8,
    allocator: std.mem.Allocator,
) void {
    _ = state_any;
    _ = extra;
    _ = allocator;
    mock_extra_cells_destroy_called = true;
}

fn mockBuilderWithExtraCells(state: *MockBuilderState) ScriptContextBuilder {
    return .{
        .state = @ptrCast(state),
        .build_fn = mockBuild,
        .destroy_fn = mockDestroy,
        .extra_cells_fn = mockExtraCells,
        .extra_cells_destroy_fn = mockExtraCellsDestroy,
    };
}

test "PR-8b-v composite: extra_cells routes through winning child" {
    mock_extra_cells_called = false;
    mock_extra_cells_destroy_called = false;
    var state_a = MockBuilderState{ .return_null = true };
    var state_b = MockBuilderState{};
    const children = [_]ScriptContextBuilder{
        mockBuilder(&state_a),
        mockBuilderWithExtraCells(&state_b),
    };
    var composite = CompositeContextBuilder{ .children = &children };
    const builder = composite.toBuilder();

    var cell: [CELL_SIZE]u8 = undefined;
    @memset(&cell, 0);

    const result = builder.build_fn(builder.state, &cell, testing.allocator);
    try testing.expect(result != null);
    try testing.expectEqual(@as(?usize, 1), composite.last_built_child);

    // extra_cells_fn must route to child 1, which has the extra_cells callback.
    const extra = builder.extra_cells_fn.?(builder.state, result.?, testing.allocator);
    try testing.expect(extra != null);
    try testing.expectEqual(@as(usize, 1), extra.?.len);
    try testing.expect(mock_extra_cells_called);

    // extra_cells_destroy must also route to child 1.
    builder.extra_cells_destroy_fn.?(builder.state, extra.?, testing.allocator);
    try testing.expect(mock_extra_cells_destroy_called);

    // Final destroy_fn fires last in the dispatcher's LIFO defer order;
    // it must STILL be able to route (last_built_child intact after
    // extra_cells_destroy).
    try testing.expectEqual(@as(?usize, 1), composite.last_built_child);
    builder.destroy_fn(builder.state, result.?, testing.allocator);
    try testing.expect(state_b.destroy_called);
    // After destroy, composite resets for the next dispatch.
    try testing.expectEqual(@as(?usize, null), composite.last_built_child);
}

test "PR-8b-v composite: extra_cells returns null when winning child has no extra_cells_fn" {
    mock_extra_cells_called = false;
    var state_a = MockBuilderState{};
    const children = [_]ScriptContextBuilder{
        // mockBuilder (no extra_cells_fn) — defaults to null.
        mockBuilder(&state_a),
    };
    var composite = CompositeContextBuilder{ .children = &children };
    const builder = composite.toBuilder();

    var cell: [CELL_SIZE]u8 = undefined;
    @memset(&cell, 0);

    const result = builder.build_fn(builder.state, &cell, testing.allocator);
    try testing.expect(result != null);

    const extra = builder.extra_cells_fn.?(builder.state, result.?, testing.allocator);
    try testing.expect(extra == null);
    try testing.expect(!mock_extra_cells_called);

    builder.destroy_fn(builder.state, result.?, testing.allocator);
}

```
