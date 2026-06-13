---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/shell/shell_nav.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.900674+00:00
---

# archive/apps-semantos-monolith/lib/src/shell/shell_nav.dart

```dart
// ShellNav — cartridge-holder + inner Home|Do|Talk|Find nav.
//
// Per docs/design/SHELL-CARTRIDGE-MODEL.md, the shell is a two-level
// composition:
//
//   outer: cartridge holder — exactly one foreground cartridge visible
//          at a time; header is cartridge-specific (calendar+mic for
//          oddjobz, intention status for self, etc.); long-press
//          header → cartridge switcher (commit 3)
//   inner: canonical 4-tab nav — Home | Do | Talk | Find — that
//          foreground cartridges inherit by default.  Cartridges that
//          opt out (customSurface) take over the whole body below the
//          header.
//
// Background cartridges (wallet-headers, push-registration) have no UI
// presence here — they're activated via the lifecycle hook in HomeScreen.
// Latent cartridges (ratification, wallet-payment) arm trigger handlers
// in their onActivate and surface as modal routes when fired.
//
// Migration note: this widget keeps the same constructor signature
// (registry + deps + initialIndex) as the pre-refactor ShellNav, but
// `initialIndex` now refers to the index into `registry.foregroundEntries`
// (the cartridge selector) rather than the flat-nav tab index.  Commit 3
// promotes initialIndex into a cartridge_id read from a settings cell.

import 'package:flutter/material.dart';

import 'cartridge_entry.dart';
import 'cartridge_switcher.dart';

class ShellNav extends StatefulWidget {
  const ShellNav({
    super.key,
    required this.registry,
    required this.deps,
    this.initialCartridgeId,
    this.onCartridgeChanged,
  });

  final ShellCartridgeRegistry registry;
  final ShellDeps deps;

  /// Cartridge id to mount first.  Null = first foreground in declaration
  /// order (the safe default for fresh installs that haven't gone through
  /// the welcome flow).  Commit 3 follow-up: cell-backed via
  /// `shell.config.default_cartridge.v0`.
  final String? initialCartridgeId;

  /// Called when the operator switches to a different cartridge via the
  /// switcher modal.  HomeScreen wires this to
  /// [CartridgeSelectionStore.setLastUsedCartridgeId] so the next cold
  /// start opens the same cartridge.  Null = no persistence.
  final Future<void> Function(String cartridgeId)? onCartridgeChanged;

  @override
  State<ShellNav> createState() => _ShellNavState();
}

class _ShellNavState extends State<ShellNav> {
  late String _cartridgeId;

  @override
  void initState() {
    super.initState();
    final foregrounds = widget.registry.foregroundEntries;
    final initial = widget.initialCartridgeId;
    // If the requested id isn't a registered foreground (e.g. a cartridge
    // was uninstalled between sessions), fall back to the first one.
    if (initial != null &&
        foregrounds.any((e) => e.descriptor.id == initial)) {
      _cartridgeId = initial;
    } else {
      _cartridgeId =
          foregrounds.isNotEmpty ? foregrounds.first.descriptor.id : '';
    }
  }

  void _selectCartridge(String id) {
    if (!mounted) return;
    setState(() => _cartridgeId = id);
    // Fire-and-forget persistence so the switcher feels instant.
    widget.onCartridgeChanged?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    final foregrounds = widget.registry.foregroundEntries;
    if (foregrounds.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No foreground cartridges registered.')),
      );
    }

    final active = foregrounds.firstWhere(
      (e) => e.descriptor.id == _cartridgeId,
      orElse: () => foregrounds.first,
    );

    return _CartridgeFrame(
      cartridge: active,
      deps: widget.deps,
      onLongPressHeader: () => _openSwitcher(context, foregrounds),
    );
  }

  Future<void> _openSwitcher(
      BuildContext context, List<CartridgeEntry> foregrounds) async {
    final picked = await showCartridgeSwitcher(
      context,
      foregrounds: foregrounds,
      activeCartridgeId: _cartridgeId,
    );
    if (picked != null) _selectCartridge(picked);
  }
}

// ════════════════════════════════════════════════════════════════════════
// Cartridge frame — header + body (default-nav or custom-surface)
// ════════════════════════════════════════════════════════════════════════

class _CartridgeFrame extends StatefulWidget {
  const _CartridgeFrame({
    required this.cartridge,
    required this.deps,
    required this.onLongPressHeader,
  });

  final CartridgeEntry cartridge;
  final ShellDeps deps;
  final VoidCallback onLongPressHeader;

  @override
  State<_CartridgeFrame> createState() => _CartridgeFrameState();
}

class _CartridgeFrameState extends State<_CartridgeFrame> {
  @override
  Widget build(BuildContext context) {
    final c = widget.cartridge;
    final defaultNav = c.defaultNav;
    final customSurface = c.customSurface;

    // Header: cartridge-specific or shell default.
    final headerWidget = c.headerBuilder?.call(context, widget.deps);
    final appBar = AppBar(
      title: headerWidget ??
          GestureDetector(
            onLongPress: widget.onLongPressHeader,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(c.icon, size: 20),
                const SizedBox(width: 8),
                Text(c.label),
              ],
            ),
          ),
      // Long-press anywhere on the AppBar (when cartridge supplies its
      // own header) still opens the switcher.  Cartridge headers
      // typically include a dedicated cartridge-name affordance that
      // chains to onLongPressHeader; the GestureDetector here is the
      // shell-default fallback.
    );

    if (defaultNav != null) {
      return Scaffold(
        appBar: appBar,
        body: _DefaultNavBody(
          cartridge: c,
          nav: defaultNav,
          deps: widget.deps,
        ),
      );
    }

    if (customSurface != null) {
      return Scaffold(
        appBar: appBar,
        body: customSurface(context, widget.deps),
      );
    }

    // Legacy fallback — pre-taxonomy entries still render via buildTab.
    // ignore: deprecated_member_use_from_same_package
    return Scaffold(appBar: appBar, body: c.buildTab(context, widget.deps));
  }
}

// ════════════════════════════════════════════════════════════════════════
// Default nav — Home | Do | Talk | Find
// ════════════════════════════════════════════════════════════════════════

class _DefaultNavBody extends StatefulWidget {
  const _DefaultNavBody({
    required this.cartridge,
    required this.nav,
    required this.deps,
  });

  final CartridgeEntry cartridge;
  final CartridgeDefaultNav nav;
  final ShellDeps deps;

  @override
  State<_DefaultNavBody> createState() => _DefaultNavBodyState();
}

class _DefaultNavBodyState extends State<_DefaultNavBody> {
  int _tabIndex = 0;

  /// Compose the list of visible slots based on what the cartridge
  /// declared.  Home + Do are always visible; Talk is always visible
  /// (shell-default if no `buildTalk`); Find appears only when the
  /// cartridge declared a findScope or buildFind.
  List<_Slot> get _slots {
    final nav = widget.nav;
    final slots = <_Slot>[
      _Slot(
        icon: Icons.home,
        label: 'Home',
        build: nav.buildHome,
      ),
      _Slot(
        icon: Icons.bolt,
        label: 'Do',
        build: nav.buildDo,
      ),
      _Slot(
        icon: Icons.mic,
        label: 'Talk',
        build: nav.buildTalk ??
            (ctx, deps) => _ShellDefaultTalkPlaceholder(scope: nav.talkScope),
      ),
    ];
    if (nav.buildFind != null || nav.findScope != null) {
      slots.add(_Slot(
        icon: Icons.search,
        label: 'Find',
        build: nav.buildFind ??
            (ctx, deps) =>
                _ShellDefaultFindPlaceholder(scope: nav.findScope!),
      ));
    }
    return slots;
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slots;
    final safeIndex = _tabIndex.clamp(0, slots.length - 1);

    return Scaffold(
      body: IndexedStack(
        index: safeIndex,
        children: [
          for (final slot in slots)
            _KeepAlive(
              child: Builder(builder: (ctx) => slot.build(ctx, widget.deps)),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: [
          for (final slot in slots)
            NavigationDestination(icon: Icon(slot.icon), label: slot.label),
        ],
      ),
    );
  }
}

class _Slot {
  const _Slot({required this.icon, required this.label, required this.build});
  final IconData icon;
  final String label;
  final Widget Function(BuildContext, ShellDeps) build;
}

/// Wraps each slot body so its state survives tab switches.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ════════════════════════════════════════════════════════════════════════
// Shell-default placeholders for Talk and Find
// ════════════════════════════════════════════════════════════════════════
//
// These are deliberately minimal — the shell-native default Talk and
// Find surfaces are a follow-up (the contract supports them now; the
// rendering is a separate piece of work).  Cartridges that need real
// Talk/Find today (oddjobz) override the builders.

class _ShellDefaultTalkPlaceholder extends StatelessWidget {
  const _ShellDefaultTalkPlaceholder({required this.scope});
  final TalkScope scope;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text('Talk',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 8),
            Text(
              'No threads in scope: ${scope.cartridgeId ?? "global"}.\n'
              'Conversations relevant to this cartridge land here.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellDefaultFindPlaceholder extends StatelessWidget {
  const _ShellDefaultFindPlaceholder({required this.scope});
  final FindScope scope;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search,
                size: 48, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text('Find',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 8),
            Text(
              'Cell-store search scoped to: '
              '${scope.typePathPrefixAllowList?.join(", ") ?? "all"}.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

```
