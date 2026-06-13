---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/wallet-client/wallet-client-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.872542+00:00
---

# core/protocol-types/src/wallet-client/wallet-client-facade.ts

```ts
/**
 * WalletClient facade — orchestrates the BRC-100 method handlers.
 *
 * Each public method is a thin wrapper that resolves the active
 * transport (port-bound or default) and delegates to the matching
 * `methods/*.ts` handler. Behaviour matches the pre-split class
 * 1:1 — same signatures, same return shapes, same error semantics.
 */

import { createAction } from './methods/create-action';
import { createSignature, type CreateSignatureArgs } from './methods/create-signature';
import { getHeight } from './methods/get-height';
import { getNetwork } from './methods/get-network';
import { getPublicKey, type GetPublicKeyArgs } from './methods/get-public-key';
import { internalizeAction } from './methods/internalize-action';
import { isAuthenticated } from './methods/is-authenticated';
import { listOutputs } from './methods/list-outputs';
import { signAction, type SignActionArgs } from './methods/sign-action';
import type {
  CreateActionRequest,
  CreateActionResult,
  InternalizeActionRequest,
  WalletClientConfig,
  WalletOutputEntry,
} from './types';
import {
  getTransport,
  type HttpTransport,
  type HttpTransportContext,
} from './wallet-http-transport';

export class WalletClient {
  private readonly ctx: HttpTransportContext;
  private readonly transportOverride?: HttpTransport;

  constructor(config: WalletClientConfig, transport?: HttpTransport) {
    this.ctx = {
      baseUrl: config.baseUrl.replace(/\/$/, ''),
      timeoutMs: config.timeout ?? 120_000,
      originator: config.originator ?? 'semantos',
      origin: config.origin ?? 'http://localhost',
    };
    if (transport) this.transportOverride = transport;
  }

  private get transport(): HttpTransport {
    return this.transportOverride ?? getTransport();
  }

  isAuthenticated(): Promise<boolean> {
    return isAuthenticated(this.transport, this.ctx);
  }

  createAction(req: CreateActionRequest): Promise<CreateActionResult> {
    return createAction(this.transport, this.ctx, req);
  }

  getPublicKey(args?: GetPublicKeyArgs): Promise<string> {
    return getPublicKey(this.transport, this.ctx, args);
  }

  listOutputs(
    basket: string,
    tags?: string[],
    include?: 'locking scripts',
  ): Promise<WalletOutputEntry[]> {
    return listOutputs(this.transport, this.ctx, basket, tags, include);
  }

  signAction(args: SignActionArgs): Promise<CreateActionResult> {
    return signAction(this.transport, this.ctx, args);
  }

  createSignature(args: CreateSignatureArgs): Promise<{ signature: number[] }> {
    return createSignature(this.transport, this.ctx, args);
  }

  internalizeAction(req: InternalizeActionRequest): Promise<{ accepted: boolean }> {
    return internalizeAction(this.transport, this.ctx, req);
  }

  getHeight(): Promise<number> {
    return getHeight(this.transport, this.ctx);
  }

  getNetwork(): Promise<'mainnet' | 'testnet'> {
    return getNetwork(this.transport, this.ctx);
  }
}

```
