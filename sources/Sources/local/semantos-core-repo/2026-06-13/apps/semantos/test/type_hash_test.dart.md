---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/type_hash_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.093609+00:00
---

# apps/semantos/test/type_hash_test.dart

```dart
// Conformance test: Dart buildTypeHash matches the live brain's
// cartridge_cell_registry lookup. Originally verified 2026-05-28 by
// minting a real self.practice.release cell at oddjobtodd.info using
// the type hash 06c604b332b386b6ada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14.
//
// RENAME (2026-05-29): cellType prefix flipped self.* → betterment.*
// alongside the self_experience → betterment_experience package
// rename. The verified live-brain mint is now stale (used the old
// prefix); a re-verification against the canonical app on the
// canonical brain is part of the C7-E operator-acceptance run.
// The function under test is unchanged — only the input segment + the
// expected hex value moved.
//
// Run: flutter test test/type_hash_test.dart
//   (or from repo root: cd apps/semantos && flutter test test/type_hash_test.dart)

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/gradient/type_hash.dart';

void main() {
  group('buildTypeHash — Dart parity with Zig type_hash spec', () {
    test('betterment.practice.release → 06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14', () {
      final bytes = buildTypeHash('betterment', 'practice', 'release', '');
      expect(bytes.length, 32);
      expect(
        typeHashHex(bytes),
        '06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14',
      );
    });

    test('segment count is 4', () {
      // 4 segments × 8 bytes = 32-byte hash
      expect(typeHashSegmentCount, 4);
      expect(typeHashSegmentBytes, 8);
      expect(typeHashSize, 32);
    });

    test('empty segment hashes the empty string', () {
      // sha256('')[0..8] = e3b0c44298fc1c14 — appears at end of
      // betterment.practice.release (where segment4 is empty). That
      // the parity with the per-cartridge spec holds proves empty-
      // segment handling is correct.
      final bytes = buildTypeHash('', '', '', '');
      // All four segments are sha256('')[..8] = e3b0c44298fc1c14
      expect(typeHashHex(bytes), 'e3b0c44298fc1c14' * 4);
    });

    test('first 8 bytes are namespace prefix sha256("betterment")[0..8]', () {
      // Per cartridges/betterment/brain/zig/betterment_cell_specs.zig:
      //   "Bytes 0:8 of every type_hash here are 06d0a049e88a982b
      //    = sha256('betterment')[0:8]"
      final bytes = buildTypeHash('betterment', 'anything', 'anything', 'anything');
      expect(typeHashHex(bytes).substring(0, 16), '06d0a049e88a982b');
    });
  });
}

```
