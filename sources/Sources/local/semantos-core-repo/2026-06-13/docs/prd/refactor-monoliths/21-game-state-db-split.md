---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/21-game-state-db-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.776079+00:00
---

# 21 — Split `apps/poker-agent/src/game-state-db.ts`

**Phase:** 7 (Poker stack) · **Depends on:** 01 · **Est. effort:** 0.5 day · **Branch:** `refactor/21-game-state-db`

## Why

513 LOC SQLite wrapper covering sessions, hands, actions, snapshots, CellToken refs, agent memory — all querying and mutating via inline SQL.

## Deliverables

Create under `apps/poker-agent/src/game-state-db/`:

- `schema.ts` — all SQL DDL in one place, versioned. Migrations.
- `row-mappers.ts` — `mapSessionRow`, `mapHandRow`, `mapActionRow`, etc. Export for tests.
- `session-store.ts` — sessions + players.
- `hand-store.ts` — hands + winner + pot.
- `action-store.ts` — seq-numbered actions. Internal seq counter.
- `snapshot-store.ts` — phase snapshots.
- `memory-store.ts` — agent memory K-V.
- `context-builder.ts` — pure queries: `getCurrentHandContext`, `getGameHistory`.
- `game-state-db.ts` — facade composing the stores.
- `__tests__/*.test.ts`.

Edit:

- `apps/poker-agent/src/game-state-db.ts` → re-export facade.

## Acceptance criteria

- [ ] Inline SQL strings only in `schema.ts` or the specific store file that owns the table — no cross-file SQL.
- [ ] Row mappers exported and tested standalone.
- [ ] All existing queries return identical results.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing the SQLite schema.

## Test plan

Seed DB with fixture data; run every public method pre- and post-refactor; results byte-identical.
