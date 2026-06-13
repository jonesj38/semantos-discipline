---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/accumulated-job-state.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.516855+00:00
---

# cartridges/oddjobz/brain/src/conversation/accumulated-job-state.ts

```ts
/**
 * D-O7 — accumulated job state.
 *
 * Origin: `oddjobtodd/src/lib/ai/extractors/extractionSchema.ts` —
 *         the OJT `accumulatedJobStateSchema` + sub-score helpers.
 * Last tuned: 2026-04 (Sprint 3 sub-score refactor).
 *
 * This module is the application-layer companion to D-O6b's
 * `lead-extract.ts`. The dispatcher boundary stays minimal —
 * `LeadExtractResult` exposes only `{has_lead, draft_estimate,
 * confidence}`. The richer state shape (sub-scores, estimate-ack
 * status, customer-fit + worthiness scores, RomInstrument shape)
 * lives here for the conversation state-manager to consume between
 * turns.
 *
 * The OJT version used Zod for parse-time validation; the canon
 * port uses TypeScript types directly with explicit defaults — keeps
 * the extension tree dependency-free (no Zod), and the cell-engine's
 * own validators will own the on-cell validation when the state ever
 * needs to be serialised to a cell.
 *
 * D-O7 scope note: the state DOES NOT become its own cell type. It is
 * rebuilt each turn from the persisted `oddjobz.message.v1` cells +
 * the merged extractions. This avoids minting a parallel "job-state"
 * cell-type that would compete with `oddjobz.job.v1` (D-O2). When the
 * conversation manager wants to checkpoint state, it does so via the
 * Job FSM's transitions — the state lives in the FSM's path through
 * the canonical 8-state graph, not in a side-table.
 */

/* ══════════════════════════════════════════════════════════════════════
 * Accumulated state shape
 * ══════════════════════════════════════════════════════════════════════ */

/** Sub-score axes — each in [0, 100]. */
export interface SubScores {
  readonly scopeClarity: number;
  readonly locationClarity: number;
  readonly contactReadiness: number;
  readonly estimateReadiness: number;
  readonly decisionReadiness: number;
  /** Weighted blend per the OJT formula. */
  readonly total: number;
}

/** Estimate-ack status — verbatim enum from OJT. */
export type EstimateAckStatus =
  | 'accepted'
  | 'tentative'
  | 'uncertain'
  | 'pushback'
  | 'rejected'
  | 'wants_exact_price'
  | 'rate_shopping'
  | 'unclear'
  | 'pending';

/** A single LLM-extracted message — the per-turn delta the merger
 *  reads. Mirror of OJT's `MessageExtraction` minus the Zod parsing. */
export interface MessageExtraction {
  readonly customerName?: string | null;
  readonly customerPhone?: string | null;
  readonly customerEmail?: string | null;
  readonly suburb?: string | null;
  readonly locationClue?: string | null;
  readonly address?: string | null;
  readonly postcode?: string | null;
  readonly accessNotes?: string | null;

  readonly jobType?: string | null;
  readonly jobTypeConfidence?: 'certain' | 'likely' | 'guess' | null;
  readonly jobSubcategory?: string | null;
  readonly repairReplaceSignal?:
    | 'repair'
    | 'replace'
    | 'install'
    | 'inspect'
    | 'unclear'
    | null;
  readonly scopeDescription?: string | null;
  readonly quantity?: string | null;
  readonly materials?: string | null;
  readonly materialCondition?: string | null;
  readonly accessDifficulty?:
    | 'ground_level'
    | 'ladder_required'
    | 'scaffolding_required'
    | 'difficult_access'
    | null;
  readonly photosReferenced?: boolean | null;
  readonly urgency?:
    | 'emergency'
    | 'urgent'
    | 'next_week'
    | 'next_2_weeks'
    | 'flexible'
    | 'when_convenient'
    | 'unspecified'
    | null;

  readonly estimateReaction?: EstimateAckStatus | null;
  readonly budgetReaction?:
    | 'accepted'
    | 'ok'
    | 'unsure'
    | 'expensive'
    | 'cheap'
    | 'wants_hourly'
    | 'wants_guarantee'
    | null;
  readonly customerToneSignal?:
    | 'friendly'
    | 'practical'
    | 'demanding'
    | 'suspicious'
    | 'price_focused'
    | 'vague'
    | 'impatient'
    | null;
  readonly micromanagerSignals?: boolean | null;
  readonly cheapestMindset?: boolean | null;
  readonly clarityScore?: 'very_clear' | 'clear' | 'vague' | 'confused' | null;
  readonly contactReadiness?:
    | 'offered'
    | 'willing'
    | 'reluctant'
    | 'refused'
    | null;
  readonly jobPivot?: 'same_job' | 'additional_scope' | 'different_job' | null;

  readonly conversationPhase?:
    | 'greeting'
    | 'describing_job'
    | 'providing_details'
    | 'providing_location'
    | 'providing_contact'
    | 'reviewing_estimate'
    | 'confirmed'
    | 'disengaged';
  readonly missingInfo?: readonly string[];
  readonly isComplete?: boolean;
}

/** Accumulated job state — the merger output. Verbatim shape from
 *  OJT's `accumulatedJobStateSchema`. */
export interface AccumulatedJobState {
  // Customer
  readonly customerName: string | null;
  readonly customerPhone: string | null;
  readonly customerEmail: string | null;
  // Location
  readonly suburb: string | null;
  readonly locationClue: string | null;
  readonly address: string | null;
  readonly postcode: string | null;
  readonly accessNotes: string | null;
  // Job
  readonly jobType: string | null;
  readonly jobTypeConfidence: string | null;
  readonly jobSubcategory: string | null;
  readonly repairReplaceSignal: string | null;
  readonly scopeDescription: string | null;
  readonly quantity: string | null;
  readonly materials: string | null;
  readonly materialCondition: string | null;
  readonly accessDifficulty: string | null;
  readonly photosReferenced: boolean | null;
  readonly urgency: string | null;
  // Customer signals
  readonly estimateReaction: string | null;
  readonly budgetReaction: string | null;
  readonly customerToneSignal: string | null;
  readonly micromanagerSignals: boolean | null;
  readonly cheapestMindset: boolean | null;
  readonly clarityScore: string | null;
  readonly contactReadiness: string | null;
  // Conversation state
  readonly conversationPhase: string;
  readonly missingInfo: readonly string[];
  // Sub-scores (computed)
  readonly completenessScore: number;
  readonly scopeClarity: number;
  readonly locationClarity: number;
  readonly contactReadinessScore: number;
  readonly estimateReadiness: number;
  readonly decisionReadiness: number;
  // Estimate ack
  readonly estimatePresented: boolean;
  readonly estimateAcknowledged: boolean;
  readonly estimateAckStatus: EstimateAckStatus;
  // Scoring (set by external scoring services)
  readonly customerFitScore: number | null;
  readonly customerFitLabel: string | null;
  readonly quoteWorthinessScore: number | null;
  readonly quoteWorthinessLabel: string | null;
  // SD2 — set once the lead job has been created in the standardised
  // store for this contact (genesis ∅→lead via jobs.create). Optional
  // + persisted so the exactly-once guard survives the multiple
  // done:true turns a conversation can emit (ensure-lead-job.ts).
  readonly leadJobCreated?: boolean;
}

/** Default initial state. */
export function emptyJobState(): AccumulatedJobState {
  return {
    customerName: null,
    customerPhone: null,
    customerEmail: null,
    suburb: null,
    locationClue: null,
    address: null,
    postcode: null,
    accessNotes: null,
    jobType: null,
    jobTypeConfidence: null,
    jobSubcategory: null,
    repairReplaceSignal: null,
    scopeDescription: null,
    quantity: null,
    materials: null,
    materialCondition: null,
    accessDifficulty: null,
    photosReferenced: null,
    urgency: null,
    estimateReaction: null,
    budgetReaction: null,
    customerToneSignal: null,
    micromanagerSignals: null,
    cheapestMindset: null,
    clarityScore: null,
    contactReadiness: null,
    conversationPhase: 'greeting',
    missingInfo: [],
    completenessScore: 0,
    scopeClarity: 0,
    locationClarity: 0,
    contactReadinessScore: 0,
    estimateReadiness: 0,
    decisionReadiness: 0,
    estimatePresented: false,
    estimateAcknowledged: false,
    estimateAckStatus: 'pending',
    customerFitScore: null,
    customerFitLabel: null,
    quoteWorthinessScore: null,
    quoteWorthinessLabel: null,
  };
}

/* ══════════════════════════════════════════════════════════════════════
 * Sub-score computation
 *
 * Verbatim port of OJT's `calculateSubScores` from
 * `extractionSchema.ts` lines 355–416. Thresholds + weights are the
 * operator-tuned numbers; do not change without updating the
 * conversationStateManager thresholds in lockstep.
 * ══════════════════════════════════════════════════════════════════════ */

export function calculateSubScores(state: AccumulatedJobState): SubScores {
  // Scope clarity (0-100)
  let scopeClarity = 0;
  if (state.scopeDescription) scopeClarity += 35;
  if (state.jobType) scopeClarity += 15;
  if (
    state.repairReplaceSignal &&
    state.repairReplaceSignal !== 'unclear'
  )
    scopeClarity += 10;
  if (state.quantity) scopeClarity += 15;
  if (state.materials) scopeClarity += 10;
  if (state.accessDifficulty) scopeClarity += 5;
  if (state.photosReferenced) scopeClarity += 5;
  if (state.urgency && state.urgency !== 'unspecified') scopeClarity += 5;
  scopeClarity = Math.min(100, scopeClarity);

  // Location clarity (0-100)
  let locationClarity = 0;
  if (state.suburb) locationClarity += 60;
  if (state.locationClue && !state.suburb) locationClarity += 20;
  if (state.address) locationClarity += 25;
  if (state.postcode) locationClarity += 10;
  if (state.accessNotes) locationClarity += 5;
  locationClarity = Math.min(100, locationClarity);

  // Contact readiness (0-100)
  let contactReadiness = 0;
  if (state.customerName) contactReadiness += 30;
  if (state.customerPhone) contactReadiness += 40;
  if (state.customerEmail) contactReadiness += 30;
  contactReadiness = Math.min(100, contactReadiness);

  // Estimate readiness — can we give a ROM? (0-100)
  let estimateReadiness = 0;
  if (state.scopeDescription) estimateReadiness += 30;
  if (state.jobType) estimateReadiness += 20;
  if (state.suburb) estimateReadiness += 20;
  if (state.quantity) estimateReadiness += 15;
  if (state.materials || state.materialCondition) estimateReadiness += 10;
  if (state.accessDifficulty) estimateReadiness += 5;
  estimateReadiness = Math.min(100, estimateReadiness);

  // Decision readiness — can the operator act on this? (0-100)
  let decisionReadiness = 0;
  if (state.estimatePresented) decisionReadiness += 15;
  if (state.estimateAcknowledged) decisionReadiness += 20;
  if (
    state.estimateAckStatus === 'accepted' ||
    state.estimateAckStatus === 'tentative'
  )
    decisionReadiness += 10;
  if (state.customerFitScore !== null) decisionReadiness += 10;
  if (state.quoteWorthinessScore !== null) decisionReadiness += 10;
  if (scopeClarity >= 50) decisionReadiness += 15;
  if (locationClarity >= 60) decisionReadiness += 10;
  if (contactReadiness >= 30) decisionReadiness += 10;
  decisionReadiness = Math.min(100, decisionReadiness);

  // Overall completeness — weighted blend (verbatim from OJT)
  const total = Math.min(
    100,
    Math.round(
      scopeClarity * 0.3 +
        locationClarity * 0.15 +
        contactReadiness * 0.15 +
        estimateReadiness * 0.2 +
        decisionReadiness * 0.2,
    ),
  );

  return {
    scopeClarity,
    locationClarity,
    contactReadiness,
    estimateReadiness,
    decisionReadiness,
    total,
  };
}

/* ══════════════════════════════════════════════════════════════════════
 * Merge + scope-overlap helper
 *
 * Verbatim port of OJT's `mergeExtraction` from `extractionSchema.ts`
 * lines 250–341, minus the Zod parsing and the SemanticContext
 * bridging (which is now D-O4's territory). The scope-merge heuristic
 * (>60% word overlap = restatement, <60% = augmentation) is preserved
 * as written.
 * ══════════════════════════════════════════════════════════════════════ */

/** Result of a merge — the merged state plus the field-level delta. */
export interface MergeResult {
  readonly state: AccumulatedJobState;
  readonly delta: Readonly<Record<string, { from: unknown; to: unknown }>>;
  readonly deltaCount: number;
}

/** Merge an extraction into an accumulated state. Only non-null values
 *  from the new extraction overwrite. Returns the merged state +
 *  per-field delta. Pure function. */
export function mergeExtraction(
  current: AccumulatedJobState,
  extraction: MessageExtraction,
): MergeResult {
  const delta: Record<string, { from: unknown; to: unknown }> = {};
  // Build a mutable working copy; freeze on return.
  const merged: { [K in keyof AccumulatedJobState]: AccumulatedJobState[K] } = {
    ...current,
  };

  function setField<K extends keyof AccumulatedJobState>(
    key: K,
    value: AccumulatedJobState[K],
  ): void {
    if (merged[key] !== value) {
      delta[key] = { from: merged[key], to: value };
    }
    merged[key] = value;
  }

  if (extraction.customerName != null)
    setField('customerName', extraction.customerName);
  if (extraction.customerPhone != null)
    setField('customerPhone', extraction.customerPhone);
  if (extraction.customerEmail != null)
    setField('customerEmail', extraction.customerEmail);
  if (extraction.suburb != null) setField('suburb', extraction.suburb);
  if (extraction.locationClue != null)
    setField('locationClue', extraction.locationClue);
  if (extraction.address != null) setField('address', extraction.address);
  if (extraction.postcode != null) setField('postcode', extraction.postcode);
  if (extraction.accessNotes != null)
    setField('accessNotes', extraction.accessNotes);
  if (extraction.jobType != null) {
    setField('jobType', extraction.jobType);
    setField(
      'jobTypeConfidence',
      extraction.jobTypeConfidence ?? merged.jobTypeConfidence,
    );
  }
  if (extraction.jobSubcategory != null)
    setField('jobSubcategory', extraction.jobSubcategory);
  if (extraction.repairReplaceSignal != null)
    setField('repairReplaceSignal', extraction.repairReplaceSignal);

  if (extraction.scopeDescription != null) {
    setField(
      'scopeDescription',
      mergeScopeDescription(
        merged.scopeDescription,
        extraction.scopeDescription,
      ),
    );
  }

  if (extraction.quantity != null) setField('quantity', extraction.quantity);
  if (extraction.materials != null)
    setField('materials', extraction.materials);
  if (extraction.materialCondition != null)
    setField('materialCondition', extraction.materialCondition);
  if (extraction.accessDifficulty != null)
    setField('accessDifficulty', extraction.accessDifficulty);
  if (extraction.photosReferenced !== null && extraction.photosReferenced !== undefined)
    setField('photosReferenced', extraction.photosReferenced);
  if (extraction.urgency != null) setField('urgency', extraction.urgency);

  if (extraction.estimateReaction != null) {
    setField('estimateReaction', extraction.estimateReaction);
    // Bridge extraction → state-machine fields: estimateAcknowledged / estimateAckStatus.
    // The extractor populates estimateReaction; the state manager reads the ack fields.
    if (extraction.estimateReaction !== 'pending') {
      setField('estimateAcknowledged', true);
      setField('estimateAckStatus', extraction.estimateReaction as EstimateAckStatus);
    }
  }
  if (extraction.budgetReaction != null)
    setField('budgetReaction', extraction.budgetReaction);
  if (extraction.customerToneSignal != null)
    setField('customerToneSignal', extraction.customerToneSignal);
  if (
    extraction.micromanagerSignals !== null &&
    extraction.micromanagerSignals !== undefined
  )
    setField('micromanagerSignals', extraction.micromanagerSignals);
  if (
    extraction.cheapestMindset !== null &&
    extraction.cheapestMindset !== undefined
  )
    setField('cheapestMindset', extraction.cheapestMindset);
  if (extraction.clarityScore != null)
    setField('clarityScore', extraction.clarityScore);
  if (extraction.contactReadiness != null)
    setField('contactReadiness', extraction.contactReadiness);

  if (extraction.conversationPhase != null) {
    setField('conversationPhase', extraction.conversationPhase);
    // 'confirmed' implies the customer accepted — infer acknowledgement if
    // not already set explicitly via estimateReaction.
    if (
      extraction.conversationPhase === 'confirmed' &&
      merged.estimatePresented &&
      !merged.estimateAcknowledged
    ) {
      setField('estimateAcknowledged', true);
      if (merged.estimateAckStatus === 'pending') {
        setField('estimateAckStatus', 'accepted');
      }
    }
  }
  if (extraction.missingInfo != null)
    setField('missingInfo', Object.freeze([...extraction.missingInfo]));

  // Recompute sub-scores after merge.
  const sub = calculateSubScores(merged as AccumulatedJobState);
  setField('scopeClarity', sub.scopeClarity);
  setField('locationClarity', sub.locationClarity);
  setField('contactReadinessScore', sub.contactReadiness);
  setField('estimateReadiness', sub.estimateReadiness);
  setField('decisionReadiness', sub.decisionReadiness);
  setField('completenessScore', sub.total);

  return {
    state: Object.freeze(merged) as AccumulatedJobState,
    delta: Object.freeze(delta),
    deltaCount: Object.keys(delta).length,
  };
}

/**
 * Merge two scope-description strings using the OJT word-overlap
 * heuristic. >60% overlap → keep the longer (it's a restatement);
 * <60% overlap → concatenate (genuinely new info). Verbatim from
 * OJT origin (chatService.ts lines 281–303).
 */
export function mergeScopeDescription(
  existing: string | null,
  incoming: string,
): string {
  if (!existing) return incoming;
  const existingWords = new Set(
    existing
      .toLowerCase()
      .split(/\s+/)
      .filter((w) => w.length > 2),
  );
  const incomingWords = incoming
    .toLowerCase()
    .split(/\s+/)
    .filter((w) => w.length > 2);
  const overlap =
    incomingWords.filter((w) => existingWords.has(w)).length /
    Math.max(incomingWords.length, 1);
  if (overlap >= 0.6) {
    return incoming.length >= existing.length ? incoming : existing;
  }
  return `${existing}. ${incoming}`;
}

```
