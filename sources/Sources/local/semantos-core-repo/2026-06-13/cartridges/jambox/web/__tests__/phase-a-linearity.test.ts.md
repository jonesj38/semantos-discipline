---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/__tests__/phase-a-linearity.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.600362+00:00
---

# cartridges/jambox/web/__tests__/phase-a-linearity.test.ts

```ts
/**
 * D-A.5 — Linearity unit tests.
 *
 * Asserts that every new Phase A factory emits the correct linearity class
 * per the table in §A.1 of PHASE-A-VOCABULARY-AND-RACK.md.
 *
 * | Kind              | Linearity |
 * | jam.rack          | linear    |
 * | jam.macro         | debug     |
 * | jam.clip          | affine    |
 * | jam.scene         | affine    |
 * | jam.take          | linear    |
 * | jam.contribution  | relevant  |
 * | jam.player        | affine    |
 * | jam.gesture       | debug     |
 * | jam.mapping       | linear    |
 * | jam.permission    | linear    |
 */

import { describe, it, expect } from 'vitest';
import {
  createRack,
  createClip,
  createScene,
  createTake,
  createContribution,
  createPlayer,
  createGesture,
  createMapping,
  createPermission,
} from '../src/semantic/objects';

const OWNER = 'test-owner';
const ROOM = 'test-room';
const PAT_ID = 'jam.pattern:test-owner:test-room-pattern-a';
const SRC_ID = 'jam.scene:test-owner:test-room-scene-0-a';
const OBJ_ID = 'jam.clip:test-owner:test-room-clip-a';

describe('Phase A linearity', () => {
  it('jam.rack → linear', () => {
    const obj = createRack({
      ownerIdentity: OWNER,
      rackId: 'jam.rack.drum-808',
      name: 'Drum 808',
      engine: 'webaudio',
    });
    expect(obj.header.linearity).toBe('linear');
    expect(obj.header.objectType).toBe('jam.rack');
  });

  it('jam.clip → affine', () => {
    const obj = createClip({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'clip-a',
      patternObjectId: PAT_ID,
    });
    expect(obj.header.linearity).toBe('affine');
    expect(obj.header.objectType).toBe('jam.clip');
  });

  it('jam.scene → affine', () => {
    const obj = createScene({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'scene-a',
      sceneIndex: 0,
    });
    expect(obj.header.linearity).toBe('affine');
    expect(obj.header.objectType).toBe('jam.scene');
  });

  it('jam.take → linear', () => {
    const obj = createTake({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'take-a',
      sourceObjectId: SRC_ID,
      startMs: 1000,
      durationMs: 4000,
    });
    expect(obj.header.linearity).toBe('linear');
    expect(obj.header.objectType).toBe('jam.take');
  });

  it('jam.contribution → relevant', () => {
    const obj = createContribution({
      ownerIdentity: OWNER,
      room: ROOM,
      playerIdentity: 'player-1',
      objectIds: [PAT_ID],
      shareBps: 5000,
      startMs: 1000,
    });
    expect(obj.header.linearity).toBe('relevant');
    expect(obj.header.objectType).toBe('jam.contribution');
  });

  it('jam.player → affine', () => {
    const obj = createPlayer({
      ownerIdentity: OWNER,
      room: ROOM,
      identity: 'player-1',
      displayName: 'Player One',
      colorHex: '#ff6600',
    });
    expect(obj.header.linearity).toBe('affine');
    expect(obj.header.objectType).toBe('jam.player');
  });

  it('jam.gesture → debug', () => {
    const obj = createGesture({
      ownerIdentity: OWNER,
      room: ROOM,
      kind: 'filter-sweep',
      playerIdentity: 'player-1',
      rackId: 'jam.rack.acid-303',
    });
    expect(obj.header.linearity).toBe('debug');
    expect(obj.header.objectType).toBe('jam.gesture');
  });

  it('jam.mapping → linear', () => {
    const obj = createMapping({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'test-mapping',
      surfaceShape: 'grid-8x8',
    });
    expect(obj.header.linearity).toBe('linear');
    expect(obj.header.objectType).toBe('jam.mapping');
  });

  it('jam.permission → linear', () => {
    const obj = createPermission({
      ownerIdentity: OWNER,
      room: ROOM,
      objectId: OBJ_ID,
      granteeIdentity: 'player-2',
      grants: ['read', 'launch'],
    });
    expect(obj.header.linearity).toBe('linear');
    expect(obj.header.objectType).toBe('jam.permission');
  });
});

```
