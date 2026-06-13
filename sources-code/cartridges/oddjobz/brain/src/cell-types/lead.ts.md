---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/lead.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.502081+00:00
---

# cartridges/oddjobz/brain/src/cell-types/lead.ts

```ts
/**
 * `oddjobz.lead.v1` — AFFINE cell.
 *
 * D-O6b — Public chat v1.0. The Lead cell captures the operator-
 * ratification provenance of a chat-extracted (or otherwise sourced)
 * inbound inquiry. Distinct from the Job FSM `lead` *state*, which is a
 * transient state on the LINEAR Job cell. A `oddjobz.lead.v1` cell is
 * minted at ratification time alongside the freshly-driven `∅ → lead`
 * Job genesis transition; the Lead cell is the audit-anchor that links
 * the chat session, the drafted Estimate, and the materialised Job into
 * a single signed envelope under the operator's hat.
 *
 * Linearity choice — AFFINE — chosen because:
 *   • A Lead is `used at most once`: the ratification fires exactly
 *     once, then the Lead has done its job (anchor the provenance).
 *   • DROP is permitted: stale Leads on rejected drafts are simply
 *     allowed to lapse; we don't force a successor state.
 *   • DUP is denied: duplicating a Lead would duplicate the audit
 *     anchor — a single Job comes from a single Lead.
 *
 * The §O6b spec brief explicitly authors this cell as the bridge
 * between the §O6b ratification queue and the §O4 Job FSM `∅ → lead`
 * row. No FSM transition consumes a Lead; the Lead itself is the
 * record-of-creation for a Job, sitting alongside it in the substrate.
 *
 * Field shape matches the §O6b spec brief (Deliverable 4):
 *
 *   leadId                 — stable ID for this lead (UUID v4)
 *   chatSessionId          — FK to the chat thread the lead came from
 *                            (opaque string per the visitor's session
 *                            cookie); empty for non-chat provenance
 *   extractedEstimateId    — FK to the just-signed
 *                            `oddjobz.estimate.v1` cell (UUID v4)
 *   customerHint           — free-form name/contact extracted from chat
 *                            (NOT yet a Customer cell; the operator
 *                            decides whether to mint one on ratify)
 *   jobId                  — FK to the freshly-minted Job from
 *                            `∅ → lead` (UUID v4)
 *   ratifiedBy             — operator cert id who signed the
 *                            ratification (16-byte hex)
 *   ratifiedAt             — ISO-8601 ratification timestamp
 *   provenance             — enum `from_chat` | `from_walk_in` |
 *                            `from_phone` | `from_email` | `from_sms`
 *                            | `from_referral`
 *
 * The cell is signed under the operator's hat at ratification — the
 * same context-tag scheme `cap.oddjobz.write_customer` carries.
 *
 * ── Lean spec status ─────────────────────────────────────────────────
 *
 * The existing `proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/`
 * tree carries per-FSM theorems (transition totality, consumption
 * single-firing, kernel-gate parity). It does NOT carry per-cell-type
 * theorems — the cell-type side of the extension is covered by the
 * core K1/K2/K3a theorems against the wire-level linearity codes,
 * which the §O2 cell types already inherit by carrying `wireLinearity`
 * codes the kernel-side proofs are stated over.
 *
 * D-O6b's Lead cell adds nothing structurally new from the kernel's
 * point of view: it is wire-level AFFINE (code 2), same as Estimate.
 * The substrate-level proofs (LinearityK1, AuthSoundnessK2,
 * DomainIsolationK3, FailureAtomicK4) cover it without modification.
 *
 * Per-cell-type Lean specs (a hypothetical
 * `proofs/lean/Semantos/Extensions/Oddjobz/CellTypes/Lead.lean`)
 * are DEFERRED — the existing Lean shape doesn't include such a
 * directory and adding one would set a per-cell-type-theorem
 * precedent that needs design discussion (every D-O2 cell would then
 * want its own Lean file). For D-O6b the deferral is recorded here;
 * a follow-up commission can land per-cell-type Lean specs uniformly
 * for all nine cells.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertOptionalString,
  assertNonEmptyString,
  assertEnum,
  assertIsoDateString,
} from './validators.js';

export const LEAD_PROVENANCES = [
  'from_chat',
  'from_walk_in',
  'from_phone',
  'from_email',
  'from_sms',
  'from_referral',
] as const;
export type LeadProvenance = (typeof LEAD_PROVENANCES)[number];

export interface OddjobzLead {
  /** Stable lead identifier (UUID v4). */
  readonly leadId: string;
  /**
   * Chat session the lead was extracted from (opaque string, matches
   * the visitor's `session_id` from the chat widget). Empty string for
   * non-chat provenances (walk-in, phone, etc.).
   */
  readonly chatSessionId: string;
  /** FK to the just-signed `oddjobz.estimate.v1` cell (UUID v4). */
  readonly extractedEstimateId: string;
  /**
   * Free-form customer hint extracted from the chat (name + contact).
   * Not a structured customer record yet — that's a separate operator
   * decision after ratification. Empty string allowed when the chat
   * carried no contact info but the operator ratifies anyway.
   */
  readonly customerHint: string;
  /** FK to the freshly-minted Job (UUID v4) from §O4 `∅ → lead`. */
  readonly jobId: string;
  /**
   * Operator cert id (16-byte hex) that signed the ratification.
   * Lower-case, no separator, exactly 32 chars.
   */
  readonly ratifiedBy: string;
  /** ISO-8601 ratification timestamp. */
  readonly ratifiedAt: string;
  /** Where the lead came from. */
  readonly provenance: LeadProvenance;
}

const HEX16_RE = /^[0-9a-f]{32}$/;

function assertHex16(field: string, value: unknown): asserts value is string {
  if (typeof value !== 'string' || !HEX16_RE.test(value)) {
    throw new Error(`field ${field}: not a 16-byte lower-case hex string`);
  }
}

function assertChatSessionId(field: string, value: unknown): asserts value is string {
  if (typeof value !== 'string') {
    throw new Error(`field ${field}: not a string`);
  }
  if (value.length > 256) {
    throw new Error(`field ${field}: too long (max 256 chars)`);
  }
}

function assertCustomerHint(field: string, value: unknown): asserts value is string {
  if (typeof value !== 'string') {
    throw new Error(`field ${field}: not a string`);
  }
  if (value.length > 4000) {
    throw new Error(`field ${field}: too long (max 4000 chars)`);
  }
}

function validate(v: OddjobzLead): void {
  assertUuid('leadId', v.leadId);
  assertChatSessionId('chatSessionId', v.chatSessionId);
  assertUuid('extractedEstimateId', v.extractedEstimateId);
  assertCustomerHint('customerHint', v.customerHint);
  assertUuid('jobId', v.jobId);
  assertHex16('ratifiedBy', v.ratifiedBy);
  assertIsoDateString('ratifiedAt', v.ratifiedAt);
  assertEnum('provenance', v.provenance, LEAD_PROVENANCES);

  // Cross-field invariant: chat-provenance leads MUST carry a non-empty
  // chatSessionId. Other provenances MAY (e.g. an operator on the phone
  // takes notes that happen to share a session id with a prior chat).
  if (v.provenance === 'from_chat' && v.chatSessionId.length === 0) {
    throw new Error(
      'lead: provenance=from_chat requires non-empty chatSessionId',
    );
  }
  // Avoid unused-imports warnings.
  void assertOptionalString;
  void assertNonEmptyString;
}

function toCanonical(v: OddjobzLead): Record<string, unknown> {
  return {
    leadId: v.leadId,
    chatSessionId: v.chatSessionId,
    extractedEstimateId: v.extractedEstimateId,
    customerHint: v.customerHint,
    jobId: v.jobId,
    ratifiedBy: v.ratifiedBy,
    ratifiedAt: v.ratifiedAt,
    provenance: v.provenance,
  };
}

function fromCanonical(c: unknown): OddjobzLead {
  if (typeof c !== 'object' || c === null) {
    throw new Error('lead: payload not an object');
  }
  const r = c as Record<string, unknown>;
  return {
    leadId: r.leadId as string,
    chatSessionId: r.chatSessionId as string,
    extractedEstimateId: r.extractedEstimateId as string,
    customerHint: r.customerHint as string,
    jobId: r.jobId as string,
    ratifiedBy: r.ratifiedBy as string,
    ratifiedAt: r.ratifiedAt as string,
    provenance: r.provenance as LeadProvenance,
  };
}

export const leadCellType: CellTypeDef<OddjobzLead> = defineCellType({
  name: 'oddjobz.lead.v1',
  identity: {
    whatPath: 'oddjobz.lead',
    howSlug: 'ratify',
    instPath: 'inst.signal.lead-anchor',
  },
  // §O6b — AFFINE: used at most once at ratify, droppable on stale
  // queue entries. See module head for the linearity-choice rationale.
  linearity: 'AFFINE',
  toCanonical,
  fromCanonical,
  validate,
});

```
