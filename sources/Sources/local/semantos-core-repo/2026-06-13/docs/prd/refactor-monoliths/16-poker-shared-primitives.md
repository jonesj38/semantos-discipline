---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/16-poker-shared-primitives.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.774564+00:00
---

# 16 — Poker stack: shared primitives

**Phase:** 7 (Poker stack) · **Depends on:** 14 · **Est. effort:** 0.5 day · **Branch:** `refactor/16-poker-shared-primitives`

## Why

Six poker files reimplement the same building blocks: BEEF array conversion, deterministic shuffle, audit-log rendering. Extract them once so the subsequent prompts just import.

## Deliverables

Create under `apps/poker-agent/src/shared/`:

- `beef-codec.ts` — `toArray(beef): number[]`, `fromArray(arr): Beef`. Single source of truth.
- `deterministic-shuffle.ts` — pure `shuffle(seed: string, deck: Card[]): Card[]` using SHA-256-based PRNG. Must be bit-identical across both players.
- `audit-log-builder.ts` — pure builder for hand audit logs; accepts event stream, returns formatted string.
- `card-types.ts` — `Card`, `Rank`, `Suit`, `Hand` shared across poker files.
- `hand-evaluator.ts` — if evaluator logic currently duplicated (check `extensions/games/cards/poker.ts` and `apps/poker-agent/src/game-loop.ts`), consolidate here. Otherwise, port from whichever file is canonical and delete duplicates.
- `__tests__/*.test.ts`.

Edit:

- Any existing file that defines these locally — remove local definitions, import from `shared/`.

## Acceptance criteria

- [ ] Zero duplicate definitions of BEEF conversion or shuffle logic across poker files.
- [ ] Shuffle determinism test: same seed → identical deck across 1000 iterations.
- [ ] All existing poker tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Refactoring the poker files that use these primitives (prompts 17–21).

## Test plan

Diff shuffle output of old local impls against new `deterministic-shuffle.ts` — must be bit-identical for ≥100 seeds.
