---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/site_server_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.173139+00:00
---

# runtime/semantos-brain/tests/site_server_conformance.zig

```zig
// Phase WSITE2 — site server conformance tests.
//
// Tests focus on the request-routing logic + content-type guess.  The
// full HTTP listener loop is exercised end-to-end by the binary smoke
// test; unit tests don't bind sockets (avoids flakiness around port
// allocation in CI).

const std = @import("std");
const site_config = @import("site_config");
const site_server = @import("site_server");

test "WSITE2 server: guessContentType maps common extensions" {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", site_server.guessContentType("index.html"));
    try std.testing.expectEqualStrings("text/css; charset=utf-8", site_server.guessContentType("/style.css"));
    try std.testing.expectEqualStrings("application/javascript; charset=utf-8", site_server.guessContentType("/a/b.js"));
    try std.testing.expectEqualStrings("application/json; charset=utf-8", site_server.guessContentType("data.json"));
    try std.testing.expectEqualStrings("image/png", site_server.guessContentType("logo.png"));
    try std.testing.expectEqualStrings("image/svg+xml", site_server.guessContentType("a.svg"));
    try std.testing.expectEqualStrings("application/wasm", site_server.guessContentType("h.wasm"));
}

test "WSITE2 server: guessContentType falls back to octet-stream" {
    try std.testing.expectEqualStrings("application/octet-stream", site_server.guessContentType("file"));
    try std.testing.expectEqualStrings("application/octet-stream", site_server.guessContentType("file.weird"));
}

fn tempDir(allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return allocator.dupe(u8, real);
}

test "WSITE2 server: init creates an access log under <data-dir>/sites/<domain>/" {
    const data_dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(data_dir);

    const json =
        \\{
        \\  "site": { "domain": "test.local", "content_root": ".", "listen_port": 9999 },
        \\  "routes": { "/": { "type": "static", "file": "index.html", "public": true } }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();

    var server = try site_server.SiteServer.init(std.testing.allocator, &cfg, data_dir);
    defer server.deinit();
    // The access_log_path should resolve under data_dir/sites/test.local/.
    try std.testing.expect(std.mem.indexOf(u8, server.access_log_path, "test.local") != null);
    try std.testing.expect(std.mem.endsWith(u8, server.access_log_path, "access.log"));

    // The file should be openable for read.
    const f = try std.fs.cwd().openFile(server.access_log_path, .{});
    f.close();
}

test "WSITE2 server: routeFor finds the right route, falls through on miss" {
    const json =
        \\{
        \\  "site": { "domain": "x", "content_root": "." },
        \\  "routes": {
        \\    "/": { "type": "static", "file": "i.html", "public": true },
        \\    "/about": { "type": "static", "file": "a.html", "public": true }
        \\  }
        \\}
    ;
    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();
    try std.testing.expect(cfg.routeFor("/") != null);
    try std.testing.expect(cfg.routeFor("/about") != null);
    try std.testing.expect(cfg.routeFor("/nope") == null);
}

// ─────────────────────────────────────────────────────────────────────
// D-O5 — directory route safety + MIME helpers.
// ─────────────────────────────────────────────────────────────────────

test "D-O5 server: isSafeRelativeUrlPath accepts ordinary asset paths" {
    try std.testing.expect(site_server.isSafeRelativeUrlPath(""));
    try std.testing.expect(site_server.isSafeRelativeUrlPath("index.html"));
    try std.testing.expect(site_server.isSafeRelativeUrlPath("assets/index-Bua8tKlp.js"));
    try std.testing.expect(site_server.isSafeRelativeUrlPath("a/b/c/file.css"));
}

test "D-O5 server: isSafeRelativeUrlPath rejects parent-dir traversal" {
    try std.testing.expect(!site_server.isSafeRelativeUrlPath(".."));
    try std.testing.expect(!site_server.isSafeRelativeUrlPath("../etc/passwd"));
    try std.testing.expect(!site_server.isSafeRelativeUrlPath("a/../../etc/passwd"));
    try std.testing.expect(!site_server.isSafeRelativeUrlPath("assets/../secret"));
}

test "D-O5 server: isSafeRelativeUrlPath rejects absolute-style or backslash paths" {
    try std.testing.expect(!site_server.isSafeRelativeUrlPath("/etc/passwd"));
    try std.testing.expect(!site_server.isSafeRelativeUrlPath("a\\b"));
    // Path containing a NUL byte
    var buf = [_]u8{ 'a', 0, 'b' };
    try std.testing.expect(!site_server.isSafeRelativeUrlPath(buf[0..]));
}

test "D-O5 server: isSafeRelativeUrlPath does not flag dots inside filenames" {
    // Filenames with periods (as in versioned bundles) must pass.
    try std.testing.expect(site_server.isSafeRelativeUrlPath("assets/index-Bua8tKlp.js"));
    try std.testing.expect(site_server.isSafeRelativeUrlPath(".dotfile"));
    try std.testing.expect(site_server.isSafeRelativeUrlPath("a.b.c.txt"));
}

test "D-O5 server: guessContentType handles SPA bundle extensions" {
    try std.testing.expectEqualStrings("application/javascript; charset=utf-8", site_server.guessContentType("a.mjs"));
    try std.testing.expectEqualStrings("application/json; charset=utf-8", site_server.guessContentType("bundle.js.map"));
    try std.testing.expectEqualStrings("font/woff2", site_server.guessContentType("inter.woff2"));
    try std.testing.expectEqualStrings("image/webp", site_server.guessContentType("hero.webp"));
}

test "D-O5 server: directory route + asset roundtrip on disk" {
    // Stand up a temporary SPA bundle and serve a real file out of it
    // through the site_server's request dispatcher.  We don't bind a
    // socket — instead we spin a tmp-dir, write a few files, and verify
    // routeFor returns the directory route + the validate stage warns
    // when files are missing.  The full HTTP roundtrip is exercised by
    // the integration smoke test (operator_helm_deploy.sh + curl).
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    // Lay out: <tmp>/public/helm/index.html + assets/index-abc.js
    try tmp.dir.makePath("public/helm/assets");
    try tmp.dir.writeFile(.{ .sub_path = "public/helm/index.html", .data = "<!doctype html><title>helm</title>" });
    try tmp.dir.writeFile(.{ .sub_path = "public/helm/assets/index-abc.js", .data = "console.log('helm')" });

    // Build a config that points at the tmp's public/helm.
    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "public/helm" });
    defer std.testing.allocator.free(root_path);
    const json = try std.fmt.allocPrint(std.testing.allocator,
        \\{{
        \\  "site": {{ "domain": "x", "content_root": "." }},
        \\  "routes": {{
        \\    "/helm/": {{ "type": "directory", "root": "{s}" }}
        \\  }}
        \\}}
    , .{root_path});
    defer std.testing.allocator.free(json);

    var cfg = try site_config.parseJson(std.testing.allocator, json);
    defer cfg.deinit();

    // routeFor on a deep asset path should still hit the directory route.
    const r = cfg.routeFor("/helm/assets/index-abc.js") orelse return error.TestFailed;
    try std.testing.expectEqual(site_config.RouteType.directory, r.kind);
    try std.testing.expectEqualStrings("index.html", r.spa_fallback);

    // validate() should NOT warn — the root + spa_fallback both exist.
    var report = try site_config.validate(std.testing.allocator, &cfg);
    defer report.deinit();
    for (report.problems.items) |p| {
        if (std.mem.indexOf(u8, p.message, "directory root not found") != null) return error.TestFailed;
        if (std.mem.indexOf(u8, p.message, "spa_fallback not found") != null) return error.TestFailed;
    }
}

```
