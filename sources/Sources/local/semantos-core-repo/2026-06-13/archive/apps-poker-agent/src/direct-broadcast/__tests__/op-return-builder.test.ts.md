---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/__tests__/op-return-builder.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.807984+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/__tests__/op-return-builder.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { buildPokerCell, POKER_HAND_TYPE_HASH } from '../op-return-builder';

describe('buildPokerCell', () => {
  test('1. semantic path follows game/poker/<id>/hand-<n>/state', async () => {
    const r = await buildPokerCell('g-1', 7, 'preflop', { foo: 1 });
    expect(r.semanticPath).toBe('game/poker/g-1/hand-7/state');
  });

  test('2. produces a non-empty cell + 32-byte content hash', async () => {
    const r = await buildPokerCell('g-1', 1, 'preflop', {});
    expect(r.cellBytes.length).toBeGreaterThan(0);
    expect(r.contentHash.length).toBe(32);
  });

  test('3. version > 1 patches the header at offset 20', async () => {
    const r = await buildPokerCell('g-1', 1, 'flop', {}, 5);
    const dv = new DataView(r.cellBytes.buffer, r.cellBytes.byteOffset, r.cellBytes.byteLength);
    expect(dv.getUint32(20, true)).toBe(5);
  });

  test('4. same input → byte-identical cell + content hash', async () => {
    const a = await buildPokerCell('g-1', 1, 'preflop', { x: 1 });
    const b = await buildPokerCell('g-1', 1, 'preflop', { x: 1 });
    expect(a.cellBytes).toEqual(b.cellBytes);
    expect(a.contentHash).toEqual(b.contentHash);
  });

  test('5. POKER_HAND_TYPE_HASH is 32 bytes and stable', () => {
    expect(POKER_HAND_TYPE_HASH.length).toBe(32);
  });
});

```
