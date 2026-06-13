---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/identity/secure_signing_key_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.914483+00:00
---

# archive/apps-semantos-monolith/test/identity/secure_signing_key_test.dart

```dart
// D-O5m.followup-2 — InMemorySecureSigningKeyAdapter happy paths.
//
// These tests cover the pure-Dart adapter (the one tests + the
// Dart-test-suite fallback use).  The platform adapter
// (PlatformSecureSigningKeyAdapter) is exercised manually on a
// device + simulator per the runbook — it requires a Flutter SDK
// gate + MethodChannel binding that this pure-`dart test` suite
// does NOT have.
//
// What's asserted:
//   1. generateNew produces a 33-byte compressed pub + a non-empty
//      handle.
//   2. sign produces a 64-byte (r||s) signature whose verify against
//      the returned pub succeeds (round-trip via cell_signer's
//      verifyCellSignature).
//   3. exists returns true after generate, false after delete.
//   4. delete is idempotent — calling it twice doesn't throw.
//   5. sign on a missing handle throws SecureSigningKeyNotFound.
//   6. seedHandles constructor lets a test pre-load a handle ↔ priv
//      mapping (used by the migration test fixture).

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:semantos/src/identity/cell_signer.dart';
import 'package:semantos/src/identity/secure_signing_key.dart';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  group('InMemorySecureSigningKeyAdapter', () {
    test('generateNew produces a non-empty handle + 33-byte compressed pub',
        () async {
      final adapter = InMemorySecureSigningKeyAdapter();
      final material = await adapter.generateNew(label: 'phone-A');
      expect(material.keyHandle, isNotEmpty);
      expect(material.publicKey.length, equals(33));
      // SEC1 compressed prefix: 0x02 (even y) or 0x03 (odd y).
      expect(material.publicKey[0], anyOf(equals(0x02), equals(0x03)));
      expect(material.generatedAt, isA<DateTime>());
    });

    test('sign + verifyCellSignature round-trip succeeds', () async {
      final adapter = InMemorySecureSigningKeyAdapter();
      final material = await adapter.generateNew(label: 'phone-B');
      final payload = utf8.encode('arbitrary cell payload bytes');

      final sig = await adapter.sign(
        keyHandle: material.keyHandle,
        message: Uint8List.fromList(payload),
      );

      expect(sig.length, equals(64));
      // Round-trip through the canonical Dart verifier — the
      // adapter MUST produce a signature shape the brain accepts.
      expect(
        verifyCellSignature(
            Uint8List.fromList(payload), sig, material.publicKey),
        isTrue,
        reason: 'InMemoryAdapter sign output must round-trip via '
            'verifyCellSignature so the brain accepts it.',
      );
    });

    test('sign on a missing handle throws SecureSigningKeyNotFound',
        () async {
      final adapter = InMemorySecureSigningKeyAdapter();
      await expectLater(
        () => adapter.sign(
          keyHandle: 'no-such-handle',
          message: Uint8List.fromList(utf8.encode('x')),
        ),
        throwsA(isA<SecureSigningKeyNotFound>()),
      );
    });

    test('exists / delete lifecycle', () async {
      final adapter = InMemorySecureSigningKeyAdapter();
      final material = await adapter.generateNew(label: 'phone-C');
      expect(await adapter.exists(keyHandle: material.keyHandle), isTrue);
      await adapter.delete(keyHandle: material.keyHandle);
      expect(await adapter.exists(keyHandle: material.keyHandle), isFalse);
      // Idempotent — second delete must not throw.
      await adapter.delete(keyHandle: material.keyHandle);
      expect(await adapter.exists(keyHandle: material.keyHandle), isFalse);
    });

    test('seedHandles pre-loads a handle ↔ priv mapping', () async {
      // The migration test fixture seeds a handle that maps to a
      // pinned priv so the resulting pub is reproducible.
      final priv = _hex(
          'a1b2c3d4e5f600112233445566778899aabbccddeeff00112233445566778899');
      final adapter = InMemorySecureSigningKeyAdapter(
        seedHandles: {'pinned-handle': priv},
      );
      expect(await adapter.exists(keyHandle: 'pinned-handle'), isTrue);
      // The signature over a known message must verify against the
      // pub derived from the seeded priv — proves the seeded handle
      // really maps to that priv.
      final pub = devicePubFromPriv(priv);
      final sig = await adapter.sign(
        keyHandle: 'pinned-handle',
        message: Uint8List.fromList(utf8.encode('hello')),
      );
      expect(
        verifyCellSignature(
            Uint8List.fromList(utf8.encode('hello')), sig, pub),
        isTrue,
      );
    });

    test('generated handles are unique across generateNew calls', () async {
      final adapter = InMemorySecureSigningKeyAdapter();
      final a = await adapter.generateNew(label: 'phone-A');
      final b = await adapter.generateNew(label: 'phone-B');
      expect(a.keyHandle, isNot(equals(b.keyHandle)));
      expect(a.publicKey, isNot(equals(b.publicKey)));
      // Each can be signed independently.
      final sa = await adapter.sign(
          keyHandle: a.keyHandle,
          message: Uint8List.fromList(utf8.encode('m')));
      final sb = await adapter.sign(
          keyHandle: b.keyHandle,
          message: Uint8List.fromList(utf8.encode('m')));
      expect(sa, isNot(equals(sb)));
    });

    test('testReadLabel surfaces the operator-supplied label', () async {
      final adapter = InMemorySecureSigningKeyAdapter();
      final material = await adapter.generateNew(label: 'kitchen-tablet');
      expect(adapter.testReadLabel(material.keyHandle), equals('kitchen-tablet'));
      expect(adapter.testReadLabel('no-such-handle'), isNull);
    });
  });

  group('CellSigner (adapter-routed)', () {
    test('signCanonicalCellPayload routes through the supplied adapter',
        () async {
      final adapter = InMemorySecureSigningKeyAdapter();
      final material = await adapter.generateNew(label: 'phone-D');
      final signer = CellSigner(
        adapter: adapter,
        keyHandle: material.keyHandle,
      );
      final payload = Uint8List.fromList(utf8.encode('canonical preimage'));
      final sig = await signer.signCanonicalCellPayload(payload);
      expect(sig.length, equals(64));
      expect(verifyCellSignature(payload, sig, material.publicKey), isTrue);
      expect(signer.debugKeyHandle, equals(material.keyHandle));
    });

    test(
        'signCanonicalCellPayload throws StateError when adapter returns wrong-size sig',
        () async {
      final adapter = _BadSizeAdapter();
      final signer =
          CellSigner(adapter: adapter, keyHandle: 'whatever');
      await expectLater(
        () => signer.signCanonicalCellPayload(
            Uint8List.fromList(utf8.encode('x'))),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// Test double — returns a 32-byte (wrong-size) signature so the
/// CellSigner wrapper's defensive check fires.
class _BadSizeAdapter implements SecureSigningKeyAdapter {
  @override
  Future<SecureKeyMaterial> generateNew({required String label}) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> sign({
    required String keyHandle,
    required Uint8List message,
  }) async =>
      Uint8List(32);

  @override
  Future<void> delete({required String keyHandle}) async {}

  @override
  Future<bool> exists({required String keyHandle}) async => false;
}

```
