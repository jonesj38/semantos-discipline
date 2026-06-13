---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/ballot-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.112777+00:00
---

# runtime/services/src/services/config-store/ballot-resolver.ts

```ts
/**
 * Pure ballot resolver — given a finalized governance ballot whose
 * "motion" field carries a JSON-encoded taxonomy proposal, produce
 * the corresponding `ConfigOverlay`.
 *
 * Returns null when the ballot is not eligible (not finalized, votes
 * against ≥ for, motion missing or malformed, required fields
 * absent). Same eligibility semantics as the pre-split monolith.
 */

import type { ConfigOverlay, TaxonomyNode } from '../../config/extensionConfig';

export function resolveTaxonomyBallot(
  ballotPayload: Record<string, unknown>,
  ballotId: string,
): ConfigOverlay | null {
  const status = ballotPayload.status as string | undefined;
  const votesFor = (ballotPayload.votesFor as number) ?? 0;
  const votesAgainst = (ballotPayload.votesAgainst as number) ?? 0;
  if (status !== 'finalized' || votesFor <= votesAgainst) return null;

  const motion = ballotPayload.motion as string | undefined;
  if (!motion) return null;

  let motionData: Record<string, unknown>;
  try {
    motionData = JSON.parse(motion);
  } catch {
    return null;
  }

  const axis = motionData.axis as 'what' | 'how' | 'why' | undefined;
  const parentPath = motionData.parentPath as string | undefined;
  const nodeName = motionData.nodeName as string | undefined;
  if (!axis || !parentPath || !nodeName) return null;

  const newPath = `${parentPath}.${nodeName.toLowerCase().replace(/\s+/g, '-')}`;
  const newNode: TaxonomyNode = {
    path: newPath,
    name: nodeName,
    axis,
    metadata: {
      function_type: motionData.functionType ?? 'unspecified',
      rationale: motionData.rationale,
      primary_outputs: motionData.primaryOutputs ?? [],
      required_inputs: motionData.requiredInputs ?? [],
    },
  };

  return {
    id: `overlay-${Date.now()}-${ballotId}`,
    source: 'ballot',
    ballotId,
    appliedAt: Date.now(),
    taxonomyNodes: [newNode],
  };
}

```
