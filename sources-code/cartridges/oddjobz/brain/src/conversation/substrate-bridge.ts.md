---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/substrate-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.517207+00:00
---

# cartridges/oddjobz/brain/src/conversation/substrate-bridge.ts

```ts
/**
 * D-O7 — substrate-bridge surface.
 *
 * Origin: `oddjobtodd/src/lib/domain/bridge/semanticRuntimeAdapter.ts`
 *         (the SHIM that delegated to OJT's `semantos-kernel/`).
 *
 * Provenance note: most of the OJT bridge is obsolete in canon.
 * D-O7-OJT-SALVAGE-REPORT.md Finding 6's mapping table:
 *
 *   | OJT shim function          | Canon replacement                                         |
 *   | -------------------------- | --------------------------------------------------------- |
 *   | ensureSemanticObject       | D-O2 OddjobzJob cell + D-O4 genesisJobLead                |
 *   | recordStateSnapshot        | D-O4 jobTransition (each transition mints a successor)    |
 *   | recordScores               | Out of scope — application logic; cell carries inputs     |
 *   | recordEvidence             | D-O6b oddjobz.message.v1 cell via chat-persistence        |
 *   | recordInstrument           | D-O6b lead-extract.ts draftEstimate                       |
 *   | recordStatusTransition     | D-O4 jobTransition returns {consumedCellId, successorCellId} |
 *
 * What's left to port: the typed Plumbing surface — a single `BridgeContext`
 * that the conversation manager threads through (chatSessionId, jobId,
 * customerId, hat-scoping context, the dispatcher resource handles).
 * The shim's internal singleton-cache pattern is dropped: D-O7 wires
 * the dispatcher per-call, no module-level state.
 *
 * This module deliberately has NO behaviour beyond the typed shape.
 * The actual "record" functions are the canon work merged at D-O4 +
 * D-O6b — callers reach those directly. This module exists so the
 * conversation/state-manager.ts caller has a typed surface to thread
 * through to chat-persistence + lead-extract + ratification-queue.
 */

import type { OddjobzHat } from './hat-scoping.js';

/* ══════════════════════════════════════════════════════════════════════
 * BridgeContext — what the conversation manager threads through
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * The typed surface for one conversation turn. Carries the IDs the
 * dispatcher resources need + the hat under which the turn is
 * authored. Pure value — no behaviour. The bridge calls (chat
 * persistence, lead extract, ratification) are reached via the
 * dispatcher's resource interface in production; the conversation
 * manager passes this context through to whichever helper it invokes.
 *
 * The `hat` field is the K3-grounded hat-scoping anchor. Every
 * persistence call that flows through this context inherits the
 * hat's contextTag — the cell-engine kernel-gate then enforces
 * cryptographic hat-isolation at cap-presentation time. Application-
 * layer filtering is no longer the gate; the hat IS the gate.
 */
export interface BridgeContext {
  /** Stable chat session id (D-O6b chat-persistence input). */
  readonly chatSessionId: string;
  /** Stable job id (UUID v4) — null when the job hasn't been minted
   *  yet (the lead-extract / ratification path mints it). */
  readonly jobId: string | null;
  /** Stable customer id (UUID v4) — null pre-ratification. */
  readonly customerId: string | null;
  /** Hat under which this conversation turn is authored. */
  readonly hat: OddjobzHat;
  /** Wall-clock timestamp for this turn (ISO-8601). */
  readonly nowIso: string;
}

/** Build a BridgeContext for a turn. */
export function buildBridgeContext(input: BridgeContext): BridgeContext {
  return Object.freeze({
    chatSessionId: input.chatSessionId,
    jobId: input.jobId,
    customerId: input.customerId,
    hat: input.hat,
    nowIso: input.nowIso,
  });
}

/**
 * Re-export the per-turn helpers the conversation manager actually
 * calls. Each helper lives in its canon module — this index gives
 * callers a single import surface.
 *
 * If the conversation manager wants to record something the canon
 * doesn't yet have a primitive for (e.g. a customer-fit score that
 * isn't yet a dedicated cell-type), the right path is to add a new
 * cell-type at D-O2 in a follow-up deliverable, NOT to extend this
 * bridge with side-table writes — the OJT-era shim is what we are
 * eliminating, not duplicating.
 */
export type { ChatPersistenceInput } from '../chat-persistence.js';
export {
  buildVisitorMessageCell,
  buildAiMessageCell,
  buildChatTurn,
} from '../chat-persistence.js';
export {
  extractLead,
  type LeadExtractInput,
  type LeadExtractResult,
} from '../lead-extract.js';
export {
  RatificationQueue,
  type RatifyInput,
  type RatifyResult,
} from '../ratification-queue.js';

```
