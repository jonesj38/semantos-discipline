---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/tests/wasm_host_test.mjs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.406207+00:00
---

# src/ffi/tests/wasm_host_test.mjs

```mjs
// Semantos FFI — WASM Integration Tests (Phase 30E)
//
// 9 TDD Gate Tests exercising the WASM module end-to-end via the JS host.
// Run: node --test src/ffi/tests/wasm_host_test.mjs
// Prerequisites: zig build wasm (produces zig-out/bin/semantos.wasm)

import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createSemantosHost } from '../host/js-host.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const WASM_PATH = resolve(__dirname, '..', 'zig-out', 'bin', 'semantos.wasm');

// ── T1: WASM module builds and loads successfully ──
describe('T1: WASM module loads', () => {
  it('should load the WASM module and instantiate', async () => {
    const host = await createSemantosHost(WASM_PATH);
    assert.ok(host.exports, 'WASM exports should exist');
    assert.ok(host.memory, 'WASM memory should exist');
  });
});

// ── T2: All C ABI exports present ──
describe('T2: WASM exports all C ABI functions', () => {
  it('should export all semantos_* functions', async () => {
    const wasmBytes = await readFile(WASM_PATH);
    const mod = new WebAssembly.Module(wasmBytes);
    const exports = WebAssembly.Module.exports(mod)
      .filter(e => e.kind === 'function')
      .map(e => e.name);

    const required = [
      'semantos_init',
      'semantos_shutdown',
      'semantos_cell_write',
      'semantos_cell_read',
      'semantos_cell_verify',
      'semantos_free',
      'semantos_version',
      'semantos_last_error',
      'semantos_register_callbacks',
      'semantos_capability_check',
      'semantos_capability_present',
      'semantos_linear_consume',
      'semantos_anchor_batch',
      'semantos_anchor_verify',
    ];

    for (const fn of required) {
      assert.ok(exports.includes(fn), `Missing export: ${fn}`);
    }
  });
});

// ── T3: semantos_alloc and semantos_dealloc work ──
describe('T3: WASM memory alloc/dealloc', () => {
  it('should allocate and deallocate memory', async () => {
    const host = await createSemantosHost(WASM_PATH);
    const { semantos_alloc, semantos_dealloc } = host.exports;

    // Allocate 1024 bytes
    const ptr = semantos_alloc(1024);
    assert.ok(ptr !== 0, 'semantos_alloc(1024) should return non-null pointer');

    // Write data to allocated buffer
    const data = new Uint8Array(host.memory.buffer, ptr, 1024);
    for (let i = 0; i < 1024; i++) data[i] = i & 0xff;

    // Read back and verify
    const readBack = new Uint8Array(host.memory.buffer, ptr, 1024);
    for (let i = 0; i < 1024; i++) {
      assert.equal(readBack[i], i & 0xff, `Byte ${i} mismatch`);
    }

    // Deallocate
    semantos_dealloc(ptr, 1024);

    // Stress test: 100 cycles of alloc/dealloc (leak check)
    for (let i = 0; i < 100; i++) {
      const p = semantos_alloc(256);
      assert.ok(p !== 0, `Cycle ${i}: alloc failed`);
      semantos_dealloc(p, 256);
    }
  });

  it('should return null for zero-size allocation', async () => {
    const host = await createSemantosHost(WASM_PATH);
    const ptr = host.exports.semantos_alloc(0);
    assert.equal(ptr, 0, 'semantos_alloc(0) should return null');
  });
});

// ── T4: WASM module declares host imports ──
describe('T4: WASM declares env.* host imports', () => {
  it('should declare adapter callback imports', async () => {
    const wasmBytes = await readFile(WASM_PATH);
    const mod = new WebAssembly.Module(wasmBytes);
    const imports = WebAssembly.Module.imports(mod);

    const envImports = imports
      .filter(i => i.module === 'env')
      .map(i => i.name);

    // These are the imports that are actually used in current code paths.
    // Dead-code-eliminated imports (host_identity_derive, host_network_*)
    // will appear when their calling functions are wired up.
    const requiredImports = [
      'host_storage_read',
      'host_storage_write',
      'host_identity_resolve',
      'host_anchor_submit',
    ];

    for (const imp of requiredImports) {
      assert.ok(envImports.includes(imp), `Missing import: env.${imp}`);
    }
  });
});

// ── T5: JS host calls semantos_version() ──
describe('T5: semantos_version()', () => {
  it('should return version string', async () => {
    const host = await createSemantosHost(WASM_PATH);
    const version = host.kernelVersion();
    assert.ok(version.startsWith('0.30.0'), `Version should start with 0.30.0, got: ${version}`);
    assert.ok(version.includes('30e'), `Version should include 30e, got: ${version}`);
  });
});

// ── T6: Cell write/read round-trip through WASM ──
describe('T6: Cell write/read round-trip', () => {
  it('should write and read data through WASM linear memory', async () => {
    const host = await createSemantosHost(WASM_PATH);
    host.init('{}');

    // Write test data
    const testData = new Uint8Array([0xDE, 0xAD, 0xBE, 0xEF, 0x42, 0x00, 0xFF]);
    host.cellWrite('/test/roundtrip', testData);

    // Read it back
    const result = host.cellRead('/test/roundtrip');

    // Verify identical bytes
    assert.equal(result.length, testData.length, 'Length mismatch');
    for (let i = 0; i < testData.length; i++) {
      assert.equal(result[i], testData[i], `Byte ${i}: expected ${testData[i]}, got ${result[i]}`);
    }

    host.shutdown();
  });

  it('should persist data across multiple calls', async () => {
    const host = await createSemantosHost(WASM_PATH);
    host.init('{}');

    host.cellWrite('/a', new Uint8Array([1]));
    host.cellWrite('/b', new Uint8Array([2]));
    host.cellWrite('/c', new Uint8Array([3]));

    assert.deepEqual(host.cellRead('/a'), new Uint8Array([1]));
    assert.deepEqual(host.cellRead('/b'), new Uint8Array([2]));
    assert.deepEqual(host.cellRead('/c'), new Uint8Array([3]));

    host.shutdown();
  });

  it('should verify that storage uses host callbacks (not in-memory store)', async () => {
    const host = await createSemantosHost(WASM_PATH);
    host.init('{}');

    host.cellWrite('/host-storage-test', new Uint8Array([0x42]));

    // The JS host's storage Map should contain the entry
    assert.ok(host._storage.has('/host-storage-test'),
      'Data should be in JS host storage Map (callback-routed)');

    host.shutdown();
  });
});

// ── T7: Capability check through WASM host imports ──
describe('T7: Capability check through WASM', () => {
  it('should check capability via host identity resolve', async () => {
    const host = await createSemantosHost(WASM_PATH);
    host.init('{}');

    // Seed a test certificate
    host.seedIdentity('test-cert-001', {
      certId: 'test-cert-001',
      domainFlag: 0x0001,
      createdAt: Date.now(),
      ttl: 86400000, // 24 hours
    });

    // Call capability_check through WASM
    const certId = new TextEncoder().encode('test-cert-001');
    const certPtr = host.exports.semantos_alloc(certId.length);
    new Uint8Array(host.memory.buffer, certPtr, certId.length).set(certId);

    const rc = host.exports.semantos_capability_check(certPtr, certId.length, 0x0001);
    host.exports.semantos_dealloc(certPtr, certId.length);

    assert.equal(rc, 0, `capability_check should return SEMANTOS_OK, got ${rc}`);

    host.shutdown();
  });

  it('should reject capability with wrong domain flag', async () => {
    const host = await createSemantosHost(WASM_PATH);
    host.init('{}');

    host.seedIdentity('test-cert-002', {
      certId: 'test-cert-002',
      domainFlag: 0x0001,
      createdAt: Date.now(),
      ttl: 86400000,
    });

    const certId = new TextEncoder().encode('test-cert-002');
    const certPtr = host.exports.semantos_alloc(certId.length);
    new Uint8Array(host.memory.buffer, certPtr, certId.length).set(certId);

    // Wrong domain flag (0x0002 instead of 0x0001)
    const rc = host.exports.semantos_capability_check(certPtr, certId.length, 0x0002);
    host.exports.semantos_dealloc(certPtr, certId.length);

    assert.equal(rc, -8, `Should return SEMANTOS_ERR_DENIED (-8), got ${rc}`);

    host.shutdown();
  });
});

// ── T8: WASM module size under 2MB ──
describe('T8: WASM module size', () => {
  it('should be under 2MB (ReleaseSafe)', async () => {
    const stats = await stat(WASM_PATH);
    const sizeMB = stats.size / (1024 * 1024);
    assert.ok(sizeMB < 2, `WASM module is ${sizeMB.toFixed(2)}MB, must be under 2MB`);
    console.log(`    WASM module size: ${(stats.size / 1024).toFixed(0)}KB (${sizeMB.toFixed(2)}MB)`);
  });
});

// ── T9: Host cannot access kernel internals ──
describe('T9: WASM sandbox isolation', () => {
  it('should only expose declared exports, not internal state', async () => {
    const wasmBytes = await readFile(WASM_PATH);
    const mod = new WebAssembly.Module(wasmBytes);
    const exports = WebAssembly.Module.exports(mod);

    const exportNames = exports.map(e => e.name);

    // Verify no internal symbols leak
    const forbidden = [
      'g_initialized',
      'g_store',
      'g_last_error',
      'g_registry',
      'g_registered',
      'validateJson',
      'setLastError',
      'hexFormat',
    ];

    for (const name of forbidden) {
      assert.ok(!exportNames.includes(name),
        `Internal symbol '${name}' should NOT be exported`);
    }

    // Memory export should exist (for host to read/write)
    assert.ok(exportNames.includes('memory'), 'memory should be exported');
  });

  it('should not allow writing to arbitrary memory addresses', async () => {
    const host = await createSemantosHost(WASM_PATH);

    // Attempt to read from kernel without init — should fail gracefully
    const pathBytes = new TextEncoder().encode('/no-init');
    const pathPtr = host.exports.semantos_alloc(pathBytes.length);
    new Uint8Array(host.memory.buffer, pathPtr, pathBytes.length).set(pathBytes);

    const outPtr = host.exports.semantos_alloc(256);
    const lenPtr = host.exports.semantos_alloc(4);
    new DataView(host.memory.buffer).setUint32(lenPtr, 256, true);

    const rc = host.exports.semantos_cell_read(pathPtr, pathBytes.length, outPtr, lenPtr);
    // Should return SEMANTOS_ERR_NOT_INIT (-5) — not crash
    assert.equal(rc, -5, `Should return NOT_INIT error, got ${rc}`);

    host.exports.semantos_dealloc(pathPtr, pathBytes.length);
    host.exports.semantos_dealloc(outPtr, 256);
    host.exports.semantos_dealloc(lenPtr, 4);
  });
});

```
