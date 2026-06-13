---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/__tests__/tombstone-resolver.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.905788+00:00
---

# core/protocol-types/src/semantic-fs/__tests__/tombstone-resolver.test.ts

```ts
/**
 * tombstone-resolver tests — drives resolvePath against an
 * in-memory adapter with hand-crafted tombstone cells.
 */

import { describe, expect, test } from 'bun:test';
import { MemoryAdapter } from '../../adapters/memory-adapter';
import { resolvePath } from '../tombstone-resolver';
import { FLAGS_TOMBSTONE, MAX_REDIRECT_HOPS } from '../types';
import { CELL_SIZE, HEADER_SIZE } from '../../constants';
import { serializeCellHeader } from '../../cell-header';
import type { CellHeader } from '../../cell-header';

function header(flags = 0): CellHeader {
  return {
    magic: new Uint8Array(16),
    linearity: 1,
    version: 1,
    flags,
    refCount: 1,
    typeHash: new Uint8Array(32),
    ownerId: new Uint8Array(16),
    timestamp: 0n,
    cellCount: 1,
    totalSize: 0,
    parentHash: new Uint8Array(32),
    prevStateHash: new Uint8Array(32),
    domainPayloadRoot: new Uint8Array(32),
  };
}

function tombstoneCell(redirect: string): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);
  cell.set(serializeCellHeader(header(FLAGS_TOMBSTONE)), 0);
  const payload = new TextEncoder().encode(redirect + '\0');
  cell.set(payload, HEADER_SIZE);
  return cell;
}

function liveCell(): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);
  cell.set(serializeCellHeader(header(0)), 0);
  return cell;
}

describe('resolvePath', () => {
  test('1. returns the path unchanged when the key is missing', async () => {
    const adapter = new MemoryAdapter();
    expect(await resolvePath(adapter, 'objects/never')).toBe('objects/never');
  });

  test('2. returns the path unchanged when the cell is not a tombstone', async () => {
    const adapter = new MemoryAdapter();
    await adapter.write('objects/live', liveCell());
    expect(await resolvePath(adapter, 'objects/live')).toBe('objects/live');
  });

  test('3. follows a single tombstone redirect', async () => {
    const adapter = new MemoryAdapter();
    await adapter.write('objects/old', tombstoneCell('objects/new'));
    await adapter.write('objects/new', liveCell());
    expect(await resolvePath(adapter, 'objects/old')).toBe('objects/new');
  });

  test('4. follows a 3-hop redirect chain', async () => {
    const adapter = new MemoryAdapter();
    await adapter.write('a', tombstoneCell('b'));
    await adapter.write('b', tombstoneCell('c'));
    await adapter.write('c', liveCell());
    expect(await resolvePath(adapter, 'a')).toBe('c');
  });

  test('5. throws on redirect cycles exceeding MAX_REDIRECT_HOPS', async () => {
    const adapter = new MemoryAdapter();
    // Cycle a → b → a
    await adapter.write('a', tombstoneCell('b'));
    await adapter.write('b', tombstoneCell('a'));
    await expect(resolvePath(adapter, 'a')).rejects.toThrow(/Too many redirects/);
    expect(MAX_REDIRECT_HOPS).toBeGreaterThan(0);
  });

  test('6. empty redirect target stops the walk at the current cell', async () => {
    const adapter = new MemoryAdapter();
    await adapter.write('zombie', tombstoneCell(''));
    expect(await resolvePath(adapter, 'zombie')).toBe('zombie');
  });

  test('7. truncated cell bytes (< HEADER_SIZE) is treated as a non-tombstone', async () => {
    const adapter = new MemoryAdapter();
    await adapter.write('truncated', new Uint8Array(10));
    expect(await resolvePath(adapter, 'truncated')).toBe('truncated');
  });

  test('8. only the tombstone bit is consulted — other flag bits are ignored', async () => {
    const adapter = new MemoryAdapter();
    const cell = new Uint8Array(CELL_SIZE);
    cell.set(serializeCellHeader(header(0xfffe)), 0); // every bit set except FLAGS_TOMBSTONE
    await adapter.write('weird', cell);
    expect(await resolvePath(adapter, 'weird')).toBe('weird');
  });
});

```
