---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/branchonoutput-e2e.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.989570+00:00
---

# core/cell-engine/tests-bun/branchonoutput-e2e.test.ts

```ts
/**
 * OP_BRANCHONOUTPUT (0xE0) — full TS → WASM → Zig end-to-end integration.
 *
 * Loads cell-engine.wasm directly (bypassing the broken @semantos/cell-ops
 * dist build), drives kernel_set_output_index + kernel_load_script +
 * kernel_execute, and verifies the bytes pushed by OP_BRANCHONOUTPUT
 * match the TS-side u32ToLE encoding for the same indices.
 *
 * This is the deferred-from-tick-4 integration test, unblocked by the
 * `TxContext.initInPlace` fix to the Zig ≥0.15.2 kernel_init OOB
 * (commit f30d184).
 *
 * Spec:    docs/design/OP-BRANCHONOUTPUT-SPEC.md
 * Tracker: docs/OP-BRANCHONOUTPUT-TRACKER.md
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';

const WASM_PATH = join(__dirname, '..', 'zig-out', 'bin', 'cell-engine.wasm');

// ── Opcode bytes (mirror constants.zig) ──
const OP_0 = 0x00;
const OP_1 = 0x51;
const OP_DUP = 0x76;
const OP_DROP = 0x75;
const OP_EQUAL = 0x87;
const OP_IF = 0x63;
const OP_ELSE = 0x67;
const OP_ENDIF = 0x68;
const OP_BRANCHONOUTPUT = 0xE0;

const SCRIPT_PTR = 0x500000;

interface Engine {
  exports: any;
  memory: WebAssembly.Memory;
  run(script: number[], outputIndex: number): { rc: number; depth: number; topBytes: Uint8Array };
}

let engine: Engine;

beforeAll(async () => {
  const wasmBytes = readFileSync(WASM_PATH);
  const hostStubs = {
    host_fetch_cell: () => 0,
    host_call_by_name: () => 0,
    hostDbOpenCursor: () => 0,
    hostDbCursorPull: () => 0,
    hostDbCursorClose: () => 0,
  };
  const { instance } = await WebAssembly.instantiate(wasmBytes, { host: hostStubs });
  const e: any = instance.exports;
  const initRc = e.kernel_init();
  if (initRc !== 0) throw new Error(`kernel_init failed: rc=${initRc}`);

  engine = {
    exports: e,
    memory: e.memory as WebAssembly.Memory,
    run(script, outputIndex) {
      e.kernel_reset();
      const setRc = e.kernel_set_output_index(outputIndex);
      if (setRc !== 0) throw new Error(`kernel_set_output_index failed: rc=${setRc}`);
      const buf = new Uint8Array(this.memory.buffer);
      buf.set(script, SCRIPT_PTR);
      const loadRc = e.kernel_load_script(SCRIPT_PTR, script.length);
      if (loadRc !== 0) throw new Error(`kernel_load_script failed: rc=${loadRc}`);
      const rc = e.kernel_execute();
      const depth = e.kernel_stack_depth();
      // Peek index 1 = the BRANCHONOUTPUT push (index 0 is the OP_1 tail).
      const ptr = e.kernel_stack_peek(1);
      const len = e.kernel_stack_value_length(1);
      const topBytes =
        ptr === 0 || len === 0
          ? new Uint8Array(0)
          : new Uint8Array(this.memory.buffer, ptr, len).slice();
      return { rc, depth, topBytes };
    },
  };
});

function u32ToLE(n: number): number[] {
  return [n & 0xff, (n >>> 8) & 0xff, (n >>> 16) & 0xff, (n >>> 24) & 0xff];
}

// ── E2E parity vectors ──

describe('OP_BRANCHONOUTPUT end-to-end (TS → WASM → Zig)', () => {
  const VECTORS = [0, 1, 2, 7, 42, 255, 256, 0x12345678, 0xabcdef01];

  for (const idx of VECTORS) {
    test(`output_index = 0x${idx.toString(16).padStart(8, '0')} → 4-byte LE push`, () => {
      const { rc, depth, topBytes } = engine.run([OP_BRANCHONOUTPUT, OP_1], idx);
      expect(rc).toBe(0);
      expect(depth).toBe(2);
      expect(Array.from(topBytes)).toEqual(u32ToLE(idx));
    });
  }
});

// ── E2E index-based dispatch ──

describe('OP_BRANCHONOUTPUT — end-to-end index-based dispatch', () => {
  // Script: BRANCHONOUTPUT DUP <0> EQUAL IF <0x42> ELSE DUP <1> EQUAL IF <0xCC>
  //                        ELSE DUP <2> EQUAL IF <0xFF> ELSE OP_0 ENDIF ENDIF ENDIF
  // Each <N> is the 4-byte LE encoding of N.
  const pushBytes = (bs: number[]) => [bs.length, ...bs];
  const compareEq = (idxLE: number[], payload: number[]) => [
    OP_DUP,
    ...pushBytes(idxLE),
    OP_EQUAL,
    OP_IF,
    ...pushBytes(payload),
    OP_ELSE,
  ];
  const SCRIPT = [
    OP_BRANCHONOUTPUT,
    ...compareEq(u32ToLE(0), [0x42]),
    ...compareEq(u32ToLE(1), [0xCC]),
    ...compareEq(u32ToLE(2), [0xFF]),
    OP_0,
    OP_ENDIF, OP_ENDIF, OP_ENDIF,
  ];

  test('index 0 → 0x42 path', () => {
    const { rc } = engine.run(SCRIPT, 0);
    expect(rc).toBe(0);
    const topPtr = engine.exports.kernel_stack_peek(0);
    const topLen = engine.exports.kernel_stack_value_length(0);
    expect(Array.from(new Uint8Array(engine.memory.buffer, topPtr, topLen))).toEqual([0x42]);
  });

  test('index 1 → 0xCC path', () => {
    const { rc } = engine.run(SCRIPT, 1);
    expect(rc).toBe(0);
    const topPtr = engine.exports.kernel_stack_peek(0);
    const topLen = engine.exports.kernel_stack_value_length(0);
    expect(Array.from(new Uint8Array(engine.memory.buffer, topPtr, topLen))).toEqual([0xCC]);
  });

  test('index 2 → 0xFF path', () => {
    const { rc } = engine.run(SCRIPT, 2);
    expect(rc).toBe(0);
    const topPtr = engine.exports.kernel_stack_peek(0);
    const topLen = engine.exports.kernel_stack_value_length(0);
    expect(Array.from(new Uint8Array(engine.memory.buffer, topPtr, topLen))).toEqual([0xFF]);
  });

  test('index 3 (out of range) → OP_0 leaves untruthy top, kernel_execute fails', () => {
    const { rc } = engine.run(SCRIPT, 3);
    // OP_0 pushes empty; verify_failed is returned.
    expect(rc).not.toBe(0);
  });

  test('exactly three indices produce done_true (one per dispatch branch)', () => {
    const successes = [0, 1, 2, 3, 4, 5].filter(
      (i) => engine.run(SCRIPT, i).rc === 0,
    );
    expect(successes).toEqual([0, 1, 2]);
  });
});

// ── E2E non-malleability (I3) ──

describe('OP_BRANCHONOUTPUT — end-to-end non-malleability (I3)', () => {
  test('repeated invocations with different indices yield distinct pushes', () => {
    const a = engine.run([OP_BRANCHONOUTPUT, OP_1], 7);
    const b = engine.run([OP_BRANCHONOUTPUT, OP_1], 8);
    expect(Array.from(a.topBytes)).toEqual([7, 0, 0, 0]);
    expect(Array.from(b.topBytes)).toEqual([8, 0, 0, 0]);
  });

  test('script that drops the push cannot affect the next invocation', () => {
    // Script: BRANCHONOUTPUT DROP OP_1 — pops the BRANCH push, leaves OP_1.
    engine.run([OP_BRANCHONOUTPUT, OP_DROP, OP_1], 42);
    // Next invocation: runtime alone decides the index.
    const { topBytes } = engine.run([OP_BRANCHONOUTPUT, OP_1], 99);
    expect(Array.from(topBytes)).toEqual([99, 0, 0, 0]);
  });
});

```
