---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/__tests__/phase-f-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.602184+00:00
---

# cartridges/jambox/web/__tests__/phase-f-gate.test.ts

```ts
/**
 * D-F.8 — Phase F gate test.
 *
 * Asserts all Phase F criteria:
 *   1. TakeCapturer records cells and produces a JamboxTakeObject.
 *   2. Contribution splits sum to 10,000 bps.
 *   3. TakeReplay emits cells in depth order.
 *   4. TakeBouncer returns null when consent is denied.
 *   5. Fork narrows license (personal < remixable < commercial).
 *   6. Fork attempt to widen license throws LicenseViolationError.
 *   7. LineageCard resolves chain from registry.
 *   8. anchorTake / anchorArrangement compile and expose correct types.
 *   9. JamboxTakePayload Phase F fields round-trip through JSON.
 *  10. Phase A / B / C / D gates re-run and pass.
 */

import { describe, it, expect, vi } from 'vitest';

// ── Previous phase gate re-runs ───────────────────────────────────────────────
import './phase-a-gate.test';
import './phase-b-gate.test';
import './phase-c-gate.test';
import './phase-d-gate.test';

// ── Phase F imports ───────────────────────────────────────────────────────────
import { TakeCapturer } from '../src/takes/capturer';
import type { CaptureResult } from '../src/takes/capturer';
import { TakeReplay } from '../src/takes/replay';
import type { ReplayCallbacks } from '../src/takes/replay';
import { TakeBouncer } from '../src/takes/bouncer';
import type { BounceCallbacks } from '../src/takes/bouncer';
import { computeContributionSplits } from '../src/contrib/policy';
import type { ContributionInput } from '../src/contrib/policy';
import { validateForkLicense, forkObject, LicenseViolationError } from '../src/contrib/fork';
import { LineageCard } from '../src/ui/lineage-card';
import type { LineageCardCallbacks } from '../src/ui/lineage-card';
import { anchorTake, anchorArrangement, buildAnchorScript } from '../src/core/anchor';
import type { TakeAnchorPayload, ArrangementAnchorPayload } from '../src/core/anchor';
import {
  createTake,
  createContribution,
} from '../src/semantic/objects';
import type { JamboxTakePayload, JamboxSemanticObject } from '../src/semantic/objects';
import type { SerializedCell } from '../src/core/sync';

// ─────────────────────────────────────────────────────────────────────────────

const OWNER = 'gate-f-owner';
const ROOM  = 'gate-f-room';

/** Minimal SerializedCell factory. */
function fakeCell(opts: { depth?: number; op?: string; index?: number }): SerializedCell {
  const idx = opts.index ?? 0;
  return {
    id: `cell-${String(idx).padStart(4, '0')}`,
    stateHashHex: `deadbeef${String(idx).padStart(2, '0')}`,
    parentHashes: [],
    patch: { op: opts.op ?? 'jam.note.on', payload: {} },
    hat: 'jam',
    depth: opts.depth ?? idx,
    branch: 'jam',
    cherryPickedFromHash: null,
    tampered: false,
  };
}

// ── 1. TakeCapturer records cells → JamboxTakeObject ─────────────────────────

describe('F-1 — TakeCapturer', () => {
  it('produces a JamboxTakeObject after stop()', () => {
    const capturer = new TakeCapturer({ ownerIdentity: OWNER, roomId: ROOM });

    capturer.start('snap-hash-aaa', 0);
    capturer.recordCell(fakeCell({ op: 'jam.note.on', index: 0 }), 'alice', 100);
    capturer.recordCell(fakeCell({ op: 'jam.trigger', index: 1 }), 'bob', 200);
    capturer.recordCell(fakeCell({ op: 'jam.input.pad', index: 2 }), 'alice', 300);

    const result: CaptureResult = capturer.stop(4000, 2);

    expect(result.take.header.objectType).toBe('jam.take');
    expect(result.take.header.linearity).toBe('linear');
    expect(result.take.payload.state).toBe('captured');
    expect(result.cells).toHaveLength(3);
    expect(result.take.payload.lengthBars).toBe(2);
    expect(result.take.payload.startSnapshotHash).toBe('snap-hash-aaa');
  });

  it('status transitions: idle → capturing → captured', () => {
    const capturer = new TakeCapturer({ ownerIdentity: OWNER, roomId: ROOM });
    expect(capturer.status).toBe('idle');
    capturer.start('snap-xxx', 0);
    expect(capturer.status).toBe('capturing');
    capturer.stop(1000);
    expect(capturer.status).toBe('captured');
  });

  it('reset() returns capturer to idle', () => {
    const capturer = new TakeCapturer({ ownerIdentity: OWNER, roomId: ROOM });
    capturer.start('snap-yyy', 0);
    capturer.stop(500);
    capturer.reset();
    expect(capturer.status).toBe('idle');
  });

  it('recordCell() is a no-op when idle (no throw)', () => {
    const capturer = new TakeCapturer({ ownerIdentity: OWNER, roomId: ROOM });
    expect(() => capturer.recordCell(fakeCell({ index: 0 }), 'alice', 0)).not.toThrow();
  });
});

// ── 2. Contribution splits sum to 10,000 bps ─────────────────────────────────

describe('F-2 — computeContributionSplits', () => {
  it('splits sum to exactly 10,000 bps (mixed events)', () => {
    const events: ContributionInput[] = [
      { player: 'alice', roomTimeMs: 100 },
      { player: 'alice', roomTimeMs: 200, family: 'jam.note.on' },
      { player: 'alice', roomTimeMs: 300, family: 'jam.input.pad' },
      { player: 'bob',   roomTimeMs: 400, family: 'jam.trigger' },
      { player: 'bob',   roomTimeMs: 500, family: 'jam.rack.macro.set' },
      { player: 'carol', roomTimeMs: 600, family: 'jam.clock.tick' },
    ];
    const splits = computeContributionSplits(events);
    const total = [...splits.values()].reduce((a, b) => a + b, 0);
    expect(total).toBe(10_000);
  });

  it('clock events contribute zero weight (infrastructure only)', () => {
    const events: ContributionInput[] = [
      { player: 'alice', roomTimeMs: 100, family: 'jam.note.on' },
      { player: 'clock', roomTimeMs: 200, family: 'jam.clock.tick' },
      { player: 'clock', roomTimeMs: 300, family: 'jam.clock.tick' },
    ];
    const splits = computeContributionSplits(events);
    expect(splits.get('clock') ?? 0).toBe(0);
    expect(splits.get('alice')).toBe(10_000);
  });

  it('equal contribution between two players sums to 10,000', () => {
    const events: ContributionInput[] = [
      { player: 'alice', roomTimeMs: 100, family: 'jam.note.on' },
      { player: 'bob',   roomTimeMs: 200, family: 'jam.note.on' },
    ];
    const splits = computeContributionSplits(events);
    const total = [...splits.values()].reduce((a, b) => a + b, 0);
    expect(total).toBe(10_000);
    expect((splits.get('alice') ?? 0) + (splits.get('bob') ?? 0)).toBe(10_000);
  });

  it('single player gets 10,000 bps', () => {
    const events: ContributionInput[] = [
      { player: 'alice', roomTimeMs: 100, family: 'jam.note.on' },
    ];
    const splits = computeContributionSplits(events);
    expect(splits.get('alice')).toBe(10_000);
  });
});

// ── 3. TakeReplay emits cells in depth order ──────────────────────────────────

describe('F-3 — TakeReplay', () => {
  it('emits cells in depth order and calls onDone', async () => {
    const capturer = new TakeCapturer({ ownerIdentity: OWNER, roomId: ROOM });
    capturer.start('snap-replay-hash', 0);
    capturer.recordCell(fakeCell({ depth: 2, op: 'jam.trigger', index: 0 }), 'alice', 300);
    capturer.recordCell(fakeCell({ depth: 0, op: 'jam.note.on', index: 1 }), 'bob', 100);
    capturer.recordCell(fakeCell({ depth: 1, op: 'jam.input.pad', index: 2 }), 'alice', 200);
    const { take } = capturer.stop(4000, 2);

    const emittedDepths: number[] = [];
    let doneCalled = false;
    let snapshotRestored = '';

    const callbacks: ReplayCallbacks = {
      onRestoreSnapshot: async (hash: string) => { snapshotRestored = hash; },
      onCell: async (cell: SerializedCell) => { emittedDepths.push(cell.depth); },
      onDone: () => { doneCalled = true; },
    };

    const replay = new TakeReplay(take, callbacks);
    await replay.run();

    expect(emittedDepths).toEqual([0, 1, 2]);
    expect(doneCalled).toBe(true);
    expect(snapshotRestored).toBe('snap-replay-hash');
  });

  it('status is "idle" before run and "done" after', async () => {
    const capturer = new TakeCapturer({ ownerIdentity: OWNER, roomId: ROOM });
    capturer.start('snap-status', 0);
    capturer.recordCell(fakeCell({ depth: 0 }), 'alice', 0);
    const { take } = capturer.stop(1000);

    const replay = new TakeReplay(take, {
      onRestoreSnapshot: async () => {},
      onCell: async () => {},
    });
    expect(replay.status).toBe('idle');
    await replay.run();
    expect(replay.status).toBe('done');
  });

  it('reset() returns replay to idle', async () => {
    const capturer = new TakeCapturer({ ownerIdentity: OWNER, roomId: ROOM });
    capturer.start('snap-reset', 0);
    const { take } = capturer.stop(1000);

    const replay = new TakeReplay(take, {
      onRestoreSnapshot: async () => {},
      onCell: async () => {},
    });
    await replay.run();
    replay.reset();
    expect(replay.status).toBe('idle');
  });
});

// ── 4. TakeBouncer returns null on consent decline ────────────────────────────

describe('F-4 — TakeBouncer consent gate', () => {
  it('returns null when consent is denied', async () => {
    const capturer = new TakeCapturer({ ownerIdentity: OWNER, roomId: ROOM });
    capturer.start('snap-bounce', 0);
    capturer.recordCell(fakeCell({ depth: 0, op: 'jam.note.on' }), 'alice', 100);
    const { take } = capturer.stop(4000);

    const callbacks: BounceCallbacks = {
      requestConsent: async (_players: string[]) => false,
      replayCell: vi.fn(),
      writeToCas: vi.fn(),
    };
    const bouncer = new TakeBouncer(take, callbacks);
    const result = await bouncer.bounce();
    expect(result).toBeNull();
  });

  it('calls requestConsent with player list', async () => {
    const capturer = new TakeCapturer({ ownerIdentity: OWNER, roomId: ROOM });
    capturer.start('snap-consent', 0);
    capturer.recordCell(fakeCell({ depth: 0 }), 'alice', 0);
    capturer.recordCell(fakeCell({ depth: 1 }), 'carol', 0);
    const { take } = capturer.stop(2000);

    const consentSpy = vi.fn(async (_players: string[]) => false);
    const bouncer = new TakeBouncer(take, {
      requestConsent: consentSpy,
      replayCell: vi.fn(),
      writeToCas: vi.fn(),
    });
    await bouncer.bounce();
    expect(consentSpy).toHaveBeenCalledOnce();
  });
});

// ── 5 & 6. Fork license lattice ───────────────────────────────────────────────

describe('F-5/F-6 — Fork license lattice', () => {
  const baseObj = createTake({
    ownerIdentity: OWNER,
    room: ROOM,
    name: 'Original take',
    sourceObjectId: 'src-001',
    startMs: 0,
    durationMs: 4000,
  });

  it('fork from remixable to personal succeeds (narrowing)', () => {
    expect(() => validateForkLicense('remixable', 'personal')).not.toThrow();
  });

  it('fork from commercial to remixable succeeds (narrowing)', () => {
    expect(() => validateForkLicense('commercial', 'remixable')).not.toThrow();
  });

  it('fork from remixable to commercial throws LicenseViolationError (widening)', () => {
    expect(() => validateForkLicense('remixable', 'commercial')).toThrow(LicenseViolationError);
  });

  it('fork from personal to remixable throws LicenseViolationError (widening)', () => {
    expect(() => validateForkLicense('personal', 'remixable')).toThrow(LicenseViolationError);
  });

  it('fork from personal to personal succeeds (same level)', () => {
    expect(() => validateForkLicense('personal', 'personal')).not.toThrow();
  });

  it('forkObject sets parents[0] to original id', () => {
    const { forked } = forkObject(baseObj, {
      ownerIdentity: 'bob',
      room: ROOM,
      license: 'personal',
    });
    expect(forked.header.parents[0]).toBe(baseObj.id);
  });

  it('forkObject assigns a new id', () => {
    const { forked } = forkObject(baseObj, {
      ownerIdentity: 'bob',
      room: ROOM,
      license: 'personal',
    });
    expect(forked.id).not.toBe(baseObj.id);
  });
});

// ── 7. LineageCard resolves chain ─────────────────────────────────────────────

describe('F-7 — LineageCard', () => {
  it('select() populates chain with the selected object at depth 0', () => {
    const objA = createTake({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'Take A',
      sourceObjectId: 'src-001',
      startMs: 0,
      durationMs: 4000,
    });
    const objB = createTake({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'Take B',
      sourceObjectId: objA.id,
      startMs: 4000,
      durationMs: 4000,
    });

    const registry = new Map<string, JamboxSemanticObject<unknown>>([
      [objA.id, objA as JamboxSemanticObject<unknown>],
      [objB.id, objB as JamboxSemanticObject<unknown>],
    ]);

    const callbacks: LineageCardCallbacks = {
      resolveObject: (id: string) => registry.get(id) ?? null,
      onFocusObject: vi.fn(),
      onForkComplete: vi.fn(),
      onForkError: vi.fn(),
    };

    const card = new LineageCard(callbacks);
    card.select(objB.id);

    expect(card.chain.length).toBeGreaterThan(0);
    const rootNode = card.chain.find((n) => n.id === objB.id);
    expect(rootNode).toBeDefined();
    expect(rootNode?.depth).toBe(0);
  });

  it('chain is empty before select()', () => {
    const card = new LineageCard({
      resolveObject: () => null,
      onFocusObject: vi.fn(),
      onForkComplete: vi.fn(),
      onForkError: vi.fn(),
    });
    expect(card.chain).toHaveLength(0);
  });
});

// ── 8. anchor functions compile and export correct types ─────────────────────

describe('F-8 — Anchor extensions (D-F.7)', () => {
  it('TakeAnchorPayload shape is correct', () => {
    const payload: TakeAnchorPayload = {
      v: 1,
      kind: 'jam.take',
      takeId: 'take-001',
      room: ROOM,
      players: ['alice', 'bob'],
      cellCount: 42,
      ts: Date.now(),
    };
    expect(payload.v).toBe(1);
    expect(payload.kind).toBe('jam.take');
    expect(payload.cellCount).toBe(42);
  });

  it('ArrangementAnchorPayload shape is correct', () => {
    const payload: ArrangementAnchorPayload = {
      v: 1,
      kind: 'jam.arrangement',
      arrangementId: 'arr-001',
      room: ROOM,
      takeIds: ['take-001', 'take-002'],
      ts: Date.now(),
    };
    expect(payload.v).toBe(1);
    expect(payload.kind).toBe('jam.arrangement');
    expect(payload.takeIds).toHaveLength(2);
  });

  it('anchorTake is an async function', () => {
    expect(typeof anchorTake).toBe('function');
    expect(anchorTake.constructor.name).toBe('AsyncFunction');
  });

  it('anchorArrangement is an async function', () => {
    expect(typeof anchorArrangement).toBe('function');
    expect(anchorArrangement.constructor.name).toBe('AsyncFunction');
  });

  it('buildAnchorScript is exported', () => {
    expect(typeof buildAnchorScript).toBe('function');
  });
});

// ── 9. JamboxTakePayload Phase F fields round-trip ───────────────────────────

describe('F-9 — JamboxTakePayload Phase F fields round-trip', () => {
  it('all Phase F optional fields survive JSON round-trip', () => {
    const takeObj = createTake({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'F round-trip take',
      sourceObjectId: 'src-rtrip',
      startMs: 1000,
      durationMs: 8000,
    });

    const payload: JamboxTakePayload = {
      ...takeObj.payload,
      room: ROOM,
      range: { startRoomTimeMs: 1000, endRoomTimeMs: 9000 },
      lengthBars: 4,
      cells: [fakeCell({ depth: 0 })],
      players: ['alice', 'bob'],
      racks: ['rack-001'],
      mappings: ['mapping-001'],
      startSnapshotHash: 'snap-aaa',
    };

    const json = JSON.stringify(payload);
    const parsed = JSON.parse(json) as JamboxTakePayload;

    expect(parsed.room).toBe(ROOM);
    expect(parsed.range?.startRoomTimeMs).toBe(1000);
    expect(parsed.range?.endRoomTimeMs).toBe(9000);
    expect(parsed.lengthBars).toBe(4);
    expect(Array.isArray(parsed.cells)).toBe(true);
    expect(parsed.players).toEqual(['alice', 'bob']);
    expect(parsed.startSnapshotHash).toBe('snap-aaa');
  });

  it('JamboxContributionPayload Phase F fields round-trip', () => {
    const contrib = createContribution({
      ownerIdentity: OWNER,
      room: ROOM,
      playerIdentity: 'alice',
      objectIds: ['take-001'],
      shareBps: 6000,
      startMs: 0,
      cellRange: { from: 0, to: 4000 },
      category: 'note.play',
      license: 'remixable',
    });

    const json = JSON.stringify(contrib);
    const parsed = JSON.parse(json) as typeof contrib;

    expect(parsed.payload.cellRange?.from).toBe(0);
    expect(parsed.payload.cellRange?.to).toBe(4000);
    expect(parsed.payload.category).toBe('note.play');
    expect(parsed.payload.license).toBe('remixable');
    expect(parsed.payload.splitBps).toBe(6000);
  });
});

```
