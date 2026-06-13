---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/headers_client_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.124294+00:00
---

# apps/semantos/test/wallet/headers_client_test.dart

```dart
// C11 PR-C11-7b — Unit tests for `headers_client.dart`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/sha256.dart';

import 'package:semantos/src/wallet/headers_client.dart';

BlockHeader _fakeHeader(int height, int seed) {
  final bytes = Uint8List(80);
  for (var i = 0; i < 80; i++) {
    bytes[i] = (i + seed * 7 + height * 13) & 0xff;
  }
  return BlockHeader(
    bytes: bytes,
    blockHashHex: displayHashOf(bytes),
    height: height,
  );
}

Uint8List _doubleSha256(Uint8List input) =>
    SHA256Digest().process(SHA256Digest().process(input));

void main() {
  group('InMemoryHeadersClient', () {
    test('put + getByHeight round-trips', () async {
      final c = InMemoryHeadersClient();
      final h = _fakeHeader(100, 1);
      c.put(h);
      final read = await c.getByHeight(100);
      expect(read.height, 100);
      expect(read.bytes, equals(h.bytes));
    });

    test('put + getByHash round-trips', () async {
      final c = InMemoryHeadersClient();
      final h = _fakeHeader(200, 2);
      c.put(h);
      final read = await c.getByHash(h.blockHashHex);
      expect(read, isNotNull);
      expect(read!.height, 200);
    });

    test('getByHash returns null for unknown hash', () async {
      final c = InMemoryHeadersClient();
      c.put(_fakeHeader(300, 3));
      final read = await c.getByHash('00' * 32);
      expect(read, isNull);
    });

    test('getTip returns highest-height header', () async {
      final c = InMemoryHeadersClient();
      c.put(_fakeHeader(10, 1));
      c.put(_fakeHeader(50, 2));
      c.put(_fakeHeader(30, 3));
      final tip = await c.getTip();
      expect(tip.height, 50);
    });

    test('explicit setTip overrides the auto-promoted tip', () async {
      final c = InMemoryHeadersClient();
      c.put(_fakeHeader(10, 1));
      c.put(_fakeHeader(50, 2));
      final far = _fakeHeader(1000, 99);
      c.setTip(far);
      final tip = await c.getTip();
      expect(tip.height, 1000);
    });

    test('getTip throws when no tip is set', () async {
      final c = InMemoryHeadersClient();
      expect(() => c.getTip(), throwsA(isA<HeadersClientException>()));
    });

    test('getByHeight throws on unknown height', () async {
      final c = InMemoryHeadersClient();
      expect(
        () => c.getByHeight(42),
        throwsA(isA<HeadersClientException>()),
      );
    });

    test('rejects malformed block-hash queries', () async {
      final c = InMemoryHeadersClient();
      expect(() => c.getByHash('not-hex'), throwsA(isA<ArgumentError>()));
      expect(() => c.getByHash('aa' * 30), throwsA(isA<ArgumentError>()));
    });
  });

  group('displayHashOf', () {
    test('produces 64-char lowercase hex', () {
      final bytes = Uint8List(80);
      for (var i = 0; i < 80; i++) {
        bytes[i] = i & 0xff;
      }
      final hex = displayHashOf(bytes);
      expect(hex.length, 64);
      expect(hex, equals(hex.toLowerCase()));
    });

    test('differs for different headers', () {
      final a = Uint8List(80);
      final b = Uint8List(80);
      b[0] = 1;
      expect(displayHashOf(a), isNot(equals(displayHashOf(b))));
    });

    test('reverses the double-sha256 (BSV display order)', () {
      // The last byte of sha256(sha256(input)) is the first byte of
      // the display hex (BSV byte-reverse-on-display convention).
      final bytes = Uint8List(80);
      final inner = _doubleSha256(bytes);
      final hex = displayHashOf(bytes);
      final lastByte = inner[inner.length - 1];
      expect(hex.substring(0, 2),
          equals(lastByte.toRadixString(16).padLeft(2, '0')));
    });
  });
}

```
