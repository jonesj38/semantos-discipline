---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-contracts/src/transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.822609+00:00
---

# core/plexus-contracts/src/transport.ts

```ts
/**
 * BRC-100 transport header constants.
 *
 * Based on Plexus Technical Requirements v1.3 — Network SDK (component 4).
 * All network interactions must include these headers for authentication.
 */

/** BRC-100 identity key header — 33-byte compressed public key, hex-encoded. */
export const BRC100_HEADER_IDENTITY_KEY = 'x-brc100-identitykey';

/** BRC-100 nonce header — random value to prevent replay. */
export const BRC100_HEADER_NONCE = 'x-brc100-nonce';

/** BRC-100 timestamp header — Unix timestamp of the request. */
export const BRC100_HEADER_TIMESTAMP = 'x-brc100-timestamp';

/** BRC-100 signature header — ECDSA signature of the canonical request preimage. */
export const BRC100_HEADER_SIGNATURE = 'x-brc100-signature';

/** BRC-52 certificate header — serialized certificate for identity binding. */
export const BRC52_HEADER_CERTIFICATE = 'x-brc52-certificate';

```
