---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/cartridge_descriptor.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.014953+00:00
---

# platforms/flutter/semantos_core/lib/src/cartridge_descriptor.dart

```dart
/// CC2c — the Flutter-free identity/discovery half of a cartridge.
///
/// `semantos_core` is pure Dart by design (no Flutter), so the
/// discovery/identity facts a cartridge declares — and what the Brain
/// surfaces at `GET /api/v1/info` `cartridges[]` (CC2b) — live here.
/// The Flutter binding (icon/buildScreen) is `CartridgeEntry` in the
/// `cartridge_sdk` package, which composes this descriptor.
///
/// Ref: docs/design/CANONICAL-CARTRIDGE-MODEL.md (C1/C3).
library;

class CartridgeDescriptor {
  const CartridgeDescriptor({
    required this.id,
    required this.routePath,
    required this.title,
    this.role = 'experience',
  });

  /// Canonical cartridge id — matches `cartridge.json` `id` and the
  /// Brain discovery list (`/api/v1/info` `cartridges[].id`).
  final String id;

  /// Cartridge role (`infra` | `experience` | `grammar-lexicon`).
  final String role;

  /// Route path the shell registers for this cartridge.
  final String routePath;

  /// Human-readable title for the home picker.
  final String title;
}

```
