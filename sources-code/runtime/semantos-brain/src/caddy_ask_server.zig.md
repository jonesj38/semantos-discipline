---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/caddy_ask_server.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.220261+00:00
---

# runtime/semantos-brain/src/caddy_ask_server.zig

```zig
// W7.14 — Caddy on-demand TLS `ask` endpoint.
//
// Caddy calls `GET http://127.0.0.1:<port>/caddy/ask?domain=<fqdn>` before
// provisioning an on-demand ACME certificate for any new domain.  This
// server returns 200 if the domain is in the allowlist and 403 otherwise,
// preventing cert issuance for domains that haven't been registered.
//
// Reference: https://caddyserver.com/docs/automatic-https#on-demand-tls
// PRD: docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md W7.14
//
// Architecture:
//   - Bound to 127.0.0.1 only (never exposed externally).
//   - One connection per request; no keep-alive (Caddy sends one ask per
//     handshake, not a persistent stream).
//   - Per-request file read of domain_allowlist (cold path; ACME negotiation
//     is already slow; the file read is negligible and ensures consistency
//     without locking).
//   - A maximum of 4096 bytes is read from each request (far more than
//     needed for a single HTTP request line).
//
// Global Caddy config (place in /etc/caddy/conf.d/00-globals.conf or in
// the top-level Caddyfile):
//
//   {
//       on_demand_tls {
//           ask http://127.0.0.1:2020/caddy/ask
//       }
//   }
//
// The port is configurable (--caddy-ask-port in cmdServe; default 2020).

const std = @import("std");
const domain_allowlist = @import("domain_allowlist");

pub const ServerError = error{
    bind_failed,
};

/// Run the ask server loop in the calling thread.  Blocks until the process
/// exits.  Intended to be spawned in a background thread by cmdServe.
///
/// `port`     TCP port to listen on (127.0.0.1 only).
/// `data_dir` Path to the data directory containing `domain_allowlist`.
/// `allocator` Per-request allocator; each connection is freed before the
///             next one starts.
pub fn run(
    port: u16,
    data_dir: []const u8,
    allocator: std.mem.Allocator,
) ServerError!void {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    var server = addr.listen(.{ .reuse_address = true }) catch return error.bind_failed;
    defer server.deinit();

    while (true) {
        const conn = server.accept() catch continue;
        handleConn(conn, data_dir, allocator);
    }
}

// ── Internal ──────────────────────────────────────────────────────────────

fn handleConn(
    conn: std.net.Server.Connection,
    data_dir: []const u8,
    allocator: std.mem.Allocator,
) void {
    defer conn.stream.close();

    var buf: [4096]u8 = undefined;
    const n = conn.stream.read(&buf) catch return;
    if (n == 0) return;

    const request = buf[0..n];
    const domain_opt = extractDomain(request);

    const allowed: bool = if (domain_opt) |domain|
        domain_allowlist.contains(allocator, data_dir, domain) catch false
    else
        false;

    const resp = if (allowed)
        "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    else
        "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";

    conn.stream.writeAll(resp) catch {};
}

/// Extract the `domain` query parameter from a raw HTTP request.
/// Expects: `GET /caddy/ask?domain=<fqdn> HTTP/1.1`
/// Returns a slice into `request` — valid only for the lifetime of `request`.
fn extractDomain(request: []const u8) ?[]const u8 {
    // Find the request line end (first \r\n or \n).
    const line_end = std.mem.indexOfAny(u8, request, "\r\n") orelse request.len;
    const line = request[0..line_end];

    // Expect "GET /caddy/ask?domain=<fqdn> HTTP/..."
    const prefix = "/caddy/ask?domain=";
    const path_start = std.mem.indexOf(u8, line, prefix) orelse return null;
    const domain_start = path_start + prefix.len;
    if (domain_start >= line.len) return null;

    // Domain ends at the next space or end of line.
    const rest = line[domain_start..];
    const domain_end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
    const raw = rest[0..domain_end];

    // Strip any trailing HTTP version fragment just in case.
    return if (raw.len > 0) raw else null;
}

// ── Inline tests ──────────────────────────────────────────────────────────

test "extractDomain: standard Caddy ask request" {
    const req = "GET /caddy/ask?domain=brain.coastal.com.au HTTP/1.1\r\nHost: 127.0.0.1:2020\r\n\r\n";
    const d = extractDomain(req);
    try std.testing.expectEqualStrings("brain.coastal.com.au", d.?);
}

test "extractDomain: no domain param" {
    const req = "GET /caddy/ask HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";
    try std.testing.expect(extractDomain(req) == null);
}

test "extractDomain: empty domain" {
    const req = "GET /caddy/ask?domain= HTTP/1.1\r\n\r\n";
    const d = extractDomain(req);
    try std.testing.expect(d == null);
}

test "extractDomain: domain with dot-au TLD" {
    const req = "GET /caddy/ask?domain=brain.oddjobz.com.au HTTP/1.1\r\n\r\n";
    const d = extractDomain(req);
    try std.testing.expectEqualStrings("brain.oddjobz.com.au", d.?);
}

```
