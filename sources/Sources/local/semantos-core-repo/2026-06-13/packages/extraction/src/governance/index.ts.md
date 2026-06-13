---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/governance/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.458058+00:00
---

# packages/extraction/src/governance/index.ts

```ts
/**
 * Governance — constraint enforcement and version compatibility for extensions.
 */

export {
  enforceL0Constraints,
  enforceL1Constraints,
  type ConstraintResult,
  type ObjectPayload,
  type IdentityContext,
} from './constraint-engine';

export {
  checkCompatibility,
} from './version-compat';

```
