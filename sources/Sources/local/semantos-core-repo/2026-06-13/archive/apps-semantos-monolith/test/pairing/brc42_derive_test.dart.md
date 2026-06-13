---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/pairing/brc42_derive_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.906467+00:00
---

# archive/apps-semantos-monolith/test/pairing/brc42_derive_test.dart

```dart
// D-O5m — Cross-language BRC-42 parity test.
//
// LOAD-BEARING — this is the strongest correctness proof we have for
// the Dart pairing port. Loads the canonical fixture at
// `test/fixtures/device-pair-v2-fixture.json` (mirror of
// `extensions/oddjobz/tests/vectors/device-pair/v2-fixture.json`)
// and asserts:
//
//   1. buildBrc42Invoice(contextTag, label) produces the exact bytes
//      `invoiceHex` from the fixture.
//   2. deriveChildKeyMaterial(devicePriv, operatorRootPub, ...)
//      produces a `childPubKeyHex` byte-identical to the fixture's
//      `childPubKeyHex` (which was produced by the Zig + TS sides).
//
// If this test fails, the Dart port is wrong — fix the port; do not
// dilute the test.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:semantos/src/pairing/brc42_derive.dart';

void main() {
  group('BRC-42 child derivation — cross-language parity', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final raw =
          File('test/fixtures/device-pair-v2-fixture.json').readAsStringSync();
      fixture = json.decode(raw) as Map<String, dynamic>;
    });

    test('buildBrc42Invoice matches the fixture invoiceHex byte-for-byte',
        () {
      final payload = fixture['payload'] as Map<String, dynamic>;
      final contextTag = payload['contextTag'] as int;
      final label = payload['label'] as String;

      final invoiceBytes = buildBrc42Invoice(contextTag, label);
      final invoiceHex = _bytesToHex(invoiceBytes);

      expect(invoiceHex, equals(fixture['invoiceHex']));
    });

    test('deriveChildKeyMaterial produces the fixture childPubKeyHex', () {
      final operator = fixture['operator'] as Map<String, dynamic>;
      final device = fixture['device'] as Map<String, dynamic>;
      final payload = fixture['payload'] as Map<String, dynamic>;

      final derived = deriveChildKeyMaterial(
        devicePrivKeyHex: device['privHex'] as String,
        operatorRootPubKeyHex: operator['pubHex'] as String,
        contextTag: payload['contextTag'] as int,
        label: payload['label'] as String,
      );

      // Cross-language parity assertion.
      expect(derived.childPubKeyHex, equals(fixture['childPubKeyHex']));
      // The device pub the brain stores as `derivation_proof` —
      // matches the fixture's pinned device pub.
      expect(derived.devicePubKeyHex, equals(device['pubHex']));
    });

    test('rejects out-of-range contextTag', () {
      expect(
        () => buildBrc42Invoice(-1, 'x'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => buildBrc42Invoice(256, 'x'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects malformed operator pub hex', () {
      expect(
        () => deriveChildKeyMaterial(
          devicePrivKeyHex: '01' * 32,
          operatorRootPubKeyHex: 'too-short',
          contextTag: 16,
          label: 'x',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

String _bytesToHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

```
