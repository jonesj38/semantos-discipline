---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/wallet-economic-port.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.076133+00:00
---

# runtime/session-protocol/src/swarm/__tests__/wallet-economic-port.test.ts

```ts
/**
 * WalletEconomicPort logic — against a mock wallet + mock tx lookup (no real
 * money). Proves signSpend broadcasts a payment to the target and returns a
 * 'spv' anchor, and verifyPayment confirms an on-chain output pays the
 * recipient. The real money-moving binding (headless-wallet) is exercised by
 * demo/swarm-real-payment.ts.
 */
import { describe, expect, test } from 'bun:test';
import { WalletEconomicPort, type PaymentWallet, type TxLookup } from '../wallet-economic-port';

const SEEDER_PUB = '02' + 'ab'.repeat(32); // 33-byte compressed pubkey hex
const PAYER_PUB = '03' + 'cd'.repeat(32);

function payerWallet(): { wallet: PaymentWallet; calls: Array<{ to: string; sats: number; memo: string }> } {
  const calls: Array<{ to: string; sats: number; memo: string }> = [];
  return {
    calls,
    wallet: {
      myPubkeyHex: PAYER_PUB,
      async pay(to, sats, memo) {
        calls.push({ to, sats, memo });
        return 'ab'.repeat(32); // fake 64-hex txid
      },
    },
  };
}

describe('WalletEconomicPort', () => {
  test('signSpend pays the target pubkey on-chain and returns an spv anchor', async () => {
    const { wallet, calls } = payerWallet();
    const port = new WalletEconomicPort(wallet, async () => null);
    const spend = await port.signSpend({ payerCertId: 'p', targetId: SEEDER_PUB, amount: 5, currency: 'sat', memo: 'ih:0' });
    expect(spend.verifier).toBe('spv');
    expect(spend.txAnchor).toBe('ab'.repeat(32));
    expect(spend.amount).toBe(5);
    expect(calls).toEqual([{ to: SEEDER_PUB, sats: 5, memo: 'ih:0' }]);
  });

  test('verifyPayment accepts a tx whose output pays the recipient ≥ amount', async () => {
    const lookup: TxLookup = async () => ({ outputs: [{ valueSats: 5, scriptHex: `21${SEEDER_PUB}ac` }] });
    const seeder = new WalletEconomicPort({ myPubkeyHex: SEEDER_PUB, pay: async () => '' }, lookup);
    expect((await seeder.verifyPayment({ txAnchor: 'ab'.repeat(32), amount: 5, currency: 'sat' })).valid).toBe(true);
  });

  test('verifyPayment rejects underpayment + outputs that pay someone else', async () => {
    const seeder = (lookup: TxLookup) => new WalletEconomicPort({ myPubkeyHex: SEEDER_PUB, pay: async () => '' }, lookup);
    // underpaid (output < amount)
    expect((await seeder(async () => ({ outputs: [{ valueSats: 1, scriptHex: SEEDER_PUB }] })).verifyPayment({ txAnchor: 'x', amount: 5, currency: 'sat' })).valid).toBe(false);
    // pays a different key
    expect((await seeder(async () => ({ outputs: [{ valueSats: 9, scriptHex: 'deadbeef' }] })).verifyPayment({ txAnchor: 'x', amount: 5, currency: 'sat' })).valid).toBe(false);
  });

  test('verifyPayment rejects a tx that was never broadcast (not found)', async () => {
    const seeder = new WalletEconomicPort({ myPubkeyHex: SEEDER_PUB, pay: async () => '' }, async () => null);
    const v = await seeder.verifyPayment({ txAnchor: 'ab'.repeat(32), amount: 5, currency: 'sat' });
    expect(v.valid).toBe(false);
    expect(v.reason).toBe('tx_not_found');
  });
});

```
