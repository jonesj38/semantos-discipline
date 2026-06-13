---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cartridge_sdk/lib/src/cartridge_registry.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.510275+00:00
---

# packages/cartridge_sdk/lib/src/cartridge_registry.dart

```dart
/// CC2c — the Flutter cartridge binding + registry.
///
/// [CartridgeEntry] composes the pure [CartridgeDescriptor]
/// (semantos_core — id/role/routePath/title) with the Flutter binding
/// (icon + buildScreen). Every `*_experience` package self-registers
/// one into [CartridgeRegistry]; the shell router/home iterate the
/// registry generically — adding a cartridge needs NO router/main
/// logic edit (only its pubspec dep + one registration call).
///
/// Dependency direction: shell -> *_experience -> cartridge_sdk ->
/// semantos_core (pure Dart). No cycle.
library;

import 'package:flutter/widgets.dart';
import 'package:semantos_core/semantos_core.dart' show CartridgeDescriptor;

/// One registered cartridge's PWA-experience binding (the C3 link).
class CartridgeEntry {
  const CartridgeEntry({
    required this.descriptor,
    required this.buildScreen,
    this.icon,
  });

  /// Flutter-free identity/discovery facts (matches the Brain
  /// `/api/v1/info` `cartridges[]` entry).
  final CartridgeDescriptor descriptor;

  /// Optional home-picker icon.
  final IconData? icon;

  /// Builds the cartridge's root screen widget.
  final WidgetBuilder buildScreen;

  String get id => descriptor.id;
  String get role => descriptor.role;
  String get routePath => descriptor.routePath;
  String get title => descriptor.title;
}

/// Process-wide registry every `*_experience` self-registers into and
/// the shell iterates. Single instance; idempotent by id (last wins,
/// so a host can override).
class CartridgeRegistry {
  CartridgeRegistry._();
  static final CartridgeRegistry instance = CartridgeRegistry._();

  final Map<String, CartridgeEntry> _byId = <String, CartridgeEntry>{};

  /// Register (or replace) a cartridge entry.
  void register(CartridgeEntry entry) {
    _byId[entry.id] = entry;
  }

  /// All registered entries, stable insertion order.
  List<CartridgeEntry> get entries => _byId.values.toList(growable: false);

  CartridgeEntry? byId(String id) => _byId[id];

  bool has(String id) => _byId.containsKey(id);

  /// Entries the Brain actually serves — intersect the registry with
  /// the discovery list (`/api/v1/info` `cartridges[].id`). When
  /// [servedIds] is null the full registry is returned (dev/no-brain).
  List<CartridgeEntry> served(Set<String>? servedIds) {
    if (servedIds == null) return entries;
    return entries
        .where((e) => servedIds.contains(e.id))
        .toList(growable: false);
  }

  /// Test/host hook — clear all registrations.
  void resetForTest() => _byId.clear();
}

```
