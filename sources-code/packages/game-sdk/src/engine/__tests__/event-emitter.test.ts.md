---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/__tests__/event-emitter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.531375+00:00
---

# packages/game-sdk/src/engine/__tests__/event-emitter.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { gameEventBus } from '../event-emitter';

describe('gameEventBus', () => {
  test('1. emit + on round-trip', () => {
    const bus = gameEventBus<{ kind: string; data: number }>();
    const seen: { kind: string; data: number }[] = [];
    bus.on((e) => seen.push(e));
    bus.emit({ kind: 'tick', data: 1 });
    bus.emit({ kind: 'tick', data: 2 });
    expect(seen).toHaveLength(2);
    expect(seen[1].data).toBe(2);
  });

  test('2. distinct buses are isolated', () => {
    const a = gameEventBus<{ x: number }>();
    const b = gameEventBus<{ x: number }>();
    let aSeen = 0;
    let bSeen = 0;
    a.on(() => aSeen++);
    b.on(() => bSeen++);
    a.emit({ x: 1 });
    expect(aSeen).toBe(1);
    expect(bSeen).toBe(0);
  });

  test('3. on returns dispose', () => {
    const bus = gameEventBus<number>();
    let count = 0;
    const dispose = bus.on(() => count++);
    bus.emit(1);
    dispose();
    bus.emit(2);
    expect(count).toBe(1);
  });
});

```
