---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/memory-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.572670+00:00
---

# tests/gates/memory-adapter.test.ts

```ts
/**
 * Phase 25A — MemoryAdapter tests (T1–T7).
 */

import { describe, test, expect, beforeEach } from 'bun:test';
import { createHash } from 'crypto';
import { MemoryAdapter } from '../../core/protocol-types/src/adapters/memory-adapter';
import type { StorageEvent } from '../../core/protocol-types/src/storage';

function sha256(data: Uint8Array): string {
  return createHash('sha256').update(data).digest('hex');
}

describe('Phase 25A — MemoryAdapter', () => {
  let adapter: MemoryAdapter;

  beforeEach(() => {
    adapter = new MemoryAdapter();
  });

  // T1: write then read round-trips bytes
  test('T1: write then read round-trips bytes', async () => {
    const data = new Uint8Array([1, 2, 3, 4, 5]);
    await adapter.write('test/key', data);
    const result = await adapter.read('test/key');
    expect(result).toEqual(data);
  });

  // T2: read non-existent key returns null
  test('T2: read non-existent key returns null', async () => {
    const result = await adapter.read('does/not/exist');
    expect(result).toBeNull();
  });

  // T3: exists returns true/false correctly
  test('T3: exists returns true/false correctly', async () => {
    expect(await adapter.exists('test/key')).toBe(false);
    await adapter.write('test/key', new Uint8Array([42]));
    expect(await adapter.exists('test/key')).toBe(true);
  });

  // T4: list returns keys under prefix with prefix stripped
  test('T4: list returns keys under prefix with prefix stripped', async () => {
    await adapter.write('data/a.bin', new Uint8Array([1]));
    await adapter.write('data/sub/b.bin', new Uint8Array([2]));
    await adapter.write('other/c.bin', new Uint8Array([3]));

    const results = await adapter.list('data');
    expect(results.sort()).toEqual(['a.bin', 'sub/b.bin']);
  });

  // T5: delete returns true when key exists, false when not
  test('T5: delete returns true/false correctly', async () => {
    await adapter.write('test/key', new Uint8Array([1]));
    expect(await adapter.delete('test/key')).toBe(true);
    expect(await adapter.delete('test/key')).toBe(false);
    expect(await adapter.exists('test/key')).toBe(false);
  });

  // T6: stat returns correct size and contentHash
  test('T6: stat returns correct size and contentHash', async () => {
    const data = new Uint8Array([10, 20, 30]);
    await adapter.write('test/key', data);
    const info = await adapter.stat('test/key');
    expect(info).not.toBeNull();
    expect(info!.size).toBe(3);
    expect(info!.contentHash).toBe(sha256(data));
    expect(info!.modifiedAt).toBeGreaterThan(0);

    // Non-existent key
    expect(await adapter.stat('nope')).toBeNull();
  });

  // T7: watch fires on write, fires on delete, unsubscribe stops events
  test('T7: watch fires on write and delete, unsubscribe works', async () => {
    const events: StorageEvent[] = [];
    const unsub = adapter.watch!('test', (e) => events.push(e));

    const data = new Uint8Array([1, 2, 3]);
    await adapter.write('test/a', data);
    expect(events).toHaveLength(1);
    expect(events[0].type).toBe('write');
    expect(events[0].key).toBe('test/a');
    expect(events[0].contentHash).toBe(sha256(data));

    await adapter.delete('test/a');
    expect(events).toHaveLength(2);
    expect(events[1].type).toBe('delete');

    // Unrelated prefix should not fire
    await adapter.write('other/b', new Uint8Array([4]));
    expect(events).toHaveLength(2);

    // Unsubscribe stops events
    unsub();
    await adapter.write('test/c', new Uint8Array([5]));
    expect(events).toHaveLength(2);
  });
});

```
