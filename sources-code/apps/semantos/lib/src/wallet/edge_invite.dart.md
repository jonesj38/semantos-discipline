---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/edge_invite.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.108404+00:00
---

# apps/semantos/lib/src/wallet/edge_invite.dart

```dart
// PWA contacts-PKI — peer invite + bilateral edge creation.
//
// Dart mirror of two brain modules:
//   - cartridges/wallet-headers/brain/src/peer-invite.ts
//       PeerInvite / generateInvite / encode+decodeInviteToken /
//       build+parseInviteUrl
//   - cartridges/wallet-headers/brain/src/ecdh-edge.ts
//       deriveEdgeSharedSecret / buildEdgeBackupRecipe / acceptInvite
//
// This is the BILATERAL (two-party) domain. The shared secret is a true
// ECDH between the two parties' keys — it is NOT the unilateral
// `deriveSegment` path. The crypto is built on `edge_derive.dart`
// (BRC-42 counterparty derivation) per the contacts-PKI design.
//
// IMPORTANT — interop contract: the `edgeId`, `backupRecipe`, and invite
// token/URL byte-shapes here are BYTE-IDENTICAL to the brain TS for the
// same inputs, so an edge created in the PWA interoperates with one
// created in the brain. The cross-language KAT in
// `test/wallet/edge_kat_test.dart` (vectors generated against the real
// `ecdh-edge.ts` / `peer-invite.ts` via
// `cartridges/wallet-headers/brain/scripts/gen-edge-kat.ts`) pins this.
//
// Two ECDH HMAC-key conventions exist in the brain and they are NOT
// interchangeable:
//   - ecdh42.ts `computeTweak`  : HMAC key = raw compressed ECDH point.
//   - host.ts   `deriveLeafSync`: HMAC key = SHA-256(raw point).
// The edge SHARED SECRET (`deriveEdgeSharedSecret`) is built on the
// `deriveLeafSync` convention — that is what `ecdh-edge.ts` uses — so
// this file replicates the SHA-256(point)-keyed leaf, NOT the
// `deriveEdgeSk` in `edge_derive.dart` (which is the raw-point ecdh42
// convention used for payment-key rotation).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart' show KeyParameter;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/macs/hmac.dart';

import 'edge_derive.dart'
    show applyTweakToPrivate, buildBinaryInvoice, ecdhSharedCompressed,
        kEdgeProtocolHash;
import 'edge_store.dart';

/// Default base URL a shared invite link points at. Mirrors
/// `DEFAULT_BASE_URL` in `peer-invite.ts`.
const String kInviteDefaultBaseUrl = 'https://wallet.semantos.me/connect';

/// Invite time-to-live (24h), mirroring `INVITE_TTL_MS`.
const int kInviteTtlMs = 24 * 60 * 60 * 1000;

/// Backup-recipe HMAC prefix, mirroring `ecdh-edge.ts`.
const String kEdgeBackupRecipePrefix = 'edge-backup-recipe';

/// An off-band invite — encodes the inviter's identity so a peer can
/// initiate the ECDH edge. Field set + order match `PeerInvite` in
/// `peer-invite.ts` exactly (the order matters: it fixes the JSON byte
/// layout the invite token base64url-encodes).
class PeerInvite {
  const PeerInvite({
    required this.certId,
    required this.publicKey,
    required this.nonce,
    required this.timestamp,
  });

  /// Inviter's cert id (hex).
  final String certId;

  /// Inviter's 33-byte compressed secp256k1 pubkey (hex).
  final String publicKey;

  /// 32-byte random hex (anti-replay).
  final String nonce;

  /// Unix ms when the invite was minted.
  final int timestamp;

  /// JSON map in the SAME key order as the TS object literal
  /// (`{certId, publicKey, nonce, timestamp}`) so `encodeInviteToken`
  /// reproduces the brain's exact token bytes.
  Map<String, dynamic> toJson() => {
        'certId': certId,
        'publicKey': publicKey,
        'nonce': nonce,
        'timestamp': timestamp,
      };

  /// Parse + validate a decoded JSON object. Returns null when any
  /// required field is missing or mistyped (mirrors the TS field-type
  /// guards in `decodeInviteToken`).
  static PeerInvite? tryFromJson(Object? decoded) {
    if (decoded is! Map) return null;
    final certId = decoded['certId'];
    final publicKey = decoded['publicKey'];
    final nonce = decoded['nonce'];
    final timestamp = decoded['timestamp'];
    if (certId is! String ||
        publicKey is! String ||
        nonce is! String ||
        timestamp is! int) {
      return null;
    }
    return PeerInvite(
      certId: certId,
      publicKey: publicKey,
      nonce: nonce,
      timestamp: timestamp,
    );
  }
}

/// Generate a fresh invite for my identity. `myPk` is the 33-byte
/// compressed identity pubkey. Uses a cryptographically secure 32-byte
/// nonce. `nowMs` is injectable for tests; defaults to wall-clock.
PeerInvite generateInvite({
  required String myCertId,
  required Uint8List myPk,
  int? nowMs,
}) {
  final rand = Random.secure();
  final nonce = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    nonce[i] = rand.nextInt(256);
  }
  return PeerInvite(
    certId: myCertId,
    publicKey: _hex(myPk),
    nonce: _hex(nonce),
    timestamp: nowMs ?? DateTime.now().millisecondsSinceEpoch,
  );
}

/// Encode an invite to a URL-safe token (base64url of the JSON, no
/// padding) — byte-identical to `encodeInviteToken` in `peer-invite.ts`.
String encodeInviteToken(PeerInvite invite) {
  final json = jsonEncode(invite.toJson());
  return _toBase64url(json);
}

/// Decode + validate a token. Returns null when malformed, mistyped, or
/// expired (older than [ttlMs]). `nowMs` is injectable for tests.
PeerInvite? decodeInviteToken(
  String token, {
  int ttlMs = kInviteTtlMs,
  int? nowMs,
}) {
  if (token.isEmpty) return null;
  String jsonStr;
  try {
    jsonStr = _fromBase64url(token);
  } catch (_) {
    return null;
  }
  Object? decoded;
  try {
    decoded = jsonDecode(jsonStr);
  } catch (_) {
    return null;
  }
  final invite = PeerInvite.tryFromJson(decoded);
  if (invite == null) return null;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  if (now - invite.timestamp > ttlMs) return null;
  return invite;
}

/// Build a shareable invite URL (`<base>?invite=<token>`). Mirrors
/// `buildInviteUrl`.
String buildInviteUrl(PeerInvite invite, {String? baseUrl}) {
  final base = baseUrl ?? kInviteDefaultBaseUrl;
  final token = encodeInviteToken(invite);
  final sep = base.contains('?') ? '&' : '?';
  return '$base${sep}invite=$token';
}

/// Parse an invite URL, returning the decoded invite or null. Mirrors
/// `parseInviteUrl`.
PeerInvite? parseInviteUrl(String url, {int ttlMs = kInviteTtlMs, int? nowMs}) {
  Uri parsed;
  try {
    parsed = Uri.parse(url);
  } catch (_) {
    return null;
  }
  final token = parsed.queryParameters['invite'];
  if (token == null || token.isEmpty) return null;
  return decodeInviteToken(token, ttlMs: ttlMs, nowMs: nowMs);
}

// ─────────────── edge crypto (ecdh-edge.ts) ───────────────

/// Derive the BRC-42 edge-creation leaf SK at [signingKeyIndex].
///
/// Mirror of `deriveLeafSync(mySk, SHA256("BRC-42-edge-creation")[0:16],
/// theirPk, index)` in `host.ts`:
///   invoice = protocolHash(16) ‖ index_le(8)
///   tweak   = HMAC-SHA256(SHA-256(ECDH(mySk, theirPk)), invoice)
///   leaf    = (mySk + tweak) mod N
///
/// NOTE the HMAC key is SHA-256 of the raw ECDH point — the
/// `deriveLeafSync` convention — NOT the raw point used by
/// `edge_derive.dart`'s `deriveEdgeSk`. Returns the 32-byte leaf SK;
/// the caller must zero it after use.
Uint8List deriveEdgeLeafSk({
  required Uint8List mySk,
  required Uint8List theirPk,
  required int signingKeyIndex,
}) {
  final invoice = buildBinaryInvoice(
    protocolHash: kEdgeProtocolHash,
    signingKeyIndex: signingKeyIndex,
  );
  final shared = ecdhSharedCompressed(mySk: mySk, theirPub: theirPk);
  final hmacKey = SHA256Digest().process(shared);
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(hmacKey));
  final tweak = hmac.process(invoice);
  return applyTweakToPrivate(mySk, tweak);
}

/// Derive the 32-byte ECDH shared secret for an edge at
/// [signingKeyIndex], mirroring `deriveEdgeSharedSecret` in
/// `ecdh-edge.ts`:
///   sharedSecret = SHA-256(ECDH(deriveEdgeLeafSk(...), theirPk))
Uint8List deriveEdgeSharedSecret({
  required Uint8List mySk,
  required Uint8List theirPk,
  required int signingKeyIndex,
}) {
  final leafSk = deriveEdgeLeafSk(
    mySk: mySk,
    theirPk: theirPk,
    signingKeyIndex: signingKeyIndex,
  );
  try {
    final sharedPoint = ecdhSharedCompressed(mySk: leafSk, theirPub: theirPk);
    return SHA256Digest().process(sharedPoint);
  } finally {
    leafSk.fillRange(0, leafSk.length, 0);
  }
}

/// Deterministic edge id, mirroring `acceptInvite`:
///   edgeId = hex(SHA-256(UTF-8(myCertId ‖ theirCertId ‖ nonce)))
String computeEdgeId({
  required String myCertId,
  required String theirCertId,
  required String nonce,
}) {
  final input = utf8.encode('$myCertId$theirCertId$nonce');
  return _hex(SHA256Digest().process(Uint8List.fromList(input)));
}

/// Build the BRC-69 backup recipe, mirroring `buildEdgeBackupRecipe`:
///   recipe = hex(HMAC-SHA256(sharedSecret, "edge-backup-recipe" ‖ edgeIdBytes))
/// where `edgeIdBytes` is the hex-decode of [edgeId], falling back to
/// its UTF-8 bytes if [edgeId] is not valid hex (matches the TS
/// try/catch).
String buildEdgeBackupRecipe({
  required Uint8List mySk,
  required Uint8List theirPk,
  required int signingKeyIndex,
  required String edgeId,
}) {
  final sharedSecret = deriveEdgeSharedSecret(
    mySk: mySk,
    theirPk: theirPk,
    signingKeyIndex: signingKeyIndex,
  );
  try {
    final prefix = utf8.encode(kEdgeBackupRecipePrefix);
    final edgeIdBytes = _hexOrUtf8(edgeId);
    final msg = Uint8List(prefix.length + edgeIdBytes.length)
      ..setRange(0, prefix.length, prefix)
      ..setRange(prefix.length, prefix.length + edgeIdBytes.length, edgeIdBytes);
    final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(sharedSecret));
    return _hex(hmac.process(msg));
  } finally {
    sharedSecret.fillRange(0, sharedSecret.length, 0);
  }
}

/// Accept an [invite] under my identity and produce the edge envelope —
/// the pure equivalent of `acceptInvite` in `ecdh-edge.ts` (without the
/// store write; persistence is the caller's via [EdgeStore.save]).
///
/// [mySk] is my identity private key (cert_body); the caller is
/// responsible for zeroing it. Throws [ArgumentError] / [StateError]
/// when the invite pubkey or derivation is malformed (the TS returns
/// null; Dart surfaces the cause).
LocalEdgeEnvelope createEdgeEnvelope({
  required PeerInvite invite,
  required String myCertId,
  required Uint8List mySk,
  required int signingKeyIndex,
  String edgeType = kEdgeTypeMessaging,
  int? nowMs,
}) {
  final theirPk = _fromHex(invite.publicKey);
  final edgeId = computeEdgeId(
    myCertId: myCertId,
    theirCertId: invite.certId,
    nonce: invite.nonce,
  );
  final backupRecipe = buildEdgeBackupRecipe(
    mySk: mySk,
    theirPk: theirPk,
    signingKeyIndex: signingKeyIndex,
    edgeId: edgeId,
  );
  return LocalEdgeEnvelope(
    edgeId: edgeId,
    myCertId: myCertId,
    theirCertId: invite.certId,
    theirPublicKey: invite.publicKey,
    signingKeyIndex: signingKeyIndex,
    edgeType: edgeType,
    backupRecipe: backupRecipe,
    createdAt: nowMs ?? DateTime.now().millisecondsSinceEpoch,
  );
}

// ─────────────── helpers ───────────────

String _hex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List _fromHex(String h) {
  if (h.length.isOdd) {
    throw ArgumentError.value(h, 'hex', 'odd-length hex');
  }
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final b = int.tryParse(h.substring(i * 2, i * 2 + 2), radix: 16);
    if (b == null) {
      throw ArgumentError.value(h, 'hex', 'invalid hex');
    }
    out[i] = b;
  }
  return out;
}

/// Hex-decode [s], falling back to its UTF-8 bytes when it is not valid
/// hex — mirrors the `hexToBytes` try/catch in `buildEdgeBackupRecipe`.
Uint8List _hexOrUtf8(String s) {
  try {
    return _fromHex(s);
  } catch (_) {
    return Uint8List.fromList(utf8.encode(s));
  }
}

/// base64url(no padding) of the UTF-8 bytes of [s]. Invite payloads are
/// ASCII (hex + digits + URL), so UTF-8 == the latin1 bytes the TS
/// `btoa` sees, making the token byte-identical.
String _toBase64url(String s) {
  return base64Url.encode(utf8.encode(s)).replaceAll('=', '');
}

/// Inverse of [_toBase64url]: re-pad and decode. Throws on malformed
/// input (caught by the callers, which then return null).
String _fromBase64url(String s) {
  final pad = (4 - s.length % 4) % 4;
  return utf8.decode(base64Url.decode(s + ('=' * pad)));
}

```
