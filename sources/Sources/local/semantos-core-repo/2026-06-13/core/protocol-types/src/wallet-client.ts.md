---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.850101+00:00
---

# core/protocol-types/src/wallet-client.ts

```ts
/**
 * @deprecated Use `@semantos/protocol-types/wallet-client/wallet-client-facade`
 * (or the package barrel) instead. This module is a one-release
 * re-export shim for the new home of the wallet client under
 * `wallet-client/`. It will be removed once all consumers have
 * migrated.
 *
 * The split lives in `core/protocol-types/src/wallet-client/`:
 *   - `types.ts`                  — public interfaces
 *   - `wallet-error.ts`           — WalletClientError class
 *   - `wallet-error-handler.ts`   — `{status:'error'}` → throw
 *   - `wallet-http-transport.ts`  — bindable httpTransportPort
 *   - `wallet-path-resolver.ts`   — `tryPaths()` fallback walker
 *   - `wallet-request-builder.ts` — pure per-method body builders
 *   - `wallet-response-parser.ts` — pure per-method parsers
 *   - `methods/*.ts`              — one file per BRC-100 method
 *   - `wallet-client-facade.ts`   — public WalletClient class
 */

export { WalletClient } from './wallet-client/wallet-client-facade';
export { WalletClientError } from './wallet-client/wallet-error';
export type {
  CreateActionInput,
  CreateActionRequest,
  CreateActionResult,
  InternalizeActionRequest,
  InternalizeOutput,
  WalletClientConfig,
  WalletInput,
  WalletOutput,
  WalletOutputEntry,
} from './wallet-client/types';

```
