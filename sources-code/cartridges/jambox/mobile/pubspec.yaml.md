---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.578964+00:00
---

# cartridges/jambox/mobile/pubspec.yaml

```yaml
name: jam_room_mobile
description: >
  D-G.2 — Flutter mobile shell for the jam room. Pairs with runtime/semantos-brain over
  WSS, subscribes to LoomState, renders L1 anchor card + L2 bottom-tab bar
  natively, and hosts MIDI controllers via flutter_midi_command (USB OTG on
  Android; CoreMIDI on iOS).

  See docs/prd/jam-room/PHASE-G-MOBILE-AND-FLUTTER.md for the full spec.
  Modelled on apps/oddjobz-mobile/; reuses its pairing flow, theme service,
  and WSS event stream pattern.

publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.11.0
  flutter: ^3.41.0

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # Crypto primitives for BRC-42 child derivation — same as oddjobz-mobile.
  pointycastle: ^3.9.1

  # HTTP client — bearer-gated POST /api/v1/device-pair.
  dio: ^5.7.0

  # Child-cert + bearer custody (iOS Keychain / Android Keystore).
  flutter_secure_storage: ^9.2.0

  # QR scanner for the pairing screen — same plugin as oddjobz-mobile.
  mobile_scanner: ^5.2.3

  # D-G.3: WSS live subscription to room:{roomId}:state.
  web_socket_channel: ^3.0.0

  # D-G.6: MIDI hosting via flutter_midi_command.
  # Supports USB OTG on Android and CoreMIDI on iOS.
  flutter_midi_command: ^0.4.5

  # Persistent outbox queue: cells queued locally during WSS loss.
  sqflite: ^2.4.0
  sqflite_common: ^2.5.4
  path: ^1.9.0
  path_provider: ^2.1.0
  uuid: ^4.5.0

  # Fonts: Geist, Geist Mono, Instrument Serif via Google Fonts.
  google_fonts: ^6.2.1

  # Local FFI plugin (kernel + adapters) — same path dep as oddjobz-mobile.
  semantos_ffi:
    path: ../../platforms/flutter/semantos_ffi

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  mocktail: ^1.0.4
  test: ^1.25.0
  sqflite_common_ffi: ^2.3.3

# D-OPS carry-over: record_linux pin from oddjobz-mobile (same resolver bug).
dependency_overrides:
  record_linux: ^1.0.0

flutter:
  uses-material-design: true
  assets:
    - test/fixtures/

```
