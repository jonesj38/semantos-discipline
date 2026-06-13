---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/swarm-broadcast.loopback.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.081307+00:00
---

# runtime/session-protocol/src/swarm/__tests__/swarm-broadcast.loopback.test.ts

```ts
/**
 * Paid private broadcast over loopback — the A4 capstone. A multi-segment
 * broadcast served by per-segment SwarmSessions that are BOTH gated (engine-
 * checked access.grant, #987) AND metered (per-cell prepay, #977), composed via
 * andServePolicies / andPayPolicies. Proves:
 *   - an authorized + paying subscriber reassembles the whole broadcast and the
 *     seeders settle per-cell receipts;
 *   - a paying-but-ungranted subscriber stalls (the grant gate);
 *   - a granted-but-unpaying subscriber stalls (the meter gate).
 *
 * One broadcast-level grant admits the subscriber to EVERY segment; metering is
 * orthogonal and per-cell. (FakeAccessGrantVerifier stands in for the 2-PDA, as
 * in access-grant-serve.test.ts.)
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { LoopbackUdpTransport } from '@semantos/protocol-types/adapters/udp-transport';
import { bytesEqual } from '@semantos/protocol-types';
import {
  encodeAccessGrantCell,
  accessGrantCellHash,
  type AccessGrant,
} from '@semantos/protocol-types/bsv/access-grant';
import type { EconomicPort } from '@semantos/identity-ports';
import { sha256, toHex } from '@semantos/protocol-types';
import { udpSwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmSession } from '../swarm-session';
import { PaidSeeder, makePayPolicy } from '../paid-seeder';
import {
  AccessGrantServePolicy,
  makeGrantPayPolicy,
  andServePolicies,
  andPayPolicies,
  type AccessGrantVerifier,
  type AccessGrantProver,
} from '../access-grant-serve';
import { segmentBuffer, publishBroadcast, broadcastContentHash } from '../media-broadcast';
import { seedBroadcast, consumeSwarmBroadcast } from '../swarm-broadcast';

const PORT = 42300;
const GROUP = 'ff02::a4-paid';
const PRICE = 10;

function mediaOf(n: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 29 + 13) & 0xff;
  return b;
}
function makeTransport(addr: string) {
  const udp = new LoopbackUdpTransport(addr);
  return udpSwarmTransport({ udp, address: addr, port: PORT, group: GROUP });
}
function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([p, new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`timeout: ${label}`)), ms))]);
}

/** Shared-ledger stub economy (per swarm-paid.loopback.test.ts). */
class StubEconomy {
  private readonly ledger = new Map<string, { amount: number; currency: string }>();
  private seq = 0;
  port(): EconomicPort {
    return {
      signSpend: async (input) => {
        const anchor = toHex(sha256(new TextEncoder().encode(`${input.payerCertId}|${input.targetId}|${input.amount}|${input.memo}|${this.seq++}`)));
        this.ledger.set(anchor, { amount: input.amount, currency: input.currency });
        return { txAnchor: anchor, amount: input.amount, currency: input.currency, verifier: 'stub' };
      },
      verifyPayment: async ({ txAnchor, amount, currency }) => {
        const e = this.ledger.get(txAnchor);
        if (!e) return { valid: false, reason: 'unknown', verifier: 'stub' };
        if (e.currency !== currency || amount > e.amount) return { valid: false, reason: 'amount', verifier: 'stub' };
        return { valid: true, verifier: 'stub' };
      },
    };
  }
}

const okVerifier: AccessGrantVerifier = { verify: async () => ({ ok: true }) };
function proverFor(grantHash: Uint8Array): AccessGrantProver {
  return { async proveAccess(h) { return bytesEqual(h, grantHash) ? { grantHash: h, signature: new Uint8Array(71).fill(0x30) } : null; } };
}

/** Build a 2-segment broadcast + a broadcast-level grant bound to it. */
function setupBroadcast() {
  const media = mediaOf(4 * 1016); // → 2 segments of ~2 cells each at target 2*1016
  const segs = segmentBuffer(media, { targetBytes: 2 * 1016 });
  const { playlist, published } = publishBroadcast(segs, 'paid/talk');
  const broadcastHash = broadcastContentHash(playlist);
  const grant: AccessGrant = { granteePubkey: new Uint8Array(33).fill(2), contentHash: broadcastHash, expiry: 9_999_999_999n };
  const cell = encodeAccessGrantCell(grant);
  const grantHash = accessGrantCellHash(cell);
  const resolveGrant = (h: Uint8Array) => (bytesEqual(h, grantHash) ? { cell, grant } : undefined);
  return { media, playlist, published, broadcastHash, grantHash, resolveGrant };
}

afterEach(() => LoopbackUdpTransport.resetAll());

describe('paid private broadcast over the swarm', () => {
  test('an authorized + paying subscriber reassembles the broadcast and seeders settle receipts', async () => {
    const { media, playlist, published, broadcastHash, grantHash, resolveGrant } = setupBroadcast();
    const brain = new FakeBrainClient();
    const economy = new StubEconomy();
    const paidSeeders: PaidSeeder[] = [];

    const seeders = await seedBroadcast(published, (_role, i) => {
      const paid = new PaidSeeder({ economic: economy.port(), pricePerCellSats: PRICE });
      paidSeeders.push(paid);
      const grantGate = new AccessGrantServePolicy({ verifier: okVerifier, resolveGrant, contentHash: broadcastHash });
      return new SwarmSession({
        transport: makeTransport(`fe80::5${i}`),
        brain,
        servePolicy: andServePolicies(grantGate, paid),
      });
    });

    const order: number[] = [];
    const got = await withTimeout(
      consumeSwarmBroadcast(playlist, (_role, i) => new SwarmSession({
        transport: makeTransport(`fe80::6${i}`),
        brain,
        payPolicy: andPayPolicies(
          makeGrantPayPolicy(proverFor(grantHash), grantHash),
          makePayPolicy({ economic: economy.port(), payerCertId: 'sub', pricePerCellSats: PRICE }),
        ),
      }), { onSegment: (_b, ref) => order.push(ref.index) }),
      6000,
      'paid-broadcast',
    );

    expect(bytesEqual(got, media)).toBe(true);
    expect(order).toEqual([0, 1]);
    // Each seeder metered its served cells.
    const settled = (await Promise.all(seeders.map((s) => s.flushReceipts()))).reduce((a, n) => a + n, 0);
    expect(settled).toBe(playlist.segments.reduce((a, ref) => a + Math.ceil(ref.byteLength / 1016), 0));
    await Promise.all(seeders.map((s) => s.stop()));
  });

  test('a paying but UNGRANTED subscriber stalls (the grant gate)', async () => {
    const { playlist, published, broadcastHash, resolveGrant } = setupBroadcast();
    const brain = new FakeBrainClient();
    const economy = new StubEconomy();

    const seeders = await seedBroadcast(published, (_role, i) =>
      new SwarmSession({
        transport: makeTransport(`fe80::5${i}`),
        brain,
        servePolicy: andServePolicies(
          new AccessGrantServePolicy({ verifier: okVerifier, resolveGrant, contentHash: broadcastHash }),
          new PaidSeeder({ economic: economy.port(), pricePerCellSats: PRICE }),
        ),
      }),
    );

    await expect(
      withTimeout(
        consumeSwarmBroadcast(playlist, (_role, i) => new SwarmSession({
          transport: makeTransport(`fe80::6${i}`),
          brain,
          payPolicy: makePayPolicy({ economic: economy.port(), payerCertId: 'sub', pricePerCellSats: PRICE }), // pays, no grant
        })),
        900,
        'ungranted',
      ),
    ).rejects.toThrow('timeout');
    await Promise.all(seeders.map((s) => s.stop()));
  });

  test('a granted but UNPAYING subscriber stalls (the meter gate)', async () => {
    const { playlist, published, broadcastHash, grantHash, resolveGrant } = setupBroadcast();
    const brain = new FakeBrainClient();
    const economy = new StubEconomy();

    const seeders = await seedBroadcast(published, (_role, i) =>
      new SwarmSession({
        transport: makeTransport(`fe80::5${i}`),
        brain,
        servePolicy: andServePolicies(
          new AccessGrantServePolicy({ verifier: okVerifier, resolveGrant, contentHash: broadcastHash }),
          new PaidSeeder({ economic: economy.port(), pricePerCellSats: PRICE }),
        ),
      }),
    );

    await expect(
      withTimeout(
        consumeSwarmBroadcast(playlist, (_role, i) => new SwarmSession({
          transport: makeTransport(`fe80::6${i}`),
          brain,
          payPolicy: makeGrantPayPolicy(proverFor(grantHash), grantHash), // grant, no payment
        })),
        900,
        'unpaid',
      ),
    ).rejects.toThrow('timeout');
    await Promise.all(seeders.map((s) => s.stop()));
  });
});

```
