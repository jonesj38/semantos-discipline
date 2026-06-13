---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/site_config_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.208637+00:00
---

# runtime/semantos-brain/tests/site_config_conformance.zig

```zig
// Phase WSITE1 — site config conformance tests.

const std = @import("std");
const site_config = @import("site_config");

test "WSITE1 config: default template parses cleanly" {
    const tmpl = try site_config.defaultJsonTemplate(std.testing.allocator, "example.com");
    defer std.testing.allocator.free(tmpl);
    var cfg = try site_config.parseJson(std.testing.allocator, tmpl);
    defer cfg.deinit();
    try std.testing.expectEqualStrings("example.com", cfg.domain);
    try std.testing.expectEqualStrings("./public", cfg.content_root);
    try std.testing.expectEqual(@as(u16, 8080), cfg.listen_port);
    try std.testing.expectEqual(@as(usize, 1), cfg.routes.len);
    try std.testing.expectEqualStrings("/", cfg.routes[0].path);
    try std.testing.expectEqual(site_config.RouteType.static, cfg.routes[0].kind);
    try std.testing.expectEqualStrings("index.html", cfg.routes[0].file);
    try std.testing.expectEqual(site_config.AuthKind.public, cfg.routes[0].auth);
}

test "WSITE1 config: parses dynamic + auth-gated routes" {
    const json =
        \\{
        \\  "site": { "domain": "x.test", "content_root": "./pub", "listen_port": 8081 },
        \\  "routes": {
        \\    "/api/play": {
        \\      "type": "dynamic",
        \\      "handler": "game.wasm",
        \\      "auth": "identity_required"
        \\    },
        \\    "/premium": {
        \\      "type": "static",
        \\      "file": "premium.html",
        \\      "auth": "payment_required",
        \\      "price_sats": 5000
        \\    }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    try std.testing.expectEqual(@as(u16, 8081), cfg.listen_port);
    try std.testing.expectEqual(@as(usize, 2), cfg.routes.len);

    const play = cfg.routeFor("/api/play") orelse return error.TestFailed;
    try std.testing.expectEqual(site_config.RouteType.dynamic, play.kind);
    try std.testing.expectEqualStrings("game.wasm", play.handler);
    try std.testing.expectEqual(site_config.AuthKind.identity_required, play.auth);

    const premium = cfg.routeFor("/premium") orelse return error.TestFailed;
    try std.testing.expectEqual(site_config.AuthKind.payment_required, premium.auth);
    try std.testing.expectEqual(@as(u64, 5000), premium.price_sats);
}

test "WSITE5 config: parses per-route output_basket override" {
    const json =
        \\{
        \\  "site": { "domain": "x.test", "content_root": "./pub", "listen_port": 8081,
        \\            "payment_recipient": "020202020202020202020202020202020202020202020202020202020202020202" },
        \\  "routes": {
        \\    "/premium": {
        \\      "type": "static",
        \\      "file": "premium.html",
        \\      "auth": "payment_required",
        \\      "price_sats": 5000,
        \\      "output_basket": "premium-revenue"
        \\    },
        \\    "/comments": {
        \\      "type": "static",
        \\      "file": "comments.html",
        \\      "auth": "payment_required",
        \\      "price_sats": 100
        \\    }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    const premium = cfg.routeFor("/premium") orelse return error.TestFailed;
    try std.testing.expectEqualStrings("premium-revenue", premium.output_basket);
    const comments = cfg.routeFor("/comments") orelse return error.TestFailed;
    try std.testing.expectEqualStrings("", comments.output_basket);
}

test "WSITE1 config: rejects malformed JSON" {
    try std.testing.expectError(
        error.parse_failed,
        site_config.parseJson(std.testing.allocator, "{ bad"),
    );
}

test "WSITE1 config: rejects missing site section" {
    try std.testing.expectError(
        error.schema_mismatch,
        site_config.parseJson(std.testing.allocator, "{}"),
    );
}

test "WSITE1 config: rejects unknown route type" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "p" },
        \\  "routes": { "/": { "type": "weird", "file": "x" } }
        \\}
    ;
    try std.testing.expectError(
        error.invalid_route_type,
        site_config.parseJson(std.testing.allocator, json),
    );
}

test "WSITE1 config: rejects unknown auth kind" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "p" },
        \\  "routes": { "/": { "type": "static", "file": "x", "auth": "magic_glove" } }
        \\}
    ;
    try std.testing.expectError(
        error.invalid_auth_kind,
        site_config.parseJson(std.testing.allocator, json),
    );
}

test "WSITE1 config: routeFor returns null for unknown paths" {
    const tmpl = try site_config.defaultJsonTemplate(std.testing.allocator, "x.test");
    defer std.testing.allocator.free(tmpl);
    var cfg = try site_config.parseJson(std.testing.allocator, tmpl);
    defer cfg.deinit();
    try std.testing.expect(cfg.routeFor("/nope") == null);
}

test "WSITE1 validate: payment_required with price=0 is an error" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "/tmp" },
        \\  "routes": {
        \\    "/p": { "type": "static", "file": "f", "auth": "payment_required" }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    var report = try site_config.validate(std.testing.allocator, &cfg);
    defer report.deinit();
    try std.testing.expect(report.errCount() >= 1);
}

test "WSITE1 validate: warns on missing static file" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "/tmp/wsite1-no-such-dir" },
        \\  "routes": {
        \\    "/": { "type": "static", "file": "missing.html", "public": true }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    var report = try site_config.validate(std.testing.allocator, &cfg);
    defer report.deinit();
    var saw_warn = false;
    for (report.problems.items) |p| {
        if (p.severity == .warn and std.mem.indexOf(u8, p.message, "file not found") != null) {
            saw_warn = true;
        }
    }
    try std.testing.expect(saw_warn);
}

test "WSITE2.5 validate: dynamic route without handler_sha256 errors" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "/tmp" },
        \\  "routes": {
        \\    "/d": { "type": "dynamic", "handler": "h.wasm" }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    var report = try site_config.validate(std.testing.allocator, &cfg);
    defer report.deinit();
    var saw_hash_err = false;
    for (report.problems.items) |p| {
        if (std.mem.indexOf(u8, p.message, "handler_sha256") != null and p.severity == .err) saw_hash_err = true;
    }
    try std.testing.expect(saw_hash_err);
}

test "WSITE2.5 config: parses handler_sha256 hash-pin" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "/tmp" },
        \\  "routes": {
        \\    "/d": {
        \\      "type": "dynamic",
        \\      "handler": "h.wasm",
        \\      "handler_sha256": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        \\    }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    const r = cfg.routeFor("/d") orelse return error.TestFailed;
    try std.testing.expect(r.handler_sha256_set);
    try std.testing.expectEqual(@as(u8, 0xde), r.handler_sha256[0]);
    try std.testing.expectEqual(@as(u8, 0xad), r.handler_sha256[1]);
    try std.testing.expectEqual(@as(u8, 0xbe), r.handler_sha256[2]);
    try std.testing.expectEqual(@as(u8, 0xef), r.handler_sha256[3]);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5 — brain issue #274 — RouteType.directory.
// ─────────────────────────────────────────────────────────────────────

test "D-O5 config: parses directory route with explicit spa_fallback" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "." },
        \\  "routes": {
        \\    "/helm/": {
        \\      "type": "directory",
        \\      "root": "./public/helm",
        \\      "spa_fallback": "index.html"
        \\    }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    const helm = cfg.routeFor("/helm/") orelse return error.TestFailed;
    try std.testing.expectEqual(site_config.RouteType.directory, helm.kind);
    try std.testing.expectEqualStrings("./public/helm", helm.root);
    try std.testing.expectEqualStrings("index.html", helm.spa_fallback);
}

test "D-O5 config: directory route defaults spa_fallback to index.html" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "." },
        \\  "routes": {
        \\    "/helm/": { "type": "directory", "root": "./public/helm" }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    const helm = cfg.routeFor("/helm/") orelse return error.TestFailed;
    try std.testing.expectEqualStrings("index.html", helm.spa_fallback);
}

test "D-O5 config: directory route path missing trailing slash is rejected" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "." },
        \\  "routes": {
        \\    "/helm": { "type": "directory", "root": "./public/helm" }
        \\  }
        \\}
    ;
    try std.testing.expectError(
        error.invalid_route_type,
        site_config.parseJson(std.testing.allocator, json),
    );
}

test "D-O5 config: directory route without root errors" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "." },
        \\  "routes": {
        \\    "/helm/": { "type": "directory" }
        \\  }
        \\}
    ;
    try std.testing.expectError(
        error.schema_mismatch,
        site_config.parseJson(std.testing.allocator, json),
    );
}

test "D-O5 routeFor: prefix-matches directory routes" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "." },
        \\  "routes": {
        \\    "/helm/": { "type": "directory", "root": "./public/helm" },
        \\    "/": { "type": "static", "file": "i.html", "public": true }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();

    // Exact prefix hit.
    const r1 = cfg.routeFor("/helm/") orelse return error.TestFailed;
    try std.testing.expectEqual(site_config.RouteType.directory, r1.kind);

    // Asset under prefix should still match the directory route.
    const r2 = cfg.routeFor("/helm/assets/index-Bua8tKlp.js") orelse return error.TestFailed;
    try std.testing.expectEqual(site_config.RouteType.directory, r2.kind);

    // Unrelated path falls through to the static "/" route via exact match.
    const r3 = cfg.routeFor("/") orelse return error.TestFailed;
    try std.testing.expectEqual(site_config.RouteType.static, r3.kind);

    // No matching prefix → null.
    try std.testing.expect(cfg.routeFor("/foo/bar") == null);
}

test "D-O5 routeFor: longest-prefix wins among directory routes" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "." },
        \\  "routes": {
        \\    "/a/": { "type": "directory", "root": "./pa" },
        \\    "/a/b/": { "type": "directory", "root": "./pb" }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    const r = cfg.routeFor("/a/b/c.txt") orelse return error.TestFailed;
    try std.testing.expectEqualStrings("./pb", r.root);
}

test "WSITE3 validate: identity_required routes get a heads-up" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "/tmp" },
        \\  "routes": {
        \\    "/a": { "type": "static", "file": "f", "auth": "identity_required" }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    var report = try site_config.validate(std.testing.allocator, &cfg);
    defer report.deinit();
    var saw = false;
    for (report.problems.items) |p| {
        if (std.mem.indexOf(u8, p.message, "auth=identity_required") != null) saw = true;
    }
    try std.testing.expect(saw);
}

```
