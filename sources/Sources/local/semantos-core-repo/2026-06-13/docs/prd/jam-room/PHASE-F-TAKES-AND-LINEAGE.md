---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/PHASE-F-TAKES-AND-LINEAGE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.778976+00:00
---

# Phase F — Takes, Contributions, Remix Lineage

**Version**: 1.0
**Date**: May 2026
**Status**: Draft PRD
**Duration**: 1.5–2 weeks
**Prerequisites**: Phase A (`jam.take`, `jam.contribution`, `jam.permission` types); Phase B (Session/Arrange modes); Phase C (mappings emit attributable cells); Phase E (`jam.arrangement.take.promote` cell wired up).
**Branch prefix**: `jam-room-f-takes`
**Master document**: `MASTER.md`

---

## Context

Every prior phase emits canonical, identified, owned cells. Phase F
turns that stream into something playable: **takes** (captured
performance passes that can be replayed from the cell stream alone),
**contributions** (split-aware authorship objects), and **lineage**
(fork / remix relationships visible in the headers' `parents` arrays).

After Phase F, two players can jam, capture the session as a take,
fork the take, and replay it later from the take object alone — with
contributions correctly attributing both players' work, and the take
optionally anchored to BSV via the existing PushDrop path.

### What this phase is not

- Not a payment system. `jam.contribution` records splits; settlement
  happens downstream in `packages/settlement/`.
- Not an audio render farm. Takes record the cell stream, not a final
  audio mixdown. Audio bounce is opt-in and uses the existing
  `MediaStreamAudioDestinationNode` tap from `audio.ts`.
- Not a public marketplace. Takes can be marked as `commercial` /
  `royaltyBps` in their headers; a marketplace UI is a future phase.

---

## Architecture

### F.1 What is a take?

A `jam.take` is a captured range of cells from the room's event
stream, attributable to a set of players, replayable, forkable.

```ts
export interface JamboxTakePayload {
  /** Room the take was captured in. */
  room: string;
  /** Start and end of the captured range, in room time. */
  range: { startRoomTimeMs: number; endRoomTimeMs: number };
  /** Bar count if the take is a clean musical range. */
  lengthBars?: number;
  /** Cell-stream slice (or a content reference if large). */
  cells: SerializedCell[] | { ref: string; sha256: string };
  /** Players who contributed to this take. */
  players: string[];   // playerIds
  /** Bound rack ids at capture time. */
  racks: string[];
  /** Bound mapping ids at capture time. */
  mappings: string[];
  /** Optional audio bounce (m4a / opus) of the take. */
  audio?: { ref: string; sha256: string; sampleRate: number; channels: number };
  /** Snapshot of room state at capture start, for deterministic replay. */
  startSnapshotHash: string;
}
```

Takes are `linear` (Phase A): a take is a once-only capture; promotion
to an arrangement does not consume it.

### F.2 What is a contribution?

A `jam.contribution` records that a player did something specific
during a take — placed steps, played notes, twisted macros, dropped
gestures.

```ts
export interface JamboxContributionPayload {
  player: string;
  /** Object the contribution is against. */
  objectId: string;            // jam.take.id, jam.pattern.id, jam.arrangement.id
  /** Cell range within the parent take. */
  cellRange: { from: number; to: number };
  /** Action category — informational, not authoritative. */
  category: 'pattern.edit' | 'note.play' | 'macro.twist' | 'gesture' | 'mapping.fork' | 'launch' | 'arrangement.edit' | 'capture';
  /** Suggested split, in basis points. Default policy fills these in. */
  splitBps?: number;
  /** License this contribution flows under. */
  license: 'personal' | 'remixable' | 'commercial';
}
```

Contributions are `relevant` (Phase A): once recorded, they accrete;
you cannot un-contribute.

The default split policy is documented in `src/contrib/policy.md`:

- Each player's contribution is weighted by event count and macro
  range covered, then normalised to 10 000 bps.
- Owners of forked content (via `parents`) receive a small inheritance
  share of the take's splits when their content is reused.

### F.3 Capture pipeline

```
Player presses transport → record   (or scene-row-record gesture)
        │
        ▼
TakeCapturer.start()
  - subscribes to all jam.* cells with sourceRoom = currentRoom
  - records startSnapshotHash from current room state
        │
   user plays...
        │
        ▼
TakeCapturer.stop()
  - ends subscription
  - groups cells by player → emits one jam.contribution per player
  - emits a jam.take cell with the cell range and contribution ids
        │
        ▼
Optional: TakeBouncer.render()
  - replays cells through racks into MediaStreamAudioDestinationNode
  - encodes opus/m4a → CAS → fills jam.take.audio
        │
        ▼
Optional: TakeAnchor.anchor()
  - existing PushDrop path (anchor.ts) writes the take's headHash to
    BSV
```

### F.4 Promotion to arrangement

A take can be promoted to a `jam.arrangement` section. The promotion
is a `jam.arrangement.take.promote` cell (Phase E already emits this
cell from the wall promote button) which:

- Creates an arrangement section referencing the take.
- Copies the take's `players` and `racks` into the section's
  contribution chain.
- Marks the section as **derived** — the section's `parents[0]` is the
  take id.

### F.5 Forking and remix lineage

Forking a take, pattern, scene, or arrangement creates a new object
whose header's `parents[0]` points to the original. Phase F adds:

- A `forkObject(objectId, owner)` function in `src/contrib/fork.ts` that
  works for any `JamboxObjectKind`.
- A lineage UI: in the contribution-stream HUD (Phase E.D-E.8), each
  entry has a "fork" button that opens a confirm dialog.
- A lineage explorer card: lists the parent chain of a selected object
  back to its root.

### F.6 License propagation

Headers carry an optional `commercial.license` (`personal | remixable
| commercial`). On fork:

- `personal` → child must also be `personal`. Cannot be tightened or
  loosened.
- `remixable` → child can be `remixable` or `personal`.
- `commercial` → child can be `commercial`, `remixable`, or `personal`,
  with the original license preserved in the lineage.

The fork dialog enforces these rules.

### F.7 Anchoring

`src/core/anchor.ts` already PushDrops session snapshot hashes to BSV.
Phase F extends:

- `anchorTake(takeId)` writes a take's content hash.
- `anchorArrangement(arrangementId)` writes an arrangement's content
  hash.
- The take object header's `commercial.listed` flag controls whether
  the anchor includes a marketplace pointer.

Anchoring is optional and explicit — there is no auto-anchor on
capture.

---

## Deliverables

### D-F.1 — Take capturer

- `src/takes/capturer.ts` — start / stop / status lifecycle.
- Subscribes to the cell-relay channel (existing
  `room:{roomId}:events` channel).
- Produces a `jam.take` object on stop.
- Transport panel grows a Capture button; long-press selects "capture
  last 4 / 8 / 16 / 32 bars" without manually starting first.

### D-F.2 — Contribution policy

- `src/contrib/policy.ts` and `src/contrib/policy.md` documenting the
  default split policy.
- Per take: emits one `jam.contribution` per player with `splitBps`
  filled in.
- Tests cover edge cases: solo player (10 000 bps), two equal players
  (5 000/5 000), heavily-weighted player (e.g. 8 500/1 500).

### D-F.3 — Take replay

- `src/takes/replay.ts` — given a take id, restores the room to
  `startSnapshotHash` and replays cells in order.
- Replay handles missing racks gracefully (warn and continue).

### D-F.4 — Audio bounce (opt-in)

- `src/takes/bouncer.ts` — replays a take into an offline-render audio
  context, encodes opus, writes to CAS, fills `jam.take.audio`.
- Bouncing is gated by a confirm dialog (privacy; bouncing audio of a
  multiplayer session implicates other players).

### D-F.5 — Forking

- `src/contrib/fork.ts` — `forkObject(objectId, owner)` for all kinds.
- License-propagation rules enforced.
- Adds a `parents[0]` link.

### D-F.6 — Lineage explorer card

- New `data-card="lineage"` workbench card.
- Shows the parent chain of the selected object back to its root.
- Click any node = focus that object.

### D-F.7 — Anchoring extensions

- `anchorTake(takeId)` and `anchorArrangement(arrangementId)` in
  `src/core/anchor.ts`.
- Anchor button on the take detail view.

### D-F.8 — Phase F gate test

`apps/world-apps/jam-room/__tests__/phase-f-gate.test.ts`:

- A simulated two-player jam captures a take; the take has the right
  cell range, two contributions, splits totalling 10 000 bps.
- Replay restores deterministic state.
- Forking a take produces a new take whose `parents[0]` is the
  original; the license-propagation rule fires when expected.
- Anchoring writes a PushDrop transaction (mock SPV path).
- Phase A/B/C/D/E gate tests re-run and pass.

---

## Gate tests (commands)

```bash
pnpm -C apps/world-apps/jam-room typecheck
pnpm -C apps/world-apps/jam-room test --filter phase-f-gate
pnpm -C apps/world-apps/jam-room test
pnpm -C apps/world-apps/jam-room build:bundle
```

---

## Completion criteria

1. Capture button records a take; the resulting `jam.take` object has
   range, players, racks, mappings, and start snapshot.
2. One `jam.contribution` per active player, splits sum to 10 000 bps.
3. Replay restores deterministic state and plays back identically.
4. Audio bounce produces an opus / m4a encoded payload.
5. Forking honours license propagation.
6. Anchoring extends to takes and arrangements.
7. Lineage card walks parent chain back to root.
8. All prior phase gates pass.

---

## Risks & mitigations

| Risk                                                                  | Mitigation                                                                                              |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Determinism break: replay diverges from original                      | `startSnapshotHash` fixes initial state; cells replayed in deterministic order; non-deterministic Strudel patterns capture text + rendered snapshot (Phase D rule). |
| Long takes blow CAS storage                                            | Cells over a threshold (default 256 KB serialised) are CAS-stored by reference, not inline.            |
| Privacy: a player bounces a multi-player session without consent       | Bounce dialog shows participating players and requires explicit confirmation; future phase adds revoke. |
| Default split policy feels unfair                                      | Policy is documented in `policy.md`; players can override per-take in the contribution editor (Phase F UI). |
| Anchoring misuse: malicious party anchors content they don't own       | Anchor only succeeds when ownerIdentity matches the user's signing key; cell-engine enforces this.      |

---

## Non-goals

- No payment / settlement integration in this phase.
- No marketplace UI.
- No public take browser. Sharing a take is content-link copy/paste.
- No automatic take revocation. Takes are immutable once captured.
- No retroactive contribution editing for old takes (only the current
  capture session is editable before commit).

---

## Coda

After Phase F merges, the success metric in `MASTER.md` §6 is testable
end to end:

> Enter URL → hear pulse → press pad in <3 s → hear sound → capture
> 4-bar loop → see orb in 3D room with your colour → second player
> joins → contributes a different track → promote take → fork take →
> replay take in a new session.

If those steps work without configuration, the jam room build is
done.
