---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/octave_compat.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.987275+00:00
---

# core/cell-engine/tests-bun/octave_compat.test.ts

```ts
// Phase 6: Octave memory integration tests
// End-to-end test for OP_DEREF_POINTER (0xC8) through the full WASM→host path.

import { describe, test, expect, beforeAll, afterEach } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import {
  createHostFunctions,
  createOctaveCellStore,
  seedCellInStore,
  type OctaveCellStore,
} from '../bindings/host-functions';

const WASM_PATH = join(__dirname, '..', 'zig-out', 'bin', 'cell-engine.wasm');

let instance: WebAssembly.Instance;
let memory: WebAssembly.Memory;
let cellStore: OctaveCellStore;

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
  cellStore = createOctaveCellStore();
  const result = await WebAssembly.instantiate(wasmBytes, {
    host: createHostFunctions(memProxy as any, undefined, cellStore),
  });
  instance = result.instance;
  currentInstance = instance;
  memory = instance.exports.memory as WebAssembly.Memory;
});

afterEach(() => {
  cellStore.clear();
});

/**
 * Build a pointer cell (1024 bytes) in the given buffer at the given offset.
 * Wire format: 8-byte continuation header + 90-byte payload + 926 zero padding.
 */
function writePointerCell(
  mem: Uint8Array,
  ptr: number,
  octave: number,
  slot: number,
  offset: number,
): void {
  // Zero the cell
  for (let i = 0; i < 1024; i++) mem[ptr + i] = 0;

  // Continuation header (8 bytes)
  mem[ptr + 0] = 0x06; // POINTER cell type
  // cell_index = 1 (LE u16)
  mem[ptr + 1] = 1;
  mem[ptr + 2] = 0;
  // total_cells = 1 (LE u16)
  mem[ptr + 3] = 1;
  mem[ptr + 4] = 0;
  // payload_size = 90 (LE u16)
  mem[ptr + 5] = 90;
  mem[ptr + 6] = 0;
  // reserved = 0
  mem[ptr + 7] = 0;

  // Pointer payload (90 bytes starting at offset 8)
  const p = ptr + 8;
  mem[p + 0] = octave;
  // slot (LE u16)
  mem[p + 1] = slot & 0xFF;
  mem[p + 2] = (slot >> 8) & 0xFF;
  // offset (LE u32)
  mem[p + 3] = offset & 0xFF;
  mem[p + 4] = (offset >> 8) & 0xFF;
  mem[p + 5] = (offset >> 16) & 0xFF;
  mem[p + 6] = (offset >> 24) & 0xFF;
  // pad byte at p+7 = 0 (already zeroed)
  // content_hash, type_hash, total_size, flags, fragment_count, reserved = 0
}

describe('Phase 6: OP_DEREF_POINTER (0xC8) through WASM', () => {
  test('OP_DEREF_POINTER fetches seeded cell from octave store', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');
    const stackDepth = getExport<() => number>('kernel_stack_depth');
    const stackPeek = getExport<(index: number) => number>('kernel_stack_peek');

    init();
    reset();

    // Seed a 1KB cell at octave 1, slot 7
    const targetCell = new Uint8Array(1024);
    targetCell[0] = 0xDE; // distinctive marker
    targetCell[1] = 0xAD;
    targetCell[1023] = 0xFF; // marker at end
    seedCellInStore(cellStore, 1, 7, targetCell);

    const memView = new Uint8Array(memory.buffer);

    // Build a pointer cell pointing to octave 1, slot 7, offset 0
    const cellPtr = 0x200000;
    writePointerCell(memView, cellPtr, 1, 7, 0);

    // Unlock script: PUSHDATA2 + 1024 bytes (push the pointer cell)
    // Then lock script: 0xC8 (OP_DEREF_POINTER) + OP_TRUE (to leave a truthy value)
    const unlockPtr = 0x210000;
    memView[unlockPtr] = 0x4D; // OP_PUSHDATA2
    memView[unlockPtr + 1] = 0x00; // 1024 & 0xFF
    memView[unlockPtr + 2] = 0x04; // 1024 >> 8
    // Copy pointer cell data
    for (let i = 0; i < 1024; i++) {
      memView[unlockPtr + 3 + i] = memView[cellPtr + i];
    }
    const unlockLen = 3 + 1024;

    // Lock script: OP_DEREF_POINTER (0xC8) then OP_DROP then OP_TRUE
    // We drop the fetched cell and push TRUE so the script succeeds
    const lockPtr = 0x220000;
    memView[lockPtr] = 0xC8;     // OP_DEREF_POINTER
    memView[lockPtr + 1] = 0x75; // OP_DROP
    memView[lockPtr + 2] = 0x51; // OP_TRUE (OP_1)
    const lockLen = 3;

    loadUnlock(unlockPtr, unlockLen);
    loadScript(lockPtr, lockLen);

    const result = execute();
    expect(result).toBe(0); // success
  });

  test('OP_DEREF_POINTER on non-pointer cell returns invalid_pointer_cell error', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');

    init();
    reset();

    const memView = new Uint8Array(memory.buffer);

    // Push a regular DATA cell (type 0x04), NOT a pointer cell
    const cellPtr = 0x200000;
    for (let i = 0; i < 1024; i++) memView[cellPtr + i] = 0;
    memView[cellPtr] = 0x04; // DATA type

    // Unlock: push the non-pointer cell
    const unlockPtr = 0x210000;
    memView[unlockPtr] = 0x4D; // OP_PUSHDATA2
    memView[unlockPtr + 1] = 0x00;
    memView[unlockPtr + 2] = 0x04;
    for (let i = 0; i < 1024; i++) {
      memView[unlockPtr + 3 + i] = memView[cellPtr + i];
    }

    // Lock: OP_DEREF_POINTER
    const lockPtr = 0x220000;
    memView[lockPtr] = 0xC8;

    loadUnlock(unlockPtr, 3 + 1024);
    loadScript(lockPtr, 1);

    const result = execute();
    expect(result).toBe(41); // invalid_pointer_cell error code
  });

  test('OP_DEREF_POINTER with missing octave cell returns host_fetch_failed', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');

    init();
    reset();

    const memView = new Uint8Array(memory.buffer);

    // Pointer cell pointing to octave 2, slot 999 — nothing seeded there
    const cellPtr = 0x200000;
    writePointerCell(memView, cellPtr, 2, 999, 0);

    const unlockPtr = 0x210000;
    memView[unlockPtr] = 0x4D;
    memView[unlockPtr + 1] = 0x00;
    memView[unlockPtr + 2] = 0x04;
    for (let i = 0; i < 1024; i++) {
      memView[unlockPtr + 3 + i] = memView[cellPtr + i];
    }

    const lockPtr = 0x220000;
    memView[lockPtr] = 0xC8;

    loadUnlock(unlockPtr, 3 + 1024);
    loadScript(lockPtr, 1);

    const result = execute();
    expect(result).toBe(42); // host_fetch_failed error code
  });

  test('OP_DEREF_POINTER is failure-atomic — stack unchanged on error', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');
    const stackDepth = getExport<() => number>('kernel_stack_depth');

    init();
    reset();

    const memView = new Uint8Array(memory.buffer);

    // Push a non-pointer cell, then try OP_DEREF_POINTER — should fail
    // but the cell should still be on the stack
    const cellPtr = 0x200000;
    for (let i = 0; i < 1024; i++) memView[cellPtr + i] = 0;
    memView[cellPtr] = 0x04; // DATA type, not POINTER

    const unlockPtr = 0x210000;
    memView[unlockPtr] = 0x4D;
    memView[unlockPtr + 1] = 0x00;
    memView[unlockPtr + 2] = 0x04;
    for (let i = 0; i < 1024; i++) {
      memView[unlockPtr + 3 + i] = memView[cellPtr + i];
    }

    const lockPtr = 0x220000;
    memView[lockPtr] = 0xC8; // OP_DEREF_POINTER — will fail

    loadUnlock(unlockPtr, 3 + 1024);
    loadScript(lockPtr, 1);

    const result = execute();
    expect(result).toBe(41); // invalid_pointer_cell
    // Stack depth should still be 1 (the non-pointer cell was not consumed)
    expect(stackDepth()).toBe(1);
  });
});

```
