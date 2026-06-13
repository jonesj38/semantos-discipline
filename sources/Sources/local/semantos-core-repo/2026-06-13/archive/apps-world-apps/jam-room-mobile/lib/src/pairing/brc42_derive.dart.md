---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-apps/jam-room-mobile/lib/src/pairing/brc42_derive.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.831237+00:00
---

# archive/apps-world-apps/jam-room-mobile/lib/src/pairing/brc42_derive.dart

```dart
// D-O5m — BRC-42 child derivation in pure Dart via pointycastle.
//
// Port of `deriveChildKeyMaterial` + `buildBrc42Invoice` in
// `extensions/oddjobz/src/device-pair-client.ts`. Cross-language
// parity is asserted by `test/pairing/brc42_derive_test.dart` against
// the canonical fixture at
// `extensions/oddjobz/tests/vectors/device-pair/v2-fixture.json` —
// the derived child pubkey hex MUST match the TS-derived value
// byte-for-byte.
//
// Algorithm (mirrors `runtime/semantos-brain/src/bkds.zig` + the TS reference):
//
//   invoice       = "BKDS-BRC42-v1" || u8(context_tag) || u32_be(label.len) || label
//   shared_secret = ECDH(device_priv, operator_root_pub)
//   hmac          = HMAC-SHA-256(key=shared_compressed_sec1, msg=invoice)
//   child_pub     = hmac*G + operator_root_pub                (66 hex, compressed SEC1)
//
// Critical compatibility note (also in the TS reference):
//   The HMAC key is the **compressed-SEC1 33-byte form** of the ECDH
//   shared point — NOT the raw X coordinate. pointycastle's
//   `ECDHBasicAgreement` returns the raw X scalar, so we must encode
//   the shared point manually via `Q = priv * pub`.
//
// Why pointycastle: pure-Dart, mature, ships secp256k1 as a domain
// parameter set, and works on iOS + Android + the desktop test
// harness. The parity test against the v2 fixture discharges
// correctness; we don't need a Zig FFI export for BRC-42 (the
// arithmetic is straightforward and the audit surface is finite).

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/macs/hmac.dart';

/// BRC-42 invoice domain — must match
/// `runtime/semantos-brain/src/bkds.zig`'s INVOICE_DOMAIN.
const String invoiceDomain = 'BKDS-BRC42-v1';

/// Result of BRC-42 child derivation: the child's pubkey (the audit
/// identifier the brain stores as `derivation_pubkey`) and the
/// device's own pubkey (the proof material the brain stores as
/// `derivation_proof`).
class DerivedChild {
  /// 66 hex chars (compressed SEC1).
  final String childPubKeyHex;

  /// 66 hex chars (compressed SEC1).
  final String devicePubKeyHex;

  const DerivedChild({
    required this.childPubKeyHex,
    required this.devicePubKeyHex,
  });

  @override
  String toString() =>
      'DerivedChild(childPubKeyHex=$childPubKeyHex, '
      'devicePubKeyHex=$devicePubKeyHex)';
}

/// Build the BRC-42 invoice bytes — must match
/// `runtime/semantos-brain/src/bkds.zig`'s `buildInvoice` byte-for-byte.
///
///   "BKDS-BRC42-v1" || u8(context_tag) || u32_be(label.len) || label
Uint8List buildBrc42Invoice(int contextTag, String label) {
  if (contextTag < 0 || contextTag > 255) {
    throw ArgumentError('contextTag must be u8 (0..255), got $contextTag');
  }
  final labelBytes = utf8.encode(label);
  if (labelBytes.length > 256) {
    throw ArgumentError('label exceeds 256-byte invoice cap');
  }
  final domainBytes = utf8.encode(invoiceDomain);
  final out = Uint8List(domainBytes.length + 1 + 4 + labelBytes.length);
  out.setRange(0, domainBytes.length, domainBytes);
  out[domainBytes.length] = contextTag;
  // u32 big-endian length prefix.
  final len = labelBytes.length;
  out[domainBytes.length + 1] = (len >> 24) & 0xff;
  out[domainBytes.length + 2] = (len >> 16) & 0xff;
  out[domainBytes.length + 3] = (len >> 8) & 0xff;
  out[domainBytes.length + 4] = len & 0xff;
  out.setRange(
      domainBytes.length + 5, domainBytes.length + 5 + labelBytes.length, labelBytes);
  return out;
}

/// secp256k1 domain parameters (same curve the operator + device sign
/// over). Matches the TS reference's `new Curve()` (which @bsv/sdk
/// hard-codes to secp256k1).
final ECDomainParameters _secp256k1 = ECCurve_secp256k1();

/// Derive the BRC-42 child key material.
///
/// Inputs:
///   - [devicePrivKeyHex]: 64 hex chars (32 bytes) — the device's
///     identity priv (in production: held in Keychain/Keystore;
///     here: passed in by the caller).
///   - [operatorRootPubKeyHex]: 66 hex chars (compressed SEC1) —
///     the operator's root pub from the decoded payload.
///   - [contextTag]: u8 from the decoded payload.
///   - [label]: from the decoded payload.
///
/// Returns:
///   - childPubKeyHex: 66 hex chars (compressed SEC1). Submitted as
///     `derivation_pubkey` in the accept request body.
///   - devicePubKeyHex: 66 hex chars. Submitted as `derivation_proof`.
DerivedChild deriveChildKeyMaterial({
  required String devicePrivKeyHex,
  required String operatorRootPubKeyHex,
  required int contextTag,
  required String label,
}) {
  final devicePrivBn = _hexToBigInt(devicePrivKeyHex);
  final devicePriv = ECPrivateKey(devicePrivBn, _secp256k1);
  final operatorRootPub = _decodePubHex(operatorRootPubKeyHex);

  // ECDH shared point: Q = devicePriv * operatorRootPub.
  // We need the COMPRESSED SEC1 of Q (33 bytes), not just the X
  // coordinate, as the HMAC key. pointycastle's
  // ECDHBasicAgreement returns just the X scalar — wrong for our
  // needs — so compute the point multiply manually.
  final sharedPoint = (operatorRootPub.Q! * devicePriv.d!)!;
  final sharedCompressed = sharedPoint.getEncoded(true);

  // Build invoice bytes (must match bkds.zig byte-for-byte).
  final invoice = buildBrc42Invoice(contextTag, label);

  // HMAC-SHA-256(key=sharedCompressed, msg=invoice).
  final hmac = HMac.withDigest(SHA256Digest())
    ..init(KeyParameter(sharedCompressed));
  hmac.update(invoice, 0, invoice.length);
  final hmacOut = Uint8List(32);
  hmac.doFinal(hmacOut, 0);
  final hmacBn = _bytesToBigInt(hmacOut);

  // child_pub = hmac*G + operator_root_pub
  // Mirrors bsvz `PublicKey.deriveChild` exactly:
  //   const pt = secp256k1.Point.basePointMul(h);
  //   const sum = pt.add(self.inner.toPoint());
  //   return PublicKey.fromPoint(sum);
  final tweakPoint = (_secp256k1.G * hmacBn)!;
  final childPubPoint = (operatorRootPub.Q! + tweakPoint)!;
  final childPubCompressed = childPubPoint.getEncoded(true);

  // Device pub = devicePriv * G.
  final devicePubPoint = (_secp256k1.G * devicePriv.d!)!;
  final devicePubCompressed = devicePubPoint.getEncoded(true);

  return DerivedChild(
    childPubKeyHex: _bytesToHex(childPubCompressed),
    devicePubKeyHex: _bytesToHex(devicePubCompressed),
  );
}

// ─── helpers ─────────────────────────────────────────────────────────

ECPublicKey _decodePubHex(String hex) {
  if (hex.length != 66) {
    throw ArgumentError(
        'operator_root_pub must be 66 hex chars (33-byte compressed SEC1), got ${hex.length}');
  }
  final bytes = _hexToBytes(hex);
  final point = _secp256k1.curve.decodePoint(bytes);
  if (point == null) {
    throw ArgumentError('failed to decode pub hex as secp256k1 point');
  }
  return ECPublicKey(point, _secp256k1);
}

Uint8List _hexToBytes(String hex) {
  if (hex.length % 2 != 0) {
    throw ArgumentError('hex string must have even length, got ${hex.length}');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

BigInt _hexToBigInt(String hex) => BigInt.parse(hex, radix: 16);

BigInt _bytesToBigInt(List<int> bytes) {
  // Treat as unsigned big-endian.
  var n = BigInt.zero;
  for (final b in bytes) {
    n = (n << 8) | BigInt.from(b & 0xff);
  }
  return n;
}

```
