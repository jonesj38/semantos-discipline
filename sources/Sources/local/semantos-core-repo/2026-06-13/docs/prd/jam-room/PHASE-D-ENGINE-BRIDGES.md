---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-D-ENGINE-BRIDGES.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.778451+00:00
---

# Phase D — Engine Bridges: Strudel, PureData, External MIDI

**Version**: 1.0
**Date**: May 2026
**Status**: Draft PRD
**Duration**: 2–3 weeks (with 20% buffer: ~2.5–3.5 weeks)
**Prerequisites**: Phase A merged (`JamRack` contract + 4 default WebAudio racks); Phase B merged (Mix mode targets `jam.rack.macro.set` cells); Phase C optional but desirable for live MIDI controller workflows.
**Branch prefix**: `jam-room-d-engine-bridges`
**Master document**: `MASTER.md`

---

## Context

The brief argues — correctly — that the room's most distinctive
musical asset will be the ability to host engines that aren't
WebAudio. Two engines unlock most of the value:

- **Strudel** — pattern text becomes audible musical logic that's
  versionable, remixable, and explainable.
- **PureData** — modular DSP, granular sampling, weird bass synths,
  custom effects. The thing that turns the room from "another web
  groovebox" into "weird instrument lab".

Both engines must conform to the Phase A `JamRack` contract. That is
the entire point of the contract: the rack interface is engine-blind.
A third deliverable — an external MIDI rack — exercises the contract
against real hardware.

### What this phase is not

- Not a Strudel UI rebuild. Strudel runs as a runtime; the editor
  affordance is one workbench card with a textarea + run button + macro
  knobs. The full Strudel REPL is out of scope.
- Not a PureData IDE. PD patches are loaded as sealed objects; editing
  patches happens outside the room (in PD itself). The bridge is a
  shim, not an editor.
- Not a VST host. Phase F deliberately keeps `jam.rack` engine kinds
  closed; new engines are a future phase decision.

---

## Architecture

### D.1 Engine kinds in scope

```
JamRackEngine = 'webaudio' | 'puredata' | 'strudel' | 'midi' | 'hybrid'
```

Phase A shipped `webaudio`. Phase D adds `puredata`, `strudel`, and
`midi`. The `hybrid` kind is reserved for future racks that wrap two
engines (e.g. Strudel triggering a PureData voice).

### D.2 Strudel rack

```
src/racks/strudel/StrudelRack.ts
```

- Loads the Strudel runtime lazily (dynamic `import()` on first
  instantiation).
- Wraps a single `pattern: string`. The pattern is the rack's primary
  state.
- Macros 0..7 fan out to documented Strudel transforms:

  | Macro       | Strudel transform                                                |
  | ----------- | ---------------------------------------------------------------- |
  | brightness  | `.lpf(...)`                                                      |
  | dirt        | `.coarse(...)` or `.shape(...)`                                  |
  | wobble      | `.lfo(...)` envelope-mod                                          |
  | space       | `.room(...)`                                                     |
  | snap        | `.attack(0)` mix                                                 |
  | body        | `.gain(...)` low-shelf                                           |
  | chaos       | `.degradeBy(...)` + `.jux(rev)` weighted by macro                |
  | tension     | `.lpf(↘)` + `.hpf(↗)` blend                                      |

- `play(JamNoteOn | JamTrigger)` injects a one-shot pattern fragment
  into the running stream.
- Capture (`StrudelRack.captureToPattern(barCount)`) renders the next
  N bars of the pattern into a `jam.pattern` object whose source
  payload references the original Strudel text.

### D.3 PureData rack

```
src/racks/puredata/PureDataRack.ts
```

Two transports are supported:

1. **In-browser**: `libpd-wasm` loaded lazily for patches small enough
   and licensed accordingly. The patch is shipped as a `jam.patch`
   object whose payload has `engine: 'puredata'`.
2. **Remote bridge**: a WebSocket / OSC bridge to a PD daemon
   (`bridge.ts` already exists in `apps/world-apps/jam-room/` for
   prototype use; this phase formalises it). The bridge speaks the
   `[r jam-note]` / `[r jam-trigger]` / `[r jam-clock]` /
   `[r jam-macro-{1..8}]` receiver convention from the brief.

PD patches that conform to the convention are drop-in. A README in
`src/racks/puredata/conventions.md` lists the receiver / sender names.

### D.4 External MIDI rack

```
src/racks/midi/ExternalMidiRack.ts
```

Sends `jam.note.on` / `jam.note.off` / `jam.trigger` to a chosen Web
MIDI output channel. Macros 0..7 map to MIDI CC numbers documented in
`src/racks/midi/cc-map.ts`. Receives MIDI clock and SysEx feedback
where the device supports it.

### D.5 Engine adapter test harness

A single test fixture that takes any `JamRack` implementation and runs
the same conformance suite:

- 8 macros respect `[0,1]` clamping.
- `play()` followed by `stop()` does not leave hanging notes.
- `getState()` round-trips through `setState()`.
- `getMappingHints()` returns at least 8 hints (one per macro).
- Meters return non-NaN, monotonically-non-decreasing during playback.

Phase A's four WebAudio racks must keep passing this harness. The new
Strudel and PureData racks must also pass it. The external MIDI rack
passes a reduced harness that skips meters (devices may not report).

### D.6 Macro fan-out documentation

Each engine ships a `macros.md` next to its source:

- `src/racks/webaudio/macros.md`
- `src/racks/strudel/macros.md`
- `src/racks/puredata/macros.md`
- `src/racks/midi/macros.md`

Each documents the eight musical macro names and the engine-specific
fan-out. Mismatches between docs and code fail the gate test.

### D.7 Lazy load and bundle budget

Engines are dynamic imports. The base bundle (the boot path before any
non-WebAudio rack is touched) must not grow more than 5 KB minified.
The Strudel and libpd-WASM payloads load on first instantiation of a
rack of that kind.

---

## Deliverables

### D-D.1 — `StrudelRack`

- `src/racks/strudel/StrudelRack.ts` implementing `JamRack`.
- Lazy load via `import('@strudel.cycles/core')` (or whichever entry
  the codebase pins; record the choice in a top-of-file comment).
- Pattern textarea card: `data-card="strudel"` in the workbench card
  pool, mounted via `src/ui/strudel-card.ts`.
- Macro fan-out per §D.2.
- `captureToPattern(barCount)` produces a `jam.pattern` with the
  Strudel text in its payload `source`.

### D-D.2 — `PureDataRack`

- `src/racks/puredata/PureDataRack.ts` implementing `JamRack`.
- Two transports: in-browser libpd-wasm and remote OSC bridge.
- Transport choice is per-rack-instance config; default is in-browser
  if the patch's declared bytes are < 1 MB, remote otherwise.
- Receiver/sender naming convention enforced and documented in
  `src/racks/puredata/conventions.md`.
- Reuse `apps/world-apps/jam-room/bridge.ts` as the OSC bridge daemon
  reference.

### D-D.3 — `ExternalMidiRack`

- `src/racks/midi/ExternalMidiRack.ts` implementing `JamRack`.
- CC map in `src/racks/midi/cc-map.ts`.
- Output port chosen via the existing Web MIDI permission flow from
  Phase C device adapters.

### D-D.4 — Engine conformance harness

- `apps/world-apps/jam-room/__tests__/rack-conformance.ts` exporting a
  function `runRackConformance(rack: JamRack, opts?: { skipMeters?: boolean })`.
- Phase D gate runs the harness against all eight rack instances (4
  Phase A + 1 Strudel + 1 PureData + 2 MIDI test instances).

### D-D.5 — Capture-to-pattern

- `StrudelRack.captureToPattern(barCount)` and
  `PureDataRack.captureToPattern(barCount)` produce `jam.pattern`
  objects.
- Captured patterns can be played back through the existing 8×8 grid
  surface (Phase B Drum / Step modes work with them).

### D-D.6 — Bundle audit

- A pre-build script `scripts/audit-bundle.ts` reports the size of the
  default bundle and the size of each lazy-loaded engine chunk.
- Phase D gate test asserts the default bundle has not grown more than
  5 KB minified versus the Phase C tag (`jam-room-v0.5.0`).

### D-D.7 — Phase D gate test

`apps/world-apps/jam-room/__tests__/phase-d-gate.test.ts`:

- Engine conformance passes for all racks.
- A Strudel rack's `play()` produces audible output (smoke-tested via
  meter movement) within 200 ms of first call.
- A PureData rack with a stub patch that emits a sine on `jam-trigger`
  responds within 200 ms.
- An External MIDI rack sends the correct note-on / note-off bytes.
- Bundle audit passes.
- Phase A/B/C gate tests re-run and pass.

---

## Gate tests (commands)

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-d-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
node scripts/audit-bundle.ts
```

---

## Completion criteria

1. Three new rack engines (`strudel`, `puredata`, `midi`) implement
   `JamRack` and pass the conformance harness.
2. Strudel pattern text round-trips into a `jam.pattern` object.
3. PureData patches load via the documented receiver/sender
   convention; both transport modes work.
4. External MIDI output drives a connected device.
5. Default boot bundle has not grown more than 5 KB.
6. All prior phase gates pass.

---

## Risks & mitigations

| Risk                                                                 | Mitigation                                                                                                |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Strudel runtime version drift                                        | Pin version in `package.json`; document choice in the rack's source header.                               |
| libpd-WASM bundle size                                               | Hard 1 MB ceiling for in-browser patches; larger patches force remote OSC.                                |
| PD bridge daemon distribution                                        | `bridge.ts` already exists; extend it, do not invent a second daemon.                                     |
| External MIDI clock drift vs BEAMClock                               | External MIDI rack listens but does not author clock; clock authority remains BEAMClock from Phase A.     |
| Capture-to-pattern losing fidelity for generative Strudel patterns   | Captured pattern stores the Strudel text *plus* a 64-step rendered snapshot at capture-time BPM.          |

---

## Non-goals

- No Strudel REPL.
- No PD patch editor.
- No new engine kinds beyond `puredata` / `strudel` / `midi`.
- No 3D rack visualisation (= phase E).
- No take capture for engine bridges (= phase F; this phase only adds
  the rack contract conformance, not the take pipeline).
