---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/lib/src/cartridge.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.449198+00:00
---

# packages/betterment_experience/lib/src/cartridge.dart

```dart
/// Betterment's canonical CartridgeEntry + self-registration.
///
/// The canonical shell calls [registerBettermentCartridge] once at
/// bootstrap; the SemantosRouter routes /betterment generically off
/// the CartridgeRegistry (no per-cartridge router edits). Mirrors the
/// oddjobz_experience pattern.
///
/// RENAME (2026-05-29): id was 'self', route was '/self'. Renamed so
/// the word "self" can name the shell-level identity primitive (root
/// BRC-52 cert + helm "me" surface) without collision.
library;

import 'package:flutter/material.dart';
import 'package:cartridge_sdk/cartridge_sdk.dart';

import 'betterment_screen.dart';
import 'release_capture_screen.dart';

/// Manifest key for the `do | betterment | release` custom capture surface.
/// The Release verb's manifest `inputShape.customKey` must match this so the
/// shell's modal verb shelf pushes [ReleaseCaptureScreen] (cartridge-neutral
/// lookup via CustomVerbSurfaceRegistry).
const String kBettermentReleaseSurfaceKey = 'betterment.release';

Widget _buildBettermentScreen(BuildContext _) => const BettermentScreen();

/// The canonical entry — `descriptor.id` matches
/// `cartridges/betterment/cartridge.json` and the Brain discovery list
/// (`/api/v1/info` `cartridges[].id`).
const CartridgeEntry bettermentCartridge = CartridgeEntry(
  descriptor: CartridgeDescriptor(
    id: 'betterment',
    role: 'experience',
    routePath: '/betterment',
    title: 'Betterment',
  ),
  icon: Icons.self_improvement,
  buildScreen: _buildBettermentScreen,
);

/// Self-register into the shared registry (idempotent by id). Also registers
/// the `do | betterment | release` custom capture surface so the shell can
/// push it by manifest key without importing this package.
void registerBettermentCartridge() {
  CartridgeRegistry.instance.register(bettermentCartridge);
  CustomVerbSurfaceRegistry.instance.register(
    kBettermentReleaseSurfaceKey,
    (_) => const ReleaseCaptureScreen(),
  );
}

```
