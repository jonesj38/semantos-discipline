---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.761852+00:00
---

# archive/apps-poker-agent/src/poker-state-machine.ts

```ts
/**
 * @deprecated — use the split modules under
 * `apps/poker-agent/src/poker-state-machine/` instead.
 *
 * This file is the legacy single-file home for `PokerStateMachine`.
 * It now re-exports the facade + types from the prompt-17 module
 * split so existing call sites (`game-loop.ts`, `p2p-agent-runner.ts`)
 * keep compiling without edits during the deprecation window.
 *
 * Migration target imports:
 *
 *   import { PokerStateMachine } from './poker-state-machine/';
 *
 * The split surfaces the previously-private internals as testable
 * pure modules:
 *   - `cell-builder.ts`       — pure cell construction + version bump
 *   - `celltoken-signer.ts`   — deferred-signing flow
 *   - `p2p-key-manager.ts`    — atom-backed alternating pubkey track
 *   - `event-anchor.ts`       — OP_RETURN event + batch builder
 *   - `utxo-tracker.ts`       — `liveUtxoAtom` cache
 *   - `state-machine-facade.ts` — thin orchestrator class
 */

export {
  PokerStateMachine,
  type PokerStateMachineOptions,
  type AnchorResult,
  type HandStatePayload,
  type LiveUtxo,
  type PokerPhase,
} from './poker-state-machine/index';

```
