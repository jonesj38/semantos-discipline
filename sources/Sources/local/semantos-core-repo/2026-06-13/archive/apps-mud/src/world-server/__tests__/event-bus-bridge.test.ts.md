---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/__tests__/event-bus-bridge.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.845402+00:00
---

# archive/apps-mud/src/world-server/__tests__/event-bus-bridge.test.ts

```ts
/**
 * Tests for `event-bus-bridge.ts`.
 *
 * Stub RoomActor surface: only `onEvent` (and the lifecycle no-ops the
 * pool requires). Cast through `unknown`.
 */

import { describe, test, expect } from 'bun:test';

import type { RoomActor } from '../../room-actor';
import type { PlayerSession, RoomEvent } from '../../types';
import { EventBusBridge } from '../event-bus-bridge';
import { PlayerSessionStore } from '../player-session-store';
import { RoomActorPool } from '../room-actor-pool';

interface StubActor {
  listeners: Set<(e: RoomEvent) => void>;
  emit(e: RoomEvent): void;
  onEvent(listener: (e: RoomEvent) => void): () => void;
  start(): Promise<void>;
  stop(): void;
}

interface StubBundle {
  stub: StubActor;
  actor: RoomActor;
}

function makeStubActor(): StubBundle {
  const listeners = new Set<(e: RoomEvent) => void>();
  const stub: StubActor = {
    listeners,
    emit(e: RoomEvent) {
      for (const l of listeners) l(e);
    },
    onEvent(l: (e: RoomEvent) => void) {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    async start() {},
    stop() {},
  };
  return { stub, actor: stub as unknown as RoomActor };
}

function bindPlayer(
  sessions: PlayerSessionStore,
  roomId: string,
): PlayerSession {
  const sessionId = sessions.mintSessionId();
  const s: PlayerSession = {
    sessionId,
    playerId: sessions.playerIdFor(sessionId),
    playerName: 'p',
    currentRoomId: roomId,
    connectedAt: 0,
  };
  sessions.bind(s);
  return s;
}

describe('EventBusBridge', () => {
  test('subscribe routes events from the player\'s current room', () => {
    const pool = new RoomActorPool();
    const sessions = new PlayerSessionStore();
    const bridge = new EventBusBridge(pool, sessions);

    const a1 = makeStubActor();
    pool.register('r1', a1.actor);
    const s = bindPlayer(sessions, 'r1');

    const seen: RoomEvent[] = [];
    bridge.subscribe(s.playerId, (e) => seen.push(e));

    a1.stub.emit({ type: 'combat', roomId: 'r1', playerId: s.playerId, message: 'hi' });
    expect(seen).toHaveLength(1);
    expect(seen[0].message).toBe('hi');
  });

  test('rebindPlayer swaps subscription to the new room', () => {
    const pool = new RoomActorPool();
    const sessions = new PlayerSessionStore();
    const bridge = new EventBusBridge(pool, sessions);

    const a1 = makeStubActor();
    const a2 = makeStubActor();
    pool.register('r1', a1.actor);
    pool.register('r2', a2.actor);
    const s = bindPlayer(sessions, 'r1');

    const seen: RoomEvent[] = [];
    bridge.subscribe(s.playerId, (e) => seen.push(e));

    // Move the player and re-bind.
    sessions.rebind(s.playerId, 'r2');
    bridge.rebindPlayer(s.playerId);

    // Old room must NOT deliver to the listener anymore.
    a1.stub.emit({ type: 'combat', roomId: 'r1', playerId: s.playerId, message: 'old' });
    expect(seen).toHaveLength(0);

    // New room MUST deliver.
    a2.stub.emit({ type: 'combat', roomId: 'r2', playerId: s.playerId, message: 'new' });
    expect(seen).toHaveLength(1);
    expect(seen[0].message).toBe('new');
  });

  test('unsubscribe stops delivering events', () => {
    const pool = new RoomActorPool();
    const sessions = new PlayerSessionStore();
    const bridge = new EventBusBridge(pool, sessions);

    const a1 = makeStubActor();
    pool.register('r1', a1.actor);
    const s = bindPlayer(sessions, 'r1');

    const seen: RoomEvent[] = [];
    const unsub = bridge.subscribe(s.playerId, (e) => seen.push(e));
    unsub();

    a1.stub.emit({ type: 'combat', roomId: 'r1', playerId: s.playerId, message: 'x' });
    expect(seen).toHaveLength(0);
  });

  test('shutdown clears every active subscription', () => {
    const pool = new RoomActorPool();
    const sessions = new PlayerSessionStore();
    const bridge = new EventBusBridge(pool, sessions);

    const a1 = makeStubActor();
    pool.register('r1', a1.actor);
    const s = bindPlayer(sessions, 'r1');

    const seen: RoomEvent[] = [];
    bridge.subscribe(s.playerId, (e) => seen.push(e));
    bridge.shutdown();

    a1.stub.emit({ type: 'combat', roomId: 'r1', playerId: s.playerId, message: 'x' });
    expect(seen).toHaveLength(0);
  });

  test('subscribing without a current room defers attachment until rebind', () => {
    const pool = new RoomActorPool();
    const sessions = new PlayerSessionStore();
    const bridge = new EventBusBridge(pool, sessions);

    // No room registered yet for this player.
    const seen: RoomEvent[] = [];
    bridge.subscribe('player-loose', (e) => seen.push(e));

    const a1 = makeStubActor();
    pool.register('r1', a1.actor);

    // Pretend the session-store now reports r1 for this player.
    sessions.bind({
      sessionId: 'session-x',
      playerId: 'player-loose',
      playerName: 'q',
      currentRoomId: 'r1',
      connectedAt: 0,
    });
    bridge.rebindPlayer('player-loose');

    a1.stub.emit({ type: 'combat', roomId: 'r1', playerId: 'player-loose', message: 'late' });
    expect(seen).toHaveLength(1);
  });

  test('subscribe replaces a prior subscription cleanly', () => {
    const pool = new RoomActorPool();
    const sessions = new PlayerSessionStore();
    const bridge = new EventBusBridge(pool, sessions);

    const a1 = makeStubActor();
    pool.register('r1', a1.actor);
    const s = bindPlayer(sessions, 'r1');

    const seenA: RoomEvent[] = [];
    const seenB: RoomEvent[] = [];
    bridge.subscribe(s.playerId, (e) => seenA.push(e));
    bridge.subscribe(s.playerId, (e) => seenB.push(e));

    a1.stub.emit({ type: 'combat', roomId: 'r1', playerId: s.playerId, message: 'x' });
    expect(seenA).toHaveLength(0);
    expect(seenB).toHaveLength(1);
  });
});

```
