---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.778182+00:00
---

# `docs/prd/jam-room/` — Jam Room build phases

This folder defines the build-out of the **jam room** world app
(`apps/world-apps/jam-room/`) as a series of phases. The jam-room is
already partly wired: BEAMClock, the 8×8 grid surface with five Push-3
style modes, the 13-track sequencer, the WebAudio engine, the Three.js
jambox-world projection, BSV anchoring, and the rekordbox/splice
importers all exist. The phases below promote that working surface into
a multiplayer semantic groovebox where the room is the DAW, the grid is
the instrument, the loops are objects, and every player can bring their
own rack, mapping, and controller.

## Order of work

| Phase | What it lands | Branch prefix |
|-------|---------------|---------------|
| [A](./PHASE-A-VOCABULARY-AND-RACK.md) | Semantic vocabulary + `JamRack` contract + `viewportPlan` + `colourForPitch` | `jam-room-a-vocabulary` |
| [B](./PHASE-B-MODES.md) | Anchor row + 3 L2 buttons (Rhythm/Melody/Bass) + 5-entry support sheet; Note mode with scale-channel colour | `jam-room-b-modes` |
| [C](./PHASE-C-MAPPINGS.md) | Bring-your-own controller mappings, mapping editor, profile sharing, scale-channel LED feedback | `jam-room-c-mappings` |
| [D](./PHASE-D-ENGINE-BRIDGES.md) | Strudel rack adapter + PureData bridge + external MIDI rack | `jam-room-d-engine-bridges` |
| [E](./PHASE-E-3D-CONTROL-SURFACE.md) | Three.js room as control surface (desktop only; tablet 2D fallback; mobile hidden) | `jam-room-e-3d-surface` |
| [F](./PHASE-F-TAKES-AND-LINEAGE.md) | Take capture, contribution objects, remix lineage, anchored takes | `jam-room-f-takes` |
| [G](./PHASE-G-MOBILE-AND-FLUTTER.md) | Responsive web layout + `jam-room-mobile` Flutter shell + MIDI hosting on phone | `jam-room-g-mobile` |

[`MASTER.md`](./MASTER.md) is the cross-cutting document: design thesis,
current-reality audit (which lines of which files do what today), the
full primitive rack at a glance, the phase dependency graph, the
1-3-5-3-1 Conscious Stack mapping, the compression gradient, and the
"first 30 seconds" success metric.

`notes/REFERENCE-DEVICES.md` extracts the Push 3 / Circuit / Launchpad /
Blipblox myTRACKS / MPK49 / RX2 affordance lessons. It is design
inspiration, not deliverables — phase PRDs cite it where relevant.

[`design/`](./design/) holds polish-ready design notes the phase PRDs
fold back from:

| Note | What it covers |
| ---- | -------------- |
| [`design/CSD-COMPRESSION-GRADIENT.md`](./design/CSD-COMPRESSION-GRADIENT.md) | The 1-3-5-3-1 pyramid for jam-room; peel-from-bottom rule; three default `viewportPlan`s. |
| [`design/MODE-ROW-REVISION.md`](./design/MODE-ROW-REVISION.md) | Anchor + 3 L2 + 5-entry support sheet replacing the eight-button row. |
| [`design/MOBILE-AND-FLUTTER-SHELL.md`](./design/MOBILE-AND-FLUTTER-SHELL.md) | Phase G architecture and the controller-on-phone matrix. |
| [`design/COLOUR-AS-DIMENSION.md`](./design/COLOUR-AS-DIMENSION.md) | Scale-channel colour, palettes, scale-lock, layout-by-scale, learning overlays. |

## How each phase is structured

Two files per phase, matching the canonical `docs/prd/PHASE-NNa-*` style:

- `PHASE-{X}-{NAME}.md` — the PRD: context, architecture, deliverables
  (`D-{X}.N`), gate tests, completion criteria, risks.
- `PHASE-{X}-PROMPT.md` — a paste-ready execution prompt: critical-read
  file list, anti-bullshit rules, deliverable mapping, branch and commit
  prefixes.

## Conventions

- **Branch prefix**: `jam-room-{x}-{slug}` (e.g.
  `jam-room-a-vocabulary`).
- **Commit prefix**: `jam-room-{x}/D-{X}.{N}: ...`.
- **Gate tests**: each phase adds
  `apps/world-apps/jam-room/__tests__/phase-{x}-gate.test.ts` and is
  cumulative with previous phases.
- **Semantic kinds added in phase X must be listed under "Vocabulary
  delta" in that phase's PRD** so the `JamboxObjectKind` union and
  `semantic/objects.ts` factories stay in sync with the canon.
- **Anchoring**: where a deliverable produces a new semantic object
  type, the PRD must declare its linearity class (`linear`, `affine`,
  `relevant`, or `debug`) so cell-engine semantics are unambiguous.

## Parallelism — designing UI and system at the same time

Phase A's `viewportPlan` and `colourForPitch` deliverables are
**contract-only** — they ship types, constants, and pure functions
without touching the renderer. Designers can iterate Note-mode
visuals against `colourForPitch` snapshot data, and L1 anchor / L2
tab visuals against `mobilePlan` constants, **before Phase B's mode
row or Phase G's Flutter shell ship a single pixel**.

The rule of thumb across the whole phase set:

> **System PRs land contracts; design PRs land visuals against those
> contracts; both sides can move in parallel once the contract is
> merged.**

That's why the design notes in `design/` exist as a layer between
the master document and the phase PRDs — they are the contract
between design and system.

## Status snapshot

All seven phases are **draft PRD**. The current jam-room app is
`@semantos/world-app-jam-room@0.2.0`. None of the phases below have
been opened as branches yet.
