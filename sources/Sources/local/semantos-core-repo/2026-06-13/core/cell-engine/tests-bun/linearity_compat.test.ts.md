---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/linearity_compat.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.986721+00:00
---

# core/cell-engine/tests-bun/linearity_compat.test.ts

```ts
// Phase 4: Cross-language linearity enforcement tests
// Verifies kernel_set_enforcement and kernel_get_type_class WASM exports

import { describe, test, expect, beforeAll } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { createHostFunctions } from '../bindings/host-functions';

const WASM_PATH = join(__dirname, '..', 'zig-out', 'bin', 'cell-engine.wasm');

let instance: WebAssembly.Instance;
let memory: WebAssembly.Memory;

function getExport<T>(name: string): T {
  return instance.exports[name] as T;
}

class MemoryProxy {
  getInstance: () => WebAssembly.Instance | null;
  constructor(getInstance: () => WebAssembly.Instance | null) {
    this.getInstance = getInstance;
  }
  get buffer(): ArrayBuffer {
    const inst = this.getInstance();
    if (inst?.exports.memory) {
      return (inst.exports.memory as WebAssembly.Memory).buffer;
    }
    return new ArrayBuffer(0);
  }
}

beforeAll(async () => {
  const wasmBytes = readFileSync(WASM_PATH);
  let currentInstance: WebAssembly.Instance | null = null;
  const memProxy = new MemoryProxy(() => currentInstance);
  const result = await WebAssembly.instantiate(wasmBytes, {
    host: createHostFunctions(memProxy as any),
  });
  instance = result.instance;
  currentInstance = instance;
  memory = instance.exports.memory as WebAssembly.Memory;
});

// Helper: write a test cell at a memory address with the given linearity
function writeTestCell(memView: Uint8Array, ptr: number, linearity: number): void {
  // Magic: DEADBEEF CAFEBABE 13371337 42424242 (LE)
  const magic = [
    0xEF, 0xBE, 0xAD, 0xDE, // DEADBEEF
    0xBE, 0xBA, 0xFE, 0xCA, // CAFEBABE
    0x37, 0x13, 0x37, 0x13, // 13371337
    0x42, 0x42, 0x42, 0x42, // 42424242
  ];
  for (let i = 0; i < 16; i++) {
    memView[ptr + i] = magic[i];
  }
  // Linearity at offset 16, 4 bytes LE
  memView[ptr + 16] = linearity & 0xFF;
  memView[ptr + 17] = (linearity >> 8) & 0xFF;
  memView[ptr + 18] = (linearity >> 16) & 0xFF;
  memView[ptr + 19] = (linearity >> 24) & 0xFF;
  // Version at offset 20
  memView[ptr + 20] = 1;
}

describe('Phase 4 exports exist', () => {
  test('kernel_set_enforcement export exists', () => {
    expect(instance.exports.kernel_set_enforcement).toBeDefined();
  });

  test('kernel_get_type_class export exists', () => {
    expect(instance.exports.kernel_get_type_class).toBeDefined();
  });
});

describe('kernel_get_type_class', () => {
  test('returns -1 (UNCLASSIFIED) for empty stack', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const getTypeClass = getExport<() => number>('kernel_get_type_class');

    init();
    reset();
    expect(getTypeClass()).toBe(-1);
  });

  test('returns LINEAR (0) for LINEAR cell on stack', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');
    const getTypeClass = getExport<() => number>('kernel_get_type_class');

    init();
    reset();

    const memView = new Uint8Array(memory.buffer);

    // Write a 1024-byte LINEAR cell into WASM memory
    const cellPtr = 0x200000;
    // Zero out the full cell first
    for (let i = 0; i < 1024; i++) memView[cellPtr + i] = 0;
    writeTestCell(memView, cellPtr, 1); // LINEAR = 1

    // Unlock script: PUSHDATA2 + 1024 bytes (push the entire cell)
    // PUSHDATA2 (0x4D) + length_LE(2 bytes) + data(1024 bytes)
    const unlockPtr = 0x210000;
    memView[unlockPtr] = 0x4D; // OP_PUSHDATA2
    memView[unlockPtr + 1] = 0x00; // 1024 & 0xFF = 0x00
    memView[unlockPtr + 2] = 0x04; // 1024 >> 8 = 0x04
    // Copy cell data after the PUSHDATA2 header
    for (let i = 0; i < 1024; i++) {
      memView[unlockPtr + 3 + i] = memView[cellPtr + i];
    }
    loadUnlock(unlockPtr, 3 + 1024);

    // Lock script: OP_1 (just push 1 so it succeeds)
    const lockPtr = 0x220000;
    memView[lockPtr] = 0x51; // OP_1
    loadScript(lockPtr, 1);

    const result = execute();
    expect(result).toBe(0); // script succeeds (OP_1 pushes truthy)

    // After execution, top-of-stack is OP_1's result (not the cell)
    // Let's instead run a script that leaves the cell on top
    reset();
    // Unlock: push 1024-byte cell
    loadUnlock(unlockPtr, 3 + 1024);
    // Lock: empty (no lock script)
    loadScript(lockPtr, 0);

    // With empty lock script, the cell is still on the stack
    // But execute requires non-empty top for success...
    // Actually the cell has magic bytes so it's truthy.
    const result2 = execute();
    // Cell starts with 0xEF (DEADBEEF LE) which is truthy
    expect(result2).toBe(0);

    // Now check type class
    expect(getTypeClass()).toBe(0); // LINEAR
  });

  test('returns AFFINE (1) for AFFINE cell on stack', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');
    const getTypeClass = getExport<() => number>('kernel_get_type_class');

    init();
    reset();

    const memView = new Uint8Array(memory.buffer);
    const cellPtr = 0x200000;
    for (let i = 0; i < 1024; i++) memView[cellPtr + i] = 0;
    writeTestCell(memView, cellPtr, 2); // AFFINE = 2

    const unlockPtr = 0x210000;
    memView[unlockPtr] = 0x4D;
    memView[unlockPtr + 1] = 0x00;
    memView[unlockPtr + 2] = 0x04;
    for (let i = 0; i < 1024; i++) {
      memView[unlockPtr + 3 + i] = memView[cellPtr + i];
    }
    loadUnlock(unlockPtr, 3 + 1024);
    loadScript(0x220000, 0);

    execute();
    expect(getTypeClass()).toBe(1); // AFFINE
  });

  test('returns RELEVANT (2) for RELEVANT cell on stack', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');
    const getTypeClass = getExport<() => number>('kernel_get_type_class');

    init();
    reset();

    const memView = new Uint8Array(memory.buffer);
    const cellPtr = 0x200000;
    for (let i = 0; i < 1024; i++) memView[cellPtr + i] = 0;
    writeTestCell(memView, cellPtr, 3); // RELEVANT = 3

    const unlockPtr = 0x210000;
    memView[unlockPtr] = 0x4D;
    memView[unlockPtr + 1] = 0x00;
    memView[unlockPtr + 2] = 0x04;
    for (let i = 0; i < 1024; i++) {
      memView[unlockPtr + 3 + i] = memView[cellPtr + i];
    }
    loadUnlock(unlockPtr, 3 + 1024);
    loadScript(0x220000, 0);

    execute();
    expect(getTypeClass()).toBe(2); // RELEVANT
  });
});

describe('kernel_set_enforcement', () => {
  test('enforcement toggle works through WASM', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const setEnforcement = getExport<(enabled: number) => void>('kernel_set_enforcement');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');

    init();
    reset();

    const memView = new Uint8Array(memory.buffer);

    // Write a LINEAR cell
    const cellPtr = 0x200000;
    for (let i = 0; i < 1024; i++) memView[cellPtr + i] = 0;
    writeTestCell(memView, cellPtr, 1); // LINEAR

    // Unlock: push LINEAR cell
    const unlockPtr = 0x210000;
    memView[unlockPtr] = 0x4D;
    memView[unlockPtr + 1] = 0x00;
    memView[unlockPtr + 2] = 0x04;
    for (let i = 0; i < 1024; i++) {
      memView[unlockPtr + 3 + i] = memView[cellPtr + i];
    }

    // Lock: OP_DUP (0x76)
    const lockPtr = 0x220000;
    memView[lockPtr] = 0x76; // OP_DUP

    // With enforcement OFF: DUP should succeed
    setEnforcement(0);
    loadUnlock(unlockPtr, 3 + 1024);
    loadScript(lockPtr, 1);
    const result1 = execute();
    expect(result1).toBe(0); // success — DUP works without enforcement

    // With enforcement ON: DUP should fail (LINEAR can't be duplicated)
    reset();
    setEnforcement(1);
    loadUnlock(unlockPtr, 3 + 1024);
    loadScript(lockPtr, 1);
    const result2 = execute();
    expect(result2).toBe(22); // cannot_duplicate_linear error code
  });
});

describe('Plexus opcodes through WASM', () => {
  test('OP_CHECKLINEARTYPE (0xC0) succeeds on LINEAR cell', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const setEnforcement = getExport<(enabled: number) => void>('kernel_set_enforcement');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');

    init();
    reset();
    setEnforcement(0); // Plexus opcodes don't need enforcement to run

    const memView = new Uint8Array(memory.buffer);

    // Write LINEAR cell
    const cellPtr = 0x200000;
    for (let i = 0; i < 1024; i++) memView[cellPtr + i] = 0;
    writeTestCell(memView, cellPtr, 1);

    // Unlock: push cell
    const unlockPtr = 0x210000;
    memView[unlockPtr] = 0x4D;
    memView[unlockPtr + 1] = 0x00;
    memView[unlockPtr + 2] = 0x04;
    for (let i = 0; i < 1024; i++) {
      memView[unlockPtr + 3 + i] = memView[cellPtr + i];
    }
    loadUnlock(unlockPtr, 3 + 1024);

    // Lock: OP_CHECKLINEARTYPE (0xC0)
    const lockPtr = 0x220000;
    memView[lockPtr] = 0xC0;
    loadScript(lockPtr, 1);

    const result = execute();
    expect(result).toBe(0); // success — cell is LINEAR, TRUE pushed
  });

  test('reserved opcode 0xC9 returns reserved_opcode error', () => {
    // 0xC8 is now OP_DEREF_POINTER (Phase 6), so test 0xC9 instead
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');

    init();
    reset();

    const memView = new Uint8Array(memory.buffer);
    const lockPtr = 0x220000;
    memView[lockPtr] = 0xC9; // reserved
    loadScript(lockPtr, 1);

    const result = execute();
    expect(result).toBe(32); // reserved_opcode error code
  });
});

```
