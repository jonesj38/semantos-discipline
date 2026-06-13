---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/brain_wallet_kat_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.125717+00:00
---

# apps/semantos/test/wallet/brain_wallet_kat_test.dart

```dart
// L11 P6 — Cross-language Known-Answer Test: the operator PWA wallet
// derives BYTE-IDENTICAL change + cell-anchor keys to the brain wallet.
//
// This is the gate for the PWA ↔ brain wallet unification
// (docs/prd/PWA-BRAIN-WALLET-UNIFICATION.md §2.4). It proves real
// key-equality, not just primitive-shape parity: for fixed
// (identityKey, index) and (identityKey, typeHash, index), the PWA's
// `change` / `anchor` derivation produces the same priv AND pub as the
// brain's `deriveChangeSk` / `deriveCellAnchorSk`.
//
// Vectors are generated against the EXACT functions the brain runs on
// mainnet:
//   cartridges/wallet-headers/brain/src/ecdh42.ts    (deriveChangeSk)
//   cartridges/wallet-headers/brain/src/cell-anchor.ts (deriveCellAnchorSk)
// via cartridges/wallet-headers/brain/scripts/gen-pwa-wallet-kat.ts,
// committed as test/wallet/brain_wallet_kat.json. Regenerate with:
//   cd cartridges/wallet-headers/brain
//   bun run scripts/gen-pwa-wallet-kat.ts > \
//     ../../../apps/semantos/test/wallet/brain_wallet_kat.json
//
// ASSUMPTION (stated explicitly per the spec): the PWA's `cert_body`
// IS the brain's `identitySk` — i.e. the operator's PWA holds the same
// identity private key the brain pins as its operator key. The KAT
// proves byte-equality GIVEN that. (A non-admin user holds a different
// identity and derives a disjoint, isolated key universe by construction
// — see §1 of the spec.)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/wallet/brc42_derive.dart';
import 'package:semantos/src/wallet/derivation_domain.dart';

Uint8List _fromHex(String h) {
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _hex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

void main() {
  group('brain ↔ PWA wallet KAT (operator key unification)', () {
    // Load the committed TS-generated vectors.
    final kat = jsonDecode(
        File('test/wallet/brain_wallet_kat.json').readAsStringSync())
        as Map<String, dynamic>;

    final identityKey = _fromHex(kat['identityKeyHex'] as String);
    final typeHash = _fromHex(kat['typeHashHex'] as String);

    test('change keys match brain deriveChangeSk (priv + pub)', () {
      final vectors = kat['change'] as List;
      expect(vectors, isNotEmpty);
      for (final v in vectors) {
        final m = v as Map<String, dynamic>;
        final index = m['index'] as int;

        // PWA derivation: identity key → change domain, identity-direct.
        // L11.5 kdf-v3: fold the CHANGE flag to match brain deriveChangeSk.
        final sk = deriveSelfChild(
          parentSk: identityKey,
          protocolHash: DerivationDomain.change.protocolHash,
          index: index,
          domainFlag: DerivationDomain.change.domainFlag,
        );
        final pk = publicKeyFromPrivate(sk);

        expect(_hex(sk), m['privHex'],
            reason: 'change priv mismatch at index $index');
        expect(_hex(pk), m['pubHex'],
            reason: 'change pub mismatch at index $index');
      }
    });

    test('anchor keys match brain deriveCellAnchorSk (priv + pub)', () {
      final domain = DerivationDomain.anchor(typeHash);
      final vectors = kat['anchor'] as List;
      expect(vectors, isNotEmpty);
      for (final v in vectors) {
        final m = v as Map<String, dynamic>;
        final index = m['index'] as int;

        // PWA derivation: identity key → anchor(typeHash) domain.
        // L11.5 kdf-v3: fold domainFlagFromTypeHash to match deriveCellAnchorSk.
        final sk = deriveSelfChild(
          parentSk: identityKey,
          protocolHash: domain.protocolHash,
          index: index,
          domainFlag: domain.domainFlag,
        );
        final pk = publicKeyFromPrivate(sk);

        expect(_hex(sk), m['privHex'],
            reason: 'anchor priv mismatch at index $index');
        expect(_hex(pk), m['pubHex'],
            reason: 'anchor pub mismatch at index $index');
      }
    });

    test('protocolHashes byte-match the brain markers', () {
      // change: SHA-256("BRC-42-wallet-change")[0:16] (ecdh42.ts).
      expect(_hex(DerivationDomain.change.protocolHash),
          '795910bd9d715cdd36e4ed64574939fc');
      // anchor: SHA-256(hex(typeHash))[0:16] (cell-anchor.ts), for the
      // KAT's fixed typeHash.
      expect(_hex(DerivationDomain.anchor(typeHash).protocolHash),
          '275a263cd5f344ecf3feb92da67df08f');
    });
  });
}

```
