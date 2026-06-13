---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/cartridge_hat_state.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.103651+00:00
---

# apps/semantos/lib/shell/cartridge_hat_state.dart

```dart
// C9 PR-C9-1 — cartridge-scoped hat state.
//
// Reference: docs/design/HELM-CANONICAL-SURFACE.md §6 hat-switcher
//            cartridge-scoping protocol.
//
// Replaces the prior global ActiveHatNotifier (single hat across all
// cartridges) with a state object that tracks:
//   - which cartridge is currently active (the L2 context the operator
//     is interacting with on the helm)
//   - the operator's last-selected hat PER cartridge (persists across
//     cartridge switches, so flipping back restores the right role)
//
// HatSwitcher widget reads `activeCartridge` to filter the dropdown to
// just that cartridge's hats; reads `activeHat` (computed from the
// per-cartridge map) for the displayed value; writes back via
// `setHatFor(cartridgeId, hat)` on selection.
//
// PR-C9-3 (cartridge tab strip) will wire the cartridge-switching UI;
// for now activeCartridge starts at the shell's first-provisioned
// cartridge (matches pre-refactor default-hat behaviour for emulator
// testing) and stays there.

import 'package:flutter/widgets.dart';
import 'package:semantos_core/semantos_core.dart';

/// Shell-level state holding the active cartridge id + the per-cartridge
/// active hat.  ChangeNotifier so consumers (HatSwitcher, future tab
/// strip, dynamic verb-shelf) rebuild reactively.
class CartridgeHatState extends ChangeNotifier {
  CartridgeHatState({
    String? initialCartridge,
    Map<String, Hat>? initialHats,
  })  : _activeCartridge = initialCartridge,
        _hats = Map.from(initialHats ?? const {});

  String? _activeCartridge;
  final Map<String, Hat> _hats;

  /// The extension id of the currently-active cartridge.  Null until
  /// the shell has at least one cartridge provisioned + an active one
  /// chosen.
  String? get activeCartridge => _activeCartridge;

  /// The operator's active hat for the currently-active cartridge.
  /// Null when no cartridge is active or no hat was set for the active
  /// cartridge yet.
  Hat? get activeHat => _activeCartridge == null
      ? null
      : _hats[_activeCartridge!];

  /// Set the active cartridge.  Triggers listeners (HatSwitcher
  /// re-renders + filters its dropdown to the new cartridge's hats).
  set activeCartridge(String? id) {
    if (_activeCartridge == id) return;
    _activeCartridge = id;
    notifyListeners();
  }

  /// Set the active hat for a specific cartridge.  Persists across
  /// cartridge switches — flipping back to this cartridge restores
  /// the chosen hat.  Triggers listeners only when the cartridge
  /// being modified is the active one (otherwise the dropdown display
  /// wouldn't change).
  void setHatFor(String cartridgeId, Hat hat) {
    assert(
      hat.extensionId == cartridgeId,
      'Hat must belong to the cartridge being set (got hat.extensionId=${hat.extensionId} for cartridgeId=$cartridgeId)',
    );
    _hats[cartridgeId] = hat;
    if (_activeCartridge == cartridgeId) notifyListeners();
  }

  /// Look up the persisted active hat for a given cartridge without
  /// changing the active cartridge.  Used by HatSwitcher to surface
  /// the right initial value when the active cartridge changes.
  Hat? activeHatFor(String cartridgeId) => _hats[cartridgeId];
}

/// InheritedNotifier exposing [CartridgeHatState] to descendants.
/// Rebuilds children when activeCartridge or per-cartridge active hat
/// changes.
class CartridgeHatScope extends InheritedNotifier<CartridgeHatState> {
  const CartridgeHatScope({
    super.key,
    required CartridgeHatState super.notifier,
    required super.child,
  });

  /// Resolve the state from the widget tree.  Asserts a scope is in
  /// scope — boot code in `main.dart` is responsible for wiring it.
  static CartridgeHatState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CartridgeHatScope>();
    assert(
      scope != null,
      'CartridgeHatScope.of() called outside a CartridgeHatScope widget.',
    );
    return scope!.notifier!;
  }
}

```
