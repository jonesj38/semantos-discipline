---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/mesh/signature_metadata.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.903408+00:00
---

# archive/apps-semantos-monolith/lib/src/mesh/signature_metadata.dart

```dart
// D-O5m.followup-6 Phase 1 — Dart port of
// `runtime/semantos-brain/src/signed_bundle.zig::SignatureMetadata`.
//
// The signature_metadata sub-object on a SignedBundle.  Carries the
// algorithm pin + the anti-replay nonce + the sender's wall-clock
// timestamp at sign time.  The receive seam clamps the timestamp
// against a configurable freshness window and the nonce against an
// LRU; the codec itself only round-trips the bytes.
//
// Field-shape contract (mirrors signed_bundle.zig):
//   • algorithm: "ecdsa-secp256k1-sha256" (the only accepted value at v0.1)
//   • nonceHex: 64-hex-char nonce (32 random bytes)
//   • timestampUnix: signed 64-bit integer (seconds since epoch)
//
// Canonical-encoder field order for the JSON object (matches Zig):
//   algorithm, nonce_hex, timestamp_unix.

const String defaultSignatureAlgorithm = 'ecdsa-secp256k1-sha256';

/// Length of the nonce in hex chars (matches
/// `signed_bundle.zig::NONCE_HEX_LEN`).
const int nonceHexLen = 64;

class SignatureMetadata {
  final String algorithm;
  final String nonceHex;
  final int timestampUnix;

  SignatureMetadata({
    this.algorithm = defaultSignatureAlgorithm,
    required this.nonceHex,
    required this.timestampUnix,
  }) {
    if (nonceHex.length != nonceHexLen) {
      throw ArgumentError(
          'nonceHex must be $nonceHexLen hex chars, got ${nonceHex.length}');
    }
  }

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm,
        'nonce_hex': nonceHex,
        'timestamp_unix': timestampUnix,
      };

  factory SignatureMetadata.fromJson(Map<String, dynamic> j) {
    return SignatureMetadata(
      algorithm: (j['algorithm'] as String?) ?? defaultSignatureAlgorithm,
      nonceHex: j['nonce_hex'] as String,
      timestampUnix: j['timestamp_unix'] as int,
    );
  }
}

```
