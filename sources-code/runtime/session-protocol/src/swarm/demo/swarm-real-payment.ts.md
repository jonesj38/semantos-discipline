---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/demo/swarm-real-payment.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.081971+00:00
---

# runtime/session-protocol/src/swarm/demo/swarm-real-payment.ts

```ts
/**
 * Real paid swarm transfer — ONE cell, ONE real on-chain BSV payment.
 *
 *   ARC_URL=https://arc.gorillapool.io SWARM_ALLOW_UNCONFIRMED=1 \
 *     BRIDGE_WALLET_KEY=<64-hex> bun run .../swarm-real-payment.ts
 *
 * (arc.taal.com now requires an API key → use GorillaPool's public ARC.
 *  SWARM_ALLOW_UNCONFIRMED lets it spend a still-in-mempool funding UTXO.)
 * First real run: txid cb6be8533dde85c07afabc3426457402932a586e1151948b90e8777e76ef3dff
 *
 * The leecher's funded wallet pays the seeder (a fresh key) ON-CHAIN for the
 * single cell; the seeder verifies the payment on WhatsOnChain before serving.
 * This is the real version of M4 — `WalletEconomicPort` (verifier:'spv') in
 * place of the StubEconomy. It MOVES REAL MONEY on mainnet (price + ~1200 sat
 * fee). Kept to one cell = one payment to minimise spend.
 *
 * If the wallet is unfunded it prints the address to fund and exits without
 * spending — nothing is broadcast until there are sats.
 */

import { PrivateKey } from '@bsv/sdk';
import { publishFile, fromHex, toHex, bytesEqual, sha256 } from '@semantos/protocol-types';
import { initHeadlessWallet, sendPushdrop } from '../../../../../cartridges/shared/anchor/headless-wallet';
import { WalletEconomicPort, whatsOnChainLookup, type PaymentWallet } from '../wallet-economic-port';
import { PaidSeeder, makePayPolicy } from '../paid-seeder';
import { SwarmSession } from '../swarm-session';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';

const PRICE_SATS = Number(process.env.SWARM_PRICE_SATS ?? 1); // payment output to the seeder
const FEE_SATS = 1200; // headless-wallet flat fee per tx

async function main() {
  console.log('━━━ real paid swarm transfer (1 cell, 1 on-chain payment) ━━━\n');

  // Leecher: the funded wallet that pays.
  const leecherWallet = await initHeadlessWallet();
  // The wallet uses confirmed-only UTXOs; allow spending a still-in-mempool
  // funding UTXO (BSV permits chained/unconfirmed spends) when asked.
  if (leecherWallet.utxos.length === 0 && process.env.SWARM_ALLOW_UNCONFIRMED) {
    const r = await fetch(`https://api.whatsonchain.com/v1/bsv/main/address/${leecherWallet.address}/unspent`);
    const unspent = (await r.json()) as Array<{ height: number; tx_pos: number; tx_hash: string; value: number }>;
    leecherWallet.utxos = unspent.map(u => ({ txid: u.tx_hash, vout: u.tx_pos, value: BigInt(u.value) }));
    console.log(`(injected ${leecherWallet.utxos.length} unconfirmed utxo(s) from mempool)`);
  }
  const balance = leecherWallet.utxos.reduce((s, u) => s + u.value, 0n);
  console.log(`leecher wallet : ${leecherWallet.address}  (${balance} sats, ${leecherWallet.utxos.length} utxos)`);

  if (leecherWallet.utxos.length === 0 || balance < BigInt(PRICE_SATS + FEE_SATS)) {
    console.log(`\n⚠ NOT ENOUGH FUNDS to make the real payment.`);
    console.log(`   Fund this address with ≥ ${PRICE_SATS + FEE_SATS} sats, then re-run:`);
    console.log(`     ${leecherWallet.address}`);
    console.log(`   (everything else is wired — this is the only blocker.)`);
    process.exit(0);
  }

  // Seeder: a fresh receiving key. Pays nothing; only receives + verifies.
  const seederSk = PrivateKey.fromRandom();
  const seederPubHex = seederSk.toPublicKey().toString();
  console.log(`seeder payee   : ${seederPubHex}`);
  console.log(`price          : ${PRICE_SATS} sat/cell (+ ~${FEE_SATS} sat fee)\n`);

  const leecherPay: PaymentWallet = {
    myPubkeyHex: toHex(leecherWallet.pubKey),
    pay: (recipientPubkeyHex, sats, memo) =>
      sendPushdrop(leecherWallet, new TextEncoder().encode(memo), fromHex(recipientPubkeyHex), BigInt(sats)),
  };
  const seederReceive: PaymentWallet = {
    myPubkeyHex: seederPubHex,
    pay: async () => { throw new Error('seeder does not pay'); },
  };
  const lookup = whatsOnChainLookup('main');

  const leecherPort = new WalletEconomicPort(leecherPay, lookup);
  const seederPort = new WalletEconomicPort(seederReceive, lookup);

  const file = new Uint8Array(400);
  for (let i = 0; i < file.length; i++) file[i] = (i * 7 + 1) & 0xff;
  const published = publishFile(file, 'paid/cell');
  console.log(`file           : ${file.length} bytes → ${published.manifest.totalCells} cell(s)`);
  console.log(`infohash       : ${toHex(published.infohash)}\n`);

  const brain = new FakeBrainClient();
  const bus = new SwarmBus();
  const seeder = new SwarmSession({
    transport: inMemorySwarmTransport(bus, 'seed'),
    brain,
    servePolicy: new PaidSeeder({ economic: seederPort, pricePerCellSats: PRICE_SATS }),
  });
  const leecher = new SwarmSession({
    transport: inMemorySwarmTransport(bus, 'leech'),
    brain,
    payPolicy: makePayPolicy({ economic: leecherPort, payerCertId: 'leecher', pricePerCellSats: PRICE_SATS, payeeId: seederPubHex }),
  });

  console.log('paying on-chain + downloading…');
  await seeder.seed(published);
  const got = await Promise.race([
    leecher.download(published.infohash),
    new Promise<never>((_, r) => setTimeout(() => r(new Error('timeout (payment/verify took too long)')), 30_000)),
  ]);

  const receipts = await seeder.flushReceipts(); // settles the on-chain receipt(s) to the brain
  const journaled = brain.receiptsFor(published.infohash);
  console.log(`\ndownload       : ${got.length} bytes, bytes match=${bytesEqual(got, file)}, hash ok=${bytesEqual(sha256(got), published.manifest.contentHash)}`);
  console.log(`PAID on-chain  : txid(s) = ${journaled.map(r => r.txAnchor).join(', ')}`);
  console.log(`settled        : ${receipts} receipt(s) → https://whatsonchain.com/tx/${journaled[0]?.txAnchor ?? ''}`);

  await seeder.stop();
  await leecher.stop();
  console.log('\n━━━ RESULT: a real on-chain payment gated the cell delivery ✓ ━━━');
  process.exit(0);
}

void main();

```
