---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-D-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.781162+00:00
---

# Phase D Execution Prompt — Engine Bridges: Strudel, PureData, External MIDI

> Paste this prompt into a fresh session to execute Phase D.

## Context

You are working in `apps/world-apps/jam-room/`. Phases A, B, and C are
merged: the rack contract, the four default WebAudio racks, the mode
row, Note + Mix modes, and the BYO-mappings system are all live.

Phase D adds three new engine implementations of the `JamRack`
contract: `StrudelRack`, `PureDataRack`, and `ExternalMidiRack`. After
this phase, the same 8×8 surface that drives the WebAudio drum rack
can drive a Strudel pattern, a PureData granular patch, or a hardware
synth — using the same eight musical macro names — without changing
any code outside the rack folders.

---

## CRITICAL: READ THESE FILES FIRST

**Read first** (the PRD and contract):

- `docs/prd/jam-room/PHASE-D-ENGINE-BRIDGES.md` — Phase D spec with
  Strudel macro fan-out (§D.2), PureData transport modes (§D.3), MIDI
  rack (§D.4), engine conformance harness (§D.5), bundle audit (§D.7),
  deliverables D-D.1–D-D.7.
- `docs/prd/jam-room/MASTER.md` — Cross-cutting context.
- `docs/prd/jam-room/PHASE-A-VOCABULARY-AND-RACK.md` — `JamRack`
  contract is the law. The eight macros are
  `brightness / dirt / wobble / space / snap / body / chaos / tension`.

**Read second** (the existing engine wrappers and bridge daemon):

- `apps/world-apps/jam-room/src/racks/contract.ts` (Phase A) — The
  contract. Read every line before you implement anything.
- `apps/world-apps/jam-room/src/racks/registry.ts` (Phase A) — Where
  new rack instances register.
- `apps/world-apps/jam-room/src/racks/webaudio/{drum808,acid303,bassMono,polyKeys}.ts` (Phase A) — Reference implementation. Match this style.
- `apps/world-apps/jam-room/bridge.ts` (existing, ~14 KB) — The
  prototype OSC/WebSocket bridge. PureData rack reuses and extends it;
  do not invent a second bridge.
- `apps/world-apps/jam-room/src/audio.ts` — The capture-tap
  (`MediaStreamAudioDestinationNode`) is here; capture-to-pattern uses
  it.

**Read third** (mappings and surface integration):

- `apps/world-apps/jam-room/src/mappings/router.ts` (Phase C) — Macros
  arrive via `jam.rack.macro.set` cells routed through the editor or
  external MIDI controllers.
- `apps/world-apps/jam-room/src/grid/surface.ts` — Drum / Step / Note /
  Mix modes (Phases A–B). Captured patterns flow back here.

**Read fourth** (branching and CI):

- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as
  `jam-room-d-engine-bridges`, commits as `jam-room-d/D-D.{N}: ...`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. THE EIGHT MACRO NAMES ARE NOT NEGOTIABLE

`brightness`, `dirt`, `wobble`, `space`, `snap`, `body`, `chaos`,
`tension`. Each new rack documents its fan-out for all eight. If a
rack genuinely cannot fan out one of the eight, the `setMacro(index,
value)` call is a no-op and the `macros.md` says so. You do not rename
or extend the macro set.

### 2. CAPTURE-TO-PATTERN STORES THE TEXT *AND* A SNAPSHOT

A Strudel pattern that's generative (uses `degradeBy`, `jux(rev)`,
random `n`) will not replay identically from text alone. The captured
`jam.pattern` payload stores the Strudel text plus a rendered 64-step
snapshot at capture-time BPM, so playback is deterministic.

### 3. NO ENGINE LOADS AT BOOT

Strudel and libpd-WASM are dynamic imports. The bundle audit
(`scripts/audit-bundle.ts`) enforces a 5 KB ceiling on the default
boot bundle versus tag `jam-room-v0.5.0`. If you exceed the ceiling,
the gate fails and you have to push the engine into a deeper lazy
load.

### 4. CLOCK AUTHORITY STAYS BEAM-CLOCK

The `BEAMClock` from Phase A is the source of room time. The new
engines listen — Strudel slaves to `jam.clock.tick`, PureData receives
`[r jam-clock]`, External MIDI sends MIDI clock derived from
`BEAMClock`. None of them author clock.

### 5. PUREDATA RECEIVER NAMES ARE CONVENTIONAL

`[r jam-note]`, `[r jam-trigger]`, `[r jam-clock]`,
`[r jam-macro-1]` … `[r jam-macro-8]`. Patches that don't conform
won't load through the rack; the rack throws a descriptive error
listing the missing receivers.

### 6. EXTERNAL MIDI RACK IS OUTPUT-FIRST

The MIDI rack sends notes / triggers / CC. Receiving from a hardware
synth (audio return, SysEx state) is *optional*; meter results are
allowed to be no-op. The conformance harness's `skipMeters` option
exists for exactly this case.

### 7. NO PHASE-E/F WORK

No 3D rack visualisation, no take capture pipeline, no contribution
attribution. The `captureToPattern` deliverable produces a
`jam.pattern`, not a `jam.take`.

---

## Deliverable mapping

| ID    | File(s) you create or change                                               |
| ----- | -------------------------------------------------------------------------- |
| D-D.1 | `src/racks/strudel/StrudelRack.ts`, `src/ui/strudel-card.ts`, `index.html` card pool addition |
| D-D.2 | `src/racks/puredata/PureDataRack.ts`, `src/racks/puredata/conventions.md`, extend `bridge.ts` |
| D-D.3 | `src/racks/midi/ExternalMidiRack.ts`, `src/racks/midi/cc-map.ts`           |
| D-D.4 | `apps/world-apps/jam-room/__tests__/rack-conformance.ts`                   |
| D-D.5 | `captureToPattern` on Strudel and PureData racks                           |
| D-D.6 | `scripts/audit-bundle.ts`                                                  |
| D-D.7 | `apps/world-apps/jam-room/__tests__/phase-d-gate.test.ts`                  |

---

## Gate test commands

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-d-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
node scripts/audit-bundle.ts
```

---

## Branching

```bash
git checkout main
git pull
git checkout -b jam-room-d-engine-bridges
```

Commit prefix: `jam-room-d/D-D.{N}: <description>`.
On gate-green merge: tag `jam-room-v0.6.0`.

---

## Definition of done

1. Three new rack classes implementing `JamRack` and passing the
   shared conformance harness.
2. Strudel card mounts; pattern text plays in under 200 ms of first
   call.
3. PureData rack loads a stub patch through both in-browser and remote
   transports; receiver names enforced.
4. External MIDI rack sends correct CC / note bytes to a Web MIDI
   output.
5. Capture-to-pattern produces a `jam.pattern` that the existing 8×8
   surface can play.
6. Bundle audit passes.
7. Phase A/B/C/D gate tests all pass.

---

## What to **not** do

- Don't rename the macro set.
- Don't add `eval()` anywhere in the Strudel rack — Strudel itself
  parses; the rack just feeds and reads.
- Don't write a second OSC bridge daemon — extend `bridge.ts`.
- Don't add a take recorder. Capture-to-pattern is a `jam.pattern`,
  not a `jam.take`.
- Don't take BEAM-clock authority. New engines slave only.
- Don't ship without `macros.md` files; the gate test diffs them
  against the runtime fan-out.
