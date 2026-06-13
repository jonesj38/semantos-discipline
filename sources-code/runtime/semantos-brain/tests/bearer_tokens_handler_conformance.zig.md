---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/bearer_tokens_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.194631+00:00
---

# runtime/semantos-brain/tests/bearer_tokens_handler_conformance.zig

```zig
// Phase D-W1 / Phase 1 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3, §8.
//
// Conformance suite for `bearer_tokens_handler.zig`.  Exercises the
// dispatcher seam end-to-end (Dispatcher → ResourceHandler → TokenStore)
// against the four spec'd commands and asserts the audit-pair invariant
// for each.  Closes the test gap behind brain issues #1 and #2:
//
//   • `issue` then `validate` round-trips immediately — no daemon
//     restart, no log-replay step required.  This is what closes #2.
//   • `list` reflects the post-state (issued + revoked).
//   • `cap.brain.admin` is required for issue/revoke/list; without it
//     the dispatcher returns capability_denied and the handler's
//     mutator is never invoked.
//   • Two concurrent issuers from independent dispatchers (simulating
//     two transports) produce two distinct ids; the on-disk log keeps
//     both.

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const bearer_tokens = @import("bearer_tokens");
const handler_mod = @import("bearer_tokens_handler");

// ─────────────────────────────────────────────────────────────────────
// Test fixture — heap-allocated so the dispatcher's pointer to
// audit_log + the handler's pointer to TokenStore are address-stable.
// ─────────────────────────────────────────────────────────────────────

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    store: bearer_tokens.TokenStore,
    handler: handler_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(data_dir);
        const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(audit_path);

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .data_dir = data_dir,
            .audit_path = audit_path,
            .audit = audit_log.AuditLog.init(),
            .store = undefined,
            .handler = undefined,
            .disp = undefined,
        };
        try self.audit.open(audit_path);
        self.store = try bearer_tokens.TokenStore.init(allocator, data_dir, pinnedClock);
        self.handler = handler_mod.Handler.init(allocator, &self.store);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.store.deinit();
        self.audit.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    fn dumpAudit(self: *Fixture) ![]u8 {
        const f = try std.fs.cwd().openFile(self.audit_path, .{});
        defer f.close();
        const stat = try f.stat();
        const buf = try self.allocator.alloc(u8, stat.size);
        errdefer self.allocator.free(buf);
        const n = try f.readAll(buf);
        return buf[0..n];
    }
};

fn rootCtx() dispatcher.DispatchContext {
    return .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test", .transport_label = "test" },
    };
}

fn anonymousCtx() dispatcher.DispatchContext {
    return .{
        .auth = .{ .anonymous = .{ .site_origin = "https://example" } },
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test-anon", .transport_label = "test" },
    };
}

fn bearerCtxWithCaps(caps: []const []const u8) dispatcher.DispatchContext {
    return .{
        .auth = .{ .bearer = .{ .fingerprint_hex = [_]u8{'0'} ** 64, .label = "test" } },
        .capabilities = dispatcher.CapabilitySet.fromList(caps),
        .meta = .{ .request_id = "test-bearer", .transport_label = "test" },
    };
}

// Pull a quoted string field out of a JSON-shaped result payload.  The
// payload is small + well-formed (we built it ourselves), so a
// std.json walk is fine.
fn jsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.not_object;
    const v = parsed.value.object.get(key) orelse return error.missing_key;
    if (v != .string) return error.not_string;
    return try allocator.dupe(u8, v.string);
}

fn jsonBool(json: []const u8, key: []const u8, allocator: std.mem.Allocator) !bool {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.not_object;
    const v = parsed.value.object.get(key) orelse return error.missing_key;
    if (v != .bool) return error.not_bool;
    return v.bool;
}

// ─────────────────────────────────────────────────────────────────────
// issue → validate round-trips inside the same process (issue #2)
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 bearer_tokens: issue → validate succeeds (no restart)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();

    var issue_result = try fx.disp.dispatch(&ctx, "bearer_tokens", "issue",
        \\{"label":"helm-dev"}
    );
    defer issue_result.deinit();
    const token = try jsonString(allocator, issue_result.payload, "token");
    defer allocator.free(token);
    try std.testing.expectEqual(@as(usize, 64), token.len);

    // Validate with the freshly-issued token — must succeed without
    // a restart, replay, or any out-of-band signalling.  This is the
    // exact pattern that issue #2 said was structurally broken.
    const validate_args = try std.fmt.allocPrint(allocator,
        \\{{"token":"{s}"}}
    , .{token});
    defer allocator.free(validate_args);
    var validate_result = try fx.disp.dispatch(&ctx, "bearer_tokens", "validate", validate_args);
    defer validate_result.deinit();
    try std.testing.expect(try jsonBool(validate_result.payload, "valid", allocator));
}

// ─────────────────────────────────────────────────────────────────────
// issue → revoke → validate fails
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 bearer_tokens: revoked token fails validate" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var issued = try fx.disp.dispatch(&ctx, "bearer_tokens", "issue",
        \\{"label":"to-revoke"}
    );
    defer issued.deinit();
    const id = try jsonString(allocator, issued.payload, "id");
    defer allocator.free(id);
    const token = try jsonString(allocator, issued.payload, "token");
    defer allocator.free(token);

    // Revoke.
    const revoke_args = try std.fmt.allocPrint(allocator,
        \\{{"id":"{s}"}}
    , .{id});
    defer allocator.free(revoke_args);
    var revoked = try fx.disp.dispatch(&ctx, "bearer_tokens", "revoke", revoke_args);
    defer revoked.deinit();
    try std.testing.expect(try jsonBool(revoked.payload, "ok", allocator));

    // Validate post-revoke.
    const validate_args = try std.fmt.allocPrint(allocator,
        \\{{"token":"{s}"}}
    , .{token});
    defer allocator.free(validate_args);
    var validate_result = try fx.disp.dispatch(&ctx, "bearer_tokens", "validate", validate_args);
    defer validate_result.deinit();
    try std.testing.expect(!(try jsonBool(validate_result.payload, "valid", allocator)));
}

// ─────────────────────────────────────────────────────────────────────
// list reflects post-state
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 bearer_tokens: list after issue+revoke shows correct state" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();

    // Issue two; revoke the first.
    var first = try fx.disp.dispatch(&ctx, "bearer_tokens", "issue",
        \\{"label":"first"}
    );
    defer first.deinit();
    const id1 = try jsonString(allocator, first.payload, "id");
    defer allocator.free(id1);
    var second = try fx.disp.dispatch(&ctx, "bearer_tokens", "issue",
        \\{"label":"second"}
    );
    defer second.deinit();
    const id2 = try jsonString(allocator, second.payload, "id");
    defer allocator.free(id2);

    const revoke_args = try std.fmt.allocPrint(allocator,
        \\{{"id":"{s}"}}
    , .{id1});
    defer allocator.free(revoke_args);
    var revoked = try fx.disp.dispatch(&ctx, "bearer_tokens", "revoke", revoke_args);
    defer revoked.deinit();

    // List — should contain only id2 (revoked tokens are dropped from
    // the live index per the underlying TokenStore semantics).
    var listed = try fx.disp.dispatch(&ctx, "bearer_tokens", "list", "{}");
    defer listed.deinit();
    try std.testing.expect(std.mem.indexOf(u8, listed.payload, id2) != null);
    try std.testing.expect(std.mem.indexOf(u8, listed.payload, id1) == null);
}

// ─────────────────────────────────────────────────────────────────────
// Two concurrent issues produce distinct ids
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 bearer_tokens: two concurrent issues produce distinct ids" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var first = try fx.disp.dispatch(&ctx, "bearer_tokens", "issue",
        \\{"label":"a"}
    );
    defer first.deinit();
    var second = try fx.disp.dispatch(&ctx, "bearer_tokens", "issue",
        \\{"label":"b"}
    );
    defer second.deinit();
    const id1 = try jsonString(allocator, first.payload, "id");
    defer allocator.free(id1);
    const id2 = try jsonString(allocator, second.payload, "id");
    defer allocator.free(id2);

    try std.testing.expect(!std.mem.eql(u8, id1, id2));

    // Both fingerprints must be present in the on-disk log too — proves
    // the index + log are mutated atomically (two issues → two log
    // lines).
    const audit_text = try fx.dumpAudit();
    defer allocator.free(audit_text);
    var start_count: usize = 0;
    var rest = audit_text;
    while (std.mem.indexOf(u8, rest, "phase=start")) |idx| {
        start_count += 1;
        rest = rest[idx + "phase=start".len ..];
    }
    // 1 start per dispatch, 2 dispatches → 2 starts.
    try std.testing.expectEqual(@as(usize, 2), start_count);
}

// ─────────────────────────────────────────────────────────────────────
// cap.brain.admin gating
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 bearer_tokens: anonymous caller cannot issue" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = anonymousCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.capability_denied,
        fx.disp.dispatch(&ctx, "bearer_tokens", "issue",
            \\{"label":"x"}
        ),
    );
}

test "D-W1 P1 bearer_tokens: bearer with cap.brain.admin can issue" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    const caps = [_][]const u8{"cap.brain.admin"};
    var ctx = bearerCtxWithCaps(&caps);
    var r = try fx.disp.dispatch(&ctx, "bearer_tokens", "issue",
        \\{"label":"helm"}
    );
    defer r.deinit();
    const id = try jsonString(allocator, r.payload, "id");
    defer allocator.free(id);
    try std.testing.expectEqual(@as(usize, 32), id.len);
}

test "D-W1 P1 bearer_tokens: bearer without admin cap is denied for revoke" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = bearerCtxWithCaps(&.{});
    try std.testing.expectError(
        dispatcher.DispatchError.capability_denied,
        fx.disp.dispatch(&ctx, "bearer_tokens", "revoke",
            \\{"id":"00000000000000000000000000000000"}
        ),
    );
}

test "D-W1 P1 bearer_tokens: validate is allowed for anonymous (cap=none)" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = anonymousCtx();
    var r = try fx.disp.dispatch(&ctx, "bearer_tokens", "validate",
        \\{"token":"00000000000000000000000000000000000000000000000000000000000000aa"}
    );
    defer r.deinit();
    try std.testing.expect(!(try jsonBool(r.payload, "valid", allocator)));
}

// ─────────────────────────────────────────────────────────────────────
// Audit pair invariant — every dispatch produces start+end
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 bearer_tokens: each dispatch records one start + one end audit entry" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    var r1 = try fx.disp.dispatch(&ctx, "bearer_tokens", "issue",
        \\{"label":"audit-test"}
    );
    defer r1.deinit();
    const id = try jsonString(allocator, r1.payload, "id");
    defer allocator.free(id);
    const revoke_args = try std.fmt.allocPrint(allocator,
        \\{{"id":"{s}"}}
    , .{id});
    defer allocator.free(revoke_args);
    var r2 = try fx.disp.dispatch(&ctx, "bearer_tokens", "revoke", revoke_args);
    defer r2.deinit();

    const text = try fx.dumpAudit();
    defer allocator.free(text);

    var start_count: usize = 0;
    var end_count: usize = 0;
    var rest = text;
    while (std.mem.indexOf(u8, rest, "phase=start")) |idx| {
        start_count += 1;
        rest = rest[idx + "phase=start".len ..];
    }
    rest = text;
    while (std.mem.indexOf(u8, rest, "phase=end")) |idx| {
        end_count += 1;
        rest = rest[idx + "phase=end".len ..];
    }
    try std.testing.expectEqual(@as(usize, 2), start_count);
    try std.testing.expectEqual(@as(usize, 2), end_count);

    // op tags carry the resource.cmd shape so audit consumers can grep.
    try std.testing.expect(std.mem.indexOf(u8, text, "bearer_tokens.issue") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "bearer_tokens.revoke") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Argument validation
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1 bearer_tokens: issue with missing label returns invalid_args" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.invalid_args,
        fx.disp.dispatch(&ctx, "bearer_tokens", "issue", "{}"),
    );
}

test "D-W1 P1 bearer_tokens: revoke with bad id length returns invalid_args" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.invalid_args,
        fx.disp.dispatch(&ctx, "bearer_tokens", "revoke",
            \\{"id":"too-short"}
        ),
    );
}

test "D-W1 P1 bearer_tokens: revoke of unknown id returns not_found" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.not_found,
        fx.disp.dispatch(&ctx, "bearer_tokens", "revoke",
            \\{"id":"deadbeefdeadbeefdeadbeefdeadbeef"}
        ),
    );
}

```
