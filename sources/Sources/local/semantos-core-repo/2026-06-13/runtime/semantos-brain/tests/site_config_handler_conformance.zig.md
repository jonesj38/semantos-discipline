---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/site_config_handler_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.190403+00:00
---

# runtime/semantos-brain/tests/site_config_handler_conformance.zig

```zig
// D-O5.followup-5 — site_config_handler conformance suite.
//
// Mirrors `sites_handler_conformance.zig`: per-command happy path +
// cap-deny + typed-error path + atomicity invariant (a failing write
// never replaces the existing on-disk file).
//
// Six tests cover the spec'd surface:
//   1. read happy path — round-trip of a known site config
//   2. write happy path — full-blob replace with a valid config
//   3. write with invalid config returns validation_failed
//   4. write atomicity — failed write leaves on-disk file unchanged
//   5. write to non-existent domain returns not_found
//   6. cap-gating — anonymous caller cannot read or write

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const site_config = @import("site_config");
const handler_mod = @import("site_config_handler");

const SAMPLE_CONFIG_VALID =
    \\{
    \\  "site": {
    \\    "domain": "example.test",
    \\    "content_root": "./public",
    \\    "listen_port": 8080
    \\  },
    \\  "routes": {
    \\    "/": { "type": "static", "file": "index.html", "public": true }
    \\  }
    \\}
;

const SAMPLE_CONFIG_VALID_PORT_9000 =
    \\{
    \\  "site": {
    \\    "domain": "example.test",
    \\    "content_root": "./public",
    \\    "listen_port": 9000
    \\  },
    \\  "routes": {
    \\    "/": { "type": "static", "file": "index.html", "public": true },
    \\    "/about": { "type": "static", "file": "about.html", "public": true }
    \\  }
    \\}
;

const SAMPLE_CONFIG_INVALID_ROUTE_TYPE =
    \\{
    \\  "site": {
    \\    "domain": "example.test",
    \\    "content_root": "./public",
    \\    "listen_port": 8080
    \\  },
    \\  "routes": {
    \\    "/": { "type": "not_a_real_type", "file": "index.html" }
    \\  }
    \\}
;

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    sites_dir: []u8,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    handler: handler_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const sites_dir = try std.fs.path.join(allocator, &.{ real, "sites" });
        errdefer allocator.free(sites_dir);
        std.fs.cwd().makePath(sites_dir) catch {};
        const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(audit_path);

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .sites_dir = sites_dir,
            .audit_path = audit_path,
            .audit = audit_log.AuditLog.init(),
            .handler = undefined,
            .disp = undefined,
        };
        try self.audit.open(audit_path);
        self.handler = handler_mod.Handler.init(allocator, self.sites_dir);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.audit.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.free(self.sites_dir);
        self.allocator.destroy(self);
    }

    /// Seed `<sites_dir>/<domain>/site.json` with the given JSON
    /// contents.  Mirrors what `sites_handler.init` would do, but
    /// keeps this conformance suite independent from sites_handler so
    /// either handler can churn on its own.
    fn seedDomain(self: *Fixture, domain: []const u8, json: []const u8) !void {
        const dir = try std.fs.path.join(self.allocator, &.{ self.sites_dir, domain });
        defer self.allocator.free(dir);
        std.fs.cwd().makePath(dir) catch {};
        const file_path = try std.fs.path.join(self.allocator, &.{ dir, "site.json" });
        defer self.allocator.free(file_path);
        const f = try std.fs.cwd().createFile(file_path, .{});
        defer f.close();
        try f.writeAll(json);
    }

    fn readDomainFile(self: *Fixture, domain: []const u8) ![]u8 {
        const file_path = try std.fs.path.join(self.allocator, &.{ self.sites_dir, domain, "site.json" });
        defer self.allocator.free(file_path);
        const f = try std.fs.cwd().openFile(file_path, .{});
        defer f.close();
        const stat = try f.stat();
        const buf = try self.allocator.alloc(u8, stat.size);
        _ = try f.readAll(buf);
        return buf;
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

// ─────────────────────────────────────────────────────────────────────
// Read happy path
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-5 site_config: read returns the on-disk JSON verbatim" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedDomain("example.test", SAMPLE_CONFIG_VALID);

    var ctx = rootCtx();
    var result = try fx.disp.dispatch(&ctx, "site_config", "read",
        \\{"domain":"example.test"}
    );
    defer result.deinit();
    // The payload is `{"domain":"...","json":"<escaped raw>",...}`.
    // Assert it carries the domain marker + a snippet of the raw body
    // (post-JSON-string-encoding the literal `"listen_port"` becomes
    // `\"listen_port\"`).
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "\"domain\":\"example.test\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "\\\"listen_port\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "\"size\":") != null);
}

test "D-O5.followup-5 site_config: read of unknown domain returns not_found" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.not_found,
        fx.disp.dispatch(&ctx, "site_config", "read",
            \\{"domain":"missing.test"}
        ),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Write happy path
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-5 site_config: write replaces on-disk JSON, read sees it" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedDomain("example.test", SAMPLE_CONFIG_VALID);

    // Build the JSON envelope by hand — the inner `json` field is the
    // raw site config blob, JSON-string-encoded.  std.json.Stringify
    // gives us the right escapes.
    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(allocator);
    try args_buf.appendSlice(allocator, "{\"domain\":\"example.test\",\"json\":");
    const encoded = try std.json.Stringify.valueAlloc(allocator, SAMPLE_CONFIG_VALID_PORT_9000, .{});
    defer allocator.free(encoded);
    try args_buf.appendSlice(allocator, encoded);
    try args_buf.append(allocator, '}');

    var ctx = rootCtx();
    var result = try fx.disp.dispatch(&ctx, "site_config", "write", args_buf.items);
    defer result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "\"written_at\":") != null);

    // Confirm the on-disk bytes flipped.
    const on_disk = try fx.readDomainFile("example.test");
    defer allocator.free(on_disk);
    try std.testing.expect(std.mem.indexOf(u8, on_disk, "9000") != null);
    try std.testing.expect(std.mem.indexOf(u8, on_disk, "/about") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Write rejection: invalid config
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-5 site_config: write of malformed JSON returns validation_failed" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedDomain("example.test", SAMPLE_CONFIG_VALID);

    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(allocator);
    try args_buf.appendSlice(allocator, "{\"domain\":\"example.test\",\"json\":\"{ not valid json\"}");

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.validation_failed,
        fx.disp.dispatch(&ctx, "site_config", "write", args_buf.items),
    );
}

test "D-O5.followup-5 site_config: write of unknown route type returns validation_failed" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedDomain("example.test", SAMPLE_CONFIG_VALID);

    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(allocator);
    try args_buf.appendSlice(allocator, "{\"domain\":\"example.test\",\"json\":");
    const encoded = try std.json.Stringify.valueAlloc(allocator, SAMPLE_CONFIG_INVALID_ROUTE_TYPE, .{});
    defer allocator.free(encoded);
    try args_buf.appendSlice(allocator, encoded);
    try args_buf.append(allocator, '}');

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.validation_failed,
        fx.disp.dispatch(&ctx, "site_config", "write", args_buf.items),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Write atomicity: a rejected payload leaves the on-disk file alone
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-5 site_config: rejected write leaves on-disk file unchanged" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedDomain("example.test", SAMPLE_CONFIG_VALID);

    const before = try fx.readDomainFile("example.test");
    defer allocator.free(before);

    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(allocator);
    try args_buf.appendSlice(allocator, "{\"domain\":\"example.test\",\"json\":");
    const encoded = try std.json.Stringify.valueAlloc(allocator, SAMPLE_CONFIG_INVALID_ROUTE_TYPE, .{});
    defer allocator.free(encoded);
    try args_buf.appendSlice(allocator, encoded);
    try args_buf.append(allocator, '}');

    var ctx = rootCtx();
    _ = fx.disp.dispatch(&ctx, "site_config", "write", args_buf.items) catch {};

    const after = try fx.readDomainFile("example.test");
    defer allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);

    // No `.tmp` sidecar lingering either — the write-to-temp file
    // gets cleaned up on the rename failure path.  We don't assert
    // its absence here (writeFileAtomic only renames after a
    // successful tmp-write; failure mode would leave a stale tmp,
    // which is acceptable).
}

// ─────────────────────────────────────────────────────────────────────
// Write dry-run: validates without touching disk
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-5 site_config: write dry_run validates without touching disk" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedDomain("example.test", SAMPLE_CONFIG_VALID);

    const before = try fx.readDomainFile("example.test");
    defer allocator.free(before);

    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(allocator);
    try args_buf.appendSlice(allocator, "{\"domain\":\"example.test\",\"dry_run\":true,\"json\":");
    const encoded = try std.json.Stringify.valueAlloc(allocator, SAMPLE_CONFIG_VALID_PORT_9000, .{});
    defer allocator.free(encoded);
    try args_buf.appendSlice(allocator, encoded);
    try args_buf.append(allocator, '}');

    var ctx = rootCtx();
    var result = try fx.disp.dispatch(&ctx, "site_config", "write", args_buf.items);
    defer result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.payload, "\"dry_run\":true") != null);

    const after = try fx.readDomainFile("example.test");
    defer allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

// ─────────────────────────────────────────────────────────────────────
// not_found — write to a domain whose directory doesn't exist
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-5 site_config: write to unknown domain returns not_found" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(allocator);
    try args_buf.appendSlice(allocator, "{\"domain\":\"never-initialised.test\",\"json\":");
    const encoded = try std.json.Stringify.valueAlloc(allocator, SAMPLE_CONFIG_VALID, .{});
    defer allocator.free(encoded);
    try args_buf.appendSlice(allocator, encoded);
    try args_buf.append(allocator, '}');

    var ctx = rootCtx();
    try std.testing.expectError(
        handler_mod.HandlerError.not_found,
        fx.disp.dispatch(&ctx, "site_config", "write", args_buf.items),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Capability gating
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-5 site_config: anonymous caller cannot read" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedDomain("example.test", SAMPLE_CONFIG_VALID);

    var ctx = anonymousCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.capability_denied,
        fx.disp.dispatch(&ctx, "site_config", "read",
            \\{"domain":"example.test"}
        ),
    );
}

test "D-O5.followup-5 site_config: anonymous caller cannot write" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();
    try fx.seedDomain("example.test", SAMPLE_CONFIG_VALID);

    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(allocator);
    try args_buf.appendSlice(allocator, "{\"domain\":\"example.test\",\"json\":");
    const encoded = try std.json.Stringify.valueAlloc(allocator, SAMPLE_CONFIG_VALID_PORT_9000, .{});
    defer allocator.free(encoded);
    try args_buf.appendSlice(allocator, encoded);
    try args_buf.append(allocator, '}');

    var ctx = anonymousCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.capability_denied,
        fx.disp.dispatch(&ctx, "site_config", "write", args_buf.items),
    );
}

// ─────────────────────────────────────────────────────────────────────
// Unknown command
// ─────────────────────────────────────────────────────────────────────

test "D-O5.followup-5 site_config: unknown command returns unknown_command" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    try std.testing.expectError(
        dispatcher.DispatchError.unknown_command,
        fx.disp.dispatch(&ctx, "site_config", "lol", "{}"),
    );
}

```
