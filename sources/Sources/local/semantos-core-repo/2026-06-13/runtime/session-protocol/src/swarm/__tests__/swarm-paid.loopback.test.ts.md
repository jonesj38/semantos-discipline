---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/swarm-paid.loopback.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.074945+00:00
---

# runtime/session-protocol/src/swarm/__tests__/swarm-paid.loopback.test.ts

```ts
/**
 * Paid swarm loop over loopback — M4.
 *
 * Prepay model: the leecher signs a per-cell spend and attaches the txAnchor to
 * each request; the seeder verifies payment before serving and records a
 * receipt. Asserts: paid download completes + every served cell is settled to
 * the brain ledger; an unpaid leecher is refused (download stalls); an
 * underpaying leecher is refused.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { LoopbackUdpTransport } from '@semantos/protocol-types/adapters/udp-transport';
import { publishFile, bytesEqual, sha256, toHex } from '@semantos/protocol-types';
import type { EconomicPort } from '@semantos/identity-ports';
import { udpSwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmSession } from '../swarm-session';
import { PaidSeeder, makePayPolicy } from '../paid-seeder';

const PORT = 42100;
const GROUP = 'ff02::paid-swarm';

/** Shared-ledger stub economy so a leecher's signSpend validates on the seeder. */
class StubEconomy {
  private readonly ledger = new Map<string, { amount: number; currency: string }>();
  private seq = 0;
  port(): EconomicPort {
    return {
      signSpend: async input => {
        const seed = `${input.payerCertId}|${input.targetId}|${input.amount}|${input.memo}|${this.seq++}`;
        const anchor = toHex(sha256(new TextEncoder().encode(seed)));
        this.ledger.set(anchor, { amount: input.amount, currency: input.currency });
        return { txAnchor: anchor, amount: input.amount, currency: input.currency, verifier: 'stub' };
      },
      verifyPayment: async ({ txAnchor, amount, currency }) => {
        const e = this.ledger.get(txAnchor);
        if (!e) return { valid: false, reason: 'unknown-anchor', verifier: 'stub' };
        if (e.currency !== currency || amount > e.amount) return { valid: false, reason: 'amount', verifier: 'stub' };
        return { valid: true, verifier: 'stub' };
      },
    };
  }
}

function makeTransport(addr: string) {
  const udp = new LoopbackUdpTransport(addr);
  return udpSwarmTransport({ udp, address: addr, port: PORT, group: GROUP });
}
function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([p, new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`timeout: ${label}`)), ms))]);
}
function fileOf(n: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 41 + 17) & 0xff;
  return b;
}

afterEach(() => LoopbackUdpTransport.resetAll());

describe('paid swarm — prepay loop', () => {
  test('paid download completes and every served cell is settled to the brain', async () => {
    const file = fileOf(8 * 1016);
    const published = publishFile(file, 'paid/file');
    const brain = new FakeBrainClient();
    const economy = new StubEconomy();
    const PRICE = 10;

    const paidSeeder = new PaidSeeder({ economic: economy.port(), pricePerCellSats: PRICE });
    const seeder = new SwarmSession({ transport: makeTransport('fe80::1'), brain, servePolicy: paidSeeder });
    const leecher = new SwarmSession({
      transport: makeTransport('fe80::2'),
      brain,
      payPolicy: makePayPolicy({ economic: economy.port(), payerCertId: 'leecher-cert', pricePerCellSats: PRICE }),
    });

    await seeder.seed(published);
    const got = await withTimeout(leecher.download(published.infohash), 5000, 'paid-download');
    expect(bytesEqual(got, file)).toBe(true);
    expect(bytesEqual(sha256(got), published.manifest.contentHash)).toBe(true);

    // Settle: one receipt per served cell, journaled to the brain ledger.
    const recorded = await seeder.flushReceipts();
    expect(recorded).toBe(published.manifest.totalCells);
    expect(brain.receiptsFor(published.infohash).length).toBe(published.manifest.totalCells);
    const totalSats = brain.receiptsFor(published.infohash).reduce((a, r) => a + r.amount, 0);
    expect(totalSats).toBe(PRICE * published.manifest.totalCells);
    // Drained — a second flush records nothing.
    expect(await seeder.flushReceipts()).toBe(0);

    await seeder.stop();
    await leecher.stop();
  });

  test('an unpaid leecher is refused (download stalls)', async () => {
    const file = fileOf(4 * 1016);
    const published = publishFile(file, 'unpaid/file');
    const brain = new FakeBrainClient();
    const economy = new StubEconomy();

    const paidSeeder = new PaidSeeder({ economic: economy.port(), pricePerCellSats: 10 });
    const seeder = new SwarmSession({ transport: makeTransport('fe80::1'), brain, servePolicy: paidSeeder });
    // No payPolicy → requests carry no payment.
    const leecher = new SwarmSession({ transport: makeTransport('fe80::2'), brain });

    await seeder.seed(published);
    await expect(withTimeout(leecher.download(published.infohash), 700, 'unpaid')).rejects.toThrow('timeout');
    expect(paidSeeder.drainReceipts().length).toBe(0); // nothing served

    await seeder.stop();
    await leecher.stop();
  });

  test('an underpaying leecher is refused', async () => {
    const file = fileOf(4 * 1016);
    const published = publishFile(file, 'underpay/file');
    const brain = new FakeBrainClient();
    const economy = new StubEconomy();

    const paidSeeder = new PaidSeeder({ economic: economy.port(), pricePerCellSats: 10 });
    const seeder = new SwarmSession({ transport: makeTransport('fe80::1'), brain, servePolicy: paidSeeder });
    const leecher = new SwarmSession({
      transport: makeTransport('fe80::2'),
      brain,
      payPolicy: makePayPolicy({ economic: economy.port(), payerCertId: 'cheapskate', pricePerCellSats: 5 }),
    });

    await seeder.seed(published);
    await expect(withTimeout(leecher.download(published.infohash), 700, 'underpay')).rejects.toThrow('timeout');
    expect(paidSeeder.drainReceipts().length).toBe(0);

    await seeder.stop();
    await leecher.stop();
  });
});

```
