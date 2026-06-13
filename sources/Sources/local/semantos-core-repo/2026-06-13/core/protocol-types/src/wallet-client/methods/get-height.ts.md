---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/methods/get-height.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.909690+00:00
---

# core/protocol-types/src/wallet-client/methods/get-height.ts

```ts
import type { HttpTransport, HttpTransportContext } from '../wallet-http-transport';
import { buildGetHeight } from '../wallet-request-builder';
import { parseGetHeight } from '../wallet-response-parser';
import { runMethod } from './method-runner';

export function getHeight(
  transport: HttpTransport,
  ctx: HttpTransportContext,
): Promise<number> {
  return runMethod(transport, ctx, buildGetHeight(), parseGetHeight, 'getHeight');
}

```
