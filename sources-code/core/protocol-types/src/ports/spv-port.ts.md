---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/ports/spv-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.901809+00:00
---

# core/protocol-types/src/ports/spv-port.ts

```ts
/**
 * SPV-verifier port — the FSM gate at FLOW_READY/SETTLING (CLAUDE.md
 * rule 2) must call `verifyBeef` or `verifyBump` before the reducer
 * advances the state. Implementations route through the BSV SPV
 * stack or a deterministic stub for tests.
 */

import { port, type Port } from '@semantos/state';

export interface SpvVerifier {
  /** Verify a BEEF-encoded transaction's Merkle proof against the chain. */
  verifyBeef(beef: string | number[], txid: string): Promise<boolean>;
  /** Verify a BUMP-format Merkle proof for the given txid. */
  verifyBump(bump: string, txid: string): Promise<boolean>;
}

export const spvPort: Port<SpvVerifier> = port<SpvVerifier>('spv');

```
