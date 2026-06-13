---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/swarm-wallet.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.074063+00:00
---

# runtime/session-protocol/src/swarm/__tests__/swarm-wallet.test.ts

```ts
/**
 * Wallet seam — the metered-flow channel signs commitments through a BRC-100
 * WalletInterface. The bundled headless ProtoWallet and Metanet Desktop / a
 * browser wallet are the SAME interface (different transport), so a commitment
 * signed by any of them verifies. (Metanet Desktop itself needs the app running
 * — not exercisable here; ProtoWallet stands in for the interface.)
 */
import { describe, expect, test } from 'bun:test';
import { ProtoWallet, PrivateKey } from '@bsv/sdk';
import type { MfpFlowConfig } from '@semantos/protocol-types';
import { MeteredFlowPayer, MeteredFlowVerifier } from '../metered-flow';
import { brc100WalletPort, resolveWalletPort, walletIdentityPubHex } from '../swarm-wallet';

describe('swarm wallet seam', () => {
  test('a commitment signed via a BRC-100 wallet verifies', async () => {
    const payerKey = PrivateKey.fromRandom();
    const seederKey = PrivateKey.fromRandom();
    const cfg: MfpFlowConfig = {
      commodityId: 'swarm.cell', ratePerUnitSats: 1, counterparty: seederKey.toPublicKey().toString(),
      flowId: 'abcdef0123456789', fundMode: 'metered', vaultCapSats: 1000n, channelChunkSats: 1000n, refillThresholdSats: 0n,
    };
    // BRC-100 path — ProtoWallet here; Metanet Desktop / browser are the same WalletInterface.
    const payer = new MeteredFlowPayer(cfg, brc100WalletPort(new ProtoWallet(payerKey)));
    await payer.open();
    const step = await payer.commit(3);
    expect(step.kind).toBe('commitment');
    if (step.kind !== 'commitment') return;

    const verifier = new MeteredFlowVerifier(seederKey, 'swarm.cell', 1);
    expect(await verifier.verify(step.commitment, payerKey.toPublicKey().toString(), 3)).toBe(true);
    expect(step.commitment.cumulativeSats).toBe(3n);
  });

  test('resolveWalletPort selects bundled-headless / none', () => {
    const keyHex = PrivateKey.fromRandom().toHex();
    expect(resolveWalletPort({ mode: 'none' })).toBeUndefined();
    expect(resolveWalletPort({ mode: 'headless', keyHex })).toBeDefined();
  });

  test('walletIdentityPubHex resolves the headless identity key', async () => {
    const key = PrivateKey.fromRandom();
    expect(await walletIdentityPubHex({ mode: 'headless', keyHex: key.toHex() })).toBe(key.toPublicKey().toString());
  });
});

```
