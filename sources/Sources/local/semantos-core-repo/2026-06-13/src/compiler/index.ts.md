---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/compiler/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.397234+00:00
---

# src/compiler/index.ts

```ts
/**
 * Plexus Compiler: Re-exports
 *
 * Central export point for all compiler functions.
 */

export {
  validateConsumption,
  validateAcknowledgement,
  validateDiscard,
  validateRevocation,
  validateCapabilitySpend,
  validateTransferRecord,
  classifyObject,
  isConsumed,
  canConsume,
} from './validator.js';

export type { Result } from './validator.js';

```
