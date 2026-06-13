---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/capability_compat.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.988110+00:00
---

# core/cell-engine/tests-bun/capability_compat.test.ts

```ts
// Phase 5: Capability compatibility tests — capability scripts through WASM
// Tests kernel_verify_capability export in both profiles.

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

  const kernelInit = getExport<() => number>('kernel_init');
  kernelInit();
});

describe('Phase 5: capability export exists', () => {
  test('kernel_verify_capability exists', () => {
    expect(instance.exports.kernel_verify_capability).toBeDefined();
  });
});

describe('Phase 5: capability verification through WASM', () => {
  test('OP_TRUE capability script succeeds', () => {
    const verifyCapability = getExport<(
      lockPtr: number, lockLen: number,
      pubkeyPtr: number, capType: number,
      domainFlag: number, currentTime: number
    ) => number>('kernel_verify_capability');

    // Write OP_TRUE (0x51) locking script into WASM memory
    const lockOffset = 4096;
    new Uint8Array(memory.buffer, lockOffset, 1).set([0x51]); // OP_TRUE

    // Write a dummy 33-byte compressed pubkey
    const pubkeyOffset = lockOffset + 256;
    const pubkey = new Uint8Array(memory.buffer, pubkeyOffset, 33);
    pubkey[0] = 0x02; // compressed pubkey prefix
    pubkey.fill(0xAA, 1, 33);

    const result = verifyCapability(
      lockOffset, 1,     // lock script: OP_TRUE
      pubkeyOffset,      // owner pubkey
      0,                 // capType: RECOVERY
      0x01,              // domainFlag: well_known
      1000,              // currentTime
    );
    expect(result).toBe(0); // valid
  });

  test('OP_FALSE capability script fails', () => {
    const verifyCapability = getExport<(
      lockPtr: number, lockLen: number,
      pubkeyPtr: number, capType: number,
      domainFlag: number, currentTime: number
    ) => number>('kernel_verify_capability');

    // Write OP_FALSE (0x00) locking script
    const lockOffset = 4096;
    new Uint8Array(memory.buffer, lockOffset, 1).set([0x00]); // OP_FALSE

    const pubkeyOffset = lockOffset + 256;
    const pubkey = new Uint8Array(memory.buffer, pubkeyOffset, 33);
    pubkey[0] = 0x02;
    pubkey.fill(0xBB, 1, 33);

    const result = verifyCapability(
      lockOffset, 1,
      pubkeyOffset,
      1,           // PERMISSION
      0x01,
      2000,
    );
    expect(result).toBeLessThan(0); // failed
  });

  test('multiple sequential capability verifications work', () => {
    const verifyCapability = getExport<(
      lockPtr: number, lockLen: number,
      pubkeyPtr: number, capType: number,
      domainFlag: number, currentTime: number
    ) => number>('kernel_verify_capability');

    const lockOffset = 4096;
    const pubkeyOffset = lockOffset + 256;

    // Setup pubkey once
    const pubkey = new Uint8Array(memory.buffer, pubkeyOffset, 33);
    pubkey[0] = 0x02;
    pubkey.fill(0xCC, 1, 33);

    // First: OP_TRUE should succeed
    new Uint8Array(memory.buffer, lockOffset, 1).set([0x51]);
    expect(verifyCapability(lockOffset, 1, pubkeyOffset, 0, 0x01, 100)).toBe(0);

    // Second: OP_FALSE should fail
    new Uint8Array(memory.buffer, lockOffset, 1).set([0x00]);
    expect(verifyCapability(lockOffset, 1, pubkeyOffset, 0, 0x01, 200)).toBeLessThan(0);

    // Third: OP_TRUE should succeed again (engine resets correctly)
    new Uint8Array(memory.buffer, lockOffset, 1).set([0x51]);
    expect(verifyCapability(lockOffset, 1, pubkeyOffset, 0, 0x01, 300)).toBe(0);
  });

  test('all 6 capability types work with OP_TRUE script', () => {
    const verifyCapability = getExport<(
      lockPtr: number, lockLen: number,
      pubkeyPtr: number, capType: number,
      domainFlag: number, currentTime: number
    ) => number>('kernel_verify_capability');

    const lockOffset = 4096;
    new Uint8Array(memory.buffer, lockOffset, 1).set([0x51]); // OP_TRUE

    const pubkeyOffset = lockOffset + 256;
    const pubkey = new Uint8Array(memory.buffer, pubkeyOffset, 33);
    pubkey[0] = 0x02;
    pubkey.fill(0xDD, 1, 33);

    // CapabilityType: RECOVERY=0, PERMISSION=1, DATA_ACCESS=2,
    // COMPUTE_DELEGATION=3, METERED_ACCESS=4, TRANSFER=5
    for (let capType = 0; capType <= 5; capType++) {
      const result = verifyCapability(lockOffset, 1, pubkeyOffset, capType, 0x01, 1000);
      expect(result).toBe(0);
    }
  });
});

```
