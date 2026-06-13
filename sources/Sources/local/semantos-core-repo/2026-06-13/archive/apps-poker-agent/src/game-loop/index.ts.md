---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.776735+00:00
---

# archive/apps-poker-agent/src/game-loop/index.ts

```ts
/**
 * Game-loop module barrel — exposes the prompt-19 split surface.
 */

export {
  DEFAULT_GAME_CONFIG,
  type CardDescriptor,
  type GameEvent,
  type GameEventCallback,
  type GameLoopConfig,
  type HandResult,
  type Phase,
  type PlayerActionKind,
  type PlayerDecision,
  type SimplePlayer,
  type SimpleTable,
} from './types';

export { GameLoop } from './game-loop-facade';

export {
  getGameAtoms,
  resetGameAtoms,
  type GameAtoms,
} from './atoms';

export {
  deckCommitment,
  drawCard,
  drawCards,
  newDeck,
  type Deck,
  type ShuffleOptions,
} from './deck-manager';

export {
  executeAction,
  placeBet,
  type BetResult,
  type PlayerDelta,
  type TableDelta,
} from './betting-engine';

export {
  PHASE_ORDER,
  nextEventFrom,
  phaseReducer,
  type PhaseEvent,
  type PhaseTransitionResult,
} from './phase-fsm';

export {
  buildHandContext,
  getLegalActions,
  type BuildHandContextOptions,
} from './hand-context-builder';

export {
  makePolicyValidator,
  type PolicyValidator,
  type PolicyValidatorOptions,
} from './policy-validator';

export {
  emitGameEvent,
  getGameEventBus,
  resetGameEventBuses,
  type EmitGameEventArgs,
} from './game-events';

export {
  simpleShowdown,
  totalsByName,
} from './showdown';

export { playHand, type PlayHandContext } from './hand-flow';

export {
  recordEvent,
  recordLinear,
  type AnchorAccumulators,
} from './anchor-helpers';

export {
  runBettingRound,
  type BettingRoundContext,
} from './betting-round-flow';

```
