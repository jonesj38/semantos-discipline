---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/shell/welcome_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.901886+00:00
---

# archive/apps-semantos-monolith/lib/src/shell/welcome_screen.dart

```dart
// WelcomeScreen — first-launch operator onboarding.
//
// Shown by HomeScreen before mounting ShellNav when CartridgeSelectionStore
// reports `isWelcomed() == false`.  Walks the operator through picking
// the cartridge they want as their default landing page, then marks
// `shell.welcomed = 1` and writes `shell.lastUsedCartridgeId` so the
// next cold start opens directly into that cartridge.
//
// Per SHELL-CARTRIDGE-MODEL §8, welcome is a foreground experience that
// auto-runs exactly once.  We deliberately keep it OUTSIDE the cartridge
// registry's foreground list — it should never appear in the cartridge
// switcher, because there's nothing meaningful to return to.  Operators
// can re-trigger it later from settings (commit follow-up).

import 'package:flutter/material.dart';

import 'cartridge_entry.dart';
import 'cartridge_selection_store.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.registry,
    required this.selectionStore,
    required this.onCompleted,
  });

  /// All registered cartridges — the foreground ones are offered as
  /// candidate default landing pages.
  final ShellCartridgeRegistry registry;

  /// Where the welcome flow persists its completion state and the
  /// operator's chosen default cartridge id.
  final CartridgeSelectionStore selectionStore;

  /// Called after the welcome flow finishes successfully so HomeScreen
  /// can re-render and mount ShellNav.  Receives the cartridge id the
  /// operator picked (also already persisted via [selectionStore]).
  final Future<void> Function(String chosenCartridgeId) onCompleted;

  Future<void> _pick(BuildContext context, String cartridgeId) async {
    await selectionStore.setLastUsedCartridgeId(cartridgeId);
    await selectionStore.markWelcomed();
    await onCompleted(cartridgeId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final foregrounds = registry.foregroundEntries;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(Icons.waving_hand_outlined, size: 64, color: cs.primary),
            const SizedBox(height: 24),
            Text('Welcome to semantos',
                style: tt.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Your shell is paired and ready.  Pick a cartridge to start in '
              '— you can switch any time by long-pressing the cartridge name '
              'in the header.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Text('Start in', style: tt.titleSmall),
            const SizedBox(height: 8),
            for (final entry in foregrounds)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(entry.icon, color: cs.onPrimaryContainer),
                  ),
                  title: Text(entry.label),
                  subtitle: Text(entry.descriptor.title),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () => _pick(context, entry.descriptor.id),
                ),
              ),
            const SizedBox(height: 32),
            Text(
              'Cartridges share the same identity and conversation graph.\n'
              'Switching between them is free.',
              style: tt.bodySmall?.copyWith(color: cs.outlineVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

```
