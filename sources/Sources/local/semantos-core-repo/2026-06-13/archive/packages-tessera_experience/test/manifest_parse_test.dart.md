---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-tessera_experience/test/manifest_parse_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.827841+00:00
---

# archive/packages-tessera_experience/test/manifest_parse_test.dart

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos_core/semantos_core.dart';

/// Validates that the bundled tessera manifest + bundle envelope parse
/// against the Dart `ExtensionManifest` schema. The analyzer cannot
/// catch a malformed asset JSON — this test is the schema gate, the
/// Dart-side analogue of V0.2's manifest.test.ts.
void main() {
  test('assets/manifest.json parses + declares the 6 shell hats', () {
    final raw = File('assets/manifest.json').readAsStringSync();
    final manifest = ExtensionManifest.fromJsonString(raw);

    expect(manifest.id, 'tessera');
    expect(manifest.version, '0.0.1');
    // tessera.consumer is intentionally excluded — standalone PWA (V1.6).
    expect(
      manifest.hatRoles..sort(),
      ['club-member', 'distributor', 'dock-handler', 'field-worker',
              'producer', 'retailer']
          ..sort(),
    );
    expect(manifest.grammar.lexicon.name, 'tessera');
    expect(manifest.grammar.lexicon.categories.length, 13);
    expect(manifest.grammar.objectTypes.length, 10);
    // 13 actions: one per brain-manifest verb. The earlier hand-written
    // shell manifest had 12 (report_quality_issue was missed); the
    // generator derives all 13 from the canonical verbs[] — this count
    // is now generator-enforced, not hand-maintained.
    expect(manifest.grammar.actions.length, 13);
    // domainFlag is derived from constants.json TESSERA_PAGE, not
    // hand-allocated — 0x00010400 (66560), collision-free vs jambox
    // shell 0x000104 (260).
    expect(manifest.domainFlag, 0x00010400);
  });

  test('assets/bundle.json envelope wraps the same manifest', () {
    final raw = File('assets/bundle.json').readAsStringSync();
    // The bundle envelope embeds the manifest under "manifest"; parsing
    // the envelope's manifest field must yield the same id/version.
    expect(raw.contains('"schemaVersion": 1'), isTrue);
    expect(raw.contains('"id": "tessera"'), isTrue);
    expect(raw.contains('"scheme": "none"'), isTrue);
  });
}

```
