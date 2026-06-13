---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/cert_body_store_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.127415+00:00
---

# apps/semantos/test/wallet/cert_body_store_test.dart

```dart
// C11 PR-C11-4c — Unit tests for `cert_body_store.dart`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:semantos/src/wallet/cert_body_store.dart';

void main() {
  group('CertBodyStore', () {
    const certIdHex = '06d0a049e88a982b0000000000000000';

    late SecureStore store;
    late CertBodyStore certBody;

    setUp(() {
      store = InMemorySecureStore();
      certBody = CertBodyStore(certIdHex: certIdHex, store: store);
    });

    test('isPresent → false when empty', () async {
      expect(await certBody.isPresent(), isFalse);
      expect(await certBody.read(), isNull);
    });

    test('write + read round-trip', () async {
      final body = Uint8List.fromList(
          List<int>.generate(32, (i) => (i * 17 + 3) & 0xff));
      await certBody.write(body);
      expect(await certBody.isPresent(), isTrue);
      final read = await certBody.read();
      expect(read, equals(body));
    });

    test('storageKey is namespaced and certId-scoped', () {
      expect(certBody.storageKey, 'me.cert_body.v1.$certIdHex');
    });

    test('different identities do not collide', () async {
      final other = CertBodyStore(
        certIdHex: 'aa11bb22cc33dd44ee55ff66aa77bb88',
        store: store,
      );
      final bodyA = Uint8List.fromList(List<int>.filled(32, 1));
      final bodyB = Uint8List.fromList(List<int>.filled(32, 2));
      await certBody.write(bodyA);
      await other.write(bodyB);
      expect(await certBody.read(), equals(bodyA));
      expect(await other.read(), equals(bodyB));
    });

    test('clear removes the slot', () async {
      await certBody.write(Uint8List.fromList(List<int>.filled(32, 9)));
      await certBody.clear();
      expect(await certBody.isPresent(), isFalse);
    });

    test('rejects wrong-length body', () {
      expect(
        () => certBody.write(Uint8List(31)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects malformed certId at construction', () {
      expect(
        () => CertBodyStore(certIdHex: 'too-short', store: store),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CertBodyStore(
            certIdHex: 'zz000000000000000000000000000000', store: store),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

```
