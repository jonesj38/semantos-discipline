---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/hrr-library/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.298739+00:00
---

# runtime/hrr-library/src/index.ts

```ts
/**
 * @semantos/hrr-library — HRR vector library for analogical intent retrieval.
 *
 * Populated from NATS `intent_outcome` + `stable_transition` events.
 * Query API: nearest(query, domainFlag, jural, k, capabilities).
 * Snapshot API: serialise() / deserialise(snapshot).
 */

export { HrrLibrary } from './library';
export type {
  IntentOutcomeEvent,
  StableTransitionEvent,
  LibrarySnapshot,
} from './library';

```
