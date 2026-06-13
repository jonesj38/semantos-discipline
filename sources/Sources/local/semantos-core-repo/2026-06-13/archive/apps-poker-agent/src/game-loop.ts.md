---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.764086+00:00
---

# archive/apps-poker-agent/src/game-loop.ts

```ts
/**
 * @deprecated — use the split modules under
 * `apps/poker-agent/src/game-loop/` instead.
 *
 * This file is the legacy single-file home for `GameLoop`. Prompt 19
 * split it into per-responsibility modules:
 *
 *   - `deck-manager.ts`        — wraps shared/deterministic-shuffle
 *   - `betting-engine.ts`      — pure bet/call/raise/fold deltas
 *   - `phase-fsm.ts`           — pure (phase, event) → nextPhase
 *   - `hand-context-builder.ts` — pure HandContext stitcher
 *   - `policy-validator.ts`    — kernel-policy adapter
 *   - `game-events.ts`         — `gameEventBus<GameEvent>()`
 *   - `atoms.ts`               — `playersAtom`, `tableStateAtom`,
 *                                 `currentHandAtom`
 *   - `showdown.ts`            — legacy rank-sum + summary helpers
 *   - `betting-round-flow.ts`  — per-phase betting while-loop
 *   - `hand-flow.ts`           — `playHand()` orchestrator
 *   - `anchor-helpers.ts`      — LINEAR + OP_RETURN bookkeeping
 *   - `game-loop-facade.ts`    — thin `GameLoop` class
 *
 * Migration target imports:
 *
 *   import { GameLoop } from './game-loop/';
 */

export {
  GameLoop,
  DEFAULT_GAME_CONFIG,
  type GameEvent,
  type GameEventCallback,
  type GameLoopConfig,
  type HandResult,
  type Phase,
  type SimplePlayer,
  type SimpleTable,
} from './game-loop/index';

```
