---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/info_http_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.198801+00:00
---

# runtime/semantos-brain/tests/info_http_test.zig

```zig
// D-O5m.followup-6 Phase 2 — `GET /api/v1/info` conformance.
//
// Drives info_http.handle directly against a real bearer-token store
// so the bearer gate runs end-to-end.  Three fixtures: bearer required
// (no header → 401), mesh configured (full body), mesh not configured
// (shard_proxy_endpoint = null in body).
//
// Reference: src/info_http.zig (the endpoint under test);
// docs/canon/glossary.md `info-endpoint`.

const std = @import("std");
const bearer_tokens = @import("bearer_tokens");
const info_http = @import("info_http");
const tenant_manifest = @import("tenant_manifest");

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Setup = struct {
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    data_dir: []u8,
    tokens: bearer_tokens.TokenStore,
    bearer_hex: [64]u8,

    fn init(allocator: std.mem.Allocator) !*Setup {
        const self = try allocator.create(Setup);
        self.allocator = allocator;
        self.tmp = std.testing.tmpDir(.{});
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.data_dir = try allocator.dupe(u8, real);
        self.tokens = try bearer_tokens.TokenStore.init(allocator, self.data_dir, pinnedClock);
        const issued = try self.tokens.issue("info-test", 0);
        var bh: [64]u8 = undefined;
        bearer_tokens.hexEncode(&issued.token, &bh);
        self.bearer_hex = bh;
        return self;
    }

    fn deinit(self: *Setup) void {
        self.tokens.deinit();
        self.allocator.free(self.data_dir);
        self.tmp.cleanup();
        self.allocator.destroy(self);
    }
};

test "GET /api/v1/info: missing bearer returns 401" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
    };
    var result = try info_http.handle(&acceptor, null);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.unauthorized, result.status);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "unauthorised") != null);
}

test "GET /api/v1/info: bad bearer returns 401" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
    };
    const bogus_bearer = "0" ** 64;
    var result = try info_http.handle(&acceptor, bogus_bearer);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.unauthorized, result.status);
}

test "GET /api/v1/info: mesh-configured response carries shard-proxy URL + group" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
        .shard_proxy_endpoint = "https://shard-proxy.example.com",
        .shard_group_id = "tenant-acme",
        .brain_pin_cert_id = "abcdef0123456789abcdef0123456789",
        .brain_pin_pubkey_hex = "02" ++ ("aa" ** 32),
        .server_version = "brain 0.1.0",
    };
    var result = try info_http.handle(&acceptor, setup.bearer_hex[0..]);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.ok, result.status);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "https://shard-proxy.example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "tenant-acme") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "brain 0.1.0") != null);
    // brain pin fields surface through.
    try std.testing.expect(std.mem.indexOf(u8, result.body, "abcdef0123456789abcdef0123456789") != null);
}

test "GET /api/v1/info: mesh-not-configured response has shard_proxy_endpoint = null" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
        .shard_proxy_endpoint = "",
        .shard_group_id = "",
        .brain_pin_cert_id = "abcdef0123456789abcdef0123456789",
        .brain_pin_pubkey_hex = "02" ++ ("aa" ** 32),
        .server_version = "brain 0.1.0",
    };
    var result = try info_http.handle(&acceptor, setup.bearer_hex[0..]);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.ok, result.status);
    // Wire shape: `"shard_proxy_endpoint":null` (literal JSON null).
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"shard_proxy_endpoint\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"shard_group_id\":\"\"") != null);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-6 — `theme` block in /api/v1/info response
// ─────────────────────────────────────────────────────────────────────

test "GET /api/v1/info: response includes theme block with default values when unset" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    // Acceptor with no theme set → defaults substituted inline.
    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
        .brain_pin_cert_id = "abcdef0123456789abcdef0123456789",
        .brain_pin_pubkey_hex = "02" ++ ("aa" ** 32),
        .server_version = "brain 0.1.0",
    };
    var result = try info_http.handle(&acceptor, setup.bearer_hex[0..]);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.ok, result.status);

    // Default primary + accent inline (clients don't ship their own).
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"theme\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"primary_hex\":\"" ++ tenant_manifest.THEME_DEFAULT_PRIMARY ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"accent_hex\":\"" ++ tenant_manifest.THEME_DEFAULT_ACCENT ++ "\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"logo_url\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"font_family\":\"system\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"mode\":\"auto\"") != null);
}

test "GET /api/v1/info: response carries operator-set theme primary, accent, logo, font, mode" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
        .brain_pin_cert_id = "abcdef0123456789abcdef0123456789",
        .brain_pin_pubkey_hex = "02" ++ ("aa" ** 32),
        .server_version = "brain 0.1.0",
        .theme = .{
            .primary_hex = "#FF6F61",
            .accent_hex = "#2EC4B6",
            .logo_url = "/branding/acme.svg",
            .font_family = "serif",
            .mode = "dark",
        },
    };
    var result = try info_http.handle(&acceptor, setup.bearer_hex[0..]);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.ok, result.status);

    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"primary_hex\":\"#FF6F61\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"accent_hex\":\"#2EC4B6\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"logo_url\":\"/branding/acme.svg\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"font_family\":\"serif\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"mode\":\"dark\"") != null);
}

test "GET /api/v1/info: theme.logo_url is JSON null when no logo is configured" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
        .brain_pin_cert_id = "abcdef0123456789abcdef0123456789",
        .brain_pin_pubkey_hex = "02" ++ ("aa" ** 32),
        .server_version = "brain 0.1.0",
        .theme = .{
            .primary_hex = "#000000",
            .accent_hex = "#FFFFFF",
            .logo_url = "", // unset → JSON null in body
            .font_family = "mono",
            .mode = "light",
        },
    };
    var result = try info_http.handle(&acceptor, setup.bearer_hex[0..]);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.ok, result.status);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"logo_url\":null") != null);
    // No string-quoted logo_url value should appear.
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"logo_url\":\"") == null);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5.followup-8 — `hat` block in /api/v1/info response
// ─────────────────────────────────────────────────────────────────────

test "GET /api/v1/info: response includes hat block with bearer label + id" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
        .brain_pin_cert_id = "abcdef0123456789abcdef0123456789",
        .brain_pin_pubkey_hex = "02" ++ ("aa" ** 32),
        .server_version = "brain 0.1.0",
    };
    var result = try info_http.handle(&acceptor, setup.bearer_hex[0..]);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.ok, result.status);

    // The hat block exists.
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"hat\":") != null);
    // The hat name is the bearer's TokenRecord label ("info-test"
    // — set up by Setup.init via setup.tokens.issue("info-test", 0)).
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"name\":\"info-test\"") != null);
    // The hat id is a 32-hex string (the bearer's TokenRecord id).
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"id\":\"") != null);
    // cert_id is empty for today's bearer-only path (D-O11 will
    // wire bearer→cert linkage; this assertion stays as the wire
    // contract until then).
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"cert_id\":\"\"") != null);
    // SH14 / D12 — the hat block surfaces the bearer's role (operator default;
    // no cartridges set in this fixture, so this is the hat's role).
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"role\":\"operator\"") != null);
}

test "GET /api/v1/info: hat block surfaces operator-supplied bearer label" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    // Issue a second bearer with an operator-friendly hat name and
    // verify it round-trips through the `/api/v1/info` response.
    const issued = try setup.tokens.issue("Todd (tradie)", 0);
    var bearer_hex: [64]u8 = undefined;
    bearer_tokens.hexEncode(&issued.token, &bearer_hex);

    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
        .brain_pin_cert_id = "abcdef0123456789abcdef0123456789",
        .brain_pin_pubkey_hex = "02" ++ ("aa" ** 32),
        .server_version = "brain 0.1.0",
    };
    var result = try info_http.handle(&acceptor, bearer_hex[0..]);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.ok, result.status);

    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"name\":\"Todd (tradie)\"") != null);
}

test "GET /api/v1/info: 401 response carries no hat block" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
    };
    // Anonymous request — no bearer.  401 + plain `{"error":...}`
    // body, no hat block leaked.
    var result = try info_http.handle(&acceptor, null);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.unauthorized, result.status);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"hat\":") == null);
}

// ─────────────────────────────────────────────────────────────────────
// SH1-B (svelte-helm matrix / DECISION D9) — cartridges[] carry the
// declarative UI layer (surfacingMode + verbs[]) for the web helm.
// ─────────────────────────────────────────────────────────────────────

test "GET /api/v1/info: cartridges[] carry surfacingMode + verbs (SH1-B)" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    const verbs = [_]info_http.UiVerb{
        .{ .modal = "do", .label = "New job", .intent_type = "oddjobz.job.create", .subtitle = "log a new job", .icon = "build" },
        .{ .modal = "find", .label = "Find job", .intent_type = "oddjobz.job.find" },
        // SH14 / D12 — an admin-scoped managerial verb.
        .{ .modal = "do", .label = "Edit website", .intent_type = "site.edit", .role = "admin" },
    };
    const carts = [_]info_http.CartridgeInfo{
        .{ .id = "oddjobz", .role = "experience", .experience_package = "oddjobz_experience", .surfacing_mode = "default", .ui_verbs = &verbs },
    };
    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
        .cartridges = &carts,
    };
    var result = try info_http.handle(&acceptor, setup.bearer_hex[0..]);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.ok, result.status);
    // Declarative UI fields surface on the cartridge entry.
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"surfacingMode\":\"default\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"verbs\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"modal\":\"do\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"intentType\":\"oddjobz.job.create\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"label\":\"Find job\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"icon\":\"build\"") != null);
    // SH14 / D12 — per-verb role emitted (operator default + explicit admin).
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"role\":\"operator\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"role\":\"admin\"") != null);
}

test "GET /api/v1/info: pure-shell (no cartridges) emits empty cartridges[] (SH1-B)" {
    const allocator = std.testing.allocator;
    const setup = try Setup.init(allocator);
    defer setup.deinit();

    // No .cartridges set → the always-on brain with an empty extensions/
    // dir. The web helm must render the neutral shell from this.
    const acceptor = info_http.Acceptor{
        .allocator = allocator,
        .bearer_tokens = &setup.tokens,
    };
    var result = try info_http.handle(&acceptor, setup.bearer_hex[0..]);
    defer result.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.ok, result.status);
    try std.testing.expect(std.mem.indexOf(u8, result.body, "\"cartridges\":[]") != null);
}

```
