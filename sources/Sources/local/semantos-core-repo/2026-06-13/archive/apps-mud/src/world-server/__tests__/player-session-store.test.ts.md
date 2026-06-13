---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/__tests__/player-session-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.845969+00:00
---

# archive/apps-mud/src/world-server/__tests__/player-session-store.test.ts

```ts
/**
 * Tests for `player-session-store.ts`.
 *
 * Pure: no actor / engine dependency.
 */

import { describe, test, expect } from 'bun:test';

import type { PlayerSession } from '../../types';
import { PlayerSessionStore } from '../player-session-store';

function makeSession(
  store: PlayerSessionStore,
  roomId = 'tavern',
  name = 'alice',
): PlayerSession {
  const sessionId = store.mintSessionId();
  return {
    sessionId,
    playerId: store.playerIdFor(sessionId),
    playerName: name,
    currentRoomId: roomId,
    connectedAt: 0,
  };
}

describe('PlayerSessionStore', () => {
  test('mintSessionId is monotonic', () => {
    const store = new PlayerSessionStore();
    expect(store.mintSessionId()).toBe('session-0');
    expect(store.mintSessionId()).toBe('session-1');
    expect(store.mintSessionId()).toBe('session-2');
  });

  test('playerIdFor follows the session-id convention', () => {
    const store = new PlayerSessionStore();
    expect(store.playerIdFor('session-7')).toBe('player-session-7');
  });

  test('bind makes the session and player→room binding visible', () => {
    const store = new PlayerSessionStore();
    const s = makeSession(store, 'tavern');
    store.bind(s);
    expect(store.getSession(s.sessionId)).toBe(s);
    expect(store.getPlayerRoom(s.playerId)).toBe('tavern');
    expect(store.playerCount()).toBe(1);
  });

  test('bind throws if the session id is reused', () => {
    const store = new PlayerSessionStore();
    const s = makeSession(store);
    store.bind(s);
    expect(() => store.bind(s)).toThrow();
  });

  test('rebind moves the player AND updates currentRoomId on every session', () => {
    const store = new PlayerSessionStore();
    const s = makeSession(store, 'tavern');
    store.bind(s);
    expect(store.rebind(s.playerId, 'crypt')).toBe(true);
    expect(store.getPlayerRoom(s.playerId)).toBe('crypt');
    expect(store.getSession(s.sessionId)?.currentRoomId).toBe('crypt');
  });

  test('rebind returns false for unknown players', () => {
    const store = new PlayerSessionStore();
    expect(store.rebind('nobody', 'crypt')).toBe(false);
  });

  test('unbind drops the room binding and every session for the player', () => {
    const store = new PlayerSessionStore();
    const s = makeSession(store, 'tavern');
    store.bind(s);
    store.unbind(s.playerId);
    expect(store.getPlayerRoom(s.playerId)).toBeUndefined();
    expect(store.getSession(s.sessionId)).toBeUndefined();
    expect(store.playerCount()).toBe(0);
  });

  test('allSessions reports active sessions in insertion order', () => {
    const store = new PlayerSessionStore();
    const s1 = makeSession(store, 'tavern', 'alice');
    const s2 = makeSession(store, 'crypt', 'bob');
    store.bind(s1);
    store.bind(s2);
    const all = store.allSessions();
    expect(all.map(s => s.playerName)).toEqual(['alice', 'bob']);
  });
});

```
