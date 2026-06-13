---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/methods/get-public-key.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.910824+00:00
---

# core/protocol-types/src/wallet-client/methods/get-public-key.ts

```ts
import type { HttpTransport, HttpTransportContext } from '../wallet-http-transport';
import { buildGetPublicKey } from '../wallet-request-builder';
import { parseGetPublicKey } from '../wallet-response-parser';
import { runMethod } from './method-runner';

export interface GetPublicKeyArgs {
  identityKey?: boolean;
  protocolID?: [number, string];
  keyID?: string;
  counterparty?: string;
}

export function getPublicKey(
  transport: HttpTransport,
  ctx: HttpTransportContext,
  args?: GetPublicKeyArgs,
): Promise<string> {
  return runMethod(
    transport,
    ctx,
    buildGetPublicKey(ctx.originator, args),
    parseGetPublicKey,
    'getPublicKey',
  );
}

```
