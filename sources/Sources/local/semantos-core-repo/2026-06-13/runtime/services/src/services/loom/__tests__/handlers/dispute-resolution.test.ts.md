---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/__tests__/handlers/dispute-resolution.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.121303+00:00
---

# runtime/services/src/services/loom/__tests__/handlers/dispute-resolution.test.ts

```ts
/**
 * dispute-resolution handler tests.
 *
 * The handler reads a dispute object's `payload.resolution` field plus
 * an `evidence_merge` patch carrying the proposed reclassification or
 * dismissal. We hand-craft both objects in the state atom to keep
 * tests focused on the handler's branching.
 */

import { describe, expect, test } from 'bun:test';
import { atom, get, type Atom } from '@semantos/state';

import { resolveDisputeReclassification } from '../../handlers/dispute-resolution';
import { freshInitialState } from '../../loom-atoms';
import type { LoomState } from '../../loom-types';
import { makeObject, makePatch } from '../fixtures';

function freshAtom(): Atom<LoomState> {
  return atom<LoomState>(freshInitialState());
}

function seedDispute(
  a: Atom<LoomState>,
  resolution: string | null,
  proposed?: { what?: string; how?: string[]; why?: string[] },
  withEvidence = true,
): { disputeId: string; subjectId: string } {
  const subject = makeObject({
    id: 'subject-1',
    payload: { title: 'old-subject' },
    typeCoordinate: { what: 'what.old', how: ['how.x'], why: ['why.y'] },
  });
  const disputePatches = withEvidence
    ? [
        makePatch({
          id: 'p-evidence',
          kind: 'evidence_merge',
          delta: {
            category: 'governance.misclassification',
            subjectObjectId: subject.id,
            proposedCoordinate: proposed,
          },
        }),
      ]
    : [];
  const dispute = makeObject({
    id: 'dispute-1',
    payload: { resolution: resolution ?? undefined },
    patches: disputePatches,
  });

  const state = get(a);
  state.objects.set(subject.id, subject);
  state.objects.set(dispute.id, dispute);
  return { disputeId: dispute.id, subjectId: subject.id };
}

describe('resolveDisputeReclassification', () => {
  test('1. returns false when the dispute object is missing', () => {
    const a = freshAtom();
    expect(resolveDisputeReclassification(a, 'missing', 'hat-1')).toBe(false);
  });

  test('2. returns false when resolution is undefined', () => {
    const a = freshAtom();
    const { disputeId } = seedDispute(a, null);
    expect(resolveDisputeReclassification(a, disputeId, 'hat-1')).toBe(false);
  });

  test('3. returns false when resolution is "pending"', () => {
    const a = freshAtom();
    const { disputeId } = seedDispute(a, 'pending');
    expect(resolveDisputeReclassification(a, disputeId, 'hat-1')).toBe(false);
  });

  test('4. returns false when no evidence_merge patch is present', () => {
    const a = freshAtom();
    const { disputeId } = seedDispute(a, 'upheld', { what: 'what.new' }, false);
    expect(resolveDisputeReclassification(a, disputeId, 'hat-1')).toBe(false);
  });

  test('5. upheld with proposedCoordinate updates the subject typeCoordinate', () => {
    const a = freshAtom();
    const { disputeId, subjectId } = seedDispute(a, 'upheld', {
      what: 'what.new',
      how: ['how.new'],
      why: ['why.new'],
    });
    const ok = resolveDisputeReclassification(a, disputeId, 'hat-7', [3]);
    expect(ok).toBe(true);
    const subject = get(a).objects.get(subjectId);
    expect(subject?.typeCoordinate).toEqual({
      what: 'what.new',
      how: ['how.new'],
      why: ['why.new'],
    });
  });

  test('6. upheld appends a state_transition reclassify patch with prev/new coordinates', () => {
    const a = freshAtom();
    const { disputeId, subjectId } = seedDispute(a, 'upheld', { what: 'what.new' });
    resolveDisputeReclassification(a, disputeId, 'hat-7');
    const last = get(a).objects.get(subjectId)?.patches.slice(-1)[0];
    expect(last?.kind).toBe('state_transition');
    expect(last?.delta.action).toBe('reclassification');
    expect((last?.delta.previousCoordinate as { what: string }).what).toBe('what.old');
    expect((last?.delta.newCoordinate as { what: string }).what).toBe('what.new');
    expect(last?.delta.disputeObjectId).toBe(disputeId);
  });

  test('7. upheld but no proposedCoordinate returns false', () => {
    const a = freshAtom();
    const { disputeId } = seedDispute(a, 'upheld', undefined);
    expect(resolveDisputeReclassification(a, disputeId, 'hat-1')).toBe(false);
  });

  test('8. dismissed records a dismiss action patch on the subject', () => {
    const a = freshAtom();
    const { disputeId, subjectId } = seedDispute(a, 'dismissed', { what: 'what.new' });
    const ok = resolveDisputeReclassification(a, disputeId, 'hat-3');
    expect(ok).toBe(true);
    const last = get(a).objects.get(subjectId)?.patches.slice(-1)[0];
    expect(last?.kind).toBe('action');
    expect(last?.delta.action).toBe('classification-challenge-dismissed');
    expect(last?.hatId).toBe('hat-3');
  });

  test('9. dismissed leaves the subject typeCoordinate unchanged', () => {
    const a = freshAtom();
    const { disputeId, subjectId } = seedDispute(a, 'dismissed');
    const before = get(a).objects.get(subjectId)?.typeCoordinate;
    resolveDisputeReclassification(a, disputeId, 'hat-3');
    const after = get(a).objects.get(subjectId)?.typeCoordinate;
    expect(after).toEqual(before!);
  });

  test('10. unknown resolution string returns false', () => {
    const a = freshAtom();
    const { disputeId } = seedDispute(a, 'mystery');
    expect(resolveDisputeReclassification(a, disputeId, 'hat-1')).toBe(false);
  });

  test('11. resolution upheld with subjectObjectId pointing at a missing subject returns false', () => {
    const a = freshAtom();
    const { disputeId } = seedDispute(a, 'upheld', { what: 'what.new' });
    // wipe the subject from state but keep the dispute
    get(a).objects.delete('subject-1');
    expect(resolveDisputeReclassification(a, disputeId, 'hat-1')).toBe(false);
  });
});

```
