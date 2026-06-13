---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/methods/is-authenticated.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.910545+00:00
---

# core/protocol-types/src/wallet-client/methods/is-authenticated.ts

```ts
import type { HttpTransport, HttpTransportContext } from '../wallet-http-transport';
import { buildIsAuthenticated } from '../wallet-request-builder';
import { parseIsAuthenticated } from '../wallet-response-parser';

/**
 * isAuthenticated is special: any failure counts as "not
 * authenticated" rather than throwing — we walk each candidate path
 * and silently swallow errors, returning false at the end.
 */
export async function isAuthenticated(
  transport: HttpTransport,
  ctx: HttpTransportContext,
): Promise<boolean> {
  const spec = buildIsAuthenticated();
  for (const path of spec.paths) {
    try {
      const raw = await transport.request(ctx, spec.method, path);
      return parseIsAuthenticated(raw);
    } catch {
      continue;
    }
  }
  return false;
}

```
