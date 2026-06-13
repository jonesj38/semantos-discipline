---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/ratify_submit_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.217036+00:00
---

# runtime/semantos-brain/src/ratify_submit_handler.zig

```zig
//! Generic ratify submit — C4 PR-J5, the namespace-routed ratification primitive.
//!
//! The brain owns the ratify VERB; the per-cartridge graph construction +
//! idempotency live in a registered builder (ratify_builder_registry). This
//! handler is the thin router: resolve the builder for the requested namespace,
//! hand it the raw params, return its wire result blob.
//!
//! Wire surface: `ratify.submit { namespace, proposal_id, sir_program,
//! payload_hint }`. `oddjobz.ratify_proposal` remains as a back-compat alias
//! (namespace = "oddjobz"). The result blob shape is owned by the builder (for
//! oddjobz: `{proposal_id, cellIds:{site,customers,job,attachments}, persistedAt}`).

const std = @import("std");
const ratify_builder_registry = @import("ratify_builder_registry");

pub const RatifyError = error{
    /// No builder registered for the requested namespace.
    no_builder,
    /// The builder rejected the params / graph build (the builder maps its own
    /// domain errors; the wire layer surfaces a generic failure).
    builder_failed,
    out_of_memory,
};

pub const Handler = struct {
    registry: *const ratify_builder_registry.RatifyBuilderRegistry,

    /// Resolve the builder for `namespace` and submit `params_json` (the full
    /// `{proposal_id, sir_program, payload_hint}` object). Returns the builder's
    /// wire result blob (owned; caller frees).
    pub fn submit(
        self: *const Handler,
        allocator: std.mem.Allocator,
        namespace: []const u8,
        params_json: []const u8,
    ) RatifyError![]u8 {
        const builder = self.registry.find(namespace) orelse return RatifyError.no_builder;
        return builder.submit(builder.ctx, allocator, params_json) catch |err| switch (err) {
            error.OutOfMemory => RatifyError.out_of_memory,
            else => RatifyError.builder_failed,
        };
    }
};

// ── inline tests ──────────────────────────────────────────────────────────

const testing = std.testing;

const FakeBuilder = struct {
    body: []const u8,
    fail: bool = false,
    fn submit(ctx: *anyopaque, allocator: std.mem.Allocator, _: []const u8) anyerror![]u8 {
        const self: *FakeBuilder = @ptrCast(@alignCast(ctx));
        if (self.fail) return error.Whatever;
        return allocator.dupe(u8, self.body);
    }
};

test "submit: routes by namespace, unknown ns ⇒ no_builder" {
    var reg: ratify_builder_registry.RatifyBuilderRegistry = .{};
    var oj = FakeBuilder{ .body = "{\"ok\":true}" };
    reg.add(.{ .namespace = "oddjobz", .label = "graph", .ctx = &oj, .submit = FakeBuilder.submit });

    const h = Handler{ .registry = &reg };
    const alloc = testing.allocator;

    const out = try h.submit(alloc, "oddjobz", "{}");
    defer alloc.free(out);
    try testing.expectEqualStrings("{\"ok\":true}", out);

    try testing.expectError(RatifyError.no_builder, h.submit(alloc, "jambox", "{}"));
}

test "submit: builder error ⇒ builder_failed" {
    var reg: ratify_builder_registry.RatifyBuilderRegistry = .{};
    var oj = FakeBuilder{ .body = "", .fail = true };
    reg.add(.{ .namespace = "oddjobz", .label = "graph", .ctx = &oj, .submit = FakeBuilder.submit });
    const h = Handler{ .registry = &reg };
    try testing.expectError(RatifyError.builder_failed, h.submit(testing.allocator, "oddjobz", "{}"));
}

```
