---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/mfp_tick_producer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.225709+00:00
---

# runtime/semantos-brain/src/mfp_tick_producer.zig

```zig
// M3.6 — MfpTickProducer: per-channel MFP tick stream producer.
//
// Each MFP (Micro-Fee Protocol) channel tick is emitted to the `mfp-ticks`
// Pravega stream via PravegatClient.writeEvent.
//
// Tick JSON schema:
//   {
//     "channel_id": "<hex>",
//     "n_sequence": <u32>,
//     "value_sats": <u64>,
//     "hmac": "<64-char lowercase hex of HMAC-SHA256>",
//     "ts_ms": <u64 milliseconds>
//   }
//
// HMAC input (all little-endian):
//   channel_id_bytes (raw bytes, NOT hex) || n_sequence_LE4 || value_sats_LE8
//
// Routing key passed to writeEvent is `channel_id` (preserves per-channel
// ordering in Pravega).
//
// Usage:
//   var producer = MfpTickProducer.init(alloc, &client, "mfp-ticks", "chan-abc");
//   defer producer.deinit();
//   try producer.emitTick(&secret, value_sats, std.time.milliTimestamp());

const std = @import("std");
const pravega_client = @import("pravega_client");
const PravegatClient = pravega_client.PravegatClient;

const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

pub const MfpTickProducer = struct {
    allocator: std.mem.Allocator,
    /// Non-owning pointer — caller keeps PravegatClient alive.
    client: *PravegatClient,
    /// Pravega stream name (e.g. "mfp-ticks"). Not owned.
    stream: []const u8,
    /// Channel identifier (hex string). Not owned.
    channel_id: []const u8,
    /// Current nSequence; starts at 0 and increments on each emitTick.
    n_sequence: u32,

    /// Initialise producer. Does not connect — all I/O is deferred to emitTick.
    pub fn init(
        allocator: std.mem.Allocator,
        client: *PravegatClient,
        stream: []const u8,
        channel_id: []const u8,
    ) MfpTickProducer {
        return .{
            .allocator = allocator,
            .client = client,
            .stream = stream,
            .channel_id = channel_id,
            .n_sequence = 0,
        };
    }

    /// No heap allocations held by the producer itself.
    pub fn deinit(self: *MfpTickProducer) void {
        _ = self;
    }

    /// Emit one tick to the configured Pravega stream.
    ///
    /// `secret` — 32-byte HMAC key (channel shared secret).
    /// `value_sats` — payment amount in satoshis.
    /// `now_ms` — current wall-clock in milliseconds (caller-supplied for
    ///   deterministic testing).
    ///
    /// n_sequence is used for the current tick, then incremented.
    pub fn emitTick(
        self: *MfpTickProducer,
        secret: *const [32]u8,
        value_sats: u64,
        now_ms: u64,
    ) !void {
        const hmac_bytes = computeHmac(self.channel_id, self.n_sequence, value_sats, secret);

        const payload = try self.buildPayload(&hmac_bytes, value_sats, now_ms);
        defer self.allocator.free(payload);

        // Routing key is channel_id to preserve per-channel ordering in Pravega.
        try self.client.writeEvent(self.stream, self.channel_id, payload);

        // Increment only after successful write so callers can retry on error.
        self.n_sequence +%= 1;
    }

    /// Compute HMAC-SHA256 for a tick event.
    ///
    /// Message = channel_id_bytes (raw, NOT hex)
    ///         || n_sequence as u32 little-endian (4 bytes)
    ///         || value_sats as u64 little-endian (8 bytes)
    ///
    /// Exposed as pub so tests can compute the expected value independently.
    pub fn computeHmac(
        channel_id_bytes: []const u8,
        n_sequence: u32,
        value_sats: u64,
        secret: *const [32]u8,
    ) [32]u8 {
        var mac = HmacSha256.init(secret);
        mac.update(channel_id_bytes);

        var seq_le: [4]u8 = undefined;
        std.mem.writeInt(u32, &seq_le, n_sequence, .little);
        mac.update(&seq_le);

        var sats_le: [8]u8 = undefined;
        std.mem.writeInt(u64, &sats_le, value_sats, .little);
        mac.update(&sats_le);

        var out: [32]u8 = undefined;
        mac.final(&out);
        return out;
    }

    /// Build the tick JSON payload. Caller must free the returned slice with
    /// `producer.allocator`.
    ///
    /// Uses n_sequence at the time of the call (before the post-tick increment).
    pub fn buildPayload(
        self: *const MfpTickProducer,
        hmac_bytes: *const [32]u8,
        value_sats: u64,
        now_ms: u64,
    ) ![]u8 {
        // Format HMAC as 64-char lowercase hex string.
        const hmac_hex = std.fmt.bytesToHex(hmac_bytes.*, .lower);

        return std.fmt.allocPrint(
            self.allocator,
            "{{\"channel_id\":\"{s}\",\"n_sequence\":{d},\"value_sats\":{d},\"hmac\":\"{s}\",\"ts_ms\":{d}}}",
            .{
                self.channel_id,
                self.n_sequence,
                value_sats,
                hmac_hex,
                now_ms,
            },
        );
    }
};

```
