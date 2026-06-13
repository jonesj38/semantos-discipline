---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/26-chess-stakes-strategy-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.770837+00:00
---

# 26 — Split `extensions/games/src/chess-stakes/strategy.ts`

**Phase:** 8 (MUD + games) · **Depends on:** 22 · **Est. effort:** 0.5 day · **Branch:** `refactor/26-chess-stakes-strategy`

## Why

764 LOC strategy module for chess-with-stakes: evaluation function, move ordering, search, time management, staking integration.

## Deliverables

Create under `extensions/games/src/chess-stakes/strategy/`:

- `evaluation.ts` — pure material + positional eval.
- `move-ordering.ts` — pure heuristic ordering.
- `search.ts` — alpha-beta / iterative deepening loop.
- `time-manager.ts` — allocate-time-for-move helper.
- `stakes-integration.ts` — ties evaluator to the staking side via `channelPort` / `paymentChannelFacade`.
- `strategy-facade.ts`.
- `__tests__/*.test.ts`.

Edit:

- `extensions/games/src/chess-stakes/strategy.ts` → re-export facade.

## Acceptance criteria

- [ ] Search depth / time budget configurable.
- [ ] Evaluation pure (no timing side-effects).
- [ ] All existing strategy tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing engine strength or search algorithm tuning.

## Test plan

Fixed-position test suite (mate-in-N puzzles) returns the same best moves pre- and post-refactor.
