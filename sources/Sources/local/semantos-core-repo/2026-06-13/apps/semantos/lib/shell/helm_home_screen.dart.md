---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/helm_home_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.102242+00:00
---

# apps/semantos/lib/shell/helm_home_screen.dart

```dart
/// helm_home_screen.dart — the canonical home surface of the Semantos PWA.
///
/// The helm IS the shell substrate. It hosts:
///   - AppBar: shell brand + apps-icon → CartridgePicker (PR-C9-5)
///   - HOME body: cell activity feed (AttentionEngine output post-V2)
///   - Modal verb shelf: DO | TALK | FIND (PR-C9-4)
///
/// Cartridges contribute SUB-VERBS into each modal (DO = state-mutating,
/// TALK = conversational, FIND = read-only retrieval). The shell never
/// hardcodes a cartridge-specific verb on the helm.
///
/// NOTE on hats (PR-C9-7a): hats are CARTRIDGE-SCOPED. The helm is the
/// shell, not a cartridge — so no hat indicator appears here. The hat
/// switcher renders inside each cartridge's own AppBar (where the
/// cartridge IS the active scope). Helm-leaked hat ("oddjobz · admin"
/// showing on a screen that has nothing to do with oddjobz) was a real
/// cross-wires bug; the fix is keep helm shell-neutral.
///
/// History:
///   - Wire-tick 4b/5 (2026-05-28): Release sheet wired as FAB →
///     IntentDispatcher dispatch → in-memory recent-mints list.
///   - PR-C9-1 (2026-05-29): cartridge-scoped hat state substrate.
///   - PR-C9-2 (2026-05-29): AppBar title → "Semantos" (shell brand).
///   - PR-C9-3 (2026-05-29): cartridge tab strip below AppBar.
///   - PR-C9-4 (2026-05-29): replaced single "Release" FAB with
///     DO | TALK | FIND modal verb shelf. Removed self-cartridge
///     framing (lotus icon, "Tap Release to capture and let go" copy).
///     Removed 9-tile apps-icon leading.
///   - PR-C9-5 (2026-05-29): cartridge tab strip removed (doesn't scale
///     beyond ~3 cartridges). Apps-icon RESTORED in AppBar leading;
///     opens the new CartridgePicker bottom sheet with search +
///     recency-sorted list — scales to N cartridges.
///   - PR-C9-7a (2026-05-29, this commit): HatSwitcher REMOVED from
///     helm AppBar. Helm is shell-level, not cartridge-level — no hat
///     belongs here. Hat switching lives inside cartridge views going
///     forward.
library;

import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:flutter/material.dart';

import '../src/dispatch/intent_dispatcher.dart';
import 'cartridge_hat_state.dart';
import 'cartridge_picker.dart';
import 'me/me_sheet.dart';
import 'modal_verb_shelf.dart';

/// Canonical home for the Semantos PWA.
///
/// AppBar communicates the shell hierarchy:
///   - leading: apps-icon → CartridgePicker bottom sheet (switch
///              into a cartridge surface)
///   - title:   "Semantos" — the shell brand (NEVER a cartridge name)
///   - actions: "Me" affordance (C11 PR-C11-1) — shell-level identity
///              primitive (root BRC-52 cert + wallet + recovery
///              flows). NOT a cartridge-scoped hat — the chrome
///              stays cartridge-neutral per PR-C9-7a; "me" is a
///              shell primitive that's always present. See
///              docs/design/HELM-ME-SURFACE.md for the four-row
///              sheet shape.
///
/// Body composition (top to bottom):
///   1. HOME body — cell activity feed (in-memory recent-mints for V1;
///      AttentionEngine ranked feed for V2+)
///   2. ModalVerbShelf — DO | TALK | FIND modal buttons
class HelmHomeScreen extends StatefulWidget {
  final IntentDispatcher dispatcher;

  const HelmHomeScreen({super.key, required this.dispatcher});

  @override
  State<HelmHomeScreen> createState() => _HelmHomeScreenState();
}

class _HelmHomeScreenState extends State<HelmHomeScreen> {
  String? _activeCartridge;

  String get _homeTitle {
    final active = _activeCartridge;
    if (active == null) return 'Semantos';
    return CartridgeRegistry.instance.byId(active)?.title ?? active;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The helm shell is cartridge-neutral. It tracks active cartridge only for
    // chrome/title/empty-state copy; cartridge data feeds live inside
    // cartridge-owned surfaces mounted by SemantosRouter.
    _activeCartridge = CartridgeHatScope.of(context).activeCartridge;
  }

  /// A mint may have changed cartridge-owned state. The shell has no feed to refresh.
  void _onMinted(IntentDispatchResult result, String payloadPreview) {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _activeCartridge == null
            ? Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.apps),
                  tooltip: 'Switch cartridge',
                  onPressed: () => showCartridgePicker(context),
                ),
              )
            : null,
        title: Text(_homeTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: null,
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Me',
            onPressed: () => showMeSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // HOME is intentionally blank/neutral. Cartridge-owned field
          // surfaces are mounted by SemantosRouter, not rendered here.
          Expanded(child: _buildFeed(context)),
          // DO | TALK | FIND modal verb shelf.
          ModalVerbShelf(dispatcher: widget.dispatcher, onMinted: _onMinted),
        ],
      ),
    );
  }

  Widget _buildFeed(BuildContext context) =>
      _ScopedOutAttentionState(activeCartridge: _activeCartridge);
}

class _ScopedOutAttentionState extends StatelessWidget {
  const _ScopedOutAttentionState({required this.activeCartridge});

  final String? activeCartridge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_alt_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              activeCartridge == null
                  ? 'Blank helm'
                  : 'Cartridge surface unavailable here.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              activeCartridge == null
                  ? 'Pick a cartridge to show its field surface.'
                  : 'Cartridge-owned field surfaces are mounted by the router.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

```
