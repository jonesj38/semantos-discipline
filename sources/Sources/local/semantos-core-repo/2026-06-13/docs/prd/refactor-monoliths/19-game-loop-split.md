---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/19-game-loop-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.769834+00:00
---

# 19 — Split `apps/poker-agent/src/game-loop.ts`

**Phase:** 7 (Poker stack) · **Depends on:** 16, 17 · **Est. effort:** 1 day · **Branch:** `refactor/19-game-loop`

## Why

1056 LOC: orchestrates 2-player poker with Claude agents, deck shuffle/deal/draw, phases (preflop → showdown), betting, chip management, state persistence, payment-channel settlement, policy validation, event callbacks.

## Deliverables

Create under `apps/poker-agent/src/game-loop/`:

- `deck-manager.ts` — wraps `shared/deterministic-shuffle.ts`; deal, draw, card descriptors.
- `betting-engine.ts` — pure: blinds, bet/call/raise/fold → `PlayerDelta` immutable values.
- `phase-fsm.ts` — pure reducer: `(phase, event) → nextPhase`, phases and transitions.
- `hand-context-builder.ts` — pure: `(me, opponent, table, config) → HandContext` for Claude.
- `policy-validator.ts` — thin kernel adapter; uses `HostFunctionRegistry` + `CompiledPokerPolicies`.
- `game-events.ts` — `gameEventBus = eventBus<GameEvent>()`; external subscribers replace callback injection.
- `atoms.ts` — `playersAtom`, `tableStateAtom`, `currentHandAtom`.
- `game-loop-facade.ts` — orchestrator; accepts state-machine, db, channel via ports.
- `__tests__/*.test.ts`.

Edit:

- `apps/poker-agent/src/game-loop.ts` → re-export facade.

## Acceptance criteria

- [ ] Betting engine is pure (no `this`, no `Math.random`).
- [ ] Phase FSM has transition tests for every (phase, event) pair.
- [ ] `GameEvent`s flow through event bus; no direct callbacks.
- [ ] All existing e2e tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing poker rules or agent prompts.

## Test plan

Replay a recorded 20-hand match; verify identical action sequence, pot sizes, and final chip counts.
