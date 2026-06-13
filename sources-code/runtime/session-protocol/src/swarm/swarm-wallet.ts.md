---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/swarm-wallet.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.049638+00:00
---

# runtime/session-protocol/src/swarm/swarm-wallet.ts

```ts
/**
 * Wallet seam — the daemon ships with a bundled headless key OR connects to any
 * BRC-100 wallet (Metanet Desktop, a browser wallet, a WalletClient).
 *
 * Everything routes through one interface: BRC-100's `WalletInterface`
 * (createSignature / createAction). The bundled headless `ProtoWallet`, Metanet
 * Desktop (via `WalletClient` over the :3321 HTTP substrate), and a browser
 * wallet (`window.CWI` substrate) ALL implement it — so the swarm's metered-flow
 * channel is signed identically regardless of which wallet the user runs.
 *
 *   brc100WalletPort(new ProtoWallet(key))   // bundled headless key
 *   brc100WalletPort(new WalletClient())     // Metanet Desktop / browser (auto-detect)
 */

import { ProtoWallet, WalletClient, PrivateKey, type WalletInterface } from '@bsv/sdk';
import type { WalletPort } from '@semantos/protocol-types';

/** Adapt any BRC-100 WalletInterface into an MFP metered-flow WalletPort. */
export function brc100WalletPort(wallet: WalletInterface): WalletPort {
  return {
    async createAction(args) {
      // Channel-funding draw. The real on-chain open/settle is a separate flow
      // (headless wallet / 2-of-2); here the draw is authorised so the channel
      // can advance. Commitment SIGNING below is the live BRC-100 path.
      return { ok: true, txid: 'brc100-channel', committedSats: args.amountSats };
    },
    async createSignature(args) {
      const res = await wallet.createSignature({
        protocolID: args.protocolID,
        keyID: args.keyID,
        counterparty: args.counterparty,
        data: Array.from(args.data),
      });
      return { ok: true, signature: Uint8Array.from(res.signature) };
    },
  };
}

export type WalletSpec =
  | { mode: 'none' }
  /** Bundled headless key (BRIDGE_WALLET_KEY or explicit hex). */
  | { mode: 'headless'; keyHex: string }
  /** Any BRC-100 wallet — Metanet Desktop / browser / injected. Defaults to
   *  auto-detecting WalletClient (Metanet Desktop on :3321 or the browser). */
  | { mode: 'brc100'; wallet?: WalletInterface };

/** Resolve a metered-flow WalletPort from a spec, or undefined for the free swarm. */
export function resolveWalletPort(spec: WalletSpec): WalletPort | undefined {
  switch (spec.mode) {
    case 'none':
      return undefined;
    case 'headless':
      return brc100WalletPort(new ProtoWallet(PrivateKey.fromHex(spec.keyHex)));
    case 'brc100':
      return brc100WalletPort(spec.wallet ?? new WalletClient());
  }
}

/** The identity pubkey a counterparty verifies commitments against. */
export async function walletIdentityPubHex(spec: WalletSpec): Promise<string | undefined> {
  if (spec.mode === 'headless') return PrivateKey.fromHex(spec.keyHex).toPublicKey().toString();
  if (spec.mode === 'brc100') {
    const w = spec.wallet ?? new WalletClient();
    const { publicKey } = await w.getPublicKey({ identityKey: true });
    return publicKey;
  }
  return undefined;
}

```
