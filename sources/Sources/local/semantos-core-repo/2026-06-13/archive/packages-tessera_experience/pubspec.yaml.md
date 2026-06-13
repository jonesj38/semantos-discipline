---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-tessera_experience/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.692995+00:00
---

# archive/packages-tessera_experience/pubspec.yaml

```yaml
name: tessera_experience
description: >
  Tessera experience package for the Semantos shell. Implements
  IntentGrammar (grammar fragment + lexicon + intent handlers) for
  tessera care-chain provenance concepts: harvest, bottle,
  transfer_custody, record_care_event, consumer_scan, mark_tamper.
  Registers with the shell's ConversationEngine at boot and surfaces
  six operator hats (producer, field-worker, distributor,
  dock-handler, retailer, club-member) via the HatRegistry.

  The seventh tessera hat — consumer — is intentionally NOT here: it
  is the standalone anonymous NFC-tap PWA (Wave Tessera V1.6), no
  login, no shell composition.

  This package imports only semantos_core — never the shell or wallet
  implementation directly. Tessera does not move money, so the
  wallet seam is unused; intents resolve to brain-side verb.dispatch
  walker calls (wired post-DLO.1, V0.3).

  See docs/prd/TESSERA-CARTRIDGE.md §4 (hats) and
  docs/canon/commissions/wave-tessera.md §7.2 (V1.x hat surfaces).
version: 0.0.1
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

flutter:
  assets:
    - assets/manifest.json
    - assets/bundle.json

```
