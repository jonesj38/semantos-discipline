---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/hostcall_integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.987546+00:00
---

# core/cell-engine/tests-bun/hostcall_integration.test.ts

```ts
// Phase 25.5 Gate Tests: OP_CALLHOST WASM Integration (D25.5.1 + end-to-end)
// Tests that OP_CALLHOST (0xD0) dispatches through WASM to the TS registry.

import { describe, test, expect, beforeAll } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { createHostFunctions, HostFunctionRegistry } from '../bindings/host-functions';
import { registerBuiltinHostFunctions } from '../bindings/builtin-host-functions';

const WASM_PATH = join(__dirname, '..', 'zig-out', 'bin', 'cell-engine.wasm');

let instance: WebAssembly.Instance;
let registry: HostFunctionRegistry;

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
  registry = new HostFunctionRegistry();
  registerBuiltinHostFunctions(registry);

  const wasmBytes = readFileSync(WASM_PATH);
  let currentInstance: WebAssembly.Instance | null = null;
  const memProxy = new MemoryProxy(() => currentInstance);

  const result = await WebAssembly.instantiate(wasmBytes, {
    host: createHostFunctions(memProxy as any, undefined, undefined, registry),
  });
  instance = result.instance;
  currentInstance = instance;

  const kernelInit = getExport<() => number>('kernel_init');
  kernelInit();
});

/**
 * Helper: build a script that pushes a string then executes OP_CALLHOST (0xD0).
 * Script: [len] [name_bytes...] [0xD0]
 */
function buildHostCallScript(name: string): Uint8Array {
  const encoder = new TextEncoder();
  const nameBytes = encoder.encode(name);
  // push-data: [length_byte] [data...]  then 0xD0
  const script = new Uint8Array(1 + nameBytes.length + 1);
  script[0] = nameBytes.length;
  script.set(nameBytes, 1);
  script[1 + nameBytes.length] = 0xD0;
  return script;
}

/**
 * Helper: load and execute a lock script, return whether top-of-stack is truthy.
 */
function executeScript(script: Uint8Array): boolean {
  const kernelReset = getExport<() => void>('kernel_reset');
  const kernelLoadScript = getExport<(ptr: number, len: number) => number>('kernel_load_script');
  const kernelExecute = getExport<() => number>('kernel_execute');
  const memory = instance.exports.memory as WebAssembly.Memory;

  kernelReset();

  // Write script to WASM memory (use a high offset to avoid conflicts)
  const scriptOffset = 0x10000;
  new Uint8Array(memory.buffer, scriptOffset, script.length).set(script);
  kernelLoadScript(scriptOffset, script.length);

  return kernelExecute() === 0; // 0 = success (truthy top of stack)
}

describe('D25.5.1 — OP_CALLHOST opcode via WASM', () => {
  test('push function name + OP_CALLHOST dispatches to registered function', () => {
    registry.register('always-true', () => 1);
    registry.setContext({});
    const script = buildHostCallScript('always-true');
    expect(executeScript(script)).toBe(true);
  });

  test('host function result is pushed to main stack (truthy/falsy)', () => {
    registry.register('always-false', () => 0);
    registry.setContext({});
    const script = buildHostCallScript('always-false');
    expect(executeScript(script)).toBe(false);
  });

  test('host function receives frozen context', () => {
    let receivedCtx: Record<string, unknown> = {};
    registry.register('capture-ctx', (ctx) => {
      receivedCtx = ctx as Record<string, unknown>;
      return 1;
    });
    registry.setContext({ board: 'chess', turn: 'white' });
    const script = buildHostCallScript('capture-ctx');
    executeScript(script);
    expect(receivedCtx.board).toBe('chess');
    expect(receivedCtx.turn).toBe('white');
    // Verify frozen
    expect(Object.isFrozen(receivedCtx)).toBe(true);
  });
});

describe('D25.5 — End-to-end policy evaluation', () => {
  test('same script, different context → different result', () => {
    registry.register('is-admin?', (ctx) => (ctx.role === 'admin' ? 1 : 0));

    registry.setContext({ role: 'admin' });
    expect(executeScript(buildHostCallScript('is-admin?'))).toBe(true);

    registry.setContext({ role: 'user' });
    expect(executeScript(buildHostCallScript('is-admin?'))).toBe(false);
  });

  test('OP_CALLHOST without registered function fails gracefully', () => {
    // Unregister everything is tricky — just call a name that's not registered
    registry.setContext({});
    // Script calls a nonexistent function — should error (unknown_host_function)
    // The executor returns error, so kernel_execute returns error code
    const script = buildHostCallScript('nonexistent-function-xyz');
    // This should NOT return true
    expect(executeScript(script)).toBe(false);
  });
});

describe('D25.5 — Backward compatibility', () => {
  test('existing host functions without registry work (no OP_CALLHOST used)', () => {
    // Simple script: push 1 → top of stack is truthy
    const script = new Uint8Array([0x01, 0x01]); // push 1 byte: 0x01
    expect(executeScript(script)).toBe(true);
  });

  test('standard opcodes still work alongside OP_CALLHOST', () => {
    // push 5, push 3, OP_ADD (0x93) — result should be 8 (truthy)
    const script = new Uint8Array([
      0x01, 0x05, // push 5
      0x01, 0x03, // push 3
      0x93,       // OP_ADD
    ]);
    expect(executeScript(script)).toBe(true);
  });
});

```
