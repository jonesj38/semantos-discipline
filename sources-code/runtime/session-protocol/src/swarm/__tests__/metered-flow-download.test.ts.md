---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/metered-flow-download.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.078486+00:00
---

# runtime/session-protocol/src/swarm/__tests__/metered-flow-download.test.ts

```ts
/**
 * Full swarm download settled over a metered-flow channel — commitments on the
 * live SwarmSession wire. The leecher attaches a signed commitment per cell;
 * the seeder verifies it off-chain and serves. N cells → N off-chain
 * commitments + ONE settlement (finalCommitment), not N txs.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { publishFile, bytesEqual, type MfpFlowConfig } from '@semantos/protocol-types';
import { SwarmBus, inMemorySwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmSession } from '../swarm-session';
import {
  MeteredFlowPayer,
  MeteredFlowVerifier,
  MeteredFlowServePolicy,
  MultiChannelServePolicy,
  meteredFlowPayPolicy,
  protoWalletPort,
  PrivateKey,
} from '../metered-flow';

const COMMODITY = 'swarm.cell';
const RATE = 1;

function channel() {
  const payerKey = PrivateKey.fromRandom();
  const seederKey = PrivateKey.fromRandom();
  const cfg: MfpFlowConfig = {
    commodityId: COMMODITY,
    ratePerUnitSats: RATE,
    counterparty: seederKey.toPublicKey().toString(),
    flowId: '00112233445566778899aabbccddeeff',
    fundMode: 'metered',
    vaultCapSats: 1_000_000n,
    channelChunkSats: 1_000_000n, // fund the whole file in one on-chain draw
    refillThresholdSats: 0n,
  };
  return {
    payer: new MeteredFlowPayer(cfg, protoWalletPort(payerKey)),
    servePolicy: new MeteredFlowServePolicy(new MeteredFlowVerifier(seederKey, COMMODITY, RATE), payerKey.toPublicKey().toString(), RATE),
  };
}

const cleanups: Array<() => Promise<void>> = [];
afterEach(async () => { for (const c of cleanups.splice(0)) await c(); });

describe('metered-flow download', () => {
  test('downloads over the channel — per-cell commitments, one settlement', async () => {
    const { payer, servePolicy } = channel();
    await payer.open(); // ONE on-chain channel funding

    const file = Uint8Array.from({ length: 20 * 1016 + 7 }, (_, i) => (i * 3 + 1) & 0xff);
    const published = publishFile(file, 'flow/file');
    const brain = new FakeBrainClient();
    const bus = new SwarmBus();
    const seeder = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'seed'), brain, servePolicy });
    const leecher = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'leech'), brain, payPolicy: meteredFlowPayPolicy(payer) });
    cleanups.push(() => seeder.stop(), () => leecher.stop());

    await seeder.seed(published);
    const got = await Promise.race([
      leecher.download(published.infohash),
      new Promise<never>((_, r) => setTimeout(() => r(new Error('timeout')), 5000)),
    ]);

    expect(bytesEqual(got, file)).toBe(true);
    expect(servePolicy.servedCount()).toBe(published.manifest.totalCells);
    // ONE settlement covers the whole file: the final commitment authorises N sats.
    const fin = servePolicy.finalCommitment();
    expect(fin).not.toBeNull();
    expect(fin!.cumulativeSats).toBe(BigInt(published.manifest.totalCells * RATE));
  });

  test('a leecher with no commitment is refused (channel-gated)', async () => {
    const { servePolicy } = channel();
    const file = Uint8Array.from({ length: 4 * 1016 }, (_, i) => i & 0xff);
    const published = publishFile(file, 'flow/refuse');
    const brain = new FakeBrainClient();
    const bus = new SwarmBus();
    const seeder = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'seed'), brain, servePolicy });
    const leecher = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'leech'), brain }); // no payPolicy
    cleanups.push(() => seeder.stop(), () => leecher.stop());

    await seeder.seed(published);
    await expect(Promise.race([
      leecher.download(published.infohash),
      new Promise<never>((_, r) => setTimeout(() => r(new Error('timeout')), 600)),
    ])).rejects.toThrow('timeout');
    expect(servePolicy.servedCount()).toBe(0);
  });

  test('one seeder manages TWO funded channels at once (two leechers, two flows)', async () => {
    const seederKey = PrivateKey.fromRandom();
    const verifier = new MeteredFlowVerifier(seederKey, COMMODITY, RATE);

    // Two independent payers, each its own key + flowId.
    const mk = (flowId: string) => {
      const key = PrivateKey.fromRandom();
      const cfg: MfpFlowConfig = {
        commodityId: COMMODITY, ratePerUnitSats: RATE, counterparty: seederKey.toPublicKey().toString(),
        flowId, fundMode: 'metered', vaultCapSats: 1_000_000n, channelChunkSats: 1_000_000n, refillThresholdSats: 0n,
      };
      return { payer: new MeteredFlowPayer(cfg, protoWalletPort(key)), pub: key.toPublicKey().toString(), flowId };
    };
    const a = mk('aaaaaaaaaaaaaaaa');
    const b = mk('bbbbbbbbbbbbbbbb');
    await a.payer.open();
    await b.payer.open();

    const multi = new MultiChannelServePolicy(verifier, RATE, [
      { flowId: a.flowId, payerIdentityPubHex: a.pub },
      { flowId: b.flowId, payerIdentityPubHex: b.pub },
    ]);

    const file = Uint8Array.from({ length: 8 * 1016 }, (_, i) => (i * 5 + 2) & 0xff);
    const published = publishFile(file, 'flow/multi');
    const brain = new FakeBrainClient();
    const bus = new SwarmBus();
    const seeder = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'seed'), brain, servePolicy: multi });
    const la = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'leechA'), brain, payPolicy: meteredFlowPayPolicy(a.payer) });
    const lb = new SwarmSession({ transport: inMemorySwarmTransport(bus, 'leechB'), brain, payPolicy: meteredFlowPayPolicy(b.payer) });
    cleanups.push(() => seeder.stop(), () => la.stop(), () => lb.stop());

    await seeder.seed(published);
    const [ga, gb] = await Promise.all([la.download(published.infohash), lb.download(published.infohash)]);
    expect(bytesEqual(ga, file) && bytesEqual(gb, file)).toBe(true);

    // Two distinct channels, each settling its own tab.
    const summary = multi.channelSummary().sort((x, y) => x.flowId.localeCompare(y.flowId));
    expect(summary.length).toBe(2);
    expect(summary[0]!.owedSats).toBe(BigInt(published.manifest.totalCells * RATE));
    expect(summary[1]!.owedSats).toBe(BigInt(published.manifest.totalCells * RATE));
    expect(multi.finalCommitment(a.flowId)!.flowId).toBe(a.flowId);
    expect(multi.finalCommitment(b.flowId)!.flowId).toBe(b.flowId);
  });
});

```
