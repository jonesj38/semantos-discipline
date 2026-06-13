---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cartridge_sdk/lib/cartridge_sdk.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.509640+00:00
---

# packages/cartridge_sdk/lib/cartridge_sdk.dart

```dart
/// Canonical Flutter cartridge SPI (Wave Canonical-Cartridge CC2c).
///
/// Import this from every `*_experience` package (to self-register a
/// [CartridgeEntry]) and from the shell (to iterate the registry).
/// The Flutter-free identity half ([CartridgeDescriptor]) is
/// re-exported from `semantos_core`.
library cartridge_sdk;

export 'package:semantos_core/semantos_core.dart' show CartridgeDescriptor;
export 'src/cartridge_registry.dart';
export 'src/cartridge_host.dart';

```
