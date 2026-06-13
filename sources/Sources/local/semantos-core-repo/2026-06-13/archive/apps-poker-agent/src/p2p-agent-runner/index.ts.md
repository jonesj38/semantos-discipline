---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.785812+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/index.ts

```ts
/**
 * P2P-agent-runner module barrel — public surface for the prompt-20
 * split.
 */

export {
  type AuditLogEntry,
  type P2PAgentConfig,
  type P2PHandResult,
  type PlayerState,
  type TableState,
} from './types';

export { P2PAgentRunner } from './p2p-agent-runner-facade';

export {
  transportPort,
  type Transport,
  type TransportFactory,
  type TransportFactoryArgs,
  type OnMoveCallback,
  type OnControlCallback,
  type PokerControlMessage,
  type PokerMoveMessage,
} from './transport-port';

export {
  bindDefaultP2PTransport,
  type DefaultTransportBindingOptions,
} from './default-bindings';

export {
  awaitMyTurn,
  flipTurn,
  getTurn,
  getTurnAtoms,
  resetTurnAtoms,
  setTurn,
  type Turn,
  type TurnAtoms,
} from './turn-coordinator';

export {
  enqueueMove,
  getMessageQueueAtoms,
  queueDepth,
  resetMessageQueueAtoms,
  waitForMove,
  type MessageQueueAtoms,
} from './message-queue';

export {
  awaitControl,
  sendControl,
  sendMove,
  type SendMoveArgs,
} from './beef-transceiver';

export {
  dealForP2P,
  makeDeckCursor,
  shuffleSeedFor,
  type DealResult,
} from './hand-shuffle';

export {
  buildHandContext,
  getLegalActions,
  type BuildContextArgs,
} from './p2p-context-builder';

export {
  buildStatePayload,
  type BuildPayloadArgs,
} from './p2p-state-payload';

export {
  executeAction,
  placeBet,
  type BettingDecision,
} from './p2p-betting-engine';

export {
  renderAuditLog,
  type RenderAuditOptions,
} from './audit-log-renderer';

export { playHand, type PlayHandArgs } from './p2p-hand-flow';

export {
  runP2PBettingLoop,
  type BettingLoopArgs,
} from './p2p-betting-loop';

export {
  setupHand,
  type PreHandSetupArgs,
  type PreHandSetupResult,
} from './p2p-pre-hand';

```
