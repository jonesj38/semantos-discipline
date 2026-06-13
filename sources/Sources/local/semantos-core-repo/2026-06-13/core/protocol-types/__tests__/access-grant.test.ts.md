---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/access-grant.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.860316+00:00
---

# core/protocol-types/__tests__/access-grant.test.ts

```ts
/**
 * access-grant — DAM wire-format + challenge-digest tests.
 *
 * The load-bearing test is the cross-impl digest vector: `accessChallengeDigest`
 * here MUST equal the Zig `accessChallengeDigest` (access_grant_context.zig) for
 * the same inputs, or a grantee's edge-key signature never verifies on the real
 * 2-PDA. The expected hex below is captured FROM the Zig impl and pinned on the
 * Zig side too (access_grant_context.zig conformance test) — change one, both
 * must change.
 */

import { describe, expect, test } from 'bun:test';
import { CELL_SIZE, Linearity } from '../src/constants';
import { deserializeCellHeader } from '../src/cell-header';
import {
  ACCESS_GRANT_TYPE_HASH,
  VERIFY_INTENT_TYPE_HASH,
  VERIFY_RESULT_TYPE_HASH,
  CAP_DATA_ACCESS,
  GRANT_PAYLOAD_LEN,
  encodeAccessGrantPayload,
  decodeAccessGrantPayload,
  encodeAccessGrantCell,
  accessGrantCellHash,
  encodeVerifyIntentPayload,
  decodeVerifyIntentPayload,
  encodeVerifyIntentCell,
  buildVerifyIntentCell,
  encodeVerifyResultPayload,
  decodeVerifyResultPayload,
  encodeVerifyResultCell,
  accessChallengeDigest,
} from '../src/bsv/access-grant';

function fromHex(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}
function toHex(b: Uint8Array): string {
  return Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
}
function bytesEq(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

describe('access.grant payload', () => {
  test('round-trips capability, pubkey, content hash, expiry', () => {
    const g = {
      granteePubkey: new Uint8Array(33).fill(0x02),
      contentHash: new Uint8Array(32).fill(0xcc),
      expiry: 1_900_000_000n,
    };
    const p = encodeAccessGrantPayload(g);
    expect(p.length).toBe(GRANT_PAYLOAD_LEN);
    expect(p[0]).toBe(CAP_DATA_ACCESS);
    const d = decodeAccessGrantPayload(p);
    expect(d.capability).toBe(CAP_DATA_ACCESS);
    expect(bytesEq(d.granteePubkey, g.granteePubkey)).toBe(true);
    expect(bytesEq(d.contentHash, g.contentHash)).toBe(true);
    expect(d.expiry).toBe(g.expiry);
  });

  test('cell carries the access.grant typeHash + LINEAR linearity', () => {
    const cell = encodeAccessGrantCell({
      granteePubkey: new Uint8Array(33).fill(0x02),
      contentHash: new Uint8Array(32).fill(0xcc),
      expiry: 1_900_000_000n,
    });
    expect(cell.length).toBe(CELL_SIZE);
    const h = deserializeCellHeader(cell);
    expect(bytesEq(h.typeHash, ACCESS_GRANT_TYPE_HASH)).toBe(true);
    expect(h.linearity).toBe(Linearity.LINEAR);
    // payload decodes off the full cell (bytes 256..)
    const d = decodeAccessGrantPayload(cell.slice(256));
    expect(d.capability).toBe(CAP_DATA_ACCESS);
  });

  test('cell hash is sha256 of the full 1024-byte cell', () => {
    const cell = encodeAccessGrantCell({
      granteePubkey: new Uint8Array(33).fill(0x03),
      contentHash: new Uint8Array(32).fill(0xab),
      expiry: 42n,
    });
    expect(accessGrantCellHash(cell).length).toBe(32);
    // deterministic
    expect(bytesEq(accessGrantCellHash(cell), accessGrantCellHash(cell))).toBe(true);
  });
});

describe('access.grant.verify.intent payload', () => {
  test('round-trips grant hash + variable-length signature (u16 LE len)', () => {
    const vi = {
      grantHash: new Uint8Array(32).fill(0x11),
      signature: new Uint8Array(71).fill(0x30), // DER ‖ flag, ~71B
    };
    const p = encodeVerifyIntentPayload(vi);
    // sig_len at offset 32 is little-endian u16
    expect(p[32]! | (p[33]! << 8)).toBe(71);
    const d = decodeVerifyIntentPayload(p);
    expect(bytesEq(d.grantHash, vi.grantHash)).toBe(true);
    expect(bytesEq(d.signature, vi.signature)).toBe(true);
  });

  test('buildVerifyIntentCell carries the verify-intent typeHash', () => {
    const cell = buildVerifyIntentCell({
      grantHash: new Uint8Array(32).fill(0x11),
      signature: new Uint8Array(70).fill(0x30),
    });
    const h = deserializeCellHeader(cell);
    expect(bytesEq(h.typeHash, VERIFY_INTENT_TYPE_HASH)).toBe(true);
    const d = decodeVerifyIntentPayload(cell.slice(256));
    expect(d.signature.length).toBe(70);
  });
});

describe('access.grant.verify.result payload', () => {
  test('round-trips ok + content hash', () => {
    const r = { ok: true, contentHash: new Uint8Array(32).fill(0x7e) };
    const p = encodeVerifyResultPayload(r);
    expect(p[0]).toBe(1);
    const d = decodeVerifyResultPayload(p);
    expect(d.ok).toBe(true);
    expect(d.contentHash && bytesEq(d.contentHash, r.contentHash)).toBe(true);
  });

  test('result cell carries the verify-result typeHash', () => {
    const cell = encodeVerifyResultCell({ ok: true, contentHash: new Uint8Array(32).fill(0x7e) });
    const h = deserializeCellHeader(cell);
    expect(bytesEq(h.typeHash, VERIFY_RESULT_TYPE_HASH)).toBe(true);
  });
});

describe('accessChallengeDigest — cross-impl vector vs Zig', () => {
  // Captured from the Zig accessChallengeDigest([0x11]*32, [0x02]*33) — see
  // access_grant_context.zig's conformance test (same hex pinned on both sides).
  const ZIG_VECTOR = 'ac9b3eb15ec0447f21bb2058c591776555a5eacb187b51c47a32bdb6b1f3d4ae';

  test('matches the Zig digest byte-for-byte', () => {
    const d = accessChallengeDigest(new Uint8Array(32).fill(0x11), new Uint8Array(33).fill(0x02));
    expect(toHex(d)).toBe(ZIG_VECTOR);
  });

  test('is bound to the grant hash AND the grantee pubkey (changes with either)', () => {
    const base = accessChallengeDigest(new Uint8Array(32).fill(0x11), new Uint8Array(33).fill(0x02));
    const diffGrant = accessChallengeDigest(new Uint8Array(32).fill(0x22), new Uint8Array(33).fill(0x02));
    const diffKey = accessChallengeDigest(new Uint8Array(32).fill(0x11), new Uint8Array(33).fill(0x03));
    expect(bytesEq(base, diffGrant)).toBe(false);
    expect(bytesEq(base, diffKey)).toBe(false);
    expect(base.length).toBe(32);
  });
});

```
