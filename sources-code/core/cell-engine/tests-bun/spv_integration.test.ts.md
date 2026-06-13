---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/spv_integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.989292+00:00
---

# core/cell-engine/tests-bun/spv_integration.test.ts

```ts
// Phase 5: SPV integration tests — BEEF/BUMP verification through WASM boundary
// These tests use the full profile WASM binary (with BSVZ).

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

  // Initialize the kernel
  const kernelInit = getExport<() => number>('kernel_init');
  kernelInit();
});

describe('Phase 5: SPV exports exist', () => {
  test('kernel_beef_version exists', () => {
    expect(instance.exports.kernel_beef_version).toBeDefined();
  });

  test('kernel_verify_beef exists', () => {
    expect(instance.exports.kernel_verify_beef).toBeDefined();
  });

  test('kernel_verify_bump exists', () => {
    expect(instance.exports.kernel_verify_bump).toBeDefined();
  });
});

describe('Phase 5: BEEF version detection through WASM', () => {
  test('detects BEEF V1 magic', () => {
    const beefVersion = getExport<(ptr: number, len: number) => number>('kernel_beef_version');
    // Write BEEF V1 magic (0x0100BEEF LE) + 1 byte structure into WASM memory
    const offset = 1024;
    const view = new Uint8Array(memory.buffer, offset, 5);
    view.set([0xEF, 0xBE, 0x00, 0x01, 0x00]); // magic + nBUMPs byte
    expect(beefVersion(offset, 5)).toBe(1);
  });

  test('detects BEEF V2 magic', () => {
    const beefVersion = getExport<(ptr: number, len: number) => number>('kernel_beef_version');
    const offset = 1024;
    const view = new Uint8Array(memory.buffer, offset, 5);
    view.set([0xEF, 0xBE, 0x00, 0x02, 0x00]); // magic + nBUMPs byte
    expect(beefVersion(offset, 5)).toBe(2);
  });

  test('detects Atomic BEEF magic', () => {
    const beefVersion = getExport<(ptr: number, len: number) => number>('kernel_beef_version');
    const offset = 1024;
    const view = new Uint8Array(memory.buffer, offset, 5);
    view.set([0x01, 0x01, 0x01, 0x01, 0x00]); // magic + version byte
    expect(beefVersion(offset, 5)).toBe(3);
  });

  test('rejects magic-only data (no structure)', () => {
    const beefVersion = getExport<(ptr: number, len: number) => number>('kernel_beef_version');
    const offset = 1024;
    const view = new Uint8Array(memory.buffer, offset, 4);
    view.set([0xEF, 0xBE, 0x00, 0x01]); // only 4 bytes — no structure
    expect(beefVersion(offset, 4)).toBe(-1); // invalid
  });

  test('returns -1 for invalid magic', () => {
    const beefVersion = getExport<(ptr: number, len: number) => number>('kernel_beef_version');
    const offset = 1024;
    const view = new Uint8Array(memory.buffer, offset, 4);
    view.set([0xDE, 0xAD, 0xBE, 0xEF]);
    expect(beefVersion(offset, 4)).toBe(-1);
  });

  test('returns -1 for too-short data', () => {
    const beefVersion = getExport<(ptr: number, len: number) => number>('kernel_beef_version');
    const offset = 1024;
    expect(beefVersion(offset, 2)).toBe(-1);
  });
});

describe('Phase 5: BEEF/BUMP verification error handling', () => {
  test('kernel_verify_beef rejects garbage data', () => {
    const verifyBeef = getExport<(ptr: number, len: number, txidPtr: number) => number>('kernel_verify_beef');
    const offset = 2048;
    const view = new Uint8Array(memory.buffer, offset, 32);
    // Write garbage — not a valid BEEF
    view.fill(0xFF);
    const txidOffset = offset + 64;
    new Uint8Array(memory.buffer, txidOffset, 32).fill(0x00);

    const result = verifyBeef(offset, 32, txidOffset);
    expect(result).toBeLessThan(0); // should be negative error code
  });
});

```
