---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/methods/internalize-action.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.910268+00:00
---

# core/protocol-types/src/wallet-client/methods/internalize-action.ts

```ts
import type { InternalizeActionRequest } from '../types';
import type { HttpTransport, HttpTransportContext } from '../wallet-http-transport';
import { buildInternalizeAction } from '../wallet-request-builder';
import { parseInternalizeAction } from '../wallet-response-parser';
import { runMethod } from './method-runner';

export function internalizeAction(
  transport: HttpTransport,
  ctx: HttpTransportContext,
  req: InternalizeActionRequest,
): Promise<{ accepted: boolean }> {
  return runMethod(
    transport,
    ctx,
    buildInternalizeAction(ctx.originator, req),
    parseInternalizeAction,
    'internalizeAction',
  );
}

```
