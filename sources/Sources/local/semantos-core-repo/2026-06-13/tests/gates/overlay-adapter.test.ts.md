---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/overlay-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.563538+00:00
---

# tests/gates/overlay-adapter.test.ts

```ts
/**
 * Phase 25A — OverlayAdapter tests (T16–T19).
 */

import { describe, test, expect, beforeEach } from 'bun:test';
import { MemoryAdapter } from '../../core/protocol-types/src/adapters/memory-adapter';
import { OverlayAdapter } from '../../core/protocol-types/src/adapters/overlay-adapter';

describe('Phase 25A — OverlayAdapter', () => {
  let primary: MemoryAdapter;
  let fallback: MemoryAdapter;
  let overlay: OverlayAdapter;

  beforeEach(() => {
    primary = new MemoryAdapter();
    fallback = new MemoryAdapter();
    overlay = new OverlayAdapter(primary, fallback);
  });

  // T16: read falls through from empty primary to populated fallback
  test('T16: read falls through to fallback', async () => {
    const data = new Uint8Array([1, 2, 3]);
    await fallback.write('config/default.json', data);

    const result = await overlay.read('config/default.json');
    expect(result).toEqual(data);

    // Non-existent in both returns null
    expect(await overlay.read('nope')).toBeNull();
  });

  // T17: write goes to primary, subsequent read finds it in primary
  test('T17: write goes to primary', async () => {
    const data = new Uint8Array([10, 20]);
    await overlay.write('user/data.bin', data);

    // Primary has it
    expect(await primary.read('user/data.bin')).toEqual(data);
    // Fallback does not
    expect(await fallback.read('user/data.bin')).toBeNull();
    // Overlay reads from primary
    expect(await overlay.read('user/data.bin')).toEqual(data);
  });

  // T18: list merges and deduplicates
  test('T18: list merges and deduplicates', async () => {
    await primary.write('ns/a.bin', new Uint8Array([1]));
    await primary.write('ns/b.bin', new Uint8Array([2]));
    await fallback.write('ns/b.bin', new Uint8Array([3])); // duplicate key
    await fallback.write('ns/c.bin', new Uint8Array([4]));

    const results = await overlay.list('ns');
    expect(results.sort()).toEqual(['a.bin', 'b.bin', 'c.bin']);
  });

  // T19: delete only affects primary
  test('T19: delete only affects primary', async () => {
    await primary.write('ns/x.bin', new Uint8Array([1]));
    await fallback.write('ns/x.bin', new Uint8Array([2]));

    expect(await overlay.delete('ns/x.bin')).toBe(true);
    // Primary deleted
    expect(await primary.read('ns/x.bin')).toBeNull();
    // Fallback still has it — overlay reads from fallback now
    expect(await overlay.read('ns/x.bin')).toEqual(new Uint8Array([2]));
  });
});

```
