---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/job_fsm.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.542605+00:00
---

# cartridges/oddjobz/brain/zig/src/job_fsm.zig

```zig
// D-O4 Job FSM — brain-side Zig port.
//
// Reference:
//   - cartridges/oddjobz/brain/src/state-machines/job-fsm.ts (TS canon — the
//     `JOB_TRANSITIONS` table is the source of truth)
//   - cartridges/oddjobz/brain/tests/vectors/state-machines/job_fsm.json
//     (cross-language parity oracle — see the parity test in
//     `tests/jobs_handler_conformance.zig`)
//   - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4 (transition table prose)
//
// Why this file exists: PR #307 / #308 / #310 landed the typed `jobs.*`
// dispatcher resource shape (find / find_by_id / create / find_calendar
// / find_attention) so both helms can READ + CREATE jobs.  Until this PR
// shipped, every job stayed in `lead` state forever — the FSM only had
// a TS implementation in the extension and no brain-side substrate.  The
// helms are the Semantos Brain's surface, so the FSM has to live on the Semantos Brain side
// to drive operator action through the dispatcher.
//
// Scope: the `JOB_TRANSITIONS` array (fourteen LINEAR rows), the lookup
// helper, and a single `validateTransition` entry point that the
// dispatcher's `jobs.transition` command calls.  This file deliberately
// does NOT carry the K1 `ConsumedCellSet` / `runFailureAtomic` shape
// the TS module carries — those are kernel-gate concerns that only
// matter once cell-DAG bytes flow through this code path.  The brain-
// side store (`jobs_store_fs.zig`) holds a SUBSET of the canonical
// `oddjobz.job.v1` cell payload; idempotency on retry is provided by
// the store's append-only log + the handler's "already in to_state"
// short-circuit, not by a `consumed` set.  When the cell-DAG substrate
// lands in a later phase we'll hoist this module into a kernel-gate
// frame; today the contract is "FSM-table-correct + parity-with-TS".

const std = @import("std");

/// The thirteen canonical Job FSM states.  Mirror of `JOB_FSM_STATES`
/// in cartridges/oddjobz/brain/src/state-machines/job-fsm.ts.  The four
/// lead-nurture states (qualified / visit_pending / visit_scheduled /
/// visited) make every pre-quote gap a discrete, queryable step;
/// `authorized` is the directly-authorised (no-quote, e.g. REA WO)
/// branch parallel to `quoted` — both feed `scheduled`.
pub const JOB_FSM_STATES = [_][]const u8{
    "lead",
    "qualified",
    "visit_pending",
    "visit_scheduled",
    "visited",
    "quoted",
    "authorized",
    "scheduled",
    "in_progress",
    "completed",
    "invoiced",
    "paid",
    "closed",
};

/// Returns true if `s` is one of the canonical thirteen states.
pub fn isFsmState(s: []const u8) bool {
    for (JOB_FSM_STATES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

/// Acceptable signing principals.  Mirror of `SigningPrincipal` in
/// cartridges/oddjobz/brain/src/state-machines/kernel-gate.ts.  The brain-side
/// dispatcher carries this on the inbound `principal_kind` arg of
/// `jobs.transition`; the handler maps the string to this enum before
/// calling `validateTransition`.
pub const PrincipalKind = enum {
    operator,
    service,

    pub fn fromString(s: []const u8) ?PrincipalKind {
        if (std.mem.eql(u8, s, "operator")) return .operator;
        if (std.mem.eql(u8, s, "service")) return .service;
        return null;
    }

    pub fn toString(self: PrincipalKind) []const u8 {
        return switch (self) {
            .operator => "operator",
            .service => "service",
        };
    }
};

/// One row in the §O4 Job FSM transition table.  Mirror of
/// `JobTransitionSpec` in cartridges/oddjobz/brain/src/state-machines/job-fsm.ts.
///
/// Field name `cap_required` is snake_case here; the TS canon uses
/// `capRequired` (camelCase).  Same value semantics — null means an
/// ungated transition (the §O4 "none" rows).
pub const Transition = struct {
    from: []const u8,
    to: []const u8,
    cap_required: ?[]const u8,
    /// Acceptable principal kinds (set semantics — order does not matter).
    /// Today every row has exactly one kind, but we model it as a slice
    /// to mirror the TS canon's `principalKinds: readonly SigningPrincipal[]`
    /// shape.
    principal_kinds: []const PrincipalKind,
};

/// The §O4 critical-path Job FSM transition table — verbatim from
/// cartridges/oddjobz/brain/src/state-machines/job-fsm.ts.  Declaration order =
/// spec row order.  The genesis ∅→lead row is handled by `jobs.create`
/// (no input cell to consume); this table covers the fourteen LINEAR
/// transitions.
pub const JOB_TRANSITIONS = [_]Transition{
    // Lead-nurture front — discrete, queryable, schedulable steps so
    // a lead never falls through the gap untracked.  Mirror of the TS
    // canon's table (declaration order = row order).
    .{
        // ROM accepted in the chat widget.
        .from = "lead",
        .to = "qualified",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        // SD2 incr.2 — ingested work-order / maintenance-order: the WO
        // IS the authorisation (REA/PM-issued, no customer quote owed),
        // so a converged-ingest lead skips straight to authorized.
        // Ungated/operator — a verbatim mirror of qualified→authorized
        // (auth lives in the WO, not a presented cap).
        .from = "lead",
        .to = "authorized",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        // Needs eyes on site before a firm quote.
        .from = "qualified",
        .to = "visit_pending",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        // Skip path — quote straight off the prequalified ROM.
        .from = "qualified",
        .to = "quoted",
        .cap_required = "cap.oddjobz.quote",
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        // Directly-authorised branch — pre-authorised WO (e.g. REA)
        // that IS the authorisation; no customer quote owed.
        // Ungated/operator like the other front edges (auth lives in
        // the WO, not a presented cap).
        .from = "qualified",
        .to = "authorized",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        // Visit time locked with the customer (negotiation rounds are
        // events while in visit_pending; this fires on agreement).
        .from = "visit_pending",
        .to = "visit_scheduled",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        // Been on site; linked Visit cell completed + photos in.
        // Quote now owed — the second gap the agent watches.
        .from = "visit_scheduled",
        .to = "visited",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        // Quote issued off the completed site visit.
        .from = "visited",
        .to = "quoted",
        .cap_required = "cap.oddjobz.quote",
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    // Post-quote execution chain (unchanged from §O4).
    .{
        .from = "quoted",
        .to = "scheduled",
        .cap_required = "cap.oddjobz.dispatch",
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        // Authorised-branch dispatch — exact mirror of
        // quoted→scheduled.  quoted/authorised re-converge here.
        .from = "authorized",
        .to = "scheduled",
        .cap_required = "cap.oddjobz.dispatch",
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        .from = "scheduled",
        .to = "in_progress",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.service},
    },
    .{
        .from = "in_progress",
        .to = "completed",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        .from = "completed",
        .to = "invoiced",
        .cap_required = "cap.oddjobz.invoice",
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        .from = "invoiced",
        .to = "paid",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.service},
    },
    .{
        .from = "paid",
        .to = "closed",
        .cap_required = "cap.oddjobz.close",
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
};

/// Lookup the (from, to) row, or null if the pair isn't in the table.
pub fn findTransition(from: []const u8, to: []const u8) ?Transition {
    for (JOB_TRANSITIONS) |t| {
        if (std.mem.eql(u8, t.from, from) and std.mem.eql(u8, t.to, to)) return t;
    }
    return null;
}

/// Typed validation outcomes.  Maps onto the `{error: <kind>, from, to,
/// cap_required}` JSON body the dispatcher's `jobs.transition` returns.
pub const ValidationError = enum {
    /// Either `from` or `to` is not one of the canonical thirteen states.
    unknown_state,
    /// (from, to) is not a row in the §O4 table.
    not_reachable,
    /// Row requires a cap, but the presented cap is missing or wrong.
    wrong_cap,
    /// The supplied principal kind isn't in the row's allowed set.
    wrong_principal,
    /// Job is already at `to_state` — handler short-circuits to an
    /// "already_in_state" success body (NOT a real error per the
    /// idempotency contract; surfaced here so the handler can branch).
    already_in_state,

    pub fn toString(self: ValidationError) []const u8 {
        return switch (self) {
            .unknown_state => "unknown_state",
            .not_reachable => "not_reachable",
            .wrong_cap => "wrong_cap",
            .wrong_principal => "wrong_principal",
            .already_in_state => "already_in_state",
        };
    }
};

/// Result of `validateTransition`.  Either `.ok` with the resolved
/// transition spec (caller mints the successor state) or `.err` with a
/// typed kind + the offending (from, to) pair.
pub const ValidationResult = union(enum) {
    ok: Transition,
    err: struct {
        kind: ValidationError,
        from: []const u8,
        to: []const u8,
        /// Cap required for the (from, to) row when the row exists.
        /// null when the validation failure was state-level (`unknown_
        /// state` / `not_reachable`) or when the row is ungated.
        cap_required: ?[]const u8,
    },
};

/// Validate a transition request:
///
///   1. `to_state` must be a canonical FSM state.
///   2. `current_state` must be a canonical FSM state.  (When the helm
///      reads `current_state` from the store it should always be — but
///      defence in depth: a hand-edited jobs.jsonl with a non-canonical
///      state should produce a typed error rather than crash.)
///   3. If `current_state == to_state`, return `.already_in_state` so
///      the handler can short-circuit to the idempotent success body.
///   4. Look up the (current_state, to_state) row in JOB_TRANSITIONS;
///      `not_reachable` if absent.
///   5. Verify principal_kind is in the row's `principal_kinds`;
///      `wrong_principal` otherwise.
///   6. Verify cap.  When the row's `cap_required` is non-null, the
///      caller must present that cap (string equality);
///      `wrong_cap` otherwise.  When the row is ungated, ANY cap (or
///      no cap) is accepted.
///
/// This function does NOT write to the store; the handler owns the
/// store-mutation step.  Idempotency on already-applied transitions is
/// handled at the handler layer via the `already_in_state` short-
/// circuit; the `ConsumedCellSet` shape from the TS canon is a
/// kernel-gate concern that only applies once the cell-DAG substrate
/// lands.  See module head for the rationale.
pub fn validateTransition(
    current_state: []const u8,
    to_state: []const u8,
    presented_cap: ?[]const u8,
    principal_kind: PrincipalKind,
) ValidationResult {
    // Step 1+2: state-level validation.
    if (!isFsmState(to_state)) {
        return .{ .err = .{
            .kind = .unknown_state,
            .from = current_state,
            .to = to_state,
            .cap_required = null,
        } };
    }
    if (!isFsmState(current_state)) {
        return .{ .err = .{
            .kind = .unknown_state,
            .from = current_state,
            .to = to_state,
            .cap_required = null,
        } };
    }

    // Step 3: idempotent already-at-to_state.
    if (std.mem.eql(u8, current_state, to_state)) {
        return .{ .err = .{
            .kind = .already_in_state,
            .from = current_state,
            .to = to_state,
            .cap_required = null,
        } };
    }

    // Step 4: row lookup.
    const row = findTransition(current_state, to_state) orelse {
        return .{ .err = .{
            .kind = .not_reachable,
            .from = current_state,
            .to = to_state,
            .cap_required = null,
        } };
    };

    // Step 5: principal kind.
    var principal_ok = false;
    for (row.principal_kinds) |k| {
        if (k == principal_kind) {
            principal_ok = true;
            break;
        }
    }
    if (!principal_ok) {
        return .{ .err = .{
            .kind = .wrong_principal,
            .from = row.from,
            .to = row.to,
            .cap_required = row.cap_required,
        } };
    }

    // Step 6: cap match.  Only meaningful when the row requires one.
    if (row.cap_required) |required| {
        const presented = presented_cap orelse "";
        if (!std.mem.eql(u8, presented, required)) {
            return .{ .err = .{
                .kind = .wrong_cap,
                .from = row.from,
                .to = row.to,
                .cap_required = row.cap_required,
            } };
        }
    }

    return .{ .ok = row };
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure logic; cross-language parity lives in
// tests/jobs_handler_conformance.zig (it loads the canonical
// cartridges/oddjobz/brain/tests/vectors/state-machines/job_fsm.json oracle).
// ─────────────────────────────────────────────────────────────────────

test "isFsmState recognises the thirteen canonical states" {
    try std.testing.expectEqual(@as(usize, 13), JOB_FSM_STATES.len);
    for (JOB_FSM_STATES) |s| try std.testing.expect(isFsmState(s));
    // The four lead-nurture states are present.
    try std.testing.expect(isFsmState("qualified"));
    try std.testing.expect(isFsmState("visit_pending"));
    try std.testing.expect(isFsmState("visit_scheduled"));
    try std.testing.expect(isFsmState("visited"));
    // The directly-authorised branch state.
    try std.testing.expect(isFsmState("authorized"));
    try std.testing.expect(!isFsmState(""));
    try std.testing.expect(!isFsmState("paused"));
    try std.testing.expect(!isFsmState("LEAD"));
}

test "JOB_TRANSITIONS table has fifteen canonical rows incl. lead→authorized + the qualified branch" {
    // SD2 incr.2 added the lead→authorized WO edge at row 1 (after
    // the row-0 lead→qualified ROM-accept edge).
    try std.testing.expectEqual(@as(usize, 15), JOB_TRANSITIONS.len);
    // Row 0 is still the ROM-accept edge lead→qualified (ungated,
    // operator).
    try std.testing.expectEqualStrings("lead", JOB_TRANSITIONS[0].from);
    try std.testing.expectEqualStrings("qualified", JOB_TRANSITIONS[0].to);
    try std.testing.expect(JOB_TRANSITIONS[0].cap_required == null);
    try std.testing.expectEqual(PrincipalKind.operator, JOB_TRANSITIONS[0].principal_kinds[0]);
    // Row 1 is the SD2 incr.2 WO edge lead→authorized (ungated,
    // operator — auth lives in the work order).
    try std.testing.expectEqualStrings("lead", JOB_TRANSITIONS[1].from);
    try std.testing.expectEqualStrings("authorized", JOB_TRANSITIONS[1].to);
    try std.testing.expect(JOB_TRANSITIONS[1].cap_required == null);
    try std.testing.expectEqual(PrincipalKind.operator, JOB_TRANSITIONS[1].principal_kinds[0]);

    // The branch: qualified has TWO out-edges.
    const q_visit = findTransition("qualified", "visit_pending") orelse return error.MissingRow;
    try std.testing.expect(q_visit.cap_required == null);
    const q_quote = findTransition("qualified", "quoted") orelse return error.MissingRow;
    try std.testing.expectEqualStrings("cap.oddjobz.quote", q_quote.cap_required.?);
    // …and a THIRD: the directly-authorised (no-quote) branch.
    const q_auth = findTransition("qualified", "authorized") orelse return error.MissingRow;
    try std.testing.expect(q_auth.cap_required == null);
    try std.testing.expectEqual(PrincipalKind.operator, q_auth.principal_kinds[0]);
    // authorized re-converges with quoted at scheduled (same
    // dispatch cap).
    const a_sched = findTransition("authorized", "scheduled") orelse return error.MissingRow;
    try std.testing.expectEqualStrings("cap.oddjobz.dispatch", a_sched.cap_required.?);
    const q_sched = findTransition("quoted", "scheduled") orelse return error.MissingRow;
    try std.testing.expectEqualStrings("cap.oddjobz.dispatch", q_sched.cap_required.?);

    // The visit chain + the second in-edge to quoted.
    try std.testing.expect(findTransition("visit_pending", "visit_scheduled") != null);
    try std.testing.expect(findTransition("visit_scheduled", "visited") != null);
    const v_quote = findTransition("visited", "quoted") orelse return error.MissingRow;
    try std.testing.expectEqualStrings("cap.oddjobz.quote", v_quote.cap_required.?);

    // Tail unchanged: paid→closed (cap.oddjobz.close, operator).
    const close = findTransition("paid", "closed") orelse return error.MissingRow;
    try std.testing.expectEqualStrings("cap.oddjobz.close", close.cap_required.?);

    // Post-quote ungated service rows still present.
    const sched = findTransition("scheduled", "in_progress") orelse return error.MissingRow;
    try std.testing.expect(sched.cap_required == null);
    try std.testing.expectEqual(PrincipalKind.service, sched.principal_kinds[0]);
    const invoiced = findTransition("invoiced", "paid") orelse return error.MissingRow;
    try std.testing.expect(invoiced.cap_required == null);
    try std.testing.expectEqual(PrincipalKind.service, invoiced.principal_kinds[0]);
}

test "findTransition rejects state-skips, backwards, and the old direct lead→quoted" {
    // The pre-remodel direct edge is GONE — lead must pass through
    // qualified now.
    try std.testing.expect(findTransition("lead", "quoted") == null);
    try std.testing.expect(findTransition("lead", "invoiced") == null);
    try std.testing.expect(findTransition("closed", "lead") == null);
    try std.testing.expect(findTransition("paused", "quoted") == null);
    // No leapfrogging the visit chain.
    try std.testing.expect(findTransition("qualified", "visit_scheduled") == null);
    try std.testing.expect(findTransition("visit_pending", "quoted") == null);
    // SD2 incr.2: `lead → authorized` IS now a valid edge — an
    // ingested work-order/maintenance-order is itself the
    // authorisation (no qualify/quote owed), so it deliberately skips
    // straight to authorized (positive coverage: the row-1 test above
    // + the TS lead-authorized-edge conformance test). The authorised
    // branch still does not let `qualified` leapfrog the
    // authorized/quoted gate straight to scheduled.
    try std.testing.expect(findTransition("qualified", "scheduled") == null);
    // authorized is terminal-of-branch: no backward edge to quoted.
    try std.testing.expect(findTransition("authorized", "quoted") == null);
}

test "validateTransition: happy path" {
    // qualified → quoted is the skip-path edge (post twelve-state
    // remodel; the direct lead → quoted edge was removed).
    const r = validateTransition("qualified", "quoted", "cap.oddjobz.quote", .operator);
    switch (r) {
        .ok => |row| {
            try std.testing.expectEqualStrings("qualified", row.from);
            try std.testing.expectEqualStrings("quoted", row.to);
        },
        .err => return error.UnexpectedErr,
    }
}

test "validateTransition: ungated row accepts no cap" {
    // scheduled→in_progress requires no cap.
    const r = validateTransition("scheduled", "in_progress", null, .service);
    switch (r) {
        .ok => {},
        .err => return error.UnexpectedErr,
    }
    // Even when caller presents a cap, ungated rows accept it.
    const r2 = validateTransition("scheduled", "in_progress", "cap.oddjobz.quote", .service);
    switch (r2) {
        .ok => {},
        .err => return error.UnexpectedErr,
    }
}

test "validateTransition: wrong_cap" {
    const r = validateTransition("qualified", "quoted", "cap.oddjobz.invoice", .operator);
    switch (r) {
        .ok => return error.UnexpectedOk,
        .err => |e| try std.testing.expectEqual(ValidationError.wrong_cap, e.kind),
    }
}

test "validateTransition: missing cap on a gated row → wrong_cap" {
    const r = validateTransition("qualified", "quoted", null, .operator);
    switch (r) {
        .ok => return error.UnexpectedOk,
        .err => |e| try std.testing.expectEqual(ValidationError.wrong_cap, e.kind),
    }
}

test "validateTransition: wrong_principal" {
    // qualified→quoted is operator-only.  A service principal must reject.
    const r = validateTransition("qualified", "quoted", "cap.oddjobz.quote", .service);
    switch (r) {
        .ok => return error.UnexpectedOk,
        .err => |e| try std.testing.expectEqual(ValidationError.wrong_principal, e.kind),
    }
}

test "validateTransition: not_reachable on direct lead→invoiced jump" {
    const r = validateTransition("lead", "invoiced", "cap.oddjobz.invoice", .operator);
    switch (r) {
        .ok => return error.UnexpectedOk,
        .err => |e| try std.testing.expectEqual(ValidationError.not_reachable, e.kind),
    }
}

test "validateTransition: unknown_state when to_state isn't canonical" {
    const r = validateTransition("lead", "PAUSED", "cap.oddjobz.quote", .operator);
    switch (r) {
        .ok => return error.UnexpectedOk,
        .err => |e| try std.testing.expectEqual(ValidationError.unknown_state, e.kind),
    }
}

test "validateTransition: already_in_state when current == to" {
    const r = validateTransition("scheduled", "scheduled", null, .service);
    switch (r) {
        .ok => return error.UnexpectedOk,
        .err => |e| try std.testing.expectEqual(ValidationError.already_in_state, e.kind),
    }
}

```
