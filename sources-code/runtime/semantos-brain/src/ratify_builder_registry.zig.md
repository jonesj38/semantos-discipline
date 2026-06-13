---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/ratify_builder_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.266309+00:00
---

# runtime/semantos-brain/src/ratify_builder_registry.zig

```zig
//! Ratify-builder registry — C4 PR-J5, the generic ratification seam.
//!
//! ratify is the commit/idempotency step of the LLM intent-extraction pipeline:
//! a confirmed intent (a SIR program + payload hint) is turned into committed,
//! signed cells. That graph-construction is DOMAIN-specific (oddjobz builds
//! site→customers→job→attachments with in-walk FK refs + lookup-or-mint dedup),
//! so it stays in the cartridge — behind a builder vtable. The brain owns the
//! generic ratify VERB + this registry + namespace dispatch; each cartridge
//! registers one builder, keyed by namespace (consistent with the attention /
//! cells_by_type namespace model).
//!
//! Idempotency/persistence is the BUILDER's concern (the ratifications log stores
//! the cartridge's graph shape = cartridge domain state), not the brain's. The
//! brain is a pure namespace router: it resolves the builder and hands it the raw
//! params; the builder returns the wire result blob.
//!
//! Leaf deps: std only — so cartridge_seam can expose it on CartridgeDeps without
//! pulling in serve/reactor (#847). Builders carry an opaque ctx + a submit fn;
//! the registry never frees them (cartridge owns them, brain-lifetime).

const std = @import("std");

/// Ratify a proposal: `params_json` = `{proposal_id, sir_program, payload_hint}`.
/// Returns the wire result blob (the cartridge's serialised graph), allocated
/// with `allocator` (caller frees). The builder owns idempotency + persistence.
pub const SubmitFn = *const fn (
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    params_json: []const u8,
) anyerror![]u8;

/// One registered ratify builder.
pub const RatifyBuilder = struct {
    /// The namespace this builder serves (e.g. "oddjobz"). Matched against the
    /// caller's requested namespace. Borrowed (usually a literal).
    namespace: []const u8,
    /// Short label for diagnostics/logging. Borrowed.
    label: []const u8,
    /// Caller-owned state (the cartridge's ratify handler pointer).
    ctx: *anyopaque,
    submit: SubmitFn,
};

/// Growable, bounded registry. Default-constructable (`.{}`); cartridges append
/// via `add`. The submit handler resolves a builder via `find`.
pub const RatifyBuilderRegistry = struct {
    pub const MAX = 32;
    entries: [MAX]RatifyBuilder = undefined,
    len: usize = 0,

    pub fn add(self: *RatifyBuilderRegistry, builder: RatifyBuilder) void {
        if (self.len >= MAX) {
            std.log.warn("ratify_builder_registry: MAX ({d}) reached; dropping builder {s}/{s}", .{ MAX, builder.namespace, builder.label });
            return;
        }
        // First registration for a namespace wins; later dupes are dropped.
        if (self.find(builder.namespace) != null) {
            std.log.warn("ratify_builder_registry: namespace {s} already registered; dropping {s}", .{ builder.namespace, builder.label });
            return;
        }
        self.entries[self.len] = builder;
        self.len += 1;
    }

    /// Resolve the builder for `namespace`, or null if none registered.
    pub fn find(self: *const RatifyBuilderRegistry, namespace: []const u8) ?*const RatifyBuilder {
        for (self.entries[0..self.len]) |*b| {
            if (std.mem.eql(u8, b.namespace, namespace)) return b;
        }
        return null;
    }

    pub fn all(self: *const RatifyBuilderRegistry) []const RatifyBuilder {
        return self.entries[0..self.len];
    }
};

// ── inline tests ──────────────────────────────────────────────────────────

const testing = std.testing;

fn echoSubmit(ctx: *anyopaque, allocator: std.mem.Allocator, _: []const u8) anyerror![]u8 {
    const tag: *const u8 = @ptrCast(ctx);
    return std.fmt.allocPrint(allocator, "{{\"ns\":{d}}}", .{tag.*});
}

test "registry: add + find by namespace, first wins, dupes dropped" {
    var reg: RatifyBuilderRegistry = .{};
    var a: u8 = 1;
    var b: u8 = 2;
    reg.add(.{ .namespace = "oddjobz", .label = "graph", .ctx = &a, .submit = echoSubmit });
    reg.add(.{ .namespace = "betterment", .label = "g2", .ctx = &b, .submit = echoSubmit });
    // dupe namespace dropped
    reg.add(.{ .namespace = "oddjobz", .label = "dupe", .ctx = &b, .submit = echoSubmit });

    try testing.expectEqual(@as(usize, 2), reg.all().len);
    try testing.expect(reg.find("oddjobz") != null);
    try testing.expect(reg.find("betterment") != null);
    try testing.expect(reg.find("jambox") == null);

    const out = try reg.find("oddjobz").?.submit(reg.find("oddjobz").?.ctx, testing.allocator, "{}");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{\"ns\":1}", out);
}

```
