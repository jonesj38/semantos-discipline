---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/ports/signer-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.902349+00:00
---

# core/protocol-types/src/ports/signer-port.ts

```ts
/**
 * Signer port — abstracts BSV signing operations from concrete
 * `PrivateKey` instances. Implementations route through the active
 * wallet's `createSignature` (BRC-100) or a local key store.
 */

import { port, type Port } from '@semantos/state';

export interface Signature {
  /** DER-encoded ECDSA signature, hex. */
  hex: string;
  /** Optional sighash flag byte the signer encoded with. */
  sighashFlag?: number;
}

export interface Signer {
  /** Produce an ECDSA signature for `message` with the named keyID. */
  sign(message: Uint8Array, keyId: string): Promise<Signature>;
  /** Resolve the public key (66-hex compressed) for the named keyID. */
  derivePublicKey(keyId: string): Promise<string>;
}

export const signerPort: Port<Signer> = port<Signer>('signer');

```
