---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/handle-message-guard.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.357681+00:00
---

# runtime/intent/src/__tests__/handle-message-guard.test.ts

```ts
/**
 * handleMessage × CalendarGuard (A5) integration.
 *
 * Uses the same fixture pattern as handle-message.test.ts. The classifier
 * returns a PROPOSES outcome whose Intent.delta carries a `proposedSlot`.
 * A mock CalendarGuard reports conflicts (or doesn't); we assert
 * handleMessage returns `reject_conflict` or `proposed` accordingly.
 */
import { describe, expect, test } from 'bun:test';
import {
  handleMessage,
  createInMemoryPendingRegistry,
  type HandleMessageDeps,
} from '../handle-message';
import { createInMemoryLogger } from '../logger';
import type {
  CalendarGuard,
  CellId,
  HatContext,
  Intent,
  IntentId,
  PatchId,
  PipelineDeps,
  ScriptResult,
  Signature,
  TriageOutcome,
  Classifier,
} from '../index';

// ── Fixtures ────────────────────────────────────────────────

const mkHat = (over: Partial<HatContext> = {}): HatContext => ({
  hatId: 'hat-tenant',
  hatId: 'hat-tenant',
  certId: 'cert-tenant',
  capabilities: [1, 2],
  extensionId: 'property',
  domainFlag: 7,
  maxTrustClass: 'interpretive',
  ...over,
});

const okKernel: ScriptResult = { ok: true, stackDepth: 0, opcount: 3, gasUsed: 10 };

let cellCounter = 0;
const mkPipelineDeps = (): PipelineDeps => ({
  emitBytes: () => new Uint8Array([0xc3, 0x05]),
  executeScript: async () => okKernel,
  buildCellFromBytes: (bytes) => ({
    id: `cell-${++cellCounter}` as CellId,
    bytes,
  }),
  writeCell: async () => {},
  sign: () => new Uint8Array([0xde, 0xad]),
  now: () => 1_700_000_000_000,
  uuid: () => 'uuid-stub',
});

const stubSig: Signature = {
  bytes: new Uint8Array([0xaa]),
  algorithm: 'stub',
  keyId: 'k-1',
};

/**
 * Classifier that always returns PROPOSES with a user-supplied intent.
 * Lets each test control the Intent's delta (including proposedSlot).
 */
function proposingClassifier(deltaFactory: () => unknown): Classifier {
  return {
    async classify({ conversationPatchId }): Promise<TriageOutcome> {
      const intent: Intent = {
        id: `intent-${Date.now()}` as IntentId,
        companionOf: conversationPatchId,
        summary: 'schedule a plumber',
        category: { lexicon: 'property-management', category: 'maintenance' },
        taxonomy: { what: 'maintenance.job', how: 'quote.solicit', why: 'procurement' },
        action: 'schedule',
        constraints: [{ kind: 'capability', required: 1, name: 'cap-1' }],
        confidence: 0.88,
        source: 'nl',
        // `delta` is attached outside the Intent type's strict shape;
        // the extractor reads `intent.delta` directly.
        ...({ delta: deltaFactory() } as Record<string, unknown>),
      } as Intent;
      return { kind: 'proposes', intent };
    },
  };
}

function mkDeps(
  classifier: Classifier,
  calendarGuard?: CalendarGuard,
): HandleMessageDeps {
  const logger = createInMemoryLogger();
  let patchCounter = 0;

  return {
    conversation: {
      write: () => {},
      generatePatchId: () => `patch-conv-${++patchCounter}`,
      generateCorrelationId: () => `corr-${patchCounter}`,
      now: () => 1_700_000_000_000,
    },
    ratification: {
      write: () => {},
      generatePatchId: () => `patch-rat-${++patchCounter}`,
      now: () => 1_700_000_000_000,
    },
    classifier,
    pendingRegistry: createInMemoryPendingRegistry(),
    pipeline: mkPipelineDeps(),
    logger,
    now: () => 1_700_000_000_000,
    calendarGuard,
  };
}

const SLOT_THURSDAY_2PM = {
  startAt: '2026-07-02T14:00:00Z',
  endAt: '2026-07-02T16:00:00Z',
  hatId: 'todd-handyman',
  subjectKind: 'ojt-job',
  subjectId: 'job-1',
};

// ── Tests ────────────────────────────────────────────────────

describe('handleMessage — calendar guard (A5)', () => {
  test('HG1 guard with no conflict → passes through to proposed', async () => {
    const guard: CalendarGuard = {
      findConflicts: async () => ({ conflictingBookings: [], conflictingHolds: [] }),
      findFreeWindows: async () => [],
    };
    const deps = mkDeps(
      proposingClassifier(() => ({ proposedSlot: SLOT_THURSDAY_2PM })),
      guard,
    );
    const result = await handleMessage(
      {
        objectId: 'job-1',
        hat: mkHat(),
        body: { text: 'can Todd come Thursday 2pm?' },
        source: 'nl',
      },
      deps,
    );
    expect(result.kind).toBe('proposed');
  });

  test('HG2 guard with conflict → reject_conflict + free windows surfaced', async () => {
    const conflictingBooking = {
      id: 'book-ex',
      hatId: 'todd-advisor',
      startAt: new Date('2026-07-02T13:30:00Z'),
      endAt: new Date('2026-07-02T14:30:00Z'),
      subjectKind: 'brap-consult',
      subjectId: 'consult-1',
      recordKind: 'booking' as const,
    };
    const freeWindow = {
      startAt: new Date('2026-07-02T16:00:00Z'),
      endAt: new Date('2026-07-02T18:00:00Z'),
    };
    let findFreeCalled = 0;
    const guard: CalendarGuard = {
      findConflicts: async () => ({
        conflictingBookings: [conflictingBooking],
        conflictingHolds: [],
      }),
      findFreeWindows: async () => {
        findFreeCalled++;
        return [freeWindow];
      },
    };
    const deps = mkDeps(
      proposingClassifier(() => ({ proposedSlot: SLOT_THURSDAY_2PM })),
      guard,
    );
    const result = await handleMessage(
      {
        objectId: 'job-1',
        hat: mkHat(),
        body: { text: 'can Todd come Thursday 2pm?' },
        source: 'nl',
      },
      deps,
    );
    expect(result.kind).toBe('reject_conflict');
    if (result.kind === 'reject_conflict') {
      expect(result.conflictingBookings.length).toBe(1);
      expect(result.conflictingBookings[0].hatId).toBe('todd-advisor');
      expect(result.proposedSlot.hatId).toBe('todd-handyman');
      expect(result.freeWindows).toEqual([freeWindow]);
    }
    expect(findFreeCalled).toBe(1);
  });

  test('HG3 no guard → legacy behaviour: proposed regardless of delta shape', async () => {
    const deps = mkDeps(
      proposingClassifier(() => ({ proposedSlot: SLOT_THURSDAY_2PM })),
      // no calendarGuard
    );
    const result = await handleMessage(
      {
        objectId: 'job-1',
        hat: mkHat(),
        body: { text: 'thursday 2pm' },
        source: 'nl',
      },
      deps,
    );
    expect(result.kind).toBe('proposed');
  });

  test('HG4 guard + proposes without proposedSlot → guard NOT called; proposed', async () => {
    let findConflictsCalled = 0;
    const guard: CalendarGuard = {
      findConflicts: async () => {
        findConflictsCalled++;
        return { conflictingBookings: [], conflictingHolds: [] };
      },
      findFreeWindows: async () => [],
    };
    const deps = mkDeps(
      proposingClassifier(() => ({ some: 'other-delta' })),
      guard,
    );
    const result = await handleMessage(
      {
        objectId: 'job-1',
        hat: mkHat(),
        body: { text: 'hi' },
        source: 'nl',
      },
      deps,
    );
    expect(result.kind).toBe('proposed');
    expect(findConflictsCalled).toBe(0);
  });

  test('HG5 guard with conflicting hold (not booking) still rejects', async () => {
    const conflictingHold = {
      id: 'hold-ex',
      hatId: 'todd-advisor',
      startAt: new Date('2026-07-02T14:30:00Z'),
      endAt: new Date('2026-07-02T15:30:00Z'),
      subjectKind: 'brap-consult',
      subjectId: 'consult-1',
      recordKind: 'hold' as const,
    };
    const guard: CalendarGuard = {
      findConflicts: async () => ({
        conflictingBookings: [],
        conflictingHolds: [conflictingHold],
      }),
      findFreeWindows: async () => [],
    };
    const deps = mkDeps(
      proposingClassifier(() => ({ proposedSlot: SLOT_THURSDAY_2PM })),
      guard,
    );
    const result = await handleMessage(
      {
        objectId: 'job-1',
        hat: mkHat(),
        body: { text: 'thursday 2pm' },
        source: 'nl',
      },
      deps,
    );
    expect(result.kind).toBe('reject_conflict');
    if (result.kind === 'reject_conflict') {
      expect(result.conflictingHolds.length).toBe(1);
      expect(result.conflictingBookings.length).toBe(0);
    }
  });

  test('HG6 custom lookahead days + limit surface to findFreeWindows', async () => {
    let capturedQuery: any = null;
    const guard: CalendarGuard = {
      findConflicts: async () => ({
        conflictingBookings: [
          {
            id: 'b1',
            hatId: 'todd-handyman',
            startAt: new Date('2026-07-02T14:00Z'),
            endAt: new Date('2026-07-02T16:00Z'),
            subjectKind: 'ojt-job',
            subjectId: 'other',
            recordKind: 'booking' as const,
          },
        ],
        conflictingHolds: [],
      }),
      findFreeWindows: async (q) => {
        capturedQuery = q;
        return [];
      },
    };
    const deps = mkDeps(
      proposingClassifier(() => ({ proposedSlot: SLOT_THURSDAY_2PM })),
      guard,
    );
    deps.freeWindowLookahead = { days: 7, limit: 3 };
    await handleMessage(
      {
        objectId: 'job-1',
        hat: mkHat(),
        body: { text: 'thursday 2pm' },
        source: 'nl',
      },
      deps,
    );
    expect(capturedQuery).not.toBeNull();
    expect(capturedQuery.limit).toBe(3);
    const windowMs = capturedQuery.toAt.getTime() - capturedQuery.fromAt.getTime();
    expect(windowMs).toBe(7 * 86_400_000);
    expect(capturedQuery.durationMinutes).toBe(120); // 2 hours
    expect(capturedQuery.hatId).toBe('todd-handyman');
  });
});

void stubSig;

```
