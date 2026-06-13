---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-tessera_experience/lib/src/tessera_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.828186+00:00
---

# archive/packages-tessera_experience/lib/src/tessera_screen.dart

```dart
import 'package:flutter/material.dart';

/// The tessera experience screen widget. Registered in SemantosRouter
/// at `/tessera`.
///
/// SCAFFOLD STATUS (Wave Tessera shell wire-in): placeholder. The hat
/// surfaces migrate in per the V1.x deliverables:
///   V1.1 producer      — vineyard map, blending bench, bottling line
///   V1.2 distributor   — receiving dock, custody log, dispatch
///   V1.3 dock-handler  — single-screen scan-and-confirm
///   V1.4 retailer      — inventory verification, wine-list export
///   V1.5 club-member   — allocation queue, cellar, Care Score timeline
///   V1.7 field-worker  — offline-first in-vineyard harvest entry
///
/// The seventh hat (consumer) is a separate standalone PWA (V1.6),
/// not routed here.
///
/// The screen reads the active hat from the shell's ActiveHatScope so
/// the placeholder already reflects which surface a V1.x build will
/// fill in.
class TesseraScreen extends StatelessWidget {
  const TesseraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tessera'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Tessera — care-chain provenance\n\n'
            'Cartridge scaffold wired into the shell.\n'
            'Hat surfaces land via Wave Tessera V1.1–V1.7.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

```
