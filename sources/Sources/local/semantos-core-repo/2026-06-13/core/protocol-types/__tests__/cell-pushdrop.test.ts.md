---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/cell-pushdrop.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.856452+00:00
---

# core/protocol-types/__tests__/cell-pushdrop.test.ts

```ts
/**
 * Cell-pushdrop codec tests.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §3.1.
 *
 * Pins the locking-script wire format. The pushdrop pattern is consumed
 * by both the on-chain anchorer (which builds the locking script) and
 * any SPV-style verifier (which parses the script to recover the cell
 * bytes). Wire-format drift between writer and reader is silent and
 * catastrophic, so this test fixes the canonical byte layout.
 */
import { describe, expect, test } from 'bun:test';
import { CELL_SIZE } from '../src/constants';
import {
  OP_DROP,
  OP_CHECKSIG,
  OP_PUSHDATA1,
  OP_PUSHDATA2,
  OP_PUSHDATA4,
  COMPRESSED_PUBKEY_SIZE,
  UNCOMPRESSED_PUBKEY_SIZE,
  CANONICAL_CELL_PUSHDROP_SCRIPT_SIZE,
  pushPrefix,
  buildPushdropLockingScript,
  parsePushdropLockingScript,
} from '../src/cell-pushdrop';

function fillBytes(n: number, seed: number): Uint8Array {
  const buf = new Uint8Array(n);
  for (let i = 0; i < n; i++) buf[i] = (i * 7 + seed) & 0xff;
  return buf;
}

function compressedPubkey(seed: number = 1): Uint8Array {
  const buf = new Uint8Array(COMPRESSED_PUBKEY_SIZE);
  buf[0] = 0x02;
  for (let i = 1; i < COMPRESSED_PUBKEY_SIZE; i++) buf[i] = (i + seed) & 0xff;
  return buf;
}

describe('pushdrop pushPrefix encoding', () => {
  test('direct push for 1..75 byte payloads', () => {
    expect(Array.from(pushPrefix(1))).toEqual([1]);
    expect(Array.from(pushPrefix(33))).toEqual([33]);
    expect(Array.from(pushPrefix(75))).toEqual([75]);
  });

  test('PUSHDATA1 for 76..255 byte payloads', () => {
    expect(Array.from(pushPrefix(76))).toEqual([OP_PUSHDATA1, 76]);
    expect(Array.from(pushPrefix(255))).toEqual([OP_PUSHDATA1, 255]);
  });

  test('PUSHDATA2 for 256..65535 byte payloads (covers the canonical 1024 cell)', () => {
    expect(Array.from(pushPrefix(256))).toEqual([OP_PUSHDATA2, 0x00, 0x01]);
    expect(Array.from(pushPrefix(1024))).toEqual([OP_PUSHDATA2, 0x00, 0x04]);
    expect(Array.from(pushPrefix(65535))).toEqual([OP_PUSHDATA2, 0xff, 0xff]);
  });

  test('PUSHDATA4 for 65536+ byte payloads', () => {
    expect(Array.from(pushPrefix(65536))).toEqual([OP_PUSHDATA4, 0x00, 0x00, 0x01, 0x00]);
  });
});

describe('pushdrop locking-script build', () => {
  test('canonical 1024-byte cell + 33-byte pubkey is 1063 bytes', () => {
    const cell = fillBytes(CELL_SIZE, 0);
    const pub = compressedPubkey();
    const script = buildPushdropLockingScript(cell, pub);
    expect(script.length).toBe(CANONICAL_CELL_PUSHDROP_SCRIPT_SIZE);
    expect(script.length).toBe(1063);
  });

  test('canonical 1024-byte cell produces the §3.1 byte layout', () => {
    const cell = fillBytes(CELL_SIZE, 42);
    const pub = compressedPubkey();
    const script = buildPushdropLockingScript(cell, pub);

    // PUSHDATA2 + LE length 0x0400
    expect(script[0]).toBe(OP_PUSHDATA2);
    expect(script[1]).toBe(0x00);
    expect(script[2]).toBe(0x04);

    // Cell bytes at offset 3..3+1024
    for (let i = 0; i < CELL_SIZE; i++) {
      expect(script[3 + i]).toBe(cell[i]);
    }

    // OP_DROP at offset 3+1024 = 1027
    expect(script[1027]).toBe(OP_DROP);

    // 0x21 (push 33 bytes) at offset 1028
    expect(script[1028]).toBe(33);

    // Pubkey at offset 1029..1029+33
    for (let i = 0; i < COMPRESSED_PUBKEY_SIZE; i++) {
      expect(script[1029 + i]).toBe(pub[i]);
    }

    // OP_CHECKSIG at offset 1062
    expect(script[1062]).toBe(OP_CHECKSIG);
  });

  test('accepts uncompressed 65-byte pubkey', () => {
    const cell = fillBytes(CELL_SIZE, 1);
    const pub = new Uint8Array(UNCOMPRESSED_PUBKEY_SIZE);
    pub[0] = 0x04;
    for (let i = 1; i < UNCOMPRESSED_PUBKEY_SIZE; i++) pub[i] = i & 0xff;
    const script = buildPushdropLockingScript(cell, pub);
    expect(script.length).toBe(3 + 1024 + 1 + 1 + 65 + 1);
  });

  test('rejects empty cells', () => {
    expect(() => buildPushdropLockingScript(new Uint8Array(0), compressedPubkey())).toThrow();
  });

  test('rejects pubkeys that are neither 33 nor 65 bytes', () => {
    const cell = fillBytes(CELL_SIZE, 0);
    expect(() => buildPushdropLockingScript(cell, new Uint8Array(32))).toThrow();
    expect(() => buildPushdropLockingScript(cell, new Uint8Array(64))).toThrow();
  });

  test('rejects cells larger than PUSHDATA2 max (65535)', () => {
    expect(() =>
      buildPushdropLockingScript(new Uint8Array(65536), compressedPubkey()),
    ).toThrow();
  });
});

describe('pushdrop locking-script parse', () => {
  test('build → parse round-trip recovers cell + pubkey bit-exact', () => {
    const cell = fillBytes(CELL_SIZE, 99);
    const pub = compressedPubkey(7);
    const script = buildPushdropLockingScript(cell, pub);
    const parsed = parsePushdropLockingScript(script);
    expect(Array.from(parsed.cellBytes)).toEqual(Array.from(cell));
    expect(Array.from(parsed.pubkey)).toEqual(Array.from(pub));
  });

  test('round-trips an uncompressed pubkey', () => {
    const cell = fillBytes(CELL_SIZE, 11);
    const pub = new Uint8Array(UNCOMPRESSED_PUBKEY_SIZE);
    pub[0] = 0x04;
    for (let i = 1; i < UNCOMPRESSED_PUBKEY_SIZE; i++) pub[i] = (i * 5 + 3) & 0xff;
    const script = buildPushdropLockingScript(cell, pub);
    const parsed = parsePushdropLockingScript(script);
    expect(parsed.pubkey.length).toBe(UNCOMPRESSED_PUBKEY_SIZE);
    expect(Array.from(parsed.pubkey)).toEqual(Array.from(pub));
  });

  test('round-trips a small cell using direct-push prefix (length <= 75)', () => {
    const cell = fillBytes(30, 0);
    const pub = compressedPubkey();
    const script = buildPushdropLockingScript(cell, pub);
    expect(script[0]).toBe(30); // direct push opcode = length
    const parsed = parsePushdropLockingScript(script);
    expect(Array.from(parsed.cellBytes)).toEqual(Array.from(cell));
  });

  test('round-trips a 100-byte cell using PUSHDATA1', () => {
    const cell = fillBytes(100, 0);
    const pub = compressedPubkey();
    const script = buildPushdropLockingScript(cell, pub);
    expect(script[0]).toBe(OP_PUSHDATA1);
    expect(script[1]).toBe(100);
    const parsed = parsePushdropLockingScript(script);
    expect(Array.from(parsed.cellBytes)).toEqual(Array.from(cell));
  });

  test('rejects scripts missing OP_DROP', () => {
    const cell = fillBytes(CELL_SIZE, 0);
    const pub = compressedPubkey();
    const script = buildPushdropLockingScript(cell, pub);
    // Tamper with the OP_DROP byte.
    const tampered = new Uint8Array(script);
    tampered[1027] = 0x00; // not OP_DROP
    expect(() => parsePushdropLockingScript(tampered)).toThrow();
  });

  test('rejects scripts missing OP_CHECKSIG', () => {
    const cell = fillBytes(CELL_SIZE, 0);
    const pub = compressedPubkey();
    const script = buildPushdropLockingScript(cell, pub);
    const tampered = new Uint8Array(script);
    tampered[1062] = 0x00; // not OP_CHECKSIG
    expect(() => parsePushdropLockingScript(tampered)).toThrow();
  });

  test('rejects scripts with trailing bytes after OP_CHECKSIG', () => {
    const cell = fillBytes(CELL_SIZE, 0);
    const pub = compressedPubkey();
    const script = buildPushdropLockingScript(cell, pub);
    const padded = new Uint8Array(script.length + 1);
    padded.set(script);
    padded[script.length] = 0xff;
    expect(() => parsePushdropLockingScript(padded)).toThrow();
  });

  test('rejects truncated scripts', () => {
    const cell = fillBytes(CELL_SIZE, 0);
    const pub = compressedPubkey();
    const script = buildPushdropLockingScript(cell, pub);
    expect(() => parsePushdropLockingScript(script.subarray(0, script.length - 1))).toThrow();
    expect(() => parsePushdropLockingScript(new Uint8Array(3))).toThrow();
  });
});

```
