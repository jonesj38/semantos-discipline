---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/dispatcher.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.255838+00:00
---

# runtime/semantos-brain/src/dispatcher.zig

```zig
// Phase D-W1 / Phase 0 — brain dispatcher core.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §2, §4, §7.
//
// This file is the architectural seam brain has been missing: a single
// auth-gated, capability-checked, audit-logged entry point through which
// every transport (in-process REPL today; Unix socket, HTTP, SignedBundle
// mesh in later phases) calls every resource handler.  The dispatcher
// itself is small (~300 lines) by design — most of the work lives in the
// resource handlers it routes to and the audit log it pairs around them.
//
// Phase 0 scope (this PR):
//   • Core types: `Dispatcher`, `DispatchContext`, `AuthContext`,
//     `CapabilitySet`, `ResourceHandler`, `Result`.
//   • Capability check + dispatch fn with begin/end audit pairing.
//   • In-process transport (driven from repl.zig in this branch).
//
// Phase 1+ (NOT in this PR):
//   • Bearer-token resource (currently lives in bearer_tokens.zig);
//     migration replaces direct callers with dispatcher.dispatch.
//   • `cert: IdentityCert` AuthContext variant fully wired (post-D-O5p);
//     today it's a placeholder enum value.
//   • `llm.complete` resource handler.
//   • Unix-socket and HTTP transport adapters.
//
// Design notes baked into the shape below:
//
//   • Auth precedes capability check precedes audit-begin precedes
//     handler call precedes audit-end.  Audit-end always fires, even on
//     unknown_resource / unknown_command / capability_denied / handler
//     error — the operator should be able to see attempted dispatches
//     to non-existent resources just as clearly as accepted ones.
//
//   • Deny-by-default: a handler that fails to declare a capability for
//     one of its commands returns `error.capability_not_declared` and
//     dispatches fail loud.  Missing declarations are a developer bug,
//     not a permissive runtime fallback.
//
//   • Resources are opaque to the dispatcher.  `state: ?*anyopaque` lets
//     a handler carry its own context (bearer store, REPL session, LLM
//     adapter, etc.) without the dispatcher growing per-resource shape.
//
//   • Result is a JSON-encoded byte slice.  In-process callers may treat
//     it as opaque text; wire transports embed it directly into the
//     `result` field of the response envelope (see wire.zig).

const std = @import("std");
const audit_log = @import("audit_log");
const verb_schema = @import("verb_schema"); // C4 PR-R2 — resource verb self-description

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

/// Errors the dispatcher itself produces.  Handler-internal errors flow
/// through unchanged via `anyerror`.
pub const DispatchError = error{
    /// Resource name is not registered.
    unknown_resource,
    /// Resource exists but the named command is not implemented by it.
    unknown_command,
    /// The handler exists for this command but did not declare a capability
    /// requirement.  Deny-by-default — fail loud rather than silently allow.
    capability_not_declared,
    /// Capability check failed for the caller's auth context.
    capability_denied,
    /// Resource handler registry is full or the registration table OOMed.
    out_of_memory,
    /// Resource registration would have shadowed an already-registered name.
    duplicate_resource,
    /// D-W2 Phase 4 — the resource is registered but currently
    /// quarantined (e.g. its publishing signer was revoked).  Wire
    /// transports map this to `503 Service Unavailable` with body
    /// `{"kind":"handler_quarantined", ...}`.  See
    /// `extension_quarantine.zig` for the state machine.
    handler_quarantined,
};

/// Errors a `cap_for_cmd_fn` may return.  Two distinct failure modes so
/// the dispatcher can audit the right cause.
pub const CapDeclError = error{
    /// The command name is unknown to this resource.  Maps to the
    /// dispatcher's `unknown_command` error.
    unknown_command,
    /// The command exists in the handler's `handle_fn` switch but the
    /// handler forgot to declare a capability for it.  Maps to the
    /// dispatcher's `capability_not_declared` error — deny-by-default.
    capability_not_declared,
};

// ─────────────────────────────────────────────────────────────────────
// Capabilities
// ─────────────────────────────────────────────────────────────────────

/// Per-command capability requirement.  Returned by `ResourceHandler.cap_for_cmd_fn`.
pub const CapDecl = union(enum) {
    /// No capability required — anyone whose auth context made it through
    /// the transport may invoke this command (e.g. validate, ping).
    none,
    /// Specific dotted-namespace capability required.  Matched against the
    /// caller's `CapabilitySet` per `impliesCapability` semantics.
    require: []const u8,
};

/// A flat set of dotted-namespace capability strings ("cap.brain.admin",
/// "cap.oddjobz.public_chat.serve", …) with implicit hierarchy and
/// wildcard matching.  Pure-function check; never allocates.
///
/// Entries are borrowed — the caller (transport adapter constructing the
/// auth context) owns the underlying memory.  CapabilitySet is small,
/// stack-friendly, and trivially copyable.
pub const CapabilitySet = struct {
    entries: []const []const u8,

    pub fn empty() CapabilitySet {
        return .{ .entries = &.{} };
    }

    pub fn fromList(list: []const []const u8) CapabilitySet {
        return .{ .entries = list };
    }

    /// True iff some held capability in this set implies `required`
    /// (per `impliesCapability`).  Deny-by-default — empty set implies
    /// nothing.
    pub fn contains(self: CapabilitySet, required: []const u8) bool {
        for (self.entries) |held| {
            if (impliesCapability(held, required)) return true;
        }
        return false;
    }
};

/// Decide whether a held capability `held` grants the required capability
/// `required`.  Three cases, in order of precedence:
///
///   1. Exact match: `cap.X == cap.X`.
///   2. Wildcard: held ends in `.*`.  Strips the trailing `.*`; if the
///      remaining prefix is followed by a `.` segment in `required`,
///      grant.  Example: `cap.echo.*` grants `cap.echo.say` and
///      `cap.echo.foo.bar` (any extension at any depth).  Does NOT grant
///      `cap.echoX.say` (the `.` boundary is enforced).
///   3. Hierarchy: held is a strict prefix of required terminated by `.`
///      Example: `cap.brain.admin` grants `cap.brain.admin.bearer.issue`
///      because admin is the operator-root cap and implies all sub-scopes.
///      Does NOT grant `cap.brain.adminx` (boundary check).
///
/// Pure function — exposed for testing.
pub fn impliesCapability(held: []const u8, required: []const u8) bool {
    if (std.mem.eql(u8, held, required)) return true;

    // Wildcard: held = "cap.X.Y.*"
    if (std.mem.endsWith(u8, held, ".*")) {
        const prefix = held[0 .. held.len - 2];
        if (prefix.len == 0) return false; // a bare ".*" is meaningless
        if (required.len > prefix.len and
            std.mem.startsWith(u8, required, prefix) and
            required[prefix.len] == '.') return true;
        return false;
    }

    // Hierarchy: held is a strict prefix of required, with `.` at the boundary.
    if (required.len > held.len and
        std.mem.startsWith(u8, required, held) and
        required[held.len] == '.') return true;

    return false;
}

// ─────────────────────────────────────────────────────────────────────
// Auth context
// ─────────────────────────────────────────────────────────────────────

/// Identifies who is making this dispatch call.  Constructed by the
/// transport (in-process shell, Unix socket, HTTP, mesh peer) from
/// whatever per-transport auth signal it has — peer creds, bearer token,
/// identity cert, anonymous-with-rate-limit.  The dispatcher applies a
/// uniform policy regardless of which variant is set.
pub const AuthContext = union(enum) {
    /// In-process call from the Semantos Brain binary itself.  This covers the
    /// interactive REPL on the operator's terminal and the embedded
    /// fallback path during first-boot.  Treated as root cap scope —
    /// capability checks always pass.
    in_process_root,

    /// Local Unix-socket CLI client.  The transport verifies peer Unix
    /// uid against the daemon's own uid before constructing this; the
    /// dispatcher trusts that and grants root cap scope.
    /// Phase 1 wires the actual socket.
    local_uid: u32,

    /// Caller authenticated by a bearer token.  Capabilities derive from
    /// the token's stored scope (Phase 1: bearer_tokens resource grows a
    /// `caps` field).  Today this is just an opaque reference for the
    /// dispatcher; cap evaluation uses `DispatchContext.capabilities`.
    bearer: BearerRef,

    /// Caller authenticated by an identity cert chain (post-D-O5p).
    /// Phase 1 wires the BRC-52 cert chain → cap set derivation.  Until
    /// then this variant exists as a placeholder so transports can stub
    /// it out without changing the AuthContext shape.
    /// TODO(D-O5p): replace with `IdentityCert` per BRAIN-DISPATCHER-
    /// UNIFICATION.md §4.
    cert: CertRef,

    /// Unauthenticated caller (visitor on a public chat endpoint, etc.).
    /// Cap scope comes from per-site config's `anonymous_caps` declaration.
    anonymous: AnonymousCtx,
};

/// Reference to a bearer token already validated by the transport.  The
/// dispatcher does not look up the token itself — that's the bearer
/// resource's job once it migrates in Phase 1.  `fingerprint_hex` is
/// stored as a fixed-size array so the auth context is copyable without
/// allocation.
pub const BearerRef = struct {
    fingerprint_hex: [64]u8,
    /// Operator-supplied label.  Borrowed; lifetime is the request.
    label: []const u8 = "",
};

/// Phase 1 placeholder for cert-based auth.  The full shape (cert chain,
/// scope tag, derivation context) lands in D-O5p.
/// TODO(D-O5p): this becomes the BRC-52 cert chain reference.
pub const CertRef = struct {
    placeholder: u8 = 0,
};

/// Anonymous caller — typically a website visitor hitting a public
/// chat or download endpoint.  Per-site config drives what (if any)
/// caps anonymous gets.
pub const AnonymousCtx = struct {
    /// Origin URL or site domain — purely informational.  Borrowed.
    site_origin: []const u8 = "",
};

/// Per-call metadata the transport supplies and the dispatcher echoes
/// into audit entries.  All borrowed; lifetime is the dispatch call.
pub const TransportMeta = struct {
    /// Wire-level correlation id.  Free-form; transports SHOULD make this
    /// unique per request so audit pairs are traceable.  Empty for
    /// synthetic in-process calls.
    request_id: []const u8 = "",
    /// Unix-seconds the request was received.  0 = use audit log's clock.
    timestamp_unix: i64 = 0,
    /// Free-form transport label ("in_process", "unix_socket", "http",
    /// "wss", "signed_bundle").  Used in audit detail.
    transport_label: []const u8 = "in_process",
};

/// The dispatch envelope the transport hands to `Dispatcher.dispatch`.
pub const DispatchContext = struct {
    auth: AuthContext,
    capabilities: CapabilitySet,
    meta: TransportMeta,
};

/// True if the auth context is granted root capability scope.  Used by
/// `dispatch` to short-circuit the per-cap check.
fn isRootScope(auth: AuthContext) bool {
    return switch (auth) {
        .in_process_root, .local_uid => true,
        .bearer, .cert, .anonymous => false,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Result
// ─────────────────────────────────────────────────────────────────────

/// What a successful dispatch returns.  Carries an opaque payload (the
/// resource handler decides whether it's JSON, plain text, or empty)
/// plus the optional allocator that owns it.  The wire transport reads
/// `payload` verbatim into the `result` field of the response envelope;
/// in-process transports may treat it as text.
pub const Result = struct {
    /// Payload bytes.  Empty for void-typed commands (e.g. `repl.exit`).
    payload: []u8 = &.{},
    /// If set, owns `payload`; freed by `deinit`.  null = borrowed/static.
    allocator: ?std.mem.Allocator = null,
    /// Side-channel hint for loop-driven transports (in-process REPL).
    /// Wire transports ignore it.  Set by `repl.exit` and equivalents.
    quit: bool = false,

    pub fn empty() Result {
        return .{};
    }

    pub fn ownedPayload(allocator: std.mem.Allocator, payload: []u8) Result {
        return .{ .payload = payload, .allocator = allocator };
    }

    pub fn deinit(self: *Result) void {
        if (self.allocator) |a| {
            if (self.payload.len > 0) a.free(self.payload);
            self.payload = &.{};
            self.allocator = null;
        }
    }
};

// ─────────────────────────────────────────────────────────────────────
// Resource handler
// ─────────────────────────────────────────────────────────────────────

/// One registered resource (`bearer_tokens`, `sites`, `repl`, …).  The
/// dispatcher routes `(resource_name, command_name) → handler` and calls
/// `cap_for_cmd_fn` followed by `handle_fn`.
///
/// All function pointers receive the handler's opaque `state` so a
/// resource can carry its own context (e.g. a *Session, a *TokenStore)
/// without forcing the dispatcher to know about it.  Handlers that need
/// no state set `state = null`.
pub const ResourceHandler = struct {
    name: []const u8,
    state: ?*anyopaque,

    /// Returns the capability requirement for `cmd_name`.  Three
    /// outcomes per `CapDeclError` and `CapDecl`:
    ///
    ///   - `error.unknown_command` — the command doesn't exist on this
    ///     resource.  Dispatcher returns `unknown_command`.
    ///   - `error.capability_not_declared` — the command exists in
    ///     `handle_fn` but the cap-table is missing it.  Dispatcher
    ///     returns `capability_not_declared` (deny-by-default).
    ///   - `CapDecl.none` — no cap required (validate, ping, …).
    ///   - `CapDecl.require: cap_name` — caller's CapabilitySet must
    ///     `contains(cap_name)`.
    cap_for_cmd_fn: *const fn (state: ?*anyopaque, cmd_name: []const u8) CapDeclError!CapDecl,

    /// Executes the command.  Called only after capability check passes.
    /// Returned `Result` is the dispatcher's success value; an `anyerror`
    /// return is logged as `result=err` in the audit pair.
    handle_fn: *const fn (
        state: ?*anyopaque,
        ctx: *const DispatchContext,
        cmd_name: []const u8,
        args_json: []const u8,
        allocator: std.mem.Allocator,
    ) anyerror!Result,

    /// D-W1 Phase 2 / BRAIN-DISPATCHER-UNIFICATION.md §10 — high-frequency
    /// reads can opt out of the audit pair to keep the audit log
    /// useful (every dispatch emits begin + complete, which floods
    /// the log under sustained `headers.byHeight` traffic from peer
    /// SPV clients).  When `false`, the dispatcher consults
    /// `is_read_fn` per command; if `is_read_fn` says "this is a
    /// read", the audit pair is suppressed AND a single `phase=skip
    /// kind=read_no_audit` line is emitted instead.  Mutating
    /// commands ALWAYS audit, regardless of this flag — failures of
    /// classifier honesty fail open to "audit anyway".
    ///
    /// Threat-model trade-off: skipping audit for high-volume reads
    /// is acceptable because the transport layer rate-limits the
    /// caller (per-connection token bucket on the HTTP transport
    /// once Phase 3 lands; per-uid for the Unix socket today).  An
    /// attacker who somehow bypasses the rate limit can still flood
    /// the read endpoint, but they can't poison the audit trail by
    /// burying mutations under a torrent of reads.
    ///
    /// Defaults to `true` — opt-in only, so existing handlers
    /// continue to emit the full audit pair.
    audit_reads: bool = true,

    /// Optional read classifier — only consulted when `audit_reads ==
    /// false`.  Returns `true` for read-typed commands; `false` for
    /// mutating commands.  When null, all commands are treated as
    /// mutating (the dispatcher fails closed back to "audit always",
    /// which is the safe direction).
    is_read_fn: ?*const fn (cmd_name: []const u8) bool = null,

    /// C4 PR-R2 — optional verb self-description for the generic REPL path
    /// (`<resource> <verb> [args]`). When set, returns this resource's verbs +
    /// each verb's arg schema so the REPL can parse args into the dispatch
    /// envelope + derive help, with no per-cartridge verb code in the brain.
    /// null ⇒ the resource isn't generic-REPL-driveable (the legacy hardcoded
    /// REPL branches still serve it).
    verbs_fn: ?*const fn (state: ?*anyopaque) []const verb_schema.VerbSpec = null,

    /// Convenience wrapper around `cap_for_cmd_fn`.
    pub fn capForCmd(self: ResourceHandler, cmd_name: []const u8) CapDeclError!CapDecl {
        return self.cap_for_cmd_fn(self.state, cmd_name);
    }

    /// C4 PR-R2 — the resource's verb schema, or empty if it doesn't self-describe.
    pub fn verbs(self: ResourceHandler) []const verb_schema.VerbSpec {
        const vf = self.verbs_fn orelse return &.{};
        return vf(self.state);
    }

    /// Convenience wrapper around `handle_fn`.
    pub fn invoke(
        self: ResourceHandler,
        ctx: *const DispatchContext,
        cmd_name: []const u8,
        args_json: []const u8,
        allocator: std.mem.Allocator,
    ) anyerror!Result {
        return self.handle_fn(self.state, ctx, cmd_name, args_json, allocator);
    }
};

// ─────────────────────────────────────────────────────────────────────
// Dispatcher
// ─────────────────────────────────────────────────────────────────────

/// The single seam every transport calls.  Owns the resource registry
/// + holds a borrowed reference to the Semantos Brain-shared audit log.  Heap-
/// allocated by callers so its address is stable across moves (handlers
/// frequently keep a `*Dispatcher` to call back into).
pub const Dispatcher = struct {
    allocator: std.mem.Allocator,
    audit: *audit_log.AuditLog,
    handlers: std.StringHashMap(ResourceHandler),
    /// D-W2 Phase 4 — parallel set of resource names whose handlers
    /// are currently quarantined.  Dispatch consults this before
    /// invoking `handle_fn`; if the resource is in the set the
    /// dispatcher returns `error.handler_quarantined` and audit-logs
    /// with `kind=quarantined`.  The set is keyed by the same string
    /// the handler is registered under (extension_name, in the
    /// extension flow); operators/CLIs flip the flag via
    /// `markQuarantined` / `unmarkQuarantined`.
    ///
    /// Why a parallel set rather than a field on ResourceHandler:
    /// keeps the handler vtable small + keeps the quarantine state
    /// cleanly separable for callers that consult it without going
    /// through dispatch (the CLI, for example).  Per ambiguity (a)
    /// in the Phase 4 brief.
    quarantined_handlers: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, audit: *audit_log.AuditLog) Dispatcher {
        return .{
            .allocator = allocator,
            .audit = audit,
            .handlers = std.StringHashMap(ResourceHandler).init(allocator),
            .quarantined_handlers = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Dispatcher) void {
        // Free the dup'd keys we own in the quarantined-handlers set.
        var it = self.quarantined_handlers.keyIterator();
        while (it.next()) |k| self.allocator.free(k.*);
        self.quarantined_handlers.deinit();
        self.handlers.deinit();
    }

    /// Register a resource handler.  Returns `error.duplicate_resource`
    /// if `handler.name` is already registered — fail loud so a config
    /// or boot-order bug doesn't silently shadow a resource.
    ///
    /// The handler's `name` field is borrowed; the caller MUST keep it
    /// alive for the dispatcher's lifetime.
    pub fn register(self: *Dispatcher, handler: ResourceHandler) !void {
        const gop = try self.handlers.getOrPut(handler.name);
        if (gop.found_existing) {
            return DispatchError.duplicate_resource;
        }
        gop.value_ptr.* = handler;
    }

    /// D-W2 Phase 4 — mark the resource named `resource_name` as
    /// quarantined.  Idempotent: marking an already-quarantined name
    /// is a no-op.  The resource does NOT have to be currently
    /// registered (the quarantine flag persists across registration
    /// shapes; e.g. a brain that boots with a quarantined extension
    /// in its index marks the name BEFORE the apply path tries to
    /// register, so dispatch returns `handler_quarantined` even if
    /// the bundle's metadata-only registration succeeded).
    ///
    /// Returns `error.OutOfMemory` if the underlying hashmap insert
    /// fails — caller decides whether to surface as
    /// `QuarantineError.out_of_memory` or propagate.
    pub fn markQuarantined(self: *Dispatcher, resource_name: []const u8) !void {
        if (self.quarantined_handlers.contains(resource_name)) return;
        const key = try self.allocator.dupe(u8, resource_name);
        errdefer self.allocator.free(key);
        try self.quarantined_handlers.put(key, {});
    }

    /// D-W2 Phase 4 — unmark a previously-quarantined resource.
    /// Idempotent: unmarking a name that wasn't in the set is a
    /// no-op.  Used by the operator-driven `evaluate` re-enable
    /// path + the hard-remove path (which also clears the flag
    /// before deleting the bundle).
    pub fn unmarkQuarantined(self: *Dispatcher, resource_name: []const u8) void {
        if (self.quarantined_handlers.fetchRemove(resource_name)) |kv| {
            self.allocator.free(kv.key);
        }
    }

    /// D-W2 Phase 4 — read-only test for the quarantine flag.  Pure
    /// hashmap lookup; safe to call on the hot path.
    pub fn isQuarantined(self: *const Dispatcher, resource_name: []const u8) bool {
        return self.quarantined_handlers.contains(resource_name);
    }

    /// The single dispatch entry point.  Auth → capability → audit-begin
    /// → handler → audit-end.  Both audit entries fire even on failure
    /// (unknown resource, unknown command, capability denial, handler
    /// error) so the audit pair invariant holds for every dispatch call.
    ///
    /// Phase 2 — `audit_reads = false` opt-out: when the registered
    /// handler turned the flag off AND the handler classifies `cmd` as
    /// a read, the begin/complete pair is replaced by a single
    /// `phase=skip` line.  Mutating commands ALWAYS get the full pair;
    /// errors (unknown_resource, capability_denied, handler errors)
    /// also bypass the opt-out — surfaces still need to be visible.
    /// C4 PR-R2 — look up a registered resource handler by name (for the
    /// generic REPL path's verb self-description). Returns the handler by value
    /// (it's a small vtable struct); null if no such resource is registered.
    pub fn findHandler(self: *Dispatcher, resource: []const u8) ?ResourceHandler {
        return self.handlers.get(resource);
    }

    pub fn dispatch(
        self: *Dispatcher,
        ctx: *const DispatchContext,
        resource: []const u8,
        cmd: []const u8,
        args_json: []const u8,
    ) !Result {
        // Resource lookup — produced first so we know whether the
        // opt-out applies before we emit the begin entry.
        const handler = self.handlers.get(resource) orelse {
            // Unknown resource — emit start+end so the operator sees
            // unsuccessful attempts in the audit log even when the
            // resource doesn't exist yet.
            try self.recordAudit(ctx, resource, cmd, .ok, "phase=start");
            try self.recordAudit(ctx, resource, cmd, .denied, "phase=end kind=unknown_resource");
            return DispatchError.unknown_resource;
        };

        // D-W2 Phase 4 — quarantine gate.  Resource is registered
        // but quarantined: dispatch fails closed with a typed error
        // and audit-logs the attempt.  Quarantine ALWAYS audits
        // (mutating-vs-read opt-out doesn't apply — every quarantine
        // hit is a security-relevant event the operator wants to
        // see).  The audit pair invariant holds: start + end.
        if (self.quarantined_handlers.contains(resource)) {
            try self.recordAudit(ctx, resource, cmd, .ok, "phase=start");
            try self.recordAudit(ctx, resource, cmd, .denied, "phase=end kind=quarantined");
            return DispatchError.handler_quarantined;
        }

        const opt_out_read = handler.audit_reads == false and
            handler.is_read_fn != null and
            handler.is_read_fn.?(cmd);

        // Audit-begin fires unconditionally for mutating commands;
        // suppressed for opt-out reads (we'll emit a single `skip`
        // line at the end if the dispatch succeeds).
        if (!opt_out_read) {
            try self.recordAudit(ctx, resource, cmd, .ok, "phase=start");
        }

        // Capability declaration lookup.
        const cap_decl = handler.capForCmd(cmd) catch |err| {
            const detail = switch (err) {
                error.unknown_command => "phase=end kind=unknown_command",
                error.capability_not_declared => "phase=end kind=capability_not_declared",
            };
            // Failures always audit — opt-out applies only to the
            // happy path on read commands.  Emit start if we
            // suppressed it earlier so the pair invariant holds.
            if (opt_out_read) {
                try self.recordAudit(ctx, resource, cmd, .ok, "phase=start");
            }
            try self.recordAudit(ctx, resource, cmd, .denied, detail);
            return switch (err) {
                error.unknown_command => DispatchError.unknown_command,
                error.capability_not_declared => DispatchError.capability_not_declared,
            };
        };

        // Capability check.  Root scopes bypass the check entirely; non-
        // root scopes must hold (or have an implication of) the declared cap.
        const allowed = isRootScope(ctx.auth) or switch (cap_decl) {
            .none => true,
            .require => |req| ctx.capabilities.contains(req),
        };
        if (!allowed) {
            if (opt_out_read) {
                try self.recordAudit(ctx, resource, cmd, .ok, "phase=start");
            }
            try self.recordAudit(ctx, resource, cmd, .denied, "phase=end kind=capability_denied");
            return DispatchError.capability_denied;
        }

        // Handler invocation.  Errors land in audit-end with err result.
        const result = handler.invoke(ctx, cmd, args_json, self.allocator) catch |err| {
            // We can't allocate format-strings here without complicating the
            // error path; emit `phase=end kind=handler_err err=<name>` via a
            // small fixed buffer.  16-bit error name limit is plenty.
            var buf: [128]u8 = undefined;
            const detail = std.fmt.bufPrint(&buf, "phase=end kind=handler_err err={s}", .{@errorName(err)}) catch "phase=end kind=handler_err";
            if (opt_out_read) {
                try self.recordAudit(ctx, resource, cmd, .ok, "phase=start");
            }
            try self.recordAudit(ctx, resource, cmd, .err, detail);
            return err;
        };
        if (opt_out_read) {
            try self.recordAudit(ctx, resource, cmd, .ok, "phase=skip kind=read_no_audit");
        } else {
            try self.recordAudit(ctx, resource, cmd, .ok, "phase=end");
        }
        return result;
    }

    /// Append one audit entry tagged with the dispatch resource + cmd.
    /// `module` is fixed to `dispatcher` so audit log readers can grep
    /// for dispatcher entries specifically; `op` is `<resource>.<cmd>`;
    /// `detail` carries the phase + optional kind tag.
    fn recordAudit(
        self: *Dispatcher,
        ctx: *const DispatchContext,
        resource: []const u8,
        cmd: []const u8,
        result: audit_log.Result,
        detail: []const u8,
    ) !void {
        // op = "<resource>.<cmd>" — stack-bounded for typical lengths.
        var op_buf: [256]u8 = undefined;
        const op = std.fmt.bufPrint(&op_buf, "{s}.{s}", .{ resource, cmd }) catch op_buf[0..0];

        // detail = "<base> req_id=<id> transport=<label>"
        var detail_buf: [512]u8 = undefined;
        const augmented = std.fmt.bufPrint(
            &detail_buf,
            "{s} req_id={s} transport={s}",
            .{ detail, ctx.meta.request_id, ctx.meta.transport_label },
        ) catch detail;

        self.audit.record(self.allocator, .{
            .module = "dispatcher",
            .op = op,
            .result = result,
            .detail = augmented,
        }) catch |err| switch (err) {
            error.closed => {
                // Audit log not open yet (e.g. very-early boot path or a test
                // fixture that didn't open the log).  Dispatch SHOULD still
                // succeed — the seam exists for configuration, not for
                // crash-on-missing-side-channel.  Swallow.
            },
            else => return err,
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// Tests — pure logic; full conformance lives in
// tests/dispatcher_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "impliesCapability: exact match" {
    try std.testing.expect(impliesCapability("cap.echo.say", "cap.echo.say"));
    try std.testing.expect(!impliesCapability("cap.echo.say", "cap.echo.delete"));
}

test "impliesCapability: hierarchy" {
    try std.testing.expect(impliesCapability("cap.brain.admin", "cap.brain.admin.bearer.issue"));
    try std.testing.expect(impliesCapability("cap.brain.admin", "cap.brain.admin.x"));
    // boundary check: "cap.brain.admin" must NOT match "cap.brain.adminx"
    try std.testing.expect(!impliesCapability("cap.brain.admin", "cap.brain.adminx"));
}

test "impliesCapability: wildcard" {
    try std.testing.expect(impliesCapability("cap.echo.*", "cap.echo.say"));
    try std.testing.expect(impliesCapability("cap.echo.*", "cap.echo.foo.bar"));
    try std.testing.expect(!impliesCapability("cap.echo.*", "cap.echoX.say"));
    try std.testing.expect(!impliesCapability("cap.echo.*", "cap.echo")); // can't match the bare prefix
}

test "CapabilitySet: contains uses implication" {
    const caps = [_][]const u8{ "cap.echo.say", "cap.brain.admin" };
    const set = CapabilitySet.fromList(&caps);
    try std.testing.expect(set.contains("cap.echo.say"));
    try std.testing.expect(set.contains("cap.brain.admin.bearer.issue"));
    try std.testing.expect(!set.contains("cap.echo.delete"));
    try std.testing.expect(!CapabilitySet.empty().contains("cap.x"));
}

// ─────────────────────────────────────────────────────────────────────
// D-W2 Phase 4 — quarantine flag inline tests.  Full dispatch-time
// quarantine behaviour is in tests/dispatcher_conformance.zig +
// tests/extension_quarantine_e2e_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "markQuarantined / unmarkQuarantined are idempotent" {
    var audit = audit_log.AuditLog.init();
    defer audit.close();
    var disp = Dispatcher.init(std.testing.allocator, &audit);
    defer disp.deinit();

    try std.testing.expect(!disp.isQuarantined("acme.foo"));
    try disp.markQuarantined("acme.foo");
    try std.testing.expect(disp.isQuarantined("acme.foo"));
    // Idempotent re-mark: same name twice doesn't double-allocate.
    try disp.markQuarantined("acme.foo");
    try std.testing.expect(disp.isQuarantined("acme.foo"));

    disp.unmarkQuarantined("acme.foo");
    try std.testing.expect(!disp.isQuarantined("acme.foo"));
    // Idempotent unmark on a name not in the set is a no-op.
    disp.unmarkQuarantined("acme.foo");
    disp.unmarkQuarantined("never-set");
    try std.testing.expect(!disp.isQuarantined("acme.foo"));
}

test "dispatch on a quarantined resource returns handler_quarantined" {
    var audit = audit_log.AuditLog.init();
    defer audit.close();
    var disp = Dispatcher.init(std.testing.allocator, &audit);
    defer disp.deinit();

    // Register a tiny stub handler under "acme.foo".
    var stub = StubHandlerState{};
    try disp.register(.{
        .name = "acme.foo",
        .state = &stub,
        .cap_for_cmd_fn = stubCapForCmd,
        .handle_fn = stubHandle,
    });

    const ctx = DispatchContext{
        .auth = .in_process_root,
        .capabilities = CapabilitySet.empty(),
        .meta = .{ .request_id = "t1" },
    };

    // Pre-quarantine: dispatch succeeds (root scope bypasses caps).
    var ok_result = try disp.dispatch(&ctx, "acme.foo", "ping", "{}");
    ok_result.deinit();

    // Post-quarantine: dispatch returns the typed error.
    try disp.markQuarantined("acme.foo");
    try std.testing.expectError(DispatchError.handler_quarantined, disp.dispatch(&ctx, "acme.foo", "ping", "{}"));

    // Unmark restores normal dispatch.
    disp.unmarkQuarantined("acme.foo");
    var ok_again = try disp.dispatch(&ctx, "acme.foo", "ping", "{}");
    ok_again.deinit();
}

const StubHandlerState = struct { call_count: u32 = 0 };

fn stubCapForCmd(state: ?*anyopaque, cmd_name: []const u8) CapDeclError!CapDecl {
    _ = state;
    if (std.mem.eql(u8, cmd_name, "ping")) return .none;
    return error.unknown_command;
}

fn stubHandle(
    state: ?*anyopaque,
    ctx: *const DispatchContext,
    cmd_name: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!Result {
    _ = ctx;
    _ = args_json;
    _ = allocator;
    if (std.mem.eql(u8, cmd_name, "ping")) {
        if (state) |s| {
            const stub: *StubHandlerState = @ptrCast(@alignCast(s));
            stub.call_count += 1;
        }
        return Result.empty();
    }
    return error.unknown_command;
}

```
