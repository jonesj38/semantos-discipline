---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/signing-key-deriver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.915399+00:00
---

# core/protocol-types/src/identity-adapters/local/signing-key-deriver.ts

```ts
/**
 * Signing-key derivation isolation.
 *
 * `sigKeyFromPem(pem)` mirrors `CapabilityTokenValidator.keyFromPublicKey`
 * — must produce the same 32-byte buffer as the validator otherwise
 * round-trip token validation breaks. Pulled out so tests can pin the
 * deterministic derivation against golden vectors without spinning up
 * a full adapter.
 */

import { createHash } from 'crypto';

/** SHA-256 of a UTF-8 string, returned as lowercase hex. */
export function sha256HexStr(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

/**
 * Derive a 32-byte signing key from a public-key PEM. Same algorithm
 * used by CapabilityTokenValidator — keep them in lockstep.
 */
export function sigKeyFromPem(pem: string): Uint8Array {
  const hash = createHash('sha256').update(pem).digest();
  return new Uint8Array(hash.buffer, hash.byteOffset, hash.byteLength);
}

```
