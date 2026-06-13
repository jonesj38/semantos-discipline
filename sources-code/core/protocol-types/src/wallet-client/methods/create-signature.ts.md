---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/methods/create-signature.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.911113+00:00
---

# core/protocol-types/src/wallet-client/methods/create-signature.ts

```ts
import type { HttpTransport, HttpTransportContext } from '../wallet-http-transport';
import { buildCreateSignature } from '../wallet-request-builder';
import { parseCreateSignature } from '../wallet-response-parser';
import { runMethod } from './method-runner';

export interface CreateSignatureArgs {
  protocolID: [number, string];
  keyID: string;
  counterparty: string;
  data: number[];
  hashToDirectlySign?: number[];
}

export function createSignature(
  transport: HttpTransport,
  ctx: HttpTransportContext,
  args: CreateSignatureArgs,
): Promise<{ signature: number[] }> {
  return runMethod(
    transport,
    ctx,
    buildCreateSignature(ctx.originator, args),
    parseCreateSignature,
    'createSignature',
  );
}

```
