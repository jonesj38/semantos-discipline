---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/edge_derive.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.104356+00:00
---

# apps/semantos/lib/src/wallet/edge_derive.dart

```dart
// C11 PR-C11-7b — BRC-42 edge (counterparty-scoped) derivation.
//
// References:
//   - BRC-42 spec: https://bsv.brc.dev/key-derivation/0042
//   - BRC-29 spec: Simple Authenticated BSV P2PKH Payment Protocol
//     (invoice format: "2-3241645161d8-<prefix> <suffix>")
//   - TS reference: cartridges/wallet-headers/brain/src/ecdh42.ts
//   - Self-derivation sibling: lib/src/wallet/brc42_derive.dart
//   - Renderer contract: docs/design/WALLET-RENDERER-CONTRACT.md §2
//
// Algorithm (per BRC-42, asymmetric counterparty):
//
//     shared    = ECDH(mySk, theirPub) = mySk · theirPub  (33-byte compressed)
//     tweak     = HMAC-SHA256(shared, invoiceBytes)        (32 bytes)
//     childSk   = (recipientSk + tweak) mod N              (recipient view)
//     childPub  = recipientPub + tweak · G                 (sender view)
//
// Symmetry: ECDH(mySk, theirPub) == ECDH(theirSk, myPub) — so sender and
// recipient compute the same `shared` and hence the same `tweak`, given
// the same `invoiceBytes`. Sender produces the address; recipient
// derives the spending key. Neither side needs the other's priv.
//
// Two invoice shapes ship here:
//
//   1. Binary 24-byte: protocolHash(16) || u64_le(index). Matches the
//      change/edge domain in `ecdh42.ts`. Used by the wallet-internal
//      edge domain (kept for completeness — counterparty derivations
//      under that scheme appear in the rederivation envelope already).
//
//   2. Text BRC-29: "2-3241645161d8-<derivationPrefix> <derivationSuffix>"
//      UTF-8 encoded. This is the on-the-wire P2P payment invoice
//      format every BSV ecosystem wallet implements per BRC-29.
//
// Implementation note: this file does NOT zero out intermediate
// buffers. Dart's GC will reclaim them but they may persist between
// collections. For cert-priv-handling paths, scope these calls to a
// tight async function and let the caller manage lifetime — same as
// `brc42_derive.dart`.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart' show KeyParameter;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:pointycastle/macs/hmac.dart';

import 'brc42_derive.dart' show publicKeyFromPrivate;

/// secp256k1 domain parameters. Same instance the rest of the wallet
/// uses (cell signer, brc42_derive).
final ECDomainParameters _secp256k1 = ECCurve_secp256k1();

/// Curve order N.
final BigInt _n = _secp256k1.n;

/// 32-byte big-endian width for scalar buffers.
const int _scalarByteLen = 32;

/// BRC-29 magic number identifying the protocol (per spec §Key Derivation).
const String kBrc29Magic = '3241645161d8';

/// BRC-29 security level prefix (per BRC-43).
const int kBrc29SecurityLevel = 2;

/// BRC-29 edge protocol hash: SHA-256("BRC-42-edge-creation")[0:16].
/// Matches `EDGE_PROTOCOL_HASH` in ecdh42.ts.
final Uint8List kEdgeProtocolHash = Uint8List.sublistView(
    SHA256Digest().process(utf8.encode('BRC-42-edge-creation')), 0, 16);

/// Compute the raw ECDH shared point, compressed.
///
/// `shared = mySk · theirPub` (an EC point), returned as the 33-byte
/// compressed SEC1 encoding. This is the un-hashed point exactly as
/// `@noble/secp256k1`'s `getSharedSecret(mySk, theirPub, true)` returns
/// it — the byte-level input both the BRC-42 tweak HMAC (key = this raw
/// point, per `ecdh42.ts`) and the edge-creation leaf derivation
/// (key = SHA-256 of this point, per `host.ts` `deriveLeafSync`) chain
/// over. Factored out so the two conventions share one point math path.
///
/// Throws [ArgumentError] for malformed inputs.
Uint8List ecdhSharedCompressed({
  required Uint8List mySk,
  required Uint8List theirPub,
}) {
  if (mySk.length != 32) {
    throw ArgumentError.value(
        mySk.length, 'mySk.length', 'must be 32 bytes');
  }
  if (theirPub.length != 33 && theirPub.length != 65) {
    throw ArgumentError.value(
        theirPub.length, 'theirPub.length', 'must be 33 or 65 bytes');
  }
  final mySkScalar = _bytesToBigIntBE(mySk);
  if (mySkScalar == BigInt.zero || mySkScalar >= _n) {
    throw ArgumentError.value(
        mySk, 'mySk', 'out of secp256k1 scalar range');
  }
  // Parse counterparty pub as an EC point.
  final theirPoint = _secp256k1.curve.decodePoint(theirPub);
  if (theirPoint == null || theirPoint.isInfinity) {
    throw ArgumentError.value(
        theirPub, 'theirPub', 'invalid secp256k1 point');
  }
  // shared = mySk · theirPub (an EC point), compressed.
  final sharedPoint = (theirPoint * mySkScalar)!;
  if (sharedPoint.isInfinity) {
    throw ArgumentError('ECDH: shared point is at infinity');
  }
  return sharedPoint.getEncoded(true);
}

/// Compute the BRC-42 tweak.
///
/// `mySk` and `theirPub` are the local-private / counterparty-public
/// inputs to ECDH. `invoiceBytes` is the application-defined data the
/// HMAC chains over — either the 24-byte binary format from
/// `ecdh42.ts` or the UTF-8 bytes of a BRC-29 invoice string.
///
/// Returns the 32-byte HMAC output. Throws [ArgumentError] for
/// malformed inputs.
Uint8List computeBrc42Tweak({
  required Uint8List mySk,
  required Uint8List theirPub,
  required Uint8List invoiceBytes,
}) {
  // BRC-42 (ecdh42.ts): HMAC key = the raw compressed ECDH point.
  final shared = ecdhSharedCompressed(mySk: mySk, theirPub: theirPub);
  // tweak = HMAC-SHA256(shared, invoiceBytes)
  final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(shared));
  return hmac.process(invoiceBytes);
}

/// Add a tweak to a private key: `child = (priv + tweak) mod N`.
/// Throws [StateError] if the result is degenerate (≈ 2^-128 odds).
Uint8List applyTweakToPrivate(Uint8List priv, Uint8List tweak) {
  if (priv.length != 32) {
    throw ArgumentError.value(
        priv.length, 'priv.length', 'must be 32 bytes');
  }
  if (tweak.length != 32) {
    throw ArgumentError.value(
        tweak.length, 'tweak.length', 'must be 32 bytes');
  }
  final base = _bytesToBigIntBE(priv);
  final t = _bytesToBigIntBE(tweak);
  final child = (base + t) % _n;
  if (child == BigInt.zero) {
    throw StateError('BRC-42 edge derive: degenerate child scalar');
  }
  return _bigIntToBytesBE(child, _scalarByteLen);
}

/// Add a tweak to a public key: `child = pub + tweak · G`. Used by
/// the SENDER side of an edge derivation to compute the recipient's
/// rotated pubkey without ever touching the recipient's priv.
Uint8List applyTweakToPublic(Uint8List pub, Uint8List tweak) {
  if (pub.length != 33 && pub.length != 65) {
    throw ArgumentError.value(
        pub.length, 'pub.length', 'must be 33 or 65 bytes');
  }
  if (tweak.length != 32) {
    throw ArgumentError.value(
        tweak.length, 'tweak.length', 'must be 32 bytes');
  }
  final pubPoint = _secp256k1.curve.decodePoint(pub);
  if (pubPoint == null || pubPoint.isInfinity) {
    throw ArgumentError.value(pub, 'pub', 'invalid secp256k1 point');
  }
  final t = _bytesToBigIntBE(tweak);
  if (t == BigInt.zero) {
    throw StateError('BRC-42 edge derive: zero tweak (unexpected)');
  }
  final tweakPoint = (_secp256k1.G * t)!;
  final childPoint = (pubPoint + tweakPoint)!;
  if (childPoint.isInfinity) {
    throw StateError('BRC-42 edge derive: degenerate child point');
  }
  return childPoint.getEncoded(true);
}

// ─────────────── 24-byte binary invoice (ecdh42 EDGE/CHANGE) ───────────────

/// Build the binary 24-byte invoice used by the legacy `ecdh42.ts`
/// edge/change domains: `protocolHash(16) || u64_le(index)`.
Uint8List buildBinaryInvoice({
  required Uint8List protocolHash,
  required int signingKeyIndex,
}) {
  if (protocolHash.length != 16) {
    throw ArgumentError.value(
        protocolHash.length, 'protocolHash.length', 'must be 16 bytes');
  }
  if (signingKeyIndex < 0) {
    throw ArgumentError.value(signingKeyIndex, 'signingKeyIndex',
        'must be non-negative');
  }
  final invoice = Uint8List(24);
  invoice.setRange(0, 16, protocolHash);
  for (var i = 0; i < 8; i++) {
    invoice[16 + i] = (signingKeyIndex >> (8 * i)) & 0xff;
  }
  return invoice;
}

/// Recipient view: derive the spend SK for a payment the sender
/// addressed to me at [signingKeyIndex] under the EDGE protocol hash.
/// Mirror of `deriveEdgeSk` in ecdh42.ts.
Uint8List deriveEdgeSk({
  required Uint8List recipientSk,
  required Uint8List senderPub,
  required int signingKeyIndex,
}) {
  final invoice = buildBinaryInvoice(
    protocolHash: kEdgeProtocolHash,
    signingKeyIndex: signingKeyIndex,
  );
  final tweak = computeBrc42Tweak(
    mySk: recipientSk,
    theirPub: senderPub,
    invoiceBytes: invoice,
  );
  return applyTweakToPrivate(recipientSk, tweak);
}

/// Sender view: derive the recipient's rotated PUB at
/// [signingKeyIndex] under the EDGE protocol hash. Mirror of
/// `buildRotatedLock`'s pub-derive step in ecdh42.ts.
Uint8List deriveEdgePub({
  required Uint8List senderSk,
  required Uint8List recipientPub,
  required int signingKeyIndex,
}) {
  final invoice = buildBinaryInvoice(
    protocolHash: kEdgeProtocolHash,
    signingKeyIndex: signingKeyIndex,
  );
  // Sender computes ECDH(senderSk, recipientPub) = recipientPub · senderSk,
  // same shared bytes the recipient gets via ECDH(recipientSk, senderPub).
  final tweak = computeBrc42Tweak(
    mySk: senderSk,
    theirPub: recipientPub,
    invoiceBytes: invoice,
  );
  return applyTweakToPublic(recipientPub, tweak);
}

// ─────────────── BRC-29 text invoice ───────────────

/// Build the canonical BRC-29 invoice string for a (prefix, suffix)
/// pair: `"2-3241645161d8-<prefix> <suffix>"` (note the literal
/// space between prefix and suffix — required by spec).
String brc29InvoiceString({
  required String derivationPrefix,
  required String derivationSuffix,
}) {
  if (derivationPrefix.isEmpty) {
    throw ArgumentError.value(
        derivationPrefix, 'derivationPrefix', 'must be non-empty');
  }
  if (derivationSuffix.isEmpty) {
    throw ArgumentError.value(
        derivationSuffix, 'derivationSuffix', 'must be non-empty');
  }
  return '$kBrc29SecurityLevel-$kBrc29Magic-'
      '$derivationPrefix $derivationSuffix';
}

/// Recipient view: derive the spend SK for an incoming BRC-29
/// payment, using the prefix + suffix from the sender's
/// `paymentRemittance` payload and the sender's identity pub.
Uint8List deriveBrc29ChildSk({
  required Uint8List recipientSk,
  required Uint8List senderPub,
  required String derivationPrefix,
  required String derivationSuffix,
}) {
  final invoice = brc29InvoiceString(
    derivationPrefix: derivationPrefix,
    derivationSuffix: derivationSuffix,
  );
  final tweak = computeBrc42Tweak(
    mySk: recipientSk,
    theirPub: senderPub,
    invoiceBytes: Uint8List.fromList(utf8.encode(invoice)),
  );
  return applyTweakToPrivate(recipientSk, tweak);
}

/// Sender view: derive the recipient's rotated PUB for an outgoing
/// BRC-29 payment. The sender uses (own priv, recipient identity pub,
/// invoice) to compute the child pub; the P2PKH lock for the
/// output's scriptPubKey is `addressFromPub(childPub)`.
Uint8List deriveBrc29ChildPub({
  required Uint8List senderSk,
  required Uint8List recipientPub,
  required String derivationPrefix,
  required String derivationSuffix,
}) {
  final invoice = brc29InvoiceString(
    derivationPrefix: derivationPrefix,
    derivationSuffix: derivationSuffix,
  );
  final tweak = computeBrc42Tweak(
    mySk: senderSk,
    theirPub: recipientPub,
    invoiceBytes: Uint8List.fromList(utf8.encode(invoice)),
  );
  return applyTweakToPublic(recipientPub, tweak);
}

/// Convenience: the sender already has the recipient's identity pub
/// and wants to know what the rotated pub is so they can address an
/// output to it. Equivalent to `deriveBrc29ChildPub` but signature-
/// compatible with the recipient's `deriveBrc29ChildSk` for symmetry
/// tests (recipient's `publicKeyFromPrivate(deriveBrc29ChildSk(...))`
/// must equal sender's `deriveBrc29ChildPub(...)`).
Uint8List recoverBrc29ChildPub({
  required Uint8List recipientSk,
  required Uint8List senderPub,
  required String derivationPrefix,
  required String derivationSuffix,
}) {
  final sk = deriveBrc29ChildSk(
    recipientSk: recipientSk,
    senderPub: senderPub,
    derivationPrefix: derivationPrefix,
    derivationSuffix: derivationSuffix,
  );
  try {
    return publicKeyFromPrivate(sk);
  } finally {
    sk.fillRange(0, sk.length, 0);
  }
}

// ─────────────── helpers ───────────────

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
