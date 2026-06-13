---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/anchor-helpers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.778172+00:00
---

# archive/apps-poker-agent/src/game-loop/anchor-helpers.ts

```ts
/**
 * Tiny coordination helpers for the LINEAR + OP_RETURN anchoring
 * pattern repeated all through `playHand()`.
 *
 * Each helper takes the (live) txid accumulators and bumps the
 * counters so the orchestrator stays focused on phase control.
 */

import type { AnchorResult } from '../poker-state-machine';

export interface AnchorAccumulators {
  handTxids: string[];
  stateChain: string[];
  /** Increment to bump GameLoop.totalTxCount + linearTxCount. */
  bumpLinear: () => void;
  /** Increment to bump GameLoop.totalTxCount + eventTxCount. */
  bumpEvent: () => void;
}

/** Push a CellToken anchor onto both lists + bump linear counters. */
export function recordLinear(
  accs: AnchorAccumulators,
  anchor: AnchorResult | null,
): AnchorResult | null {
  if (!anchor) return null;
  accs.stateChain.push(anchor.txid);
  accs.handTxids.push(anchor.txid);
  accs.bumpLinear();
  return anchor;
}

/** Push an OP_RETURN anchor onto handTxids + bump event counters. */
export function recordEvent(
  accs: AnchorAccumulators,
  anchor: AnchorResult | null,
): AnchorResult | null {
  if (!anchor) return null;
  accs.handTxids.push(anchor.txid);
  accs.bumpEvent();
  return anchor;
}

```
