---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/wallet-http-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.873641+00:00
---

# core/protocol-types/src/wallet-client/wallet-http-transport.ts

```ts
/**
 * Wallet HTTP transport — bindable port wrapping a `fetch`-style
 * request with origin forwarding, BRC-100 originator header, and a
 * cancellation timeout.
 *
 * The default impl uses global `fetch`. Tests bind a stub via
 * `httpTransportPort.bind({ request: async (...) => stubResponse })`.
 */

import { port, type Port } from '@semantos/state';

import { WalletClientError } from './wallet-error';
import type { HttpMethod } from './types';

export interface HttpTransportContext {
  baseUrl: string;
  origin: string;
  originator: string;
  timeoutMs: number;
}

export interface HttpTransport {
  request(
    ctx: HttpTransportContext,
    method: HttpMethod,
    path: string,
    body?: unknown,
  ): Promise<unknown>;
}

export const httpTransportPort: Port<HttpTransport> = port<HttpTransport>('wallet-http');

/**
 * Default fetch-based transport. Throws a {@link WalletClientError}
 * tagged `HTTP_<status>` on non-2xx responses; pass-through to the
 * caller otherwise.
 */
export const defaultHttpTransport: HttpTransport = {
  async request(ctx, method, path, body) {
    const url = `${ctx.baseUrl}${path}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), ctx.timeoutMs);

    try {
      const headers: Record<string, string> = {
        Accept: 'application/json',
        Origin: ctx.origin,
        'X-BSV-Originator': ctx.originator,
      };

      const init: RequestInit = { method, headers, signal: controller.signal };

      if (body !== undefined) {
        headers['Content-Type'] = 'application/json';
        init.body = JSON.stringify(body);
      }

      const res = await fetch(url, init);

      if (!res.ok) {
        const text = await res.text().catch(() => '');
        throw new WalletClientError(
          `HTTP_${res.status}`,
          `Wallet responded ${res.status}: ${text.slice(0, 200)}`,
        );
      }

      return await res.json();
    } finally {
      clearTimeout(timer);
    }
  },
};

/** Resolve the active transport: the bound port, or the default. */
export function getTransport(): HttpTransport {
  if (httpTransportPort.isBound()) return httpTransportPort.get();
  return defaultHttpTransport;
}

```
