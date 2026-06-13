---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/nats_event_producer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.219959+00:00
---

# runtime/semantos-brain/src/nats_event_producer.zig

```zig
// W7.3 — NatsEventProducer: publish Oddjobz FSM transitions to NATS JetStream.
//
// Produces to subject: op.<op_pkh16>.<hat_id>.fsm_transition
// The per-operator JetStream stream (op_<op_pkh16>) captures all subjects
// under op.<op_pkh16>.> — so all hat lanes and event types land in one
// ordered, durable, replayable stream per operator.
//
// This runs alongside OddjobzEventProducer (W3.1, Pravega) — both are
// best-effort, so a NATS write failure does not roll back the FSM transition.
// The in-process OddjobzEventBus (W3.2) also fires independently for live
// WebSocket fanout.
//
// op_pkh16: first 16 hex chars of the operator's pubkey hash (8 bytes).
// Until W7.1 (LMDB op prefix) lands, the caller passes a placeholder derived
// from the hat config.
//
// References:
//   - docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md §2.4, W7.3
//   - runtime/semantos-brain/src/nats_client.zig (transport)
//   - runtime/semantos-brain/src/resources/jobs_handler.zig (caller)
//   - runtime/semantos-brain/src/oddjobz_event_producer.zig (Pravega counterpart)

const std = @import("std");
const nats_client = @import("nats_client");
const NatsClient = nats_client.NatsClient;

// ── Types ──────────────────────────────────────────────────────────────────

/// Subject axes:
///   op.<op_pkh16>.<hat_id>.<event_type>
///
/// Event types emitted by this producer:
///   fsm_transition  — job/visit/quote/invoice FSM state change
///
/// Reserved for future producers:
///   cell_written    — raw cell commit (W7.1 cell write path)
///   helm_refresh    — Pask graph node added / updated

pub const EVENT_TYPE_FSM_TRANSITION = "fsm_transition";
/// WI-A1 — `intent_outcome` event. Emitted after a SIR program lowers and
/// commits cleanly. Per-hat subject so library populators can filter.
pub const EVENT_TYPE_INTENT_OUTCOME = "intent_outcome";
/// WI-A3 — `stable_transition` event. Emitted by the host wrapper around
/// `pask_interact_run` when a node flips false → true on stability.
/// Uses the synthetic `pask` hat namespace because stability is kernel-level,
/// not bound to any application hat.
pub const EVENT_TYPE_STABLE_TRANSITION = "stable_transition";
pub const SYNTHETIC_HAT_PASK = "pask";

// ── Producer ──────────────────────────────────────────────────────────────

pub const NatsEventProducer = struct {
    allocator: std.mem.Allocator,
    /// Non-owning pointer — caller keeps NatsClient alive.
    client: *NatsClient,
    /// First 16 hex chars of the operator pubkey hash (8 bytes → 16 hex chars).
    /// Fixed at provisioning time.  Use placeholder until W7.1 lands.
    op_pkh16: [16]u8,
    /// Stable per-process identifier for the Pask kernel emitting
    /// `stable_transition` events. Required by the multiparticipant
    /// agreement experiment (research/cognition-implementation-plan.md §4)
    /// to attribute stability flips to a specific kernel. Set at provisioning;
    /// must be the same across the lifetime of one kernel instance.
    kernel_id: [32]u8,

    pub fn init(
        allocator: std.mem.Allocator,
        client: *NatsClient,
        op_pkh16: [16]u8,
    ) NatsEventProducer {
        return .{
            .allocator = allocator,
            .client = client,
            .op_pkh16 = op_pkh16,
            .kernel_id = defaultKernelId(op_pkh16),
        };
    }

    /// Override the kernel_id (e.g. when a host process owns multiple
    /// federated Pask kernels and must distinguish them).
    pub fn setKernelId(self: *NatsEventProducer, kernel_id: [32]u8) void {
        self.kernel_id = kernel_id;
    }

    // ── Subject builders (pure — testable without a client) ─────────────────

    /// Build the FSM-transition subject for this operator + hat.
    pub fn fsmTransitionSubject(self: *const NatsEventProducer, hat_id: []const u8, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "op.{s}.{s}." ++ EVENT_TYPE_FSM_TRANSITION, .{ &self.op_pkh16, hat_id });
    }

    /// Build the intent-outcome subject for this operator + hat.
    pub fn intentOutcomeSubject(self: *const NatsEventProducer, hat_id: []const u8, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "op.{s}.{s}." ++ EVENT_TYPE_INTENT_OUTCOME, .{ &self.op_pkh16, hat_id });
    }

    /// Build the stable-transition subject for this operator. Uses the
    /// synthetic `pask` hat namespace because stability transitions are
    /// kernel-level events, not bound to any application hat.
    pub fn stableTransitionSubject(self: *const NatsEventProducer, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "op.{s}." ++ SYNTHETIC_HAT_PASK ++ "." ++ EVENT_TYPE_STABLE_TRANSITION, .{&self.op_pkh16});
    }

    // ── Event emission ──────────────────────────────────────────────────────

    /// Emit a job FSM transition to NATS.  Best-effort — error is returned
    /// so the caller can log, but should not propagate (FSM commit already
    /// landed in LMDB/Postgres).
    ///
    /// Subject: op.<op_pkh16>.<hat_id>.fsm_transition
    /// Payload shape matches W3.1 (OddjobzEventProducer) plus op_pkh field.
    pub fn emitJobTransition(
        self: *NatsEventProducer,
        hat_id: []const u8,
        job_id: []const u8,
        cell_id: []const u8,
        from_state: []const u8,
        to_state: []const u8,
        ts_ms: u64,
    ) !void {
        var subject_buf: [256]u8 = undefined;
        const subject = try self.fsmTransitionSubject(hat_id, &subject_buf);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{" ++
                "\"job_id\":\"{s}\"," ++
                "\"cell_id\":\"{s}\"," ++
                "\"from_state\":\"{s}\"," ++
                "\"to_state\":\"{s}\"," ++
                "\"ts_ms\":{d}," ++
                "\"hat_id\":\"{s}\"," ++
                "\"op_pkh\":\"{s}\"" ++
                "}}",
            .{ job_id, cell_id, from_state, to_state, ts_ms, hat_id, &self.op_pkh16 },
        );
        defer self.allocator.free(payload);

        try self.client.publish(subject, payload);
    }

    // ── WI-A1: intent_outcome ──────────────────────────────────────────────

    /// Emit an `intent_outcome` event after a SIR program lowers and commits.
    /// Best-effort — error surfaces so the caller can log, but commit has
    /// already landed in LMDB/Postgres before this fires.
    ///
    /// Subject: op.<op_pkh16>.<hat_id>.intent_outcome
    ///
    /// `anf_bindings_json` is the already-serialised JSON array of bindings
    /// from the lowered IRProgram. The caller serialises (rather than this
    /// producer reaching into the IR types) so this module stays a pure
    /// transport with no dependency on `core/semantos-ir`.
    pub fn emitIntentOutcome(
        self: *NatsEventProducer,
        hat_id: []const u8,
        intent_id: []const u8,
        domain_flag: u32,
        lexicon: []const u8,
        jural_category: []const u8,
        anf_bindings_json: []const u8,
        composite_confidence: f64,
        cell_outcome_hash: []const u8,
        ts_ms: u64,
    ) !void {
        var subject_buf: [256]u8 = undefined;
        const subject = try self.intentOutcomeSubject(hat_id, &subject_buf);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{" ++
                "\"intent_id\":\"{s}\"," ++
                "\"domain_flag\":{d}," ++
                "\"lexicon\":\"{s}\"," ++
                "\"jural_category\":\"{s}\"," ++
                "\"anf_bindings\":{s}," ++
                "\"composite_confidence\":{d:.6}," ++
                "\"cell_outcome_hash\":\"{s}\"," ++
                "\"ts_ms\":{d}," ++
                "\"hat_id\":\"{s}\"," ++
                "\"op_pkh\":\"{s}\"" ++
                "}}",
            .{
                intent_id,
                domain_flag,
                lexicon,
                jural_category,
                anf_bindings_json,
                composite_confidence,
                cell_outcome_hash,
                ts_ms,
                hat_id,
                &self.op_pkh16,
            },
        );
        defer self.allocator.free(payload);

        try self.client.publish(subject, payload);
    }

    // ── WI-A3: stable_transition ───────────────────────────────────────────

    /// Emit a `stable_transition` event for a Pask node that just flipped
    /// false → true on stability.  The host wrapper around `pask_interact_run`
    /// is the only legitimate caller; the kernel itself never emits.
    ///
    /// Subject: op.<op_pkh16>.pask.stable_transition
    ///
    /// Carries `kernel_id` so the multiparticipant agreement experiment
    /// (§4 of the implementation plan) can attribute each flip to a specific
    /// kernel and compute cross-kernel agreement rates.
    pub fn emitStableTransition(
        self: *NatsEventProducer,
        node_idx: u32,
        cell_id: []const u8,
        h_state: f64,
        total_constraint_strength: f64,
        interaction_count: u32,
        ts_ms: u64,
    ) !void {
        var subject_buf: [128]u8 = undefined;
        const subject = try self.stableTransitionSubject(&subject_buf);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{" ++
                "\"node_idx\":{d}," ++
                "\"cell_id\":\"{s}\"," ++
                "\"h_state\":{d:.6}," ++
                "\"total_constraint_strength\":{d:.6}," ++
                "\"interaction_count\":{d}," ++
                "\"kernel_id\":\"{s}\"," ++
                "\"ts_ms\":{d}," ++
                "\"op_pkh\":\"{s}\"" ++
                "}}",
            .{
                node_idx,
                cell_id,
                h_state,
                total_constraint_strength,
                interaction_count,
                &self.kernel_id,
                ts_ms,
                &self.op_pkh16,
            },
        );
        defer self.allocator.free(payload);

        try self.client.publish(subject, payload);
    }

    // ── Stream lifecycle (W7.9 provisioning + W7.8 exit) ───────────────────

    /// JetStream stream name for this operator.
    /// Format: op_<op_pkh16>  (underscore — dots are not valid in stream names).
    pub fn streamName(self: *const NatsEventProducer, buf: *[32]u8) []u8 {
        return std.fmt.bufPrint(buf, "op_{s}", .{&self.op_pkh16}) catch unreachable;
    }

    /// Create the JetStream stream for this operator.
    /// Call during provisioning (W7.9).  Idempotent.
    pub fn ensureStream(self: *NatsEventProducer) !void {
        var name_buf: [32]u8 = undefined;
        const name = self.streamName(&name_buf);

        var subjects_buf: [64]u8 = undefined;
        const subjects_json = try std.fmt.bufPrint(
            &subjects_buf,
            "[\"op.{s}.>\"]",
            .{&self.op_pkh16},
        );

        try self.client.streamCreate(name, subjects_json);
    }

    /// Create the durable pull consumer for the BRAIN brain replay path.
    /// `consumer_name` should be unique per process (e.g. "brain_brain_<op_pkh16>").
    /// Call during provisioning, after ensureStream.
    pub fn ensureBrainConsumer(self: *NatsEventProducer, consumer_name: []const u8) !void {
        var name_buf: [32]u8 = undefined;
        const stream = self.streamName(&name_buf);

        var filter_buf: [64]u8 = undefined;
        const filter = try std.fmt.bufPrint(
            &filter_buf,
            "op.{s}.>",
            .{&self.op_pkh16},
        );

        try self.client.consumerCreateDurable(stream, consumer_name, filter, "all");
    }

    /// Delete the JetStream stream for this operator.
    /// Call during operator exit (W7.8).  Idempotent.
    pub fn deleteStream(self: *NatsEventProducer) !void {
        var name_buf: [32]u8 = undefined;
        const name = self.streamName(&name_buf);
        try self.client.streamDelete(name);
    }
};

// ── Helpers ────────────────────────────────────────────────────────────────

/// Derive a stable 32-hex-char kernel_id from the operator's pkh16.
/// Deterministic — same op_pkh16 produces same kernel_id. Production hosts
/// running multiple kernels for one operator should override via setKernelId.
pub fn defaultKernelId(op_pkh16: [16]u8) [32]u8 {
    var out: [32]u8 = undefined;
    var hash_a: u64 = 0xcbf29ce484222325; // FNV-1a offset basis
    var hash_b: u64 = 0x84222325cbf29ce4; // alt seed for second word
    for (op_pkh16) |c| {
        hash_a ^= c;
        hash_a *%= 0x100000001b3;
        hash_b ^= c;
        hash_b *%= 0xc6a4a7935bd1e995; // FNV-like alt prime
    }
    const hex = "0123456789abcdef";
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const shift: u6 = @intCast((15 - i) * 4);
        out[i] = hex[(hash_a >> shift) & 0xf];
    }
    while (i < 32) : (i += 1) {
        const shift: u6 = @intCast((31 - i) * 4);
        out[i] = hex[(hash_b >> shift) & 0xf];
    }
    return out;
}

/// Build a placeholder op_pkh16 from a hat_id string.
/// Used until W7.1 lands the real operator prefix.  Deterministic: same
/// hat_id always produces the same 16-char hex string.
pub fn opPkh16FromHatId(hat_id: []const u8) [16]u8 {
    var out: [16]u8 = undefined;
    var hash: u64 = 0xcbf29ce484222325; // FNV-1a offset basis
    for (hat_id) |c| {
        hash ^= c;
        hash *%= 0x100000001b3; // FNV-1a prime
    }
    const hex = "0123456789abcdef";
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const shift: u6 = @intCast((15 - i) * 4);
        out[i] = hex[(hash >> shift) & 0xf];
    }
    return out;
}

// ── Inline tests ──────────────────────────────────────────────────────────

test "nats_event_producer: streamName format" {
    const client_ptr: *NatsClient = undefined; // not called in this test
    const pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    const producer = NatsEventProducer.init(std.testing.allocator, client_ptr, pkh16);
    var name_buf: [32]u8 = undefined;
    const name = producer.streamName(&name_buf);
    try std.testing.expectEqualStrings("op_a3f7b2c1d4e5f6a7", name);
}

test "nats_event_producer: opPkh16FromHatId is deterministic" {
    const a = opPkh16FromHatId("oddjobz.jobs");
    const b = opPkh16FromHatId("oddjobz.jobs");
    try std.testing.expectEqualStrings(&a, &b);
}

test "nats_event_producer: opPkh16FromHatId differs for different inputs" {
    const a = opPkh16FromHatId("oddjobz.jobs");
    const b = opPkh16FromHatId("oddjobz.visits");
    // Different hat IDs should produce different hashes (not a guarantee but
    // for any two distinct strings in our namespace it holds).
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
}

test "nats_event_producer: opPkh16FromHatId output is 16 hex chars" {
    const pkh = opPkh16FromHatId("test-hat");
    try std.testing.expectEqual(@as(usize, 16), pkh.len);
    for (pkh) |c| {
        const valid = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(valid);
    }
}

// ── WI-A1: intent_outcome subject ──────────────────────────────────────────

test "WI-A1: intentOutcomeSubject format" {
    const client_ptr: *NatsClient = undefined; // not called in this test
    const pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    const producer = NatsEventProducer.init(std.testing.allocator, client_ptr, pkh16);
    var buf: [256]u8 = undefined;
    const subject = try producer.intentOutcomeSubject("oddjobz.jobs", &buf);
    try std.testing.expectEqualStrings(
        "op.a3f7b2c1d4e5f6a7.oddjobz.jobs.intent_outcome",
        subject,
    );
}

test "WI-A1: intentOutcomeSubject distinguishes hats" {
    const client_ptr: *NatsClient = undefined;
    const pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    const producer = NatsEventProducer.init(std.testing.allocator, client_ptr, pkh16);
    var buf_a: [256]u8 = undefined;
    var buf_b: [256]u8 = undefined;
    const sub_a = try producer.intentOutcomeSubject("oddjobz.jobs", &buf_a);
    const sub_b = try producer.intentOutcomeSubject("scada.alarms", &buf_b);
    try std.testing.expect(!std.mem.eql(u8, sub_a, sub_b));
}

test "WI-A1: intentOutcomeSubject lives under op.<pkh>.> wildcard" {
    // The per-operator JetStream stream filters on `op.<pkh>.>`, so every
    // event subject must start with that prefix. This test pins the invariant.
    const client_ptr: *NatsClient = undefined;
    const pkh16: [16]u8 = "deadbeefcafefeed".*;
    const producer = NatsEventProducer.init(std.testing.allocator, client_ptr, pkh16);
    var buf: [256]u8 = undefined;
    const subject = try producer.intentOutcomeSubject("oddjobz.jobs", &buf);
    try std.testing.expect(std.mem.startsWith(u8, subject, "op.deadbeefcafefeed."));
}

// ── WI-A3: stable_transition subject + kernel_id ───────────────────────────

test "WI-A3: stableTransitionSubject format" {
    const client_ptr: *NatsClient = undefined;
    const pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    const producer = NatsEventProducer.init(std.testing.allocator, client_ptr, pkh16);
    var buf: [128]u8 = undefined;
    const subject = try producer.stableTransitionSubject(&buf);
    try std.testing.expectEqualStrings(
        "op.a3f7b2c1d4e5f6a7.pask.stable_transition",
        subject,
    );
}

test "WI-A3: stableTransitionSubject under op.<pkh>.> wildcard" {
    const client_ptr: *NatsClient = undefined;
    const pkh16: [16]u8 = "deadbeefcafefeed".*;
    const producer = NatsEventProducer.init(std.testing.allocator, client_ptr, pkh16);
    var buf: [128]u8 = undefined;
    const subject = try producer.stableTransitionSubject(&buf);
    try std.testing.expect(std.mem.startsWith(u8, subject, "op.deadbeefcafefeed."));
}

test "WI-A3: defaultKernelId is deterministic" {
    const a = defaultKernelId("a3f7b2c1d4e5f6a7".*);
    const b = defaultKernelId("a3f7b2c1d4e5f6a7".*);
    try std.testing.expectEqualStrings(&a, &b);
}

test "WI-A3: defaultKernelId differs for different operators" {
    const a = defaultKernelId("a3f7b2c1d4e5f6a7".*);
    const b = defaultKernelId("deadbeefcafefeed".*);
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
}

test "WI-A3: defaultKernelId is 32 hex chars" {
    const kid = defaultKernelId("a3f7b2c1d4e5f6a7".*);
    try std.testing.expectEqual(@as(usize, 32), kid.len);
    for (kid) |c| {
        const valid = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(valid);
    }
}

test "WI-A3: setKernelId overrides default" {
    const client_ptr: *NatsClient = undefined;
    const pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    var producer = NatsEventProducer.init(std.testing.allocator, client_ptr, pkh16);
    const original = producer.kernel_id;
    const override: [32]u8 = "00000000000000000000000000000001".*;
    producer.setKernelId(override);
    try std.testing.expect(!std.mem.eql(u8, &original, &producer.kernel_id));
    try std.testing.expectEqualStrings(&override, &producer.kernel_id);
}

test "WI-A3: same producer keeps stable kernel_id across reads" {
    // The multiparticipant agreement experiment depends on kernel_id being
    // stable across the lifetime of one producer instance — different events
    // from the same kernel must carry the same id so a downstream consumer
    // can attribute them to the same observer.
    const client_ptr: *NatsClient = undefined;
    const pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    const producer = NatsEventProducer.init(std.testing.allocator, client_ptr, pkh16);
    const first = producer.kernel_id;
    const second = producer.kernel_id;
    try std.testing.expectEqualStrings(&first, &second);
}

```
