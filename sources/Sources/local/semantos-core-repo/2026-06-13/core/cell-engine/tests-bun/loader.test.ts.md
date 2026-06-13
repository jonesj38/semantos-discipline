---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/loader.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.990419+00:00
---

# core/cell-engine/tests-bun/loader.test.ts

```ts
/**
 * Tests for the Bun WASM loader (D7.2).
 */

import { describe, test, expect } from 'bun:test';
import { loadCellEngine } from '../bindings/bun/loader';
import { CellEngine } from '../bindings/bun/cell-engine';

describe('Bun loader', () => {
  test('loadCellEngine() returns CellEngine with full profile', async () => {
    const engine = await loadCellEngine();
    expect(engine).toBeInstanceOf(CellEngine);
    expect(engine.profile).toBe('full');
    expect(engine.memory).toBeDefined();
  });

  test('loadCellEngine({ profile: "embedded" }) returns CellEngine with embedded profile', async () => {
    const engine = await loadCellEngine({ profile: 'embedded' });
    expect(engine).toBeInstanceOf(CellEngine);
    expect(engine.profile).toBe('embedded');
  });

  test('missing WASM file throws descriptive error', async () => {
    await expect(
      loadCellEngine({ wasmPath: '/nonexistent/path/to/engine.wasm' })
    ).rejects.toThrow();
  });

  test('full profile has SPV exports', async () => {
    const engine = await loadCellEngine();
    // SPV methods should not throw on full profile (even with garbage data they return results)
    const result = engine.beefVersion(new Uint8Array([0x01, 0x02, 0x03, 0x04]));
    expect(result).toBeDefined();
    expect(typeof result.version).toBe('number');
  });

  test('embedded profile throws on SPV methods', async () => {
    const engine = await loadCellEngine({ profile: 'embedded' });
    expect(() => engine.verifyBEEF(new Uint8Array(10), new Uint8Array(32))).toThrow(
      'SPV not available in embedded profile'
    );
    expect(() => engine.beefVersion(new Uint8Array(10))).toThrow(
      'SPV not available in embedded profile'
    );
  });
});

```
