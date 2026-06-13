---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/script-macro.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.673569+00:00
---

# cartridges/wallet-headers/brain/test/script-macro.spec.ts

```ts
// script-macro spec — canonical push encoding + loop unrolling + determinism.
//
// The load-bearing correctness is minimal-ScriptNum push encoding (Appendix B);
// the rest verifies that --macro-unroll-loops produces flat, deterministic,
// branch-free bytecode.

import { describe, expect, test } from 'bun:test';
import {
  OP, op, pushInt, pushBytes, pushHex, LOOP, REPEAT, seq, compile, toAsm, toHex,
  xRot, xDrop, xSwap, hashCat,
} from '../src/script-macro';

const hex = (...frags: Uint8Array[][]) => toHex(compile(frags.flat()));

describe('pushInt — canonical minimal ScriptNum (Appendix B)', () => {
  test('0..16 use OP_0 / OP_1..OP_16', () => {
    expect(toHex(pushInt(0))).toBe('00');     // OP_0
    expect(toHex(pushInt(1))).toBe('51');     // OP_1
    expect(toHex(pushInt(16))).toBe('60');    // OP_16
  });
  test('-1 uses OP_1NEGATE', () => {
    expect(toHex(pushInt(-1))).toBe('4f');
  });
  test('17 is a 1-byte data push', () => {
    expect(toHex(pushInt(17))).toBe('0111');  // PUSH(1) 0x11
  });
  test('positive value with high bit set gets a 0x00 sign pad', () => {
    // 128 = 0x80 → would read negative, so pad: PUSH(2) 80 00
    expect(toHex(pushInt(128))).toBe('028000');
    expect(toHex(pushInt(255))).toBe('02ff00');
  });
  test('negative values set the sign bit', () => {
    // -128: magnitude 0x80 has high bit set → append 0x80: PUSH(2) 80 80
    expect(toHex(pushInt(-128))).toBe('028080');
    // -127: magnitude 0x7f, set high bit → 0xff: PUSH(1) ff
    expect(toHex(pushInt(-127))).toBe('01ff');
  });
  test('256 → little-endian PUSH(2) 00 01', () => {
    expect(toHex(pushInt(256))).toBe('020001');
  });
  test('big int round (bigint input)', () => {
    expect(toHex(pushInt(0x010203n))).toBe('03030201');
  });
});

describe('pushBytes — minimal push opcode selection', () => {
  test('1..75 byte payloads use a direct push', () => {
    expect(toHex(pushBytes(new Uint8Array(1)))).toBe('0100');
    expect(toHex(pushBytes(new Uint8Array(75)))).toBe('4b' + '00'.repeat(75));
  });
  test('76..255 use PUSHDATA1', () => {
    const out = pushBytes(new Uint8Array(76));
    expect(out[0]).toBe(OP.OP_PUSHDATA1);
    expect(out[1]).toBe(76);
  });
  test('256+ use PUSHDATA2 (little-endian length)', () => {
    const out = pushBytes(new Uint8Array(256));
    expect(out[0]).toBe(OP.OP_PUSHDATA2);
    expect(out[1]).toBe(0x00);
    expect(out[2]).toBe(0x01);
  });
  test('empty push is OP_0', () => {
    expect(toHex(pushBytes(new Uint8Array(0)))).toBe('00');
  });
});

describe('LOOP — compile-time unrolling', () => {
  test('LOOP(3, push i) → OP_0 OP_1 OP_2', () => {
    expect(hex([LOOP(3, (i) => [pushInt(i)])])).toBe('005152');
  });
  test('square macro (BSV OP_MUL): i DUP MUL per iteration', () => {
    const square = LOOP(3, (i) => [pushInt(i), op(OP.OP_DUP), op(OP.OP_MUL)]);
    // 0 DUP MUL | 1 DUP MUL | 2 DUP MUL
    expect(hex([square])).toBe('00' + '7695' + '51' + '7695' + '52' + '7695');
  });
  test('square macro (BTC, precomputed literals): push i*i', () => {
    const square = LOOP(4, (i) => [pushInt(i * i)]);
    // 0, 1, 4, 9  → OP_0 OP_1 OP_4 OP_9
    expect(hex([square])).toBe('00' + '51' + '54' + '59');
  });
  test('nested LOOP = cartesian product', () => {
    const grid = LOOP(2, (i) => [...LOOP(2, (j) => [pushInt(i), pushInt(j)])]);
    // (0,0)(0,1)(1,0)(1,1) → 00 00 | 00 51 | 51 00 | 51 51
    expect(hex([grid])).toBe('0000' + '0051' + '5100' + '5151');
  });
  test('REPEAT repeats an index-free fragment', () => {
    expect(hex([REPEAT(3, [op(OP.OP_DUP)])])).toBe('767676');
  });
  test('LOOP rejects a negative / non-integer bound', () => {
    expect(() => LOOP(-1, () => [])).toThrow();
    expect(() => LOOP(1.5, () => [])).toThrow();
  });
});

// These pin the LEGACY lowering of the engine's native Craig macros. The exact
// byte expansions are cross-verified against macro.zig in the cell-engine
// (tests/macro_legacy_equivalence.zig: native 0xB0 opcode vs this bytecode ⇒
// identical PDA stack). If you change an expansion here, change it there too.
describe('canonical macro family — legacy lowering of native Craig macros', () => {
  test('XROT-3 → OP_2 OP_ROLL (≡ OP_ROT)', () => {
    expect(toAsm(compile(xRot(3)))).toBe('OP_2 OP_ROLL');
    expect(toHex(compile(xRot(3)))).toBe('527a');
  });
  test('XROT-4 → OP_3 OP_ROLL', () => {
    expect(toAsm(compile(xRot(4)))).toBe('OP_3 OP_ROLL');
  });
  test('XDROP-N drops the top N (XDROP-2 ≡ OP_2DROP semantics)', () => {
    expect(toAsm(compile(xDrop(2)))).toBe('OP_DROP OP_DROP');
    expect(toAsm(compile(xDrop(4)))).toBe('OP_DROP OP_DROP OP_DROP OP_DROP');
  });
  test('XSWAP-2 → OP_SWAP', () => {
    expect(toAsm(compile(xSwap(2)))).toBe('OP_SWAP');
  });
  test('XSWAP-3 → OP_SWAP OP_ROT', () => {
    expect(toAsm(compile(xSwap(3)))).toBe('OP_SWAP OP_ROT');
  });
  test('XSWAP-4 → OP_3 OP_ROLL OP_TOALTSTACK OP_2 OP_ROLL OP_2 OP_ROLL OP_FROMALTSTACK', () => {
    expect(toAsm(compile(xSwap(4)))).toBe(
      'OP_3 OP_ROLL OP_TOALTSTACK OP_2 OP_ROLL OP_2 OP_ROLL OP_FROMALTSTACK');
  });
  test('HASHCAT → OP_CAT OP_SHA256', () => {
    expect(toAsm(compile(hashCat()))).toBe('OP_CAT OP_SHA256');
  });
  test('depth literal stays minimal-push for n-1 > 16 (xRot(18) → PUSH(1) 0x11 OP_ROLL)', () => {
    expect(toAsm(compile(xRot(18)))).toBe('PUSH(1) 11 OP_ROLL');
  });
  test('macros reject an out-of-range / non-integer depth', () => {
    expect(() => xRot(1)).toThrow();   // XROT needs >= 2
    expect(() => xDrop(0)).toThrow();  // XDROP needs >= 1
    expect(() => xSwap(2.5)).toThrow();
  });
  test('macros are branch-free and compose under LOOP', () => {
    const folded = compile(LOOP(3, () => xRot(3)));
    expect(folded.includes(OP.OP_IF)).toBe(false);
    expect(folded.includes(OP.OP_ELSE)).toBe(false);
    expect(toAsm(folded)).toBe('OP_2 OP_ROLL OP_2 OP_ROLL OP_2 OP_ROLL');
  });
});

describe('determinism + composition', () => {
  test('identical macro → byte-identical script (twice)', () => {
    const build = () => compile(seq(
      LOOP(5, (i) => [pushInt(i), op(OP.OP_ADD)]),
      [op(OP.OP_VERIFY)],
    ));
    expect(toHex(build())).toBe(toHex(build()));
  });
  test('the emitted script is branch-free (no OP_IF/ELSE/ENDIF) for an unrolled accumulator', () => {
    const acc = compile(seq([pushInt(0)], LOOP(4, (i) => [pushInt(i + 1), op(OP.OP_ADD)])));
    expect(acc.includes(OP.OP_IF)).toBe(false);
    expect(acc.includes(OP.OP_ELSE)).toBe(false);
    expect(acc.includes(OP.OP_ENDIF)).toBe(false);
  });
});

describe('toAsm — auditability', () => {
  test('disassembles opcodes + pushes', () => {
    const s = compile(seq([pushInt(5)], [op(OP.OP_DUP), op(OP.OP_MUL)]));
    expect(toAsm(s)).toBe('OP_5 OP_DUP OP_MUL');
  });
  test('shows data pushes with hex', () => {
    const s = compile([pushHex('deadbeef')]);
    expect(toAsm(s)).toBe('PUSH(4) deadbeef');
  });
});

```
