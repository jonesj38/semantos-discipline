---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/mesh/cert_ref.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.902528+00:00
---

# archive/apps-semantos-monolith/lib/src/mesh/cert_ref.dart

```dart
// D-O5m.followup-6 Phase 1 — Dart port of `runtime/semantos-brain/src/signed_bundle.zig::CertRef`.
//
// One link in the SignedBundle's sender_cert_chain.  The chain is leaf-
// first; the root cert sits last and has `parentCertId == null`.  The
// canonical preimage encoder serialises CertRef objects in the field
// order (cert_id, context_tag, parent_cert_id, pubkey) — the Zig codec
// at runtime/semantos-brain/src/signed_bundle.zig::writeCertRef enforces the same
// order, so this port must too.
//
// Field-shape contract (mirrors signed_bundle.zig):
//   • certId: 32 hex chars (16-byte sha256-prefix of pubkey)
//   • pubkey: 33-byte compressed-SEC1 secp256k1 point
//   • contextTag: u8 (0 = root; 0x10 = carpenter; 0x11 = musician; etc.)
//   • parentCertId: 32 hex chars OR null (root cert only)

import 'dart:typed_data';

/// Length of a cert id in hex chars (matches `signed_bundle.zig::CERT_ID_HEX_LEN`).
const int certIdHexLen = 32;

/// Length of a 33-byte compressed-SEC1 pubkey hex string (matches
/// `signed_bundle.zig::PUBKEY_HEX_LEN`).
const int pubkeyHexLen = 66;

/// Length of a 33-byte compressed-SEC1 pubkey (matches `bkds.KEY_LEN`).
const int pubkeyByteLen = 33;

/// One cert in the sender_cert_chain.
class CertRef {
  /// 32-hex-char cert id (sha256(pubkey)[0..16] hex-encoded).  Verified
  /// brain-side against `identity_certs.certIdFromPubkey(pubkey)` to
  /// catch a forged claim that "this pubkey owns this cert id."
  final String certId;

  /// 33-byte compressed-SEC1 secp256k1 public key.  The wire encoding
  /// is hex (66 chars).
  final Uint8List pubkey;

  /// 0..255.  The carpenter / musician / root identifier the brain
  /// uses to gate capabilities.
  final int contextTag;

  /// 32-hex-char parent cert id, or null only for the root.
  final String? parentCertId;

  CertRef({
    required this.certId,
    required this.pubkey,
    required this.contextTag,
    required this.parentCertId,
  }) {
    if (certId.length != certIdHexLen) {
      throw ArgumentError(
          'certId must be $certIdHexLen hex chars, got ${certId.length}');
    }
    if (pubkey.length != pubkeyByteLen) {
      throw ArgumentError(
          'pubkey must be $pubkeyByteLen bytes, got ${pubkey.length}');
    }
    if (contextTag < 0 || contextTag > 255) {
      throw ArgumentError('contextTag must be 0..255, got $contextTag');
    }
    if (parentCertId != null && parentCertId!.length != certIdHexLen) {
      throw ArgumentError(
          'parentCertId must be $certIdHexLen hex chars or null');
    }
  }

  /// 66-char hex encoding of `pubkey`.  The wire shape carries this
  /// hex directly under the `pubkey` JSON key.
  String get pubkeyHex {
    final sb = StringBuffer();
    for (final b in pubkey) {
      sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  Map<String, dynamic> toJson() => {
        'cert_id': certId,
        'context_tag': contextTag,
        'parent_cert_id': parentCertId,
        'pubkey': pubkeyHex,
      };

  factory CertRef.fromJson(Map<String, dynamic> j) {
    final pubHex = j['pubkey'] as String;
    if (pubHex.length != pubkeyHexLen) {
      throw FormatException(
          'CertRef.pubkey must be $pubkeyHexLen hex chars, got ${pubHex.length}');
    }
    final pub = Uint8List(pubkeyByteLen);
    for (var i = 0; i < pubkeyByteLen; i++) {
      pub[i] = int.parse(pubHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    final parent = j['parent_cert_id'];
    return CertRef(
      certId: j['cert_id'] as String,
      pubkey: pub,
      contextTag: j['context_tag'] as int,
      parentCertId: parent is String ? parent : null,
    );
  }
}

```
