---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/type-hasher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.867120+00:00
---

# core/protocol-types/src/semantic-fs/type-hasher.ts

```ts
/**
 * Type-hash derivation — SHA-256 of the dotted taxonomy path.
 *
 * The semantic-fs facade calls this when writing an object so the
 * `typeHash` header field uniquely identifies the taxonomy node the
 * object lives under. Pure-ish: routes through the bindable
 * `contentHasherPort` so tests can inject a deterministic stub.
 */

import { hexToBytes, sha256 } from '../cell-store/content-hasher';

/**
 * Compute the 32-byte typeHash for a taxonomy path expressed as
 * segment array. e.g. `["create", "job", "plumbing"]` →
 * `SHA-256("create.job.plumbing")` as a 32-byte buffer.
 */
export async function computeTypeHash(taxonomyPath: string[]): Promise<Uint8Array> {
  const dotted = taxonomyPath.join('.');
  const hash = await sha256(new TextEncoder().encode(dotted));
  return hexToBytes(hash);
}

```
