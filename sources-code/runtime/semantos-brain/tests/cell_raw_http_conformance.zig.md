---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/cell_raw_http_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.183976+00:00
---

# runtime/semantos-brain/tests/cell_raw_http_conformance.zig

```zig
// D-LC1 + D-LC4 — Raw-cell-over-HTTP reactor conformance.
//
// Coverage extends the inline path-parse tests in src/cell_raw_http.zig
// (decodeHashHex, parsePath, parseSincePath) with end-to-end reactor
// round-trips: a synthetic HttpRequest is fed straight into
// reactorHandleCellRaw / reactorHandleCellSince and the resulting
// write_buf is parsed back into (status, headers, body) for assertions.
//
// This is the same shape attachments_*_conformance uses for the upload
// path's pure helpers — except here we drive the reactor handler itself,
// which is the load-bearing seam for D-LC1/D-LC4 wire conformance.
//
// We deliberately do NOT spin up the full reactor on a TCP socket:
//   1. The brain reactor is single-threaded; an in-test TCP path would
//      need a background thread + a wake-listener tear-down (cf.
//      device_pair_reactor_conformance), which buys us nothing for these
//      handlers — they don't open subordinate connections.
//   2. reactorHandleCellRaw / reactorHandleCellSince take a *const
//      HttpRequest + *ArrayList(u8); a synthetic request is the smallest
//      thing that exercises the wire-shape code paths under test.
//
// Cases covered (see test names below for the matrix):
//
// D-LC1  /api/v1/cell/<sha256hex>
//   404 — acceptor not attached
//   401 — bearer missing / malformed / unverified
//   405 — method != GET/HEAD
//   400 — hex tail malformed (non-hex / wrong length)
//   404 — well-formed hash, no cell in store
//   200 — happy path; body == 1024 stored bytes; x-cell-sha256;
//         cache-control: public,max-age=31536000,immutable; no
//         x-cell-anchor when projection absent
//   200 — x-cell-anchor: pending after setAnchorStatus(.pending)
//   200 — x-cell-anchor: confirmed after setAnchorStatus(.confirmed)
//
// D-LC4  /api/v1/cell/since/<prev_hash_hex>
//   404 — acceptor not attached
//   401 — bearer missing / invalid
//   405 — method != GET/HEAD
//   400 — hex tail malformed
//   200 — empty body + x-cell-count: 0 when no children exist
//   200 — body of N×1024; x-cell-count == N; membership match
//
// Plus a precedence test confirming /api/v1/cell/since/... DOES NOT
// fall into the D-LC1 handler (cell_raw_http.parsePath rejects
// "since/..." segments). This is asserted by handing the since-shaped
// path to reactorHandleCellRaw directly; it must surface 400.

const std = @import("std");
const lmdb = @import("lmdb");
const lmdb_cell_store = @import("lmdb_cell_store");
const cell_store_mod = @import("cell_store");
const cell_raw_http = @import("cell_raw_http");
const bearer_tokens = @import("bearer_tokens");
const site_config = @import("site_config");
const site_server = @import("site_server");
const http_parser = @import("http_parser");

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

const CELL_BYTES: usize = 1024;
const PREV_STATE_HASH_OFFSET: usize = 128;
const DOMAIN_FLAG_OFFSET: usize = 24;
const ATTESTATION_TARGET_OFFSET: usize = 256;
const DOMAIN_FLAG_ANCHOR_ATTESTATION_V1: u32 = 0x0001FE02;

const SITE_CFG_JSON =
    \\{
    \\  "site": {
    \\    "domain": "cell-raw-conformance.local",
    \\    "content_root": "."
    \\  },
    \\  "routes": {}
    \\}
;

fn testClock() i64 {
    return 1_700_000_000;
}

// ─────────────────────────────────────────────────────────────────────
// Cell fixtures
// ─────────────────────────────────────────────────────────────────────

fn makeCell(fill: u8) [CELL_BYTES]u8 {
    var c: [CELL_BYTES]u8 = undefined;
    @memset(&c, fill);
    // Zero the domain-flag bytes so a fill of e.g. 0x02 doesn't accidentally
    // form the anchor-attestation magic in cell_store_lmdb's doPut dispatch.
    @memset(c[DOMAIN_FLAG_OFFSET .. DOMAIN_FLAG_OFFSET + 4], 0);
    return c;
}

fn makeCellWithPrevState(fill: u8, prev_state: [32]u8) [CELL_BYTES]u8 {
    var c = makeCell(fill);
    @memcpy(c[PREV_STATE_HASH_OFFSET .. PREV_STATE_HASH_OFFSET + 32], &prev_state);
    return c;
}

// Build an anchor-attestation cell pointing at `target_cell_id`. Same wire
// shape doPut watches for via DOMAIN_FLAG_ANCHOR_ATTESTATION_V1. Used to
// exercise the auto-confirm side-effect (D-LC5 observer) end-to-end, even
// though the explicit setAnchorStatus path is the one this suite asserts
// on for the response-header matrix.
fn makeAttestationCell(target_cell_id: [32]u8, fill: u8) [CELL_BYTES]u8 {
    var c = makeCell(fill);
    std.mem.writeInt(
        u32,
        c[DOMAIN_FLAG_OFFSET..][0..4],
        DOMAIN_FLAG_ANCHOR_ATTESTATION_V1,
        .little,
    );
    @memcpy(c[ATTESTATION_TARGET_OFFSET .. ATTESTATION_TARGET_OFFSET + 32], &target_cell_id);
    return c;
}

// ─────────────────────────────────────────────────────────────────────
// HTTP fixture — build a synthetic HttpRequest with given method / path /
// optional Authorization header.  No body; these handlers ignore body.
// ─────────────────────────────────────────────────────────────────────

const RequestFixture = struct {
    req: http_parser.HttpRequest,
    // We hand-build the headers array but keep ownership here so slices
    // stay valid for the request's lifetime.
    auth_hdr_buf: [256]u8 = undefined,

    fn init(method: []const u8, path: []const u8, bearer_hex: ?[]const u8) RequestFixture {
        var self: RequestFixture = .{
            .req = .{
                .method = method,
                .path = path,
                .query = "",
                .version = "HTTP/1.1",
                .headers = undefined,
                .header_count = 0,
                .body = "",
                .keep_alive = false,
            },
        };
        if (bearer_hex) |hex| {
            const hdr_value = std.fmt.bufPrint(&self.auth_hdr_buf, "Bearer {s}", .{hex}) catch unreachable;
            self.req.headers[0] = .{ .name = "authorization", .value = hdr_value };
            self.req.header_count = 1;
        }
        return self;
    }
};

// ─────────────────────────────────────────────────────────────────────
// Response parser — turn the raw HTTP/1.1 bytes the reactor wrote into
// (status, header-list, body) for assertion.
// ─────────────────────────────────────────────────────────────────────

const ParsedHeader = struct { name: []u8, value: []u8 };

const ParsedResponse = struct {
    status: u16,
    headers: std.ArrayList(ParsedHeader),
    body: []u8,
    allocator: std.mem.Allocator,

    fn deinit(self: *ParsedResponse) void {
        for (self.headers.items) |h| {
            self.allocator.free(h.name);
            self.allocator.free(h.value);
        }
        self.headers.deinit(self.allocator);
        self.allocator.free(self.body);
    }

    fn header(self: *const ParsedResponse, name: []const u8) ?[]const u8 {
        for (self.headers.items) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
        }
        return null;
    }
};

fn parseResponse(allocator: std.mem.Allocator, raw: []const u8) !ParsedResponse {
    const split = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return error.bad_response;
    const head = raw[0..split];
    const body = raw[split + 4 ..];

    var lines = std.mem.splitSequence(u8, head, "\r\n");
    const status_line = lines.next() orelse return error.bad_response;

    var status_fields = std.mem.splitScalar(u8, status_line, ' ');
    _ = status_fields.next() orelse return error.bad_response; // HTTP/1.1
    const status_str = status_fields.next() orelse return error.bad_response;
    const status = try std.fmt.parseInt(u16, status_str, 10);

    var headers = std.ArrayList(ParsedHeader){};
    errdefer {
        for (headers.items) |h| {
            allocator.free(h.name);
            allocator.free(h.value);
        }
        headers.deinit(allocator);
    }

    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        try headers.append(allocator, .{
            .name = try allocator.dupe(u8, name),
            .value = try allocator.dupe(u8, value),
        });
    }

    return .{
        .status = status,
        .headers = headers,
        .body = try allocator.dupe(u8, body),
        .allocator = allocator,
    };
}

// ─────────────────────────────────────────────────────────────────────
// ServerFixture — env, cell store, bearer-token store, site server,
// acceptor.  No threads; the reactor handlers are called directly.
// ─────────────────────────────────────────────────────────────────────

const ServerFixture = struct {
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    data_dir: []u8,
    env: lmdb.Env,
    store: lmdb_cell_store.LmdbCellStore,
    /// CellStore vtable wrapper. Populated after `store` is initialized so
    /// the Acceptor (and reactor handlers) talk through the vtable seam
    /// rather than the concrete impl. Mirrors the production wiring in
    /// `cli/serve.zig`.
    cell_store_vt: cell_store_mod.CellStore,
    token_store: bearer_tokens.TokenStore,
    site_cfg: site_config.SiteConfig,
    server: site_server.SiteServer,
    acceptor: cell_raw_http.Acceptor,
    /// 64-hex bearer the test should use for authorized requests.
    bearer_hex: [64]u8,

    fn init(allocator: std.mem.Allocator) !*ServerFixture {
        const self = try allocator.create(ServerFixture);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.tmp = std.testing.tmpDir(.{});
        errdefer self.tmp.cleanup();

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(self.data_dir);

        self.env = try lmdb.Env.open(self.data_dir, .{
            .max_dbs = 8,
            .map_size = 4 * 1024 * 1024,
            .open_flags = lmdb.EnvFlags.NOSYNC,
        });
        errdefer self.env.close();

        self.store = try lmdb_cell_store.LmdbCellStore.init(&self.env, allocator);
        errdefer self.store.deinit();

        self.token_store = try bearer_tokens.TokenStore.init(allocator, self.data_dir, testClock);
        errdefer self.token_store.deinit();

        // Mint a bearer, encode as hex — the reactor calls verifyHex on the
        // Authorization-header tail.
        const issued = try self.token_store.issue("cell-raw-conformance", 86400);
        const hex_chars = "0123456789abcdef";
        for (issued.token, 0..) |b, i| {
            self.bearer_hex[i * 2] = hex_chars[b >> 4];
            self.bearer_hex[i * 2 + 1] = hex_chars[b & 0x0f];
        }

        self.site_cfg = try site_config.parseJson(allocator, SITE_CFG_JSON);
        errdefer self.site_cfg.deinit();

        self.server = try site_server.SiteServer.init(allocator, &self.site_cfg, self.data_dir);
        errdefer self.server.deinit();

        // CellStore vtable wrapper — produced once `store` is in place at
        // its final address. The Acceptor borrows `*const CellStore` so
        // read-path callers depend on the seam, not the impl.
        self.cell_store_vt = self.store.store();
        self.acceptor = .{
            .cell_store = &self.cell_store_vt,
            .bearer_tokens = &self.token_store,
        };
        self.server.attachCellRawAcceptor(&self.acceptor);

        return self;
    }

    fn deinit(self: *ServerFixture) void {
        self.server.deinit();
        self.site_cfg.deinit();
        self.token_store.deinit();
        self.store.deinit();
        self.env.close();
        self.tmp.cleanup();
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    /// Build a SiteServer with NO acceptor attached.  Used to assert the
    /// 404 "acceptor not attached" gate fires for both handlers.
    fn initNoAcceptor(allocator: std.mem.Allocator) !*ServerFixture {
        const self = try allocator.create(ServerFixture);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.tmp = std.testing.tmpDir(.{});
        errdefer self.tmp.cleanup();

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try self.tmp.dir.realpath(".", &path_buf);
        self.data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(self.data_dir);

        self.env = try lmdb.Env.open(self.data_dir, .{
            .max_dbs = 8,
            .map_size = 4 * 1024 * 1024,
            .open_flags = lmdb.EnvFlags.NOSYNC,
        });
        errdefer self.env.close();

        self.store = try lmdb_cell_store.LmdbCellStore.init(&self.env, allocator);
        errdefer self.store.deinit();

        self.token_store = try bearer_tokens.TokenStore.init(allocator, self.data_dir, testClock);
        errdefer self.token_store.deinit();
        const issued = try self.token_store.issue("cell-raw-no-acceptor", 86400);
        const hex_chars = "0123456789abcdef";
        for (issued.token, 0..) |b, i| {
            self.bearer_hex[i * 2] = hex_chars[b >> 4];
            self.bearer_hex[i * 2 + 1] = hex_chars[b & 0x0f];
        }

        self.site_cfg = try site_config.parseJson(allocator, SITE_CFG_JSON);
        errdefer self.site_cfg.deinit();

        self.server = try site_server.SiteServer.init(allocator, &self.site_cfg, self.data_dir);
        errdefer self.server.deinit();

        self.cell_store_vt = self.store.store();
        self.acceptor = .{
            .cell_store = &self.cell_store_vt,
            .bearer_tokens = &self.token_store,
        };
        // NB: NOT calling attachCellRawAcceptor.  cell_raw_acceptor remains null.

        return self;
    }
};

// ─────────────────────────────────────────────────────────────────────
// Drive a handler and parse the response in one shot.
// ─────────────────────────────────────────────────────────────────────

fn callCellRaw(
    allocator: std.mem.Allocator,
    fx: *ServerFixture,
    req: *const http_parser.HttpRequest,
) !ParsedResponse {
    var write_buf: std.ArrayList(u8) = .{};
    defer write_buf.deinit(allocator);
    _ = site_server.reactorHandleCellRaw(&fx.server, req, &write_buf, allocator, &.{});
    return parseResponse(allocator, write_buf.items);
}

fn callCellSince(
    allocator: std.mem.Allocator,
    fx: *ServerFixture,
    req: *const http_parser.HttpRequest,
) !ParsedResponse {
    var write_buf: std.ArrayList(u8) = .{};
    defer write_buf.deinit(allocator);
    _ = site_server.reactorHandleCellSince(&fx.server, req, &write_buf, allocator, &.{});
    return parseResponse(allocator, write_buf.items);
}

// Encode a 32-byte hash as 64 lowercase hex chars (mirrors the reactor's
// bytesToHex output so we can compare without ambiguity).
fn hexEncode32(bytes: [32]u8) [64]u8 {
    var out: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = hex_chars[b >> 4];
        out[i * 2 + 1] = hex_chars[b & 0x0f];
    }
    return out;
}

// ─────────────────────────────────────────────────────────────────────
// D-LC1 — GET /api/v1/cell/<sha256hex>
// ─────────────────────────────────────────────────────────────────────

test "D-LC1: 404 when cell_raw_acceptor is not attached" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.initNoAcceptor(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/" ++ ("ab" ** 32);
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 404), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "not_found") != null);
}

test "D-LC1: 401 when bearer header is missing" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/" ++ ("ab" ** 32);
    var req_fx = RequestFixture.init("GET", path, null);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 401), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "bearer_invalid") != null);
}

test "D-LC1: 401 when bearer is malformed (wrong length)" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/" ++ ("ab" ** 32);
    // 8 hex chars — reactorBearerHex64 requires exactly 64.
    var req_fx = RequestFixture.init("GET", path, "deadbeef");
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 401), resp.status);
}

test "D-LC1: 401 when bearer is 64 hex chars but does not verify" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/" ++ ("ab" ** 32);
    // 64 hex zeros — well-formed, but never issued by the token store.
    var req_fx = RequestFixture.init("GET", path, "0" ** 64);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 401), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "bearer_invalid") != null);
}

test "D-LC1: 405 when method is POST" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/" ++ ("ab" ** 32);
    var req_fx = RequestFixture.init("POST", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 405), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "method_not_allowed") != null);
}

test "D-LC1: 405 when method is DELETE" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/" ++ ("ab" ** 32);
    var req_fx = RequestFixture.init("DELETE", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 405), resp.status);
}

test "D-LC1: 400 when hex tail is non-hex" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    // 'g' is not a hex digit; length is still 64.
    const path = "/api/v1/cell/" ++ ("gg" ** 32);
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 400), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "bad_request") != null);
}

test "D-LC1: 400 when hex tail is wrong length" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/abcd";
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 400), resp.status);
}

test "D-LC1: 404 when hash is well-formed but cell not in store" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    // Random 64-hex hash, nothing stored.
    const path = "/api/v1/cell/" ++ ("ab" ** 32);
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 404), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "not_found") != null);
}

test "D-LC1: 200 happy path — body, content-type, cache-control, x-cell-sha256, no x-cell-anchor" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const cell = makeCell(0xAB);
    const hash = try fx.store.store().put(&cell);
    const hash_hex = hexEncode32(hash);

    var path_buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/api/v1/cell/{s}", .{&hash_hex});
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);

    // Content-Type must be the layer-collapse media type.
    const ct = resp.header("content-type") orelse return error.missing_content_type;
    try std.testing.expectEqualStrings("application/x-semantos-cell", ct);

    // Body is exactly the stored cell bytes.
    try std.testing.expectEqual(@as(usize, CELL_BYTES), resp.body.len);
    try std.testing.expectEqualSlices(u8, cell[0..], resp.body);

    // x-cell-sha256 echoes the requested hex.
    const sha_hdr = resp.header("x-cell-sha256") orelse return error.missing_sha256;
    try std.testing.expectEqualStrings(hash_hex[0..], sha_hdr);

    // Cache-control is the immutable form.
    const cc = resp.header("cache-control") orelse return error.missing_cache_control;
    try std.testing.expectEqualStrings("public, max-age=31536000, immutable", cc);

    // No x-cell-anchor — projection wasn't set.
    try std.testing.expect(resp.header("x-cell-anchor") == null);
}

test "D-LC1: 200 with x-cell-anchor: pending after setAnchorStatus(.pending)" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const cell = makeCell(0xCD);
    const hash = try fx.store.store().put(&cell);
    try fx.store.setAnchorStatus(&hash, .pending);
    const hash_hex = hexEncode32(hash);

    var path_buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/api/v1/cell/{s}", .{&hash_hex});
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    const anchor_hdr = resp.header("x-cell-anchor") orelse return error.missing_anchor;
    try std.testing.expectEqualStrings("pending", anchor_hdr);
}

test "D-LC1: 200 with x-cell-anchor: confirmed after setAnchorStatus(.confirmed)" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const cell = makeCell(0x12);
    const hash = try fx.store.store().put(&cell);
    try fx.store.setAnchorStatus(&hash, .confirmed);
    const hash_hex = hexEncode32(hash);

    var path_buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/api/v1/cell/{s}", .{&hash_hex});
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    const anchor_hdr = resp.header("x-cell-anchor") orelse return error.missing_anchor;
    try std.testing.expectEqualStrings("confirmed", anchor_hdr);
}

test "D-LC1: x-cell-anchor flips confirmed automatically when attestation cell lands (D-LC5 observer)" {
    // Spot-check the D-LC5 observer wired through the live store as seen
    // by D-LC1's response surface.  We mark the target pending, then put
    // an attestation cell whose targetCellId points at the target's hash.
    // doPut's same-txn observer must flip the projection to .confirmed,
    // which D-LC1 then surfaces via x-cell-anchor.
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const target = makeCell(0x77);
    const target_hash = try fx.store.store().put(&target);
    try fx.store.setAnchorStatus(&target_hash, .pending);

    const attestation = makeAttestationCell(target_hash, 0x88);
    _ = try fx.store.store().put(&attestation);

    const hash_hex = hexEncode32(target_hash);
    var path_buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/api/v1/cell/{s}", .{&hash_hex});
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    const anchor_hdr = resp.header("x-cell-anchor") orelse return error.missing_anchor;
    try std.testing.expectEqualStrings("confirmed", anchor_hdr);
}

// ─────────────────────────────────────────────────────────────────────
// D-LC4 — GET /api/v1/cell/since/<prev_hash_hex>
// ─────────────────────────────────────────────────────────────────────

test "D-LC4: 404 when cell_raw_acceptor is not attached" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.initNoAcceptor(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/since/" ++ ("ab" ** 32);
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 404), resp.status);
}

test "D-LC4: 401 when bearer header is missing" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/since/" ++ ("ab" ** 32);
    var req_fx = RequestFixture.init("GET", path, null);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 401), resp.status);
}

test "D-LC4: 401 when bearer is well-formed but does not verify" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/since/" ++ ("ab" ** 32);
    var req_fx = RequestFixture.init("GET", path, "0" ** 64);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 401), resp.status);
}

test "D-LC4: 405 when method is POST" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/since/" ++ ("ab" ** 32);
    var req_fx = RequestFixture.init("POST", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 405), resp.status);
}

test "D-LC4: 400 when hex tail is malformed" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/since/notHexAtAll";
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 400), resp.status);
}

test "D-LC4: 200 with empty body + x-cell-count: 0 when no children exist (chain tip)" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    // Unknown prev_hash — no children indexed.
    const path = "/api/v1/cell/since/" ++ ("99" ** 32);
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);

    const ct = resp.header("content-type") orelse return error.missing_content_type;
    try std.testing.expectEqualStrings("application/x-semantos-cells", ct);

    const count_hdr = resp.header("x-cell-count") orelse return error.missing_count;
    try std.testing.expectEqualStrings("0", count_hdr);

    try std.testing.expectEqual(@as(usize, 0), resp.body.len);
}

test "D-LC4: 200 with N children, body length N*1024, count matches, contents match (any order)" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const root_hash: [32]u8 = [_]u8{0xAA} ** 32;

    const c1 = makeCellWithPrevState(0x11, root_hash);
    const c2 = makeCellWithPrevState(0x22, root_hash);
    const c3 = makeCellWithPrevState(0x33, root_hash);
    _ = try fx.store.store().put(&c1);
    _ = try fx.store.store().put(&c2);
    _ = try fx.store.store().put(&c3);

    // An unrelated cell on a different prev — must not show up.
    const other_prev: [32]u8 = [_]u8{0xBB} ** 32;
    _ = try fx.store.store().put(&makeCellWithPrevState(0x44, other_prev));

    const prev_hex = hexEncode32(root_hash);
    var path_buf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/api/v1/cell/since/{s}", .{&prev_hex});
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);

    const count_hdr = resp.header("x-cell-count") orelse return error.missing_count;
    try std.testing.expectEqualStrings("3", count_hdr);

    try std.testing.expectEqual(@as(usize, 3 * CELL_BYTES), resp.body.len);

    // Membership check — every returned 1024-byte slot must equal one of
    // c1/c2/c3.  LMDB lex order over (op_pkh ‖ prev ‖ cell_hash) keys is
    // hash-driven, so we don't assert position.
    var saw_c1 = false;
    var saw_c2 = false;
    var saw_c3 = false;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const slot = resp.body[i * CELL_BYTES .. (i + 1) * CELL_BYTES];
        if (std.mem.eql(u8, slot, c1[0..])) saw_c1 = true;
        if (std.mem.eql(u8, slot, c2[0..])) saw_c2 = true;
        if (std.mem.eql(u8, slot, c3[0..])) saw_c3 = true;
    }
    try std.testing.expect(saw_c1);
    try std.testing.expect(saw_c2);
    try std.testing.expect(saw_c3);
}

// ─────────────────────────────────────────────────────────────────────
// Precedence — a /since/ path handed to reactorHandleCellRaw must NOT
// be matched as a D-LC1 hash.  The real reactor dispatch routes /since/
// to the D-LC4 handler before this branch; this test asserts the
// inner-handler guard (parsePath rejects "since/..." tails) so the gate
// still holds if dispatch ordering were ever to regress.
// ─────────────────────────────────────────────────────────────────────

test "precedence: D-LC1 handler returns 400 for a /since/ path (does not match as hash)" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const path = "/api/v1/cell/since/" ++ ("ab" ** 32);
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellRaw(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 400), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "bad_request") != null);
}

// ─────────────────────────────────────────────────────────────────────
// D-LC4 follow-up — cursor pagination on /api/v1/cell/since/<hex>
//
// `?limit=N` clamps the page size; `x-next-cursor` is set IFF more
// results exist; `?after=<hex>` resumes strictly-after the previous
// page's last hash. Default (no query) is byte-identical to the
// unpaginated D-LC4 contract.
// ─────────────────────────────────────────────────────────────────────

// In-test path builder. The since-URL fits in 192 bytes easily.
fn buildSincePath(buf: *[192]u8, prev_hex: []const u8, query: []const u8) ![]u8 {
    if (query.len == 0) {
        return std.fmt.bufPrint(buf, "/api/v1/cell/since/{s}", .{prev_hex});
    }
    return std.fmt.bufPrint(buf, "/api/v1/cell/since/{s}?{s}", .{ prev_hex, query });
}

// Insert 5 children of the same prev_state and return their content
// hashes sorted by LMDB lex order (== ascending bytewise) — that's the
// order the since endpoint walks them in under a (op_pkh ‖ prev) prefix.
fn seedFiveChildrenSorted(fx: *ServerFixture, prev_state: [32]u8) ![5][32]u8 {
    var hashes: [5][32]u8 = undefined;
    const fills = [_]u8{ 0x11, 0x22, 0x33, 0x44, 0x55 };
    for (fills, 0..) |fill, i| {
        const c = makeCellWithPrevState(fill, prev_state);
        hashes[i] = try fx.store.store().put(&c);
    }
    std.mem.sort([32]u8, &hashes, {}, struct {
        fn lt(_: void, a: [32]u8, b: [32]u8) bool {
            return std.mem.lessThan(u8, &a, &b);
        }
    }.lt);
    return hashes;
}

test "D-LC4 pagination: ?limit=2 returns 2 cells + x-next-cursor (more pages exist)" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const prev: [32]u8 = [_]u8{0xAA} ** 32;
    const sorted = try seedFiveChildrenSorted(fx, prev);

    const prev_hex = hexEncode32(prev);
    var path_buf: [192]u8 = undefined;
    const path = try buildSincePath(&path_buf, &prev_hex, "limit=2");
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("2", resp.header("x-cell-count") orelse return error.missing_count);
    try std.testing.expectEqual(@as(usize, 2 * CELL_BYTES), resp.body.len);

    const cursor = resp.header("x-next-cursor") orelse return error.missing_cursor;
    const expected_cursor = hexEncode32(sorted[1]);
    try std.testing.expectEqualStrings(&expected_cursor, cursor);
}

test "D-LC4 pagination: ?after=<2nd>&limit=2 returns cells 3-4 + x-next-cursor" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const prev: [32]u8 = [_]u8{0xAA} ** 32;
    const sorted = try seedFiveChildrenSorted(fx, prev);

    const prev_hex = hexEncode32(prev);
    const after_hex = hexEncode32(sorted[1]);

    var query_buf: [128]u8 = undefined;
    const query = try std.fmt.bufPrint(&query_buf, "after={s}&limit=2", .{&after_hex});

    var path_buf: [192]u8 = undefined;
    const path = try buildSincePath(&path_buf, &prev_hex, query);
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("2", resp.header("x-cell-count") orelse return error.missing_count);
    try std.testing.expectEqual(@as(usize, 2 * CELL_BYTES), resp.body.len);

    const cursor = resp.header("x-next-cursor") orelse return error.missing_cursor;
    const expected_cursor = hexEncode32(sorted[3]);
    try std.testing.expectEqualStrings(&expected_cursor, cursor);
}

test "D-LC4 pagination: ?after=<4th>&limit=2 returns final cell, no x-next-cursor" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const prev: [32]u8 = [_]u8{0xAA} ** 32;
    const sorted = try seedFiveChildrenSorted(fx, prev);

    const prev_hex = hexEncode32(prev);
    const after_hex = hexEncode32(sorted[3]);

    var query_buf: [128]u8 = undefined;
    const query = try std.fmt.bufPrint(&query_buf, "after={s}&limit=2", .{&after_hex});

    var path_buf: [192]u8 = undefined;
    const path = try buildSincePath(&path_buf, &prev_hex, query);
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("1", resp.header("x-cell-count") orelse return error.missing_count);
    try std.testing.expectEqual(@as(usize, 1 * CELL_BYTES), resp.body.len);

    // Last page — x-next-cursor MUST be absent.
    try std.testing.expectEqual(@as(?[]const u8, null), resp.header("x-next-cursor"));
}

test "D-LC4 pagination: ?after=<unknown>&limit=2 returns empty body + no x-next-cursor" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const prev: [32]u8 = [_]u8{0xAA} ** 32;
    _ = try seedFiveChildrenSorted(fx, prev);

    const prev_hex = hexEncode32(prev);
    // 0xff*32 sorts higher than any [0x55,0x44,0x33,0x22,0x11]-prev cell
    // hash. Even if a fixture collision ever drifted, this is the safe
    // upper-extreme — guaranteed strictly-after every entry.
    const after_hex = ("ff" ** 32);

    var query_buf: [128]u8 = undefined;
    const query = try std.fmt.bufPrint(&query_buf, "after={s}&limit=2", .{after_hex});

    var path_buf: [192]u8 = undefined;
    const path = try buildSincePath(&path_buf, &prev_hex, query);
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("0", resp.header("x-cell-count") orelse return error.missing_count);
    try std.testing.expectEqual(@as(usize, 0), resp.body.len);
    try std.testing.expectEqual(@as(?[]const u8, null), resp.header("x-next-cursor"));
}

test "D-LC4 pagination: ?limit=0 → 400 with hint" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const prev_hex = ("ab" ** 32);
    var path_buf: [192]u8 = undefined;
    const path = try buildSincePath(&path_buf, prev_hex, "limit=0");
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 400), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "limit") != null);
}

test "D-LC4 pagination: ?limit=2000 clamps to MAX (matches limit=1024 behavior)" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const prev: [32]u8 = [_]u8{0xAA} ** 32;
    _ = try seedFiveChildrenSorted(fx, prev);

    const prev_hex = hexEncode32(prev);
    var path_buf: [192]u8 = undefined;
    const path = try buildSincePath(&path_buf, &prev_hex, "limit=2000");
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    // 5 children all fit under the clamped 1024 cap → no next-cursor.
    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("5", resp.header("x-cell-count") orelse return error.missing_count);
    try std.testing.expectEqual(@as(usize, 5 * CELL_BYTES), resp.body.len);
    try std.testing.expectEqual(@as(?[]const u8, null), resp.header("x-next-cursor"));
}

test "D-LC4 pagination: ?after=notHex → 400" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const prev_hex = ("ab" ** 32);
    var path_buf: [192]u8 = undefined;
    const path = try buildSincePath(&path_buf, prev_hex, "after=notHex");
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 400), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "after") != null);
}

test "D-LC4 pagination: ?after=<wrong-length> → 400" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const prev_hex = ("ab" ** 32);
    // 43 hex chars — well-formed hex but wrong length.
    var path_buf: [192]u8 = undefined;
    const path = try buildSincePath(&path_buf, prev_hex, "after=" ++ ("a" ** 43));
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 400), resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "after") != null);
}

test "D-LC4 pagination: default (no query params) matches pre-pagination behavior" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const prev: [32]u8 = [_]u8{0xAA} ** 32;
    _ = try seedFiveChildrenSorted(fx, prev);

    const prev_hex = hexEncode32(prev);
    var path_buf: [192]u8 = undefined;
    const path = try buildSincePath(&path_buf, &prev_hex, "");
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("5", resp.header("x-cell-count") orelse return error.missing_count);
    try std.testing.expectEqual(@as(usize, 5 * CELL_BYTES), resp.body.len);
    // Default limit == MAX == cap; all 5 fit; cursor MUST be absent.
    try std.testing.expectEqual(@as(?[]const u8, null), resp.header("x-next-cursor"));
}

test "D-LC4 pagination: limit exactly matches result count, no more rows → no cursor" {
    const allocator = std.testing.allocator;
    var fx = try ServerFixture.init(allocator);
    defer fx.deinit();

    const prev: [32]u8 = [_]u8{0xAA} ** 32;
    _ = try seedFiveChildrenSorted(fx, prev);

    // limit == exactly 5 — boundary case where results.len == limit but
    // the underlying enumeration is exhausted, so cursor MUST be absent.
    const prev_hex = hexEncode32(prev);
    var path_buf: [192]u8 = undefined;
    const path = try buildSincePath(&path_buf, &prev_hex, "limit=5");
    var req_fx = RequestFixture.init("GET", path, fx.bearer_hex[0..]);
    var resp = try callCellSince(allocator, fx, &req_fx.req);
    defer resp.deinit();

    try std.testing.expectEqual(@as(u16, 200), resp.status);
    try std.testing.expectEqualStrings("5", resp.header("x-cell-count") orelse return error.missing_count);
    try std.testing.expectEqual(@as(?[]const u8, null), resp.header("x-next-cursor"));
}

```
