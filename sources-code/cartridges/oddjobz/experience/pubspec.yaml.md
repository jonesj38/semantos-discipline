---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.452235+00:00
---

# cartridges/oddjobz/experience/pubspec.yaml

```yaml
name: oddjobz_experience
description: >
  Oddjobz experience package for the Semantos shell. Implements
  IntentGrammar (grammar fragment + lexicon + intent handlers) for
  oddjobz domain concepts: pay_milestone, transition_job, assign_worker,
  request_quote. Registers with the shell's ConversationEngine at boot.

  This package imports only semantos_core — never the shell or wallet
  implementation directly. The shell wires the concrete WalletService
  at boot and provides it via SemantosPlatform.of(context).wallet.

  See docs/design/PLATFORM-WALLET-ARCHITECTURE.md §4.1, §5.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.11.0
  flutter: ^3.41.0

dependencies:
  flutter:
    sdk: flutter
  semantos_core:
    path: ../../../platforms/flutter/semantos_core
  cartridge_sdk:
    path: ../../../packages/cartridge_sdk
  # Web-compatible HTTP client (XHR on web, dart:io on native).
  http: ^1.2.0
  # Persistent bearer-token storage (localStorage on web, NSUserDefaults
  # on iOS, SharedPreferences on Android).
  shared_preferences: ^2.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  assets:
    - assets/manifest.json
    - assets/bundle.json

```
