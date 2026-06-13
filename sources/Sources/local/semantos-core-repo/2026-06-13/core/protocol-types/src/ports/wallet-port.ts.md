---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/ports/wallet-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.902880+00:00
---

# core/protocol-types/src/ports/wallet-port.ts

```ts
/**
 * Wallet port — the BRC-100 wallet client surface that
 * payment-channel callers use. Two role-scoped variants enforce the
 * CashLanes role-isolation rule.
 *
 * The default-bindings layer (in `apps/poker-agent`) wires concrete
 * implementations at boot; tests bind in-memory doubles.
 */

import { port, type Port } from '@semantos/state';

import type {
  CreateActionRequest,
  CreateActionResult,
  InternalizeActionRequest,
  WalletOutputEntry,
} from '../wallet-client/types';

export interface WalletPortClient {
  isAuthenticated(): Promise<boolean>;
  createAction(req: CreateActionRequest): Promise<CreateActionResult>;
  getPublicKey(args?: {
    identityKey?: boolean;
    protocolID?: [number, string];
    keyID?: string;
    counterparty?: string;
  }): Promise<string>;
  listOutputs(
    basket: string,
    tags?: string[],
    include?: 'locking scripts',
  ): Promise<WalletOutputEntry[]>;
  signAction(args: {
    reference: string;
    spends: Record<number, { unlockingScript: string | number[] }>;
  }): Promise<CreateActionResult>;
  internalizeAction(req: InternalizeActionRequest): Promise<{ accepted: boolean }>;
}

export type WalletRole = 'provider' | 'consumer';

/** Role-agnostic wallet port (for callers that do not need isolation). */
export const walletPort: Port<WalletPortClient> = port<WalletPortClient>('wallet');

const roleScopedPorts = new Map<WalletRole, Port<WalletPortClient>>();

/**
 * Resolve (or create) the wallet port scoped to a specific role.
 *
 * Two distinct ports — `'wallet:provider'` and `'wallet:consumer'` —
 * back the CashLanes role-isolation rule: the same process must not
 * funnel both roles through one wallet client.
 */
export function createWalletPort(role: WalletRole): Port<WalletPortClient> {
  const existing = roleScopedPorts.get(role);
  if (existing) return existing;
  const fresh = port<WalletPortClient>(`wallet:${role}`);
  roleScopedPorts.set(role, fresh);
  return fresh;
}

```
