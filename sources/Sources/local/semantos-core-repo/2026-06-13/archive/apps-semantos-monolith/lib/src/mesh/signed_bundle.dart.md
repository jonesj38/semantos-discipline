---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/mesh/signed_bundle.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.902230+00:00
---

# archive/apps-semantos-monolith/lib/src/mesh/signed_bundle.dart

```dart
// D-O5m.followup-6 Phase 1 — Dart port of
// `runtime/semantos-brain/src/signed_bundle.zig` (the SignedBundle codec) +
// `extensions/oddjobz/tools/send-bundle.ts` (the TS reference encoder).
//
// Reference: runtime/semantos-brain/src/signed_bundle.zig (canonical struct shape,
//            canonical preimage encoder, sign + verify);
//            extensions/oddjobz/tools/send-bundle.ts (TS-side encoder
//            that already agrees byte-for-byte with the Zig codec);
//            apps/oddjobz-mobile/lib/src/identity/cell_signer.dart
//            (the cell-signer ECDSA primitives we reuse — we do NOT
//            duplicate the deterministic-k machinery).
//
// Cross-language seam:
//   • Zig owns the codec on the receive side.  The brain decodes a
//     SignedBundle, verifies the cert chain + signature, then dispatches.
//   • TS (send-bundle.ts) is the desktop / federation peer encoder.
//   • Dart (this file) is the mobile peer encoder for the Phase 2 mesh
//     transport.  It MUST produce a byte-identical canonical preimage
//     to the Zig + TS implementations — without that, Phase 2's
//     transport would be broken at the wire layer.
//
// What "canonical preimage" means:
//   1. Prefix the ASCII bytes "BRAIN-SIGNED-BUNDLE-v1" (no trailing
//      separator) — the SIG_DOMAIN tag.  Prevents cross-protocol sig
//      reuse.
//   2. Append the JSON serialisation of the bundle WITHOUT the
//      `signature` field.  Keys in fixed canonical order:
//        Bundle: payload, payload_type, recipient_cert_id,
//                sender_cert_chain, signature_metadata, v
//        CertRef: cert_id, context_tag, parent_cert_id, pubkey
//        SignatureMetadata: algorithm, nonce_hex, timestamp_unix
//   3. The signature is `ECDSA-secp256k1-SHA256(SHA-256(preimage))` —
//      the inner SHA-256 is the prehash; the digest is what the ECDSA
//      signing scheme consumes.
//
// Why we re-implement the JSON encoder rather than calling
// `dart:convert::jsonEncode(map)`:
//   `jsonEncode` does not guarantee key ordering.  We need byte parity
//   with the Zig encoder, so we build the bytes deterministically here.
//   String escaping IS delegated to `dart:convert::jsonEncode(String)`
//   for individual string values — same JSON string-escape rules
//   match Zig's std.json and JS's JSON.stringify byte-for-byte.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

import '../identity/cell_signer.dart';
import 'cert_ref.dart';
import 'signature_metadata.dart';

/// Schema version of the SignedBundle envelope.  Matches
/// `signed_bundle.zig::ENVELOPE_VERSION`.
const int signedBundleEnvelopeVersion = 1;

/// Domain tag for the canonical signature preimage.  Matches
/// `signed_bundle.zig::SIG_DOMAIN`.
const String signedBundleSigDomain = 'BRAIN-SIGNED-BUNDLE-v1';

/// Length of the compact (r||s) ECDSA signature in bytes.  Matches
/// `signed_bundle.zig::SIG_LEN`.
const int signedBundleSigLen = 64;

/// secp256k1 domain parameters — same instance cell_signer.dart uses.
final ECDomainParameters _secp256k1 = ECCurve_secp256k1();

/// The decoded envelope.  Mirrors the field set in
/// `signed_bundle.zig::SignedBundle`.
class SignedBundle {
  final int v;
  final List<CertRef> senderCertChain;

  /// 32-hex-char recipient cert id, or null for broadcast (the receive
  /// seam rejects broadcast at v0.1, but the codec round-trips it).
  final String? recipientCertId;

  final String payloadType;

  /// Raw payload bytes — whatever the sender wrapped (typically a
  /// dispatch.request envelope JSON string).  The wire form encodes
  /// these as a UTF-8 JSON string.  We carry the bytes verbatim and
  /// the canonical encoder JSON-escapes on the way out.
  final Uint8List payload;

  /// 64-byte compact (r||s) ECDSA signature.  All-zero before signing.
  final Uint8List signature;

  final SignatureMetadata signatureMetadata;

  SignedBundle({
    this.v = signedBundleEnvelopeVersion,
    required this.senderCertChain,
    required this.recipientCertId,
    required this.payloadType,
    required this.payload,
    required this.signature,
    required this.signatureMetadata,
  }) {
    if (signature.length != signedBundleSigLen) {
      throw ArgumentError(
          'signature must be $signedBundleSigLen bytes, got ${signature.length}');
    }
    if (senderCertChain.isEmpty) {
      throw ArgumentError('senderCertChain must not be empty');
    }
  }

  /// Convenience: a copy with `signature` replaced.
  SignedBundle copyWithSignature(Uint8List newSignature) => SignedBundle(
        v: v,
        senderCertChain: senderCertChain,
        recipientCertId: recipientCertId,
        payloadType: payloadType,
        payload: payload,
        signature: newSignature,
        signatureMetadata: signatureMetadata,
      );

  /// Convenience: a copy with `payload` replaced.  Used by tamper tests.
  SignedBundle copyWithPayload(Uint8List newPayload) => SignedBundle(
        v: v,
        senderCertChain: senderCertChain,
        recipientCertId: recipientCertId,
        payloadType: payloadType,
        payload: newPayload,
        signature: signature,
        signatureMetadata: signatureMetadata,
      );

  /// Encode to wire JSON bytes (with the signature field present).
  /// Mirrors `signed_bundle.zig::encode`.
  Uint8List encode() => Uint8List.fromList(
      utf8.encode(_writeBundleJson(this, includeSignature: true)));

  /// Decode wire JSON bytes back into a SignedBundle.  Mirrors
  /// `signed_bundle.zig::decode` minus the OwnedBundle allocator
  /// dance (Dart's GC handles lifetimes).
  static SignedBundle decode(Uint8List wireBytes) {
    final s = utf8.decode(wireBytes);
    final j = json.decode(s) as Map<String, dynamic>;
    final v = j['v'] as int;
    if (v != signedBundleEnvelopeVersion) {
      throw FormatException('SignedBundle.v unsupported: $v');
    }
    final chainJson = j['sender_cert_chain'] as List<dynamic>;
    if (chainJson.isEmpty) {
      throw const FormatException('SignedBundle.sender_cert_chain empty');
    }
    final chain = chainJson
        .map((e) => CertRef.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    final recipient = j['recipient_cert_id'];
    final sigHex = j['signature'] as String;
    if (sigHex.length != signedBundleSigLen * 2) {
      throw FormatException(
          'SignedBundle.signature must be ${signedBundleSigLen * 2} hex chars, got ${sigHex.length}');
    }
    final sig = Uint8List(signedBundleSigLen);
    for (var i = 0; i < signedBundleSigLen; i++) {
      sig[i] = int.parse(sigHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return SignedBundle(
      v: v,
      senderCertChain: chain,
      recipientCertId: recipient is String ? recipient : null,
      payloadType: j['payload_type'] as String,
      payload: Uint8List.fromList(utf8.encode(j['payload'] as String)),
      signature: sig,
      signatureMetadata:
          SignatureMetadata.fromJson(j['signature_metadata'] as Map<String, dynamic>),
    );
  }
}

/// Compute the canonical signature preimage bytes for `b`.  Byte-
/// identical to `signed_bundle.zig::canonicalSignaturePreimage` and
/// `send-bundle.ts::canonicalSignaturePreimage`.
Uint8List computeCanonicalPreimage(SignedBundle b) {
  final inner = _writeBundleJson(b, includeSignature: false);
  final out = utf8.encode(signedBundleSigDomain + inner);
  return Uint8List.fromList(out);
}

/// SHA-256 of the canonical preimage.  This is the digest the ECDSA
/// signer consumes.
Uint8List computeSignDigest(SignedBundle b) {
  final preimage = computeCanonicalPreimage(b);
  final digest = Uint8List(32);
  final sha = SHA256Digest();
  sha.update(preimage, 0, preimage.length);
  sha.doFinal(digest, 0);
  return digest;
}

/// Sign `unsigned` with `signingPriv` (32-byte secp256k1 private key)
/// and return a copy with `.signature` filled in.  Reuses
/// `cell_signer.dart::signCellPayload`'s ECDSA primitives —
/// deterministic-k matches Zig stdlib byte-for-byte.
SignedBundle signBundle({
  required SignedBundle unsigned,
  required Uint8List signingPriv,
}) {
  final preimage = computeCanonicalPreimage(unsigned);
  // signCellPayload internally computes SHA-256(payload) → ECDSA →
  // strip recovery byte → low-s normalise, returning 64-byte r||s.
  // The bundle's preimage is what gets prehashed; we hand it in
  // verbatim and let the signer do the SHA-256 step.
  final sig = signCellPayload(preimage, signingPriv);
  if (sig.length != signedBundleSigLen) {
    throw StateError(
        'signCellPayload returned ${sig.length} bytes, expected $signedBundleSigLen');
  }
  return unsigned.copyWithSignature(sig);
}

/// Verify the bundle's signature against `expectedPubkey` (33-byte
/// compressed-SEC1 leaf cert pubkey).  Mirrors
/// `signed_bundle.zig::verifySignature`'s recovery loop over recovery
/// bytes 31..34 (which corresponds to recId 0..3 in standard SEC1
/// terminology).  Returns true on a match, false otherwise.
bool verifyBundleSignature({
  required SignedBundle bundle,
  required Uint8List expectedPubkey,
}) {
  if (bundle.signatureMetadata.algorithm != defaultSignatureAlgorithm) {
    return false;
  }
  // The cell_signer's verifyCellSignature hashes the payload bytes
  // with SHA-256 internally, then runs the recovery loop against
  // that digest.  We hand it the canonical preimage (NOT the
  // brain-side `sha256(preimage)` digest) so it can do the same.
  final preimage = computeCanonicalPreimage(bundle);
  return verifyCellSignature(preimage, bundle.signature, expectedPubkey);
}

// ─────────────────────────────────────────────────────────────────────
// Canonical JSON encoder — must produce the same bytes the Zig +
// TS encoders produce.  Sorted keys; no whitespace; numbers as
// base-10 integers; strings JSON-escaped.
// ─────────────────────────────────────────────────────────────────────

String _writeBundleJson(SignedBundle b, {required bool includeSignature}) {
  // Mirror Zig's writeBundleJson key order: payload, payload_type,
  // recipient_cert_id, sender_cert_chain, [signature], signature_metadata, v.
  final parts = <String>[];
  parts.add('${jsonEncode("payload")}:${jsonEncode(utf8.decode(b.payload))}');
  parts.add('${jsonEncode("payload_type")}:${jsonEncode(b.payloadType)}');
  parts.add(
      '${jsonEncode("recipient_cert_id")}:${b.recipientCertId == null ? 'null' : jsonEncode(b.recipientCertId)}');
  parts.add('${jsonEncode("sender_cert_chain")}:${_encodeChain(b.senderCertChain)}');
  if (includeSignature) {
    parts.add('${jsonEncode("signature")}:${jsonEncode(_bytesToHex(b.signature))}');
  }
  parts.add('${jsonEncode("signature_metadata")}:${_encodeSignatureMetadata(b.signatureMetadata)}');
  parts.add('${jsonEncode("v")}:${b.v}');
  return '{${parts.join(",")}}';
}

String _encodeChain(List<CertRef> chain) {
  final parts = chain.map(_encodeCertRef).toList(growable: false);
  return '[${parts.join(",")}]';
}

String _encodeCertRef(CertRef c) {
  // Key order: cert_id, context_tag, parent_cert_id, pubkey.
  final parts = <String>[
    '${jsonEncode("cert_id")}:${jsonEncode(c.certId)}',
    '${jsonEncode("context_tag")}:${c.contextTag}',
    '${jsonEncode("parent_cert_id")}:${c.parentCertId == null ? 'null' : jsonEncode(c.parentCertId)}',
    '${jsonEncode("pubkey")}:${jsonEncode(c.pubkeyHex)}',
  ];
  return '{${parts.join(",")}}';
}

String _encodeSignatureMetadata(SignatureMetadata m) {
  final parts = <String>[
    '${jsonEncode("algorithm")}:${jsonEncode(m.algorithm)}',
    '${jsonEncode("nonce_hex")}:${jsonEncode(m.nonceHex)}',
    '${jsonEncode("timestamp_unix")}:${m.timestampUnix}',
  ];
  return '{${parts.join(",")}}';
}

String _bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Suppress unused-import lint — the cell_signer import is load-
/// bearing (signCellPayload + verifyCellSignature are called above)
/// but the analyzer occasionally flags pointycastle imports if no
/// other consumer touches them.  This sink keeps us honest about
/// the dependency without changing observable behaviour.
// ignore: unused_element
ECDomainParameters get _curveSink => _secp256k1;

```
