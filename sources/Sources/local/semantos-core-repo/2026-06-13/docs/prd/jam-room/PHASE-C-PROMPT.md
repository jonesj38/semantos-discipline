---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-C-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.779248+00:00
---

# Phase C Execution Prompt — Bring-Your-Own Mappings

> Paste this prompt into a fresh session to execute Phase C.

## Context

You are working in `apps/world-apps/jam-room/`. Phases A and B are
merged: the semantic vocabulary, `JamRack` contract, four default
WebAudio racks, mode row, Note mode, Mix mode, and clip/scene
upgrades are all live.

Phase C makes the controller story real. After this phase, any MIDI /
HID / gamepad / touch / QWERTY device routes through a five-layer
mapping pipeline (device → surface → mode → semantic → feedback).
Mappings are saved as content-addressed `jam.mapping` semantic
objects, forkable and shareable, with eight built-in profiles
covering Launchpad / Push / Circuit / MPK49 / RX2 / QWERTY / touch /
gamepad. The Custom mode button (disabled in Phase B) becomes live.

---

## CRITICAL: READ THESE FILES FIRST

**Read first** (the PRD and prior phases):

- `docs/prd/jam-room/PHASE-C-MAPPINGS.md` — Phase C spec with the
  five-layer pipeline (§C.1), `JamboxMappingPayload` (§C.2), built-in
  profiles (§C.3), registry (§C.4), editor (§C.5), Custom mode (§C.6),
  deliverables D-C.1–D-C.8, gate tests.
- `docs/prd/jam-room/MASTER.md` — Cross-cutting context.
- `docs/prd/jam-room/PHASE-A-VOCABULARY-AND-RACK.md` — `jam.mapping` is
  declared `linear` (one mapping owns its surface slot, forking creates
  a new mapping). `JamMappingHint` on every rack feeds the editor's
  target picker.
- `docs/prd/jam-room/PHASE-B-MODES.md` — Mode row, Note mode, Mix mode
  semantics that the mapping pipeline now routes against.

**Read second** (the existing surface and instrument code you extend):

- `apps/world-apps/jam-room/src/grid/surface.ts` — `GridModeKind` now
  includes `'note'` and `'mix'`. Add `'custom'`. Add a routing hook
  that consults the active mapping when in Custom mode.
- `apps/world-apps/jam-room/src/instruments/midi.ts` — Existing Web MIDI
  scaffolding. Your new device adapter generalises this.
- `apps/world-apps/jam-room/src/instruments/midi-map.ts` — Existing
  per-track MIDI map. The mapping registry subsumes this; keep this
  file for backward compatibility but route through the new registry.
- `apps/world-apps/jam-room/src/instruments/keys.ts` — QWERTY keys;
  reuse for the QWERTY profile.
- `apps/world-apps/jam-room/src/racks/registry.ts` (Phase A) — Used by
  the editor's target picker via `getMappingHints()`.
- `apps/world-apps/jam-room/src/semantic/objects.ts` — Add the
  `JamboxMappingPayload` shape; the kind already exists.

**Read third** (sharing and content addressing):

- `packages/world-sdk/src/relay/client.ts` — How the cell-relay
  client talks to the BEAM region. Mapping save uses the same path.
- `packages/cell-relay/src/types.ts` — Cell envelope shape mappings
  ride.

**Read fourth** (branching and CI):

- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as
  `jam-room-c-mappings`, commits as `jam-room-c/D-C.{N}: ...`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. THE PIPELINE IS THE PIPELINE

Five layers: device → surface → mode → semantic → feedback. Each layer
has a single responsibility. The device layer normalises raw events;
it does not emit `jam.input.*`. The semantic layer emits cells; it
does not poke audio nodes. If you find yourself short-circuiting a
layer, you are wrong.

### 2. MAPPINGS ARE DECLARATIVE

A mapping is JSON. No `eval()`, no embedded scripts, no Turing-complete
runtime in the mapping payload. Transforms are declared (`linear / exp
/ log / clamp` with named parameters). If a user wants something
weirder, they write a new mapping kind in a future phase.

### 3. NEVER LET A DEVICE DRIVE THE WIRE FORMAT DIRECTLY

A malicious or buggy device must not be able to skip the surface and
mode layers. The router enforces order. Devices emit `DeviceEvent`;
nothing else. The router decides what becomes a `jam.*` cell.

### 4. CONTENT-ADDRESSED, NOT MUTABLE

Saving a mapping produces a new content hash and a new
`JamboxSemanticObject<JamboxMappingPayload>`. Mappings are never
mutated in place; edits create a new object whose `previousStateHash`
points to the prior version.

### 5. NOTE-MODE GUARDRAIL IS PRESERVED

Phase B requires "no wrong notes" in default scale-locked Note mode.
A device mapping that would emit chromatic notes in Note mode must
either:
- declare `MappingConstraint { kind: 'requires-permission', value: 'chromatic' }`, or
- fall back to scale-locked input.

The router silently quantises in fallback; it does not crash.

### 6. CUSTOM MODE IS A LAST RESORT, NOT THE FIRST OPTION

Custom mode bypasses Phase B's mode rules. It exists for power users
running their own mapping. The mode row's Custom button stays the
last button on the right.

### 7. NO PHASE-D/E/F WORK

No Strudel, no PureData, no 3D affordances, no take capture.

---

## Deliverable mapping

| ID    | File(s) you create or change                                                  |
| ----- | ----------------------------------------------------------------------------- |
| D-C.1 | `JamboxMappingPayload` in `objects.ts`; `src/mappings/registry.ts`; `src/mappings/router.ts` |
| D-C.2 | `src/mappings/devices/{web-midi,web-hid,pointer-touch,gamepad,keyboard}.ts`   |
| D-C.3 | `src/mappings/profiles/{qwerty,touch,launchpad,launchpad-pro,push3,circuit,mpk49,rx2,gamepad,phone}.ts` |
| D-C.4 | `src/ui/mapping-editor.ts` + `index.html` card pool addition                  |
| D-C.5 | Surface `'custom'` mode + mode-row Custom button activation                   |
| D-C.6 | Auto-detect + first-time mapping prompt in `src/main.ts`                      |
| D-C.7 | Conflict resolution rules in `src/mappings/router.ts`                         |
| D-C.8 | `apps/world-apps/jam-room/__tests__/phase-c-gate.test.ts`                     |

---

## Gate test commands

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-c-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
```

---

## Branching

```bash
git checkout main
git pull
git checkout -b jam-room-c-mappings
```

Commit prefix: `jam-room-c/D-C.{N}: <description>`.
On gate-green merge: tag `jam-room-v0.5.0`.

---

## Definition of done

1. Eight profiles in `src/mappings/profiles/`; QWERTY + touch active by
   default; the rest activate on detection.
2. Mapping editor card creates, edits, saves, forks mappings.
3. Saved mappings are content-addressed `jam.mapping` objects with
   correct linearity and parent lineage.
4. Custom mode routes input through the active mapping without applying
   built-in mode guardrails (except chromatic Note guardrail unless
   permission granted).
5. Plug-in MPK49 immediately drives `jam.rack.poly-keys` keys with no
   editor interaction.
6. Phase A/B/C gate tests all pass.

---

## What to **not** do

- Don't replace `src/instruments/midi.ts` or `midi-map.ts`. Subsume
  them; keep the existing module exports for backward compat.
- Don't expose raw DSP names in the editor's target picker. Use
  `getMappingHints()` from each rack.
- Don't add a marketplace UI; sharing is a content-link copy/paste.
- Don't ship without conflict-resolution rules; two devices mapping
  the same target is real and common.
- Don't introduce new permission tokens; reuse `jam.permission` from
  Phase A.
