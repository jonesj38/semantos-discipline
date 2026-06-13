---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-apps/jam-room-mobile/lib/src/pairing/pair_payload.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.831540+00:00
---

# archive/apps-world-apps/jam-room-mobile/lib/src/pairing/pair_payload.dart

```dart
// D-O5m — Decoded view of a v2 pairing payload.
//
// Mirrors the TS reference's `DecodedPairingPayload` interface in
// `extensions/oddjobz/src/device-pair-client.ts`. Field names follow
// Dart's camelCase convention; the underlying JSON wire shape is
// snake_case (matching `runtime/semantos-brain/src/device_pair.zig`'s
// `canonicalJsonForSigning`).
//
// Wire format reference:
//   - runtime/semantos-brain/src/device_pair.zig lines 180-260 (PairPayload)
//   - extensions/oddjobz/tests/vectors/device-pair/v2-fixture.json
//
// This module deliberately matches the TS shape byte-for-byte so the
// cross-language parity test (test/pairing/decode_token_test.dart)
// can decode the same fixture and assert all decoded fields equal.

/// Wire-format domain tag — must match
/// `runtime/semantos-brain/src/device_pair.zig`'s WIRE_DOMAIN.
const String wireDomain = 'brain-device-pair-v2';

/// Wire-format version — must match `device_pair.zig`'s WIRE_VERSION.
const int wireVersion = 2;

/// Decoded view of a v2 pairing payload. Field names mirror the JSON
/// wire shape in camelCase per Dart convention (see `decode_token.dart`
/// for the snake_case <-> camelCase translation).
class PairPayload {
  /// Wire-format version (must equal `wireVersion`).
  final int v;

  /// Wire-format domain tag (must equal `wireDomain`).
  final String domain;

  /// Operator's root cert id, 32 hex chars.
  final String operatorRootCertId;

  /// Operator's root pubkey, 66 hex chars (compressed SEC1).
  final String operatorRootPub;

  /// Per-device contextTag (spec v0.5 §4.4 isolation). u8: 0..255.
  final int contextTag;

  /// Operator-supplied label (e.g. "Todd's iPhone").
  final String label;

  /// Capability allowlist (e.g. ["cap.attach.photo", ...]).
  final List<String> capabilities;

  /// Unix-seconds expiry; pairing token is one-shot but the brain
  /// also rejects stale tokens.
  final int expiresAt;

  /// 16-byte CSPRNG nonce, 32 hex chars.
  final String nonce;

  /// Production HTTPS endpoint the device POSTs its claim_child
  /// payload to (e.g. https://oddjobtodd.info/api/v1/device-pair).
  final String brainPairEndpoint;

  /// Post-pair operations WSS endpoint the device opens once
  /// registered (e.g. wss://oddjobtodd.info/api/v1/wallet).
  final String brainWssEndpoint;

  /// Cert pinning value the device pins. Same value as
  /// operatorRootCertId today; kept distinct so a future delegated-
  /// brain fork is a one-field rev.
  final String brainPinCertId;

  /// Pubkey the device pins. Same value as operatorRootPub today.
  final String brainPinPubkey;

  /// Operator signature over the canonical JSON (DER-hex).
  final String signature;

  const PairPayload({
    required this.v,
    required this.domain,
    required this.operatorRootCertId,
    required this.operatorRootPub,
    required this.contextTag,
    required this.label,
    required this.capabilities,
    required this.expiresAt,
    required this.nonce,
    required this.brainPairEndpoint,
    required this.brainWssEndpoint,
    required this.brainPinCertId,
    required this.brainPinPubkey,
    required this.signature,
  });

  @override
  String toString() =>
      'PairPayload(v=$v, domain=$domain, label=$label, contextTag=$contextTag, '
      'caps=${capabilities.length}, brainPairEndpoint=$brainPairEndpoint)';
}

/// Thrown when a pairing token's wire shape, version, domain, or
/// individual field types/sizes are invalid. The message is operator-
/// readable and is surfaced verbatim by the pairing UI.
class PairPayloadFormatException implements Exception {
  final String message;
  const PairPayloadFormatException(this.message);

  @override
  String toString() => 'PairPayloadFormatException: $message';
}

```
