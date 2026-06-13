---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.762988+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner.ts

```ts
/**
 * @deprecated — use the split modules under
 * `apps/poker-agent/src/p2p-agent-runner/` instead.
 *
 * This file is the legacy single-file home for `P2PAgentRunner`.
 * Prompt 20 split it into per-responsibility modules:
 *
 *   - `transport-port.ts`        — `transportPort = port<TransportFactory>()`
 *                                  with `Transport` interface
 *   - `default-bindings.ts`      — production binding to
 *                                  `PokerMessageTransport`
 *   - `turn-coordinator.ts`      — `turnAtom = atom<'mine'|'opponent'>` +
 *                                  `awaitMyTurn(gameId)` promise
 *   - `message-queue.ts`         — atom-backed FIFO + `waitForMove`
 *                                  effect
 *   - `beef-transceiver.ts`      — sendMove/sendControl/awaitControl
 *                                  (BEEF normalised via shared/beef-codec)
 *   - `hand-shuffle.ts`          — deterministic deal via prompt-16
 *                                  shared/deterministic-shuffle
 *   - `p2p-context-builder.ts`   — pure HandContext + getLegalActions
 *   - `p2p-state-payload.ts`     — pure HandStatePayload
 *   - `p2p-betting-engine.ts`    — fold/check/call/bet/raise/all-in
 *   - `audit-log-renderer.ts`    — pure stringifier
 *   - `p2p-pre-hand.ts`          — reset / deal / blinds / v1 anchor
 *   - `p2p-betting-loop.ts`      — phase walk + alternating turns
 *   - `p2p-hand-flow.ts`         — `playHand()` orchestrator
 *   - `p2p-agent-runner-facade.ts` — thin `P2PAgentRunner` class
 *
 * Migration target imports:
 *
 *   import { P2PAgentRunner } from './p2p-agent-runner/';
 */

export {
  P2PAgentRunner,
  type P2PAgentConfig,
  type P2PHandResult,
} from './p2p-agent-runner/index';

```
