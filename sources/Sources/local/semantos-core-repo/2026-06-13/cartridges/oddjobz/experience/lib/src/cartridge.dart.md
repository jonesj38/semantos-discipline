---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/cartridge.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.460746+00:00
---

# cartridges/oddjobz/experience/lib/src/cartridge.dart

```dart
/// CC2c — oddjobz's canonical CartridgeEntry + self-registration.
///
/// The shell calls [registerOddjobzCartridge] once at bootstrap; the
/// router then routes /oddjobz generically off the CartridgeRegistry
/// (no per-cartridge router edits). Ref:
/// docs/design/CANONICAL-CARTRIDGE-MODEL.md (C3 binding).
library;

import 'package:flutter/material.dart';
import 'package:cartridge_sdk/cartridge_sdk.dart';

import 'oddjobz_screen.dart';

Widget _buildOddjobzScreen(BuildContext _) => const OddjobzScreen();

/// The canonical entry — `descriptor.id` matches
/// `extensions/oddjobz/cartridge.json` and the Brain discovery list
/// (`/api/v1/info` `cartridges[].id`).
const CartridgeEntry oddjobzCartridge = CartridgeEntry(
  descriptor: CartridgeDescriptor(
    id: 'oddjobz',
    role: 'experience',
    routePath: '/oddjobz',
    title: 'Oddjobz',
  ),
  icon: Icons.work_outline,
  buildScreen: _buildOddjobzScreen,
);

/// Self-register into the shared registry (idempotent by id).
void registerOddjobzCartridge() =>
    CartridgeRegistry.instance.register(oddjobzCartridge);

```
