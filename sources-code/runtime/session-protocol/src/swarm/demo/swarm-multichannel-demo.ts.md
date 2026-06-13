---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/demo/swarm-multichannel-demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.084124+00:00
---

# runtime/session-protocol/src/swarm/demo/swarm-multichannel-demo.ts

```ts
/**
 * Multiple payment channels managed at once — one seeder, N leechers, each its
 * own metered-flow channel, all downloading concurrently. Prints the seeder's
 * per-channel state (the funded channels it is managing simultaneously).
 *
 *   bun run runtime/session-protocol/src/swarm/demo/swarm-multichannel-demo.ts [N]
 *
 * In-process (in-memory transport) — the metered-flow policies live at the
 * SwarmSession/wire layer and are transport-agnostic, so the identical setup
 * runs across the Pi mesh (seeder on one node, leechers on the others).
 */

import { PrivateKey } from '@bsv/sdk';
import { publishFile, bytesEqual, type MfpFlowConfig } from '@semantos/protocol-types';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmSession } from '../swarm-session';
import {
  MeteredFlowPayer, MeteredFlowVerifier, MultiChannelServePolicy, meteredFlowPayPolicy, protoWalletPort,
  type ChannelRegistration,
} from '../metered-flow';

const COMMODITY = 'swarm.cell';
const RATE = 1;

async function main() {
  const N = Number(process.argv[2] ?? 4);
  console.log(`━━━ one seeder managing ${N} payment channels at once ━━━\n`);

  const seederKey = PrivateKey.fromRandom();
  const verifier = new MeteredFlowVerifier(seederKey, COMMODITY, RATE);

  // N leechers, each its own key + flowId → its own channel.
  const leechers = Array.from({ length: N }, (_, i) => {
    const key = PrivateKey.fromRandom();
    const flowId = Buffer.from(crypto.getRandomValues(new Uint8Array(8))).toString('hex');
    const cfg: MfpFlowConfig = {
      commodityId: COMMODITY, ratePerUnitSats: RATE, counterparty: seederKey.toPublicKey().toString(),
      flowId, fundMode: 'metered', vaultCapSats: 1_000_000n, channelChunkSats: 1_000_000n, refillThresholdSats: 0n,
    };
    return { i, payer: new MeteredFlowPayer(cfg, protoWalletPort(key)), flowId, pub: key.toPublicKey().toString() };
  });
  const registry: ChannelRegistration[] = leechers.map(l => ({ flowId: l.flowId, payerIdentityPubHex: l.pub }));
  const multi = new MultiChannelServePolicy(verifier, RATE, registry);

  // Each leecher opens (funds) its channel.
  for (const l of leechers) await l.payer.open();
  console.log(`${N} channels funded/opened (one per leecher).`);

  // One file, served by one seeder session; each leecher pays via its OWN channel.
  const brain = new FakeBrainClient();
  const bus = new SwarmBus();
  const seeder = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'seed'), brain, servePolicy: multi });

  const file = Uint8Array.from({ length: 12 * 1016 }, (_, k) => (k * 7 + 1) & 0xff);
  const published = publishFile(file, 'mc/file');
  await seeder.seed(published);

  // All leechers download concurrently — N channels active at once.
  console.log('all leechers downloading the file concurrently, each via its own channel…\n');
  const got = await Promise.all(leechers.map((l, i) => {
    const s = new SwarmSession({ transport: inMemorySwarmTransport(bus, `leech-${i}`), brain, payPolicy: meteredFlowPayPolicy(l.payer) });
    return s.download(published.infohash).then(async f => { await s.stop(); return f; });
  }));

  const allOk = got.every(f => bytesEqual(f, file));

  console.log('seeder is managing these channels simultaneously:');
  for (const c of multi.channelSummary()) {
    console.log(`  flow ${c.flowId}  cells=${c.cellsServed}  owed=${c.owedSats} sat  settle=1 tx`);
  }
  const totalCells = multi.channelSummary().reduce((s, c) => s + c.cellsServed, 0);
  const totalCommit = multi.channelSummary().reduce((s, c) => s + Number(c.owedSats), 0);
  console.log(`\n${N} channels · ${totalCells} cells served · ${totalCommit} off-chain commitments · ${N} settlements (1 per channel)`);
  console.log(allOk ? '\n━━━ RESULT: OK ✓ ━━━' : '\n━━━ RESULT: data mismatch ✗ ━━━');

  await seeder.stop();
  process.exit(allOk ? 0 : 1);
}

void main();

```
