---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/methods/method-runner.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.909975+00:00
---

# core/protocol-types/src/wallet-client/methods/method-runner.ts

```ts
/**
 * Tiny helper that every method file uses: run a `RequestSpec`
 * through the path resolver, then run the parser. Centralizes the
 * compose `builder → tryPaths → throwIfError → parser`.
 *
 * Methods only have to declare the builder + parser; everything else
 * stays in this 25-LOC helper.
 */

import { tryPaths } from '../wallet-path-resolver';
import { throwIfError } from '../wallet-error-handler';
import type { HttpTransport, HttpTransportContext } from '../wallet-http-transport';
import type { RequestSpec } from '../types';

export async function runMethod<T>(
  transport: HttpTransport,
  ctx: HttpTransportContext,
  spec: RequestSpec,
  parser: (raw: unknown) => T,
  operation: string,
): Promise<T> {
  const raw = await tryPaths(transport, ctx, spec.method, spec.paths, spec.body);
  throwIfError(raw, operation);
  return parser(raw);
}

```
