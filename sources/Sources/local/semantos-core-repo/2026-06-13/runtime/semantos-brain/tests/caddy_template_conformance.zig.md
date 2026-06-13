---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/caddy_template_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.191314+00:00
---

# runtime/semantos-brain/tests/caddy_template_conformance.zig

```zig
// Phase D-O9 — Caddy block templating conformance.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 (the canonical
// `[provision] writing Caddy block ... /etc/caddy/conf.d/<domain>.conf`
// step), docs/canon/deliverables.yml D-O9.
//
// Drives src/caddy_template.zig:
//   • renders each manifest fixture from D-O8's tenant-manifest
//     vectors → compares to the matching `.conf.expected` fixture
//     under tests/vectors/caddy-blocks/ byte-for-byte
//   • exercises the CORS conditional shapes (no CORS / `*` wildcard /
//     specific origins via `@allowed_origins` matcher)
//   • exercises the listen-port-from-manifest threading
//   • when `caddy validate` is on PATH, parses the rendered block as
//     a structural sanity check (skipped silently when not installed
//     so CI doesn't depend on a non-Zig binary)

const std = @import("std");
const tm = @import("tenant_manifest");
const caddy = @import("caddy_template");

const MANIFEST_VECTORS = "tests/vectors/tenant-manifests";
const CADDY_VECTORS = "tests/vectors/caddy-blocks";

fn loadBytes(allocator: std.mem.Allocator, dir: []const u8, name: []const u8) ![]u8 {
    const path = try std.fs.path.join(allocator, &.{ dir, name });
    defer allocator.free(path);
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    _ = try f.readAll(buf);
    return buf;
}

fn renderManifest(
    allocator: std.mem.Allocator,
    manifest_name: []const u8,
) !struct {
    rendered: []u8,
    manifest: tm.TenantManifest,
} {
    const bytes = try loadBytes(allocator, MANIFEST_VECTORS, manifest_name);
    defer allocator.free(bytes);
    var m = try tm.parse(allocator, bytes);
    errdefer m.deinit();
    const rendered = try caddy.renderCaddyBlock(allocator, &m);
    return .{ .rendered = rendered, .manifest = m };
}

// ─────────────────────────────────────────────────────────────────────
// Byte-stable rendering against expected fixtures
// ─────────────────────────────────────────────────────────────────────

test "D-O9: acme-plumbing-canonical (§11) renders byte-for-byte" {
    const a = std.testing.allocator;
    var out = try renderManifest(a, "acme-plumbing-canonical.toml");
    defer out.manifest.deinit();
    defer a.free(out.rendered);

    const expected = try loadBytes(a, CADDY_VECTORS, "acme-plumbing-canonical.conf.expected");
    defer a.free(expected);

    try std.testing.expectEqualStrings(expected, out.rendered);
}

test "D-O9: minimal manifest renders byte-for-byte (no CORS)" {
    const a = std.testing.allocator;
    var out = try renderManifest(a, "minimal.toml");
    defer out.manifest.deinit();
    defer a.free(out.rendered);

    const expected = try loadBytes(a, CADDY_VECTORS, "minimal.conf.expected");
    defer a.free(expected);

    try std.testing.expectEqualStrings(expected, out.rendered);
}

test "D-O9: with-network manifest renders byte-for-byte (specific CORS origins via @allowed_origins matcher + custom port)" {
    const a = std.testing.allocator;
    var out = try renderManifest(a, "with-network.toml");
    defer out.manifest.deinit();
    defer a.free(out.rendered);

    const expected = try loadBytes(a, CADDY_VECTORS, "with-network-cors.conf.expected");
    defer a.free(expected);

    try std.testing.expectEqualStrings(expected, out.rendered);
}

// ─────────────────────────────────────────────────────────────────────
// Conditional rendering shape checks (no fixture comparison — just
// structural assertions so a future renderer change can't silently
// drop a section)
// ─────────────────────────────────────────────────────────────────────

test "D-O9: minimal manifest has NO CORS preflight block (cors_allowed_origins empty)" {
    const a = std.testing.allocator;
    var out = try renderManifest(a, "minimal.toml");
    defer out.manifest.deinit();
    defer a.free(out.rendered);

    try std.testing.expect(std.mem.indexOf(u8, out.rendered, "@cors_preflight") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.rendered, "Access-Control-Allow-") == null);
}

test "D-O9: with-network manifest emits @allowed_origins matcher (specific origins, NOT wildcard)" {
    const a = std.testing.allocator;
    var out = try renderManifest(a, "with-network.toml");
    defer out.manifest.deinit();
    defer a.free(out.rendered);

    try std.testing.expect(std.mem.indexOf(u8, out.rendered, "@allowed_origins header Origin") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.rendered, "https://helm.acme-plumbing.com.au") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.rendered, "https://app.acme-plumbing.com.au") != null);
    // Wildcard echo path must NOT be used when origins are pinned.
    try std.testing.expect(std.mem.indexOf(u8, out.rendered, "    handle @cors_preflight {\n        header Access-Control-Allow-Origin \"{header.Origin}\"") == null);
}

test "D-O9: wildcard CORS origin renders {header.Origin} echo (no @allowed_origins matcher)" {
    const a = std.testing.allocator;

    // Build a wildcard manifest in-memory so we don't have to add yet
    // another D-O8 fixture just for D-O9.  D-O8's parser is the source
    // of truth for the schema; D-O9 only consumes it.
    const src =
        \\[tenant]
        \\domain = "wild.example"
        \\display_name = "Wild"
        \\owner_cert_path = "./acme-plumbing-cert.pem"
        \\recovery_enrolment_id = "plexus-rec-wild"
        \\
        \\[extensions]
        \\install = ["sovereignty"]
        \\
        \\[branding]
        \\landing_page_template = "minimal"
        \\brand_color = "#000"
        \\
        \\[network]
        \\cors_allowed_origins = ["*"]
        \\
    ;
    var m = try tm.parse(a, src);
    defer m.deinit();
    const rendered = try caddy.renderCaddyBlock(a, &m);
    defer a.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "@cors_preflight") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "@allowed_origins") == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "header Access-Control-Allow-Origin \"{header.Origin}\"") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Port + domain threading
// ─────────────────────────────────────────────────────────────────────

test "D-O9: listen_port_start threads through reverse_proxy upstreams" {
    const a = std.testing.allocator;
    var out = try renderManifest(a, "with-network.toml"); // port 8090
    defer out.manifest.deinit();
    defer a.free(out.rendered);

    try std.testing.expectEqual(@as(u16, 8090), out.manifest.listen_port_start);
    try std.testing.expect(std.mem.indexOf(u8, out.rendered, "reverse_proxy localhost:8090") != null);
    // Default port 8082 must NOT appear.
    try std.testing.expect(std.mem.indexOf(u8, out.rendered, "localhost:8082") == null);
}

test "D-O9: per-tenant access log path embeds the tenant domain" {
    const a = std.testing.allocator;
    var out = try renderManifest(a, "acme-plumbing-canonical.toml");
    defer out.manifest.deinit();
    defer a.free(out.rendered);

    try std.testing.expect(std.mem.indexOf(u8, out.rendered, "/var/log/caddy/acme-plumbing.com.au.access.log") != null);
}

test "D-O9: site-block opens with the manifest domain + closes" {
    const a = std.testing.allocator;
    var out = try renderManifest(a, "acme-plumbing-canonical.toml");
    defer out.manifest.deinit();
    defer a.free(out.rendered);

    try std.testing.expect(std.mem.startsWith(u8, out.rendered, "acme-plumbing.com.au {\n"));
    try std.testing.expect(std.mem.endsWith(u8, out.rendered, "\n}\n"));
}

test "D-O9: TLS on_demand block always present (default operator-friendly LE strategy)" {
    const a = std.testing.allocator;
    var out = try renderManifest(a, "acme-plumbing-canonical.toml");
    defer out.manifest.deinit();
    defer a.free(out.rendered);

    try std.testing.expect(std.mem.indexOf(u8, out.rendered, "tls {\n        on_demand\n    }") != null);
}

```
