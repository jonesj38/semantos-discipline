---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/conversation-patch.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.343841+00:00
---

# runtime/intent/src/conversation-patch.ts

```ts
/**
 * writeConversationPatch — the cheap-path primitive.
 *
 * Every user/agent exchange produces one of these. No LLM, no SIR,
 * no kernel. A conversation patch is just "this was said by this hat
 * at this time, attached to this object." It writes through the
 * caller-supplied writer and emits one `conversation_patch_written`
 * stage event keyed by correlationId.
 *
 * Triage (Slice 2b) runs *after* this helper succeeds, deciding
 * whether to also run the expensive pipeline (PROPOSES_INTENT),
 * emit a ratification (RATIFIES_INTENT), or stop (NO_INTENT).
 * Conversation patches are independent of that decision — they
 * always land.
 *
 * See docs/INTENT-PIPELINE.md §"Triage and conversation patches".
 */

import type { CorrelationId, IntentSource, Logger, PatchId, StageEvent } from './types';

// ── ConversationPatchShape — structural, not nominal ─────────
//
// Mirrors the fields on the ObjectPatch union that conversation
// patches actually populate. Imported by a structural `write` dep
// so the intent package stays decoupled from runtime-services.

export interface ConversationPatchShape {
  id: string;
  kind: 'conversation';
  timestamp: number;
  delta: Record<string, unknown>;
  hatId?: string;
  hatCapabilities?: number[];
  /**
   * Optional lexicon name identifying which grammar/domain the
   * author was operating under when they wrote this patch. Federates
   * cleanly across systems: a bundle round-trip preserves
   * "tenant wrote this under OJT's jural lexicon" vs "REA wrote
   * that under project-management." Matches a `Lexicon.name` from
   * `@semantos/semantos-sir`.
   */
  lexicon?: string;
}

// ── Input + deps ─────────────────────────────────────────────

export interface ConversationPatchInput {
  /** The object the message is attached to. */
  objectId: string;
  /** The authoring hat. */
  hatId: string;
  /** The message body — freeform text, attachments URIs, etc. */
  body: unknown;
  /** Hat capabilities at write time, carried into the patch for audit. */
  hatCapabilities?: number[];
  /** Defaults to Date.now(). Injectable for determinism in tests. */
  timestamp?: number;
  /** Defaults to a generated id. Injectable for determinism. */
  patchId?: PatchId;
  /** Threads a turn through multiple writes (conversation + derived + ratification). */
  correlationId?: CorrelationId;
  /** Provenance — which input mode produced this message. */
  source: IntentSource;
  /**
   * Optional lexicon the author's extension operates under. When set,
   * stamps onto the patch's `lexicon` field so federated consumers
   * can route by domain (OJT: 'jural', REA: 'project-management',
   * SCADA: 'control-systems', etc.).
   */
  authorLexicon?: string;
}

export interface ConversationPatchDeps {
  /** Caller-supplied write. Usually dispatches to the loom store. */
  write: (objectId: string, patch: ConversationPatchShape) => Promise<void> | void;
  /** Stage-event sink. */
  logger: Logger;
  /** Patch-id generator used when input.patchId is not supplied. */
  generatePatchId: () => string;
  /** CorrelationId generator used when input.correlationId is not supplied. */
  generateCorrelationId: () => string;
  /** Wall-clock ms. Defaults to Date.now() at the callsite if omitted. */
  now?: () => number;
}

export interface ConversationPatchResult {
  patchId: PatchId;
  correlationId: CorrelationId;
  patch: ConversationPatchShape;
}

// ── Implementation ───────────────────────────────────────────

function asCorrelationId(s: string): CorrelationId {
  return s as CorrelationId;
}
function asPatchId(s: string): PatchId {
  return s as PatchId;
}

export async function writeConversationPatch(
  input: ConversationPatchInput,
  deps: ConversationPatchDeps,
): Promise<ConversationPatchResult> {
  const start = performance.now();

  const patchId: PatchId = input.patchId ?? asPatchId(deps.generatePatchId());
  const correlationId: CorrelationId =
    input.correlationId ?? asCorrelationId(deps.generateCorrelationId());
  const timestamp = input.timestamp ?? (deps.now ? deps.now() : Date.now());

  const patch: ConversationPatchShape = {
    id: patchId,
    kind: 'conversation',
    timestamp,
    delta: { body: input.body, hatId: input.hatId, source: input.source },
    ...(input.hatId ? { hatId: input.hatId } : {}),
    ...(input.hatCapabilities ? { hatCapabilities: input.hatCapabilities } : {}),
    ...(input.authorLexicon ? { lexicon: input.authorLexicon } : {}),
  };

  await deps.write(input.objectId, patch);

  const durationMs = performance.now() - start;
  const event: StageEvent = {
    ts: new Date(timestamp).toISOString(),
    correlationId,
    intentId: null, // no Intent for a cheap conversation patch
    stage: 'conversation_patch_written',
    durationMs,
    hatId: input.hatId,
    source: input.source,
    data: {
      objectId: input.objectId,
      patchId,
    },
  };
  deps.logger.emit(event);

  return { patchId, correlationId, patch };
}

```
