---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/gradient/type_hash.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.115699+00:00
---

# apps/semantos/lib/src/gradient/type_hash.dart

```dart
/// type_hash.dart — Dart port of core/cell-engine/src/type_hash.zig::buildTypeHash.
///
/// Computes the 32-byte cell type hash from a 4-segment triple. Each
/// segment is sha256'd independently and the first 8 bytes of each
/// digest are concatenated. The result is the value the brain's
/// cartridge_cell_registry keys cellTypes by.
///
/// Example: betterment.practice.release → buildTypeHash('betterment', 'practice', 'release', '')
///          → 06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14
///
/// Verified against live brain mint 2026-05-28 (see C7-D ✓ in matrix).
library;

import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// Number of bytes from each segment's sha256 that go into the type hash.
const int typeHashSegmentBytes = 8;

/// Number of triple segments (s1..s4).
const int typeHashSegmentCount = 4;

/// Total bytes in a cell type hash.
const int typeHashSize = typeHashSegmentBytes * typeHashSegmentCount; // 32

/// Compute the 32-byte cell type hash from a 4-segment triple.
///
/// Mirrors buildTypeHash() in core/cell-engine/src/type_hash.zig.
/// An empty segment is hashed as the empty string (sha256('') first 8 bytes).
Uint8List buildTypeHash(String s1, String s2, String s3, String s4) {
  final out = Uint8List(typeHashSize);
  for (final (i, seg) in [s1, s2, s3, s4].indexed) {
    final digest = SHA256Digest().process(Uint8List.fromList(utf8.encode(seg)));
    out.setRange(
      i * typeHashSegmentBytes,
      (i + 1) * typeHashSegmentBytes,
      digest.sublist(0, typeHashSegmentBytes),
    );
  }
  return out;
}

/// Hex-encode a Uint8List as lowercase hex (no `0x` prefix).
/// Convenience wrapper — many BRC-100 wire fields are hex-encoded.
String typeHashHex(Uint8List bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

```
