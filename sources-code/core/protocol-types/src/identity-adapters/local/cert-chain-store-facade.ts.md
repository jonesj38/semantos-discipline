---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/cert-chain-store-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.915124+00:00
---

# core/protocol-types/src/identity-adapters/local/cert-chain-store-facade.ts

```ts
/**
 * Thin re-export of CertChainStore. The pre-split LocalIdentityAdapter
 * created the store inside its constructor and reached into it
 * directly; the new design treats it as an injectable dependency so
 * tests can wrap or stub it without subclassing the adapter.
 *
 * The interface here intentionally mirrors `CertChainStore`'s public
 * methods 1:1 — anything beyond that lives in dedicated handler files.
 */

export { CertChainStore } from '../CertChainStore';
export type { CertData } from '../CertChainStore';

```
