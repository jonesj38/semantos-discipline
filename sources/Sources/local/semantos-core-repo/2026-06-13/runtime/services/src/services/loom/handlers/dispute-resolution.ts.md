---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/handlers/dispute-resolution.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.116659+00:00
---

# runtime/services/src/services/loom/handlers/dispute-resolution.ts

```ts
/**
 * Dispute resolution handler.
 *
 * `resolveDisputeReclassification` reads a dispute object's resolution
 * field, finds the misclassification evidence patch, and either
 * reclassifies the subject's typeCoordinate (`upheld`) or records a
 * dismissal patch. Returns true when an action was taken.
 */

import { get, type Atom } from '@semantos/state';

import type { ObjectPatch, TypeCoordinate } from '../../../types/loom';
import { dispatchTo } from '../loom-atoms';
import type { LoomState } from '../loom-types';

export function resolveDisputeReclassification(
  stateAtom: Atom<LoomState>,
  disputeObjectId: string,
  hatId: string,
  hatCapabilities?: number[],
): boolean {
  const state = get(stateAtom);
  const dispute = state.objects.get(disputeObjectId);
  if (!dispute) return false;

  const resolution = dispute.payload.resolution as string | undefined;
  if (!resolution || resolution === 'pending') return false;

  const evidencePatch = dispute.patches.find(
    (p) => p.kind === 'evidence_merge' && p.delta.category === 'governance.misclassification',
  );
  if (!evidencePatch) return false;

  const subjectObjectId = evidencePatch.delta.subjectObjectId as string | undefined;
  if (!subjectObjectId) return false;

  const subject = state.objects.get(subjectObjectId);
  if (!subject) return false;

  if (resolution === 'upheld') {
    const proposed = evidencePatch.delta.proposedCoordinate as Partial<TypeCoordinate> | undefined;
    if (!proposed) return false;

    const currentCoordinate = subject.typeCoordinate ?? { what: '', how: [], why: [] };
    const newCoordinate: TypeCoordinate = {
      what: proposed.what ?? currentCoordinate.what,
      how: proposed.how ?? currentCoordinate.how,
      why: proposed.why ?? currentCoordinate.why,
    };

    dispatchTo(stateAtom, {
      type: 'UPDATE_OBJECT',
      id: subjectObjectId,
      updates: { typeCoordinate: newCoordinate },
    });

    const reclassPatch: ObjectPatch = {
      id: `patch-${Date.now()}-reclassify`,
      kind: 'state_transition',
      timestamp: Date.now(),
      delta: {
        action: 'reclassification',
        previousCoordinate: currentCoordinate,
        newCoordinate,
        disputeObjectId,
        resolution: 'upheld',
      },
      hatId,
      ...(hatCapabilities !== undefined ? { hatCapabilities } : {}),
    };
    dispatchTo(stateAtom, { type: 'ADD_PATCH', objectId: subjectObjectId, patch: reclassPatch });
    return true;
  }

  if (resolution === 'dismissed') {
    const dismissPatch: ObjectPatch = {
      id: `patch-${Date.now()}-dismiss`,
      kind: 'action',
      timestamp: Date.now(),
      delta: {
        action: 'classification-challenge-dismissed',
        disputeObjectId,
        resolution: 'dismissed',
      },
      hatId,
      ...(hatCapabilities !== undefined ? { hatCapabilities } : {}),
    };
    dispatchTo(stateAtom, { type: 'ADD_PATCH', objectId: subjectObjectId, patch: dismissPatch });
    return true;
  }

  return false;
}

```
