---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/identity_event_producer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.265757+00:00
---

# runtime/semantos-brain/src/identity_event_producer.zig

```zig
// M3.4 — IdentityEventProducer: emit cert mint/edge/revoke to Pravega.
//
// Events are written to the `identity-events` stream (or a caller-supplied
// stream name) via the M3.2 PravegatClient.  The routing key is always the
// cert_id hex string so all events for the same cert land on the same segment
// and are therefore consumed in FIFO order.
//
// Wire format (JSON):
//   {"kind":"mint","cert_id":"<hex64>","subject_pub":"<hex>","issuer_pub":"<hex>","ts_ms":<u64>,"seq":<u64>}
//   {"kind":"edge","cert_id":"<hex64>","subject_pub":"<hex64>","issuer_pub":"","ts_ms":<u64>,"seq":<u64>}
//   {"kind":"revoke","cert_id":"<hex64>","subject_pub":"","issuer_pub":"","ts_ms":<u64>,"seq":<u64>}
//
// For emitEdge, `cert_id` = from_cert_id (the routing key) and
// `subject_pub`  = to_cert_id.  `issuer_pub` is left empty.
//
// References:
//   - Matrix entry M3.4 in docs/design/
//   - runtime/semantos-brain/src/pravega_client.zig  (M3.2 PravegatClient)
//   - runtime/semantos-brain/src/identity_certs.zig  (cert mint/edge/revoke operations)

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;

// ─── Public types ─────────────────────────────────────────────────────────────

pub const EventKind = enum {
    mint,
    edge,
    revoke,

    pub fn wireName(self: EventKind) []const u8 {
        return switch (self) {
            .mint => "mint",
            .edge => "edge",
            .revoke => "revoke",
        };
    }
};

pub const IdentityEvent = struct {
    kind: EventKind,
    /// hex string, 64 chars (32 bytes → sha256 → first 16 bytes → hex)
    cert_id: []const u8,
    /// hex string for the subject / child pubkey; empty for revoke
    subject_pub: []const u8,
    /// hex string for the issuer / root pubkey; empty for self-signed or revoke
    issuer_pub: []const u8,
    timestamp_ms: u64,
    /// Monotonically increasing per-producer; starts at 0
    sequence: u64,
};

// ─── Producer ─────────────────────────────────────────────────────────────────

pub const IdentityEventProducer = struct {
    allocator: std.mem.Allocator,
    client: *PravegatClient,
    stream: []const u8,
    /// Incremented after every successful emit.  Starts at 0.
    sequence: u64,

    /// Initialise.  `stream` is borrowed — caller keeps it alive.
    pub fn init(
        allocator: std.mem.Allocator,
        client: *PravegatClient,
        stream: []const u8,
    ) IdentityEventProducer {
        return .{
            .allocator = allocator,
            .client = client,
            .stream = stream,
            .sequence = 0,
        };
    }

    pub fn deinit(self: *IdentityEventProducer) void {
        _ = self;
    }

    // ── Emit helpers ──────────────────────────────────────────────────────────

    /// Emit a `mint` event.  `cert_id`, `subject_pub`, `issuer_pub` are hex
    /// strings owned by the caller.
    pub fn emitMint(
        self: *IdentityEventProducer,
        cert_id: []const u8,
        subject_pub: []const u8,
        issuer_pub: []const u8,
        now_ms: u64,
    ) !void {
        const event = IdentityEvent{
            .kind = .mint,
            .cert_id = cert_id,
            .subject_pub = subject_pub,
            .issuer_pub = issuer_pub,
            .timestamp_ms = now_ms,
            .sequence = self.sequence,
        };
        try self.emit(event, cert_id);
    }

    /// Emit an `edge` event.  The routing key is `from_cert_id`.
    /// `to_cert_id` is encoded in the `subject_pub` field so the consumer
    /// can reconstruct the DAG edge without additional lookups.
    pub fn emitEdge(
        self: *IdentityEventProducer,
        from_cert_id: []const u8,
        to_cert_id: []const u8,
        now_ms: u64,
    ) !void {
        const event = IdentityEvent{
            .kind = .edge,
            .cert_id = from_cert_id,
            .subject_pub = to_cert_id,
            .issuer_pub = "",
            .timestamp_ms = now_ms,
            .sequence = self.sequence,
        };
        try self.emit(event, from_cert_id);
    }

    /// Emit a `revoke` event.
    pub fn emitRevoke(
        self: *IdentityEventProducer,
        cert_id: []const u8,
        now_ms: u64,
    ) !void {
        const event = IdentityEvent{
            .kind = .revoke,
            .cert_id = cert_id,
            .subject_pub = "",
            .issuer_pub = "",
            .timestamp_ms = now_ms,
            .sequence = self.sequence,
        };
        try self.emit(event, cert_id);
    }

    /// Build the event JSON.  Caller must free with `self.allocator`.
    pub fn buildPayload(self: *IdentityEventProducer, event: IdentityEvent) ![]u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "{{\"kind\":\"{s}\",\"cert_id\":\"{s}\",\"subject_pub\":\"{s}\",\"issuer_pub\":\"{s}\",\"ts_ms\":{d},\"seq\":{d}}}",
            .{
                event.kind.wireName(),
                event.cert_id,
                event.subject_pub,
                event.issuer_pub,
                event.timestamp_ms,
                event.sequence,
            },
        );
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    fn emit(
        self: *IdentityEventProducer,
        event: IdentityEvent,
        routing_key: []const u8,
    ) !void {
        const payload = try self.buildPayload(event);
        defer self.allocator.free(payload);

        try self.client.writeEvent(self.stream, routing_key, payload);
        self.sequence += 1;
    }
};

```
