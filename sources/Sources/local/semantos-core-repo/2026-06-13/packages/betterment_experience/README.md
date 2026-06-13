---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.388770+00:00
---

# betterment_experience — canonical PWA cartridge package

**Track**: C2 (PWA Cartridge Extraction). First move 2026-05-27.
**Source cartridge manifest**: `cartridges/betterment/cartridge.json`.

## What's here (first move — skeleton + cartridge entry)

| File | Purpose |
|------|---------|
| `pubspec.yaml` | Package manifest. Depends on `semantos_core` + `cartridge_sdk`. |
| `lib/betterment_experience.dart` | Public API surface — exports cartridge entry, manifest loader, betterment_screen. |
| `lib/src/cartridge.dart` | `bettermentCartridge` CartridgeEntry + `registerBettermentCartridge()`. Mirrors oddjobz pattern. |
| `lib/src/manifest_loader.dart` | `BettermentManifestLoader.load()` + `provisionFromAsset()`. Same provisioner pipeline as oddjobz. |
| `lib/src/betterment_screen.dart` | Placeholder route screen. Real surface lands in second move. |
| `assets/manifest.json` | Minimal extension manifest (id/name/version/hatRoles). |
| `assets/bundle.json` | Compile-time DEV bundle envelope (no signature). |

## What's deferred (second move)

The cartridge.json content (23 cellTypes, 12 flows, enforcementHooks, theme) needs to land in manifest.json + bundle.json. Options:
- Mirror cartridges/betterment/cartridge.json contents
- Or load cartridges/betterment/cartridge.json at build-time and project into manifest schema

The intent grammar (`BettermentIntentGrammar` matching the oddjobz pattern) needs to be authored to bind the cartridge's flows to the shell's gradient pipeline.

The real screen surface for release-writing, intention-setting, evening-review etc. lands once C1 forklifts the gradient pipeline and C9 ships the canonical helm verb shelf this cartridge consumes.

## Wiring into the canonical shell

When the shell's main.dart wires betterment_experience (C2 second move):

```dart
import 'package:betterment_experience/betterment_experience.dart';
// ...
final provisioned = await Future.wait([
  OddjobzManifestLoader.provisionFromAsset(provisioner),
  BettermentManifestLoader.provisionFromAsset(provisioner),
]);
// ...
registerOddjobzCartridge();
registerBettermentCartridge();
```

Note the absence of JamManifestLoader and TesseraManifestLoader — those cartridges are archived per C8.

## Status vs C7 golden slice

The slice (`do | betterment | release`) needs the betterment cartridge registered at:
- **Layer 3 (OIR resolution)** — gradient pipeline looks up `betterment` in CartridgeRegistry, resolves trigger `release` to the `daily-release` flow from this cartridge's manifest.
- **Layer 8 (helm card)** — the new `betterment.practice.release` cell renders here as an attention surface card with title from `displayName: "Release"`.

After C2 second move, layer 3 should narrow from "cartridge missing" to "cartridge present but grammar/flows not wired".
