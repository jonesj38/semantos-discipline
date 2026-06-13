---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/access-grant-serve.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.075245+00:00
---

# runtime/session-protocol/src/swarm/__tests__/access-grant-serve.test.ts

```ts
/**
 * access-grant serve gate — RTC matrix A4 axis A (the DAM "Transfer-serve
 * integration"). The seeder admits a leecher to a file by an engine-checked
 * `access.grant`, not an app-layer cert check.
 *
 * NOTE ON THE TEST DOUBLE: `FakeAccessGrantVerifier` stands in for the real
 * 2-PDA verify `.handler` (cartridges/swarm/brain/access_grant_handler.zig),
 * exactly as `FakeBrainClient`/`StubXmppTransport` stand in for their live
 * counterparts. It models the engine's VERDICT — it does NOT re-implement the
 * ECDSA / expiry / capability checks in TS (that would be the very app-layer
 * enforcement DAM corrected against). The cryptographic correctness of the
 * verdict is proven where enforcement lives: the Zig 2-PDA tests + the
 * `accessChallengeDigest` cross-impl vector in
 * core/protocol-types/__tests__/access-grant.test.ts. This suite proves the
 * SEAM: the wire carries the proof, the policy routes the right grant and gates
 * on the verdict, and it composes with payment.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { LoopbackUdpTransport } from '@semantos/protocol-types/adapters/udp-transport';
import { publishFile, bytesEqual, sha256, toHex, HEADER_SIZE } from '@semantos/protocol-types';
import {
  encodeAccessGrantCell,
  accessGrantCellHash,
  decodeVerifyIntentPayload,
  decodeAccessGrantPayload,
  type AccessGrant,
} from '@semantos/protocol-types/bsv/access-grant';
import { udpSwarmTransport } from '../swarm-transport';
import { FakeBrainClient } from '../brain-client';
import { SwarmSession, type ServePolicy, type PayPolicy } from '../swarm-session';
import { encodeRequest, decodeRequest, type SwarmRequest } from '../swarm-wire';
import {
  AccessGrantServePolicy,
  makeGrantPayPolicy,
  andServePolicies,
  andPayPolicies,
  type AccessGrantVerifier,
  type AccessGrantProver,
  type GrantRecord,
} from '../access-grant-serve';

const PORT = 42200;
const GROUP = 'ff02::a4-grant';

// ── helpers ────────────────────────────────────────────────────────────

function fileOf(n: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 37 + 11) & 0xff;
  return b;
}
function pubkey(seed: number): Uint8Array {
  const k = new Uint8Array(33);
  k[0] = 0x02;
  for (let i = 1; i < 33; i++) k[i] = (seed + i) & 0xff;
  return k;
}
function makeTransport(addr: string) {
  const udp = new LoopbackUdpTransport(addr);
  return udpSwarmTransport({ udp, address: addr, port: PORT, group: GROUP });
}
function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([p, new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`timeout: ${label}`)), ms))]);
}

/** Issue a grant + return everything the seeder + leecher need to test with. */
function issueGrant(opts: { granteeSeed: number; contentHash: Uint8Array; expiry?: bigint }) {
  const granteePubkey = pubkey(opts.granteeSeed);
  const grant: AccessGrant = {
    granteePubkey,
    contentHash: opts.contentHash,
    expiry: opts.expiry ?? 9_999_999_999n,
  };
  const cell = encodeAccessGrantCell(grant);
  const grantHash = accessGrantCellHash(cell);
  return { grant, cell, grantHash, record: { cell, grant } as GrantRecord };
}

/**
 * The 2-PDA stand-in. `accept` decides the engine's verdict; the verifier reads
 * the intent's grant hash + the grant cell's content hash to mirror what the
 * real handler returns (ok + the bound content hash).
 */
class FakeAccessGrantVerifier implements AccessGrantVerifier {
  calls = 0;
  constructor(private readonly accept: (grantHashHex: string) => boolean) {}
  async verify({ grantCell, intentCell }: { grantCell: Uint8Array; intentCell: Uint8Array }) {
    this.calls++;
    const intent = decodeVerifyIntentPayload(intentCell.slice(HEADER_SIZE));
    const grant = decodeAccessGrantPayload(grantCell.slice(HEADER_SIZE));
    const ok = this.accept(toHex(intent.grantHash));
    return ok ? { ok, contentHash: grant.contentHash } : { ok };
  }
}

/** The leecher's signer stand-in: attaches a (placeholder) signature for a held
 *  grant. Real signing lives in the wallet (edge BRC-42 key). */
function proverFor(grantHash: Uint8Array): AccessGrantProver {
  return {
    async proveAccess(h) {
      if (!bytesEqual(h, grantHash)) return null;
      return { grantHash: h, signature: new Uint8Array(71).fill(0x30) }; // DER ‖ flag placeholder
    },
  };
}

afterEach(() => LoopbackUdpTransport.resetAll());

// ── 1. wire round-trip ─────────────────────────────────────────────────

describe('SwarmRequest grant-proof wire', () => {
  test('round-trips a request carrying a grant proof', () => {
    const req: SwarmRequest = {
      infohash: new Uint8Array(32).fill(7),
      cellIndex: 5,
      requesterBca: new Uint8Array(16).fill(9),
      grant: { grantHash: new Uint8Array(32).fill(0xab), signature: new Uint8Array(70).fill(0x30) },
    };
    const back = decodeRequest(encodeRequest(req));
    expect(back.grant).toBeDefined();
    expect(bytesEqual(back.grant!.grantHash, req.grant!.grantHash)).toBe(true);
    expect(bytesEqual(back.grant!.signature, req.grant!.signature)).toBe(true);
    expect(back.payment).toBeUndefined();
    expect(back.commitment).toBeUndefined();
  });

  test('a request without a grant decodes with grant undefined (back-compat)', () => {
    const req: SwarmRequest = {
      infohash: new Uint8Array(32).fill(1),
      cellIndex: 0,
      requesterBca: new Uint8Array(16).fill(2),
    };
    const back = decodeRequest(encodeRequest(req));
    expect(back.grant).toBeUndefined();
  });
});

// ── 2. policy unit (the gate branches) ─────────────────────────────────

describe('AccessGrantServePolicy', () => {
  const content = sha256(fileOf(2048));
  const { grantHash, record } = issueGrant({ granteeSeed: 1, contentHash: content });
  const req = (grant?: SwarmRequest['grant']): SwarmRequest => ({
    infohash: new Uint8Array(32),
    cellIndex: 0,
    requesterBca: new Uint8Array(16),
    grant,
  });
  const proof = { grantHash, signature: new Uint8Array(71).fill(0x30) };

  test('serves when the grant resolves, binds to the content, and the engine says ok', async () => {
    const verifier = new FakeAccessGrantVerifier(() => true);
    const policy = new AccessGrantServePolicy({ verifier, resolveGrant: () => record, contentHash: content });
    expect(await policy.authorizeServe(req(proof))).toBe(true);
    expect(verifier.calls).toBe(1);
  });

  test('refuses a request with no grant proof (fail-closed) — engine never consulted', async () => {
    const verifier = new FakeAccessGrantVerifier(() => true);
    const policy = new AccessGrantServePolicy({ verifier, resolveGrant: () => record, contentHash: content });
    expect(await policy.authorizeServe(req(undefined))).toBe(false);
    expect(verifier.calls).toBe(0);
  });

  test('refuses when the grant is revoked (resolver returns undefined)', async () => {
    const verifier = new FakeAccessGrantVerifier(() => true);
    const policy = new AccessGrantServePolicy({ verifier, resolveGrant: () => undefined, contentHash: content });
    expect(await policy.authorizeServe(req(proof))).toBe(false);
    expect(verifier.calls).toBe(0);
  });

  test('refuses a grant minted for different content', async () => {
    const other = issueGrant({ granteeSeed: 2, contentHash: sha256(fileOf(64)) });
    const verifier = new FakeAccessGrantVerifier(() => true);
    const policy = new AccessGrantServePolicy({ verifier, resolveGrant: () => other.record, contentHash: content });
    const otherProof = { grantHash: other.grantHash, signature: new Uint8Array(71).fill(0x30) };
    expect(await policy.authorizeServe(req(otherProof))).toBe(false);
    expect(verifier.calls).toBe(0); // routed out before the engine
  });

  test('refuses when the engine rejects the verdict (bad sig / expired live on the 2-PDA)', async () => {
    const verifier = new FakeAccessGrantVerifier(() => false);
    const policy = new AccessGrantServePolicy({ verifier, resolveGrant: () => record, contentHash: content });
    expect(await policy.authorizeServe(req(proof))).toBe(false);
    expect(verifier.calls).toBe(1);
  });
});

// ── 3. combinators ─────────────────────────────────────────────────────

describe('policy combinators', () => {
  const allow: ServePolicy = { authorizeServe: () => true };
  const deny: ServePolicy = { authorizeServe: () => false };

  test('andServePolicies serves only when all authorize', async () => {
    expect(await andServePolicies(allow, allow).authorizeServe({} as SwarmRequest)).toBe(true);
    expect(await andServePolicies(allow, deny).authorizeServe({} as SwarmRequest)).toBe(false);
  });

  test('andServePolicies concatenates receipts', () => {
    const a: ServePolicy = { authorizeServe: () => true, drainReceipts: () => [{ cellIndex: 0 } as any] };
    const b: ServePolicy = { authorizeServe: () => true, drainReceipts: () => [{ cellIndex: 1 } as any] };
    expect(andServePolicies(a, b).drainReceipts!()).toHaveLength(2);
  });

  test('andPayPolicies merges a grant proof and a payment onto one request', async () => {
    const grantPol = makeGrantPayPolicy(proverFor(new Uint8Array(32).fill(5)), new Uint8Array(32).fill(5));
    const payPol: PayPolicy = { payFor: async () => ({ payment: { txAnchor: new Uint8Array(32), amount: 10n, currency: 'sat' } }) };
    const merged = await andPayPolicies(grantPol, payPol).payFor(new Uint8Array(32), 0, 'addr');
    expect(merged?.grant).toBeDefined();
    expect(merged?.payment).toBeDefined();
  });

  test('andPayPolicies returns null when no policy attaches anything', async () => {
    const none: PayPolicy = { payFor: async () => null };
    expect(await andPayPolicies(none, none).payFor(new Uint8Array(32), 0, 'addr')).toBeNull();
  });
});

// ── 4. end-to-end over loopback ────────────────────────────────────────

describe('access-grant swarm — serve gate over loopback', () => {
  test('a grantee with a valid proof downloads the whole file', async () => {
    const file = fileOf(6 * 1016);
    const published = publishFile(file, 'grant/ok');
    const brain = new FakeBrainClient();
    const { grantHash, record } = issueGrant({ granteeSeed: 1, contentHash: published.manifest.contentHash });

    const verifier = new FakeAccessGrantVerifier(() => true);
    const policy = new AccessGrantServePolicy({
      verifier,
      resolveGrant: (h) => (bytesEqual(h, grantHash) ? record : undefined),
      contentHash: published.manifest.contentHash,
    });
    const seeder = new SwarmSession({ transport: makeTransport('fe80::1'), brain, servePolicy: policy });
    const leecher = new SwarmSession({
      transport: makeTransport('fe80::2'),
      brain,
      payPolicy: makeGrantPayPolicy(proverFor(grantHash), grantHash),
    });

    await seeder.seed(published);
    const got = await withTimeout(leecher.download(published.infohash), 5000, 'grant-download');
    expect(bytesEqual(got, file)).toBe(true);
    expect(verifier.calls).toBeGreaterThanOrEqual(published.manifest.totalCells);

    await seeder.stop();
    await leecher.stop();
  });

  test('a leecher with no grant proof stalls', async () => {
    const file = fileOf(3 * 1016);
    const published = publishFile(file, 'grant/none');
    const brain = new FakeBrainClient();
    const { grantHash, record } = issueGrant({ granteeSeed: 1, contentHash: published.manifest.contentHash });
    const policy = new AccessGrantServePolicy({
      verifier: new FakeAccessGrantVerifier(() => true),
      resolveGrant: (h) => (bytesEqual(h, grantHash) ? record : undefined),
      contentHash: published.manifest.contentHash,
    });
    const seeder = new SwarmSession({ transport: makeTransport('fe80::1'), brain, servePolicy: policy });
    const leecher = new SwarmSession({ transport: makeTransport('fe80::2'), brain }); // no payPolicy

    await seeder.seed(published);
    await expect(withTimeout(leecher.download(published.infohash), 700, 'no-grant')).rejects.toThrow('timeout');

    await seeder.stop();
    await leecher.stop();
  });

  test('a revoked grant (resolver gone) stalls the download', async () => {
    const file = fileOf(3 * 1016);
    const published = publishFile(file, 'grant/revoked');
    const brain = new FakeBrainClient();
    const { grantHash } = issueGrant({ granteeSeed: 1, contentHash: published.manifest.contentHash });
    const policy = new AccessGrantServePolicy({
      verifier: new FakeAccessGrantVerifier(() => true),
      resolveGrant: () => undefined, // revoked: the LINEAR grant was consumed
      contentHash: published.manifest.contentHash,
    });
    const seeder = new SwarmSession({ transport: makeTransport('fe80::1'), brain, servePolicy: policy });
    const leecher = new SwarmSession({
      transport: makeTransport('fe80::2'),
      brain,
      payPolicy: makeGrantPayPolicy(proverFor(grantHash), grantHash),
    });

    await seeder.seed(published);
    await expect(withTimeout(leecher.download(published.infohash), 700, 'revoked')).rejects.toThrow('timeout');

    await seeder.stop();
    await leecher.stop();
  });

  test('the engine rejecting the verdict stalls the download', async () => {
    const file = fileOf(3 * 1016);
    const published = publishFile(file, 'grant/rejected');
    const brain = new FakeBrainClient();
    const { grantHash, record } = issueGrant({ granteeSeed: 1, contentHash: published.manifest.contentHash });
    const policy = new AccessGrantServePolicy({
      verifier: new FakeAccessGrantVerifier(() => false), // 2-PDA says no
      resolveGrant: (h) => (bytesEqual(h, grantHash) ? record : undefined),
      contentHash: published.manifest.contentHash,
    });
    const seeder = new SwarmSession({ transport: makeTransport('fe80::1'), brain, servePolicy: policy });
    const leecher = new SwarmSession({
      transport: makeTransport('fe80::2'),
      brain,
      payPolicy: makeGrantPayPolicy(proverFor(grantHash), grantHash),
    });

    await seeder.seed(published);
    await expect(withTimeout(leecher.download(published.infohash), 700, 'rejected')).rejects.toThrow('timeout');

    await seeder.stop();
    await leecher.stop();
  });
});

```
