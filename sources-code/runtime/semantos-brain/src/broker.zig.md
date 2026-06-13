---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/broker.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.234136+00:00
---

# runtime/semantos-brain/src/broker.zig

```zig
// Phase Brain 2 — Host-import broker.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 2 deliverables 1–4).
//
// Single dispatch point for every host-side call a WASM module makes —
// storage I/O, crypto, derivation, network, cross-module routing. Three
// concerns:
//
//   1. **Routing** — dispatches each named call to the right backing
//      (SlotStore / DerivationStateStore / HeaderStore / future bsvz
//      crypto + broadcast).
//
//   2. **Module-isolation policy** — each module sees only the import
//      surface its responsibilities allow. Wallet engine calling
//      `host_fetch_header_range` → denied. Headers verifier calling
//      `host_sign` → denied. Violations return `error.policy_denied`
//      and emit a `denied` audit-log entry.
//
//   3. **Audit log** — every dispatch records `(ts, module, op, result,
//      detail)` to the audit log so the operator can see what each
//      module is doing in real time. Detail strings never include
//      plaintext secrets — the broker pre-summarises (e.g., "len=1024"
//      not the cell bytes).
//
// Brain 2 ships the dispatcher + policy + audit wiring + storage call
// surfaces. The broker is callable from native Zig today (tests do this
// directly to verify routing). When Brain 2.5 lands wasmtime, the actual
// host-import callbacks are thin shims that decode WASM linear-memory
// pointers + lengths and forward to `Broker.dispatch*` — all the policy
// + audit logic lives here.

const std = @import("std");
const slot_store_mod = @import("slot_store");
const derivation_state_mod = @import("derivation_state");
const header_store_mod = @import("header_store");
const audit_log_mod = @import("audit_log");
const beef = @import("beef");

pub const Module = enum {
    /// The wallet engine — owns tier base keys, leaf-key derivation,
    /// signing. Reads + writes SlotStore + DerivationStateStore. Asks
    /// the headers verifier (via cross-module bridge) for SPV roots.
    wallet_engine,
    /// The headers verifier — owns the PoW-validated header chain.
    /// Reads + writes HeaderStore. Answers `host_verify_beef_root`
    /// queries from wallet_engine.
    headers_verifier,
    /// WSITE2.5 — a dynamic-route WASM handler bound to a single site
    /// route.  Treated as untrusted code: allowed to call stateless
    /// hash + chain-context primitives, but DENIED everything that
    /// touches the wallet's keys, slots, derivation state, or headers
    /// chain.  Effectively pure: handler memory is the only mutable
    /// state, and that's reset between requests by the runner.
    dynamic_handler,
    /// C11 PR4a — cell-engine script handler (typeHash → bytecode
    /// dispatched via the 2-PDA executor). Placeholder for the call
    /// site PR4b's dispatcher will use when invoking
    /// `checkInvocationCapabilities` to authorise a caller against
    /// the manifest's `handler.capabilities[]`.
    script_handler,
};

pub const BrokerError = error{
    policy_denied,
    not_found,
    persistence_failed,
    out_of_memory,
    audit_failed,
    invalid_height,
};

/// PR-C11-7e-2e-2 — outcome of `checkInvocationCapabilities`. A
/// tagged union (rather than a bare bool) so 7e-2e-2 can ship the
/// typed seam reviewer-ask-style WITHOUT pretending enforcement
/// exists. The mint pipeline inspects the tag and either proceeds
/// (`granted`) or audits + refuses with the carried reason.
///
/// Reasons are stable strings (mirror `audit_log_mod.Result` detail
/// surfaces). Adding a new reason is a non-breaking change; renaming
/// one is breaking for any operator dashboards keyed on the string.
pub const AuthzResult = union(enum) {
    /// The caller is authorised. The mint pipeline may fire the 2PDA.
    granted,
    /// The caller is NOT authorised. Refuse the mint; surface the
    /// reason in the audit trail.
    denied: []const u8,
    /// The structural inputs say a real cert check is required but
    /// the verifier hasn't been wired yet (Phase-1b BCA un-park
    /// pending). Distinct tag — not `denied` — so the mint pipeline
    /// can audit it as a known-deferred gap rather than a security
    /// rejection. Refuses the mint regardless (fail-closed).
    cert_verifier_pending: []const u8,
};

pub const Broker = struct {
    allocator: std.mem.Allocator,
    slot: slot_store_mod.SlotStore,
    state: derivation_state_mod.DerivationStateStore,
    headers: header_store_mod.HeaderStore,
    audit: *audit_log_mod.AuditLog,

    pub fn init(
        allocator: std.mem.Allocator,
        slot: slot_store_mod.SlotStore,
        state: derivation_state_mod.DerivationStateStore,
        headers: header_store_mod.HeaderStore,
        audit: *audit_log_mod.AuditLog,
    ) Broker {
        return .{
            .allocator = allocator,
            .slot = slot,
            .state = state,
            .headers = headers,
            .audit = audit,
        };
    }

    // ──────────────────────────────────────────────────────────────────
    // Storage — host_persist_cell / host_load_cell
    // Both modules MAY persist (they own different slot-id namespaces),
    // so the policy gate is by slot-id range rather than module name.
    // For v0.1 we permit any module to call slot ops; per-namespace
    // checks land alongside the WSITE multi-tenant story.
    // ──────────────────────────────────────────────────────────────────

    pub fn hostPersistCell(
        self: *Broker,
        module: Module,
        slot_id: u32,
        bytes: []const u8,
    ) BrokerError!void {
        try self.recordStart(module, "host_persist_cell", "");
        self.slot.put(slot_id, bytes) catch |err| {
            const msg = std.fmt.allocPrint(self.allocator, "slot={d} len={d} err={s}", .{ slot_id, bytes.len, @errorName(err) }) catch "";
            defer if (msg.len > 0) self.allocator.free(msg);
            try self.recordResult(module, "host_persist_cell", .err, msg);
            return error.persistence_failed;
        };
        const detail = std.fmt.allocPrint(self.allocator, "slot={d} len={d}", .{ slot_id, bytes.len }) catch "";
        defer if (detail.len > 0) self.allocator.free(detail);
        try self.recordResult(module, "host_persist_cell", .ok, detail);
    }

    pub fn hostLoadCell(
        self: *Broker,
        module: Module,
        slot_id: u32,
    ) BrokerError![]const u8 {
        try self.recordStart(module, "host_load_cell", "");
        const blob = self.slot.get(slot_id) catch |err| {
            const detail = std.fmt.allocPrint(self.allocator, "slot={d} err={s}", .{ slot_id, @errorName(err) }) catch "";
            defer if (detail.len > 0) self.allocator.free(detail);
            try self.recordResult(module, "host_load_cell", .err, detail);
            return switch (err) {
                error.not_found => error.not_found,
                else => error.persistence_failed,
            };
        };
        const detail = std.fmt.allocPrint(self.allocator, "slot={d} len={d}", .{ slot_id, blob.len }) catch "";
        defer if (detail.len > 0) self.allocator.free(detail);
        try self.recordResult(module, "host_load_cell", .ok, detail);
        return blob;
    }

    // ──────────────────────────────────────────────────────────────────
    // Derivation — host_state_next_index
    // Wallet-engine-only.
    // ──────────────────────────────────────────────────────────────────

    pub fn hostStateNextIndex(
        self: *Broker,
        module: Module,
        protocol_hash: *const [16]u8,
        counterparty: *const [33]u8,
    ) BrokerError!u64 {
        if (module != .wallet_engine) {
            try self.recordResult(module, "host_state_next_index", .denied, "wallet-engine-only");
            return error.policy_denied;
        }
        const idx = self.state.nextIndex(protocol_hash, counterparty) catch |err| {
            const detail = std.fmt.allocPrint(self.allocator, "err={s}", .{@errorName(err)}) catch "";
            defer if (detail.len > 0) self.allocator.free(detail);
            try self.recordResult(module, "host_state_next_index", .err, detail);
            return error.persistence_failed;
        };
        const detail = std.fmt.allocPrint(self.allocator, "index={d}", .{idx}) catch "";
        defer if (detail.len > 0) self.allocator.free(detail);
        try self.recordResult(module, "host_state_next_index", .ok, detail);
        return idx;
    }

    // ──────────────────────────────────────────────────────────────────
    // Cross-module — host_verify_beef_root
    // Wallet engine asks headers verifier for the canonical merkle root
    // at a height.  Routed through the broker so the wallet engine
    // never touches HeaderStore directly — the boundary is enforced by
    // routing, not by trust.
    // ──────────────────────────────────────────────────────────────────

    pub fn hostVerifyBeefRoot(
        self: *Broker,
        module: Module,
        height: u32,
    ) BrokerError![32]u8 {
        if (module != .wallet_engine) {
            try self.recordResult(module, "host_verify_beef_root", .denied, "wallet-engine-only");
            return error.policy_denied;
        }
        const rec = self.headers.getByHeight(height) orelse {
            const detail = std.fmt.allocPrint(self.allocator, "height={d}", .{height}) catch "";
            defer if (detail.len > 0) self.allocator.free(detail);
            try self.recordResult(module, "host_verify_beef_root", .err, detail);
            return error.invalid_height;
        };
        const detail = std.fmt.allocPrint(self.allocator, "height={d}", .{height}) catch "";
        defer if (detail.len > 0) self.allocator.free(detail);
        try self.recordResult(module, "host_verify_beef_root", .ok, detail);
        return rec.header.merkle_root;
    }

    // ──────────────────────────────────────────────────────────────────
    // BEEF SPV verification — host_verify_beef_spv
    //
    // C11 PR-C11-7d. Composes `core/cell-engine/src/beef.zig::verifyBeefSpv`
    // with the broker's HeaderStore: snapshots the local chain, extracts
    // every header's merkle root as the trusted-roots set, and forwards
    // the BEEF + txid into the cell-engine primitive.
    //
    // The verifier is **fail-closed**: any internal failure (parse error,
    // txid not in the BEEF, missing trusted root match, allocation
    // failure) returns `false`. Only audit-log + allocator-OOM bubble
    // up as broker errors.
    //
    // Policy gate: any-module. BEEF SPV check is read-only — it returns
    // a bool, never mutates state. The capability formalisation lands
    // in PR-C11-7e with cell-type manifest loading; until then, any
    // module that can reach the host call is allowed to invoke it.
    // Auditing every dispatch keeps the policy decision observable.
    //
    // See docs/design/LINEAR-CELL-SPV-STATE.md §3.2 + §7.
    // ──────────────────────────────────────────────────────────────────

    pub fn hostVerifyBeefSpv(
        self: *Broker,
        module: Module,
        beef_bytes: []const u8,
        txid: [32]u8,
    ) BrokerError!bool {
        // Snapshot the chain to build the trusted-roots set. The
        // verifier accepts iff every BUMP root in the BEEF matches one
        // of these.
        const records = self.headers.snapshot(self.allocator) catch {
            try self.recordResult(module, "host_verify_beef_spv", .err, "snapshot-failed");
            return error.persistence_failed;
        };
        defer self.allocator.free(records);

        // Extract merkle_root per header. Allocator failure here is
        // genuinely fatal (we're already in the verify hot path).
        var roots = self.allocator.alloc([32]u8, records.len) catch {
            try self.recordResult(module, "host_verify_beef_spv", .err, "roots-alloc-failed");
            return error.out_of_memory;
        };
        defer self.allocator.free(roots);
        for (records, 0..) |rec, i| roots[i] = rec.header.merkle_root;

        const ok = beef.verifyBeefSpv(self.allocator, beef_bytes, txid, roots) catch |err| {
            // Verification failure is NOT a broker error — it's a
            // legitimate "no" answer. Audit the cause + return false.
            const detail = std.fmt.allocPrint(
                self.allocator,
                "beef_len={d} roots_n={d} err={s}",
                .{ beef_bytes.len, roots.len, @errorName(err) },
            ) catch "";
            defer if (detail.len > 0) self.allocator.free(detail);
            try self.recordResult(module, "host_verify_beef_spv", .err, detail);
            return false;
        };

        const detail = std.fmt.allocPrint(
            self.allocator,
            "beef_len={d} roots_n={d} valid={any}",
            .{ beef_bytes.len, roots.len, ok },
        ) catch "";
        defer if (detail.len > 0) self.allocator.free(detail);
        try self.recordResult(module, "host_verify_beef_spv", .ok, detail);
        return ok;
    }

    // ──────────────────────────────────────────────────────────────────
    // Headers-verifier-only — host_append_validated_header
    // Wallet engine MUST NOT append to the header chain.  Routing the
    // append through the broker lets us audit every step the headers
    // verifier takes without trusting it not to call random imports.
    // ──────────────────────────────────────────────────────────────────

    pub fn hostAppendValidatedHeader(
        self: *Broker,
        module: Module,
        header: header_store_mod.Header,
        height: u32,
    ) BrokerError!void {
        if (module != .headers_verifier) {
            try self.recordResult(module, "host_append_validated_header", .denied, "headers-verifier-only");
            return error.policy_denied;
        }
        self.headers.appendValidated(header, height) catch |err| {
            const detail = std.fmt.allocPrint(self.allocator, "height={d} err={s}", .{ height, @errorName(err) }) catch "";
            defer if (detail.len > 0) self.allocator.free(detail);
            try self.recordResult(module, "host_append_validated_header", .err, detail);
            return error.persistence_failed;
        };
        const detail = std.fmt.allocPrint(self.allocator, "height={d}", .{height}) catch "";
        defer if (detail.len > 0) self.allocator.free(detail);
        try self.recordResult(module, "host_append_validated_header", .ok, detail);
    }

    // ──────────────────────────────────────────────────────────────────
    // Layer-2 invocation-capability check (generic gate)
    //
    // Capability layering for cell-type handlers:
    //
    //   Layer 1 (load-time): the cartridge loader refuses to bind a
    //     host import the manifest's `module.capabilities[]` doesn't
    //     claim. This gates what the module CAN CALL.
    //
    //   Layer 2 (call-time): this method. A dispatcher calls it
    //     BEFORE instantiating a handler, with the verified caller's
    //     capability set as `presented_caps`. This gates whether the
    //     handler GETS FIRED at all for this particular invocation.
    //
    // Typed seam — the signature is the long-term shape, but the body
    // is intentionally limited until Phase-1b BCA un-parks the cert
    // verifier. Behaviour today:
    //
    //   - If `require_cert == false` AND `required_caps` is empty,
    //     the structural inputs say no caller verification is
    //     needed. Returns `granted`.
    //
    //   - Otherwise the body would need the cert verifier to decide.
    //     Returns `cert_verifier_pending` with an explanatory
    //     reason; dispatcher refuses the call (fail-closed).
    //
    // No silent default-allow: a handler that declares ANY
    // invocation cap stays gated until Phase-1b lands.
    // ──────────────────────────────────────────────────────────────────

    pub fn checkInvocationCapabilities(
        self: *Broker,
        module: Module,
        handler_id: [32]u8,
        required_caps: []const []const u8,
        require_cert: bool,
        presented_caps: []const []const u8,
    ) BrokerError!AuthzResult {
        _ = handler_id;
        // Audit detail surfaces the structural input shape so
        // operator dashboards can distinguish "gate wasn't needed"
        // from "gate fired but verifier stubbed".
        var detail_buf: [64]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "req_cert={} req_caps={} presented={}",
            .{ require_cert, required_caps.len, presented_caps.len },
        ) catch "fmt-failed";

        // Path A: structural no-op-gate. require_cert=false AND no
        // caps required → no verifier needed → grant.
        if (!require_cert and required_caps.len == 0) {
            try self.recordResult(module, "check_invocation_capabilities", .ok, detail);
            return .granted;
        }

        // Path B: gate fires but verifier is the Phase-1b BCA
        // un-park dependency. Surface as a distinct tag so callers
        // can route on it, but refuse the mint.
        try self.recordResult(module, "check_invocation_capabilities", .denied, "cert_verifier_pending_phase_1b_bca");
        return .{ .cert_verifier_pending = "phase_1b_bca_un_park_pending" };
    }

    // ──────────────────────────────────────────────────────────────────
    // Network — placeholders for Brain 2.5
    // host_broadcast_tx, host_fetch_header_range — wallet-engine and
    // headers-verifier respectively.  v0.1 returns policy_denied for
    // both modules so unsigned/unimplemented calls fail loud.
    // ──────────────────────────────────────────────────────────────────

    pub fn hostFetchHeaderRange(self: *Broker, module: Module) BrokerError!void {
        if (module != .headers_verifier) {
            try self.recordResult(module, "host_fetch_header_range", .denied, "headers-verifier-only");
            return error.policy_denied;
        }
        try self.recordResult(module, "host_fetch_header_range", .err, "not-yet-implemented");
        return error.persistence_failed;
    }

    pub fn hostBroadcastTx(self: *Broker, module: Module) BrokerError!void {
        if (module != .wallet_engine) {
            try self.recordResult(module, "host_broadcast_tx", .denied, "wallet-engine-only");
            return error.policy_denied;
        }
        try self.recordResult(module, "host_broadcast_tx", .err, "not-yet-implemented");
        return error.persistence_failed;
    }

    pub fn hostSign(self: *Broker, module: Module) BrokerError!void {
        if (module != .wallet_engine) {
            try self.recordResult(module, "host_sign", .denied, "wallet-engine-only");
            return error.policy_denied;
        }
        try self.recordResult(module, "host_sign", .err, "not-yet-implemented");
        return error.persistence_failed;
    }

    // ──────────────────────────────────────────────────────────────────
    // Audit helpers
    // ──────────────────────────────────────────────────────────────────

    fn recordStart(self: *Broker, module: Module, op: []const u8, detail: []const u8) BrokerError!void {
        // Optional. v0.1 only records the result line — start-line gets
        // noisy with no extra signal.
        _ = self;
        _ = module;
        _ = op;
        _ = detail;
    }

    /// Public surface for the wasmtime host-import callbacks (Brain 2.5)
    /// that need to audit calls without going through one of the typed
    /// `host*` methods — e.g., `host_log` is purely a side-effect on the
    /// log itself, so it bypasses the per-store dispatch.
    pub fn auditRecord(
        self: *Broker,
        module: Module,
        op: []const u8,
        result: audit_log_mod.Result,
        detail: []const u8,
    ) BrokerError!void {
        return self.recordResult(module, op, result, detail);
    }

    fn recordResult(
        self: *Broker,
        module: Module,
        op: []const u8,
        result: audit_log_mod.Result,
        detail: []const u8,
    ) BrokerError!void {
        const module_str = switch (module) {
            .wallet_engine => "wallet-engine",
            .headers_verifier => "headers-verifier",
            .dynamic_handler => "dynamic-handler",
            .script_handler => "script-handler",
        };
        self.audit.record(self.allocator, .{
            .module = module_str,
            .op = op,
            .result = result,
            .detail = detail,
        }) catch return error.audit_failed;
    }
};

```
