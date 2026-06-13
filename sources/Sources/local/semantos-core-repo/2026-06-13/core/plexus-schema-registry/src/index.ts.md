---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.946498+00:00
---

# core/plexus-schema-registry/src/index.ts

```ts
/**
 * @semantos/plexus-schema-registry — Phase H RM-012.
 *
 * Maps `(domain_flag, version) → DomainSchema`; encodes/decodes
 * payload bytes per the schema; computes `domainPayloadRoot`;
 * persists schemas under the vendor identity for recovery; verifies
 * signed schemas under a `SchemaAuthority`. See
 * `docs/PHASE-H-HEADER-CLEANUP-SPEC.md` §4.1 for the design.
 */
export * from './types.js';
export * from './encoding.js';
export * from './hash.js';
export * from './registry.js';
export * from './persistence.js';
export * from './schemas/index.js';

```
