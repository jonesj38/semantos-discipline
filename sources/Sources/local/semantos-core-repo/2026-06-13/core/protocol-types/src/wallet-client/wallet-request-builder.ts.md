---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/wallet-request-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.873104+00:00
---

# core/protocol-types/src/wallet-client/wallet-request-builder.ts

```ts
/**
 * Pure per-method BRC-100 request body builders.
 *
 * Each function takes the `originator` plus the method-specific args
 * and returns the JSON body the wallet expects. No I/O, no transport,
 * no parsing — separating these lets tests assert request shape
 * without spinning up a transport stub.
 */

import type {
  CreateActionRequest,
  InternalizeActionRequest,
  RequestSpec,
} from './types';

export function buildIsAuthenticated(): RequestSpec {
  return { method: 'GET', paths: ['/v1/isAuthenticated', '/isAuthenticated'] };
}

export function buildGetHeight(): RequestSpec {
  return { method: 'GET', paths: ['/v1/getHeight', '/getHeight'] };
}

export function buildGetNetwork(): RequestSpec {
  return { method: 'GET', paths: ['/v1/getNetwork', '/getNetwork'] };
}

export function buildGetPublicKey(
  originator: string,
  args?: {
    identityKey?: boolean;
    protocolID?: [number, string];
    keyID?: string;
    counterparty?: string;
  },
): RequestSpec {
  return {
    method: 'POST',
    paths: ['/v1/getPublicKey', '/getPublicKey'],
    body: { originator, ...(args ?? { identityKey: true }) },
  };
}

export function buildListOutputs(
  originator: string,
  basket: string,
  tags?: string[],
  include?: 'locking scripts',
): RequestSpec {
  const body: Record<string, unknown> = { originator, basket };
  if (tags && tags.length > 0) body.tags = tags;
  if (include) body.include = include;
  return { method: 'POST', paths: ['/v1/listOutputs', '/listOutputs'], body };
}

export function buildCreateAction(
  originator: string,
  req: CreateActionRequest,
): RequestSpec {
  const body: Record<string, unknown> = {
    originator,
    description: req.description,
    labels: req.labels,
    outputs: req.outputs.map((o) => ({
      lockingScript: o.lockingScript,
      satoshis: o.satoshis,
      outputDescription: o.outputDescription,
      basket: o.basket,
      tags: o.tags,
    })),
  };
  if (req.inputs && req.inputs.length > 0) {
    body.inputs = req.inputs.map((inp) => ({
      outpoint: inp.outpoint,
      inputDescription: inp.inputDescription,
      unlockingScriptLength: inp.unlockingScriptLength,
      unlockingScript: inp.unlockingScript,
      sequenceNumber: inp.sequenceNumber,
      sourceTransaction: inp.sourceTransaction,
      sourceSatoshis: inp.sourceSatoshis,
      sourceLockingScript: inp.sourceLockingScript,
    }));
  }
  if (req.inputBEEF) body.inputBEEF = req.inputBEEF;
  return { method: 'POST', paths: ['/v1/createAction', '/createAction'], body };
}

export function buildSignAction(
  originator: string,
  args: {
    reference: string;
    spends: Record<number, { unlockingScript: string | number[] }>;
  },
): RequestSpec {
  return {
    method: 'POST',
    paths: ['/v1/signAction', '/signAction'],
    body: { originator, ...args },
  };
}

export function buildCreateSignature(
  originator: string,
  args: {
    protocolID: [number, string];
    keyID: string;
    counterparty: string;
    data: number[];
    hashToDirectlySign?: number[];
  },
): RequestSpec {
  return {
    method: 'POST',
    paths: ['/v1/createSignature', '/createSignature'],
    body: { originator, ...args },
  };
}

export function buildInternalizeAction(
  originator: string,
  req: InternalizeActionRequest,
): RequestSpec {
  return {
    method: 'POST',
    paths: ['/v1/internalizeAction', '/internalizeAction'],
    body: {
      originator,
      tx: req.tx,
      outputs: req.outputs,
      description: req.description,
      labels: req.labels,
    },
  };
}

```
