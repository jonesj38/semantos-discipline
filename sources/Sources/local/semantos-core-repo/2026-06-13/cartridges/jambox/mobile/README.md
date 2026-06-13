---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.578667+00:00
---

# jam-room-mobile

Flutter shell for the Jam Room world application.  Phase G (D-G.2 – D-G.11).

Pairs with a running `brain` node over WSS (same BRC-42 pairing flow as
`oddjobz-mobile`), subscribes to `room:{roomId}:state`, and renders the
CSD Conscious Stack 1-3-5-3-1 compression gradient at L1+L2.

---

## Architecture

```
lib/
  main.dart                  — entry point
  src/
    app.dart                 — auth-gated router (pair vs home)
    jam/
      home_screen.dart       — L1 anchor card + L2 tab bar host
      rack_tab_bar.dart      — bottom nav: Rhythm / Melody / Bass
      support_sheet.dart     — L3 draggable bottom sheet (5 entries)
      note_mode_widget.dart  — 4×8 scale-colour pad grid
      mix_peek_widget.dart   — 4-channel fader strip
      pairing_screen.dart    — QR scanner + paste-token fallback
    repl/
      jam_event_stream.dart  — WSS JSON-RPC subscriber + reconnect
    colour/
      scale_colour.dart      — Dart port of colourForPitch (D-G.5)
    midi/
      midi_host.dart         — flutter_midi_command wrapper
      controller_detection.dart — device profile resolver
    identity/                — BRC-42 identity layer (from oddjobz-mobile)
    pairing/                 — pairing flow (from oddjobz-mobile)
    theme/                   — theme service (from oddjobz-mobile)
```

## Quick start

```bash
cd apps/world-apps/jam-room-mobile
flutter pub get
flutter run
```

Run tests:
```bash
flutter test
flutter test test/scale_colour_parity_test.dart  # requires parity fixture
```

Generate the parity fixture first (from the jam-room web package):
```bash
pnpm -C apps/world-apps/jam-room run gen-parity
```

## Key contracts

- **No new `jam.*` cell families** — uses existing cells from Phase A vocab.
- **Profile JSON is portable** — `phone.ts` has no Dart-specific fields.
- **Three.js never loads on mobile** — enforced by `mobilePlan.surfacedLayers`.
- **Scale-colour parity** — Dart output matches TypeScript byte-for-byte.

## Pairing

Uses the same `brain device pair` flow as `oddjobz-mobile` (BRC-42 v2).
See `docs/operator-runbooks/jam-room-mobile-build-and-pair.md`.

## Supported platforms

- Android (API 21+, arm64-v8a / armeabi-v7a / x86_64)
- iOS (13+, CoreMIDI)
