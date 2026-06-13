---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/device_pair.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.227689+00:00
---

# runtime/semantos-brain/src/device_pair.zig

```zig
// Phase D-W1 / Phase 1 follow-up — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3
// (the identity_certs row), docs/design/ODDJOBZ-EXTENSION-PLAN.md §3
// phase O5p (lines around 268-285), §11 (operator's perspective);
// docs/spec/protocol-v0.5.md §4.4 (per-device contextTag isolation,
// the BKDS substrate the pair flow rides on).
//
// What this module does:
//
//   • Builds + signs the pairing PAYLOAD that `brain device pair` emits
//     and `brain device claim` (or, in production, the device's Flutter
//     app) consumes.
//   • Parses + verifies an inbound payload, surfacing typed errors
//     for the failure modes the operator + tests care about
//     (`pairing_payload_expired`, `pairing_payload_consumed`,
//     `pairing_payload_invalid_signature`, etc.).
//   • Allocates the next unused `context_tag` (starting at `0x10` for
//     the first paired device, increment by 1) by walking the cert
//     store's live index.
//   • Persists a one-shot nonce ledger at `<data_dir>/pairing-nonces.log`
//     so a payload claimed once cannot be claimed again across
//     daemon restarts.
//
// ─── Pairing payload wire shape ───────────────────────────────────────
//
// JSON object base64url-encoded into a URL query string.  Patterned
// after the existing JSON envelope shape in `wire.zig`.  The signature
// is computed over the canonical-bytes serialization of the payload
// (with the `signature` field omitted) — same domain-separator
// convention the BKDS invoice uses.
//
// D-O5p note (wire format choice — JSON vs CBOR):
//   ODDJOBZ-EXTENSION-PLAN.md §3 phase O5p-a calls for a CBOR-encoded
//   payload.  We retain JSON+base64url (the shape #281 shipped) plus
//   the additional fields O5p-c needs (brain WSS endpoint + cert
//   pinning data).  Justification:
//     • neither bsvz nor any current brain dep ships a CBOR codec;
//       pulling one in is a multi-deliverable effort
//     • the spec language is "CBOR-encoded" (descriptive) not "MUST
//       be CBOR" (normative) — the load-bearing properties are
//       canonical-bytes signing + tagged versioning + the field set
//     • base64url-of-JSON encodes about 1.4× larger than CBOR for
//       this payload (~900 bytes after fields) but still fits in
//       QR V25-V40 byte mode; size is not a blocker
//     • the field set is what determines forward compatibility, and
//       a v3 CBOR migration is a one-PR follow-up: emit both
//       encodings, rev parser to accept both, deprecate v2 JSON one
//       wave later
//   See PR #281 for the v1 baseline; this PR ships v2.
//
// D-O5p schema (v2):
// {
//   "v": 2,
//   "domain": "brain-device-pair-v2",
//   "operator_root_cert_id": "<32 hex>",
//   "operator_root_pub": "<66 hex / 33 bytes compressed SEC1>",
//   "context_tag": <u8>,
//   "label": "<utf-8 string, ≤256 bytes>",
//   "capabilities": ["cap.X.Y", "cap.A.B", ...],
//   "expires_at": <unix-seconds, +300s from issue>,
//   "nonce": "<32 hex / 16 random bytes>",
//   "brain_pair_endpoint": "<https? URL ≤512 bytes>",
//     // production HTTP POST URL the device claim flow targets, e.g.
//     // "https://oddjobtodd.info/api/v1/device-pair".
//   "brain_wss_endpoint": "<wss URL ≤512 bytes>",
//     // post-pair operations channel, e.g.
//     // "wss://oddjobtodd.info/api/v1/wallet".
//   "brain_pin_cert_id": "<32 hex>",
//     // mirror of operator_root_cert_id for cert pinning at the
//     // device side.  Keeping it as a separate field documents the
//     // intent + makes it explicit which value the device pins.
//   "brain_pin_pubkey": "<66 hex>",
//     // mirror of operator_root_pub for the same reason — the device
//     // pins (cert_id, pubkey) so a man-in-the-middle that swaps the
//     // brain's TLS cert can't redirect the registration payload.
//   "signature": "<DER-encoded ECDSA-SHA256, hex>"
// }
//
// v1 → v2 compatibility: receivers reject v1 with `pairing_payload_
// unknown_version`.  v1 was the lab-fixture wire format from PR #281
// and is not guaranteed to be in operator hands; bumping forces a
// fresh `brain device pair` → `brain device claim` cycle.
//
// `signature` is over the SHA-256 of the canonical payload-without-
// signature bytes.  The canonical encoding is the JSON object with
// keys in alphabetical order, no whitespace, no signature field.  We
// hand-build this via a small writer rather than relying on a JSON
// library's default ordering.
//
// ─── URL form ─────────────────────────────────────────────────────────
//
// The CLI emits two equivalent forms:
//
//   1. URL form: `semantos-pair://<brain-domain>/pair?token=<base64url>`
//      where `<base64url>` is the base64url-encoded payload JSON.
//      Length grows with capabilities + label; typically ~600-1000
//      bytes which fits comfortably in any QR code (alphanumeric
//      mode; ~4296 byte cap on V40).
//
//   2. Plain token form: just the base64url string.  Useful for
//      copy-paste workflows where the URL scheme isn't desired.
//
// `brain device claim --token <...>` accepts either: it strips the
// scheme + path + query if present.
//
// ─── Capability allowlist resolution ──────────────────────────────────
//
// The CLI accepts three forms via `--caps`:
//
//   `minimal` → ["cap.attach.photo", "cap.attach.gps", "cap.attach.voice"]
//   `full`    → minimal ++ ["cap.oddjobz.write_customer",
//                            "cap.oddjobz.public_chat_serve"]
//   `cap.X,cap.Y,...` → custom comma-separated list, validated for
//                       cap-name shape (dotted-namespace, ≤128 chars).
//
// The `cap.attach.{photo,gps,voice}` cap names are NEW cap names
// referenced in the pair payload allowlist but they don't yet need
// to be minted at first-boot like the oddjobz caps in PR #279 —
// they're declared in the pair payload as future-cap references.
// They'll be minted later (likely D-O5m / D-O5p when the device-side
// claim flow's first real consumer surfaces).

const std = @import("std");
const bsvz = @import("bsvz");
const bkds = @import("bkds");

pub const Error = error{
    /// Combined input failed to encode (allocator OOM or shape
    /// violation upstream of us).
    pairing_payload_encode_failed,
    /// Inbound payload was not valid base64url + JSON.
    pairing_payload_invalid_format,
    /// Inbound payload's `domain` or `v` fields didn't match what we
    /// build.  Defensive against future wire-format bumps.
    pairing_payload_unknown_version,
    /// Inbound payload has expired.
    pairing_payload_expired,
    /// One-shot nonce was already consumed by an earlier `claim`.
    pairing_payload_consumed,
    /// Signature verify failed against the embedded operator pubkey.
    pairing_payload_invalid_signature,
    /// One of the supplied capability names didn't match the dotted-
    /// namespace shape.
    pairing_payload_invalid_capability,
    /// `label` exceeded the spec'd byte cap.
    pairing_payload_label_too_long,
    /// `context_tag` allocation failed (255 children already paired).
    pairing_payload_no_context_tag,
    /// Underlying file I/O on the nonce ledger failed.
    pairing_payload_nonce_store_failed,
    /// Allocator OOM.
    out_of_memory,
};

/// Lifetime of an emitted pairing payload — 5 minutes.  The brief
/// pins this; mismatch will cause `pairing_payload_expired` on
/// receivers that disagree.
pub const PAYLOAD_TTL_SECONDS: i64 = 300;

/// First context_tag we hand out for a paired device (carpenter slot
/// per §2.5 of the dispatcher unification doc; musician = 0x11, etc).
/// 0x00..0x0F is reserved for the operator + future system-context
/// tags; we start at 0x10.
pub const FIRST_CHILD_CONTEXT_TAG: u8 = 0x10;

/// Hard cap on label length.  Mirrors `bkds.MAX_LABEL_LEN` so the
/// claim path's invoice construction can't surface a different ceiling.
pub const MAX_LABEL_LEN: usize = 256;

/// Hard cap on the number of capabilities we'll embed in a single
/// payload.  Defensive against runaway operator input.
pub const MAX_CAPABILITIES: usize = 64;

/// Wire-domain version tag.  Bumping this requires a coordinated bump
/// on the device-side parser too; receivers reject unknown values
/// loudly via `pairing_payload_unknown_version`.
///
/// v1: PR #281 lab-fixture baseline.  Did not include the brain
///     endpoint / cert-pinning fields the device needs for production
///     registration.  Receivers in this build reject v1.
/// v2: D-O5p production close-out — adds brain_pair_endpoint,
///     brain_wss_endpoint, brain_pin_cert_id, brain_pin_pubkey.
pub const WIRE_DOMAIN: []const u8 = "brain-device-pair-v2";

pub const WIRE_VERSION: u32 = 2;

/// Hard cap on URL length.  Defensive against runaway operator input
/// and against the QR-mode-V40 ceiling of ~7000 alphanumeric chars
/// (we want plenty of headroom for a fully-loaded payload + caps list).
pub const MAX_BRAIN_URL_LEN: usize = 512;

/// One-shot nonce length: 16 bytes (32 hex chars) of CSPRNG output.
/// Birthday-collision-free for any realistic pairing volume.
pub const NONCE_LEN: usize = 16;

// ─────────────────────────────────────────────────────────────────────
// Payload shapes
// ─────────────────────────────────────────────────────────────────────

/// Constructed-side view: what `brain device pair` builds on the
/// operator's brain.  Field names mirror the JSON wire shape.
pub const PairPayload = struct {
    /// Operator's root cert id (32 hex chars).
    operator_root_cert_id: [32]u8,
    /// 33-byte compressed-SEC1 secp256k1 root pubkey.
    operator_root_pub: [bkds.PUBKEY_LEN]u8,
    /// Context tag this device will be issued under (0x10, 0x11, ...).
    context_tag: u8,
    /// Operator-supplied label (sanitised).  Owned by the caller.
    label: []const u8,
    /// Capability allowlist.  Slice-of-slices, owned by the caller.
    capabilities: []const []const u8,
    /// Unix-seconds, 5 minutes after issue.
    expires_at: i64,
    /// 16-byte CSPRNG nonce for one-shot consumption.
    nonce: [NONCE_LEN]u8,
    /// D-O5p — production HTTP endpoint the device POSTs its
    /// `claim_child` payload to (e.g. `https://oddjobtodd.info/
    /// api/v1/device-pair`).  Owned by the caller.
    brain_pair_endpoint: []const u8,
    /// D-O5p — post-pair operations WSS endpoint the device opens
    /// once registered (e.g. `wss://oddjobtodd.info/api/v1/wallet`).
    /// Owned by the caller.
    brain_wss_endpoint: []const u8,
    /// D-O5p — cert pinning value the device pins.  Same value as
    /// `operator_root_cert_id`; kept distinct so the field is
    /// explicit at the wire level + a future fork (delegated brain,
    /// where the device pins a sub-cert id) is a one-field rev.
    brain_pin_cert_id: [32]u8,
    /// D-O5p — pubkey the device pins.  Same value as
    /// `operator_root_pub`; same explicitness rationale.
    brain_pin_pubkey: [bkds.PUBKEY_LEN]u8,
};

/// Validate a brain endpoint URL.  Length-bounded; must start with
/// `https://` (HTTP path) or `wss://` (WSS path); ASCII printable.
pub fn isValidBrainUrl(url: []const u8, comptime scheme: []const u8) bool {
    if (url.len < scheme.len + 1) return false;
    if (url.len > MAX_BRAIN_URL_LEN) return false;
    if (!std.mem.startsWith(u8, url, scheme)) return false;
    for (url) |b| {
        if (b < 0x20 or b > 0x7e) return false;
    }
    return true;
}

/// Sanitise a CLI-supplied label: strip leading/trailing whitespace,
/// reject empty results, reject runaway length.  Returns a
/// caller-allocated copy of the cleaned bytes.
pub fn sanitiseLabel(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return Error.pairing_payload_invalid_format;
    if (trimmed.len > MAX_LABEL_LEN) return Error.pairing_payload_label_too_long;
    return try allocator.dupe(u8, trimmed);
}

/// Validate a single cap name: dotted-namespace ASCII printable,
/// 4..128 chars, must start with `cap.`.
pub fn isValidCapability(name: []const u8) bool {
    if (name.len < 4 or name.len > 128) return false;
    if (!std.mem.startsWith(u8, name, "cap.")) return false;
    for (name) |c| {
        const ok = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '.' or c == '_' or c == '-' or c == ':';
        if (!ok) return false;
    }
    // No empty segments (no consecutive dots, no trailing dot).
    if (std.mem.indexOf(u8, name, "..") != null) return false;
    if (name[name.len - 1] == '.') return false;
    return true;
}

pub const Caps = struct {
    /// Dynamically-allocated slice-of-slices.  Caller owns every
    /// inner slice + the outer allocation.
    items: [][]u8,

    pub fn deinit(self: Caps, allocator: std.mem.Allocator) void {
        for (self.items) |c| allocator.free(c);
        if (self.items.len > 0) allocator.free(self.items);
    }
};

/// Resolve the `--caps` arg into a concrete capability allowlist.
/// Three accepted forms — see the file header for the policy.
pub fn resolveCaps(allocator: std.mem.Allocator, raw: []const u8) !Caps {
    if (std.mem.eql(u8, raw, "minimal")) {
        return makeStaticCaps(allocator, &[_][]const u8{
            "cap.attach.photo",
            "cap.attach.gps",
            "cap.attach.voice",
        });
    }
    if (std.mem.eql(u8, raw, "full")) {
        return makeStaticCaps(allocator, &[_][]const u8{
            "cap.attach.photo",
            "cap.attach.gps",
            "cap.attach.voice",
            "cap.oddjobz.write_customer",
            "cap.oddjobz.public_chat_serve",
        });
    }
    // Custom: comma-separated list.
    var list: std.ArrayList([]u8) = .{};
    errdefer {
        for (list.items) |c| allocator.free(c);
        list.deinit(allocator);
    }
    var it = std.mem.splitScalar(u8, raw, ',');
    while (it.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, " \t");
        if (part.len == 0) continue;
        if (!isValidCapability(part)) return Error.pairing_payload_invalid_capability;
        if (list.items.len >= MAX_CAPABILITIES) return Error.pairing_payload_invalid_capability;
        const owned = try allocator.dupe(u8, part);
        try list.append(allocator, owned);
    }
    if (list.items.len == 0) return Error.pairing_payload_invalid_capability;
    const slice = try list.toOwnedSlice(allocator);
    return .{ .items = slice };
}

fn makeStaticCaps(allocator: std.mem.Allocator, names: []const []const u8) !Caps {
    var list: std.ArrayList([]u8) = .{};
    errdefer {
        for (list.items) |c| allocator.free(c);
        list.deinit(allocator);
    }
    for (names) |n| {
        const owned = try allocator.dupe(u8, n);
        try list.append(allocator, owned);
    }
    return .{ .items = try list.toOwnedSlice(allocator) };
}

// ─────────────────────────────────────────────────────────────────────
// Canonical encoding for signing
// ─────────────────────────────────────────────────────────────────────

/// Build the canonical JSON bytes the signature is computed over.
/// Keys in alphabetical order, no whitespace, no signature field.
/// Returns caller-allocated bytes.
pub fn canonicalJsonForSigning(
    allocator: std.mem.Allocator,
    payload: PairPayload,
) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    var operator_pub_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&payload.operator_root_pub, &operator_pub_hex);
    var pin_pub_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&payload.brain_pin_pubkey, &pin_pub_hex);
    var nonce_hex: [NONCE_LEN * 2]u8 = undefined;
    bkds.hexEncode(&payload.nonce, &nonce_hex);

    // Alphabetical key order: brain_pair_endpoint, brain_pin_cert_id,
    // brain_pin_pubkey, brain_wss_endpoint, capabilities, context_tag,
    // domain, expires_at, label, nonce, operator_root_cert_id,
    // operator_root_pub, v.
    try buf.appendSlice(allocator, "{\"brain_pair_endpoint\":");
    try writeJsonString(allocator, &buf, payload.brain_pair_endpoint);
    try buf.appendSlice(allocator, ",\"brain_pin_cert_id\":\"");
    try buf.appendSlice(allocator, &payload.brain_pin_cert_id);
    try buf.appendSlice(allocator, "\",\"brain_pin_pubkey\":\"");
    try buf.appendSlice(allocator, &pin_pub_hex);
    try buf.appendSlice(allocator, "\",\"brain_wss_endpoint\":");
    try writeJsonString(allocator, &buf, payload.brain_wss_endpoint);
    try buf.appendSlice(allocator, ",\"capabilities\":[");
    for (payload.capabilities, 0..) |c, i| {
        if (i != 0) try buf.append(allocator, ',');
        try writeJsonString(allocator, &buf, c);
    }
    try buf.appendSlice(allocator, "],");
    try buf.print(allocator, "\"context_tag\":{d},", .{payload.context_tag});
    try buf.appendSlice(allocator, "\"domain\":\"");
    try buf.appendSlice(allocator, WIRE_DOMAIN);
    try buf.appendSlice(allocator, "\",");
    try buf.print(allocator, "\"expires_at\":{d},", .{payload.expires_at});
    try buf.appendSlice(allocator, "\"label\":");
    try writeJsonString(allocator, &buf, payload.label);
    try buf.appendSlice(allocator, ",\"nonce\":\"");
    try buf.appendSlice(allocator, &nonce_hex);
    try buf.appendSlice(allocator, "\",\"operator_root_cert_id\":\"");
    try buf.appendSlice(allocator, &payload.operator_root_cert_id);
    try buf.appendSlice(allocator, "\",\"operator_root_pub\":\"");
    try buf.appendSlice(allocator, &operator_pub_hex);
    try buf.appendSlice(allocator, "\",");
    try buf.print(allocator, "\"v\":{d}", .{WIRE_VERSION});
    try buf.append(allocator, '}');
    return buf.toOwnedSlice(allocator);
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

// ─────────────────────────────────────────────────────────────────────
// Build + sign the on-the-wire token
// ─────────────────────────────────────────────────────────────────────

pub const SignedToken = struct {
    /// Caller-owned base64url-encoded signed JSON.
    base64url: []u8,
    /// Caller-owned raw signed JSON (with signature embedded).  Useful
    /// for tests + debug printing.
    json: []u8,

    pub fn deinit(self: SignedToken, allocator: std.mem.Allocator) void {
        allocator.free(self.base64url);
        allocator.free(self.json);
    }
};

/// Sign + encode the payload.  The signature covers
/// `canonicalJsonForSigning(payload)` (SHA-256, ECDSA over the
/// operator's root priv).  The on-the-wire JSON adds the signature
/// at canonical-keys order — the receiver re-derives the canonical
/// bytes by stripping `signature` from the parsed object.
pub fn signAndEncode(
    allocator: std.mem.Allocator,
    payload: PairPayload,
    operator_root_priv: [bkds.PRIVKEY_LEN]u8,
) !SignedToken {
    const canonical = try canonicalJsonForSigning(allocator, payload);
    defer allocator.free(canonical);

    // SHA-256 of canonical bytes; ECDSA over secp256k1.
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical, &digest, .{});

    const priv = bsvz.primitives.ec.PrivateKey.fromBytes(operator_root_priv) catch
        return Error.pairing_payload_encode_failed;
    const sig_obj = priv.signDigest(digest) catch return Error.pairing_payload_encode_failed;
    const sig_bytes = sig_obj.asSlice();
    const sig_hex = try allocator.alloc(u8, sig_bytes.len * 2);
    defer allocator.free(sig_hex);
    bkds.hexEncode(sig_bytes, sig_hex);

    // Re-emit with signature at the canonical position
    // (alphabetically: signature falls between operator_root_pub and v).
    var operator_pub_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&payload.operator_root_pub, &operator_pub_hex);
    var pin_pub_hex: [bkds.PUBKEY_LEN * 2]u8 = undefined;
    bkds.hexEncode(&payload.brain_pin_pubkey, &pin_pub_hex);
    var nonce_hex: [NONCE_LEN * 2]u8 = undefined;
    bkds.hexEncode(&payload.nonce, &nonce_hex);

    var json: std.ArrayList(u8) = .{};
    errdefer json.deinit(allocator);
    try json.appendSlice(allocator, "{\"brain_pair_endpoint\":");
    try writeJsonString(allocator, &json, payload.brain_pair_endpoint);
    try json.appendSlice(allocator, ",\"brain_pin_cert_id\":\"");
    try json.appendSlice(allocator, &payload.brain_pin_cert_id);
    try json.appendSlice(allocator, "\",\"brain_pin_pubkey\":\"");
    try json.appendSlice(allocator, &pin_pub_hex);
    try json.appendSlice(allocator, "\",\"brain_wss_endpoint\":");
    try writeJsonString(allocator, &json, payload.brain_wss_endpoint);
    try json.appendSlice(allocator, ",\"capabilities\":[");
    for (payload.capabilities, 0..) |c, i| {
        if (i != 0) try json.append(allocator, ',');
        try writeJsonString(allocator, &json, c);
    }
    try json.appendSlice(allocator, "],");
    try json.print(allocator, "\"context_tag\":{d},", .{payload.context_tag});
    try json.appendSlice(allocator, "\"domain\":\"");
    try json.appendSlice(allocator, WIRE_DOMAIN);
    try json.appendSlice(allocator, "\",");
    try json.print(allocator, "\"expires_at\":{d},", .{payload.expires_at});
    try json.appendSlice(allocator, "\"label\":");
    try writeJsonString(allocator, &json, payload.label);
    try json.appendSlice(allocator, ",\"nonce\":\"");
    try json.appendSlice(allocator, &nonce_hex);
    try json.appendSlice(allocator, "\",\"operator_root_cert_id\":\"");
    try json.appendSlice(allocator, &payload.operator_root_cert_id);
    try json.appendSlice(allocator, "\",\"operator_root_pub\":\"");
    try json.appendSlice(allocator, &operator_pub_hex);
    try json.appendSlice(allocator, "\",\"signature\":\"");
    try json.appendSlice(allocator, sig_hex);
    try json.appendSlice(allocator, "\",");
    try json.print(allocator, "\"v\":{d}", .{WIRE_VERSION});
    try json.append(allocator, '}');

    const json_owned = try json.toOwnedSlice(allocator);
    errdefer allocator.free(json_owned);

    // Base64url encode, no padding.
    const enc = std.base64.url_safe_no_pad.Encoder;
    const out_len = enc.calcSize(json_owned.len);
    const b64 = try allocator.alloc(u8, out_len);
    errdefer allocator.free(b64);
    _ = enc.encode(b64, json_owned);

    return .{ .base64url = b64, .json = json_owned };
}

/// Build the URL form: `semantos-pair://<brain-domain>/pair?token=<...>`.
pub fn pairUrl(
    allocator: std.mem.Allocator,
    brain_domain: []const u8,
    token: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "semantos-pair://{s}/pair?token={s}", .{ brain_domain, token });
}

// ─────────────────────────────────────────────────────────────────────
// Parse + verify
// ─────────────────────────────────────────────────────────────────────

/// Parsed-side view of an inbound payload.  Owns its strings.
pub const ParsedPayload = struct {
    operator_root_cert_id: [32]u8,
    operator_root_pub: [bkds.PUBKEY_LEN]u8,
    context_tag: u8,
    label: []u8,
    capabilities: [][]u8,
    expires_at: i64,
    nonce: [NONCE_LEN]u8,
    brain_pair_endpoint: []u8,
    brain_wss_endpoint: []u8,
    brain_pin_cert_id: [32]u8,
    brain_pin_pubkey: [bkds.PUBKEY_LEN]u8,

    pub fn deinit(self: ParsedPayload, allocator: std.mem.Allocator) void {
        allocator.free(self.label);
        for (self.capabilities) |c| allocator.free(c);
        if (self.capabilities.len > 0) allocator.free(self.capabilities);
        allocator.free(self.brain_pair_endpoint);
        allocator.free(self.brain_wss_endpoint);
    }
};

/// Strip a `semantos-pair://...?token=<...>` URL down to the bare
/// base64url token.  If `input` doesn't start with the scheme, return
/// it as-is (caller passed the bare token).
pub fn extractToken(input: []const u8) []const u8 {
    if (std.mem.indexOf(u8, input, "?token=")) |idx| {
        return input[idx + "?token=".len ..];
    }
    return input;
}

/// Parse + verify a pairing payload.  Returns an owned `ParsedPayload`
/// on success.  Errors are typed; the CLI maps them to operator-
/// readable messages.
///
/// Verification steps, in order:
///   1. base64url decode → JSON parse
///   2. version + domain check
///   3. embedded signature verifies under embedded operator pubkey
///      (defends against payload tampering — the brain compares the
///      pubkey against its own root cert separately)
///   4. expires_at > now (caller passes `now`)
///
/// One-shot nonce consumption is NOT performed here; that's
/// `NonceLedger.markConsumed`, called by the CLI after the cert
/// issue succeeds.
pub fn parseAndVerify(
    allocator: std.mem.Allocator,
    token: []const u8,
    now_unix: i64,
) !ParsedPayload {
    const dec = std.base64.url_safe_no_pad.Decoder;
    const json_len = dec.calcSizeForSlice(token) catch return Error.pairing_payload_invalid_format;
    const json_buf = try allocator.alloc(u8, json_len);
    defer allocator.free(json_buf);
    dec.decode(json_buf, token) catch return Error.pairing_payload_invalid_format;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_buf, .{}) catch
        return Error.pairing_payload_invalid_format;
    defer parsed.deinit();
    if (parsed.value != .object) return Error.pairing_payload_invalid_format;
    const obj = parsed.value.object;

    // Version / domain.
    {
        const v = obj.get("v") orelse return Error.pairing_payload_unknown_version;
        if (v != .integer or v.integer != WIRE_VERSION) return Error.pairing_payload_unknown_version;
        const dom = obj.get("domain") orelse return Error.pairing_payload_unknown_version;
        if (dom != .string or !std.mem.eql(u8, dom.string, WIRE_DOMAIN))
            return Error.pairing_payload_unknown_version;
    }

    // Cert id + pub.
    var operator_root_cert_id: [32]u8 = undefined;
    {
        const v = obj.get("operator_root_cert_id") orelse return Error.pairing_payload_invalid_format;
        if (v != .string or v.string.len != 32) return Error.pairing_payload_invalid_format;
        @memcpy(&operator_root_cert_id, v.string);
    }

    var operator_root_pub: [bkds.PUBKEY_LEN]u8 = undefined;
    {
        const v = obj.get("operator_root_pub") orelse return Error.pairing_payload_invalid_format;
        if (v != .string or v.string.len != bkds.PUBKEY_LEN * 2) return Error.pairing_payload_invalid_format;
        bkds.hexDecode(v.string, &operator_root_pub) catch return Error.pairing_payload_invalid_format;
    }

    const context_tag: u8 = blk: {
        const v = obj.get("context_tag") orelse return Error.pairing_payload_invalid_format;
        if (v != .integer or v.integer < 0 or v.integer > 255) return Error.pairing_payload_invalid_format;
        break :blk @intCast(v.integer);
    };

    // Label.
    const label = blk: {
        const v = obj.get("label") orelse return Error.pairing_payload_invalid_format;
        if (v != .string or v.string.len == 0 or v.string.len > MAX_LABEL_LEN)
            return Error.pairing_payload_label_too_long;
        break :blk try allocator.dupe(u8, v.string);
    };
    errdefer allocator.free(label);

    // Capabilities.
    const capabilities = blk: {
        const v = obj.get("capabilities") orelse return Error.pairing_payload_invalid_format;
        if (v != .array) return Error.pairing_payload_invalid_format;
        if (v.array.items.len > MAX_CAPABILITIES) return Error.pairing_payload_invalid_capability;
        var list: std.ArrayList([]u8) = .{};
        errdefer {
            for (list.items) |c| allocator.free(c);
            list.deinit(allocator);
        }
        for (v.array.items) |c| {
            if (c != .string) return Error.pairing_payload_invalid_format;
            if (!isValidCapability(c.string)) return Error.pairing_payload_invalid_capability;
            const owned = try allocator.dupe(u8, c.string);
            try list.append(allocator, owned);
        }
        break :blk try list.toOwnedSlice(allocator);
    };
    errdefer {
        for (capabilities) |c| allocator.free(c);
        if (capabilities.len > 0) allocator.free(capabilities);
    }

    // Expiry — strict gate.  Past now → expired.
    const expires_at: i64 = blk: {
        const v = obj.get("expires_at") orelse return Error.pairing_payload_invalid_format;
        if (v != .integer) return Error.pairing_payload_invalid_format;
        break :blk v.integer;
    };
    if (expires_at <= now_unix) return Error.pairing_payload_expired;

    // Nonce.
    var nonce: [NONCE_LEN]u8 = undefined;
    {
        const v = obj.get("nonce") orelse return Error.pairing_payload_invalid_format;
        if (v != .string or v.string.len != NONCE_LEN * 2) return Error.pairing_payload_invalid_format;
        bkds.hexDecode(v.string, &nonce) catch return Error.pairing_payload_invalid_format;
    }

    // D-O5p — brain endpoints + pin.
    const brain_pair_endpoint = blk: {
        const v = obj.get("brain_pair_endpoint") orelse return Error.pairing_payload_invalid_format;
        if (v != .string) return Error.pairing_payload_invalid_format;
        if (!isValidBrainUrl(v.string, "https://") and !isValidBrainUrl(v.string, "http://"))
            return Error.pairing_payload_invalid_format;
        break :blk try allocator.dupe(u8, v.string);
    };
    errdefer allocator.free(brain_pair_endpoint);

    const brain_wss_endpoint = blk: {
        const v = obj.get("brain_wss_endpoint") orelse return Error.pairing_payload_invalid_format;
        if (v != .string) return Error.pairing_payload_invalid_format;
        if (!isValidBrainUrl(v.string, "wss://") and !isValidBrainUrl(v.string, "ws://"))
            return Error.pairing_payload_invalid_format;
        break :blk try allocator.dupe(u8, v.string);
    };
    errdefer allocator.free(brain_wss_endpoint);

    var brain_pin_cert_id: [32]u8 = undefined;
    {
        const v = obj.get("brain_pin_cert_id") orelse return Error.pairing_payload_invalid_format;
        if (v != .string or v.string.len != 32) return Error.pairing_payload_invalid_format;
        @memcpy(&brain_pin_cert_id, v.string);
    }
    var brain_pin_pubkey: [bkds.PUBKEY_LEN]u8 = undefined;
    {
        const v = obj.get("brain_pin_pubkey") orelse return Error.pairing_payload_invalid_format;
        if (v != .string or v.string.len != bkds.PUBKEY_LEN * 2) return Error.pairing_payload_invalid_format;
        bkds.hexDecode(v.string, &brain_pin_pubkey) catch return Error.pairing_payload_invalid_format;
    }

    // Signature — verify against embedded pub.
    const sig_hex = blk: {
        const v = obj.get("signature") orelse return Error.pairing_payload_invalid_signature;
        if (v != .string) return Error.pairing_payload_invalid_signature;
        break :blk v.string;
    };

    const sig_bytes_buf = try allocator.alloc(u8, sig_hex.len / 2);
    defer allocator.free(sig_bytes_buf);
    if (sig_hex.len % 2 != 0) return Error.pairing_payload_invalid_signature;
    bkds.hexDecode(sig_hex, sig_bytes_buf) catch return Error.pairing_payload_invalid_signature;

    const der_sig = bsvz.crypto.DerSignature.fromDer(sig_bytes_buf) catch
        return Error.pairing_payload_invalid_signature;

    // Re-derive canonical bytes from the parsed payload.
    const re_payload = PairPayload{
        .operator_root_cert_id = operator_root_cert_id,
        .operator_root_pub = operator_root_pub,
        .context_tag = context_tag,
        .label = label,
        .capabilities = capabilities,
        .expires_at = expires_at,
        .nonce = nonce,
        .brain_pair_endpoint = brain_pair_endpoint,
        .brain_wss_endpoint = brain_wss_endpoint,
        .brain_pin_cert_id = brain_pin_cert_id,
        .brain_pin_pubkey = brain_pin_pubkey,
    };
    const canonical = try canonicalJsonForSigning(allocator, re_payload);
    defer allocator.free(canonical);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical, &digest, .{});

    const pub_key = bsvz.primitives.ec.PublicKey.fromSec1(&operator_root_pub) catch
        return Error.pairing_payload_invalid_signature;
    const ok = pub_key.verifyDigest(digest, der_sig) catch
        return Error.pairing_payload_invalid_signature;
    if (!ok) return Error.pairing_payload_invalid_signature;

    return .{
        .operator_root_cert_id = operator_root_cert_id,
        .operator_root_pub = operator_root_pub,
        .context_tag = context_tag,
        .label = label,
        .capabilities = capabilities,
        .expires_at = expires_at,
        .nonce = nonce,
        .brain_pair_endpoint = brain_pair_endpoint,
        .brain_wss_endpoint = brain_wss_endpoint,
        .brain_pin_cert_id = brain_pin_cert_id,
        .brain_pin_pubkey = brain_pin_pubkey,
    };
}

// ─────────────────────────────────────────────────────────────────────
// One-shot nonce ledger
// ─────────────────────────────────────────────────────────────────────

/// Append-only ledger of consumed nonces, persisted at
/// `<data_dir>/pairing-nonces.log`.  One nonce per line, hex-encoded.
/// The store loads on init + checks `isConsumed` before allowing a
/// claim; `markConsumed` is called by the CLI once the dispatcher's
/// `issue_child` succeeds.
pub const NonceLedger = struct {
    allocator: std.mem.Allocator,
    log_path: []u8,
    consumed: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !NonceLedger {
        const log_path = try std.fs.path.join(allocator, &.{ data_dir, "pairing-nonces.log" });
        errdefer allocator.free(log_path);
        std.fs.cwd().makePath(data_dir) catch {};
        var self = NonceLedger{
            .allocator = allocator,
            .log_path = log_path,
            .consumed = std.StringHashMap(void).init(allocator),
        };
        try self.replay();
        return self;
    }

    pub fn deinit(self: *NonceLedger) void {
        var it = self.consumed.iterator();
        while (it.next()) |e| self.allocator.free(e.key_ptr.*);
        self.consumed.deinit();
        self.allocator.free(self.log_path);
    }

    fn replay(self: *NonceLedger) !void {
        const f = std.fs.cwd().openFile(self.log_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return Error.pairing_payload_nonce_store_failed,
        };
        defer f.close();
        const stat = f.stat() catch return Error.pairing_payload_nonce_store_failed;
        const buf = self.allocator.alloc(u8, stat.size) catch return Error.out_of_memory;
        defer self.allocator.free(buf);
        const n = f.readAll(buf) catch return Error.pairing_payload_nonce_store_failed;
        var it = std.mem.splitScalar(u8, buf[0..n], '\n');
        while (it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (trimmed.len != NONCE_LEN * 2) continue;
            const owned = self.allocator.dupe(u8, trimmed) catch return Error.out_of_memory;
            const gop = self.consumed.getOrPut(owned) catch return Error.out_of_memory;
            if (gop.found_existing) self.allocator.free(owned);
        }
    }

    pub fn isConsumed(self: *NonceLedger, nonce: [NONCE_LEN]u8) bool {
        var hex: [NONCE_LEN * 2]u8 = undefined;
        bkds.hexEncode(&nonce, &hex);
        return self.consumed.contains(&hex);
    }

    pub fn markConsumed(self: *NonceLedger, nonce: [NONCE_LEN]u8) !void {
        var hex_buf: [NONCE_LEN * 2]u8 = undefined;
        bkds.hexEncode(&nonce, &hex_buf);
        if (self.consumed.contains(&hex_buf)) return; // idempotent

        // Append to log first; index update only on successful append.
        const f = std.fs.cwd().createFile(self.log_path, .{ .truncate = false }) catch
            return Error.pairing_payload_nonce_store_failed;
        defer f.close();
        f.seekFromEnd(0) catch return Error.pairing_payload_nonce_store_failed;
        var line: [NONCE_LEN * 2 + 1]u8 = undefined;
        @memcpy(line[0 .. NONCE_LEN * 2], &hex_buf);
        line[NONCE_LEN * 2] = '\n';
        f.writeAll(&line) catch return Error.pairing_payload_nonce_store_failed;

        const owned = try self.allocator.dupe(u8, &hex_buf);
        const gop = try self.consumed.getOrPut(owned);
        if (gop.found_existing) self.allocator.free(owned);
    }
};

// ─────────────────────────────────────────────────────────────────────
// Context-tag allocator
// ─────────────────────────────────────────────────────────────────────

/// Pick the next unused context_tag for a new child cert.  Walks the
/// supplied list of currently-issued context tags + returns the
/// lowest u8 ≥ FIRST_CHILD_CONTEXT_TAG that isn't in the set.
/// Returns `pairing_payload_no_context_tag` if every byte from 0x10
/// through 0xFF is already taken.
pub fn allocateContextTag(used_tags: []const u8) !u8 {
    var seen: [256]bool = .{false} ** 256;
    for (used_tags) |t| seen[t] = true;
    var t: u16 = FIRST_CHILD_CONTEXT_TAG;
    while (t <= 0xFF) : (t += 1) {
        if (!seen[t]) return @intCast(t);
    }
    return Error.pairing_payload_no_context_tag;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure-function unit shape; full conformance lives in
// tests/device_pair_claim_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "isValidCapability accepts dotted-namespace cap names" {
    try std.testing.expect(isValidCapability("cap.attach.photo"));
    try std.testing.expect(isValidCapability("cap.oddjobz.write_customer"));
    try std.testing.expect(isValidCapability("cap.llm.complete:foo"));
    try std.testing.expect(!isValidCapability("notcap.X"));
    try std.testing.expect(!isValidCapability("cap."));
    try std.testing.expect(!isValidCapability("cap..bar"));
    try std.testing.expect(!isValidCapability("cap.X "));
    try std.testing.expect(!isValidCapability(""));
}

test "resolveCaps minimal returns 3 attach caps" {
    const allocator = std.testing.allocator;
    const c = try resolveCaps(allocator, "minimal");
    defer c.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), c.items.len);
    try std.testing.expectEqualStrings("cap.attach.photo", c.items[0]);
    try std.testing.expectEqualStrings("cap.attach.gps", c.items[1]);
    try std.testing.expectEqualStrings("cap.attach.voice", c.items[2]);
}

test "resolveCaps full returns 5 caps" {
    const allocator = std.testing.allocator;
    const c = try resolveCaps(allocator, "full");
    defer c.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 5), c.items.len);
}

test "resolveCaps custom comma-separated list" {
    const allocator = std.testing.allocator;
    const c = try resolveCaps(allocator, "cap.X.foo, cap.Y.bar");
    defer c.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), c.items.len);
    try std.testing.expectEqualStrings("cap.X.foo", c.items[0]);
    try std.testing.expectEqualStrings("cap.Y.bar", c.items[1]);
}

test "resolveCaps custom rejects malformed" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(Error.pairing_payload_invalid_capability, resolveCaps(allocator, "notcap.X"));
}

test "allocateContextTag returns FIRST_CHILD_CONTEXT_TAG when none used" {
    const empty: []const u8 = &.{};
    try std.testing.expectEqual(FIRST_CHILD_CONTEXT_TAG, try allocateContextTag(empty));
}

test "allocateContextTag returns next free tag" {
    const used = [_]u8{ 0x10, 0x11 };
    try std.testing.expectEqual(@as(u8, 0x12), try allocateContextTag(&used));
}

test "extractToken strips URL scheme" {
    try std.testing.expectEqualStrings("abc", extractToken("semantos-pair://brain.example/pair?token=abc"));
    try std.testing.expectEqualStrings("abc", extractToken("abc"));
}

```
