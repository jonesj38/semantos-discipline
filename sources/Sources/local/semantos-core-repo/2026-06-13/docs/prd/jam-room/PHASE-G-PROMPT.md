---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-G-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.780055+00:00
---

# Phase G Execution Prompt — Mobile Compression + Flutter Shell

> Paste this prompt into a fresh session to execute Phase G.

## Context

You are working in the `semantos-core` repo. Phases A through F are
merged: the jam-room has its full semantic vocabulary, JamRack
contract, four default WebAudio racks, the anchor + 3 L2 + support
sheet UI, BYO mappings with eight built-in profiles, Strudel /
PureData / external MIDI engines, the interactive 3D room (desktop
only), and take capture / contributions / lineage.

Phase G is the **portability phase**. Two adapters ship:

1. A responsive web layout for `apps/world-apps/jam-room/` that
   honours Phase A's `viewportPlan` and degrades the Three.js canvas
   on tablet (2D fallback) and mobile (hidden).
2. `apps/world-apps/jam-room-mobile/` — a Flutter app modelled on
   `apps/oddjobz-mobile/` that pairs with `runtime/semantos-brain` over WSS,
   subscribes to LoomState, dispatches LoomActions through the
   broker, renders L1 + L2 natively, and hosts MIDI controllers via
   `flutter_midi_command` (USB OTG on Android; CoreMIDI on iOS).

After this phase, an iPhone user can connect an MPK49 over Lightning,
open the Flutter app, scan a room QR code, and drive the same
`jam.rack.poly-keys` keys their desktop friend is playing. The
profile JSON is unchanged.

---

## CRITICAL: READ THESE FILES FIRST

**Read first** (the PRD and design notes):

- `docs/prd/jam-room/PHASE-G-MOBILE-AND-FLUTTER.md` — Phase G spec
  with two-adapter architecture (§G.1), responsive web layout (§G.2),
  Flutter shell structure (§G.3), MIDI hosting (§G.4),
  phone-as-controller (§G.5), cross-renderer determinism (§G.6),
  bundle/battery budgets (§G.7), deliverables D-G.1–D-G.11.
- `docs/prd/jam-room/design/CSD-COMPRESSION-GRADIENT.md` — The
  compression rule and three default plans.
- `docs/prd/jam-room/design/MOBILE-AND-FLUTTER-SHELL.md` —
  Controller-on-phone matrix and Flutter scaffold rationale.
- `docs/prd/jam-room/design/COLOUR-AS-DIMENSION.md` — The colour
  algorithm Phase G's Flutter shell ports to Dart.
- `docs/prd/jam-room/MASTER.md` — Cross-cutting context.

**Read second** (the Flutter template you mirror):

- `apps/oddjobz-mobile/lib/main.dart` — Entry point.
- `apps/oddjobz-mobile/lib/src/app.dart` — App shell pattern.
- `apps/oddjobz-mobile/lib/src/pairing/claim_request.dart` and
  `decode_token.dart` — QR-code pairing flow you reuse.
- `apps/oddjobz-mobile/lib/src/repl/helm_event_stream.dart` — The
  WSS subscription pattern; `jam_event_stream.dart` mirrors this.
- `apps/oddjobz-mobile/lib/src/theme/theme_service.dart` — Theming
  service you reuse.
- `apps/oddjobz-mobile/pubspec.yaml` — Dependency baseline.
- `apps/oddjobz-mobile/scripts/build-android-libs.sh` — Cross-compile
  pattern.
- `docs/operator-runbooks/mobile-build-and-pair.md` — Operator runbook
  pattern; `jam-room-mobile-build-and-pair.md` mirrors it.

**Read third** (the existing web jam-room you make responsive):

- `apps/world-apps/jam-room/index.html` — Card pool layout. You add
  the mobile-plan / tablet-plan / desktop-plan routing.
- `apps/world-apps/jam-room/style.css` — Existing CSS. Mobile-plan
  styles attach via `[data-viewport="mobile"]`.
- `apps/world-apps/jam-room/src/world/viewport-plans.ts` (Phase A) —
  Three default plans you read.
- `apps/world-apps/jam-room/src/colour/scale-colour.ts` (Phase A) —
  Algorithm you port to Dart.
- `apps/world-apps/jam-room/src/three/jambox-world.ts` (Phase E) —
  Dynamic-import gated on `viewportPlan.surfacedLayers.includes('L4')`.
- `apps/world-apps/jam-room/src/mappings/profiles/phone.ts` (Phase C)
  — You extend with gyroscope + multi-touch + three-finger-tap.

**Read fourth** (Loom + BRAIN plumbing):

- `runtime/services/src/services/loom/` — `loomStateAtom`,
  `loomReducer`, action union. The Flutter shell subscribes through
  the broker the same way the Helm SPA does.
- `runtime/semantos-brain/src/repl.zig` — REPL endpoint; jam-room-mobile pairs
  through the same `info_http` device-pair flow `oddjobz-mobile`
  uses.
- `packages/cell-relay/src/types.ts` — Cell envelope shape.

**Read fifth** (branching and CI):

- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `jam-room-g-mobile`,
  commits as `jam-room-g/D-G.{N}: ...`. Gate tests under
  `apps/world-apps/jam-room/__tests__/phase-g-gate.test.ts` and
  `apps/world-apps/jam-room-mobile/test/phase_g_gate_test.dart`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. SAME CELLS, SAME ROOM, ALL RENDERERS

The cell-relay protocol is unchanged. The Flutter shell receives the
same `jam.*` cells the desktop browser receives. Adapters parse and
render; they do not author new cell families.

### 2. SCALE-COLOUR PARITY OR THE GATE FAILS

The Dart port of `colourForPitch` is tested against the same JSON
snapshot matrix as the TypeScript original. If a snapshot disagrees,
the gate fails. **Both implementations are bugs of the same algorithm
or the algorithm is wrong** — pick one source of truth and keep them
in lockstep.

### 3. NO NEW MUSICAL PRIMITIVES

You will be tempted to add a new `jam.*` kind for "phone-only" things.
Don't. The phone is just another surfaceShape. The cells flow
unchanged.

### 4. iPHONE SAFARI HAS NO WEB MIDI

Don't pretend you can polyfill it. Phone-as-controller (the inverse
path) works on Safari because it uses DeviceMotion / DeviceOrientation
/ PointerEvents. Hosting a USB MIDI controller from iPhone is a
**Flutter-only path**.

### 5. THREE.JS BUNDLE NEVER LOADS ON MOBILE-PLAN

The Three.js entry is a dynamic import gated on
`viewportPlan.surfacedLayers.includes('L4')`. On mobile-plan, the
gate is false and the module never loads. The bundle audit
(D-G.9) enforces this with a hard size assertion.

### 6. PROFILE JSON IS PORTABLE

A profile saved on a desktop room (e.g. an MPK49 mapping) installs
unchanged on the Flutter shell. The Dart-side parser reads the same
JSON shape the TypeScript parser reads. **Do not add Dart-specific
fields.**

### 7. PAIRING REUSES THE EXISTING BRAIN FLOW

`oddjobz-mobile` already pairs with `runtime/semantos-brain` via the
device-pair HTTP endpoint. Reuse it. Do not invent a second pairing
protocol.

### 8. NO APP-STORE PLUMBING

Phase G ships a buildable artefact, not a published app. No
fastlane configs, no signing automation, no store metadata. That's
downstream ops.

---

## Deliverable mapping

| ID     | File(s) you create or change                                                       |
| ------ | ---------------------------------------------------------------------------------- |
| D-G.1  | `apps/world-apps/jam-room/src/ui/viewport-plan.ts`; CSS updates under `style.css`  |
| D-G.2  | `apps/world-apps/jam-room-mobile/` scaffold per §G.3                               |
| D-G.3  | `lib/src/pairing/`, `lib/src/repl/jam_event_stream.dart`                           |
| D-G.4  | `lib/src/jam/{home_screen,rack_tab_bar,support_sheet}.dart`                        |
| D-G.5  | `lib/src/jam/note_mode_widget.dart`; Dart port of `colourForPitch`; parity test    |
| D-G.6  | `lib/src/midi/{midi_host,controller_detection}.dart`                               |
| D-G.7  | Update `apps/world-apps/jam-room/src/mappings/profiles/phone.ts`                   |
| D-G.8  | `tests/cross-renderer.test.ts` + `test/cross_renderer_test.dart`                   |
| D-G.9  | `scripts/audit-bundle.ts` extension; `scripts/audit-flutter-build.sh`              |
| D-G.10 | `docs/operator-runbooks/jam-room-mobile-build-and-pair.md`; mobile app `README.md` |
| D-G.11 | `__tests__/phase-g-gate.test.ts` (web); `test/phase_g_gate_test.dart` (Flutter)    |

---

## Gate test commands

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
flutter build apk --release --target-platform android-arm64
flutter build ios --release --no-codesign
bash ../../../scripts/audit-flutter-build.sh
```

All prior phase gates must continue to pass.

---

## Branching

```bash
git checkout main
git pull
git checkout -b jam-room-g-mobile
```

Commit prefix: `jam-room-g/D-G.{N}: <description>`.
On gate-green merge: tag `jam-room-v0.9.0`.

---

## Definition of done

1. Responsive web layout at 1440 / 1024 / 768 / 414 widths matches
   `viewportPlan` placements.
2. Mobile-plan boot bundle ≤ 350 KB; Three.js bundle never loads.
3. `apps/world-apps/jam-room-mobile/` builds on Android (APK) and iOS
   (unsigned IPA) under their budgets.
4. Flutter shell pairs with `runtime/semantos-brain` via the existing QR-code
   device-pair flow.
5. Same cell stream produces parity-equivalent state on the desktop
   browser and the Flutter shell (cross-renderer test green).
6. Scale-colour Dart port is byte-identical to the TS source on the
   shared snapshot matrix.
7. iPhone Flutter shell hosts a USB / BLE MIDI controller via
   CoreMIDI; profile JSON unchanged from desktop.
8. Phone-as-controller (web) works on iPhone Safari with gyroscope +
   multi-touch + three-finger-tap.
9. Operator runbook + mobile-app README published.
10. Phase A/B/C/D/E/F/G gate tests all pass.

---

## What to **not** do

- Don't add new cell families.
- Don't pretend Safari has Web MIDI.
- Don't load Three.js on mobile.
- Don't add Dart-specific fields to profile JSON.
- Don't invent a second pairing protocol; reuse `runtime/semantos-brain`'s
  device-pair endpoint.
- Don't ship app-store metadata; this phase is build-only.
- Don't drop existing transport panel bindings; they live as a
  "Transport+" support sheet entry per Phase B's revision.
