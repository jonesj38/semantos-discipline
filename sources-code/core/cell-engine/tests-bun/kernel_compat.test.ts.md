---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/kernel_compat.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.990683+00:00
---

# core/cell-engine/tests-bun/kernel_compat.test.ts

```ts
// Phase 3: Cross-language kernel tests
// Verifies WASM exports match PlexusKernelWasm interface

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

// Wrapper that lazily reads memory from the WASM instance
// This handles the case where memory.buffer gets detached on grow
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

describe('kernel exports exist', () => {
  test('kernel_init exists', () => {
    expect(instance.exports.kernel_init).toBeDefined();
  });

  test('kernel_reset exists', () => {
    expect(instance.exports.kernel_reset).toBeDefined();
  });

  test('kernel_load_script exists', () => {
    expect(instance.exports.kernel_load_script).toBeDefined();
  });

  test('kernel_load_unlock exists', () => {
    expect(instance.exports.kernel_load_unlock).toBeDefined();
  });

  test('kernel_execute exists', () => {
    expect(instance.exports.kernel_execute).toBeDefined();
  });

  test('kernel_get_opcount exists', () => {
    expect(instance.exports.kernel_get_opcount).toBeDefined();
  });

  test('kernel_stack_depth exists', () => {
    expect(instance.exports.kernel_stack_depth).toBeDefined();
  });

  test('kernel_step exists', () => {
    expect(instance.exports.kernel_step).toBeDefined();
  });

  test('kernel_get_pc exists', () => {
    expect(instance.exports.kernel_get_pc).toBeDefined();
  });

  test('kernel_get_current_op exists', () => {
    expect(instance.exports.kernel_get_current_op).toBeDefined();
  });

  test('kernel_alt_stack_depth exists', () => {
    expect(instance.exports.kernel_alt_stack_depth).toBeDefined();
  });

  test('kernel_load_tx_context exists', () => {
    expect(instance.exports.kernel_load_tx_context).toBeDefined();
  });
});

describe('kernel execution', () => {
  test('kernel_init returns 0 on success', () => {
    const init = getExport<() => number>('kernel_init');
    expect(init()).toBe(0);
  });

  test('kernel_load_script + kernel_execute runs OP_1 OP_1 OP_ADD', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');
    const stackDepth = getExport<() => number>('kernel_stack_depth');
    const getOpcount = getExport<() => number>('kernel_get_opcount');

    init();
    reset();

    // Write script to WASM memory: OP_1 OP_1 OP_ADD = 0x51 0x51 0x93
    const scriptPtr = 0x100000; // arbitrary offset in linear memory
    const memView = new Uint8Array(memory.buffer);
    memView[scriptPtr] = 0x51;     // OP_1
    memView[scriptPtr + 1] = 0x51; // OP_1
    memView[scriptPtr + 2] = 0x93; // OP_ADD

    const loadResult = loadScript(scriptPtr, 3);
    expect(loadResult).toBe(0);

    const execResult = execute();
    expect(execResult).toBe(0); // success (truthy top = 2)

    expect(getOpcount()).toBe(3);
    expect(stackDepth()).toBe(1);
  });

  test('kernel_execute with OP_0 returns verify_failed (falsy)', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');

    init();
    reset();

    const scriptPtr = 0x100000;
    const memView = new Uint8Array(memory.buffer);
    memView[scriptPtr] = 0x00; // OP_0

    loadScript(scriptPtr, 1);
    const result = execute();
    expect(result).toBe(6); // verify_failed (KernelError code)
  });

  test('kernel_reset clears all state', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const execute = getExport<() => number>('kernel_execute');
    const stackDepth = getExport<() => number>('kernel_stack_depth');
    const getOpcount = getExport<() => number>('kernel_get_opcount');

    init();

    // Execute a script first
    const scriptPtr = 0x100000;
    const memView = new Uint8Array(memory.buffer);
    memView[scriptPtr] = 0x51; // OP_1
    loadScript(scriptPtr, 1);
    execute();
    expect(stackDepth()).toBe(1);

    // Reset
    reset();
    expect(stackDepth()).toBe(0);
    expect(getOpcount()).toBe(0);
  });

  test('unlock + lock script: P2PK-like pattern', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const execute = getExport<() => number>('kernel_execute');

    init();
    reset();

    const memView = new Uint8Array(memory.buffer);

    // Unlock: OP_5 (push 5)
    const unlockPtr = 0x100000;
    memView[unlockPtr] = 0x55; // OP_5
    loadUnlock(unlockPtr, 1);

    // Lock: OP_5 OP_NUMEQUAL (push 5, compare)
    const lockPtr = 0x101000;
    memView[lockPtr] = 0x55;     // OP_5
    memView[lockPtr + 1] = 0x9C; // OP_NUMEQUAL
    loadScript(lockPtr, 2);

    const result = execute();
    expect(result).toBe(0); // success
  });
});

describe('SIGHASH pipeline', () => {
  test('kernel_load_tx_context succeeds with minimal transaction', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadTxCtx = getExport<(ptr: number, len: number, idx: number, val: bigint) => number>('kernel_load_tx_context');

    init();
    reset();

    // Minimal BSV transaction: version(4) + 1 input + 1 output + locktime(4)
    // Input: prev_txid(32) + prev_vout(4) + scriptLen(1=0) + nSequence(4)
    // Output: value(8) + scriptLen(1) + script(1)
    const tx = new Uint8Array([
      // version (1, LE)
      0x01, 0x00, 0x00, 0x00,
      // input count (1)
      0x01,
      // prev_txid (32 bytes of 0xAA)
      ...new Array(32).fill(0xAA),
      // prev_vout (0, LE)
      0x00, 0x00, 0x00, 0x00,
      // scriptSig length (0 = empty)
      0x00,
      // nSequence (0xFFFFFFFF)
      0xFF, 0xFF, 0xFF, 0xFF,
      // output count (1)
      0x01,
      // value (10000 sats, LE)
      0x10, 0x27, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      // script length (1)
      0x01,
      // script (OP_1 = 0x51)
      0x51,
      // locktime (0)
      0x00, 0x00, 0x00, 0x00,
    ]);

    const txPtr = 0x100000;
    const memView = new Uint8Array(memory.buffer);
    memView.set(tx, txPtr);

    const result = loadTxCtx(txPtr, tx.length, 0, BigInt(50000));
    expect(result).toBe(0); // success
  });

  test('OP_CHECKSIG with tx context does not crash (smoke test)', () => {
    const init = getExport<() => number>('kernel_init');
    const reset = getExport<() => void>('kernel_reset');
    const loadTxCtx = getExport<(ptr: number, len: number, idx: number, val: bigint) => number>('kernel_load_tx_context');
    const loadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
    const loadUnlock = getExport<(ptr: number, len: number) => number>('kernel_load_unlock');
    const execute = getExport<() => number>('kernel_execute');

    init();
    reset();

    const memView = new Uint8Array(memory.buffer);

    // Load a minimal transaction
    const tx = new Uint8Array([
      0x01, 0x00, 0x00, 0x00, // version
      0x01, // 1 input
      ...new Array(32).fill(0xAA), // prev_txid
      0x00, 0x00, 0x00, 0x00, // prev_vout
      0x00, // empty scriptSig
      0xFF, 0xFF, 0xFF, 0xFF, // nSequence
      0x01, // 1 output
      0x10, 0x27, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // value
      0x01, 0x51, // script: OP_1
      0x00, 0x00, 0x00, 0x00, // locktime
    ]);
    const txPtr = 0x100000;
    memView.set(tx, txPtr);
    loadTxCtx(txPtr, tx.length, 0, BigInt(50000));

    // Lock script: OP_CHECKSIG (0xAC)
    const lockPtr = 0x101000;
    memView[lockPtr] = 0xAC; // OP_CHECKSIG
    loadScript(lockPtr, 1);

    // Unlock script: push fake sig (with SIGHASH_ALL|FORKID = 0x41) + push fake pubkey
    // sig: 0x30 (DER marker) + 0x41 (sighash type) = 2 bytes
    // pubkey: 33 bytes (compressed, starts with 0x02)
    const unlockPtr = 0x102000;
    let off = unlockPtr;
    // Push 2-byte signature: PUSH2 sig_byte sighash_byte
    memView[off++] = 0x02; // OP_PUSHBYTES_2
    memView[off++] = 0x30; // fake DER byte
    memView[off++] = 0x41; // SIGHASH_ALL|FORKID
    // Push 33-byte pubkey
    memView[off++] = 0x21; // OP_PUSHBYTES_33
    memView[off] = 0x02; // compressed pubkey prefix
    // rest is zeros (invalid but won't crash)
    loadUnlock(unlockPtr, off - unlockPtr + 33);

    // Execute — should NOT crash. Signature verification will fail
    // (host_checksig stub returns 0), so result will be verify_failed (6)
    const result = execute();
    expect(result).toBe(6); // verify_failed (sig is fake, but no crash)
  });
});

describe('WASM binary', () => {
  test('WASM binary size is under 500KB', () => {
    const wasmBytes = readFileSync(WASM_PATH);
    expect(wasmBytes.length).toBeLessThan(500 * 1024);
  });
});

```
