---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/bundle_sign_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.227138+00:00
---

# runtime/semantos-brain/src/bundle_sign_http.zig

```zig
//! D-helm-rtc-operator-sign — POST /api/v1/bundle/sign signing core.
//!
//! The helm (loom-svelte SPA) builds an UNSIGNED SignedBundle wrapping an
//! `rtc.jingle` (or any payload) addressed to a contact, and asks the brain —
//! the sovereign node that actually holds the operator's pin private key — to
//! sign it AS the operator. The SPA never holds the operator key, so signing
//! stays on the brain. This closes the RTC "dev signer" gap: with a real
//! operator signature the recipient can verify a call's authenticity via
//! `verifyBrainBundleSignature` / `makeContactBundleVerifier`
//! (runtime/session-protocol/src/rtc/bsv-signed-bundle-verifier.ts), whose
//! preimage (`SIG_DOMAIN || canonical-json(bundle - signature)`) is
//! byte-identical to `signed_bundle.canonicalSignaturePreimage` here.
//!
//! Request body : an UNSIGNED SignedBundle JSON (the `signed_bundle.decode`
//!                shape). The `signature` field is overwritten — callers may
//!                send 64 zero bytes. `signature_metadata.timestamp_unix` is
//!                re-stamped by the brain so freshness is brain-authoritative
//!                (a stale SPA clock would otherwise trip the recipient's
//!                freshness window).
//! Response     : the SIGNED SignedBundle JSON (`signed_bundle.encode`), which
//!                the helm POSTs to the recipient's MessageBox unchanged.
//!
//! AUTH: admin (`cap.brain.admin`) — only the operator may sign as the
//! operator. The route handler + auth gate + operator-key plumbing live in
//! site_server/reactor.zig; this module is the PURE signing core
//! (parse → re-stamp → sign → encode) so it is unit-testable without the HTTP
//! reactor. The leaf pubkey the caller declares must be the operator's own pin
//! pubkey: the brain signs with `operator_root_priv`, so a bundle declaring any
//! OTHER pubkey simply won't verify downstream — no forgery is possible.

const std = @import("std");
const signed_bundle = @import("signed_bundle");
const bkds = @import("bkds");

/// Route path. Matched in site_server/reactor.zig before the 404 fallthrough.
pub const ROUTE: []const u8 = "/api/v1/bundle/sign";

pub const SignError = error{
    /// Body was not a decodable unsigned SignedBundle → 400.
    parse_failed,
    /// secp256k1 signing failed (bad operator key) → 500.
    sign_failed,
    /// Re-encoding the signed bundle failed → 500.
    encode_failed,
} || std.mem.Allocator.Error;

/// Parse an unsigned SignedBundle, stamp the brain's timestamp, sign with the
/// operator private key, and return the signed bundle JSON. Caller frees.
pub fn signBundleJson(
    allocator: std.mem.Allocator,
    body: []const u8,
    operator_priv: [bkds.PRIVKEY_LEN]u8,
    now_unix: i64,
) SignError![]u8 {
    var owned = signed_bundle.decode(allocator, body) catch return error.parse_failed;
    defer owned.deinit();
    // Brain-authoritative freshness — overwrite whatever the helm sent.
    owned.bundle.signature_metadata.timestamp_unix = now_unix;
    signed_bundle.signBundle(allocator, &owned.bundle, operator_priv) catch
        return error.sign_failed;
    return signed_bundle.encode(allocator, owned.bundle) catch return error.encode_failed;
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;
const bsvz = @import("bsvz");

test "signBundleJson signs an unsigned bundle so the operator pubkey verifies" {
    const alloc = testing.allocator;

    // Fixed, valid secp256k1 operator key (scalar 0x0102…20, well below n).
    var priv: [bkds.PRIVKEY_LEN]u8 = undefined;
    for (&priv, 0..) |*p, i| p.* = @intCast(i + 1);
    const kp = try bsvz.primitives.ec.PrivateKey.fromBytes(priv);
    const op_pub: [bkds.KEY_LEN]u8 = (try kp.publicKey()).toCompressedSec1();

    // Build an UNSIGNED bundle declaring the operator pubkey as the leaf cert,
    // then serialise it — that is exactly the shape the helm POSTs.
    var chain = [_]signed_bundle.CertRef{.{
        .cert_id = [_]u8{'a'} ** signed_bundle.CERT_ID_HEX_LEN,
        .pubkey = op_pub,
        .context_tag = 0x10,
        .parent_cert_id = null,
    }};
    const unsigned = signed_bundle.SignedBundle{
        // `.v` defaults to ENVELOPE_VERSION.
        .sender_cert_chain = &chain,
        .recipient_cert_id = [_]u8{'b'} ** signed_bundle.CERT_ID_HEX_LEN,
        .payload_type = "rtc.jingle",
        .payload = "<jingle xmlns='urn:xmpp:jingle:1'/>",
        .signature = [_]u8{0} ** signed_bundle.SIG_LEN,
        .signature_metadata = .{
            .algorithm = "ecdsa-secp256k1-sha256",
            .nonce_hex = [_]u8{'0'} ** signed_bundle.NONCE_HEX_LEN,
            .timestamp_unix = 0,
        },
    };
    const unsigned_json = try signed_bundle.encode(alloc, unsigned);
    defer alloc.free(unsigned_json);

    // Sign it as the operator.
    const signed_json = try signBundleJson(alloc, unsigned_json, priv, 1_700_000_000);
    defer alloc.free(signed_json);

    // The signed bundle must decode, carry a non-zero signature + the brain's
    // re-stamped timestamp, and verify against the operator's pubkey.
    var out = try signed_bundle.decode(alloc, signed_json);
    defer out.deinit();
    try testing.expect(!std.mem.allEqual(u8, &out.bundle.signature, 0));
    try testing.expectEqual(@as(i64, 1_700_000_000), out.bundle.signature_metadata.timestamp_unix);
    try signed_bundle.verifySignature(alloc, out.bundle, op_pub);
}

test "signBundleJson rejects an undecodable body" {
    const alloc = testing.allocator;
    var priv: [bkds.PRIVKEY_LEN]u8 = undefined;
    @memset(&priv, 0x07);
    try testing.expectError(error.parse_failed, signBundleJson(alloc, "{not json", priv, 0));
}

```
