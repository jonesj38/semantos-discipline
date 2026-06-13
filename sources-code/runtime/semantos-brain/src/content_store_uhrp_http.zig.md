---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/content_store_uhrp_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.238477+00:00
---

# runtime/semantos-brain/src/content_store_uhrp_http.zig

```zig
// M4.2 — UhrpHttpStore: HTTP-backed octave-2 content store.
//
// Stores slot → URL mappings and fetches 1024-byte windows via HTTP Range
// requests:
//   GET <url>
//   Range: bytes=<offset>-<offset+1023>
//
// The server must respond with HTTP 206 Partial Content and a body of at
// least 1024 bytes. Returns:
//   error.SlotNotRegistered — slot has no registered URL
//   error.HttpError         — server did not return 206 Partial Content
//   error.EndOfStream       — response body was < 1024 bytes
//
// UHRP pattern: slot URLs are typically "uhrp://<hash>" but any HTTP/HTTPS
// URL that supports Range requests is accepted. Resolution from uhrp:// to
// HTTP is the caller's responsibility (register the resolved URL).

const std = @import("std");

pub const UhrpHttpStore = struct {
    allocator: std.mem.Allocator,
    /// Base URL for resolving UHRP hashes, e.g. "https://content.example.com/uhrp/"
    /// NOT owned — caller keeps it live.
    base_url: []const u8,
    /// Slot → URL registry: maps slot(u32) → URL string (owned copies).
    slot_urls: std.AutoHashMap(u32, []u8),

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8) UhrpHttpStore {
        return .{
            .allocator = allocator,
            .base_url = base_url,
            .slot_urls = std.AutoHashMap(u32, []u8).init(allocator),
        };
    }

    pub fn deinit(self: *UhrpHttpStore) void {
        var it = self.slot_urls.valueIterator();
        while (it.next()) |url_ptr| {
            self.allocator.free(url_ptr.*);
        }
        self.slot_urls.deinit();
        self.slot_urls = undefined;
    }

    /// Register a URL for a slot (used by tests + runtime wiring).
    /// The URL string is duplicated; the caller does not need to keep it live.
    pub fn registerSlot(self: *UhrpHttpStore, slot: u32, url: []const u8) !void {
        const owned_url = try self.allocator.dupe(u8, url);
        errdefer self.allocator.free(owned_url);

        // If a URL was already registered for this slot, free the old one.
        if (self.slot_urls.fetchRemove(slot)) |kv| {
            self.allocator.free(kv.value);
        }

        try self.slot_urls.put(slot, owned_url);
    }

    /// Fetch exactly 1024 bytes at `offset` from the slot's registered URL.
    /// Makes an HTTP GET with Range header: "bytes=offset-(offset+1023)".
    ///
    /// Returns:
    ///   - void on success (1024 bytes written to `out`)
    ///   - error.SlotNotRegistered if slot has no URL
    ///   - error.HttpError if the response is not 206 Partial Content
    ///   - error.EndOfStream if response body < 1024 bytes
    pub fn fetchWindow(
        self: *UhrpHttpStore,
        slot: u32,
        offset: u32,
        out: *[1024]u8,
    ) !void {
        const url = self.slot_urls.get(slot) orelse return error.SlotNotRegistered;

        // Build the Range header value: "bytes=<offset>-<end>"
        const end: u64 = @as(u64, offset) + 1023;
        var range_buf: [64]u8 = undefined;
        const range_value = try std.fmt.bufPrint(
            &range_buf,
            "bytes={d}-{d}",
            .{ offset, end },
        );

        // Make the HTTP request.
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const extra_headers: []const std.http.Header = &.{
            .{ .name = "Range", .value = range_value },
        };

        const uri = try std.Uri.parse(url);

        // Build the request (bodiless GET).
        var req = try client.request(.GET, uri, .{
            .extra_headers = extra_headers,
            .keep_alive = false,
        });
        defer req.deinit();

        try req.sendBodiless();

        // Receive the response head. Use a stack buffer for the redirect path.
        var redirect_buf: [1024]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);

        // Check status: must be 206 Partial Content.
        if (response.head.status != .partial_content) {
            return error.HttpError;
        }

        // Read exactly 1024 bytes from the response body.
        // `reader` needs a transfer_buffer for internal HTTP framing.
        var transfer_buf: [1024]u8 = undefined;
        const body_reader = response.reader(&transfer_buf);
        const n = try body_reader.readSliceShort(out[0..1024]);
        if (n < 1024) {
            return error.EndOfStream;
        }
    }
};

```
