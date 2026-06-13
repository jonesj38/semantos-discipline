---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/hash.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.947876+00:00
---

# core/plexus-schema-registry/src/hash.ts

```ts
/**
 * `computeDomainPayloadRoot` — 32B SHA-256 over the encoded payload
 * bytes per the schema. This is the value the kernel reads at the
 * fixed `domainPayloadRoot` offset of the cell header (RM-023).
 */
import { createHash } from 'node:crypto';
import { encodePayload } from './encoding.js';
import type { DomainSchema } from './types.js';

/** Hash bytes already encoded. */
export function computePayloadRootFromBytes(bytes: Uint8Array): Uint8Array {
  const h = createHash('sha256');
  h.update(bytes);
  return new Uint8Array(h.digest());
}

/** Encode a payload Record then hash the result. */
export function computeDomainPayloadRoot(
  schema: DomainSchema,
  values: Record<string, unknown>,
): Uint8Array {
  return computePayloadRootFromBytes(encodePayload(schema, values));
}

```
