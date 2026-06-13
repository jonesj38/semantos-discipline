---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/self/self_type_hash_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.911029+00:00
---

# archive/apps-semantos-monolith/test/self/self_type_hash_test.dart

```dart
// BRAIN-GENERIC-MINT-VERB M4 — cross-language buildTypeHash parity.
//
// Pinned vectors mirror what the Zig kernel
// (core/cell-engine/src/type_hash.zig::buildTypeHash) and the TS mirror
// (core/protocol-types/src/type-hash.ts) produce for the same triples.
// Drift between any of the three implementations would break the live
// mint round-trip: the Flutter shell would compute one typeHash, the
// brain would expect another, and the registry lookup would 404.
//
// Vectors generated via:
//   python3 -c "
//   import hashlib
//   def b(*s): return b''.join(hashlib.sha256(x.encode()).digest()[:8] for x in s).hex()
//   print(b('self','practice','release',''))
//   ..."
//
// Also asserts the routing-prefix property from the typehash-canonical
// decision record §7.2: every typeHash whose first segment is 'self'
// shares the same `bytes[0:8]` prefix.  That's the property relays use
// for O(1) namespace filtering — if it breaks, the routing optimisation
// is silently lost.

import 'package:test/test.dart';
import 'package:semantos/src/self/self_type_hash.dart';

void main() {
  group('buildTypeHash — parity with Zig kernel', () {
    test('self.practice.release matches pinned vector', () {
      final got = typeHashHex(
        buildTypeHash('self', 'practice', 'release', ''),
      );
      expect(
        got,
        equals(
          '06c604b332b386b6ada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14',
        ),
      );
    });

    test('self.paskian.graph.node matches pinned vector', () {
      final got = typeHashHex(
        buildTypeHash('self', 'paskian', 'graph', 'node'),
      );
      expect(
        got,
        equals(
          '06c604b332b386b623a58f8728c6cf6feef93e1d14482804545ea538461003ef',
        ),
      );
    });

    test('self.story.thread matches pinned vector', () {
      final got =
          typeHashHex(buildTypeHash('self', 'story', 'thread', ''));
      expect(
        got,
        equals(
          '06c604b332b386b6c478361e6869af2539200d1e8a8dbbb6e3b0c44298fc1c14',
        ),
      );
    });

    test('output is always 32 bytes', () {
      final hash = buildTypeHash('a', 'b', 'c', 'd');
      expect(hash.length, equals(32));
    });

    test('hex output is always 64 lowercase chars', () {
      final hex = typeHashHex(buildTypeHash('foo', 'bar', 'baz', 'qux'));
      expect(hex.length, equals(64));
      expect(hex, equals(hex.toLowerCase()));
    });
  });

  group('routing-prefix property (decision record §7.2)', () {
    test('every self cellType shares the same bytes[0:8] prefix', () {
      // The first 8 bytes of every self.* typeHash MUST equal
      // sha256("self")[0:8] = "06c604b332b386b6".  This is the property
      // brain relays exploit for O(1) namespace filtering.
      const expectedPrefix = '06c604b332b386b6';
      for (final entry in selfCellTypeTriples.entries) {
        final hex = selfCellTypeNameToHashHex(entry.key);
        expect(
          hex.substring(0, 16),
          equals(expectedPrefix),
          reason:
              'cellType ${entry.key} broke the namespace-prefix invariant',
        );
      }
    });

    test('every self cellType has a unique full typeHash', () {
      final seen = <String>{};
      for (final name in selfCellTypeTriples.keys) {
        final hex = selfCellTypeNameToHashHex(name);
        expect(
          seen.add(hex),
          isTrue,
          reason: 'typeHash collision for $name (= $hex)',
        );
      }
    });
  });

  group('selfCellTypeNameToHashHex', () {
    test('resolves every cellTypeName declared in selfCellTypeTriples', () {
      for (final name in selfCellTypeTriples.keys) {
        final hex = selfCellTypeNameToHashHex(name);
        expect(hex.length, equals(64));
      }
    });

    test('throws ArgumentError for unknown cellTypeName', () {
      expect(
        () => selfCellTypeNameToHashHex('unknown.cell.type'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

```
