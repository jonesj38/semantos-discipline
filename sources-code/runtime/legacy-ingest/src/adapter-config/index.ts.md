---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/adapter-config/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.155603+00:00
---

# runtime/legacy-ingest/src/adapter-config/index.ts

```ts
/**
 * CC6.3a — Adapter-config module barrel.
 * See `./types.ts` (the shape) + `./default-oddjobz-config.ts` (the
 * default seed); together they form the dependency-injection seam that
 * lets the EmailExtractor consume per-source rules without hardcoded
 * constants.
 */

export type {
  AdapterConfigMetadata,
  BillingRule,
  BillingRuleOutcome,
  DomainMatch,
  PromptFragments,
} from './types';
export { DEFAULT_ODDJOBZ_ADAPTER_CONFIG } from './default-oddjobz-config';

```
