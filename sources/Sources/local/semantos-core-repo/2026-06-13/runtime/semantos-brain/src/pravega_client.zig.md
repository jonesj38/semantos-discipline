---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/pravega_client.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.243587+00:00
---

# runtime/semantos-brain/src/pravega_client.zig

```zig
// M3.2 — PravegatClient: Zig client for the Pravega Go gateway sidecar.
//
// Calls the gateway at http://127.0.0.1:7180 (default) which in turn proxies
// to Pravega's REST API on ports 9090 (controller) and 9091 (data plane).
//
// All public methods use std.http.Client (same pattern as UhrpHttpStore in M4.2).
// HTTP requests follow the Zig 0.15 API:
//   - client.request(method, uri, options) → Request
//   - req.sendBodiless()           for GET / bodiless requests
//   - req.sendBodyComplete(body)   for POST with body (takes []u8)
//   - req.receiveHead(&buf)        → Response
//   - response.reader(&tbuf)       → *std.Io.Reader for body
//
// Error handling:
//   - ensureScope / ensureStream: 201 and 409 (already exists) are both ok.
//   - writeEvent: 201 is ok; anything else → error.HttpError.
//   - readEvent: 200 with empty body → null; non-200 → error.HttpError.

const std = @import("std");

pub const PravegatConfig = struct {
    /// Base URL of the gateway sidecar, e.g. "http://127.0.0.1:7180".
    /// Not owned — caller must keep alive for the lifetime of the client.
    gateway_url: []const u8,
    /// Pravega scope name, e.g. "semantos".
    /// Not owned — caller must keep alive for the lifetime of the client.
    scope: []const u8,
};

pub const PravegatClient = struct {
    allocator: std.mem.Allocator,
    cfg: PravegatConfig,
    http_client: std.http.Client,

    /// Initialise the client. Does NOT connect — connections are made per-call.
    pub fn init(allocator: std.mem.Allocator, cfg: PravegatConfig) !PravegatClient {
        return PravegatClient{
            .allocator = allocator,
            .cfg = cfg,
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }

    /// Release resources held by the HTTP client.
    pub fn deinit(self: *PravegatClient) void {
        self.http_client.deinit();
    }

    // ─── Public API ──────────────────────────────────────────────────────────

    /// Ensure the scope exists. Creates it if absent; 409 (already exists) is
    /// treated as success.
    pub fn ensureScope(self: *PravegatClient) !void {
        var url_buf: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(&url_buf, "{s}/v1/scopes", .{self.cfg.gateway_url});

        var body_buf: [256]u8 = undefined;
        const body = try std.fmt.bufPrint(&body_buf, "{{\"scopeName\":\"{s}\"}}", .{self.cfg.scope});

        const status = try self.postJson(url, body);
        if (status != 201 and status != 409) {
            return error.HttpError;
        }
    }

    /// Ensure the stream exists in the client's scope. 409 is ok.
    pub fn ensureStream(self: *PravegatClient, stream: []const u8) !void {
        var url_buf: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &url_buf,
            "{s}/v1/scopes/{s}/streams",
            .{ self.cfg.gateway_url, self.cfg.scope },
        );

        var body_buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(
            &body_buf,
            "{{\"streamName\":\"{s}\",\"scalingPolicy\":{{\"type\":\"FIXED_NUM_SEGMENTS\",\"minNumSegments\":1}},\"retentionPolicy\":{{\"type\":\"UNLIMITED\"}}}}",
            .{stream},
        );

        const status = try self.postJson(url, body);
        if (status != 201 and status != 409) {
            return error.HttpError;
        }
    }

    /// Write one event to the named stream.
    /// `routing_key` and `event_json` are caller-owned.
    /// The routing key is appended as `?routingKey=<key>` in the URL so that
    /// Pravega segments events by key (and so tests can capture it).
    pub fn writeEvent(
        self: *PravegatClient,
        stream: []const u8,
        routing_key: []const u8,
        event_json: []const u8,
    ) !void {
        var url_buf: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &url_buf,
            "{s}/v1/scopes/{s}/streams/{s}/events?routingKey={s}",
            .{ self.cfg.gateway_url, self.cfg.scope, stream, routing_key },
        );

        const status = try self.postJson(url, event_json);
        if (status != 201) {
            return error.HttpError;
        }
    }

    /// Create a reader group for the given stream. Returns the group name
    /// (caller must free with allocator).
    pub fn createReaderGroup(self: *PravegatClient, stream: []const u8) ![]u8 {
        const ts = std.time.nanoTimestamp();
        const rg_name = try std.fmt.allocPrint(
            self.allocator,
            "rg-{s}-{d}",
            .{ stream, @as(u64, @intCast(@mod(ts, 1_000_000_000_000_000_000))) },
        );
        errdefer self.allocator.free(rg_name);

        var url_buf: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &url_buf,
            "{s}/v1/scopes/{s}/readergroups",
            .{ self.cfg.gateway_url, self.cfg.scope },
        );

        var body_buf: [1024]u8 = undefined;
        const body = try std.fmt.bufPrint(
            &body_buf,
            "{{\"readerGroupName\":\"{s}\",\"streams\":[{{\"scopeName\":\"{s}\",\"streamName\":\"{s}\"}}]}}",
            .{ rg_name, self.cfg.scope, stream },
        );

        const status = try self.postJson(url, body);
        if (status != 201) {
            return error.HttpError;
        }
        return rg_name;
    }

    /// Create a reader in the given reader group. Returns the reader ID
    /// (caller must free with allocator).
    pub fn createReader(self: *PravegatClient, reader_group: []const u8) ![]u8 {
        const ts = std.time.nanoTimestamp();
        const reader_id = try std.fmt.allocPrint(
            self.allocator,
            "reader-{d}",
            .{@as(u64, @intCast(@mod(ts, 1_000_000_000_000_000_000)))},
        );
        errdefer self.allocator.free(reader_id);

        var url_buf: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &url_buf,
            "{s}/v1/scopes/{s}/readergroups/{s}/readers",
            .{ self.cfg.gateway_url, self.cfg.scope, reader_group },
        );

        var body_buf: [256]u8 = undefined;
        const body = try std.fmt.bufPrint(
            &body_buf,
            "{{\"readerId\":\"{s}\"}}",
            .{reader_id},
        );

        const status = try self.postJson(url, body);
        if (status != 201) {
            return error.HttpError;
        }
        return reader_id;
    }

    /// Read one event from a reader. Returns null if no events are available.
    /// Caller must free the returned slice with allocator.
    pub fn readEvent(
        self: *PravegatClient,
        reader_group: []const u8,
        reader_id: []const u8,
    ) !?[]u8 {
        var url_buf: [512]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &url_buf,
            "{s}/v1/scopes/{s}/readergroups/{s}/readers/{s}/events",
            .{ self.cfg.gateway_url, self.cfg.scope, reader_group, reader_id },
        );

        const uri = try std.Uri.parse(url);

        var req = try self.http_client.request(.GET, uri, .{
            .keep_alive = false,
        });
        defer req.deinit();

        try req.sendBodiless();

        var redirect_buf: [4096]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);

        const status = response.head.status;
        if (status != .ok) {
            return error.HttpError;
        }

        // Read body using allocRemaining (reads until connection closes / content-length).
        var transfer_buf: [4096]u8 = undefined;
        const body_reader = response.reader(&transfer_buf);
        const body = try body_reader.allocRemaining(self.allocator, .unlimited);
        errdefer self.allocator.free(body);

        // Empty body → no events.
        if (body.len == 0) {
            self.allocator.free(body);
            return null;
        }

        return body;
    }

    // ─── Internal helpers ────────────────────────────────────────────────────

    /// POST `body` as application/json to `url`. Returns the HTTP status code.
    /// Note: sendBodyComplete takes []u8 (mutable), so body must be mutable.
    /// Made `pub` so PravegatSubscriber can delegate checkpoint HTTP calls here.
    pub fn postJson(self: *PravegatClient, url: []const u8, body: []const u8) !u16 {
        const uri = try std.Uri.parse(url);

        const extra_headers: []const std.http.Header = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        };

        var req = try self.http_client.request(.POST, uri, .{
            .extra_headers = extra_headers,
            .keep_alive = false,
        });
        defer req.deinit();

        // sendBodyComplete requires a mutable slice — copy to a heap buffer.
        const body_copy = try self.allocator.dupe(u8, body);
        defer self.allocator.free(body_copy);

        try req.sendBodyComplete(body_copy);

        var redirect_buf: [4096]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);

        // Drain the body so the connection is properly closed.
        var transfer_buf: [4096]u8 = undefined;
        const rdr = response.reader(&transfer_buf);
        _ = rdr.discardRemaining() catch {};

        return @intFromEnum(response.head.status);
    }
};

```
