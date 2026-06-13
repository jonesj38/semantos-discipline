---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/cell-data-carriers.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.854677+00:00
---

# core/protocol-types/__tests__/cell-data-carriers.test.ts

```ts
/**
 * Cell data-carrier variants tests.
 *
 * CW Lift L13 (docs/canon/cw-lift-matrix.yml).
 *
 * Pins the wire format for all three carrier shapes (pushdrop,
 * OP_FALSE OP_IF, OP_DROP+P2PKH) and asserts round-trip + cross-shape
 * discrimination. Wire-format drift between writer and reader is silent
 * and catastrophic, so this test fixes the canonical byte layout of
 * each variant.
 *
 * Reference: docs/prd/CW-LIFT-ROADMAP.md §2.
 */
import { describe, expect, test } from 'bun:test';
import { CELL_SIZE } from '../src/constants';
import {
  CANONICAL_CELL_OP_DROP_P2PKH_SIZE,
  CANONICAL_CELL_OP_FALSE_IF_SIZE,
  CANONICAL_CELL_PUSHDROP_SIZE,
  buildOpDropP2pkhCarrierScript,
  buildOpFalseIfCarrierScript,
  buildPushdropLockingScript,
  detectDataCarrierShape,
  parseDataCarrier,
  parseOpDropP2pkhCarrierScript,
  parseOpFalseIfCarrierScript,
  parsePushdropLockingScript,
  PKH_SIZE,
  OP_CHECKSIG,
  OP_DROP,
  OP_DUP,
  OP_ENDIF,
  OP_EQUALVERIFY,
  OP_FALSE,
  OP_HASH160,
  OP_IF,
} from '../src/cell-data-carriers';
import { COMPRESSED_PUBKEY_SIZE } from '../src/cell-pushdrop';

function bytes(n: number, fill = 0): Uint8Array {
  const b = new Uint8Array(n);
  if (fill) b.fill(fill);
  return b;
}

function compressedPubkey(): Uint8Array {
  const pk = new Uint8Array(COMPRESSED_PUBKEY_SIZE);
  pk[0] = 0x02; // 0x02 or 0x03 — compressed marker
  for (let i = 1; i < COMPRESSED_PUBKEY_SIZE; i++) pk[i] = i;
  return pk;
}

function pkh(): Uint8Array {
  const h = new Uint8Array(PKH_SIZE);
  for (let i = 0; i < PKH_SIZE; i++) h[i] = 0x10 + i;
  return h;
}

describe('CW Lift L13: cell-data-carriers — three carrier shapes', () => {
  describe('(a) pushdrop carrier (re-exported, unchanged)', () => {
    test('round-trips through buildPushdropLockingScript + parsePushdropLockingScript', () => {
      const cell = bytes(CELL_SIZE, 0xAA);
      const pk = compressedPubkey();
      const script = buildPushdropLockingScript(cell, pk);
      expect(script.length).toBe(CANONICAL_CELL_PUSHDROP_SIZE);
      const parsed = parsePushdropLockingScript(script);
      expect(parsed.cellBytes).toEqual(cell);
      expect(parsed.pubkey).toEqual(pk);
    });

    test('canonical size constant = 1063 bytes', () => {
      expect(CANONICAL_CELL_PUSHDROP_SIZE).toBe(1063);
    });
  });

  describe('(b) OP_FALSE OP_IF carrier', () => {
    test('produces the expected byte prefix + suffix', () => {
      const cell = bytes(CELL_SIZE, 0xBB);
      const pk = compressedPubkey();
      const script = buildOpFalseIfCarrierScript(cell, pk);
      // Prefix: OP_FALSE OP_IF
      expect(script[0]).toBe(OP_FALSE);
      expect(script[1]).toBe(OP_IF);
      // Pushdata2 + LE 0x0400 (1024)
      expect(script[2]).toBe(0x4d); // OP_PUSHDATA2
      expect(script[3]).toBe(0x00);
      expect(script[4]).toBe(0x04);
      // After cell: OP_ENDIF, then push of pubkey, then OP_CHECKSIG
      const endifOff = 5 + CELL_SIZE;
      expect(script[endifOff]).toBe(OP_ENDIF);
      expect(script[endifOff + 1]).toBe(0x21); // push 33 bytes
      // Last byte is OP_CHECKSIG
      expect(script[script.length - 1]).toBe(OP_CHECKSIG);
      expect(script.length).toBe(CANONICAL_CELL_OP_FALSE_IF_SIZE);
    });

    test('canonical size constant = 1065 bytes (2 more than pushdrop: OP_FALSE+OP_IF+OP_ENDIF − removed OP_DROP)', () => {
      // pushdrop has OP_DROP (1 byte); op_false_if has OP_FALSE+OP_IF+OP_ENDIF (3 bytes) — net +2
      expect(CANONICAL_CELL_OP_FALSE_IF_SIZE).toBe(CANONICAL_CELL_PUSHDROP_SIZE + 2);
      expect(CANONICAL_CELL_OP_FALSE_IF_SIZE).toBe(1065);
    });

    test('round-trips through build + parse', () => {
      const cell = bytes(CELL_SIZE, 0xCC);
      const pk = compressedPubkey();
      const script = buildOpFalseIfCarrierScript(cell, pk);
      const parsed = parseOpFalseIfCarrierScript(script);
      expect(parsed.cellBytes).toEqual(cell);
      expect(parsed.pubkey).toEqual(pk);
    });

    test('rejects empty cell + wrong pubkey size', () => {
      expect(() => buildOpFalseIfCarrierScript(new Uint8Array(0), compressedPubkey())).toThrow();
      expect(() => buildOpFalseIfCarrierScript(bytes(100), new Uint8Array(32))).toThrow();
    });

    test('parser rejects script that does not start with OP_FALSE OP_IF', () => {
      const fake = new Uint8Array([OP_DROP, 0x21, 0xAA, 0xAC]);
      expect(() => parseOpFalseIfCarrierScript(fake)).toThrow();
    });
  });

  describe('(c) OP_DROP + P2PKH carrier', () => {
    test('produces the expected byte layout', () => {
      const cell = bytes(CELL_SIZE, 0xDD);
      const h = pkh();
      const script = buildOpDropP2pkhCarrierScript(cell, h);
      // Pushdata2 + LE 0x0400 (1024)
      expect(script[0]).toBe(0x4d); // OP_PUSHDATA2
      expect(script[1]).toBe(0x00);
      expect(script[2]).toBe(0x04);
      // After cell: OP_DROP OP_DUP OP_HASH160 0x14 <20> OP_EQUALVERIFY OP_CHECKSIG
      const tailOff = 3 + CELL_SIZE;
      expect(script[tailOff + 0]).toBe(OP_DROP);
      expect(script[tailOff + 1]).toBe(OP_DUP);
      expect(script[tailOff + 2]).toBe(OP_HASH160);
      expect(script[tailOff + 3]).toBe(0x14); // direct push of 20 bytes
      // pkh occupies tailOff+4 .. tailOff+24 (exclusive)
      for (let i = 0; i < 20; i++) {
        expect(script[tailOff + 4 + i]).toBe(h[i]);
      }
      expect(script[tailOff + 24]).toBe(OP_EQUALVERIFY);
      expect(script[tailOff + 25]).toBe(OP_CHECKSIG);
      expect(script.length).toBe(tailOff + 26);
      expect(script.length).toBe(CANONICAL_CELL_OP_DROP_P2PKH_SIZE);
    });

    test('canonical size constant = 1053 bytes', () => {
      // 3 (PUSHDATA2 prefix) + 1024 (cell) + 1 (OP_DROP) + 1 (OP_DUP) + 1 (OP_HASH160) + 1 (push20) + 20 (pkh) + 1 (OP_EQUALVERIFY) + 1 (OP_CHECKSIG) = 1053
      expect(CANONICAL_CELL_OP_DROP_P2PKH_SIZE).toBe(1053);
    });

    test('round-trips through build + parse', () => {
      const cell = bytes(CELL_SIZE, 0xEE);
      const h = pkh();
      const script = buildOpDropP2pkhCarrierScript(cell, h);
      const parsed = parseOpDropP2pkhCarrierScript(script);
      expect(parsed.cellBytes).toEqual(cell);
      expect(parsed.pkh).toEqual(h);
    });

    test('rejects wrong pkh size', () => {
      expect(() => buildOpDropP2pkhCarrierScript(bytes(100), new Uint8Array(19))).toThrow();
      expect(() => buildOpDropP2pkhCarrierScript(bytes(100), new Uint8Array(21))).toThrow();
      expect(() => buildOpDropP2pkhCarrierScript(bytes(100), new Uint8Array(33))).toThrow();
    });
  });

  describe('discriminator + universal parser', () => {
    test('detectDataCarrierShape correctly identifies all three shapes', () => {
      const cell = bytes(CELL_SIZE);
      const pk = compressedPubkey();
      const h = pkh();
      expect(detectDataCarrierShape(buildPushdropLockingScript(cell, pk))).toBe('pushdrop');
      expect(detectDataCarrierShape(buildOpFalseIfCarrierScript(cell, pk))).toBe('op_false_op_if');
      expect(detectDataCarrierShape(buildOpDropP2pkhCarrierScript(cell, h))).toBe('op_drop_p2pkh');
    });

    test('detectDataCarrierShape returns null for non-carrier scripts', () => {
      expect(detectDataCarrierShape(new Uint8Array([0x6a, 0xAB, 0xCD, 0xEF]))).toBe(null); // OP_RETURN
      expect(detectDataCarrierShape(new Uint8Array([0xAC]))).toBe(null); // bare OP_CHECKSIG
      expect(detectDataCarrierShape(new Uint8Array(0))).toBe(null);
    });

    test('parseDataCarrier round-trips all three shapes via the universal entry point', () => {
      const cell = bytes(CELL_SIZE, 0x11);
      const pk = compressedPubkey();
      const h = pkh();

      const a = parseDataCarrier(buildPushdropLockingScript(cell, pk));
      expect(a.shape).toBe('pushdrop');
      if (a.shape === 'pushdrop') {
        expect(a.cellBytes).toEqual(cell);
        expect(a.pubkey).toEqual(pk);
      }

      const b = parseDataCarrier(buildOpFalseIfCarrierScript(cell, pk));
      expect(b.shape).toBe('op_false_op_if');
      if (b.shape === 'op_false_op_if') {
        expect(b.cellBytes).toEqual(cell);
        expect(b.pubkey).toEqual(pk);
      }

      const c = parseDataCarrier(buildOpDropP2pkhCarrierScript(cell, h));
      expect(c.shape).toBe('op_drop_p2pkh');
      if (c.shape === 'op_drop_p2pkh') {
        expect(c.cellBytes).toEqual(cell);
        expect(c.pkh).toEqual(h);
      }
    });

    test('parseDataCarrier throws on unknown shape', () => {
      // OP_RETURN data carrier — semantos does NOT use this.
      expect(() => parseDataCarrier(new Uint8Array([0x6a, 0x04, 0xAA, 0xBB, 0xCC, 0xDD]))).toThrow();
    });
  });

  describe('all three carriers commit the same cell bytes (BSV-only invariant)', () => {
    test('cell is recoverable identically from each carrier shape', () => {
      const cell = bytes(CELL_SIZE);
      for (let i = 0; i < CELL_SIZE; i++) cell[i] = (i * 37) & 0xff;
      const pk = compressedPubkey();
      const h = pkh();

      const fromA = parseDataCarrier(buildPushdropLockingScript(cell, pk));
      const fromB = parseDataCarrier(buildOpFalseIfCarrierScript(cell, pk));
      const fromC = parseDataCarrier(buildOpDropP2pkhCarrierScript(cell, h));

      expect(fromA.cellBytes).toEqual(cell);
      expect(fromB.cellBytes).toEqual(cell);
      expect(fromC.cellBytes).toEqual(cell);
    });

    test('no carrier shape contains OP_RETURN (BSV-only / L14 invariant)', () => {
      const cell = bytes(CELL_SIZE);
      const pk = compressedPubkey();
      const h = pkh();
      const scripts = [
        buildPushdropLockingScript(cell, pk),
        buildOpFalseIfCarrierScript(cell, pk),
        buildOpDropP2pkhCarrierScript(cell, h),
      ];
      for (const s of scripts) {
        // OP_RETURN is 0x6a; cell payload may legitimately contain 0x6a,
        // so only check that the script doesn't START with OP_RETURN (which
        // is how a data-carrier-style output would be discriminated). Per
        // BSV semantics, an OP_RETURN at script start unconditionally
        // unspendable-marks the output.
        expect(s[0]).not.toBe(0x6a);
      }
    });
  });
});

```
