---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-G-MOBILE-AND-FLUTTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.780599+00:00
---

# Phase G — Mobile Compression + Flutter Shell

**Version**: 1.0
**Date**: May 2026
**Status**: Draft PRD
**Duration**: 2.5–3 weeks (with 20% buffer: ~3–3.5 weeks)
**Prerequisites**: Phase A merged (`viewportPlan`, `palette`, `labelMode`, `colourForPitch`); Phase B merged (anchor + 3 L2 + support sheet); Phase C merged (`MappingRegistry`, built-in profiles).
**Branch prefix**: `jam-room-g-mobile`
**Master document**: `MASTER.md`

---

## Context

The Loom is renderer-agnostic by construction (textbook 17b §17b.1).
`apps/oddjobz-mobile/` already pairs with `runtime/semantos-brain` over WSS,
subscribes to LoomState, and dispatches LoomActions through the
broker (recent commits: `bf8382e` per-tenant theming, `eac5808`
multi-hat helm sessions, `7b860bc` REPL event stream). The
architecture is shaped to host another adapter; what's missing for
the jam-room is the actual responsive web layout *and* a Flutter
shell that can host MIDI controllers on iPhone (Safari has no Web
MIDI API, so a browser-only iOS jam-room cannot accept a USB or BLE
MIDI controller — Flutter is the only path).

Phase G ships two adapters in parallel:

1. **Responsive web layout** for the existing
   `apps/world-apps/jam-room/` that respects Phase A's `viewportPlan`.
2. **`apps/world-apps/jam-room-mobile/`** — a Flutter app modelled on
   `apps/oddjobz-mobile/` that pairs with `runtime/semantos-brain` over WSS,
   renders L1 + L2 natively, and hosts MIDI controllers via
   platform-specific plugins.

This phase folds in:

- [`design/CSD-COMPRESSION-GRADIENT.md`](./design/CSD-COMPRESSION-GRADIENT.md)
  — the peel-from-bottom rule and three default plans.
- [`design/MOBILE-AND-FLUTTER-SHELL.md`](./design/MOBILE-AND-FLUTTER-SHELL.md)
  — the controller-on-phone matrix and the Flutter scaffold.

### What this phase is not

- Not new musical functionality. All cells, racks, modes, and engines
  already exist before Phase G starts.
- Not a marketplace or app-store distribution flow. Phase G ships a
  buildable Flutter project; signing / store deployment is downstream
  ops.
- Not XR.
- Not BEAM-side work. The CellRelay protocol is unchanged.

---

## Architecture

### G.1 The two adapters

```
┌──────────────────────────────────────────────────────────┐
│                       jam.room (BEAM)                    │
│                  cell_relay region authority              │
└────────────────────┬─────────────────────────────────────┘
                     │ WSS — same channel, same cells
        ┌────────────┼────────────┬────────────────────┐
        │            │            │                    │
┌───────▼──────┐ ┌───▼─────────┐ ┌▼──────────────┐ ┌───▼────────────┐
│ Desktop      │ │ Tablet web  │ │ Android Flutter│ │ iOS Flutter    │
│ jam-room     │ │ jam-room    │ │ jam-room-mobile│ │ jam-room-mobile│
│ (full)       │ │ (compressed)│ │ (L1+L2 native) │ │ (L1+L2 native) │
│              │ │             │ │ + USB MIDI     │ │ + CoreMIDI     │
└──────────────┘ └─────────────┘ └────────────────┘ └────────────────┘
```

Same LoomState. Same JamRack registry. Same `jam.*` cells. Same rooms.

### G.2 Responsive web layout

The existing browser app reads the active `viewportPlan` at boot and
on resize, and chooses a layout class:

```ts
// new src/ui/viewport-plan.ts (built in this phase)

export function pickViewportPlan(): ViewportPlan {
  const w = window.innerWidth;
  if (w <= 600)  return mobilePlan;
  if (w <= 1024) return tabletPlan;
  return desktopPlan;
}

export function applyViewportPlan(plan: ViewportPlan): void {
  document.documentElement.dataset.viewport = plan.placements.anchor === 'hero'
    ? 'mobile' : plan.placements.active === 'tab-row' ? 'tablet' : 'desktop';
  // Re-mount cards into the placements named by the plan.
}
```

The card-pool layout system already exists (Phase B's anchor /
mode-row / support-sheet cards); this phase adds the routing logic
that decides where each card lands per plan.

CSS uses `[data-viewport="mobile"]` / `[data-viewport="tablet"]` /
`[data-viewport="desktop"]` selectors. No CSS-in-JS or runtime
re-style.

### G.3 Flutter shell — `jam-room-mobile`

Mirrors `apps/oddjobz-mobile/` structure:

```
apps/world-apps/jam-room-mobile/
├── lib/
│   ├── main.dart
│   └── src/
│       ├── app.dart
│       ├── pairing/
│       │   ├── claim_request.dart
│       │   └── decode_token.dart
│       ├── jam/
│       │   ├── home_screen.dart           // L1 anchor card
│       │   ├── rack_tab_bar.dart          // L2 bottom tabs
│       │   ├── support_sheet.dart         // L3 bottom sheet
│       │   ├── note_mode_widget.dart      // pads w/ scale colour
│       │   └── mix_peek_widget.dart
│       ├── midi/
│       │   ├── midi_host.dart             // flutter_midi_command wrapper
│       │   └── controller_detection.dart
│       ├── repl/
│       │   └── jam_event_stream.dart      // mirrors helm_event_stream
│       └── theme/
│           └── theme_service.dart         // reuses oddjobz pattern
├── android/
├── ios/
├── pubspec.yaml
└── README.md
```

Pairing flow reuses the QR-code claim-request pattern from
`apps/oddjobz-mobile/lib/src/pairing/`. Theming reuses
`theme_service.dart`. Event stream mirrors
`apps/oddjobz-mobile/lib/src/repl/helm_event_stream.dart` but
subscribes to `room:{roomId}:state` instead of helm channels.

### G.4 MIDI hosting on phone

Two plugins:

- **Android**: `flutter_midi_command` — supports USB OTG (a connected
  MPK49 / Launchpad / Circuit appears as a MIDI port) and BLE-MIDI
  (advertised devices auto-pair).
- **iOS**: same plugin uses CoreMIDI under the hood; CoreMIDI handles
  Lightning / USB-C MIDI accessories and BLE-MIDI.

The detected MIDI ports are converted to `DeviceEvent`s and routed
through the same Phase C `MappingRegistry` JSON profiles. A profile
saved on a desktop room (e.g. an MPK49 mapping forked from the
built-in) installs unchanged on the Flutter shell — same JSON, same
behaviour.

### G.5 Phone-as-controller (the inverse path)

For users on iPhone Safari (no Web MIDI), or for any user wanting to
augment a desktop room with their phone, the existing `phone.ts`
profile from Phase C drives a remote desktop room over WS. Phase G
extends Phase C's phone adapter with:

- Multi-touch grid (up to 10 touches).
- Tilt → XY (gyroscope).
- Accelerometer → macro 7 (chaos).
- Gyroscope → macro 6 (body).
- Three-finger-tap → `jam.gesture { kind: 'propose' }`.

This works on **any phone browser, including iPhone Safari**, because
it doesn't require Web MIDI — only DeviceMotion / DeviceOrientation /
PointerEvents, all of which iOS Safari supports (with a one-time
permission prompt on iOS 13+).

### G.6 Cross-renderer determinism

The same room state must produce the same Loom projection regardless
of which renderer connects. A multi-renderer test fixture asserts
this:

- Boot a room.
- Connect a desktop browser and a Flutter shell to the same room.
- Both subscribers receive the same cell stream.
- Both render the same `jam.scene` as the L1 anchor.
- A pad press on the Flutter shell shows up in the desktop's session
  view via the cell stream.

### G.7 Bundle and battery budgets

| Constraint                                | Budget                                                  |
| ----------------------------------------- | ------------------------------------------------------- |
| Mobile web bundle (default boot, no Three.js) | ≤ 350 KB minified + gzipped                          |
| Flutter app size on Android (release)     | ≤ 25 MB APK                                             |
| Flutter app size on iOS (release)         | ≤ 35 MB IPA                                             |
| Battery drain in a 60-min room session    | ≤ 8% on a 2023 mid-tier Android; ≤ 6% on iPhone 13     |
| Audio glitch rate at home WiFi            | < 1 audible glitch per 10 minutes                       |

The budgets are enforced via:

- `scripts/audit-bundle.ts` extends from Phase D to also report
  mobile-plan boot bundle (Three.js excluded).
- `scripts/audit-flutter-build.sh` reports release artefact sizes.
- `scripts/audit-battery.sh` runs a synthetic 60-min loopback session.

---

## Deliverables

### D-G.1 — Responsive web layout

- `src/ui/viewport-plan.ts` — `pickViewportPlan()` and
  `applyViewportPlan()`.
- CSS updates under `style.css` or `responsive.css` honouring
  `[data-viewport]`.
- Mobile-plan: anchor row pinned top; mode row as bottom tab bar;
  support sheet from right edge; Three.js canvas not mounted.
- Tablet-plan: anchor row pinned top; mode row as inline tab row;
  support sheet from right edge; Three.js canvas degrades to 2D
  session view (Phase E gate clause).
- Desktop-plan: unchanged behaviour from Phase B.

### D-G.2 — `apps/world-apps/jam-room-mobile/` scaffold

- Flutter app structure per §G.3.
- `pubspec.yaml` lists `flutter_midi_command`, `web_socket_channel`,
  `qr_code_scanner`, and the same theming / pairing dependencies as
  `apps/oddjobz-mobile/`.
- `scripts/build-android-libs.sh` extended (or duplicated) for
  jam-room-mobile artefacts.
- iOS build configuration mirroring `apps/oddjobz-mobile/ios/`.

### D-G.3 — Pairing + WSS subscription

- QR-code-based claim flow ported from
  `apps/oddjobz-mobile/lib/src/pairing/`.
- `jam_event_stream.dart` subscribing to room state and dispatching
  `LoomAction`s via the broker.
- Reconnect logic: cells queued locally during loss; replayed on
  reconnect.

### D-G.4 — L1 anchor card + L2 tab bar + support sheet

- `home_screen.dart` renders the L1 anchor card (loop orb pulse +
  scene name + clock dial).
- `rack_tab_bar.dart` renders three Material bottom tabs
  (Rhythm/Melody/Bass) with cycle-dot indicator.
- `support_sheet.dart` modal bottom sheet with five entries
  (Sequencer/Mix/Session/Arrange/Custom).
- Custom is enabled (Phase C is a prerequisite for G).

### D-G.5 — Note mode + scale colour on Flutter

- `note_mode_widget.dart` ports the colour-channel rendering from
  Phase B.
- The scale-colour function is duplicated in Dart from Phase A's
  TypeScript module (same algorithm, same snapshots — both are
  tested against the same matrix file in JSON).
- `tests/scale_colour_parity_test.dart` asserts identical output for
  100+ pitch/scale/root combinations.

### D-G.6 — MIDI hosting on phone

- `midi/midi_host.dart` wraps `flutter_midi_command`.
- `midi/controller_detection.dart` watches for new ports and applies
  the matching Phase C profile.
- The profile JSON imported from the cell-relay is unchanged from the
  desktop format.

### D-G.7 — Phone-as-controller extensions to Phase C

- Update `apps/world-apps/jam-room/src/mappings/profiles/phone.ts`
  to add gyroscope + multi-touch grid + three-finger-tap.
- iOS DeviceMotion permission prompt handled on first activation.
- The web client used by the phone is the existing
  `apps/world-apps/jam-room/` running mobile-plan; no separate app.

### D-G.8 — Cross-renderer test fixture

- `tests/cross-renderer.test.ts` (web side) and
  `tests/cross_renderer_test.dart` (Flutter side) cooperatively
  assert that the same cells produce the same projections.
- A CI job spawns a headless desktop browser and a Flutter test
  driver against a shared room and checks parity.

### D-G.9 — Bundle + battery audits

- `scripts/audit-bundle.ts` reports mobile-plan boot bundle size and
  asserts ≤ 350 KB.
- `scripts/audit-flutter-build.sh` runs release builds and asserts
  artefact sizes.
- `scripts/audit-battery.sh` runs a 60-min loopback fixture and
  reports battery drain on attached test devices (informational, not
  CI-gating).

### D-G.10 — Documentation

- `docs/operator-runbooks/jam-room-mobile-build-and-pair.md`
  modelled on `docs/operator-runbooks/mobile-build-and-pair.md`.
- `apps/world-apps/jam-room-mobile/README.md` with build / pair /
  troubleshoot sections.

### D-G.11 — Phase G gate test

`apps/world-apps/jam-room/__tests__/phase-g-gate.test.ts` (web side):

- Responsive layout at 1440 / 1024 / 768 / 414 viewport widths
  matches `viewportPlan` placements.
- Mobile-plan boot does not load the Three.js bundle.
- `phone.ts` profile gyroscope + accelerometer routes correctly.
- Bundle audit passes.

`apps/world-apps/jam-room-mobile/test/phase_g_gate_test.dart`
(Flutter side):

- App pairs with a mock BRAIN endpoint, receives a `jam.scene.launch`
  cell, and updates the L1 anchor card.
- A simulated USB MIDI controller routes through the registry.
- Scale-colour parity test passes.
- L2 tab bar and support sheet render correctly.

All prior phase gates (A/B/C/D/E/F) re-run and pass.

---

## Gate tests (commands)

```bash
# Web side
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-g-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
node scripts/audit-bundle.ts

# Flutter side
cd apps/world-apps/jam-room-mobile
flutter analyze
flutter test
flutter build apk --release  --target-platform android-arm64
flutter build ios --release  --no-codesign
bash ../../../scripts/audit-flutter-build.sh
```

---

## Completion criteria

1. Responsive web layout at 1440 / 1024 / 768 / 414 viewport widths
   matches `viewportPlan` placements with no broken UI.
2. Mobile-plan boot bundle ≤ 350 KB; Three.js excluded; Flutter
   artefacts under their budgets.
3. Flutter shell pairs with `runtime/semantos-brain` over WSS using the same QR
   flow as `oddjobz-mobile`.
4. Same cells flow through the desktop browser and the Flutter shell;
   cross-renderer parity test green.
5. iPhone Flutter shell hosts a USB / BLE MIDI controller via
   CoreMIDI; the Phase C profile JSON is unchanged from desktop.
6. Phone-as-controller (web) works on iPhone Safari with the
   gyroscope + multi-touch + three-finger-tap extensions.
7. Phase A/B/C/D/E/F/G gate tests all pass.

---

## Risks & mitigations

| Risk                                                                  | Mitigation                                                                                                |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Scale-colour algorithm drifts between TS and Dart                      | Both are tested against a shared JSON snapshot matrix; CI runs both test suites on the same file.        |
| Flutter app size blows the budget                                      | `flutter_midi_command` is the only large dep; trim the alternative-palette assets if needed.              |
| iOS MIDI behaves differently from Android                              | Profile JSON is identical; abstract differences in `midi_host.dart` not in the profile.                   |
| Cross-renderer parity test is flaky on CI                              | Use deterministic mock cell streams; no real audio in the parity test.                                    |
| Battery drain on long sessions                                         | Audio session priority + wake-lock on; expose a "low battery — degrade visuals" toggle on the anchor card.|
| App store review for jam-room-mobile                                   | Out of scope for Phase G; Phase G ships a buildable artefact, not a published app.                        |

---

## Non-goals

- No app-store deployment automation.
- No native macOS / Windows / Linux Flutter targets (web + Android +
  iOS only).
- No XR / VR shells.
- No new musical primitives.
- No BEAM-side protocol changes.

---

## Parallelism note

Phase G is the most parallelism-friendly phase. The five workstreams
can run concurrently after pairing scaffold (D-G.3) lands:

1. Responsive web layout (D-G.1) — pure CSS / layout JS work.
2. Flutter scaffold + L1+L2 widgets (D-G.2 + D-G.4) — Dart only.
3. Scale-colour parity (D-G.5) — algorithm port, easily testable.
4. MIDI hosting (D-G.6) — plugin integration; can land last.
5. Phone-as-controller extensions to Phase C (D-G.7) — small TS
   patch.

Designers can iterate the L1 anchor visual against `mobilePlan`
fixture data from Phase A while system work on D-G.1 and D-G.4
proceeds. The whole phase is designed so UI and system can move in
parallel.
