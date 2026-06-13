---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.689971+00:00
---

# archive/packages-jam_experience/pubspec.yaml

```yaml
name: jam_experience
description: >
  Jam Room experience package for the Semantos shell. Implements
  IntentGrammar (grammar fragment + lexicon + intent handlers) for
  jambox domain concepts: launch_clip, record_take, capture_gesture,
  edit_pattern, twist_macro, mute_track, set_tempo. Registers with the
  shell's ConversationEngine at boot.

  This package imports only semantos_core — never the shell or wallet
  implementation directly. The shell wires the concrete WalletService
  at boot and provides it via SemantosPlatform.of(context).wallet.

  Vocabulary lifted from apps/world-apps/jam-room/src/semantic/objects.ts
  (JamboxObjectKind union) and the action verbs in
  docs/prd/jam-room/PHASE-A-VOCABULARY-AND-RACK.md.

  See docs/design/PLATFORM-WALLET-SHELL-EXPLORATION.md §16 for the
  multi-extension validation this package unlocks.
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

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  assets:
    - assets/manifest.json
    - assets/bundle.json

```
