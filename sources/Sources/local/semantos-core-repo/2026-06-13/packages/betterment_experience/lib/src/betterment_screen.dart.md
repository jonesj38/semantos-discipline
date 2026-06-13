---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/lib/src/betterment_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.448639+00:00
---

# packages/betterment_experience/lib/src/betterment_screen.dart

```dart
import 'package:flutter/material.dart';

/// Placeholder Betterment screen — C2 first move (2026-05-27).
///
/// The real surface (release-writing flow, intention setter, evening
/// review, vacuum session, gold seal, etc.) lands in the second move,
/// once the gradient pipeline forklift (C1) makes
/// `do | betterment | <verb>` utterances dispatchable and the C9 helm
/// primitive provides the default DO|FIND|TALK shelf this cartridge
/// consumes.
///
/// For the C7 golden slice (`do | betterment | release`), this screen
/// becomes the surface where the new release cell renders as an
/// attention card after layer 7 (brain dispatch) succeeds.
///
/// RENAME (2026-05-29): class previously SelfScreen.
class BettermentScreen extends StatelessWidget {
  const BettermentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Betterment')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.self_improvement, size: 64, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                'betterment',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.primary,
                      letterSpacing: 0.12,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Personal practice + Paskian narrative substrate for self-development',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                'C2 first move placeholder. The release flow, intention setter, evening review, and other practice flows surface here once the C1 gradient pipeline + C9 helm verb shelf land.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

```
