---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/helm_scaffold.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.103369+00:00
---

# apps/semantos/lib/shell/helm_scaffold.dart

```dart
/// helm_scaffold.dart — the canonical helm widget for the Semantos PWA.
///
/// C9 first move (2026-05-28). Implements the **default UI surface** per
/// docs/canon/canonicalization-glossary.md "Helm" + the CSD 1-3-5-3-1
/// pyramid layout per docs/prd/jam-room/design/CSD-COMPRESSION-GRADIENT.md.
///
/// Layout (1-3-5-3-1 on viewport):
///   L1 anchor:   AppBar with cartridge title + hat switcher (header bar)
///   L2 active:   DO | FIND | TALK verb shelf (3 modal verbs, big buttons)
///   L3 support:  Attention surface (ranked feed of cells to look at next)
///   L4 infra:    SemantosPlatform (cell DAG + pask + wallet — invisible)
///   L5 device:   surfaceShape from MediaQuery
///
/// Cartridges with `ui.surfacingMode: default` (oddjobz, self) render
/// here. Cartridges with `ui.surfacingMode: dedicated` (jam-room, chess)
/// substitute their own widget via SemantosRouter routing.
///
/// SUPERSEDES THE NAMING CLASH: the monolith's lib/src/helm/ is actually
/// oddjobz's job dashboard — this file (lib/shell/helm_scaffold.dart) is
/// the universal helm primitive in the canonical shell.
///
/// Status vs C7 slice (layer 8 — helm card render): this widget provides
/// the surface. Wiring the AttentionSurface to render a real
/// betterment.practice.release cell card is C9 tick 2+ (depends on
/// AttentionEngine forklift from monolith's lib/src/helm/ ratio of
/// substrate vs cartridge code — separate cleanup).

import 'package:flutter/material.dart';

import 'hat_switcher.dart';

/// The canonical helm surface. Drop this in as `home:` for any cartridge
/// with surfacingMode=default, or wire as the shell's default route.
class HelmScaffold extends StatelessWidget {
  /// Title shown in the AppBar. Defaults to the active cartridge's name.
  final String title;

  /// Optional override widget for the attention surface body. Cartridges
  /// can supply their own card list while keeping the verb shelf + hat
  /// switcher canonical.
  final Widget? attentionSurface;

  /// Optional callbacks for the DO/FIND/TALK verb buttons. C9 tick 1
  /// scaffolds the chrome; tick 2+ wires the gradient pipeline +
  /// ConversationEngine + voice mic.
  final VoidCallback? onDoPressed;
  final VoidCallback? onFindPressed;
  final VoidCallback? onTalkPressed;
  final VoidCallback? onMicPressed;

  const HelmScaffold({
    super.key,
    this.title = 'Semantos',
    this.attentionSurface,
    this.onDoPressed,
    this.onFindPressed,
    this.onTalkPressed,
    this.onMicPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      // L1 ANCHOR — header bar: cartridge identity + hat switcher
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic),
            tooltip: 'Voice (helm mic — captures utterance, routes through gradient pipeline)',
            onPressed: onMicPressed,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: HatSwitcher(),
          ),
        ],
      ),
      body: Column(
        children: [
          // L2 ACTIVE — DO|FIND|TALK verb shelf
          // Per CSD pyramid: 3 active items, big touch targets.
          _VerbShelf(
            onDoPressed: onDoPressed,
            onFindPressed: onFindPressed,
            onTalkPressed: onTalkPressed,
          ),
          // L3 SUPPORT — attention surface (ranked feed)
          Expanded(
            child: attentionSurface ??
                _PlaceholderAttentionSurface(color: cs.surfaceContainerHighest),
          ),
        ],
      ),
    );
  }
}

/// The DO | FIND | TALK verb shelf — L2 active layer of the pyramid.
///
/// Each button surfaces the modal's L3-support sub-verbs when tapped
/// (DO → new/patch/transition/sign/publish, FIND → inspect/list/trace/verify,
/// TALK → conversation scope). C9 tick 2 wires the sub-verb surfacing.
class _VerbShelf extends StatelessWidget {
  final VoidCallback? onDoPressed;
  final VoidCallback? onFindPressed;
  final VoidCallback? onTalkPressed;

  const _VerbShelf({
    this.onDoPressed,
    this.onFindPressed,
    this.onTalkPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(child: _VerbButton(label: 'DO', icon: Icons.bolt, onPressed: onDoPressed)),
          const SizedBox(width: 8),
          Expanded(child: _VerbButton(label: 'FIND', icon: Icons.search, onPressed: onFindPressed)),
          const SizedBox(width: 8),
          Expanded(child: _VerbButton(label: 'TALK', icon: Icons.forum, onPressed: onTalkPressed)),
        ],
      ),
    );
  }
}

class _VerbButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _VerbButton({required this.label, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        ],
      ),
    );
  }
}

/// Placeholder until AttentionEngine forklift lands (C9 tick 2+).
/// Renders a subtle empty state explaining what'll go here.
class _PlaceholderAttentionSurface extends StatelessWidget {
  final Color color;
  const _PlaceholderAttentionSurface({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.format_list_bulleted, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Attention surface',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Ranked feed of what to look at next. AttentionEngine forklift in C9 tick 2 wires this to real cells.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

```
