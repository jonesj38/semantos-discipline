---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/hat_switcher.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.101648+00:00
---

# apps/semantos/lib/shell/hat_switcher.dart

```dart
import 'package:flutter/material.dart';
import 'package:semantos_core/semantos_core.dart';

import 'cartridge_hat_state.dart';
import 'semantos_platform.dart';

/// Top-bar widget that surfaces the operator's active hat FOR the
/// currently-active cartridge.
///
/// C9 PR-C9-1 refactor (2026-05-29 per HELM-CANONICAL-SURFACE.md §6):
/// hats are now CARTRIDGE-SCOPED. The dropdown shows ONLY the active
/// cartridge's declared hats. Hat selection persists per-cartridge —
/// flipping back to this cartridge restores the previously-chosen role.
/// When the active cartridge changes (PR-C9-3 lands the tab strip to
/// drive that), the displayed hat reactively updates to whatever was
/// last selected for the new active cartridge.
///
/// State source: [CartridgeHatState] (wired in main.dart boot).
/// Hat list source: [HatRegistry.forExtension(activeCartridge)] —
/// reads each manifest's hatRoles[] at boot.
///
/// Pre-refactor: a single global ActiveHatNotifier held one hat across
/// all cartridges. Bug: "oddjobz · admin" stuck even when Self was
/// the foregrounded cartridge.
class HatSwitcher extends StatelessWidget {
  const HatSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final platform = SemantosPlatform.of(context);
    final state = CartridgeHatScope.of(context);
    final cartridgeId = state.activeCartridge;

    // No cartridge active yet (boot race) → suppress switcher.
    if (cartridgeId == null) return const SizedBox.shrink();

    // Filter hats to just the active cartridge's contributions.
    // HatRegistry.forExtension is an existing per-extension query —
    // pre-refactor this was unused; now it's the canonical source.
    final hats = platform.hatRegistry.forExtension(cartridgeId).toList();
    if (hats.isEmpty) return const SizedBox.shrink();

    // Active hat for this cartridge — falls back to the first hat
    // when no explicit selection has been persisted yet.
    final active = state.activeHatFor(cartridgeId) ?? hats.first;

    return DropdownButton<Hat>(
      value: active,
      underline: const SizedBox.shrink(),
      icon: const Icon(Icons.face_outlined),
      items: [
        for (final hat in hats)
          DropdownMenuItem<Hat>(
            value: hat,
            child: Text(hat.label),
          ),
      ],
      onChanged: (selected) {
        if (selected != null) state.setHatFor(cartridgeId, selected);
      },
    );
  }
}

```
