---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/identity-derive-segment-public-key.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.854400+00:00
---

# core/protocol-types/__tests__/identity-derive-segment-public-key.test.ts

```ts
/**
 * IdentityAdapter.deriveSegmentPublicKey — substrate-side L11 port tests.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L11 (substrate-side adapter
 * port that unblocks tessera + similar greenfield-discipline cartridges
 * from doing L11-shaped key derivation without violating their
 * consumption gates).
 *
 * Covers:
 *   1. Stub conformance — structural contract (66-char hex, 02/03 prefix,
 *      deterministic, fail-closed on bad input).
 *   2. Real (LocalIdentityAdapter) conformance — same structural shape.
 *   3. Real impl PARITY with the L11 deriveSegmentPub primitive — the
 *      adapter doesn't add any extra hashing; output is byte-equal to
 *      vendor-sdk's deriveSegmentPub.
 *   4. Cartridge use-case smoke: a tessera-shaped caller deriving
 *      per-cell keys from an operator root pubkey.
 */

import { describe, expect, test } from 'bun:test';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import { sha256 } from '@bsv/sdk/primitives/Hash';
import { deriveScalarPub, deriveDomainSegmentPub } from '@plexus/vendor-sdk';
import { StubIdentityAdapter } from '../src/adapters/stub-identity-adapter';
import { LocalIdentityAdapter } from '../src/identity-adapters/local/local-identity-adapter';

const PARENT_PRIV_HEX =
  'e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';

function parentPubHex(): string {
  const priv = PrivateKey.fromString(PARENT_PRIV_HEX, 'hex');
  return priv.toPublicKey().toDER('hex') as string;
}

describe('IdentityAdapter.deriveSegmentPublicKey — StubIdentityAdapter', () => {
  test('returns 66-char hex starting with 02 or 03', async () => {
    const stub = new StubIdentityAdapter({ debugLogging: false });
    const result = await stub.deriveSegmentPublicKey(
      parentPubHex(),
      'tessera/bottle/btl-11111111/owner',
    );
    expect(result.childPubKeyHex.length).toBe(66);
    const prefix = result.childPubKeyHex.slice(0, 2);
    expect(['02', '03']).toContain(prefix);
    expect(/^[0-9a-f]{66}$/.test(result.childPubKeyHex)).toBe(true);
  });

  test('deterministic — same input → same output', async () => {
    const stub = new StubIdentityAdapter({ debugLogging: false });
    const a = await stub.deriveSegmentPublicKey(parentPubHex(), 'segment-x');
    const b = await stub.deriveSegmentPublicKey(parentPubHex(), 'segment-x');
    expect(a.childPubKeyHex).toBe(b.childPubKeyHex);
  });

  test('different segments → different outputs', async () => {
    const stub = new StubIdentityAdapter({ debugLogging: false });
    const a = await stub.deriveSegmentPublicKey(parentPubHex(), 'segment-x');
    const b = await stub.deriveSegmentPublicKey(parentPubHex(), 'segment-y');
    expect(a.childPubKeyHex).not.toBe(b.childPubKeyHex);
  });

  test('different parents → different outputs', async () => {
    const stub = new StubIdentityAdapter({ debugLogging: false });
    const altParentPriv = PrivateKey.fromString(
      'aa873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262',
      'hex',
    );
    const altParentPub = altParentPriv.toPublicKey().toDER('hex') as string;
    const a = await stub.deriveSegmentPublicKey(parentPubHex(), 'shared-segment');
    const b = await stub.deriveSegmentPublicKey(altParentPub, 'shared-segment');
    expect(a.childPubKeyHex).not.toBe(b.childPubKeyHex);
  });

  test('Uint8Array segment ≡ utf-8 string segment', async () => {
    const stub = new StubIdentityAdapter({ debugLogging: false });
    const segStr = 'tessera/care-event/handler';
    const segBytes = new TextEncoder().encode(segStr);
    const a = await stub.deriveSegmentPublicKey(parentPubHex(), segStr);
    const b = await stub.deriveSegmentPublicKey(parentPubHex(), segBytes);
    expect(a.childPubKeyHex).toBe(b.childPubKeyHex);
  });

  test('rejects non-66-char hex parent', async () => {
    const stub = new StubIdentityAdapter({ debugLogging: false });
    await expect(stub.deriveSegmentPublicKey('too-short', 'x')).rejects.toThrow();
    await expect(
      stub.deriveSegmentPublicKey('A'.repeat(66), 'x'), // uppercase → rejected
    ).rejects.toThrow();
    await expect(
      stub.deriveSegmentPublicKey('x'.repeat(65), 'x'),
    ).rejects.toThrow();
  });
});

describe('IdentityAdapter.deriveSegmentPublicKey — LocalIdentityAdapter (real crypto)', () => {
  test('returns 66-char compressed hex', async () => {
    const local = new LocalIdentityAdapter();
    const result = await local.deriveSegmentPublicKey(
      parentPubHex(),
      'tessera/bottle/btl-11111111/owner',
    );
    expect(result.childPubKeyHex.length).toBe(66);
    expect(/^[0-9a-f]{66}$/.test(result.childPubKeyHex)).toBe(true);
    expect(['02', '03']).toContain(result.childPubKeyHex.slice(0, 2));
  });

  test('deterministic', async () => {
    const local = new LocalIdentityAdapter();
    const a = await local.deriveSegmentPublicKey(parentPubHex(), 'segment-x');
    const b = await local.deriveSegmentPublicKey(parentPubHex(), 'segment-x');
    expect(a.childPubKeyHex).toBe(b.childPubKeyHex);
  });

  test('PARITY: adapter output ≡ deriveSegmentPub(parentPub, sha256(segment.utf8)) directly', async () => {
    // This is the structural claim: the adapter does NOT add any extra
    // hashing or transformation beyond what L11 deriveSegmentPub does
    // with a hashed segment. A real BSV-aware verifier that holds the
    // parent's private key can compute the same child PRIVATE key via
    // deriveSegment(priv, segment).toPublicKey() — proven byte-equal
    // in vendor-sdk/derive-segment tests.
    const local = new LocalIdentityAdapter();
    const segment = 'tessera/bottle/owner/seq-1';
    const fromAdapter = await local.deriveSegmentPublicKey(parentPubHex(), segment);
    const PublicKey = (await import('@bsv/sdk/primitives/PublicKey')).default;
    const parentPub = PublicKey.fromString(parentPubHex());
    const scalarBytes = sha256(Array.from(new TextEncoder().encode(segment)));
    const fromPrimitive = deriveScalarPub(parentPub, scalarBytes);
    expect(fromAdapter.childPubKeyHex).toBe(fromPrimitive.toDER('hex') as string);
  });

  test('different segments → different real-crypto outputs', async () => {
    const local = new LocalIdentityAdapter();
    const a = await local.deriveSegmentPublicKey(parentPubHex(), 'segment-x');
    const b = await local.deriveSegmentPublicKey(parentPubHex(), 'segment-y');
    expect(a.childPubKeyHex).not.toBe(b.childPubKeyHex);
  });

  test('rejects bad parent format', async () => {
    const local = new LocalIdentityAdapter();
    await expect(
      local.deriveSegmentPublicKey('bad-hex', 'x'),
    ).rejects.toThrow();
  });
});

describe('Cartridge use-case smoke (tessera-shaped consumer)', () => {
  test('greenfield cartridge derives per-cell owner pubkeys without registering each', async () => {
    // What a tessera consumer would do:
    //   - Hold an operator-root pubkey hex (received during setup)
    //   - For each new tessera.bottle cell, derive a child pubkey
    //     using "tessera/bottle/<cellId>/owner" as the segment
    //   - Cell's owner field is the derived pubkey hex; never
    //     registered, never round-tripped through cert/hat surface
    //   - The cartridge never imports @bsv/sdk or @plexus/vendor-sdk
    //     directly — it only ever uses IdentityAdapter
    const adapter = new LocalIdentityAdapter();
    const operatorRoot = parentPubHex();

    const ownerForBottle1 = await adapter.deriveSegmentPublicKey(
      operatorRoot,
      'tessera/bottle/btl-aaaa/owner',
    );
    const ownerForBottle2 = await adapter.deriveSegmentPublicKey(
      operatorRoot,
      'tessera/bottle/btl-bbbb/owner',
    );
    const ownerForCareEvent = await adapter.deriveSegmentPublicKey(
      operatorRoot,
      'tessera/care-event/ce-cccc/handler',
    );

    expect(ownerForBottle1.childPubKeyHex).not.toBe(ownerForBottle2.childPubKeyHex);
    expect(ownerForBottle1.childPubKeyHex).not.toBe(ownerForCareEvent.childPubKeyHex);
    // All three are valid compressed pubkeys
    for (const result of [ownerForBottle1, ownerForBottle2, ownerForCareEvent]) {
      expect(/^0[23][0-9a-f]{64}$/.test(result.childPubKeyHex)).toBe(true);
    }
  });
});

describe('IdentityAdapter.deriveDomainSegmentPublicKey — L11.5 (kdf-v3)', () => {
  const FLAG = 0x00010400; // tessera page base, used as a representative flag

  test('Local — PARITY with deriveDomainSegmentPub(parentPub, flag, segment) (guards arg order)', async () => {
    const local = new LocalIdentityAdapter();
    const segment = 'tessera.bottle/btl-aaaa/owner';
    const fromAdapter = await local.deriveDomainSegmentPublicKey(parentPubHex(), FLAG, segment);
    const PublicKey = (await import('@bsv/sdk/primitives/PublicKey')).default;
    const parentPub = PublicKey.fromString(parentPubHex());
    const fromPrimitive = deriveDomainSegmentPub(parentPub, FLAG, segment);
    expect(fromAdapter.childPubKeyHex).toBe(fromPrimitive.toDER('hex') as string);
  });

  test('Local — domain-bound: differs from the v2 (flagless) deriveSegmentPublicKey', async () => {
    const local = new LocalIdentityAdapter();
    const segment = 'tessera.bottle/btl-aaaa/owner';
    const v2 = await local.deriveSegmentPublicKey(parentPubHex(), segment);
    const v3 = await local.deriveDomainSegmentPublicKey(parentPubHex(), FLAG, segment);
    expect(v3.childPubKeyHex).not.toBe(v2.childPubKeyHex);
  });

  test('Local — flag-sensitive: same segment, different flag → different pubkey', async () => {
    const local = new LocalIdentityAdapter();
    const seg = 'same-segment';
    const a = await local.deriveDomainSegmentPublicKey(parentPubHex(), 1, seg);
    const b = await local.deriveDomainSegmentPublicKey(parentPubHex(), 2, seg);
    expect(a.childPubKeyHex).not.toBe(b.childPubKeyHex);
  });

  test('Local — rejects non-u32 domainFlag', async () => {
    const local = new LocalIdentityAdapter();
    await expect(local.deriveDomainSegmentPublicKey(parentPubHex(), -1, 'x')).rejects.toThrow();
    await expect(
      local.deriveDomainSegmentPublicKey(parentPubHex(), 0x1_0000_0000, 'x'),
    ).rejects.toThrow();
  });

  test('Stub — deterministic + flag-sensitive + structural shape', async () => {
    const stub = new StubIdentityAdapter({ debugLogging: false });
    const a = await stub.deriveDomainSegmentPublicKey(parentPubHex(), FLAG, 'seg');
    const b = await stub.deriveDomainSegmentPublicKey(parentPubHex(), FLAG, 'seg');
    const c = await stub.deriveDomainSegmentPublicKey(parentPubHex(), FLAG + 1, 'seg');
    expect(a.childPubKeyHex).toBe(b.childPubKeyHex);
    expect(a.childPubKeyHex).not.toBe(c.childPubKeyHex);
    expect(/^0[23][0-9a-f]{64}$/.test(a.childPubKeyHex)).toBe(true);
  });
});

```
