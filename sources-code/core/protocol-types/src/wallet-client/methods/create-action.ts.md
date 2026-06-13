---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/methods/create-action.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.909133+00:00
---

# core/protocol-types/src/wallet-client/methods/create-action.ts

```ts
import type { CreateActionRequest, CreateActionResult } from '../types';
import type { HttpTransport, HttpTransportContext } from '../wallet-http-transport';
import { buildCreateAction } from '../wallet-request-builder';
import { parseCreateAction } from '../wallet-response-parser';
import { runMethod } from './method-runner';

export function createAction(
  transport: HttpTransport,
  ctx: HttpTransportContext,
  req: CreateActionRequest,
): Promise<CreateActionResult> {
  return runMethod(
    transport,
    ctx,
    buildCreateAction(ctx.originator, req),
    parseCreateAction,
    'createAction',
  );
}

```
