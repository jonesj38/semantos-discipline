---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/cartridge.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.815216+00:00
---

# archive/packages-jam_experience/lib/src/cartridge.dart

```dart
/// CC2c — jam-room's canonical CartridgeEntry + self-registration.
///
/// The shell calls [registerJamCartridge] once at bootstrap; the
/// router then routes generically off the CartridgeRegistry (no
/// per-cartridge router edits). Ref:
/// docs/design/CANONICAL-CARTRIDGE-MODEL.md (C3 binding).
///
/// NOTE: `id` is kept as `jambox` to match the existing shell
/// grammar/route id; reconciling it to the canonical cartridge.json id
/// is CC4 (fan-out + directory collapse).
library;

import 'package:flutter/material.dart';
import 'package:cartridge_sdk/cartridge_sdk.dart';

import 'jam_screen.dart';

Widget _buildJamScreen(BuildContext _) => const JamboxScreen();

const CartridgeEntry jamCartridge = CartridgeEntry(
  descriptor: CartridgeDescriptor(
    id: 'jambox',
    role: 'experience',
    routePath: '/jambox',
    title: 'Jam Room',
  ),
  icon: Icons.music_note_outlined,
  buildScreen: _buildJamScreen,
);

/// Self-register into the shared registry (idempotent by id).
void registerJamCartridge() =>
    CartridgeRegistry.instance.register(jamCartridge);

```
