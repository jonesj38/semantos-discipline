---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/handle-message.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.345730+00:00
---

# runtime/intent/src/handle-message.ts

```ts
/**
 * handleMessage — the full conversation-turn orchestrator.
 *
 * For every incoming user/agent message the orchestrator:
 *
 *   1. Writes a conversation patch (cheap path — always happens).
 *   2. Looks up pending proposals on the object (so the classifier
 *      can recognise RATIFIES outcomes).
 *   3. Runs triage — NO_INTENT / PROPOSES / RATIFIES.
 *   4. Dispatches:
 *        NO_INTENT → return — only the conversation patch landed
 *        PROPOSES  → run processIntent; derived patch carries
 *                    companionOf → the conversation patch
 *        RATIFIES  → issueRatification; no SIR/IR/kernel
 *
 * The whole turn shares ONE correlationId, from the conversation
 * patch through every downstream event. A single grep over the
 * JSONL stream reconstructs the turn's full trace.
 *
 * See docs/INTENT-PIPELINE.md §"Triage and conversation patches".
 */

import type {
  CorrelationId,
  HatContext,
  IntentResult,
  IntentSource,
  Logger,
  PatchId,
  RatificationPatch,
} from './types';
import {
  writeConversationPatch,
  type ConversationPatchDeps,
  type ConversationPatchShape,
} from './conversation-patch';
import {
  issueRatification,
  type IssueRatificationDeps,
  type RatificationPatchShape,
} from './ratification';
import { triage, type Classifier } from './triage';
import { processIntent } from './pipeline';
import type { PipelineDeps } from './pipeline';
import type { Intent } from './types';
import {
  extractProposedSlot,
  type CalendarGuard,
  type ProposedSlot,
  type CalendarConflictRecord,
  type FreeWindow,
} from './calendar-guard';

// ── PendingProposalRegistry — minimal interface ─────────────
//
// The orchestrator needs to know which derived patches on an object
// are currently `ratificationState: 'pending'`. The persistence
// layer owns that state; we take a narrow lookup here so the intent
// package doesn't have to know about store shape.

export interface PendingProposal {
  patchId: PatchId;
  summary: string;
}

export interface PendingProposalLookup {
  /** Returns the open pending proposals for the given object, oldest-first. */
  listPendingForObject(objectId: string): Promise<ReadonlyArray<PendingProposal>>;
  /**
   * Called after a PROPOSES → pipeline run completes successfully.
   * Records the derived patch as pending, so a later RATIFIES can
   * find it.
   */
  markProposed(
    objectId: string,
    proposal: PendingProposal,
    correlationId: CorrelationId,
  ): Promise<void>;
  /**
   * Called after a RATIFIES close-out. Flips the proposal from
   * pending → ratified; the ratification patch id is recorded for
   * audit.
   */
  markRatified(
    objectId: string,
    pendingPatchId: PatchId,
    ratificationPatchId: PatchId,
  ): Promise<void>;
}

// ── Input + deps ─────────────────────────────────────────────

export interface HandleMessageInput {
  /** The object this message is attached to. */
  objectId: string;
  /** The authoring hat. */
  hat: HatContext;
  /** Message body — free-form text, attachments, etc. */
  body: unknown;
  /** Input mode. */
  source: IntentSource;
  /** Optional explicit correlationId to thread through. */
  correlationId?: CorrelationId;
  /**
   * Optional lexicon name the authoring hat's extension operates
   * under. Stamped onto the conversation patch and onto any
   * pipeline-derived artifacts so federated consumers can see
   * which domain each patch came from. OJT passes 'jural'; REA
   * passes 'project-management'; SCADA passes 'control-systems';
   * etc. Match a `Lexicon.name` from `@semantos/semantos-sir`.
   */
  authorLexicon?: string;
  /**
   * Hook invoked when triage returns PROPOSES. Receives the intent
   * the classifier produced plus the conversation patch id and must
   * return a summary string for the pending-proposals registry.
   * The orchestrator runs processIntent afterward.
   */
  onProposed?: (args: {
    intent: Intent;
    conversationPatchId: PatchId;
  }) => { summary: string } | undefined;
}

export interface HandleMessageDeps {
  /** Cheap conversation-patch writer deps. */
  conversation: Omit<ConversationPatchDeps, 'logger'>;
  /** Ratification writer deps. */
  ratification: Omit<IssueRatificationDeps, 'logger'>;
  /** Classifier used by triage. */
  classifier: Classifier;
  /** Registry for pending proposals. */
  pendingRegistry: PendingProposalLookup;
  /** Kernel / storage / sign / uuid for full-pipeline runs. */
  pipeline: PipelineDeps;
  /** Single shared logger — every stage event on the turn uses this. */
  logger: Logger;
  /** Wall-clock. Used for hat context's extension bits. */
  now?: () => number;
  /**
   * Optional A5 calendar guard. If supplied AND the PROPOSES-triage
   * intent carries a `proposedSlot` delta, the guard runs BEFORE the
   * pipeline. Conflicts short-circuit to `reject_conflict` with free
   * windows. No guard = calendar step skipped (legacy behaviour).
   */
  calendarGuard?: CalendarGuard;
  /**
   * Optional free-window lookahead for REJECT_CONFLICT responses.
   * Defaults to 21 days from the proposed startAt, limit 5.
   */
  freeWindowLookahead?: {
    days?: number;
    limit?: number;
  };
}

// ── Result union ────────────────────────────────────────────

export type HandleMessageResult =
  | {
      kind: 'no_intent';
      conversationPatchId: PatchId;
      correlationId: CorrelationId;
      reason: string;
    }
  | {
      kind: 'proposed';
      conversationPatchId: PatchId;
      correlationId: CorrelationId;
      intentResult: IntentResult;
    }
  | {
      kind: 'ratified';
      conversationPatchId: PatchId;
      correlationId: CorrelationId;
      ratification: RatificationPatch;
      ratificationPatchId: PatchId;
      pendingPatchId: PatchId;
    }
  | {
      /**
       * A5: the classifier proposed a booking for a specific slot, but
       * the injected CalendarGuard reported conflicts. The pipeline
       * was NOT run; no derived patch was written. The caller should
       * surface a conflict message to the user, typically listing the
       * `freeWindows` as alternatives.
       */
      kind: 'reject_conflict';
      conversationPatchId: PatchId;
      correlationId: CorrelationId;
      proposedSlot: ProposedSlot;
      conflictingBookings: CalendarConflictRecord[];
      conflictingHolds: CalendarConflictRecord[];
      freeWindows: FreeWindow[];
    };

// ── Orchestrator ────────────────────────────────────────────

export async function handleMessage(
  input: HandleMessageInput,
  deps: HandleMessageDeps,
): Promise<HandleMessageResult> {
  // 1. Conversation patch — always land.
  const conv = await writeConversationPatch(
    {
      objectId: input.objectId,
      hatId: input.hat.hatId,
      body: input.body,
      hatCapabilities: input.hat.capabilities,
      source: input.source,
      correlationId: input.correlationId,
      authorLexicon: input.authorLexicon,
    },
    { ...deps.conversation, logger: deps.logger },
  );

  // 2. Look up pending proposals for triage.
  const pending = await deps.pendingRegistry.listPendingForObject(input.objectId);

  // 3. Triage.
  const outcome = await triage(
    {
      body: input.body,
      conversationPatchId: conv.patchId,
      objectId: input.objectId,
      hat: input.hat,
      source: input.source,
      pendingProposals: pending,
      correlationId: conv.correlationId,
    },
    { classifier: deps.classifier, logger: deps.logger },
  );

  // 4. Dispatch.
  switch (outcome.kind) {
    case 'no_intent':
      return {
        kind: 'no_intent',
        conversationPatchId: conv.patchId,
        correlationId: conv.correlationId,
        reason: outcome.reason,
      };

    case 'ratifies': {
      const ratResult = await issueRatification(
        {
          objectId: input.objectId,
          pendingPatchId: outcome.pendingPatchId,
          hat: input.hat,
          attestation: outcome.attestation,
          correlationId: conv.correlationId,
        },
        { ...deps.ratification, logger: deps.logger },
      );
      await deps.pendingRegistry.markRatified(
        input.objectId,
        outcome.pendingPatchId,
        ratResult.patchId,
      );
      return {
        kind: 'ratified',
        conversationPatchId: conv.patchId,
        correlationId: conv.correlationId,
        ratification: ratResult.ratification,
        ratificationPatchId: ratResult.patchId,
        pendingPatchId: outcome.pendingPatchId,
      };
    }

    case 'proposes': {
      // The classifier has produced an Intent; ensure companionOf is
      // threaded even if the classifier forgot (defensive).
      const intent: Intent = {
        ...outcome.intent,
        companionOf: outcome.intent.companionOf ?? conv.patchId,
        correlationId: outcome.intent.correlationId ?? conv.correlationId,
      };

      // A5 calendar guard: if the intent's delta carries a proposedSlot
      // AND a guard was injected, check availability BEFORE running the
      // pipeline. Conflicts short-circuit to reject_conflict; the bot's
      // chat route picks up the free windows and surfaces them to the
      // user.
      if (deps.calendarGuard) {
        const slot = extractProposedSlot((intent as unknown as { delta?: unknown }).delta);
        if (slot) {
          const report = await deps.calendarGuard.findConflicts(slot);
          if (
            report.conflictingBookings.length > 0 ||
            report.conflictingHolds.length > 0
          ) {
            const lookaheadDays = deps.freeWindowLookahead?.days ?? 21;
            const lookaheadLimit = deps.freeWindowLookahead?.limit ?? 5;
            const durationMinutes = Math.max(
              15,
              Math.round(
                (slot.endAt.getTime() - slot.startAt.getTime()) / 60_000,
              ),
            );
            const freeWindows = await deps.calendarGuard.findFreeWindows({
              hatId: slot.hatId,
              fromAt: slot.startAt,
              toAt: new Date(
                slot.startAt.getTime() + lookaheadDays * 86_400_000,
              ),
              durationMinutes,
              limit: lookaheadLimit,
            });
            return {
              kind: 'reject_conflict',
              conversationPatchId: conv.patchId,
              correlationId: conv.correlationId,
              proposedSlot: slot,
              conflictingBookings: report.conflictingBookings,
              conflictingHolds: report.conflictingHolds,
              freeWindows,
            };
          }
        }
      }

      const intentResult = await processIntent(
        intent,
        {
          hat: input.hat,
          logger: deps.logger,
          correlationId: conv.correlationId,
        },
        deps.pipeline,
      );

      // If the pipeline produced a cell (happy path), register the
      // proposal as pending for future ratification lookup.
      if (intentResult.ok && intentResult.cell) {
        const summary =
          input.onProposed?.({ intent, conversationPatchId: conv.patchId })
            ?.summary ?? intent.summary;
        await deps.pendingRegistry.markProposed(
          input.objectId,
          { patchId: intentResult.cell.id as unknown as PatchId, summary },
          conv.correlationId,
        );
      }

      return {
        kind: 'proposed',
        conversationPatchId: conv.patchId,
        correlationId: conv.correlationId,
        intentResult,
      };
    }
  }
}

// ── In-memory registry — for tests + dev ───────────────────

export function createInMemoryPendingRegistry(): PendingProposalLookup & {
  snapshot: () => Record<string, ReadonlyArray<PendingProposal>>;
} {
  const byObject = new Map<string, PendingProposal[]>();

  return {
    async listPendingForObject(objectId) {
      return byObject.get(objectId) ?? [];
    },
    async markProposed(objectId, proposal) {
      const list = byObject.get(objectId) ?? [];
      list.push(proposal);
      byObject.set(objectId, list);
    },
    async markRatified(objectId, pendingPatchId) {
      const list = byObject.get(objectId);
      if (!list) return;
      byObject.set(
        objectId,
        list.filter(p => p.patchId !== pendingPatchId),
      );
    },
    snapshot() {
      const out: Record<string, ReadonlyArray<PendingProposal>> = {};
      for (const [k, v] of byObject.entries()) out[k] = [...v];
      return out;
    },
  };
}

// Re-exports for convenience.
export type { ConversationPatchShape, RatificationPatchShape };

```
