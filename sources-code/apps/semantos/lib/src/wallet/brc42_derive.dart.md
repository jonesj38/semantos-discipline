---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/brc42_derive.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.107186+00:00
---

# apps/semantos/lib/src/wallet/brc42_derive.dart

```dart
// C11 PR-C11-4c — unilateral node-derivation primitive (Dart).
//
// CW Lift L11 (kdf-v2): this is EP3259724B1 `deriveSegment`, the canonical
// UNILATERAL primitive — there is no counterparty, so the v0 self-ECDH
// (`ECDH(parentSk, parentPub)` with sender == recipient) was a degenerate
// BRC-42 misuse. It is replaced here by `tweak = SHA-256(invoice)`.
//
// References:
//   - TS reference: cartridges/wallet-headers/brain/src/ecdh42.ts
//     (deriveChangeSk / cell-anchor.ts — same v2 primitive, byte-identical)
//   - Zig mirror: runtime/semantos-brain/src/derive_segment.zig (KAT-proven)
//   - docs/prd/CW-LIFT-ROADMAP.md §2.2
//
// Scope of this file:
//   - Unilateral derivation only. The counterparty (edge) domain
//     `BRC42(senderSk, recipientPk, index)` lives in `edge_derive.dart`
//     and correctly STAYS BRC-42 (bilateral).
//   - This primitive covers tier-0 vault, per-context spending, change,
//     and anchor universes — all the derivations the wallet needs to
//     spend on its own behalf.
//
// Algorithm (EP3259724B1 deriveSegment):
//
//     invoice    = protocolHash(16) || index_le(8)        (24 bytes)
//     tweak      = SHA-256(invoice)                        (32 bytes)
//     childSk    = (parentSk + tweak) mod N               (32 bytes)
//
// `protocolHash` is the SHA-256 of a domain-string prefix truncated to 16
// bytes (see `derivation_domain.dart`). The 24-byte invoice + SHA-256 tweak
// make this PRIMITIVE byte-identical to the TS/Zig wallet's deriveSegment.
// (End-key equality with the brain wallet additionally requires the same
// parent + preimage; the PWA uses a 4-layer tree (root→tier0→domain) vs the
// brain's identity-direct derivation, so the keys are NOT cross-equal today —
// see the P6 PR notes on domain unification.)
//
// Clean cutover: no version gate — the existing on-chain artefacts are
// throwaway prototyping objects with no spend/binding intent.

import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

/// secp256k1 curve parameters. Same instance the cell signer uses.
final ECDomainParameters _secp256k1 = ECCurve_secp256k1();

/// Curve order N. Cached at module load so we don't re-allocate per
/// derivation call.
final BigInt _n = _secp256k1.n;

/// 32-byte zero padding for left-aligning small BigInt scalars into a
/// big-endian buffer.
const int _scalarByteLen = 32;

/// Compute a BRC-42 self-derived child private key.
///
/// Parameters:
///   - [parentSk]: 32-byte big-endian secp256k1 private key.
///   - [protocolHash]: 16-byte domain marker (see `derivation_domain.dart`).
///   - [index]: monotonically increasing per-domain index. Must be
///     `>= 0` and fit in a u64.
///   - [domainFlag]: optional canonical u32 domain flag (CW Lift L11.5,
///     kdf-v3). When supplied, it is folded into the tweak as a 4-byte
///     big-endian tag — `tweak = SHA-256(u32_be(domainFlag) || invoice)` —
///     binding the key to its declared domain (matches the brain's
///     `deriveDomainSegment` / `deriveChangeSk` / `deriveCellAnchorSk`). When
///     null the legacy v2 tweak `SHA-256(invoice)` is used (tier0/spend, which
///     have no brain counterpart and stay v2 pending the P6 re-architecture).
///
/// Returns the 32-byte child private key.
///
/// Throws [ArgumentError] for malformed inputs and [StateError] if
/// the derivation produces a degenerate scalar (probability ~ 2^-128
/// per BRC-42; treated as a recoverable corruption rather than a
/// silent failure).
///
/// Implementation note: this function does **not** zero out
/// intermediate buffers. Dart's GC will reclaim them but they may
/// persist in memory between collections. For cert-priv-handling code
/// paths, scope this call to a tight async function and let the
/// caller manage lifetime.
Uint8List deriveSelfChild({
  required Uint8List parentSk,
  required Uint8List protocolHash,
  required int index,
  int? domainFlag,
}) {
  if (parentSk.length != 32) {
    throw ArgumentError.value(
        parentSk.length, 'parentSk.length', 'must be 32 bytes');
  }
  if (protocolHash.length != 16) {
    throw ArgumentError.value(
        protocolHash.length, 'protocolHash.length', 'must be 16 bytes');
  }
  if (index < 0) {
    throw ArgumentError.value(index, 'index', 'must be non-negative');
  }
  if (domainFlag != null && (domainFlag < 0 || domainFlag > 0xffffffff)) {
    throw ArgumentError.value(domainFlag, 'domainFlag', 'must be a u32');
  }

  // 1. Validate the parent scalar is in range.
  final parentScalar = _bytesToBigIntBE(parentSk);
  if (parentScalar == BigInt.zero || parentScalar >= _n) {
    throw ArgumentError.value(
        parentSk, 'parentSk', 'out of secp256k1 scalar range');
  }

  // 2. invoice = protocolHash || u64_le(index)   (the deriveSegment segment)
  final invoice = Uint8List(24);
  invoice.setRange(0, 16, protocolHash);
  for (var i = 0; i < 8; i++) {
    invoice[16 + i] = (index >> (8 * i)) & 0xff;
  }

  // 3. tweak = SHA-256( [u32_be(domainFlag)] || invoice ). No ECDH, no HMAC —
  //    unilateral, no counterparty. kdf-v3 (CW Lift L11.5) prepends the 4-byte
  //    big-endian domain flag to bind the key to its domain; kdf-v2 (domainFlag
  //    null) hashes the invoice alone.
  final Uint8List tweak;
  if (domainFlag != null) {
    final preimage = Uint8List(4 + invoice.length);
    preimage[0] = (domainFlag >> 24) & 0xff;
    preimage[1] = (domainFlag >> 16) & 0xff;
    preimage[2] = (domainFlag >> 8) & 0xff;
    preimage[3] = domainFlag & 0xff;
    preimage.setRange(4, 4 + invoice.length, invoice);
    tweak = SHA256Digest().process(preimage);
  } else {
    tweak = SHA256Digest().process(invoice);
  }

  // 4. childSk = (parentSk + tweak) mod N
  final tweakScalar = _bytesToBigIntBE(tweak);
  final child = (parentScalar + tweakScalar) % _n;
  if (child == BigInt.zero) {
    throw StateError(
        'deriveSegment: degenerate child scalar (zero) at index $index');
  }
  return _bigIntToBytesBE(child, _scalarByteLen);
}

/// Compute the 33-byte compressed secp256k1 public key for a private
/// key. Convenience for callers that have a child priv from
/// [deriveSelfChild] and need to publish or fingerprint the pub.
Uint8List publicKeyFromPrivate(Uint8List sk) {
  if (sk.length != 32) {
    throw ArgumentError.value(sk.length, 'sk.length', 'must be 32 bytes');
  }
  final scalar = _bytesToBigIntBE(sk);
  if (scalar == BigInt.zero || scalar >= _n) {
    throw ArgumentError.value(sk, 'sk', 'out of secp256k1 scalar range');
  }
  final pub = (_secp256k1.G * scalar)!;
  return pub.getEncoded(true);
}

BigInt _bytesToBigIntBE(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _bigIntToBytesBE(BigInt value, int length) {
  final result = Uint8List(length);
  var remaining = value;
  for (var i = length - 1; i >= 0; i--) {
    result[i] = (remaining & BigInt.from(0xff)).toInt();
    remaining = remaining >> 8;
  }
  return result;
}

```
