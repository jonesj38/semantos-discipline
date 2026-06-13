---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tests/key-derivation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.636582+00:00
---

# cartridges/tessera/brain/tests/key-derivation.test.ts

```ts
/**
 * Tessera × L11 — first consumer of the substrate-side
 * IdentityAdapter.deriveSegmentPublicKey port.
 *
 * Reference:
 *   docs/canon/cw-lift-matrix.yml L11.
 *   docs/prd/TESSERA-CARTRIDGE.md §0.1 #2.
 *
 * Verifies:
 *   - TesseraKeyDerivation routes ALL derivation through the substrate
 *     seam (the IdentityAdapter) — never @bsv/sdk, never vendor-sdk.
 *   - Per-(cellType, cellId, role) derivations are deterministic.
 *   - Different cells / different roles / different operator roots
 *     produce different pubkeys.
 *   - Fail-closed on bad inputs.
 *   - Realistic care-chain scenarios (producer derives bottle owner;
 *     consumer-app derives scanner; care-event derives handler).
 */

import { describe, expect, test } from 'bun:test';
import {
  TesseraKeyDerivation,
  tesseraDerivationSegment,
  TESSERA_DERIVATION_DOMAIN_FLAG,
} from '../src/key-derivation';

// ── Test seam: minimal IdentityAdapter that captures calls ──
//
// We don't import StubIdentityAdapter here because that lives in
// @semantos/protocol-types and tessera's consumption gate forbids
// importing from substrate INTERNAL modules from tessera tests. The
// test seam mirrors the only method the cartridge actually uses.

interface DeriveCall {
  parentPubKeyHex: string;
  domainFlag: number;
  segment: Uint8Array | string;
}

function makeMockIdentityAdapter() {
  const calls: DeriveCall[] = [];
  return {
    calls,
    adapter: {
      // L11.5: the cartridge uses the domain-separated method. Every
      // other IdentityAdapter method is absent on the test seam to prove
      // tessera isn't reaching for them.
      async deriveDomainSegmentPublicKey(
        parentPubKeyHex: string,
        domainFlag: number,
        segment: Uint8Array | string,
      ): Promise<{ childPubKeyHex: string }> {
        calls.push({ parentPubKeyHex, domainFlag, segment });
        // Deterministic mock: hash inputs (incl. the flag), take 64 hex
        // chars, prefix 02/03 by a parity bit. Mirrors the stub structure
        // without depending on @bsv/sdk.
        const segHex =
          typeof segment === 'string'
            ? Buffer.from(segment, 'utf8').toString('hex')
            : Buffer.from(segment).toString('hex');
        const flagHex = (domainFlag >>> 0).toString(16).padStart(8, '0');
        const { createHash } = await import('node:crypto');
        const digest = createHash('sha256')
          .update(parentPubKeyHex + ':' + flagHex + ':' + segHex)
          .digest('hex');
        const prefix = parseInt(digest.slice(62, 64), 16) & 1 ? '03' : '02';
        return { childPubKeyHex: prefix + digest.slice(0, 64) };
      },
      // The rest of IdentityAdapter is not exercised by this surface.
      // We don't even cast — TypeScript would complain, so we let the
      // adapter parameter type widen by passing this object as `as any`
      // at the call site of TesseraKeyDerivation construction. This is
      // a test seam, not production code.
    } as unknown as import('@semantos/protocol-types').IdentityAdapter,
  };
}

const OPERATOR_ROOT_PUB =
  '02e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';

describe('tessera × L11 — derivation segment construction', () => {
  test('canonical format: tessera/<cellType>/<cellId>/<role>', () => {
    expect(
      tesseraDerivationSegment('tessera.bottle', 'btl-aaaa', 'owner'),
    ).toBe('tessera.bottle/btl-aaaa/owner');
    expect(
      tesseraDerivationSegment('tessera.care-event', 'ce-bbbb', 'handler'),
    ).toBe('tessera.care-event/ce-bbbb/handler');
    expect(
      tesseraDerivationSegment('tessera.scan-event', 'se-cccc', 'scanner'),
    ).toBe('tessera.scan-event/se-cccc/scanner');
  });

  test('rejects empty cellId', () => {
    expect(() =>
      tesseraDerivationSegment('tessera.bottle', '', 'owner'),
    ).toThrow();
  });
});

describe('tessera × L11 — TesseraKeyDerivation construction', () => {
  test('rejects non-66-char operator root pubkey', () => {
    const { adapter } = makeMockIdentityAdapter();
    expect(() => new TesseraKeyDerivation(adapter, 'too-short')).toThrow();
    expect(
      () => new TesseraKeyDerivation(adapter, 'A'.repeat(66)),
    ).toThrow(); // uppercase
  });

  test('rejects empty operator root pubkey', () => {
    const { adapter } = makeMockIdentityAdapter();
    expect(() => new TesseraKeyDerivation(adapter, '')).toThrow();
  });
});

describe('tessera × L11 — per-cell derivation routes through the substrate seam', () => {
  test('deriveOwner(bottle) calls deriveDomainSegmentPublicKey with the right flag + segment', async () => {
    const { adapter, calls } = makeMockIdentityAdapter();
    const tkd = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);
    const result = await tkd.deriveOwner('tessera.bottle', 'btl-aaaa');

    expect(calls.length).toBe(1);
    expect(calls[0].parentPubKeyHex).toBe(OPERATOR_ROOT_PUB);
    // L11.5: binds the tessera page-base domain flag (0x00010400).
    expect(calls[0].domainFlag).toBe(TESSERA_DERIVATION_DOMAIN_FLAG);
    expect(TESSERA_DERIVATION_DOMAIN_FLAG).toBe(0x00010400);
    expect(calls[0].segment).toBe('tessera.bottle/btl-aaaa/owner');
    expect(result.segment).toBe('tessera.bottle/btl-aaaa/owner');
    expect(result.pubKeyHex.length).toBe(66);
    expect(['02', '03']).toContain(result.pubKeyHex.slice(0, 2));
  });

  test('deriveHandler(care-event) routes to the substrate seam with handler role', async () => {
    const { adapter, calls } = makeMockIdentityAdapter();
    const tkd = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);
    const result = await tkd.deriveHandler('tessera.care-event', 'ce-bbbb');
    expect(calls[0].segment).toBe('tessera.care-event/ce-bbbb/handler');
    expect(result.segment).toBe('tessera.care-event/ce-bbbb/handler');
  });

  test('deriveScanner(scan-event) routes to the substrate seam with scanner role', async () => {
    const { adapter, calls } = makeMockIdentityAdapter();
    const tkd = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);
    const result = await tkd.deriveScanner('tessera.scan-event', 'se-cccc');
    expect(calls[0].segment).toBe('tessera.scan-event/se-cccc/scanner');
    expect(result.segment).toBe('tessera.scan-event/se-cccc/scanner');
  });

  test('deriveForRole(role) generic — accepts any TesseraRole', async () => {
    const { adapter, calls } = makeMockIdentityAdapter();
    const tkd = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);
    await tkd.deriveForRole('tessera.tasting-note', 'tn-dddd', 'author');
    expect(calls[0].segment).toBe('tessera.tasting-note/tn-dddd/author');
    await tkd.deriveForRole('tessera.tamper-event', 'te-eeee', 'reporter');
    expect(calls[1].segment).toBe('tessera.tamper-event/te-eeee/reporter');
    await tkd.deriveForRole('tessera.care-event', 'ce-ffff', 'witness');
    expect(calls[2].segment).toBe('tessera.care-event/ce-ffff/witness');
  });
});

describe('tessera × L11 — determinism + binding invariants', () => {
  test('same (cellType, cellId, role) → same pubkey', async () => {
    const { adapter } = makeMockIdentityAdapter();
    const tkd = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);
    const a = await tkd.deriveOwner('tessera.bottle', 'btl-aaaa');
    const b = await tkd.deriveOwner('tessera.bottle', 'btl-aaaa');
    expect(a.pubKeyHex).toBe(b.pubKeyHex);
  });

  test('different cellId → different pubkey', async () => {
    const { adapter } = makeMockIdentityAdapter();
    const tkd = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);
    const a = await tkd.deriveOwner('tessera.bottle', 'btl-aaaa');
    const b = await tkd.deriveOwner('tessera.bottle', 'btl-bbbb');
    expect(a.pubKeyHex).not.toBe(b.pubKeyHex);
  });

  test('different cellType (same cellId) → different pubkey', async () => {
    const { adapter } = makeMockIdentityAdapter();
    const tkd = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);
    const a = await tkd.deriveOwner('tessera.bottle', 'same-id');
    const b = await tkd.deriveOwner('tessera.case', 'same-id');
    expect(a.pubKeyHex).not.toBe(b.pubKeyHex);
  });

  test('different role (same cell) → different pubkey', async () => {
    const { adapter } = makeMockIdentityAdapter();
    const tkd = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);
    const owner = await tkd.deriveOwner('tessera.bottle', 'btl-aaaa');
    const retailer = await tkd.deriveForRole(
      'tessera.bottle',
      'btl-aaaa',
      'retailer',
    );
    expect(owner.pubKeyHex).not.toBe(retailer.pubKeyHex);
  });

  test('different operator root (same cell) → different pubkey', async () => {
    const { adapter } = makeMockIdentityAdapter();
    const altRoot =
      '03aa873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';
    const tkdA = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);
    const tkdB = new TesseraKeyDerivation(adapter, altRoot);
    const a = await tkdA.deriveOwner('tessera.bottle', 'btl-aaaa');
    const b = await tkdB.deriveOwner('tessera.bottle', 'btl-aaaa');
    expect(a.pubKeyHex).not.toBe(b.pubKeyHex);
  });
});

describe('tessera × L11 — realistic care-chain scenario', () => {
  test('producer derives a fresh owner pubkey for every bottle in a batch', async () => {
    const { adapter, calls } = makeMockIdentityAdapter();
    const tkd = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);

    // Producer bottles a 48-bottle case: each gets a derived owner.
    const owners: string[] = [];
    for (let i = 0; i < 48; i++) {
      const r = await tkd.deriveOwner('tessera.bottle', `btl-2024-09-A-${i.toString().padStart(3, '0')}`);
      owners.push(r.pubKeyHex);
    }

    // All 48 must be distinct (no collisions on adjacent cellIds)
    expect(new Set(owners).size).toBe(48);
    // 48 substrate calls — one per bottle, no caching at this layer
    expect(calls.length).toBe(48);
    // No registration calls were made (tessera doesn't register
    // these as hats — the only IdentityAdapter method called is
    // deriveSegmentPublicKey)
  });

  test('care-event derives handler + witness from the same cell — bound to roles', async () => {
    const { adapter, calls } = makeMockIdentityAdapter();
    const tkd = new TesseraKeyDerivation(adapter, OPERATOR_ROOT_PUB);
    const eventId = 'ce-transit-2026-06-02-001';
    const handler = await tkd.deriveHandler('tessera.care-event', eventId);
    const witness = await tkd.deriveForRole(
      'tessera.care-event',
      eventId,
      'witness',
    );
    expect(handler.pubKeyHex).not.toBe(witness.pubKeyHex);
    // Two substrate calls — one per role
    expect(calls.length).toBe(2);
    expect(calls[0].segment).toBe(`tessera.care-event/${eventId}/handler`);
    expect(calls[1].segment).toBe(`tessera.care-event/${eventId}/witness`);
  });
});

```
