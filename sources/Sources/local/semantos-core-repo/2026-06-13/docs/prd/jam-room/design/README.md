---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/design/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.782644+00:00
---

# `docs/prd/jam-room/design/` — Design notes for polish

These are **drafts for Claude Design / a designer to polish**, not
finalised PRDs. The phase PRDs in the parent folder cite them but
don't depend on them as gating documents.

Each note answers a cross-cutting question that didn't fit cleanly
into a single phase PRD:

| Note | Question it answers |
| ---- | ------------------- |
| [CSD-COMPRESSION-GRADIENT.md](./CSD-COMPRESSION-GRADIENT.md) | How does the 1-3-5-3-1 Conscious Stack pyramid map onto the jam-room, and how does the layout compress from desktop → tablet → mobile without losing function? |
| [MODE-ROW-REVISION.md](./MODE-ROW-REVISION.md) | Phase B's eight-button mode row violates the Sincerity Filter. What does the revised row look like? |
| [MOBILE-AND-FLUTTER-SHELL.md](./MOBILE-AND-FLUTTER-SHELL.md) | What does a `jam-room-mobile` Flutter shell look like, mirroring `apps/oddjobz-mobile/`? Can a phone host a MIDI controller? |
| [COLOUR-AS-DIMENSION.md](./COLOUR-AS-DIMENSION.md) | Colour as a first-class dimension for scales, modes, chords, in-key/out-of-key, scale-lock, and learning overlays. |

## How to read these

Each note has the same shape:

1. **The question** — what design tension it resolves.
2. **The proposal** — the concrete design move.
3. **Open questions for design polish** — explicit `TODO(design)` items
   the designer should make a call on.

## Status

All four are **draft v0.1**. Polish them in place. When they're ready
for build, fold their decisions into the phase PRDs in the parent
folder and link back here from the deliverable list.

## Reference materials in repo

- `CSD_QUICK_REFERENCE.md` (repo root) — the 1-3-5-3-1 Conscious
  Stack methodology.
- `ODDJOBZ_CSD_BRIEFING.md` (repo root) — full briefing on CSD as
  applied to the Oddjobz Flutter UI.
- `CSD_SONNET_HANDOFF.md` (repo root) — handoff context.
- `docs/textbook/17b-the-loom-service-layer-warp.md` §17b.7 — the
  Loom's compression-gradient claim.
- `apps/oddjobz-mobile/` — existing Flutter shell that paired with
  BRAIN/Loom; the architectural template for `jam-room-mobile`.
- `apps/world-apps/jam-room/src/grid/surface.ts` — current
  `PadColor` vocabulary.
- `apps/world-apps/jam-room/src/sequencer.ts` — current scale
  dropdown options (`pent / major / minor / dorian / phrygian`).
