---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/dispatch/payload_canonical_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.129614+00:00
---

# apps/semantos/test/dispatch/payload_canonical_test.dart

```dart
// Parity tests for the Dart canonicaliser — it MUST agree byte-for-byte
// with the brain's `canonicaliseCellPayload` (sorted-key compact JSON), or
// sovereign mints 401. Expected strings here are hand-derived from the Zig
// canonicaliser's rules (see payload_canonical.dart header).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/dispatch/payload_canonical.dart';

void main() {
  group('canonicaliseCellPayload', () {
    test('V1 release slice payload — single ASCII string field', () {
      const payload = {
        'rawText': "I'm letting go of the pressure to make every interaction perfect.",
      };
      // Apostrophe is NOT escaped in JSON; single key ⇒ trivial order.
      expect(
        canonicalCellPayloadString(payload),
        equals(
          '{"rawText":"I\'m letting go of the pressure to make every interaction perfect."}',
        ),
      );
    });

    test('object keys are sorted by byte order, no whitespace', () {
      expect(
        canonicalCellPayloadString({'b': 1, 'a': 'x', 'c': true}),
        equals('{"a":"x","b":1,"c":true}'),
      );
      // Uppercase sorts before lowercase (ASCII 'A'=65 < 'a'=97).
      expect(
        canonicalCellPayloadString({'a': 1, 'A': 2}),
        equals('{"A":2,"a":1}'),
      );
    });

    test('nested objects + arrays canonicalise recursively', () {
      expect(
        canonicalCellPayloadString({
          'z': {'y': 2, 'x': 1},
          'arr': [3, 'two', false, null],
        }),
        equals('{"arr":[3,"two",false,null],"z":{"x":1,"y":2}}'),
      );
    });

    test('string escaping matches JSON (quote, backslash, control)', () {
      expect(
        canonicalCellPayloadString({'k': 'a"b\\c\n'}),
        equals('{"k":"a\\"b\\\\c\\n"}'),
      );
    });

    test('integral doubles render without a trailing .0', () {
      // 5.0 → "5" (Zig {d}); 5 (int) → "5". Both must agree.
      expect(canonicalCellPayloadString({'n': 5.0}), equals('{"n":5}'));
      expect(canonicalCellPayloadString({'n': 5}), equals('{"n":5}'));
    });

    test('canonical bytes are valid UTF-8 of the canonical string', () {
      const payload = {'rawText': 'héllo'};
      final bytes = canonicaliseCellPayload(payload);
      expect(utf8.decode(bytes), equals(canonicalCellPayloadString(payload)));
    });
  });
}

```
