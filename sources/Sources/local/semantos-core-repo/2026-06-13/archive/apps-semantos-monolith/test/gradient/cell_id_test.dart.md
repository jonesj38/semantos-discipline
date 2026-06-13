---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/gradient/cell_id_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.916945+00:00
---

# archive/apps-semantos-monolith/test/gradient/cell_id_test.dart

```dart
// 2026-05-07 — pins the format of `deriveCellId` so the Semantos Brain-side
// validator (which accepts the phone's id verbatim) can rely on the
// shape `cell-<sizeHex(6)>-<bytePrefix(8 hex)>-<uuidTail(8)>`.
//
// Cross-language parity is covered by the cross-lang fixture test
// (intent_cell_envelope_fixture.json) loaded in
// `production_pipeline_deps_test.dart`; this file pins pure-Dart
// behaviour.

import 'dart:typed_data';

import 'package:semantos/src/gradient/cell_id.dart';
import 'package:test/test.dart';

void main() {
  group('deriveCellId', () {
    test('renders sizeHex padded to 6 chars', () {
      final id = deriveCellId(
        Uint8List.fromList([1, 2, 3, 4]),
        () => '00000000-0000-0000-0000-deadbeefcafe',
      );
      expect(id.startsWith('cell-000004-'), isTrue, reason: id);
    });

    test('byte-prefix takes the first four bytes lower-case hex', () {
      final id = deriveCellId(
        Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x99, 0x99]),
        () => 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );
      expect(id, equals('cell-000006-deadbeef-eeeeeeee'),
          reason: 'sizeHex=6, prefix=deadbeef, uuidTail=last 8 of stripped');
    });

    test('zero-pads byte-prefix when bytes are shorter than 4', () {
      final id = deriveCellId(
        Uint8List.fromList([0xAB, 0xCD]),
        () => '11111111-2222-3333-4444-555555555555',
      );
      expect(id.split('-')[2], equals('abcd0000'),
          reason: 'underflow zeros — defensive');
    });

    test('handles empty opcode bytes (defensive)', () {
      final id = deriveCellId(
        Uint8List(0),
        () => '00000000-0000-0000-0000-000000000001',
      );
      expect(id, equals('cell-000000-00000000-00000001'));
    });

    test('uuid tail is lower-cased + dash-stripped', () {
      final id = deriveCellId(
        Uint8List.fromList([0]),
        () => 'AABBCCDD-EEFF-1122-3344-5566778899AA',
      );
      // Last 8 chars of "AABBCCDDEEFF11223344556677889900AA" lower-cased.
      // "AABBCCDDEEFF1122334455667788AA" stripped = "AABBCCDDEEFF11223344556677889900AA"
      // … with the actual uuid we passed:
      // stripped = "AABBCCDDEEFF11223344556677889900AA"  - wait, that's wrong.
      // Real strip of "AABBCCDD-EEFF-1122-3344-5566778899AA":
      // = "AABBCCDDEEFF11223344556677889900AA" -- let me trace.
      // dashes removed: "AABBCCDDEEFF11223344556677889900AA" - WAIT
      // input is "AABBCCDD-EEFF-1122-3344-5566778899AA" - 36 chars including dashes
      // dashes removed: "AABBCCDDEEFF112233445566778899AA" (32 chars)
      // last 8 lower: "778899aa"
      expect(id.split('-')[3], equals('778899aa'));
    });

    test('different bytes produce different ids (same uuid)', () {
      String fixedUuid() => '11111111-2222-3333-4444-555555555555';
      final a = deriveCellId(Uint8List.fromList([1, 2, 3, 4]), fixedUuid);
      final b = deriveCellId(Uint8List.fromList([5, 6, 7, 8]), fixedUuid);
      expect(a, isNot(equals(b)));
    });
  });
}

```
