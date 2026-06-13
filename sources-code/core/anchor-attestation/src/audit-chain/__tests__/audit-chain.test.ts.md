---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/audit-chain/__tests__/audit-chain.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.942436+00:00
---

# core/anchor-attestation/src/audit-chain/__tests__/audit-chain.test.ts

```ts
/**
 * Audit-chain tests — L12.
 *
 * Coverage:
 *   - happy path: 3-link signed chain verifies
 *   - KAT pin: a fixed master + canonical sequence produces a known
 *     entryHash chain (frozen wire format)
 *   - SEQ_NOT_MONOTONIC: chain not starting at 0
 *   - SEQ_GAP: skipping a seq mid-chain
 *   - GENESIS_PREV_HASH_NOT_ZERO: tampered genesis prevHash
 *   - PREV_HASH_MISMATCH: tampered intra-chain prevHash
 *   - CANONICAL_HASH_MISMATCH: tampered canonical bytes
 *   - ENTRY_HASH_MISMATCH: tampered entryHash bytes
 *   - LINK_PUB_KEY_MISMATCH: wrong master pub presented
 *   - INVALID_SIGNATURE: tampered signature bytes
 *   - ENTITY_ID_MISMATCH: split-brain chain
 *   - Empty input is ok
 *
 * Cross-language stability: AUDIT_CHAIN_MAGIC / VERSION asserted byte-equal.
 */

import { describe, expect, test } from 'bun:test';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import {
  AUDIT_CHAIN_MAGIC,
  AUDIT_CHAIN_VERSION,
  appendSignedEntry,
  computeEntryHash,
  genesisSignedEntry,
  verifyAuditChain,
  ZERO_HASH,
} from '../index.js';

const MASTER_PRIV_HEX =
  'e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';

function master() {
  return PrivateKey.fromString(MASTER_PRIV_HEX, 'hex');
}
function masterPubHex() {
  return master().toPublicKey().toDER('hex') as string;
}
function utf8(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}
function tampered(b: Uint8Array, byteIdx = 0, xor = 0x01): Uint8Array {
  const out = new Uint8Array(b);
  out[byteIdx] ^= xor;
  return out;
}

describe('L12 audit-chain — wire-format constants', () => {
  test('AUDIT_CHAIN_MAGIC is "L12AC" bytes', () => {
    expect(Buffer.from(AUDIT_CHAIN_MAGIC).toString('ascii')).toBe('L12AC');
  });
  test('AUDIT_CHAIN_VERSION = 1', () => {
    expect(AUDIT_CHAIN_VERSION).toBe(1);
  });
  test('ZERO_HASH is 32 zero bytes', () => {
    expect(ZERO_HASH.byteLength).toBe(32);
    expect(Array.from(ZERO_HASH).every((b) => b === 0)).toBe(true);
  });
});

describe('L12 audit-chain — happy path', () => {
  test('genesis + 2 links verifies end-to-end', () => {
    const m = master();
    const id = 'oddjobz:invoice:11111111-1111-4111-8111-111111111111';
    const g  = genesisSignedEntry(id, utf8('genesis-fact'), m);
    const e1 = appendSignedEntry(g.entry,  utf8('link-1-fact'), m);
    const e2 = appendSignedEntry(e1.entry, utf8('link-2-fact'), m);

    expect(g.entry.seq).toBe(0);
    expect(e1.entry.seq).toBe(1);
    expect(e2.entry.seq).toBe(2);
    expect(g.entry.entityId).toBe(id);

    // genesis prevHash must be zero32
    expect(Array.from(g.entry.prevHash).every((b) => b === 0)).toBe(true);
    // chain link prevHash matches prior entryHash
    expect(Buffer.from(e1.entry.prevHash).toString('hex')).toBe(
      Buffer.from(g.entry.entryHash).toString('hex'),
    );
    expect(Buffer.from(e2.entry.prevHash).toString('hex')).toBe(
      Buffer.from(e1.entry.entryHash).toString('hex'),
    );

    const result = verifyAuditChain({
      entries: [g, e1, e2],
      masterPubKeyHex: masterPubHex(),
    });
    expect(result.ok).toBe(true);
  });

  test('empty chain is ok', () => {
    const result = verifyAuditChain({
      entries: [],
      masterPubKeyHex: masterPubHex(),
    });
    expect(result.ok).toBe(true);
  });
});

describe('L12 audit-chain — KAT pin (wire format)', () => {
  test('fixed master + fixed canonical → known genesis entryHash', () => {
    // computeEntryHash is deterministic and version-stable. Any change to
    // the wire-format domain separator/magic/order will break this pin.
    const seq = 0;
    const prevHash = ZERO_HASH;
    // canonicalHash for SHA-256('hello-l12-genesis')
    const cryptoCanon = utf8('hello-l12-genesis');
    const canonicalHash = Uint8Array.from(
      // SHA-256 via @bsv/sdk — same primitive computeCanonicalHash uses
      // (don't re-import here; verify-side uses the same path).
      require('@bsv/sdk/primitives/Hash').sha256(Array.from(cryptoCanon)),
    );
    const got = computeEntryHash(seq, prevHash, canonicalHash);
    // KAT pin — recorded 2026-06-04 on first ship of L12. Any change to
    // the wire-format (magic, version, field order, u32be encoding) will
    // change this hex and trip the gate.
    const want =
      'cfe4e70e7f4267067a2c9686a733d43955494b9e9c2c41c275895022511dd938';
    expect(got.byteLength).toBe(32);
    expect(Buffer.from(got).toString('hex')).toBe(want);
  });
});

describe('L12 audit-chain — fail-closed', () => {
  test('SEQ_NOT_MONOTONIC: first entry seq != 0', () => {
    const m = master();
    const g  = genesisSignedEntry('x', utf8('a'), m);
    const e1 = appendSignedEntry(g.entry, utf8('b'), m);
    const result = verifyAuditChain({
      entries: [e1], // submit only seq=1 as first
      masterPubKeyHex: masterPubHex(),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('SEQ_NOT_MONOTONIC');
      expect(result.failedAtIndex).toBe(0);
    }
  });

  test('SEQ_GAP: missing middle link', () => {
    const m = master();
    const g  = genesisSignedEntry('x', utf8('a'), m);
    const e1 = appendSignedEntry(g.entry, utf8('b'), m);
    const e2 = appendSignedEntry(e1.entry, utf8('c'), m);
    const result = verifyAuditChain({
      entries: [g, e2], // skip e1
      masterPubKeyHex: masterPubHex(),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('SEQ_GAP');
    }
  });

  test('GENESIS_PREV_HASH_NOT_ZERO: tampered genesis prevHash', () => {
    const m = master();
    const g = genesisSignedEntry('x', utf8('a'), m);
    const badG = {
      ...g,
      entry: { ...g.entry, prevHash: tampered(g.entry.prevHash) },
    };
    const result = verifyAuditChain({
      entries: [badG],
      masterPubKeyHex: masterPubHex(),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('GENESIS_PREV_HASH_NOT_ZERO');
    }
  });

  test('PREV_HASH_MISMATCH: tampered intra-chain prevHash', () => {
    const m = master();
    const g  = genesisSignedEntry('x', utf8('a'), m);
    const e1 = appendSignedEntry(g.entry, utf8('b'), m);
    const badE1 = {
      ...e1,
      entry: { ...e1.entry, prevHash: tampered(e1.entry.prevHash) },
    };
    const result = verifyAuditChain({
      entries: [g, badE1],
      masterPubKeyHex: masterPubHex(),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('PREV_HASH_MISMATCH');
    }
  });

  test('CANONICAL_HASH_MISMATCH: canonical bytes do not produce canonicalHash', () => {
    const m = master();
    const g = genesisSignedEntry('x', utf8('a'), m);
    const badG = {
      ...g,
      entry: { ...g.entry, canonical: utf8('different bytes') },
    };
    const result = verifyAuditChain({
      entries: [badG],
      masterPubKeyHex: masterPubHex(),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('CANONICAL_HASH_MISMATCH');
    }
  });

  test('ENTRY_HASH_MISMATCH: entryHash does not recompute', () => {
    const m = master();
    const g = genesisSignedEntry('x', utf8('a'), m);
    const badG = {
      ...g,
      entry: { ...g.entry, entryHash: tampered(g.entry.entryHash) },
    };
    const result = verifyAuditChain({
      entries: [badG],
      masterPubKeyHex: masterPubHex(),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('ENTRY_HASH_MISMATCH');
    }
  });

  test('LINK_PUB_KEY_MISMATCH: wrong master pub', () => {
    const m = master();
    const g = genesisSignedEntry('x', utf8('a'), m);
    const wrongMasterPub = PrivateKey.fromString(
      '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
      'hex',
    )
      .toPublicKey()
      .toDER('hex') as string;
    const result = verifyAuditChain({
      entries: [g],
      masterPubKeyHex: wrongMasterPub,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('LINK_PUB_KEY_MISMATCH');
    }
  });

  test('INVALID_SIGNATURE: tampered signature bytes', () => {
    const m = master();
    const g = genesisSignedEntry('x', utf8('a'), m);
    // Tamper the signature near the end — DER parsing may still succeed
    // depending on the byte, but the verify will reject.
    const badSig = new Uint8Array(g.signature);
    badSig[badSig.length - 1] ^= 0x01;
    const badG = { ...g, signature: badSig };
    const result = verifyAuditChain({
      entries: [badG],
      masterPubKeyHex: masterPubHex(),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('INVALID_SIGNATURE');
    }
  });

  test('ENTITY_ID_MISMATCH: split-brain chain', () => {
    const m = master();
    const g  = genesisSignedEntry('x', utf8('a'), m);
    const e1 = appendSignedEntry(g.entry, utf8('b'), m);
    const badE1 = { ...e1, entry: { ...e1.entry, entityId: 'y' } };
    const result = verifyAuditChain({
      entries: [g, badE1],
      masterPubKeyHex: masterPubHex(),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('ENTITY_ID_MISMATCH');
    }
  });
});

describe('L12 audit-chain — custom LinkSegmentDeriver', () => {
  test('signer + verifier use the same segmenter → ok', () => {
    const m = master();
    const segmenter = (id: string, seq: number) =>
      `oddjobz/${id}/audit/${seq}`;
    const g = genesisSignedEntry('inv-A', utf8('a'), m, segmenter);
    const e1 = appendSignedEntry(g.entry, utf8('b'), m, segmenter);
    const result = verifyAuditChain({
      entries: [g, e1],
      masterPubKeyHex: masterPubHex(),
      segmenter,
    });
    expect(result.ok).toBe(true);
  });

  test('verifier with WRONG segmenter rejects at LINK_PUB_KEY_MISMATCH', () => {
    const m = master();
    const signerSegmenter = (id: string, seq: number) => `path-A/${id}/${seq}`;
    const wrongSegmenter = (id: string, seq: number) => `path-B/${id}/${seq}`;
    const g = genesisSignedEntry('inv-A', utf8('a'), m, signerSegmenter);
    const result = verifyAuditChain({
      entries: [g],
      masterPubKeyHex: masterPubHex(),
      segmenter: wrongSegmenter,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('LINK_PUB_KEY_MISMATCH');
    }
  });
});

```
