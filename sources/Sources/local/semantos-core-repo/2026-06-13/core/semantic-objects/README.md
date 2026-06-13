---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantic-objects/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.798543+00:00
---

# @semantos/semantic-objects

The canonical patch substrate for semantos. Four drizzle tables + helpers for creating aggregates, appending patches, folding state, and managing participants.

Every domain extension (calendar, OJT's kernel, BRAP's risk engine, …) writes into these tables. The calendar isn't special; jobs aren't special. They're all just rows in `sem_objects` with streams of `sem_object_patches`.

## The four tables

| Table | Role |
|---|---|
| `sem_objects` | Aggregates. One row per thing (a schedule, a conversation, a job, a hat). `current_state_hash` is the tip of the patch stream. |
| `sem_object_patches` | Append-only change log. Each patch has `prev_state_hash` (optimistic concurrency) + `new_state_hash` (new tip). |
| `sem_object_states` | Optional snapshot/checkpoint rows for objects whose fold becomes expensive. Skip until you need it. |
| `sem_participants` | Access list — who can read/write/admin an object. Soft-delete via `left_at`. |

Column shapes align with OJT's pre-existing `sem_object_patches` (federation fields: `timestamp`, `facet_id`, `facet_capabilities`, `lexicon` — OJT-PHASE-1 ships these). A signed bundle of patches from one node can be replayed on another.

## Quickstart

```ts
import {
  createObject, appendPatch, listPatches, foldState,
  addParticipant, listParticipants,
  StaleStateHashError,
} from '@semantos/semantic-objects';

// 1. Create an aggregate.
const schedule = await createObject(db, {
  id: 'schedule-primary',
  objectKind: 'schedule',
  payload: { operatorCertId: 'cert-todd', timezone: 'Australia/Brisbane' },
  createdByCertId: 'cert-todd',
});

// 2. Append patches.
const p1 = await appendPatch(db, {
  objectId: schedule.id,
  kind: 'hold',
  delta: { op: 'hold', holdId: 'h1', /* ... */ },
  lexicon: 'calendar',
  facetId: 'todd-handyman',
});

// 3. Fold the stream to current state.
type Delta = { op: 'hold' | 'book'; /* ... */ };
const patches = await listPatches<Delta>(db, { objectId: schedule.id });
const state = foldState({
  patches,
  initial: { holds: new Map(), bookings: new Map() },
  reducer: (s, p) => applyPatch(s, p), // your domain-specific reducer
});

// 4. Optimistic concurrency.
try {
  await appendPatch(db, {
    objectId: schedule.id,
    kind: 'book',
    delta: { /* ... */ },
    expectedPrevStateHash: p1.newStateHash, // throws StaleStateHashError if the tip moved
  });
} catch (e) {
  if (e instanceof StaleStateHashError) { /* retry */ }
}

// 5. Participants.
await addParticipant(db, {
  objectId: schedule.id,
  identityRef: 'cert-todd',
  participantRole: 'admin',
});
```

## Optimistic concurrency

Every patch write is guarded:

1. Read the object's `current_state_hash` + `current_version`.
2. Write the patch with `prev_state_hash = current_state_hash`.
3. UPDATE the object SET `current_state_hash = new`, `current_version = v + 1` WHERE `current_version = v`.
4. If the UPDATE affects 0 rows, someone else advanced the tip between our read and write. Throw `StaleStateHashError`.

Pass `expectedPrevStateHash` to `appendPatch` to make the contention explicit (recommended). Omit it to say "just append, don't check" (use sparingly — dangerous for conflict-sensitive streams).

## Installation

```bash
pnpm add @semantos/semantic-objects
```

Configure `.npmrc`:
```
@semantos:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
```

## Migration

```bash
psql $DATABASE_URL -f node_modules/@semantos/semantic-objects/migrations/0000_init.sql
```

## Performance

Fold is O(n) in the number of patches per object. For hot queries, either:
- Checkpoint via `sem_object_states` and fold from the latest checkpoint.
- Build a materialized projection table in your domain (opt-in).

For single-operator scale (thousands of patches), plain fold is microseconds.
