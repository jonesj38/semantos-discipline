---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/__tests__/stub-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.912010+00:00
---

# core/protocol-types/src/wallet-client/__tests__/stub-transport.ts

```ts
/**
 * Test-only HttpTransport stub. Records every request and yields a
 * caller-supplied response keyed by `(method, path)`. Tests assert on
 * the recorded request bag *and* the public method's return shape.
 */

import type {
  HttpMethod,
} from '../types';
import type {
  HttpTransport,
  HttpTransportContext,
} from '../wallet-http-transport';

export interface RecordedRequest {
  ctx: HttpTransportContext;
  method: HttpMethod;
  path: string;
  body: unknown;
}

export type StubResponder = (req: RecordedRequest) => unknown | Promise<unknown>;

export interface StubTransport extends HttpTransport {
  recorded: RecordedRequest[];
}

export function makeStubTransport(responder: StubResponder): StubTransport {
  const recorded: RecordedRequest[] = [];
  return {
    recorded,
    request: async (ctx, method, path, body) => {
      const entry: RecordedRequest = { ctx, method, path, body };
      recorded.push(entry);
      return responder(entry);
    },
  };
}

/** A 404-ish HTTP error so path resolver tests can exercise fallback. */
export class StubNotFound extends Error {
  readonly code = 'HTTP_404';
  constructor(path: string) {
    super(`stub: no handler for ${path}`);
  }
}

```
