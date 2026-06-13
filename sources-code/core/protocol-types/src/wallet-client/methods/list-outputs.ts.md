---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/methods/list-outputs.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.909413+00:00
---

# core/protocol-types/src/wallet-client/methods/list-outputs.ts

```ts
import type { WalletOutputEntry } from '../types';
import type { HttpTransport, HttpTransportContext } from '../wallet-http-transport';
import { buildListOutputs } from '../wallet-request-builder';
import { parseListOutputs } from '../wallet-response-parser';
import { runMethod } from './method-runner';

export function listOutputs(
  transport: HttpTransport,
  ctx: HttpTransportContext,
  basket: string,
  tags?: string[],
  include?: 'locking scripts',
): Promise<WalletOutputEntry[]> {
  return runMethod(
    transport,
    ctx,
    buildListOutputs(ctx.originator, basket, tags, include),
    parseListOutputs,
    'listOutputs',
  );
}

```
