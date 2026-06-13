---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/brc42_derive_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.127687+00:00
---

# apps/semantos/test/wallet/brc42_derive_test.dart

```dart
// C11 PR-C11-4c — Unit tests for `brc42_derive.dart`.
//
// Internal-consistency tests only (round-trip determinism,
// arg-validation, non-collision, scalar normalisation). Cross-host
// parity with the TS `ecdh42.ts` change-domain is planned for the
// 4e bridge PR where corrupt parity would touch real signatures.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/wallet/brc42_derive.dart';
import 'package:semantos/src/wallet/derivation_domain.dart';

void main() {
  group('deriveSelfChild', () {
    final aliceSk = Uint8List.fromList(List<int>.filled(32, 0)..[31] = 3);
    final bobSk = Uint8List.fromList(List<int>.filled(32, 0)..[31] = 7);

    test('returns 32 bytes', () {
      final out = deriveSelfChild(
        parentSk: aliceSk,
        protocolHash: DerivationDomain.tier0.protocolHash,
        index: 0,
      );
      expect(out.length, 32);
    });

    test('is deterministic', () {
      final a = deriveSelfChild(
        parentSk: aliceSk,
        protocolHash: DerivationDomain.tier0.protocolHash,
        index: 0,
      );
      final b = deriveSelfChild(
        parentSk: aliceSk,
        protocolHash: DerivationDomain.tier0.protocolHash,
        index: 0,
      );
      expect(a, equals(b));
    });

    test('different indices yield different children', () {
      final h = DerivationDomain.change.protocolHash;
      final a = deriveSelfChild(parentSk: aliceSk, protocolHash: h, index: 0);
      final b = deriveSelfChild(parentSk: aliceSk, protocolHash: h, index: 1);
      final c = deriveSelfChild(parentSk: aliceSk, protocolHash: h, index: 47);
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
      expect(b, isNot(equals(c)));
    });

    test('different domains at the same index yield different children', () {
      final tier0 = deriveSelfChild(
        parentSk: aliceSk,
        protocolHash: DerivationDomain.tier0.protocolHash,
        index: 0,
      );
      final change = deriveSelfChild(
        parentSk: aliceSk,
        protocolHash: DerivationDomain.change.protocolHash,
        index: 0,
      );
      final spend = deriveSelfChild(
        parentSk: aliceSk,
        protocolHash: DerivationDomain.spend('oddjobz/payout').protocolHash,
        index: 0,
      );
      expect(tier0, isNot(equals(change)));
      expect(tier0, isNot(equals(spend)));
      expect(change, isNot(equals(spend)));
    });

    test('different parents yield different children', () {
      final h = DerivationDomain.tier0.protocolHash;
      final a = deriveSelfChild(parentSk: aliceSk, protocolHash: h, index: 0);
      final b = deriveSelfChild(parentSk: bobSk, protocolHash: h, index: 0);
      expect(a, isNot(equals(b)));
    });

    test('rejects wrong-length parentSk', () {
      expect(
        () => deriveSelfChild(
          parentSk: Uint8List(31),
          protocolHash: DerivationDomain.tier0.protocolHash,
          index: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects wrong-length protocolHash', () {
      expect(
        () => deriveSelfChild(
          parentSk: aliceSk,
          protocolHash: Uint8List(15),
          index: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects negative index', () {
      expect(
        () => deriveSelfChild(
          parentSk: aliceSk,
          protocolHash: DerivationDomain.tier0.protocolHash,
          index: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects zero scalar', () {
      expect(
        () => deriveSelfChild(
          parentSk: Uint8List(32),
          protocolHash: DerivationDomain.tier0.protocolHash,
          index: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('publicKeyFromPrivate', () {
    test('returns 33-byte compressed pubkey', () {
      final sk = Uint8List.fromList(List<int>.filled(32, 0)..[31] = 5);
      final pub = publicKeyFromPrivate(sk);
      expect(pub.length, 33);
      expect(pub[0], anyOf(0x02, 0x03));
    });

    test('rejects wrong-length input', () {
      expect(
        () => publicKeyFromPrivate(Uint8List(31)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

```
