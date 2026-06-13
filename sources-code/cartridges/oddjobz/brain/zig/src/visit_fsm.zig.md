---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/visit_fsm.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.544886+00:00
---

# cartridges/oddjobz/brain/zig/src/visit_fsm.zig

```zig
// D-O4.followup-2 Visit FSM — brain-side Zig port.
//
// Reference:
//   - cartridges/oddjobz/brain/src/state-machines/visit-fsm.ts (TS canon — the
//     `VISIT_TRANSITIONS` table is the source of truth)
//   - cartridges/oddjobz/brain/tests/vectors/state-machines/visit_fsm.json
//     (cross-language parity oracle — see the parity test in
//     `tests/visits_handler_conformance.zig`)
//   - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4 (Visit FSM transition
//     table — the `scheduled → in_progress → completed` mirror of the
//     Job FSM with the additional `cancelled` exit row)
//
// Why this file exists: PR #311 landed the Semantos Brain-side Zig port of the Job
// FSM (job_fsm.zig + jobs.transition).  This PR mirrors that work for
// Visits — the "site event" cells linked to a parent Job that the
// helms ship the operator action surface for.  Until this PR shipped,
// every Visit stayed in `scheduled` state forever — the FSM only had a
// TS implementation in the extension and no brain-side substrate.  The
// helms are the Semantos Brain's surface, so the FSM has to live on the Semantos Brain side
// to drive operator action through the dispatcher.
//
// Scope: the `VISIT_TRANSITIONS` array (four LINEAR rows), the lookup
// helper, and a single `validateTransition` entry point that the
// dispatcher's `visits.transition` command calls.  Same posture as
// job_fsm.zig: deliberately does NOT carry the K1 `ConsumedCellSet` /
// `runFailureAtomic` shape the TS module carries — those are kernel-
// gate concerns that only matter once cell-DAG bytes flow through this
// code path.  The brain-side store (`visits_store_fs.zig`) holds a
// SUBSET of the canonical `oddjobz.visit.v1` cell payload; idempotency
// on retry is provided by the store's append-only log + the handler's
// "already in to_state" short-circuit, not by a `consumed` set.

const std = @import("std");

/// The four canonical Visit FSM states.  Mirror of `VISIT_FSM_STATES`
/// in cartridges/oddjobz/brain/src/state-machines/visit-fsm.ts.
pub const VISIT_FSM_STATES = [_][]const u8{
    "scheduled",
    "in_progress",
    "completed",
    "cancelled",
};

/// Returns true if `s` is one of the canonical four states.
pub fn isFsmState(s: []const u8) bool {
    for (VISIT_FSM_STATES) |valid| {
        if (std.mem.eql(u8, valid, s)) return true;
    }
    return false;
}

/// Acceptable signing principals.  Mirror of `SigningPrincipal` in
/// cartridges/oddjobz/brain/src/state-machines/kernel-gate.ts.  The brain-side
/// dispatcher carries this on the inbound `principal_kind` arg of
/// `visits.transition`; the handler maps the string to this enum
/// before calling `validateTransition`.  Same enum as job_fsm —
/// duplicated locally here so the visit FSM module stays a leaf with
/// no imports beyond std.
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

/// One row in the §O4 Visit FSM transition table.  Mirror of
/// `VisitTransitionSpec` in cartridges/oddjobz/brain/src/state-machines/
/// visit-fsm.ts.  Field name `cap_required` is snake_case here; the TS
/// canon uses `capRequired` (camelCase).  Same value semantics — null
/// means an ungated transition (every Visit row is ungated today; the
/// gating story for Visit transitions is delegated to the parent Job
/// FSM per the visit-fsm.ts module head).
pub const Transition = struct {
    from: []const u8,
    to: []const u8,
    cap_required: ?[]const u8,
    /// Acceptable principal kinds (set semantics — order does not matter).
    principal_kinds: []const PrincipalKind,
};

/// The §O4 critical-path Visit FSM transition table — verbatim from
/// cartridges/oddjobz/brain/src/state-machines/visit-fsm.ts.  Declaration
/// order = spec row order.  The genesis ∅→scheduled row is handled by
/// `visits.create` (no input cell to consume); this table covers the
/// four LINEAR transitions.
pub const VISIT_TRANSITIONS = [_]Transition{
    .{
        .from = "scheduled",
        .to = "in_progress",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.service},
    },
    .{
        .from = "scheduled",
        .to = "cancelled",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        .from = "in_progress",
        .to = "completed",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
    .{
        .from = "in_progress",
        .to = "cancelled",
        .cap_required = null,
        .principal_kinds = &[_]PrincipalKind{.operator},
    },
};

/// Lookup the (from, to) row, or null if the pair isn't in the table.
pub fn findTransition(from: []const u8, to: []const u8) ?Transition {
    for (VISIT_TRANSITIONS) |t| {
        if (std.mem.eql(u8, t.from, from) and std.mem.eql(u8, t.to, to)) return t;
    }
    return null;
}

/// Typed validation outcomes.  Same shape as job_fsm.ValidationError —
/// maps onto the `{error: <kind>, from, to, cap_required}` JSON body
/// the dispatcher's `visits.transition` returns.
pub const ValidationError = enum {
    /// Either `from` or `to` is not one of the canonical four states.
    unknown_state,
    /// (from, to) is not a row in the §O4 Visit table.
    not_reachable,
    /// Row requires a cap, but the presented cap is missing or wrong.
    /// (No Visit FSM row requires a cap today — gating is delegated to
    /// the parent Job FSM per the canon.  This branch is reserved for
    /// future rows that gain a cap.)
    wrong_cap,
    /// The supplied principal kind isn't in the row's allowed set.
    wrong_principal,
    /// Visit is already at `to_state` — handler short-circuits to an
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
        cap_required: ?[]const u8,
    },
};

/// Validate a transition request.  Same five-step shape as job_fsm
/// validateTransition:
///
///   1. `to_state` must be a canonical Visit FSM state.
///   2. `current_state` must be a canonical Visit FSM state.
///   3. If `current_state == to_state`, return `.already_in_state`.
///   4. Look up the (current_state, to_state) row in VISIT_TRANSITIONS;
///      `not_reachable` if absent.
///   5. Verify principal_kind is in the row's `principal_kinds`.
///   6. Verify cap.  When the row's `cap_required` is non-null, the
///      caller must present that cap (string equality).  When the row
///      is ungated (every Visit row today), ANY cap (or no cap) is
///      accepted.
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
// tests/visits_handler_conformance.zig (it loads the canonical
// cartridges/oddjobz/brain/tests/vectors/state-machines/visit_fsm.json
// oracle).
// ─────────────────────────────────────────────────────────────────────

test "isFsmState recognises the four canonical states" {
    for (VISIT_FSM_STATES) |s| try std.testing.expect(isFsmState(s));
    try std.testing.expect(!isFsmState(""));
    try std.testing.expect(!isFsmState("paused"));
    try std.testing.expect(!isFsmState("SCHEDULED"));
}

test "VISIT_TRANSITIONS table has four canonical rows" {
    try std.testing.expectEqual(@as(usize, 4), VISIT_TRANSITIONS.len);
    // Spot-check the table head + tail to catch a drift from the TS
    // canon: row 0 is scheduled→in_progress (no cap, service); row 3
    // is in_progress→cancelled (no cap, operator).
    try std.testing.expectEqualStrings("scheduled", VISIT_TRANSITIONS[0].from);
    try std.testing.expectEqualStrings("in_progress", VISIT_TRANSITIONS[0].to);
    try std.testing.expect(VISIT_TRANSITIONS[0].cap_required == null);
    try std.testing.expectEqual(PrincipalKind.service, VISIT_TRANSITIONS[0].principal_kinds[0]);

    try std.testing.expectEqualStrings("in_progress", VISIT_TRANSITIONS[3].from);
    try std.testing.expectEqualStrings("cancelled", VISIT_TRANSITIONS[3].to);
    try std.testing.expect(VISIT_TRANSITIONS[3].cap_required == null);
    try std.testing.expectEqual(PrincipalKind.operator, VISIT_TRANSITIONS[3].principal_kinds[0]);
}

test "findTransition returns null for non-table pairs" {
    try std.testing.expect(findTransition("scheduled", "completed") == null);
    try std.testing.expect(findTransition("completed", "scheduled") == null);
    try std.testing.expect(findTransition("paused", "in_progress") == null);
}

test "validateTransition: happy path scheduled → in_progress" {
    const r = validateTransition("scheduled", "in_progress", null, .service);
    switch (r) {
        .ok => |row| {
            try std.testing.expectEqualStrings("scheduled", row.from);
            try std.testing.expectEqualStrings("in_progress", row.to);
        },
        .err => return error.UnexpectedErr,
    }
}

test "validateTransition: ungated rows accept any/no cap" {
    // scheduled→in_progress requires no cap.
    const r = validateTransition("scheduled", "in_progress", null, .service);
    switch (r) {
        .ok => {},
        .err => return error.UnexpectedErr,
    }
    // Even when caller presents a cap, ungated rows accept it.
    const r2 = validateTransition("scheduled", "in_progress", "cap.oddjobz.dispatch", .service);
    switch (r2) {
        .ok => {},
        .err => return error.UnexpectedErr,
    }
}

test "validateTransition: wrong_principal" {
    // scheduled→in_progress is service-only.  An operator principal must reject.
    const r = validateTransition("scheduled", "in_progress", null, .operator);
    switch (r) {
        .ok => return error.UnexpectedOk,
        .err => |e| try std.testing.expectEqual(ValidationError.wrong_principal, e.kind),
    }
}

test "validateTransition: not_reachable on direct scheduled→completed jump" {
    const r = validateTransition("scheduled", "completed", null, .operator);
    switch (r) {
        .ok => return error.UnexpectedOk,
        .err => |e| try std.testing.expectEqual(ValidationError.not_reachable, e.kind),
    }
}

test "validateTransition: unknown_state when to_state isn't canonical" {
    const r = validateTransition("scheduled", "PAUSED", null, .operator);
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

test "validateTransition: scheduled → cancelled (operator)" {
    const r = validateTransition("scheduled", "cancelled", null, .operator);
    switch (r) {
        .ok => |row| try std.testing.expectEqualStrings("cancelled", row.to),
        .err => return error.UnexpectedErr,
    }
}

test "validateTransition: in_progress → completed (operator)" {
    const r = validateTransition("in_progress", "completed", null, .operator);
    switch (r) {
        .ok => |row| try std.testing.expectEqualStrings("completed", row.to),
        .err => return error.UnexpectedErr,
    }
}

test "validateTransition: terminal states reject outgoing transitions" {
    // completed and cancelled are absorbing — every outgoing pair is
    // not_reachable.
    const r1 = validateTransition("completed", "in_progress", null, .operator);
    switch (r1) {
        .ok => return error.UnexpectedOk,
        .err => |e| try std.testing.expectEqual(ValidationError.not_reachable, e.kind),
    }
    const r2 = validateTransition("cancelled", "scheduled", null, .operator);
    switch (r2) {
        .ok => return error.UnexpectedOk,
        .err => |e| try std.testing.expectEqual(ValidationError.not_reachable, e.kind),
    }
}

```
