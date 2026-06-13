---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/wallet-error.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.873372+00:00
---

# core/protocol-types/src/wallet-client/wallet-error.ts

```ts
/**
 * WalletClientError — single-source-of-truth error class for the
 * wallet client. Every method (and the transport itself) throws
 * instances of this class so callers get a stable surface to catch.
 */

export class WalletClientError extends Error {
  constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'WalletClientError';
  }
}

```
