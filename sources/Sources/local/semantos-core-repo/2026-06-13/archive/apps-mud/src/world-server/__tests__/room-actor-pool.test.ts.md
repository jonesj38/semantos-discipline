---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/__tests__/room-actor-pool.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.844248+00:00
---

# archive/apps-mud/src/world-server/__tests__/room-actor-pool.test.ts

```ts
/**
 * Tests for `room-actor-pool.ts` — pure registry behaviour.
 *
 * Uses a stub RoomActor: the pool only depends on `start()` and `stop()`,
 * never on the full actor surface. Cast through `unknown` to satisfy the
 * `RoomActor` parameter type.
 */

import { describe, test, expect } from 'bun:test';

import type { RoomActor } from '../../room-actor';
import { RoomActorPool } from '../room-actor-pool';

interface StubLifecycle {
  startCount: number;
  stopCount: number;
  start(): Promise<void>;
  stop(): void;
}

interface StubBundle {
  stub: StubLifecycle;
  actor: RoomActor;
}

function makeStubActor(): StubBundle {
  const stub: StubLifecycle = {
    startCount: 0,
    stopCount: 0,
    async start() {
      this.startCount++;
    },
    stop() {
      this.stopCount++;
    },
  };
  return { stub, actor: stub as unknown as RoomActor };
}

describe('RoomActorPool', () => {
  test('register + get round-trips an actor by roomId', () => {
    const pool = new RoomActorPool();
    const a = makeStubActor();
    pool.register('r1', a.actor);
    expect(pool.get('r1')).toBe(a.actor);
    expect(pool.has('r1')).toBe(true);
    expect(pool.size).toBe(1);
    expect(pool.ids()).toEqual(['r1']);
  });

  test('replace stops the prior actor and swaps in the new one', () => {
    const pool = new RoomActorPool();
    const a = makeStubActor();
    const b = makeStubActor();
    pool.register('r1', a.actor);
    const prev = pool.replace('r1', b.actor);
    expect(prev).toBe(a.actor);
    expect(a.stub.stopCount).toBe(1);
    expect(pool.get('r1')).toBe(b.actor);
    expect(b.stub.stopCount).toBe(0);
  });

  test('replace returns undefined when no prior actor exists', () => {
    const pool = new RoomActorPool();
    const a = makeStubActor();
    expect(pool.replace('r1', a.actor)).toBeUndefined();
    expect(pool.get('r1')).toBe(a.actor);
  });

  test('remove stops and deletes the actor', () => {
    const pool = new RoomActorPool();
    const a = makeStubActor();
    pool.register('r1', a.actor);
    expect(pool.remove('r1')).toBe(true);
    expect(a.stub.stopCount).toBe(1);
    expect(pool.has('r1')).toBe(false);
    expect(pool.remove('r1')).toBe(false); // already gone
  });

  test('startAll fires every actor.start() (fire-and-forget)', async () => {
    const pool = new RoomActorPool();
    const a = makeStubActor();
    const b = makeStubActor();
    pool.register('r1', a.actor);
    pool.register('r2', b.actor);
    pool.startAll();
    // Allow microtask queue to flush
    await Promise.resolve();
    expect(a.stub.startCount).toBe(1);
    expect(b.stub.startCount).toBe(1);
  });

  test('stopAll calls stop() on every actor', () => {
    const pool = new RoomActorPool();
    const a = makeStubActor();
    const b = makeStubActor();
    pool.register('r1', a.actor);
    pool.register('r2', b.actor);
    pool.stopAll();
    expect(a.stub.stopCount).toBe(1);
    expect(b.stub.stopCount).toBe(1);
  });

  test('ids preserves insertion order; entries iterates pairs', () => {
    const pool = new RoomActorPool();
    const a = makeStubActor();
    const b = makeStubActor();
    const c = makeStubActor();
    pool.register('r1', a.actor);
    pool.register('r2', b.actor);
    pool.register('r3', c.actor);
    expect(pool.ids()).toEqual(['r1', 'r2', 'r3']);
    const collected: [string, RoomActor][] = [];
    for (const entry of pool.entries()) collected.push(entry);
    expect(collected.map(e => e[0])).toEqual(['r1', 'r2', 'r3']);
  });
});

```
