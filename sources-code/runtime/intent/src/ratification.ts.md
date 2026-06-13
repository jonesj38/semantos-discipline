---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/ratification.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.341960+00:00
---

# runtime/intent/src/ratification.ts

```ts
/**
 * issueRatification — the cheap signed-pointer close-out.
 *
 * A RATIFIES_INTENT outcome doesn't need a fresh SIR/IR/kernel run.
 * The message is a Boolean acceptance of an earlier pending proposal;
 * a signed pointer at that proposal's patch id IS the formal proof on
 * the eventual authoritative-tier state transition.
 *
 * This helper:
 *   1. Writes a ratification patch to storage via the caller-supplied
 *      writer (companion to the conversation patch that carried the
 *      "approved" message).
 *   2. Emits one `ratification_issued` stage event keyed by
 *      correlationId so the audit chain stitches up cleanly.
 *
 * It does NOT mutate the pending proposal's `ratificationState` —
 * that's the caller's registry concern (orchestrator layer).
 *
 * See docs/INTENT-PIPELINE.md §"Triage and conversation patches".
 */

import type {
  CorrelationId,
  HatContext,
  Logger,
  PatchId,
  RatificationPatch,
  Signature,
  StageEvent,
} from './types';

// ── Structural shape of the ratification-kind patch on disk ──
//
// Parallels `ConversationPatchShape` — structural so the intent
// package doesn't import runtime-services' ObjectPatch union.
// Callers adapt to their own persistence type.

export interface RatificationPatchShape {
  id: string;
  kind: 'ratification';
  timestamp: number;
  delta: Record<string, unknown>;
  hatId?: string;
  hatCapabilities?: number[];
}

// ── Input + deps ─────────────────────────────────────────────

export interface IssueRatificationInput {
  /** The object this ratification is attached to. */
  objectId: string;
  /** The pending proposal patch being ratified. */
  pendingPatchId: PatchId;
  /** The attesting hat. */
  hat: HatContext;
  /** The signature over the ratification preimage. */
  attestation: Signature;
  /** Correlation id — same turn as the conversation + triage. */
  correlationId: CorrelationId;
  /** Defaults to Date.now(). */
  timestamp?: number;
  /** Optional explicit patch id. */
  ratificationPatchId?: PatchId;
}

export interface IssueRatificationDeps {
  write: (objectId: string, patch: RatificationPatchShape) => Promise<void> | void;
  logger: Logger;
  generatePatchId: () => string;
  now?: () => number;
}

export interface IssueRatificationResult {
  patchId: PatchId;
  patch: RatificationPatchShape;
  ratification: RatificationPatch;
}

// ── Implementation ───────────────────────────────────────────

export async function issueRatification(
  input: IssueRatificationInput,
  deps: IssueRatificationDeps,
): Promise<IssueRatificationResult> {
  const start = performance.now();

  const patchId = (input.ratificationPatchId ?? deps.generatePatchId()) as PatchId;
  const timestamp = input.timestamp ?? (deps.now ? deps.now() : Date.now());

  const ratification: RatificationPatch = {
    kind: 'ratification',
    ratifies: input.pendingPatchId,
    signedBy: input.hat,
    attestation: input.attestation,
    correlationId: input.correlationId,
  };

  const patch: RatificationPatchShape = {
    id: patchId,
    kind: 'ratification',
    timestamp,
    delta: {
      ratifies: input.pendingPatchId,
      signedBy: input.hat.hatId,
      attestation: {
        algorithm: input.attestation.algorithm,
        keyId: input.attestation.keyId,
        // bytes carried separately — base64 at the storage layer
      },
    },
    hatId: input.hat.hatId,
    hatCapabilities: input.hat.capabilities.slice(),
  };

  await deps.write(input.objectId, patch);

  const durationMs = performance.now() - start;
  const event: StageEvent = {
    ts: new Date(timestamp).toISOString(),
    correlationId: input.correlationId,
    intentId: null, // ratification has no Intent — it's a signed pointer
    stage: 'ratification_issued',
    durationMs,
    hatId: input.hat.hatId,
    source: 'nl', // ratifications today come only from conversational paths
    data: {
      pendingPatchId: input.pendingPatchId,
      ratificationPatchId: patchId,
    },
  };
  deps.logger.emit(event);

  return { patchId, patch, ratification };
}

```
