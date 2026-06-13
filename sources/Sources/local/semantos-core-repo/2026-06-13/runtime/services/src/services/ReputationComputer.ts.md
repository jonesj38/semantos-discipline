---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/ReputationComputer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.095070+00:00
---

# runtime/services/src/services/ReputationComputer.ts

```ts
/**
 * ReputationComputer — pure function computing reputation from evidence chain patches.
 *
 * No state, no side effects, no class. Reputation is a materialized view
 * over patches and objects, not a managed service.
 */

import type { ObjectPatch, LoomObject, ReputationScore, ReputationWeights } from '../types/loom';

/** Default weights for reputation computation. */
export const DEFAULT_REPUTATION_WEIGHTS: ReputationWeights = {
  base: 0.2,
  activity: 0.3,
  disputes: 0.3,
  contributions: 0.2,
};

const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_ACTIVITY_POINTS = 30;

/**
 * Compute a reputation score from an identity's evidence chain and the workbench state.
 *
 * @param identityPatches — patches authored by this identity (any hat)
 * @param allObjects — full workbench object map (for scanning Disputes, Ballots, Stakes)
 * @param weights — optional custom weights (defaults to DEFAULT_REPUTATION_WEIGHTS)
 * @param context — optional TypeCoordinate "what" prefix to scope reputation (e.g. "what.service.fabrication")
 */
export function computeReputation(
  identityPatches: ObjectPatch[],
  allObjects: Map<string, LoomObject>,
  weights: ReputationWeights = DEFAULT_REPUTATION_WEIGHTS,
  context?: string,
): ReputationScore {
  const now = Date.now();
  const hatIds = collectHatIds(identityPatches);

  // Filter objects to context scope if provided
  const scopedObjects = context
    ? filterByContext(allObjects, context)
    : allObjects;

  // Filter patches to context scope: only count patches that are on objects in scope
  const scopedPatches = context
    ? filterPatchesByContext(identityPatches, scopedObjects)
    : identityPatches;

  // BASE: always 50
  const base = 50;

  // ACTIVITY: count patches in last 30 days, capped at 30
  const cutoff = now - THIRTY_DAYS_MS;
  const recentPatchCount = scopedPatches.filter(p => p.timestamp >= cutoff).length;
  const activity = Math.min(recentPatchCount, MAX_ACTIVITY_POINTS);

  // DISPUTE OUTCOMES: scan Disputes, Resolutions, and Stakes
  const disputeOutcomes = computeDisputeOutcomes(hatIds, scopedObjects);

  // CONTRIBUTIONS: scan approved Ballots where identity was proposer
  const contributions = computeContributions(hatIds, scopedObjects);

  // TOTAL: weighted sum
  const total = Math.round(
    base * weights.base +
    activity * weights.activity +
    disputeOutcomes * weights.disputes +
    contributions * weights.contributions,
  );

  return { base, activity, disputeOutcomes, contributions, total, context };
}

/** Collect all unique hatIds from a set of patches. */
function collectHatIds(patches: ObjectPatch[]): Set<string> {
  const ids = new Set<string>();
  for (const p of patches) {
    if (p.hatId) ids.add(p.hatId);
  }
  return ids;
}

/** Filter objects to those whose category or typeCoordinate.what starts with the context prefix. */
function filterByContext(
  allObjects: Map<string, LoomObject>,
  context: string,
): Map<string, LoomObject> {
  const filtered = new Map<string, LoomObject>();
  for (const [id, obj] of allObjects) {
    const category = obj.typeDefinition.category ?? '';
    const what = obj.typeCoordinate?.what ?? '';
    if (category.startsWith(context) || what.startsWith(context)) {
      filtered.set(id, obj);
    }
  }
  return filtered;
}

/**
 * Filter identity patches to only those that appear on objects within the scoped set.
 * A patch counts toward context-scoped reputation only if it is literally part of
 * a scoped object's evidence chain (matched by patch.id).
 */
function filterPatchesByContext(
  identityPatches: ObjectPatch[],
  scopedObjects: Map<string, LoomObject>,
): ObjectPatch[] {
  // Build a set of all patch IDs that appear on scoped objects
  const scopedPatchIds = new Set<string>();
  for (const obj of scopedObjects.values()) {
    for (const p of obj.patches) {
      scopedPatchIds.add(p.id);
    }
  }
  // Only include identity patches that are on scoped objects
  return identityPatches.filter(p => scopedPatchIds.has(p.id));
}

/** Compute net dispute outcome score for an identity's hats. */
function computeDisputeOutcomes(
  hatIds: Set<string>,
  objects: Map<string, LoomObject>,
): number {
  let score = 0;

  for (const obj of objects.values()) {
    const category = obj.typeDefinition.category ?? '';

    // Resolution objects — check if identity was involved in the underlying dispute
    if (category === 'governance.resolution') {
      const outcome = obj.payload.outcome as string | undefined;
      const disputeObjectId = obj.payload.disputeObjectId as string | undefined;
      if (!outcome || !disputeObjectId) continue;

      const dispute = objects.get(disputeObjectId);
      if (!dispute) continue;

      const claimantId = dispute.payload.claimantHatId as string | undefined;
      const respondentId = dispute.payload.respondentHatId as string | undefined;

      if (outcome === 'upheld' && claimantId && hatIds.has(claimantId)) {
        score += 5;  // Won as claimant
      }
      if (outcome === 'dismissed' && claimantId && hatIds.has(claimantId)) {
        score -= 3;  // Lost as claimant
      }
      if (outcome === 'upheld' && respondentId && hatIds.has(respondentId)) {
        score -= 3;  // Lost as respondent
      }
      if (outcome === 'dismissed' && respondentId && hatIds.has(respondentId)) {
        score += 5;  // Won as respondent
      }
    }

    // Stake objects — forfeited vs returned
    if (category === 'governance.stake') {
      const stakerHatId = obj.payload.stakerHatId as string | undefined;
      const status = obj.payload.status as string | undefined;
      if (!stakerHatId || !hatIds.has(stakerHatId)) continue;

      if (status === 'forfeited') score -= 5;
      if (status === 'returned') score += 3;
    }
  }

  return score;
}

/** Compute contribution score from approved Ballots where identity was proposer. */
function computeContributions(
  hatIds: Set<string>,
  objects: Map<string, LoomObject>,
): number {
  let score = 0;

  for (const obj of objects.values()) {
    const category = obj.typeDefinition.category ?? '';
    if (category !== 'governance.ballot') continue;

    const status = obj.payload.status as string | undefined;
    if (status !== 'finalized') continue;

    const votesFor = (obj.payload.votesFor as number) ?? 0;
    const votesAgainst = (obj.payload.votesAgainst as number) ?? 0;
    if (votesFor <= votesAgainst) continue;  // Not approved

    // Check if identity proposed this ballot (the creation patch's hatId)
    const creationPatch = obj.patches.find(p => p.kind === 'action' && p.delta.action === 'created');
    if (creationPatch?.hatId && hatIds.has(creationPatch.hatId)) {
      score += 5;
    }
  }

  return score;
}

```
