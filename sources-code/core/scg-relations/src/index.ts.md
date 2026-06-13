---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.816788+00:00
---

# core/scg-relations/src/index.ts

```ts
/**
 * @semantos/scg-relations — typed conversation-graph relations.
 *
 * Phase 1 of the Semantos Conversation Graph (SCG). Relations are
 * `sem_objects` rows of `objectKind='scg.relation'`, inheriting identity
 * binding, hashing, optimistic concurrency, and versioning from
 * `@semantos/semantic-objects`. No schema migration.
 *
 * See `docs/SCG-IMPLEMENTATION-TRACKING.md` and
 * `docs/SCG-AND-PHASE-H-ROADMAP.md` (RM-010) for the design.
 */
export * from './types.js';
export * from './lexicon.js';
export * from './operations.js';
export * from './capability.js';
export * from './branching.js';
export * from './access-gate.js';

```
