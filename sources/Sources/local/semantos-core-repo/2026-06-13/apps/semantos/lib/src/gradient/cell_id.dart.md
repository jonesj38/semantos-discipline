---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/gradient/cell_id.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.116593+00:00
---

# apps/semantos/lib/src/gradient/cell_id.dart

```dart
// 2026-05-07 — non-cryptographic cell-id derivation for the on-device
// L1→L4 pipeline.  Mirrors the TS reference at `runtime/intent/src/
// shell-pipeline-deps.ts::deriveCellId`.
//
// Format: `cell-<sizeHex(6)>-<bytePrefix(8 hex)>-<uuidTail(8)>`
//   - `sizeHex(6)`        : opcode-bytes length, lower-case hex,
//                           left-padded to 6 chars.
//   - `bytePrefix(8 hex)` : first 4 bytes of `bytes` in lower-case hex.
//                           Zero-padded to 8 hex chars when `bytes` is
//                           shorter than 4 bytes (defensive — production
//                           opcode streams are always non-empty).
//   - `uuidTail(8)`       : last 8 chars of a fresh UUID v4 (the dashes
//                           stripped), lower-case.
//
// This is a placeholder pending the type-hashed cell-id derived from
// `core/cell-engine/src/cell.zig::packCell` — kept compatible with the
// brain-side accept-verbatim policy described in
// `docs/spec/oddjobz-intent-cell-v1.md`.

import 'dart:typed_data';

/// Build a deterministic non-cryptographic cell id from the OIR-emitted
/// opcode stream.  `uuid` is invoked to produce the trailing entropy
/// component — production wires `const Uuid().v4()`; tests inject a
/// deterministic generator.
String deriveCellId(Uint8List bytes, String Function() uuid) {
  final sizeHex = bytes.length.toRadixString(16).padLeft(6, '0');

  final prefixBuf = StringBuffer();
  for (var i = 0; i < 4; i++) {
    final b = i < bytes.length ? bytes[i] : 0;
    prefixBuf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  final bytePrefix = prefixBuf.toString();

  // `Uuid.v4()` returns the canonical `xxxxxxxx-xxxx-...` shape; strip
  // dashes and take the last 8 chars so the suffix matches the TS
  // reference (which uses Node's `crypto.randomUUID()` and slices
  // the trailing block).
  final raw = uuid();
  final stripped = raw.replaceAll('-', '').toLowerCase();
  final uuidTail = stripped.length >= 8
      ? stripped.substring(stripped.length - 8)
      : stripped.padLeft(8, '0');

  return 'cell-$sizeHex-$bytePrefix-$uuidTail';
}

```
