---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/self/self_type_hash.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.868093+00:00
---

# archive/apps-semantos-monolith/lib/src/self/self_type_hash.dart

```dart
// BRAIN-GENERIC-MINT-VERB M4 — Dart mirror of the kernel buildTypeHash.
//
// Computes the canonical structured |8|8|8|8| typeHash from a 4-segment
// identity tuple, matching:
//   - kernel:     `core/cell-engine/src/type_hash.zig::buildTypeHash`
//   - TS mirror:  `core/protocol-types/src/type-hash.ts`
//   - decision:   `docs/design/STRUCTURED-TYPEHASH-CANONICAL.md` §T5.a
//
// Algorithm:
//   typeHash[ 0: 8] = sha256(s1)[0:8]    namespace
//   typeHash[ 8:16] = sha256(s2)[0:8]    domain
//   typeHash[16:24] = sha256(s3)[0:8]    sub-type
//   typeHash[24:32] = sha256(s4)[0:8]    qualifier
//
// The 32 bytes ARE the four truncated inner hashes concatenated
// directly — NO outer hash wrapper (mirrors the kernel exactly).
//
// Also ships `selfCellTypeTriples` — a const map of every `self`
// cartridge cellType's 4-segment triple, derived from
// `cartridges/self/cartridge.json` cellTypes[].  When that file
// changes, regenerate via:
//
//   python3 -c "import json; [print(f\"  '{ct['name']}': ['{t['segment1']}', '{t['segment2']}', '{t['segment3']}', '{t['segment4']}'],\") for ct, t in ((c, c['triple']) for c in json.load(open('cartridges/self/cartridge.json')).get('cellTypes', []))]"
//
// Future work: replace the hand-baked map with a brain-side
// `GET /api/v1/cells/types` endpoint and a startup fetch, so drift
// between cartridge.json and Dart constants becomes impossible.
// Tracked in OI-5-followup.

import 'dart:typed_data';
import 'package:pointycastle/digests/sha256.dart';

const int typeHashSize = 32;
const int typeHashSegmentBytes = 8;

/// Mirror of `core/cell-engine/src/type_hash.zig::buildTypeHash`.
///
/// Returns a 32-byte structured typeHash for the four-segment triple.
/// Independent SHA-256 over each segment; first 8 bytes of each digest
/// concatenated into the result. No outer hash.
Uint8List buildTypeHash(String s1, String s2, String s3, String s4) {
  final out = Uint8List(typeHashSize);
  final segs = [s1, s2, s3, s4];
  for (var i = 0; i < 4; i++) {
    final digest = _sha256(Uint8List.fromList(segs[i].codeUnits));
    out.setRange(
      i * typeHashSegmentBytes,
      (i + 1) * typeHashSegmentBytes,
      digest,
    );
  }
  return out;
}

/// Hex-encoded 64-char form of a typeHash.  Lowercase; matches the
/// brain's expected `typeHashHex` shape on `POST /api/v1/cells`.
String typeHashHex(Uint8List hash) {
  const hexChars = '0123456789abcdef';
  final buf = StringBuffer();
  for (final b in hash) {
    buf.write(hexChars[(b >> 4) & 0x0F]);
    buf.write(hexChars[b & 0x0F]);
  }
  return buf.toString();
}

/// Resolve a `self`-cartridge cellTypeName → its 64-hex typeHash.
/// Throws `ArgumentError` for unknown names — caller is expected to
/// pass names that came from cartridge.json (the flow definitions in
/// `flow_def.dart` reference exactly the entries in
/// `selfCellTypeTriples` below; new flows should add corresponding
/// triples when first introduced).
String selfCellTypeNameToHashHex(String cellTypeName) {
  final triple = selfCellTypeTriples[cellTypeName];
  if (triple == null) {
    throw ArgumentError.value(
      cellTypeName,
      'cellTypeName',
      'no triple registered; check apps/oddjobz-mobile/lib/src/self/self_type_hash.dart and cartridges/self/cartridge.json',
    );
  }
  return typeHashHex(buildTypeHash(triple[0], triple[1], triple[2], triple[3]));
}

Uint8List _sha256(Uint8List input) {
  final digest = SHA256Digest();
  digest.update(input, 0, input.length);
  final out = Uint8List(32);
  digest.doFinal(out, 0);
  return out;
}

/// Every `self` cartridge cellType's 4-segment identity triple,
/// extracted from `cartridges/self/cartridge.json` cellTypes[].
/// MUST stay in sync with that file — regenerate via the snippet in
/// this module's header doc-comment.
const Map<String, List<String>> selfCellTypeTriples = {
  'self.paskian.graph.node': ['self', 'paskian', 'graph', 'node'],
  'self.paskian.graph.edge': ['self', 'paskian', 'graph', 'edge'],
  'self.paskian.graph.stabilised': ['self', 'paskian', 'graph', 'stabilised'],
  'self.paskian.graph.pruned': ['self', 'paskian', 'graph', 'pruned'],
  'self.story.thread': ['self', 'story', 'thread', ''],
  'self.story.artifact': ['self', 'story', 'artifact', ''],
  'self.story.entity': ['self', 'story', 'entity', ''],
  'self.story.relation': ['self', 'story', 'relation', ''],
  'self.story.moment': ['self', 'story', 'moment', ''],
  'self.practice.release': ['self', 'practice', 'release', ''],
  'self.practice.session': ['self', 'practice', 'session', ''],
  'self.practice.intention': ['self', 'practice', 'intention', ''],
  'self.practice.insight': ['self', 'practice', 'insight', ''],
  'self.practice.pattern': ['self', 'practice', 'pattern', ''],
  'self.practice.connection': ['self', 'practice', 'connection', ''],
  'self.practice.vacuum': ['self', 'practice', 'vacuum', ''],
  'self.practice.seal': ['self', 'practice', 'seal', ''],
  'self.accountability.morning': ['self', 'accountability', 'morning', ''],
  'self.accountability.review': ['self', 'accountability', 'review', ''],
  'self.accountability.pulse': ['self', 'accountability', 'pulse', ''],
  'self.accountability.streak': ['self', 'accountability', 'streak', ''],
  'self.state.dimension': ['self', 'state', 'dimension', ''],
  'self.state.elevation': ['self', 'state', 'elevation', ''],
};

```
