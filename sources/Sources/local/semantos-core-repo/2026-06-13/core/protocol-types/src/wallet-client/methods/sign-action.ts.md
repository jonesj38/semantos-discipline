---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/methods/sign-action.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.908834+00:00
---

# core/protocol-types/src/wallet-client/methods/sign-action.ts

```ts
import type { CreateActionResult } from '../types';
import type { HttpTransport, HttpTransportContext } from '../wallet-http-transport';
import { buildSignAction } from '../wallet-request-builder';
import { parseSignAction } from '../wallet-response-parser';
import { runMethod } from './method-runner';

export interface SignActionArgs {
  reference: string;
  spends: Record<number, { unlockingScript: string | number[] }>;
}

export function signAction(
  transport: HttpTransport,
  ctx: HttpTransportContext,
  args: SignActionArgs,
): Promise<CreateActionResult> {
  return runMethod(
    transport,
    ctx,
    buildSignAction(ctx.originator, args),
    parseSignAction,
    'signAction',
  );
}

```
