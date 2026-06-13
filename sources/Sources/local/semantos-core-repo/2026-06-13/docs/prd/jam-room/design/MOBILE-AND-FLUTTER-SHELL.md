---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/design/MOBILE-AND-FLUTTER-SHELL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.782916+00:00
---

# Mobile + Flutter Shell — Phase G Proposal

**Status**: Draft v0.1 — for design polish
**Audience**: Claude Design / a human designer
**Reads with**: [CSD-COMPRESSION-GRADIENT.md](./CSD-COMPRESSION-GRADIENT.md), `apps/oddjobz-mobile/`

---

## The question

How do we land the jam-room on a phone such that:

1. The same `jam.world` and `LoomState` drive the mobile renderer the
   same way they drive the desktop browser.
2. A user can hook up an external MIDI controller (MPK49, Launchpad,
   Circuit) to a phone and have it work through the existing Phase C
   mapping pipeline.
3. The mobile experience is honest about Conscious Stack discipline —
   L1 + L2 only on the home view, L3 in a sheet, L4 invisible.

---

## The proposal — Phase G

A new phase that ships two things:

### 1. Responsive web layout for `apps/world-apps/jam-room/`

The browser-side jam-room respects `viewportPlan` (introduced in
[CSD-COMPRESSION-GRADIENT.md](./CSD-COMPRESSION-GRADIENT.md)). On
narrow viewports the workbench layout collapses from
`rack-main + rack-side` to a single-column anchor + L2 + sheet.

This works on **Android Chrome** (full Web MIDI + Web Bluetooth +
gamepad) but not Safari iOS for any USB MIDI use case.

### 2. `apps/world-apps/jam-room-mobile/` — Flutter shell

A Flutter app modelled on `apps/oddjobz-mobile/` that:

- Pairs with `runtime/semantos-brain` over WSS the same way `oddjobz-mobile`
  does (`helm_event_stream`, `repl-client`).
- Subscribes to the same `LoomState` projection and dispatches
  `LoomAction`s through the broker.
- Renders L1 + L2 natively (anchor card + bottom 3-tab bar).
- Hosts MIDI controllers via `flutter_midi_command` (USB OTG on
  Android; CoreMIDI on iOS).
- Supports BLE-MIDI on both platforms.

This is the only path that lets an iPhone host a wired MIDI
controller — Safari has no Web MIDI API.

---

## Controller-on-phone matrix

| Phone path                          | USB MIDI       | BLE MIDI    | Web MIDI    | Notes |
| ----------------------------------- | -------------- | ----------- | ----------- | ----- |
| **Android browser (Chrome)**        | ✓ (USB OTG)    | ✓           | ✓           | Best web story; OTG cable required |
| **Android Flutter (jam-room-mobile)**| ✓ via plugin  | ✓           | n/a (native)| `flutter_midi_command` |
| **iOS Safari**                      | ✗              | ✗           | **✗**       | Hard wall — no Web MIDI on Safari |
| **iOS Flutter (jam-room-mobile)**   | ✓ via CoreMIDI plugin | ✓    | n/a (native)| Only iOS path that hosts a controller |
| **iOS Web (PWA in Safari)**         | ✗              | ✗           | ✗           | No improvement |

So the iPhone story is **Flutter shell only** for hosting controllers.
Browser-only iPhone users can still drive a desktop room from their
phone (phone-as-controller via touch / gyro / accelerometer).

### Phone-as-controller (the inverse)

Phase C's `phone.ts` profile uses XY pad + accelerometer-driven macro
7 (chaos). That works in any browser on either OS. So even on iPhone
Safari, the phone *itself* can drive a remote desktop jam-room:
multi-touch grid, tilt-to-XY, three-finger-tap as `jam.gesture`.

The gap is the gyroscope / accelerometer device adapter; that's a
small addition to D-C.2 (Phase C device adapters).

---

## Architecture sketch

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
└───────┬──────┘ └─────┬───────┘ └────────┬───────┘ └────────┬───────┘
        │              │                  │                  │
        │              │                  │                  │
        └──────────────┴──────────────────┴──────────────────┘
                  Same LoomState, same JamRack registry,
                  same jam.* cells, same rooms.
```

The Loom is the warp; renderers are interchangeable shuttles. Phase G
ships two new renderer adapters: a responsive web variant and a
Flutter native variant.

---

## Phase G deliverables (sketch)

### D-G.1 — Responsive web layout

- `apps/world-apps/jam-room/src/ui/viewport-plan.ts` — picks
  desktop / tablet / mobile plan from viewport size.
- CSS / layout updates under `style.css` or a new
  `responsive.css` that respects the plan.
- Phase E three-room canvas hidden on mobile; degrades to 2D session
  view on tablet.
- Phase B mode row revised per
  [MODE-ROW-REVISION.md](./MODE-ROW-REVISION.md).

### D-G.2 — `apps/world-apps/jam-room-mobile/` Flutter shell

- Scaffold the app following `apps/oddjobz-mobile/` structure.
- Pair with BRAIN over WSS using the existing `helm_event_stream` pattern.
- Subscribe to the room's `LoomState` projection.
- Dispatch `LoomAction`s through the broker.
- Implement the L1 anchor card + L2 bottom-tab navigation.

### D-G.3 — Phone MIDI hosting

- `flutter_midi_command` integration (Android USB OTG + BLE; iOS
  CoreMIDI + BLE).
- Profiles imported from the existing Phase C built-ins
  (`mpk49`, `launchpad`, `circuit`, etc.) — same JSON shape, native
  delivery.

### D-G.4 — Phone-as-controller (inverse)

- Touch grid + accelerometer + gyroscope adapter.
- A `phone-with-room` profile in Phase C that maps tilt/touch to
  `jam.gesture` and rack macros.

### D-G.5 — Cross-renderer test fixture

- A test harness that boots the same room state and asserts the same
  `jam.*` cells flow regardless of which renderer is connected.
- Multi-renderer smoke test: a laptop + a phone in the same room
  produce identical Loom state.

### D-G.6 — Documentation

- `docs/operator-runbooks/jam-room-mobile-build-and-pair.md`
  modelled on `docs/operator-runbooks/mobile-build-and-pair.md`
  (which already exists for `oddjobz-mobile`).

### D-G.7 — Phase G gate test

- Responsive web layout gate: at 1440 / 1024 / 768 / 414 viewport
  widths the anchor row, L2 buttons, and support sheet positions
  match `viewportPlan`.
- Flutter shell gate: pairs with BRAIN, receives a `jam.scene.launch`
  cell, displays the scene name in the anchor card.
- MIDI host gate: a synthetic MIDI controller events route through
  the Phase C mapping registry on the Flutter shell.

---

## Why mirror `oddjobz-mobile`

`apps/oddjobz-mobile/` already pairs with `runtime/semantos-brain`, theming
(`bf8382e`), hat-switching (`eac5808`), and the REPL event stream
(`7b860bc`). The Loom architecture is renderer-agnostic by
construction; the Flutter shell is just another adapter. Mirroring
the existing structure means:

- Same pairing flow (`pairing/claim_request.dart`,
  `pairing/decode_token.dart`).
- Same theming service (`theme/theme_service.dart`).
- Same event stream wiring (`repl/helm_event_stream.dart`).
- Same Android cross-compile script (`scripts/build-android-libs.sh`).
- Same iOS path (Flutter handles).

The only jam-room-specific pieces are the L1 anchor widget, the L2
bottom-tab bar, the support sheet, and the MIDI hosting adapter.

---

## Open questions for design polish

`TODO(design)`:

1. **Anchor card visual.** What does the L1 anchor card look like on a
   phone? Loop orb pulse? Scene name + clock dial? A waveform? A
   pulsing colour bar? Whatever it is, it's the *one* thing that has
   to be unambiguous in 200 ms.
2. **Bottom tab bar styling.** Three icons at thumb height. iOS HIG
   vs Material 3 — pick one and commit. Android Flutter typically
   uses Material; iOS Flutter can use Cupertino. Probably uniform
   Material with subtle platform tweaks.
3. **Pairing UX.** The first-time pairing of a Flutter app to a room
   has a rough edge in `oddjobz-mobile`. The jam-room version should
   feel like "scan a QR code from the desktop room" — fast and
   unceremonious.
4. **MIDI controller confirmation.** When a controller is detected
   on Android, what does the user see? A toast? A modal? The CSD
   answer is "as little as possible" — probably a transient toast
   plus a tab-bar badge.
5. **Battery and CPU on long jams.** A phone running audio + MIDI +
   WebSocket for 60 minutes at home volume needs to not drain the
   battery. Wake lock + audio session priority. This is engineering
   not design, but it's a design constraint (warning UI when battery
   is low).
6. **Offline / lossy network.** The phone leaves wifi for 10 seconds.
   What does the L1 anchor say? Probably a small "reconnecting" badge
   with cells queued locally; existing cell-relay reconnect logic
   covers this on the wire.
7. **Multi-window on tablet.** A tablet user in landscape might want
   the room *and* a chat side-by-side. Out of scope for v1 but worth
   not actively breaking.

---

## Coda

The pyramid is portable. The Loom is portable. The cells are portable.
Phase G is mostly *connecting things that already exist on different
sides of the same protocol*. The hard part is the design discipline
that makes the L1 anchor read in 200 ms on a 414-pixel-wide screen.
