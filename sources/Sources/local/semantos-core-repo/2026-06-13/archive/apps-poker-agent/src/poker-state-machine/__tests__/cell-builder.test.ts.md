---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/__tests__/cell-builder.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.799905+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/__tests__/cell-builder.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  buildCell,
  bumpCellVersion,
  deriveOwnerId,
  hexToBytes,
  POKER_HAND_TYPE_HASH,
  semanticPath,
} from '../cell-builder';
import type { HandStatePayload } from '../types';

const sampleState: HandStatePayload = {
  gameId: 'g-1',
  handNumber: 1,
  phase: 'preflop',
  dealer: 'Alice',
  players: [
    { name: 'Alice', chips: 100, folded: false, allIn: false },
    { name: 'Bob', chips: 100, folded: false, allIn: false },
  ],
  pot: 0,
  communityCards: [],
  currentBet: 10,
  actions: [],
};

describe('semanticPath', () => {
  test('1. encodes gameId + handNumber', () => {
    expect(semanticPath(sampleState)).toBe('game/poker/g-1/hand-1/state');
  });

  test('2. is byte-identical to the legacy template', () => {
    expect(semanticPath({ ...sampleState, gameId: 'XX', handNumber: 9 })).toBe(
      'game/poker/XX/hand-9/state',
    );
  });
});

describe('deriveOwnerId', () => {
  test('3. always returns 16 bytes', () => {
    expect(deriveOwnerId('any').length).toBe(16);
  });

  test('4. is deterministic for the same input', () => {
    expect(deriveOwnerId('g-1')).toEqual(deriveOwnerId('g-1'));
  });

  test('5. differs across distinct gameIds', () => {
    expect(deriveOwnerId('g-1')).not.toEqual(deriveOwnerId('g-2'));
  });
});

describe('hexToBytes', () => {
  test('6. round-trips a simple hex string', () => {
    expect(Array.from(hexToBytes('deadbeef'))).toEqual([0xde, 0xad, 0xbe, 0xef]);
  });
});

describe('buildCell', () => {
  test('7. produces non-empty cell bytes + a 32-byte content hash', async () => {
    const { cellBytes, contentHash } = await buildCell(sampleState, {
      ownerId: deriveOwnerId('g-1'),
    });
    expect(cellBytes.length).toBeGreaterThan(0);
    expect(contentHash.length).toBe(32);
  });

  test('8. version param is written into the header at offset 20', async () => {
    const { cellBytes } = await buildCell(sampleState, {
      ownerId: deriveOwnerId('g-1'),
      version: 7,
    });
    const dv = new DataView(cellBytes.buffer, cellBytes.byteOffset, cellBytes.byteLength);
    expect(dv.getUint32(20, true)).toBe(7);
  });

  test('9. same input → byte-identical cell', async () => {
    const a = await buildCell(sampleState, { ownerId: deriveOwnerId('g-1') });
    const b = await buildCell(sampleState, { ownerId: deriveOwnerId('g-1') });
    expect(a.cellBytes).toEqual(b.cellBytes);
    expect(a.contentHash).toEqual(b.contentHash);
  });
});

describe('bumpCellVersion', () => {
  test('10. patches the version field in place', async () => {
    const { cellBytes } = await buildCell(sampleState, {
      ownerId: deriveOwnerId('g-1'),
    });
    bumpCellVersion(cellBytes, 42);
    const dv = new DataView(cellBytes.buffer, cellBytes.byteOffset, cellBytes.byteLength);
    expect(dv.getUint32(20, true)).toBe(42);
  });
});

describe('POKER_HAND_TYPE_HASH', () => {
  test('11. is 32 bytes', () => {
    expect(POKER_HAND_TYPE_HASH.length).toBe(32);
  });
});

```
