---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/caddy_template.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.238199+00:00
---

# runtime/semantos-brain/src/caddy_template.zig

```zig
// Phase D-O9 — Per-tenant Caddy block renderer.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 (the canonical
// `[provision] writing Caddy block ... /etc/caddy/conf.d/<domain>.conf`
// step that fires after manifest validation), docs/canon/deliverables.yml
// D-O9 entry, runtime/semantos-brain/src/tenant_manifest.zig (D-O8 — the schema we
// read).
//
// ── What this is ─────────────────────────────────────────────────────
//
// A pure renderer.  Takes a parsed `TenantManifest` (D-O8) + emits a
// Caddy v2 site-block snippet for `/etc/caddy/conf.d/<domain>.conf`.
// The host's main `Caddyfile` does `import /etc/caddy/conf.d/*` once,
// so each tenant's snippet drops in beside the others without the
// operator needing to edit a shared file.
//
// Output shape (canonical, drives the `*.conf.expected` fixtures):
//
//   acme-plumbing.com.au {
//       tls {
//           on_demand
//       }
//
//       @cors_preflight method OPTIONS
//       handle @cors_preflight {
//           header Access-Control-Allow-Origin "{header.Origin}"
//           header Access-Control-Allow-Methods "GET, POST, OPTIONS"
//           header Access-Control-Allow-Headers "Authorization, Content-Type"
//           header Access-Control-Max-Age "86400"
//           respond 204
//       }
//
//       handle /api/v1/* {
//           reverse_proxy localhost:8082 {
//               header_up X-Forwarded-Host {host}
//               header_up X-Forwarded-Proto {scheme}
//           }
//       }
//
//       handle /helm/* {
//           reverse_proxy localhost:8082
//       }
//
//       handle / {
//           reverse_proxy localhost:8082
//       }
//
//       log {
//           output file /var/log/caddy/acme-plumbing.com.au.access.log
//           format console
//       }
//   }
//
// ── Caddy version ────────────────────────────────────────────────────
//
// Targets Caddy v2.x — the established release line.  We emit
// canonical Caddyfile syntax (NOT JSON config); operators edit + diff
// these snippets, so the human-readable form wins.  `caddy validate`
// (when installed) parses the output as a structural check; the
// conformance suite has a best-effort hook to invoke it.
//
// ── TLS strategy ─────────────────────────────────────────────────────
//
// Default: `tls { on_demand }`.  Caddy negotiates Let's Encrypt
// per-domain on first request — operator-friendly default; no ACME
// email required up front.  D-O8's manifest does NOT carry an `[acme]`
// block; if a future schema revision adds one, this renderer will
// switch the `tls` directive shape.  Tracked as a TODO at the bottom
// of this file.
//
// ── Reverse-proxy port allocation ────────────────────────────────────
//
// D-O9 renders the `localhost:<port>` upstream from
// `manifest.tenant.listen_port_start` verbatim.  Multi-tenant
// per-host port allocation (`start + tenant_index`) is D-O10's job
// during provisioning.  D-O9 just renders the configured port.
//
// ── CORS handling ────────────────────────────────────────────────────
//
// CORS only emits when `manifest.network.cors_allowed_origins` is
// non-empty.  Two shapes:
//
//   1. The list contains the literal `"*"` wildcard → echo
//      `{header.Origin}` back (mirrors caller; the caller already
//      passed Origin).  This is the operator-friendly default for
//      wide-open dev / public chat surfaces.
//
//   2. The list is specific origins → render an `@allowed_origins`
//      matcher that pins the Access-Control-Allow-Origin header to
//      one of the listed origins.  Caddy's expression matcher does
//      the include check.
//
// In both cases the actual CORS header values mirror the Semantos Brain
// dispatcher's WSITE3 / D-W1 Phase 3 surface so the Caddy + brain
// preflights agree byte-for-byte (caller sees the same headers
// whether Caddy short-circuits the preflight or brain handles it).
//
// ── Access logging ───────────────────────────────────────────────────
//
// Per-tenant access log at `/var/log/caddy/<domain>.access.log` in
// console (text) format.  Operator can rotate via the standard
// `logrotate` integration documented in the operator runbook.
//
// ── Determinism ──────────────────────────────────────────────────────
//
// Output is byte-stable for a given manifest input (no timestamps, no
// random IDs, fixed indent of 4 spaces, `\n` line endings only).
// The conformance suite drives byte-equality against the expected
// fixtures.

const std = @import("std");
const tm = @import("tenant_manifest");

pub const RenderError = error{
    out_of_memory,
};

/// Render a Caddy v2 site-block snippet for a single tenant.
///
/// Caller owns the returned slice (free with `parent_allocator`).
/// On any allocator failure returns `error.out_of_memory`.
pub fn renderCaddyBlock(
    parent_allocator: std.mem.Allocator,
    manifest: *const tm.TenantManifest,
) RenderError![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(parent_allocator);

    const w = buf.writer(parent_allocator);

    // ── Site-block header ────────────────────────────────────────────
    w.print("{s} {{\n", .{manifest.domain}) catch return error.out_of_memory;

    // ── tls { on_demand } ───────────────────────────────────────────
    //
    // Default operator-friendly TLS strategy: Caddy negotiates a
    // Let's Encrypt cert on first request per-domain.  D-O8 does NOT
    // carry an `[acme]` block; when one lands we switch shape here.
    w.writeAll("    tls {\n") catch return error.out_of_memory;
    w.writeAll("        on_demand\n") catch return error.out_of_memory;
    w.writeAll("    }\n") catch return error.out_of_memory;
    w.writeAll("\n") catch return error.out_of_memory;

    // ── CORS preflight (conditional) ─────────────────────────────────
    if (manifest.network_cors_allowed_origins.len > 0) {
        try renderCorsBlock(parent_allocator, &buf, manifest);
    }

    // ── /api/v1/* reverse proxy ─────────────────────────────────────
    w.writeAll("    handle /api/v1/* {\n") catch return error.out_of_memory;
    w.print("        reverse_proxy localhost:{d} {{\n", .{manifest.listen_port_start}) catch return error.out_of_memory;
    w.writeAll("            header_up X-Forwarded-Host {host}\n") catch return error.out_of_memory;
    w.writeAll("            header_up X-Forwarded-Proto {scheme}\n") catch return error.out_of_memory;
    w.writeAll("        }\n") catch return error.out_of_memory;
    w.writeAll("    }\n") catch return error.out_of_memory;
    w.writeAll("\n") catch return error.out_of_memory;

    // ── /helm/* reverse proxy ───────────────────────────────────────
    w.writeAll("    handle /helm/* {\n") catch return error.out_of_memory;
    w.print("        reverse_proxy localhost:{d}\n", .{manifest.listen_port_start}) catch return error.out_of_memory;
    w.writeAll("    }\n") catch return error.out_of_memory;
    w.writeAll("\n") catch return error.out_of_memory;

    // ── Catch-all → brain ────────────────────────────────────────────
    w.writeAll("    handle / {\n") catch return error.out_of_memory;
    w.print("        reverse_proxy localhost:{d}\n", .{manifest.listen_port_start}) catch return error.out_of_memory;
    w.writeAll("    }\n") catch return error.out_of_memory;
    w.writeAll("\n") catch return error.out_of_memory;

    // ── Per-tenant access log ───────────────────────────────────────
    w.writeAll("    log {\n") catch return error.out_of_memory;
    w.print("        output file /var/log/caddy/{s}.access.log\n", .{manifest.domain}) catch return error.out_of_memory;
    w.writeAll("        format console\n") catch return error.out_of_memory;
    w.writeAll("    }\n") catch return error.out_of_memory;

    // ── Site-block close ────────────────────────────────────────────
    w.writeAll("}\n") catch return error.out_of_memory;

    return buf.toOwnedSlice(parent_allocator) catch error.out_of_memory;
}

/// Render the `@cors_preflight` matcher + handler.  Caller owns the
/// `buf`'s allocator; we just append.  Two shapes:
///
///   - List contains `"*"` → mirror `{header.Origin}` back.
///   - Specific origins → emit an `@allowed_origins` named matcher
///     and use it to gate the Allow-Origin header.
fn renderCorsBlock(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    manifest: *const tm.TenantManifest,
) RenderError!void {
    const w = buf.writer(allocator);

    // Detect wildcard.
    var is_wildcard = false;
    for (manifest.network_cors_allowed_origins) |o| {
        if (std.mem.eql(u8, o, "*")) {
            is_wildcard = true;
            break;
        }
    }

    if (!is_wildcard) {
        // Named matcher pinning the allowed Origin set.
        w.writeAll("    @allowed_origins header Origin ") catch return error.out_of_memory;
        for (manifest.network_cors_allowed_origins, 0..) |o, i| {
            if (i > 0) w.writeAll(" ") catch return error.out_of_memory;
            w.print("\"{s}\"", .{o}) catch return error.out_of_memory;
        }
        w.writeAll("\n") catch return error.out_of_memory;
        w.writeAll("\n") catch return error.out_of_memory;
    }

    w.writeAll("    @cors_preflight method OPTIONS\n") catch return error.out_of_memory;
    w.writeAll("    handle @cors_preflight {\n") catch return error.out_of_memory;
    if (is_wildcard) {
        w.writeAll("        header Access-Control-Allow-Origin \"{header.Origin}\"\n") catch return error.out_of_memory;
    } else {
        w.writeAll("        header @allowed_origins Access-Control-Allow-Origin \"{header.Origin}\"\n") catch return error.out_of_memory;
    }
    w.writeAll("        header Access-Control-Allow-Methods \"GET, POST, OPTIONS\"\n") catch return error.out_of_memory;
    w.writeAll("        header Access-Control-Allow-Headers \"Authorization, Content-Type\"\n") catch return error.out_of_memory;
    w.writeAll("        header Access-Control-Max-Age \"86400\"\n") catch return error.out_of_memory;
    w.writeAll("        respond 204\n") catch return error.out_of_memory;
    w.writeAll("    }\n") catch return error.out_of_memory;
    w.writeAll("\n") catch return error.out_of_memory;
}

// ── W7.14 — Global Caddy block ────────────────────────────────────────────

/// Render the global Caddyfile block that enables on-demand TLS with an
/// `ask` endpoint for domain verification.
///
/// Output shape (write to /etc/caddy/conf.d/00-globals.conf):
///
///   {
///       on_demand_tls {
///           ask http://127.0.0.1:<port>/caddy/ask
///       }
///   }
///
/// The ask endpoint is served by `caddy_ask_server.zig`.
/// Caller owns the returned slice.
pub fn renderGlobalBlock(
    parent_allocator: std.mem.Allocator,
    ask_port: u16,
) RenderError![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(parent_allocator);

    const w = buf.writer(parent_allocator);
    w.print(
        "{{\n    on_demand_tls {{\n        ask http://127.0.0.1:{d}/caddy/ask\n    }}\n}}\n",
        .{ask_port},
    ) catch return error.out_of_memory;

    return buf.toOwnedSlice(parent_allocator) catch error.out_of_memory;
}

test "renderGlobalBlock: structure" {
    const block = try renderGlobalBlock(std.testing.allocator, 2020);
    defer std.testing.allocator.free(block);
    try std.testing.expect(std.mem.containsAtLeast(u8, block, 1, "on_demand_tls"));
    try std.testing.expect(std.mem.containsAtLeast(u8, block, 1, "ask http://127.0.0.1:2020/caddy/ask"));
}

test "renderGlobalBlock: custom port" {
    const block = try renderGlobalBlock(std.testing.allocator, 9090);
    defer std.testing.allocator.free(block);
    try std.testing.expect(std.mem.containsAtLeast(u8, block, 1, "127.0.0.1:9090"));
}

// ─────────────────────────────────────────────────────────────────────
// Future-proofing TODOs
// ─────────────────────────────────────────────────────────────────────
//
// TODO(D-O10): when the manifest gains an optional `[acme]` block
// (operator email + ACME directory URL), switch the `tls` directive
// from `on_demand` to `tls <email>` and emit `acme_ca <url>` if set.
// Until then `on_demand` is the operator-friendly default and the
// renderer is closed for that knob.
//
// TODO(D-O10): rate-limit-opt-in.  When a `[network] rate_limit_*`
// field lands, this renderer emits the matching `rate_limit` directive
// (Caddy v2 ships rate-limit as a community plugin, so the operator
// has to opt into the plugin install too — runbook covers it).

```
