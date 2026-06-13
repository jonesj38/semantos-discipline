---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/methods/get-network.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.911386+00:00
---

# core/protocol-types/src/wallet-client/methods/get-network.ts

```ts
import type { HttpTransport, HttpTransportContext } from '../wallet-http-transport';
import { buildGetNetwork } from '../wallet-request-builder';
import { parseGetNetwork } from '../wallet-response-parser';
import { runMethod } from './method-runner';

export function getNetwork(
  transport: HttpTransport,
  ctx: HttpTransportContext,
): Promise<'mainnet' | 'testnet'> {
  return runMethod(transport, ctx, buildGetNetwork(), parseGetNetwork, 'getNetwork');
}

```
