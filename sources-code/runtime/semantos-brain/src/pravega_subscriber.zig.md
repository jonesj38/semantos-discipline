---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/pravega_subscriber.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.249776+00:00
---

# runtime/semantos-brain/src/pravega_subscriber.zig

```zig
// M3.7 — PravegatSubscriber: adapter-side Pravega stream subscriber.
//
// Wraps PravegatClient's reader-group / reader creation and event polling
// behind a clean subscribe / readNext API.
//
// Lifecycle:
//   1. PravegatSubscriber.init(allocator, client) — does not own the client.
//   2. sub.subscribe(stream_name) → SubscriptionHandle — creates an RG + reader.
//   3. sub.readNext(&handle) → ?[]u8 — polls for the next event; null = empty.
//   4. handle.deinit() — frees stream, rg_name, reader_id copies.
//   5. sub.deinit() — no-op (client not owned).

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;

/// Owns the three string slices acquired during subscribe().
/// Call deinit() when no longer needed.
pub const SubscriptionHandle = struct {
    stream: []const u8,    // owned copy of the stream name
    rg_name: []const u8,   // owned copy returned by createReaderGroup
    reader_id: []const u8, // owned copy returned by createReader
    allocator: std.mem.Allocator,

    /// Free all owned slices.
    pub fn deinit(self: *SubscriptionHandle) void {
        self.allocator.free(self.stream);
        self.allocator.free(self.rg_name);
        self.allocator.free(self.reader_id);
    }
};

pub const PravegatSubscriber = struct {
    allocator: std.mem.Allocator,
    client: *PravegatClient,

    /// Initialise. Does NOT take ownership of `client`.
    pub fn init(allocator: std.mem.Allocator, client: *PravegatClient) PravegatSubscriber {
        return PravegatSubscriber{
            .allocator = allocator,
            .client = client,
        };
    }

    /// No-op — the client is not owned by this struct.
    pub fn deinit(self: *PravegatSubscriber) void {
        _ = self;
    }

    /// Subscribe to one stream.
    /// Calls createReaderGroup then createReader on the underlying client.
    /// Returns a SubscriptionHandle; caller must call handle.deinit() when done.
    pub fn subscribe(
        self: *PravegatSubscriber,
        stream_name: []const u8,
    ) !SubscriptionHandle {
        // Owned copy of the stream name (freed by handle.deinit).
        const stream_copy = try self.allocator.dupe(u8, stream_name);
        errdefer self.allocator.free(stream_copy);

        // createReaderGroup returns an allocated rg_name (caller must free).
        const rg_name = try self.client.createReaderGroup(stream_name);
        errdefer self.allocator.free(rg_name);

        // createReader returns an allocated reader_id (caller must free).
        const reader_id = try self.client.createReader(rg_name);
        errdefer self.allocator.free(reader_id);

        return SubscriptionHandle{
            .stream = stream_copy,
            .rg_name = rg_name,
            .reader_id = reader_id,
            .allocator = self.allocator,
        };
    }

    /// Poll the next event from a subscription.
    /// Returns null if no events are pending; otherwise returns the event JSON.
    /// The returned slice is allocated with self.allocator and must be freed by
    /// the caller (e.g. `defer self.allocator.free(event)`).
    pub fn readNext(
        self: *PravegatSubscriber,
        handle: *const SubscriptionHandle,
    ) !?[]u8 {
        return self.client.readEvent(handle.rg_name, handle.reader_id);
    }

    /// Checkpoint the reader group so restart resumes from current position.
    /// Calls Pravega gateway:
    ///   POST /v1/scopes/{scope}/streams/{stream}/readergroups/{rg}/checkpoints
    ///   Body: {"checkpointName":"<name>","readers":["<reader_id>"]}
    /// Returns the checkpoint name (caller must free with self.allocator).
    pub fn checkpoint(
        self: *PravegatSubscriber,
        handle: *const SubscriptionHandle,
        name: []const u8,
    ) ![]u8 {
        var url_buf: [1024]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &url_buf,
            "{s}/v1/scopes/{s}/streams/{s}/readergroups/{s}/checkpoints",
            .{
                self.client.cfg.gateway_url,
                self.client.cfg.scope,
                handle.stream,
                handle.rg_name,
            },
        );

        var body_buf: [1024]u8 = undefined;
        const body = try std.fmt.bufPrint(
            &body_buf,
            "{{\"checkpointName\":\"{s}\",\"readers\":[\"{s}\"]}}",
            .{ name, handle.reader_id },
        );

        const status = try self.client.postJson(url, body);
        if (status != 200 and status != 201) {
            return error.HttpError;
        }

        return self.allocator.dupe(u8, name);
    }

    /// Restore a reader group to a named checkpoint position.
    /// Calls Pravega gateway:
    ///   POST /v1/scopes/{scope}/streams/{stream}/readergroups/{rg}/checkpoints/{name}/restore
    /// The restored reader then picks up from that position.
    pub fn restoreCheckpoint(
        self: *PravegatSubscriber,
        handle: *const SubscriptionHandle,
        checkpoint_name: []const u8,
    ) !void {
        var url_buf: [1024]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &url_buf,
            "{s}/v1/scopes/{s}/streams/{s}/readergroups/{s}/checkpoints/{s}/restore",
            .{
                self.client.cfg.gateway_url,
                self.client.cfg.scope,
                handle.stream,
                handle.rg_name,
                checkpoint_name,
            },
        );

        const status = try self.client.postJson(url, "{}");
        if (status != 200 and status != 201 and status != 204) {
            return error.HttpError;
        }
    }
};

```
