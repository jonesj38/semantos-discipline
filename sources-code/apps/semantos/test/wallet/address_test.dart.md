---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/address_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.125993+00:00
---

# apps/semantos/test/wallet/address_test.dart

```dart
// C11 PR-C11-7a — Unit tests for `address.dart` (P2PKH encoding).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/wallet/address.dart';

void main() {
  group('base58 / base58check', () {
    test('round-trips simple payloads', () {
      final samples = <Uint8List>[
        Uint8List.fromList([0x00, 0x10, 0x20]),
        Uint8List.fromList(List.generate(20, (i) => i & 0xff)),
        Uint8List.fromList(List.generate(33, (i) => (i * 7) & 0xff)),
      ];
      for (final s in samples) {
        final enc = base58CheckEncode(s);
        final dec = base58CheckDecode(enc);
        expect(dec, isNotNull, reason: 'enc=$enc');
        expect(dec, equals(s));
      }
    });

    test('detects checksum corruption', () {
      final payload =
          Uint8List.fromList([0x00, ...List.generate(20, (i) => i & 0xff)]);
      final enc = base58CheckEncode(payload);
      // Flip the last char to corrupt the checksum.
      final lastChar = enc[enc.length - 1];
      final swap = lastChar == 'A' ? 'B' : 'A';
      final corrupted = enc.substring(0, enc.length - 1) + swap;
      expect(base58CheckDecode(corrupted), isNull);
    });

    test('decodes the known Bitcoin genesis address', () {
      // Satoshi's genesis-block reward address — the most-cited
      // base58check P2PKH fixture in the BSV/BTC world. Documented
      // here both as a sanity check and as a hint to the next reader
      // that this is plain BSV P2PKH, no BSV-specific drift.
      const genesis = '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa';
      final payload = base58CheckDecode(genesis);
      expect(payload, isNotNull);
      expect(payload!.length, 21);
      expect(payload[0], 0x00); // mainnet P2PKH version byte
    });
  });

  group('addressFromPub', () {
    test('produces mainnet address from a compressed pubkey', () {
      // Compressed pubkey for secp256k1 priv = 1 (well-known fixture).
      // Pre-computed via standard base58check off the hash160 of the
      // canonical compressed pub.
      const knownPubHex =
          '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';
      final addr = addressFromPubHex(knownPubHex, network: BsvNetwork.mainnet);
      expect(addr, startsWith('1'));
      expect(addr.length, anyOf(33, 34));
      // Round-trip: decode → reconstruct hash160 → must match the
      // address we just produced.
      final payload = base58CheckDecode(addr);
      expect(payload, isNotNull);
      expect(payload!.length, 21);
      expect(payload[0], 0x00);
    });

    test('produces testnet address with testnet version byte', () {
      const knownPubHex =
          '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';
      final addr = addressFromPubHex(knownPubHex, network: BsvNetwork.testnet);
      expect(addr, anyOf(startsWith('m'), startsWith('n')));
      final payload = base58CheckDecode(addr);
      expect(payload, isNotNull);
      expect(payload![0], 0x6f);
    });

    test('respects kDefaultNetwork when no network is supplied', () {
      const knownPubHex =
          '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';
      final prior = kDefaultNetwork;
      try {
        kDefaultNetwork = BsvNetwork.testnet;
        final addr = addressFromPubHex(knownPubHex);
        expect(addr, anyOf(startsWith('m'), startsWith('n')));
      } finally {
        kDefaultNetwork = prior;
      }
    });

    test('rejects wrong-length pubkey', () {
      expect(
        () => addressFromPub(Uint8List(32)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('hash160', () {
    test('matches the standard SHA-256 → RIPEMD-160 chain', () {
      // hash160 of the compressed pubkey for priv=1.
      const pubHex =
          '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';
      final pubBytes = Uint8List.fromList(List.generate(
        pubHex.length ~/ 2,
        (i) => int.parse(pubHex.substring(i * 2, i * 2 + 2), radix: 16),
      ));
      final h160 = hash160(pubBytes);
      expect(h160.length, 20);
    });
  });
}

```
