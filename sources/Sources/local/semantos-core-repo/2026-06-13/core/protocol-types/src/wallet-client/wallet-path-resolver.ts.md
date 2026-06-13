---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/wallet-path-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.873906+00:00
---

# core/protocol-types/src/wallet-client/wallet-path-resolver.ts

```ts
/**
 * Path resolver — try multiple BRC-100 API paths in order, returning
 * the first successful response. Handles the metanet-desktop (no
 * /v1 prefix) vs bsv-desktop (/v1 prefix) compatibility split.
 *
 * If the wallet returns a 4xx/5xx that isn't a 404 we surface it
 * immediately — only "endpoint not found" responses fall through to
 * the next candidate.
 */

import type { HttpMethod } from './types';
import type { HttpTransport, HttpTransportContext } from './wallet-http-transport';
import { WalletClientError } from './wallet-error';

export async function tryPaths(
  transport: HttpTransport,
  ctx: HttpTransportContext,
  method: HttpMethod,
  paths: string[],
  body?: unknown,
): Promise<unknown> {
  let lastError: Error | null = null;
  for (const path of paths) {
    try {
      return await transport.request(ctx, method, path, body);
    } catch (err) {
      if (err instanceof WalletClientError && !err.code.startsWith('HTTP_404')) {
        throw err;
      }
      lastError = err as Error;
    }
  }
  throw lastError ?? new WalletClientError('NO_PATH', 'All API paths failed');
}

```
