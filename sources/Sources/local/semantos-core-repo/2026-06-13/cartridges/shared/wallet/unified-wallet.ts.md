---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/wallet/unified-wallet.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.433944+00:00
---

# cartridges/shared/wallet/unified-wallet.ts

```ts
/**
 * unified-wallet.ts — the canonical BRC-100 wallet contract for Semantos.
 *
 * Per Q9 (canonicalization-decisions.md, 2026-05-28), the wallet interface
 * IS `WalletInterface` from `@bsv/sdk` 2.x — the BSV ecosystem standard
 * defined in BRC-100 (https://bsv.brc.dev/wallet/0100). We do not define
 * our own surface; we re-export the canon and add a factory registry so
 * consumers can resolve implementations by id (e.g. 'headless',
 * 'metanet-desktop', 'plexus-recovery') without coupling to constructors.
 *
 * This supersedes the bespoke UnifiedWallet interface from C6a tick 1
 * (commit 975c760) — see Q9 for rationale.
 */

import {
  ProtoWallet,
  KeyDeriver,
  type WalletInterface,
  type GetPublicKeyArgs,
  type GetPublicKeyResult,
  type CreateSignatureArgs,
  type CreateSignatureResult,
  type VerifySignatureArgs,
  type VerifySignatureResult,
  type CreateActionArgs,
  type CreateActionResult,
  type SignActionArgs,
  type SignActionResult,
  type ListOutputsArgs,
  type ListOutputsResult,
} from '@bsv/sdk';

// Re-export the most-used BRC-100 surface so consumers can import from
// one place rather than reaching into @bsv/sdk repeatedly. Full surface
// remains available via `import { ... } from '@bsv/sdk'`.
export {
  ProtoWallet,
  KeyDeriver,
};
export type {
  WalletInterface,
  GetPublicKeyArgs,
  GetPublicKeyResult,
  CreateSignatureArgs,
  CreateSignatureResult,
  VerifySignatureArgs,
  VerifySignatureResult,
  CreateActionArgs,
  CreateActionResult,
  SignActionArgs,
  SignActionResult,
  ListOutputsArgs,
  ListOutputsResult,
};

// ── Factory registry ──────────────────────────────────────────────────────

/**
 * A factory that constructs a BRC-100-conformant `WalletInterface`.
 * Each implementation (headless adapter, Metanet Desktop client, future
 * plexus-recovery) registers a factory; consumers resolve by id.
 *
 * `WalletInterface` is the @bsv/sdk type — full BRC-100 RPC surface.
 * Adapters that only implement a subset (e.g. crypto-only ProtoWallet
 * wrapper) MAY throw `WERR_NOT_IMPLEMENTED` for transaction methods
 * while still satisfying the crypto subset.
 */
export interface WalletFactory {
  readonly id: string;
  readonly displayName: string;
  /** True if this factory's wallet can construct + broadcast txs (createAction/signAction). */
  readonly canTransact: boolean;
  build(config: Record<string, unknown>): Promise<WalletInterface>;
}

const _factories = new Map<string, WalletFactory>();

export function registerWalletFactory(factory: WalletFactory): void {
  if (_factories.has(factory.id)) {
    throw new Error(`WalletFactory '${factory.id}' already registered`);
  }
  _factories.set(factory.id, factory);
}

export function listWalletFactories(): readonly WalletFactory[] {
  return Array.from(_factories.values());
}

export function getWalletFactory(id: string): WalletFactory | undefined {
  return _factories.get(id);
}

/**
 * Test-only: clear the registry. Call between conformance test cases
 * to avoid cross-test pollution.
 */
export function _resetWalletRegistryForTests(): void {
  _factories.clear();
}

```
