---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/wallet-error-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.874183+00:00
---

# core/protocol-types/src/wallet-client/wallet-error-handler.ts

```ts
/**
 * Wallet error decoder — translates a JSON response that contains a
 * BRC-100 `{status: "error", code, description}` envelope into a
 * {@link WalletClientError}, with sensible fallbacks for partial
 * responses.
 *
 * Method handlers call `throwIfError(response, 'createAction')` after
 * decoding so the caller never sees a `{status: 'error'}` payload.
 */

import { WalletClientError } from './wallet-error';

/**
 * Inspect a wallet response. When it carries `{status: 'error', …}`
 * throw a WalletClientError tagged with the supplied operation name.
 */
export function throwIfError(response: unknown, operation: string): void {
  if (
    response &&
    typeof response === 'object' &&
    (response as { status?: string }).status === 'error'
  ) {
    const err = response as { code?: string; description?: string };
    throw new WalletClientError(
      err.code ?? 'UNKNOWN',
      err.description ?? `${operation} failed`,
    );
  }
}

/**
 * Pure constructor — used by the path resolver for HTTP-level errors
 * where the wallet didn't return a structured envelope.
 */
export function toWalletClientError(code: string, message: string): WalletClientError {
  return new WalletClientError(code, message);
}

```
