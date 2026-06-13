---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/demo/swarm-channel-settle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.081671+00:00
---

# runtime/session-protocol/src/swarm/demo/swarm-channel-settle.ts

```ts
/**
 * Metered-flow paid download with a REAL on-chain settlement.
 *
 *   ARC_URL=https://arc.gorillapool.io SWARM_ALLOW_UNCONFIRMED=1 \
 *     BRIDGE_WALLET_KEY=<64-hex> bun run .../swarm-channel-settle.ts
 *
 * The leecher downloads an N-cell file, paying with N OFF-CHAIN signed
 * commitments (one per cell) — zero per-cell txs. At the end it settles the
 * channel with ONE real BSV transaction paying the seeder the final cumulative.
 * So N cells = N off-chain commitments + 1 on-chain settle (vs N txs).
 */

import { PrivateKey } from '@bsv/sdk';
import { publishFile, fromHex, toHex, bytesEqual, type MfpFlowConfig } from '@semantos/protocol-types';
import { initHeadlessWallet, sendPushdrop } from '../../../../../cartridges/shared/anchor/headless-wallet';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmSession } from '../swarm-session';
import { MeteredFlowPayer, MeteredFlowVerifier, MeteredFlowServePolicy, meteredFlowPayPolicy, protoWalletPort } from '../metered-flow';

const COMMODITY = 'swarm.cell';
const RATE = Number(process.env.SWARM_PRICE_SATS ?? 1);
const FEE_SATS = 1200;
const CELLS = Number(process.env.SWARM_CELLS ?? 5);

async function main() {
  console.log('━━━ metered-flow download + ONE on-chain settlement ━━━\n');

  const wallet = await initHeadlessWallet();
  if (wallet.utxos.length === 0 && process.env.SWARM_ALLOW_UNCONFIRMED) {
    const r = await fetch(`https://api.whatsonchain.com/v1/bsv/main/address/${wallet.address}/unspent`);
    const unspent = (await r.json()) as Array<{ tx_pos: number; tx_hash: string; value: number }>;
    wallet.utxos = unspent.map(u => ({ txid: u.tx_hash, vout: u.tx_pos, value: BigInt(u.value) }));
  }
  const balance = wallet.utxos.reduce((s, u) => s + u.value, 0n);
  console.log(`leecher wallet : ${wallet.address}  (${balance} sats)`);

  const leecherKey = PrivateKey.fromHex(toHex(wallet.privKey)); // signs commitments
  const seederKey = PrivateKey.fromRandom();
  const seederPubHex = seederKey.toPublicKey().toString();

  const cfg: MfpFlowConfig = {
    commodityId: COMMODITY, ratePerUnitSats: RATE, counterparty: seederPubHex,
    flowId: toHex(crypto.getRandomValues(new Uint8Array(8))),
    fundMode: 'metered', vaultCapSats: 1_000_000n, channelChunkSats: 1_000_000n, refillThresholdSats: 0n,
  };
  const payer = new MeteredFlowPayer(cfg, protoWalletPort(leecherKey));
  await payer.open();
  const servePolicy = new MeteredFlowServePolicy(new MeteredFlowVerifier(seederKey, COMMODITY, RATE), leecherKey.toPublicKey().toString(), RATE);

  const file = new Uint8Array(CELLS * 1016 - 200);
  for (let i = 0; i < file.length; i++) file[i] = (i * 11 + 3) & 0xff;
  const published = publishFile(file, 'channel/file');
  console.log(`file           : ${file.length} bytes → ${published.manifest.totalCells} cells`);
  console.log(`seeder payee   : ${seederPubHex}\n`);

  const brain = new FakeBrainClient();
  const bus = new SwarmBus();
  const seeder = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'seed'), brain, servePolicy });
  const leecher = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'leech'), brain, payPolicy: meteredFlowPayPolicy(payer) });

  console.log('downloading (one signed commitment per cell, OFF-CHAIN)…');
  await seeder.seed(published);
  const got = await leecher.download(published.infohash);
  await seeder.stop(); await leecher.stop();

  const fin = servePolicy.finalCommitment();
  const owed = fin!.cumulativeSats;
  console.log(`download       : ${got.length} bytes, match=${bytesEqual(got, file)}`);
  console.log(`channel        : ${servePolicy.servedCount()} cells served via ${servePolicy.servedCount()} off-chain commitments (0 per-cell txs)`);
  console.log(`owed (final)   : ${owed} sats → settling on-chain in ONE tx\n`);

  if (balance < owed + BigInt(FEE_SATS)) {
    console.log(`⚠ wallet has ${balance} sats, need ${owed + BigInt(FEE_SATS)} to settle — fund ${wallet.address}`);
    process.exit(0);
  }
  const txid = await sendPushdrop(wallet, new TextEncoder().encode(`mfp-settle ${toHex(published.infohash).slice(0, 16)}`), fromHex(seederPubHex), owed);
  console.log(`SETTLED        : ${owed} sats → seeder in 1 tx`);
  console.log(`               : https://whatsonchain.com/tx/${txid}`);
  console.log(`\n━━━ ${servePolicy.servedCount()} cells: ${servePolicy.servedCount()} off-chain commitments + 1 on-chain settle ✓ ━━━`);
  process.exit(0);
}

void main();

```
