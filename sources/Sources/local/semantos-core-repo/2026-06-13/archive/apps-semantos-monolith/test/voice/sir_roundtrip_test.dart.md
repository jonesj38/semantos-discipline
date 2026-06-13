---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/voice/sir_roundtrip_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.909848+00:00
---

# archive/apps-semantos-monolith/test/voice/sir_roundtrip_test.dart

```dart
// D-O5m.followup-3 Phase 2 — cross-language SIR roundtrip parity.
//
// Reference: runtime/intent/scripts/gen-sir-roundtrip-fixture.ts
//            (the fixture generator);
//            runtime/intent/src/__tests__/sir-roundtrip-fixture.test.ts
//            (the TS-side parity test);
//            apps/oddjobz-mobile/lib/src/voice/sir_extractor.dart
//            (the unit under test for the Dart side).
//
// Asserts that the Dart-side canonicaliseIntent + encodeCanonical
// Intent emit byte-identical JSON to the TS reference encoder.  This
// is what makes the on-device extractor's wire output structurally
// indistinguishable from a brain-side built Intent at the bytes
// level -- the brain's L1 validator can't tell which side produced
// the SIR, only that it's well-formed.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:semantos/src/voice/sir_extractor.dart';

void main() {
  group('SIR roundtrip fixture (Dart parity with TS reference)', () {
    final fixtureFile = File(
      'test/fixtures/sir-roundtrip-fixture.json',
    );
    final fixture = json.decode(fixtureFile.readAsStringSync())
        as Map<String, dynamic>;

    test('canonicalIntentJson reproduces from expectedIntent on Dart side',
        () {
      final expected = fixture['expectedIntent'] as Map<String, dynamic>;
      final canonicalJson = fixture['canonicalIntentJson'] as String;
      final got = encodeCanonicalIntent(expected);
      expect(got, equals(canonicalJson));
    });

    test('canonicaliseIntent preserves key order across (Dart, TS)', () {
      final expected = fixture['expectedIntent'] as Map<String, dynamic>;
      final dartCanonical = canonicaliseIntent(expected);
      final declaredOrder = (fixture['canonicalKeyOrder'] as List)
          .map((e) => e as String)
          .toList();
      expect(dartCanonical.keys.toList(), equals(declaredOrder));
    });

    test('null fields are dropped from the canonicalised output', () {
      final input = <String, dynamic>{
        'id': 'i-001',
        'correlationId': null, // should drop
        'summary': 'x',
        'category': {'lexicon': 'trades', 'category': 'invoice'},
        'taxonomy': {'what': 'a', 'how': 'b', 'why': 'c'},
        'action': 'invoice',
        'constraints': const [],
        'target': null, // should drop
        'confidence': 0.9,
        'source': 'voice',
      };
      final out = canonicaliseIntent(input);
      expect(out.containsKey('correlationId'), isFalse);
      expect(out.containsKey('target'), isFalse);
      expect(out['id'], equals('i-001'));
    });
  });
}

```
