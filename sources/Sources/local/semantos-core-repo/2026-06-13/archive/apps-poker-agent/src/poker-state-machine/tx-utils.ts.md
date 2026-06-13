---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/tx-utils.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.768754+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/tx-utils.ts

```ts
/**
 * Tiny helpers shared by `create-hand-flow.ts` and `transition-flow.ts`.
 * Keeping them here avoids duplication and lets each flow file stay
 * under the prompt-17 250-LOC ceiling.
 */

import type { BsvLazy } from './celltoken-signer';

/**
 * Find the vout matching `scriptHex` in a BEEF-decoded transaction.
 * Falls back to the last 1-sat output, then 0 if parsing fails.
 */
export function locateVout(bsv: BsvLazy, beefBytes: number[], scriptHex: string): number {
  try {
    const tx = bsv.Transaction.fromAtomicBEEF(beefBytes);
    let fallback = 0;
    for (let i = 0; i < tx.outputs.length; i++) {
      if (tx.outputs[i].lockingScript?.toHex() === scriptHex) return i;
      if (Number(tx.outputs[i].satoshis) === 1) fallback = i;
    }
    return fallback;
  } catch {
    return 0;
  }
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

```
