---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/tile-script.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.668845+00:00
---

# cartridges/wallet-headers/brain/test/tile-script.spec.ts

```ts
// tile-script spec — the MNCA `stepTile` rule compiled to branch-free Script.
//
// These pin the exact bytecode the compiler emits. The SAME bytes are executed
// against the native rule (mnca_tile.zig) in the cell-engine
// (core/cell-engine/tests/tile_script_equivalence.zig) — that test is the
// faithfulness oracle; this one guards the compiler output so the two cannot
// drift. Change a byte here ⇒ change the Zig pin too (and re-prove).

import { describe, expect, test } from 'bun:test';
import { compile, toHex, toAsm, OP } from '../src/script-macro';
import {
  compileCellRule, compileAliveCount, compileCellStep, DEFAULT_RULE,
} from '../src/tile-script';

describe('compileCellRule — per-cell MNCA kernel (DEFAULT_RULE)', () => {
  test('emits the exact bytecode proven equal to the native rule in-engine', () => {
    expect(toHex(compile(compileCellRule(DEFAULT_RULE)))).toBe(
      '765254a57c5354a55379028000a26b6b6b6c6c766b946c7c6c9593028000950140947c5ca2014095939300a402ff00a3',
    );
  });
  test('is branch-free (no OP_IF / OP_ELSE / OP_ENDIF — selection is arithmetic)', () => {
    const s = compile(compileCellRule());
    expect(s.includes(OP.OP_IF)).toBe(false);
    expect(s.includes(OP.OP_ELSE)).toBe(false);
    expect(s.includes(OP.OP_ENDIF)).toBe(false);
  });
  test('parametric: a different rule changes the embedded constants', () => {
    const a = toHex(compile(compileCellRule(DEFAULT_RULE)));
    const b = toHex(compile(compileCellRule({ ...DEFAULT_RULE, aliveThreshold: 100 })));
    expect(a).not.toBe(b);
  });
});

describe('compileAliveCount — threshold popcount of the top k items', () => {
  test('compileAliveCount(128, 3) emits the pinned bytecode', () => {
    expect(toHex(compile(compileAliveCount(128, 3)))).toBe('028000a26b028000a26b028000a26b006c936c936c93');
  });
  test('k=0 is just the zero seed (count of nothing is 0)', () => {
    expect(toAsm(compile(compileAliveCount(128, 0)))).toBe('OP_FALSE');
  });
  test('structure: k convert-and-park steps, then seed, then k fold steps', () => {
    expect(toAsm(compile(compileAliveCount(1, 2)))).toBe(
      'OP_TRUE OP_GREATERTHANOREQUAL OP_TOALTSTACK OP_TRUE OP_GREATERTHANOREQUAL OP_TOALTSTACK ' +
      'OP_FALSE OP_FROMALTSTACK OP_ADD OP_FROMALTSTACK OP_ADD');
  });
  test('rejects a negative k', () => {
    expect(() => compileAliveCount(128, -1)).toThrow();
  });
});

describe('compileCellStep — full interior step from raw neighbour values', () => {
  test('composes: count outer (top), park, count inner, reorder, then the kernel', () => {
    const asm = toAsm(compile(compileCellStep(DEFAULT_RULE, 2, 2)));
    // outer count (k=2) ‖ TOALTSTACK ‖ inner count (k=2) ‖ FROMALTSTACK SWAP ‖ kernel…
    expect(asm.startsWith(
      'PUSH(2) 8000 OP_GREATERTHANOREQUAL OP_TOALTSTACK PUSH(2) 8000 OP_GREATERTHANOREQUAL OP_TOALTSTACK ' +
      'OP_FALSE OP_FROMALTSTACK OP_ADD OP_FROMALTSTACK OP_ADD OP_TOALTSTACK ')).toBe(true);
    expect(asm.endsWith('PUSH(2) ff00 OP_MIN')).toBe(true); // ends with the kernel's clamp
  });
  test('deterministic — identical args ⇒ byte-identical script', () => {
    expect(toHex(compile(compileCellStep(DEFAULT_RULE, 8, 48))))
      .toBe(toHex(compile(compileCellStep(DEFAULT_RULE, 8, 48))));
  });
});

```
