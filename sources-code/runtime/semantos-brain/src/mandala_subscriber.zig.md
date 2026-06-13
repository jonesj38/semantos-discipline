---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/mandala_subscriber.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.244146+00:00
---

# runtime/semantos-brain/src/mandala_subscriber.zig

```zig
// WI-C3 — Mandala subscription rule.
//
// Implements the candidate subscription rule from cognition-framework.md §4 Gap 4.
// Given the local kernel's observable context (counterparties, domain flag,
// external high-h_state streams), the rule emits a set of NATS subjects to
// subscribe to.
//
// Subscription rules:
//   (a) Every counterparty stream with transaction_count ≥ counterparty_threshold.
//   (b) The domain stream for the active hat's domain_flag.
//   (c) Up to random_sample_cap external (non-domain) streams with the highest
//       h_state scores — a deterministic descending-score selection that approximates
//       the Mandala-graph random sample in a single-node context.
//
// Reference graph parameters from Sampaio et al. 2015 (cited in the paper):
//   b = 2..4 (branching factor)
//   n_1 = 3..4 (first-ring size)
//   λ = 2 (ring multiplier)
// The random_sample_cap should be tuned to produce a subscription graph in
// this small-world band. Default: 3.
//
// Tests (inline and conformance — no live NATS):
//   WI-C3-T-subscription-includes-counterparties
//   WI-C3-T-domain-flag-subscription-active
//   WI-C3-T-random-sample-bounded
//
// See research/cognition-implementation-plan.md §WI-C3.

const std = @import("std");

pub const MAX_SUBJECT_LEN = 128;
pub const MAX_SUBSCRIPTIONS = 512;

pub const SubjectBuf = [MAX_SUBJECT_LEN]u8;

/// A NATS subject to subscribe to.
pub const Subscription = struct {
    subject: SubjectBuf,
    subject_len: u32,

    pub fn slice(self: *const Subscription) []const u8 {
        return self.subject[0..self.subject_len];
    }
};

/// One counterparty stream observed locally.
pub const CounterpartyStream = struct {
    /// NATS subject for this counterparty's stream.
    subject: SubjectBuf,
    subject_len: u32,
    /// Number of transactions involving this counterparty.
    transaction_count: u32,

    pub fn slice(self: *const CounterpartyStream) []const u8 {
        return self.subject[0..self.subject_len];
    }
};

/// An external (non-domain) stream visible to the subscription engine.
pub const ExternalStream = struct {
    subject: SubjectBuf,
    subject_len: u32,
    /// Pask h_state for the leading node in this stream, used for sampling.
    h_state: f64,
    /// Domain flag of the owning kernel (may differ from our domain).
    domain_flag: u32,

    pub fn slice(self: *const ExternalStream) []const u8 {
        return self.subject[0..self.subject_len];
    }
};

pub const MandalaConfig = struct {
    /// Min transactions to qualify as a counterparty subscription (rule a).
    counterparty_threshold: u32,
    /// Number of high-h_state external streams to sample (rule c).
    random_sample_cap: u32,
    /// Active hat domain flag (rule b).
    domain_flag: u32,
};

pub const DEFAULT_MANDALA_CONFIG = MandalaConfig{
    .counterparty_threshold = 1,
    .random_sample_cap = 3,
    .domain_flag = 0,
};

/// Output buffer for `computeSubscriptions`.
pub const SubscriptionSet = struct {
    items: [MAX_SUBSCRIPTIONS]Subscription,
    count: u32,

    pub fn slice(self: *const SubscriptionSet) []const Subscription {
        return self.items[0..self.count];
    }
};

fn pushSubject(set: *SubscriptionSet, subject: []const u8) void {
    if (set.count >= MAX_SUBSCRIPTIONS) return;
    if (subject.len == 0 or subject.len > MAX_SUBJECT_LEN) return;
    // Deduplicate.
    var i: u32 = 0;
    while (i < set.count) : (i += 1) {
        if (std.mem.eql(u8, set.items[i].slice(), subject)) return;
    }
    const s = &set.items[set.count];
    @memcpy(s.subject[0..subject.len], subject);
    s.subject_len = @intCast(subject.len);
    set.count += 1;
}

/// Compute the Mandala subscription set.
///
/// The caller owns the output `SubscriptionSet` — no allocation.
pub fn computeSubscriptions(
    cfg: MandalaConfig,
    counterparties: []const CounterpartyStream,
    externals: []const ExternalStream,
    out: *SubscriptionSet,
) void {
    out.count = 0;

    // Rule (a): counterparty streams above threshold.
    for (counterparties) |*cp| {
        if (cp.transaction_count >= cfg.counterparty_threshold) {
            pushSubject(out, cp.slice());
        }
    }

    // Rule (b): domain stream for the active hat.
    var domain_buf: [32]u8 = undefined;
    const domain_subject = std.fmt.bufPrint(&domain_buf, "domain.{d}.>", .{cfg.domain_flag}) catch return;
    pushSubject(out, domain_subject);

    // Rule (c): top-N external streams by h_state (outside our domain).
    // Copy eligible entries into a scratch slice sorted by h_state descending.
    var scratch: [MAX_SUBSCRIPTIONS]ExternalStream = undefined;
    var n_scratch: u32 = 0;
    for (externals) |*ext| {
        if (ext.domain_flag != cfg.domain_flag and n_scratch < MAX_SUBSCRIPTIONS) {
            scratch[n_scratch] = ext.*;
            n_scratch += 1;
        }
    }
    // Insertion sort (small N — random_sample_cap is typically 3..8).
    var i: u32 = 1;
    while (i < n_scratch) : (i += 1) {
        const key = scratch[i];
        var j: i32 = @as(i32, @intCast(i)) - 1;
        while (j >= 0 and scratch[@intCast(j)].h_state < key.h_state) : (j -= 1) {
            scratch[@intCast(j + 1)] = scratch[@intCast(j)];
        }
        scratch[@intCast(j + 1)] = key;
    }
    const take = @min(cfg.random_sample_cap, n_scratch);
    var k: u32 = 0;
    while (k < take) : (k += 1) {
        pushSubject(out, scratch[k].slice());
    }
}

// ── Helpers for tests ─────────────────────────────────────────────────────────

fn makeCounterparty(subject: []const u8, tx: u32) CounterpartyStream {
    var cp: CounterpartyStream = undefined;
    @memcpy(cp.subject[0..subject.len], subject);
    cp.subject_len = @intCast(subject.len);
    cp.transaction_count = tx;
    return cp;
}

fn makeExternal(subject: []const u8, h: f64, domain: u32) ExternalStream {
    var ext: ExternalStream = undefined;
    @memcpy(ext.subject[0..subject.len], subject);
    ext.subject_len = @intCast(subject.len);
    ext.h_state = h;
    ext.domain_flag = domain;
    return ext;
}

// ── Inline tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "WI-C3-T-subscription-includes-counterparties" {
    const cfg = MandalaConfig{
        .counterparty_threshold = 2,
        .random_sample_cap = 0,
        .domain_flag = 7,
    };
    const cps = [_]CounterpartyStream{
        makeCounterparty("op.aaa.hat1.>", 3), // above threshold
        makeCounterparty("op.bbb.hat1.>", 1), // below threshold
        makeCounterparty("op.ccc.hat1.>", 5), // above threshold
    };
    var out: SubscriptionSet = undefined;
    computeSubscriptions(cfg, &cps, &.{}, &out);

    // Should have 2 counterparties + 1 domain = 3 subscriptions
    var found_aaa = false;
    var found_ccc = false;
    for (out.slice()) |*s| {
        if (std.mem.eql(u8, s.slice(), "op.aaa.hat1.>")) found_aaa = true;
        if (std.mem.eql(u8, s.slice(), "op.ccc.hat1.>")) found_ccc = true;
        // bbb should NOT appear
        try testing.expect(!std.mem.eql(u8, s.slice(), "op.bbb.hat1.>"));
    }
    try testing.expect(found_aaa);
    try testing.expect(found_ccc);
}

test "WI-C3-T-domain-flag-subscription-active" {
    const cfg = MandalaConfig{
        .counterparty_threshold = 100,
        .random_sample_cap = 0,
        .domain_flag = 11,
    };
    var out: SubscriptionSet = undefined;
    computeSubscriptions(cfg, &.{}, &.{}, &out);

    var found_domain = false;
    for (out.slice()) |*s| {
        if (std.mem.eql(u8, s.slice(), "domain.11.>")) found_domain = true;
    }
    try testing.expect(found_domain);
}

test "WI-C3-T-random-sample-bounded" {
    const cap: u32 = 3;
    const cfg = MandalaConfig{
        .counterparty_threshold = 999,
        .random_sample_cap = cap,
        .domain_flag = 7,
    };
    // Provide 10 external streams from domain 11 (all eligible for sampling)
    var externals: [10]ExternalStream = undefined;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        var buf: [24]u8 = undefined;
        const subj = std.fmt.bufPrint(&buf, "ext.stream.{d}", .{i}) catch unreachable;
        externals[i] = makeExternal(subj, 1.0 - @as(f64, @floatFromInt(i)) * 0.05, 11);
    }
    var out: SubscriptionSet = undefined;
    computeSubscriptions(cfg, &.{}, &externals, &out);

    // Count how many are external-stream entries (not the domain subject).
    var sample_count: u32 = 0;
    for (out.slice()) |*s| {
        if (std.mem.startsWith(u8, s.slice(), "ext.stream.")) sample_count += 1;
    }
    try testing.expect(sample_count <= cap);
}

test "sample selects highest-h_state externals" {
    const cfg = MandalaConfig{
        .counterparty_threshold = 999,
        .random_sample_cap = 2,
        .domain_flag = 7,
    };
    const externals = [_]ExternalStream{
        makeExternal("ext.low",  0.3, 11),
        makeExternal("ext.high", 0.9, 11),
        makeExternal("ext.mid",  0.6, 11),
    };
    var out: SubscriptionSet = undefined;
    computeSubscriptions(cfg, &.{}, &externals, &out);

    var found_high = false;
    var found_mid  = false;
    for (out.slice()) |*s| {
        if (std.mem.eql(u8, s.slice(), "ext.high")) found_high = true;
        if (std.mem.eql(u8, s.slice(), "ext.mid"))  found_mid  = true;
    }
    try testing.expect(found_high);
    try testing.expect(found_mid);
}

```
