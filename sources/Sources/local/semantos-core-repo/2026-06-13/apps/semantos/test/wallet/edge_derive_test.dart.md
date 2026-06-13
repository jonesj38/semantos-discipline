---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/edge_derive_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.126577+00:00
---

# apps/semantos/test/wallet/edge_derive_test.dart

```dart
// C11 PR-C11-7b — Unit tests for `edge_derive.dart`.
//
// The single most important property: sender's `deriveEdgePub` (resp.
// `deriveBrc29ChildPub`) must equal the public key of the recipient's
// `deriveEdgeSk` (resp. `deriveBrc29ChildSk`). Without that, the
// recipient cannot spend what the sender addressed to them — the
// whole BRC-29 protocol breaks. These tests pin it down across
// random scalars + multiple indices + multiple invoice shapes.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/wallet/brc42_derive.dart' show publicKeyFromPrivate;
import 'package:semantos/src/wallet/edge_derive.dart';

Uint8List _sk(int seed) {
  // Avoid the zero scalar; offset by 1 so seed=0 still yields a
  // valid secp256k1 priv.
  return Uint8List.fromList(
      List<int>.generate(32, (i) => ((i * 17 + seed + 1) & 0xff)));
}

void main() {
  group('edge BRC-42 (binary 24-byte invoice — ecdh42 EDGE domain)', () {
    test('sender pub == pubkey(recipient sk)', () {
      final aliceSk = _sk(3);
      final bobSk = _sk(7);
      final alicePub = publicKeyFromPrivate(aliceSk);
      final bobPub = publicKeyFromPrivate(bobSk);

      for (final index in <int>[0, 1, 5, 42, 1234]) {
        final senderDerived = deriveEdgePub(
          senderSk: aliceSk,
          recipientPub: bobPub,
          signingKeyIndex: index,
        );
        final recipientSk = deriveEdgeSk(
          recipientSk: bobSk,
          senderPub: alicePub,
          signingKeyIndex: index,
        );
        final recipientPub = publicKeyFromPrivate(recipientSk);
        expect(senderDerived, equals(recipientPub),
            reason: 'index=$index broke edge symmetry');
      }
    });

    test('different indices produce different keys', () {
      final aliceSk = _sk(11);
      final bobPub = publicKeyFromPrivate(_sk(13));
      final p0 = deriveEdgePub(
          senderSk: aliceSk, recipientPub: bobPub, signingKeyIndex: 0);
      final p1 = deriveEdgePub(
          senderSk: aliceSk, recipientPub: bobPub, signingKeyIndex: 1);
      expect(p0, isNot(equals(p1)));
    });

    test('different counterparties produce different keys', () {
      final aliceSk = _sk(21);
      final bobPub = publicKeyFromPrivate(_sk(22));
      final carolPub = publicKeyFromPrivate(_sk(23));
      final pBob = deriveEdgePub(
          senderSk: aliceSk, recipientPub: bobPub, signingKeyIndex: 0);
      final pCarol = deriveEdgePub(
          senderSk: aliceSk, recipientPub: carolPub, signingKeyIndex: 0);
      expect(pBob, isNot(equals(pCarol)));
    });
  });

  group('BRC-29 text invoice', () {
    test('invoice string matches the spec format', () {
      final s = brc29InvoiceString(
          derivationPrefix: 'pay-prefix-1', derivationSuffix: 'out-7');
      expect(s, '2-3241645161d8-pay-prefix-1 out-7');
    });

    test('sender pub == pubkey(recipient sk)', () {
      final senderSk = _sk(101);
      final recipientSk = _sk(202);
      final senderPub = publicKeyFromPrivate(senderSk);
      final recipientPub = publicKeyFromPrivate(recipientSk);

      const cases = [
        ('alpha', 'beta'),
        ('long-prefix-with-numbers-123', 'suffix.42'),
        ('UPPER_case', 'lowercase'),
      ];
      for (final (prefix, suffix) in cases) {
        final senderDerived = deriveBrc29ChildPub(
          senderSk: senderSk,
          recipientPub: recipientPub,
          derivationPrefix: prefix,
          derivationSuffix: suffix,
        );
        final recipientChildSk = deriveBrc29ChildSk(
          recipientSk: recipientSk,
          senderPub: senderPub,
          derivationPrefix: prefix,
          derivationSuffix: suffix,
        );
        final recipientChildPub = publicKeyFromPrivate(recipientChildSk);
        expect(senderDerived, equals(recipientChildPub),
            reason: 'symmetry failed for ($prefix, $suffix)');
      }
    });

    test('recoverBrc29ChildPub matches deriveBrc29ChildPub', () {
      final senderSk = _sk(50);
      final recipientSk = _sk(60);
      final senderPub = publicKeyFromPrivate(senderSk);
      final recipientPub = publicKeyFromPrivate(recipientSk);

      final senderDerived = deriveBrc29ChildPub(
        senderSk: senderSk,
        recipientPub: recipientPub,
        derivationPrefix: 'p',
        derivationSuffix: 's',
      );
      final recovered = recoverBrc29ChildPub(
        recipientSk: recipientSk,
        senderPub: senderPub,
        derivationPrefix: 'p',
        derivationSuffix: 's',
      );
      expect(recovered, equals(senderDerived));
    });

    test('different suffixes yield different child pubs', () {
      final senderSk = _sk(31);
      final recipientPub = publicKeyFromPrivate(_sk(32));
      final a = deriveBrc29ChildPub(
        senderSk: senderSk,
        recipientPub: recipientPub,
        derivationPrefix: 'pay-1',
        derivationSuffix: 'out-0',
      );
      final b = deriveBrc29ChildPub(
        senderSk: senderSk,
        recipientPub: recipientPub,
        derivationPrefix: 'pay-1',
        derivationSuffix: 'out-1',
      );
      expect(a, isNot(equals(b)));
    });

    test('different prefixes yield different child pubs', () {
      final senderSk = _sk(33);
      final recipientPub = publicKeyFromPrivate(_sk(34));
      final a = deriveBrc29ChildPub(
        senderSk: senderSk,
        recipientPub: recipientPub,
        derivationPrefix: 'pay-1',
        derivationSuffix: 'out-0',
      );
      final b = deriveBrc29ChildPub(
        senderSk: senderSk,
        recipientPub: recipientPub,
        derivationPrefix: 'pay-2',
        derivationSuffix: 'out-0',
      );
      expect(a, isNot(equals(b)));
    });

    test('rejects empty prefix or suffix', () {
      expect(
        () => brc29InvoiceString(derivationPrefix: '', derivationSuffix: 's'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => brc29InvoiceString(derivationPrefix: 'p', derivationSuffix: ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('arg validation', () {
    test('rejects wrong-length priv / pub / tweak', () {
      expect(
        () => computeBrc42Tweak(
          mySk: Uint8List(31),
          theirPub: publicKeyFromPrivate(_sk(1)),
          invoiceBytes: Uint8List(24),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => computeBrc42Tweak(
          mySk: _sk(1),
          theirPub: Uint8List(32),
          invoiceBytes: Uint8List(24),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => applyTweakToPrivate(_sk(1), Uint8List(31)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects zero scalar', () {
      expect(
        () => computeBrc42Tweak(
          mySk: Uint8List(32),
          theirPub: publicKeyFromPrivate(_sk(1)),
          invoiceBytes: Uint8List(24),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

```
