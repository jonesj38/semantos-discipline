---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/wallet-economic-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.058649+00:00
---

# runtime/session-protocol/src/swarm/wallet-economic-port.ts

```ts
/**
 * WalletEconomicPort — a REAL EconomicPort backed by a BSV wallet, replacing
 * the StubEconomy. signSpend builds + broadcasts an actual on-chain payment to
 * the seeder; verifyPayment looks the tx up on-chain and confirms an output
 * pays the recipient. `verifier: 'spv'` (not 'stub').
 *
 * Layering: this module does NOT import the wallet cartridge — it depends on an
 * injected `PaymentWallet` (sign+broadcast) and `TxLookup` (read-back). The
 * concrete binding to cartridges/shared/anchor/headless-wallet lives in the
 * demo script, keeping session-protocol cartridge-free.
 *
 * This moves REAL money on mainnet. Construct it only when you intend to spend.
 */

import type { EconomicPort, SignSpendInput, SignedSpend, PaymentVerification } from '@semantos/identity-ports';

export interface PaymentWallet {
  /** This wallet's own receiving pubkey (33-byte compressed, hex) — recipients
   *  verify that a payment's output pays this key. */
  readonly myPubkeyHex: string;
  /** Pay `sats` to `recipientPubkeyHex`, tagging the output with `memo`.
   *  Broadcasts and returns the txid. Throws if unfunded. */
  pay(recipientPubkeyHex: string, sats: number, memo: string): Promise<string>;
}

export interface TxOutputView {
  valueSats: number;
  scriptHex: string;
}
/** Fetch a broadcast tx's outputs by txid, or null if not found yet. */
export type TxLookup = (txid: string) => Promise<{ outputs: TxOutputView[] } | null>;

export class WalletEconomicPort implements EconomicPort {
  constructor(
    private readonly wallet: PaymentWallet,
    private readonly lookup: TxLookup,
  ) {}

  /** Pay the recipient (`targetId` = their pubkey hex) on-chain. */
  async signSpend(input: SignSpendInput): Promise<SignedSpend> {
    if (input.amount <= 0) throw new Error(`signSpend: amount must be positive, got ${input.amount}`);
    const txid = await this.wallet.pay(input.targetId, input.amount, input.memo ?? '');
    return { txAnchor: txid, amount: input.amount, currency: input.currency, verifier: 'spv' };
  }

  /** Confirm the tx exists on-chain and pays this wallet ≥ `amount`. */
  async verifyPayment(input: { txAnchor: string; amount: number; currency: string }): Promise<PaymentVerification> {
    let tx = await this.lookup(input.txAnchor);
    // Brief propagation grace — a just-broadcast tx may take a moment to index.
    for (let i = 0; !tx && i < 3; i++) {
      await new Promise(r => setTimeout(r, 400));
      tx = await this.lookup(input.txAnchor);
    }
    if (!tx) return { valid: false, reason: 'tx_not_found', verifier: 'spv' };
    const paysMe = tx.outputs.some(o => o.valueSats >= input.amount && o.scriptHex.includes(this.wallet.myPubkeyHex));
    return paysMe
      ? { valid: true, verifier: 'spv' }
      : { valid: false, reason: 'no_output_pays_recipient', verifier: 'spv' };
  }
}

/** A {@link TxLookup} backed by WhatsOnChain (mainnet). */
export function whatsOnChainLookup(network: 'main' | 'test' = 'main'): TxLookup {
  return async (txid: string) => {
    try {
      const r = await fetch(`https://api.whatsonchain.com/v1/bsv/${network}/tx/hash/${txid}`);
      if (!r.ok) return null;
      const j = (await r.json()) as { vout?: Array<{ value: number; scriptPubKey?: { hex?: string } }> };
      if (!j.vout) return null;
      return {
        outputs: j.vout.map(o => ({ valueSats: Math.round(o.value * 1e8), scriptHex: o.scriptPubKey?.hex ?? '' })),
      };
    } catch {
      return null;
    }
  };
}

```
