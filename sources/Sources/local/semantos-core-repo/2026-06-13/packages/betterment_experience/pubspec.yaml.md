---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.389113+00:00
---

# packages/betterment_experience/pubspec.yaml

```yaml
name: betterment_experience
description: >
  Betterment experience package for the Semantos shell. Surfaces the
  `betterment` cartridge (personal practice + Paskian narrative
  substrate for self-development) to the canonical PWA shell via the
  same provisioning pipeline used by oddjobz_experience and other
  cartridges.

  Per cartridges/betterment/cartridge.json: declares the 23 cellTypes
  under (betterment, *, *, *) — paskian.graph, story, practice,
  accountability, state — plus 12 flows (daily-release, set-intention,
  vacuum-session, gold-seal, connection-receive, evening-review,
  morning-intention, etc).

  Triggered intents like `release` map through the shell's gradient
  pipeline (SIR→OIR→opcode→cell) to mint betterment.practice.release
  cells.

  RENAME HISTORY: previously published as `self_experience` with cell-
  type prefix `self.*`. Renamed 2026-05-29 to free the word "self" for
  the shell-level identity primitive (root BRC-52 operator cert + the
  helm "me" surface). Cell-type prefix migrated to `betterment.*` in
  the same change — all type hashes recomputed; v1 was test data only,
  no on-chain migration needed.

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
  cartridge_sdk:
    path: ../cartridge_sdk
  image_picker: ^1.1.2
  # Pin to 5.0.x: record 5.1.x bumped record_platform_interface to 1.6.0
  # (added startStream), but record_linux 0.7.2 never implemented it — and
  # Flutter compiles every platform impl's Dart into the kernel, so the Linux
  # impl breaks the Android build. 5.0.x keeps the matrix coherent.
  record: 5.0.5
  path_provider: ^2.1.4

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/manifest.json
    - assets/bundle.json

```
