---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/brc42_verifier.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.012329+00:00
---

# platforms/flutter/semantos_core/lib/src/brc42_verifier.dart

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/asn1.dart' as asn1;
import 'package:pointycastle/ecc/api.dart' as ecc;
import 'package:pointycastle/ecc/curves/secp256k1.dart' as secp;
import 'package:pointycastle/signers/ecdsa_signer.dart' as ecdsa;

import 'bundle_verifier.dart';
import 'extension_bundle.dart';

/// Trust list — the set of signer pubkeys an operator's brain has
/// authorised to publish extensions on their behalf.
///
/// The brain maintains the canonical list; field shells fetch it at
/// boot via a future `wallet.trustedSigners` JSON-RPC method (not yet
/// implemented). Today shells construct a [TrustList] directly from a
/// hardcoded set of pubkeys — the production trust-management UI is a
/// follow-up.
///
/// Trust entries carry a human-readable [label] so install
/// confirmation screens can say "signed by Semantos" instead of
/// "signed by 03ab47…".
class TrustList {
  final Map<String, String> _byPubkey;

  TrustList._(this._byPubkey);

  /// Build from a list of (pubkey, label) pairs.
  factory TrustList.from(Iterable<TrustEntry> entries) {
    final map = <String, String>{};
    for (final e in entries) {
      map[e.pubkey.toLowerCase()] = e.label;
    }
    return TrustList._(map);
  }

  /// Empty trust list — every signer is rejected.
  factory TrustList.empty() => TrustList._(const {});

  /// True if [pubkey] is in the trust list (case-insensitive hex match).
  bool trusts(String pubkey) => _byPubkey.containsKey(pubkey.toLowerCase());

  /// Human-readable label for [pubkey]. Null when not trusted.
  String? labelFor(String pubkey) => _byPubkey[pubkey.toLowerCase()];

  /// All trusted pubkeys (lowercase hex).
  Iterable<String> get pubkeys => _byPubkey.keys;
}

class TrustEntry {
  final String pubkey;
  final String label;
  const TrustEntry({required this.pubkey, required this.label});
}

/// BRC-42-style bundle verifier.
///
/// Implements `brc42-ecdsa-sha256`:
///   1. Validate signature envelope shape (scheme, pubkey hex, sig hex).
///   2. Check signer pubkey is in [trustList].
///   3. Compute SHA-256 over [ExtensionBundle.canonicalBody].
///   4. Verify the DER-encoded ECDSA-secp256k1 signature against
///      (digest, pubkey).
///
/// All four steps run; bundle is accepted only when all pass. Uses
/// pointycastle for the secp256k1 primitive (pure Dart, runs on
/// native + PWA without FFI).
class Brc42BundleVerifier implements BundleVerifier {
  final TrustList trustList;

  const Brc42BundleVerifier({required this.trustList});

  @override
  Future<VerificationResult> verify(ExtensionBundle bundle) async {
    final sig = bundle.signature;
    if (sig == null) {
      return const VerificationResult.unsigned(
        'BRC-42 verifier rejects unsigned bundles (no signature envelope)',
      );
    }
    if (sig.isExplicitlyUnsigned) {
      return const VerificationResult.unsigned(
        'BRC-42 verifier rejects scheme="none" bundles',
      );
    }
    if (sig.scheme != 'brc42-ecdsa-sha256') {
      return VerificationResult.rejected(
        'unsupported signature scheme "${sig.scheme}" '
        '(BRC-42 verifier expects "brc42-ecdsa-sha256")',
      );
    }

    final pubkey = sig.signerPubkey;
    if (pubkey == null || pubkey.length != 66) {
      return const VerificationResult.rejected(
        'signature missing or invalid signerPubkey '
        '(need 66-hex compressed secp256k1 pubkey)',
      );
    }
    if (!_isLowerHex(pubkey)) {
      return const VerificationResult.rejected(
        'signerPubkey must be lowercase hex',
      );
    }
    if (!trustList.trusts(pubkey)) {
      return VerificationResult.rejected(
        'signer ${pubkey.substring(0, 12)}… not in operator trust list',
      );
    }

    final sigHex = sig.signatureBytes;
    if (sigHex == null || sigHex.isEmpty) {
      return const VerificationResult.rejected('signature missing signatureBytes');
    }
    if (!_isLowerHex(sigHex)) {
      return const VerificationResult.rejected('signatureBytes must be lowercase hex');
    }
    if (sigHex.length < 128 || sigHex.length > 160) {
      return VerificationResult.rejected(
        'signatureBytes length ${sigHex.length} outside expected DER range '
        '(128-160 hex chars for secp256k1 ECDSA DER)',
      );
    }

    // Compute digest the signature should have been computed over.
    final digestBytes = Uint8List.fromList(
      sha256.convert(utf8.encode(bundle.canonicalBody())).bytes,
    );

    final pubkeyBytes = _hexToBytes(pubkey);
    final sigBytes = _hexToBytes(sigHex);

    final cryptoOk = _ecdsaVerify(
      pubkeyCompressed: pubkeyBytes,
      derSignature: sigBytes,
      digest: digestBytes,
    );

    if (!cryptoOk) {
      return VerificationResult.rejected(
        'ECDSA signature verification failed for signer '
        '${pubkey.substring(0, 12)}… (signature does not match bundle digest)',
      );
    }

    final label = trustList.labelFor(pubkey)!;
    return VerificationResult.ok(
      'BRC-42 verification passed — signed by $label '
      '(${pubkey.substring(0, 12)}…)',
    );
  }

  /// Verify a DER-encoded secp256k1 ECDSA signature against a digest +
  /// compressed pubkey. Pure pointycastle; runs on native and web.
  static bool _ecdsaVerify({
    required Uint8List pubkeyCompressed,
    required Uint8List derSignature,
    required Uint8List digest,
  }) {
    try {
      final domainParams = secp.ECCurve_secp256k1();
      final point = domainParams.curve.decodePoint(pubkeyCompressed);
      if (point == null) return false;
      final pubParams = ecc.ECPublicKey(point, domainParams);

      // Parse DER: SEQUENCE { INTEGER r, INTEGER s }
      final parser = asn1.ASN1Parser(derSignature);
      final seq = parser.nextObject();
      if (seq is! asn1.ASN1Sequence) return false;
      if (seq.elements == null || seq.elements!.length != 2) return false;
      final rElement = seq.elements![0];
      final sElement = seq.elements![1];
      if (rElement is! asn1.ASN1Integer || sElement is! asn1.ASN1Integer) {
        return false;
      }
      final r = rElement.integer;
      final s = sElement.integer;
      if (r == null || s == null) return false;
      final ecSig = ecc.ECSignature(r, s);

      final signer = ecdsa.ECDSASigner(null, null);
      signer.init(false, pc.PublicKeyParameter<ecc.ECPublicKey>(pubParams));
      return signer.verifySignature(digest, ecSig);
    } catch (_) {
      return false;
    }
  }

  static bool _isLowerHex(String s) {
    for (final c in s.codeUnits) {
      final isDigit = c >= 0x30 && c <= 0x39;
      final isLowerAF = c >= 0x61 && c <= 0x66;
      if (!isDigit && !isLowerAF) return false;
    }
    return true;
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

```
