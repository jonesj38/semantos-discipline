---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/__tests__/host-imports.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.833547+00:00
---

# core/cell-ops/src/wasm/__tests__/host-imports.test.ts

```ts
import { describe, expect, test } from 'bun:test';

import { createNoopHostImports } from '../host-imports';

function fakeMemory(size = 256) {
  return { buffer: new ArrayBuffer(size) };
}

describe('createNoopHostImports', () => {
  test('returns a valid PlexusKernelHostImports shape', () => {
    const mem = fakeMemory();
    const imports = createNoopHostImports(mem);
    expect(typeof imports.host_sha256).toBe('function');
    expect(typeof imports.host_hash160).toBe('function');
    expect(typeof imports.host_hash256).toBe('function');
    expect(typeof imports.host_checksig).toBe('function');
    expect(typeof imports.host_checkmultisig).toBe('function');
    expect(typeof imports.host_get_blocktime).toBe('function');
    expect(typeof imports.host_get_sequence).toBe('function');
    expect(typeof imports.host_log).toBe('function');
    expect(typeof imports.host_fetch_cell).toBe('function');
  });

  test('hash functions zero their output region', () => {
    const mem = fakeMemory();
    new Uint8Array(mem.buffer).fill(0xff); // poison
    const imports = createNoopHostImports(mem);
    imports.host_sha256(0, 0, 0);
    expect(Array.from(new Uint8Array(mem.buffer, 0, 32))).toEqual(
      new Array(32).fill(0),
    );

    new Uint8Array(mem.buffer).fill(0xff);
    imports.host_hash160(0, 0, 64);
    expect(Array.from(new Uint8Array(mem.buffer, 64, 20))).toEqual(
      new Array(20).fill(0),
    );

    new Uint8Array(mem.buffer).fill(0xff);
    imports.host_hash256(0, 0, 96);
    expect(Array.from(new Uint8Array(mem.buffer, 96, 32))).toEqual(
      new Array(32).fill(0),
    );
  });

  test('checksig + checkmultisig always return 1', () => {
    const imports = createNoopHostImports(fakeMemory());
    expect(imports.host_checksig(0, 0, 0, 0, 0, 0)).toBe(1);
    expect(imports.host_checkmultisig(0, 0, 0, 0, 0, 0, 0)).toBe(1);
  });

  test('host_get_blocktime returns a recent epoch second', () => {
    const imports = createNoopHostImports(fakeMemory());
    const before = Math.floor(Date.now() / 1000);
    const blocktime = imports.host_get_blocktime();
    const after = Math.floor(Date.now() / 1000);
    expect(blocktime).toBeGreaterThanOrEqual(before);
    expect(blocktime).toBeLessThanOrEqual(after);
  });

  test('host_get_sequence returns 0', () => {
    const imports = createNoopHostImports(fakeMemory());
    expect(imports.host_get_sequence()).toBe(0);
  });

  test('host_fetch_cell returns 0 (failure)', () => {
    const imports = createNoopHostImports(fakeMemory());
    expect(imports.host_fetch_cell(0, 0, 0, 0)).toBe(0);
  });

  test('host_log is a no-op (does not throw)', () => {
    const imports = createNoopHostImports(fakeMemory());
    expect(() => imports.host_log(0, 0)).not.toThrow();
  });
});

```
