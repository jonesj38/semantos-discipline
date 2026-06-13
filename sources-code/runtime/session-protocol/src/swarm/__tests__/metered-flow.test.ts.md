---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/metered-flow.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.077913+00:00
---

# runtime/session-protocol/src/swarm/__tests__/metered-flow.test.ts

```ts
/**
 * Metered-flow payment — the channel alternative to one-tx-per-cell.
 *
 * A leecher opens ONE channel and signs a real BRC-100 commitment per cell
 * (cumulative grows); the seeder verifies each off-chain and would serve. An
 * N-cell download → 1 funding + N off-chain commitments + 1 settle, NOT N txs.
 */
import { describe, expect, test } from 'bun:test';
import type { MfpFlowConfig } from '@semantos/protocol-types';
import { MeteredFlowPayer, MeteredFlowVerifier, protoWalletPort, PrivateKey } from '../metered-flow';

const COMMODITY = 'swarm.cell';
const RATE = 1; // sats per cell

function setup() {
  const payerKey = PrivateKey.fromRandom();
  const seederKey = PrivateKey.fromRandom();
  const cfg: MfpFlowConfig = {
    commodityId: COMMODITY,
    ratePerUnitSats: RATE,
    counterparty: seederKey.toPublicKey().toString(),
    flowId: 'a1b2c3d4e5f60718',
    fundMode: 'metered',
    vaultCapSats: 100_000n,
    channelChunkSats: 100_000n, // fund the whole file in one draw
    refillThresholdSats: 0n,
  };
  return {
    payer: new MeteredFlowPayer(cfg, protoWalletPort(payerKey)),
    verifier: new MeteredFlowVerifier(seederKey, COMMODITY, RATE),
    payerPubHex: payerKey.toPublicKey().toString(),
  };
}

describe('metered flow — per-cell off-chain commitments', () => {
  test('a 50-cell download = 1 funding + 50 signed commitments, all verified, 0 per-cell txs', async () => {
    const { payer, verifier, payerPubHex } = setup();
    await payer.open(); // ONE on-chain channel funding

    const cumulative: bigint[] = [];
    for (let cell = 1; cell <= 50; cell++) {
      const step = await payer.commit(cell);
      expect(step.kind).toBe('commitment');
      if (step.kind !== 'commitment') break;
      // seeder verifies this commitment off-chain before serving cell `cell`.
      expect(await verifier.verify(step.commitment, payerPubHex, cell)).toBe(true);
      expect(step.commitment.seq).toBe(cell);
      cumulative.push(step.commitment.cumulativeSats);
    }

    expect(cumulative.length).toBe(50);
    // Monotonic, and the final commitment authorises 50 sats for ONE settlement.
    for (let i = 1; i < cumulative.length; i++) expect(cumulative[i]! >= cumulative[i - 1]!).toBe(true);
    expect(cumulative[49]).toBe(50n);
  });

  test('rejects a tampered commitment (cumulative bumped, signature stale)', async () => {
    const { payer, verifier, payerPubHex } = setup();
    await payer.open();
    const step = await payer.commit(3);
    if (step.kind !== 'commitment') throw new Error('expected commitment');
    const forged = { ...step.commitment, cumulativeSats: step.commitment.cumulativeSats + 1000n };
    expect(await verifier.verify(forged, payerPubHex, 3)).toBe(false);
  });

  test('rejects a commitment from the wrong payer identity', async () => {
    const { payer, verifier } = setup();
    await payer.open();
    const step = await payer.commit(1);
    if (step.kind !== 'commitment') throw new Error('expected commitment');
    const strangerPub = PrivateKey.fromRandom().toPublicKey().toString();
    expect(await verifier.verify(step.commitment, strangerPub, 1)).toBe(false);
  });

  test('rejects under-commitment (cumulative does not cover cells owed)', async () => {
    const { payer, verifier, payerPubHex } = setup();
    await payer.open();
    const step = await payer.commit(2); // covers 2 cells
    if (step.kind !== 'commitment') throw new Error('expected commitment');
    // valid for 2 cells, but not for 5.
    expect(await verifier.verify(step.commitment, payerPubHex, 2)).toBe(true);
    expect(await verifier.verify(step.commitment, payerPubHex, 5)).toBe(false);
  });
});

```
