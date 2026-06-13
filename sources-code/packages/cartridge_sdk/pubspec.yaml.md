---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cartridge_sdk/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.392888+00:00
---

# packages/cartridge_sdk/pubspec.yaml

```yaml
name: cartridge_sdk
description: >
  Canonical Flutter cartridge SPI (Wave Canonical-Cartridge CC2c).

  Holds CartridgeEntry (the Flutter binding — buildScreen/icon over a
  pure CartridgeDescriptor) + CartridgeRegistry. Every *_experience
  package self-registers a CartridgeEntry here; the shell
  (semantos-shell) iterates the registry generically — no per-cartridge
  router/main logic edits. The Flutter-free identity/discovery half
  (CartridgeDescriptor) lives in semantos_core so non-UI consumers and
  the Brain discovery list (/api/v1/info cartridges[]) stay pure-Dart.

  Dependency direction: shell -> *_experience -> cartridge_sdk ->
  semantos_core (no cycle; semantos_core stays pure Dart).

  See docs/design/CANONICAL-CARTRIDGE-MODEL.md (C3),
  docs/canon/commissions/wave-canonical-cartridge.md CC2c.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.11.0
  flutter: ^3.41.0

dependencies:
  flutter:
    sdk: flutter
  semantos_core:
    path: ../../platforms/flutter/semantos_core

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

```
