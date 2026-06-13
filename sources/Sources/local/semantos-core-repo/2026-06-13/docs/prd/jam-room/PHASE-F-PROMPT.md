---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-F-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.778713+00:00
---

# Phase F Execution Prompt — Takes, Contributions, Remix Lineage

> Paste this prompt into a fresh session to execute Phase F.

## Context

You are working in `apps/world-apps/jam-room/`. Phases A through E are
merged. The semantic vocabulary, JamRack contract, mode row, BYO
mappings, Strudel / PureData / external MIDI engines, and the
interactive 3D room are all live. Every cell flowing through the room
is canonical, identified, and owned.

Phase F turns that stream into something replayable. It builds the
take capturer, the default contribution-split policy, deterministic
replay, opt-in audio bounce, license-aware forking, the lineage
explorer card, and extends BSV anchoring to takes and arrangements.

---

## CRITICAL: READ THESE FILES FIRST

**Read first** (the PRD and prior phases):

- `docs/prd/jam-room/PHASE-F-TAKES-AND-LINEAGE.md` — Phase F spec with
  take payload (§F.1), contribution payload (§F.2), capture pipeline
  (§F.3), promotion (§F.4), fork rules (§F.5), license propagation
  (§F.6), anchoring (§F.7), deliverables D-F.1–D-F.8.
- `docs/prd/jam-room/MASTER.md` — Cross-cutting context and success
  metric (the seven-step end-to-end the gate test must satisfy).
- `docs/prd/jam-room/PHASE-A-VOCABULARY-AND-RACK.md` — `jam.take` is
  `linear`, `jam.contribution` is `relevant`, `jam.permission` is
  `linear`. The factory style for these kinds was set in Phase A.
- `docs/prd/jam-room/PHASE-E-3D-CONTROL-SURFACE.md` — The
  `jam.arrangement.take.promote` cell already flows from the wall
  promote button. Phase F builds the *handler* for it.

**Read second** (existing capture / anchor / snapshot code):

- `apps/world-apps/jam-room/src/core/anchor.ts` — Existing PushDrop
  anchor of `jam.snapshot`. Extend, do not replace.
- `apps/world-apps/jam-room/src/core/dag.ts` — Patch DAG; takes ride
  this graph but as their own kind.
- `apps/world-apps/jam-room/src/core/sync.ts` — Cell sync helpers.
- `apps/world-apps/jam-room/src/audio.ts` — `MediaStreamAudioDestinationNode`
  tap is already in place; the audio bouncer reuses it.
- `apps/world-apps/jam-room/src/semantic/objects.ts` — `JamboxTakePayload`
  and `JamboxContributionPayload` were declared in Phase A. Fill out
  the implementations.

**Read third** (relay and content-addressing):

- `runtime/world-beam/apps/cell_relay/lib/cell_relay/room.ex` —
  Read-only: take capture subscribes to room events the same way the
  existing snapshot path does.
- `packages/world-sdk/src/relay/client.ts` — Same client; new objects
  ride the same channel.

**Read fourth** (branching and CI):

- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `jam-room-f-takes`,
  commits as `jam-room-f/D-F.{N}: ...`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. TAKES ARE CELL STREAMS, NOT AUDIO FILES

A take is a deterministic replay of a cell range from a known starting
snapshot. The optional audio bounce is *additional*, not the take
itself. Anyone with the take object and the right racks can replay it.

### 2. CONTRIBUTIONS ARE NEVER RETROACTIVELY MUTABLE

Once a take is captured, contributions are frozen. Editing a
contribution requires forking the take. The existing relevant
linearity (Phase A) enforces this: contributions accrete.

### 3. SPLIT POLICY IS DOCUMENTED IN ONE PLACE

`src/contrib/policy.md`. Code in `src/contrib/policy.ts` matches it
line-by-line. The gate test diffs the docs against the runtime
behaviour. Don't ship if they disagree.

### 4. LICENSE PROPAGATION IS A LATTICE

`personal < remixable < commercial`. Forking can only narrow the
license, never widen it. The fork dialog enforces this; the gate test
asserts it.

### 5. AUDIO BOUNCE IS CONSENT-GATED

Bouncing audio of a multi-player session shows the participating
players in the dialog and requires explicit user confirmation. There
is no "remember my choice" option in this phase. Future phases may add
permission tokens.

### 6. ANCHORING IS NEVER AUTOMATIC

`anchorTake(takeId)` and `anchorArrangement(arrangementId)` are
explicit user actions. There is no auto-anchor on capture. The
existing PushDrop machinery is reused unmodified.

### 7. NO NEW CELL FAMILIES

Phase A locked the event-cell families. Phase F uses
`jam.arrangement.take.capture` and `jam.arrangement.take.promote`
which are already defined. If you need a new family, update Phase A's
PRD first.

---

## Deliverable mapping

| ID    | File(s) you create or change                                                |
| ----- | --------------------------------------------------------------------------- |
| D-F.1 | `src/takes/capturer.ts`; transport panel Capture button                     |
| D-F.2 | `src/contrib/policy.ts`, `src/contrib/policy.md`                            |
| D-F.3 | `src/takes/replay.ts`                                                       |
| D-F.4 | `src/takes/bouncer.ts`                                                      |
| D-F.5 | `src/contrib/fork.ts`                                                       |
| D-F.6 | `src/ui/lineage-card.ts` + `index.html` card pool addition                  |
| D-F.7 | `anchorTake`, `anchorArrangement` in `src/core/anchor.ts`                   |
| D-F.8 | `apps/world-apps/jam-room/__tests__/phase-f-gate.test.ts`                   |

---

## Gate test commands

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-f-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
```

The seven-step success metric from `MASTER.md` §6 is part of the gate.

---

## Branching

```bash
git checkout main
git pull
git checkout -b jam-room-f-takes
```

Commit prefix: `jam-room-f/D-F.{N}: <description>`.
On gate-green merge: tag `jam-room-v0.8.0`.

---

## Definition of done

1. Capture button records a take; the take object validates against
   `JamboxTakePayload`.
2. One `jam.contribution` per active player; splits sum to 10 000 bps.
3. Replay restores deterministic state and plays back identically.
4. Bounce produces an opus payload after consent.
5. Forking honours the license lattice.
6. Lineage card renders parent chain back to root.
7. Anchoring works for takes and arrangements.
8. The `MASTER.md` §6 seven-step success metric passes end to end as a
   gate-test fixture.
9. Phase A/B/C/D/E/F gate tests all pass.

---

## What to **not** do

- Don't add settlement, payments, or anything that moves money.
- Don't ship a public marketplace UI.
- Don't auto-anchor; anchoring is explicit.
- Don't allow license widening on fork.
- Don't add new cell families. Phase A locked them.
- Don't make audio bounce default-on. Privacy first.
