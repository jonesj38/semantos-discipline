---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.347843+00:00
---

# runtime/intent/src/reducer/types.ts

```ts
/**
 * Frozen interface contracts for the trivium/quadrivium intent reducer.
 *
 * All seven pass implementations (I-2..I-8) import from this file.
 * Do not change these interfaces without updating every pass — the
 * pass composer (I-9) folds over PassFn and expects a stable shape.
 *
 * See docs/textbook/32-trivium-quadrivium-intent-reducer.md
 * and docs/prd/INTENT-REDUCER-GRAMMAR-AUTOMATION-PLAN.md
 */

import type { CorrelationId, Intent, IntentId, IntentRejection, Logger } from '../types';
import type { TrustClass, ProofRequirement } from '@semantos/semantos-sir';

// ---------------------------------------------------------------------------
// GrammarSpec
//
// Minimal grammar interface the reducer needs. Structurally compatible with
// ExtensionGrammarSpec from packages/extraction — callers pass the full
// concrete type; the reducer only references this subset. This keeps
// runtime/intent independent of packages/extraction (lower layer rule).
// ---------------------------------------------------------------------------

export interface GrammarObjectType {
  name: string;
  description: string;
}

export interface GrammarAction {
  name: string;
  category: string;
  authoredBy: ReadonlyArray<string>;
  description: string;
}

export interface GrammarSpec {
  extensionId: string;
  domainFlag: number;
  lexicon: { name: string; categories: ReadonlyArray<string> };
  defaultTaxonomyWhat: string;
  actions: ReadonlyArray<GrammarAction>;
  objectTypes: ReadonlyArray<GrammarObjectType>;
  trustClass?: TrustClass;
  proofRequirement?: ProofRequirement;
}

// ---------------------------------------------------------------------------
// ReducerInputState
//
// The normalised input the reducer operates on. This is NOT the same shape
// as AccumulatedJobState — it is the type that oddjobz's adapter function
// produces by combining AccumulatedJobState + the latest turn's taggedFacts.
//
// Dependency rule: runtime/intent does NOT import from @semantos/oddjobz.
// The oddjobz adapter (extensions/oddjobz/src/conversation/) converts from
// AccumulatedJobState → ReducerInputState before calling reduceToIntent.
// ---------------------------------------------------------------------------

export interface TaggedFact {
  lexicon: string;
  category: string;
  confidence: number;
  fact: string;
  source: string;
}

export interface ReducerInputState {
  /** Free-text conversation summary for this turn (e.g. job scope description). */
  conversationSummary?: string;
  /** Structured facts extracted from the conversation by the LLM classifier. */
  taggedFacts: ReadonlyArray<TaggedFact>;
  /** Suburb / locality string, if extracted. */
  suburb?: string | null;
  /** Urgency string from AccumulatedJobState (e.g. 'emergency', 'urgent', 'flexible'). */
  urgency?: string | null;
  /** Job type string (e.g. 'plumbing', 'electrical'). */
  jobType?: string | null;
  /** Scope description — the tenant's free-text description of the job. */
  scopeDescription?: string | null;
  /** Estimated cost lower bound (AUD cents), if extracted. */
  estimatedCostMin?: number | null;
  /** Estimated cost upper bound (AUD cents), if extracted. */
  estimatedCostMax?: number | null;
  /** ISO-8601 datetime for preferred scheduling, if extracted. */
  preferredDatetime?: string | null;
  /** Free-text location / address, if extracted. */
  location?: string | null;
  /** Conversation phase from AccumulatedJobState. */
  conversationPhase?: string | null;
  /** Domain flag from the grammar (propagated from ExtensionGrammarSpec.domainFlag). */
  domainFlag?: number;
}

// ---------------------------------------------------------------------------
// Pass
// ---------------------------------------------------------------------------

export type Pass =
  | 'grammar'      // trivium 1: taxonomy.what
  | 'logic'        // trivium 2: taxonomy.how
  | 'rhetoric'     // trivium 3: TaggedCategory + action
  | 'relation'     // RM-030: SCG typed-relation detection (after rhetoric)
  | 'arithmetic'   // quadrivium 1: value constraints
  | 'geometry'              // quadrivium 2: spatial / taxonomy.where
  | 'music'                 // quadrivium 3: temporal constraints
  | 'astronomy'             // quadrivium 4: governance context
  | 'analogical_prefilter'  // WI-B3: HRR library pre-filter (between rhetoric and arithmetic)
  | 'analogical_rank';      // WI-B4: HRR rank re-score with complete intent (after astronomy)

// ---------------------------------------------------------------------------
// PassFn
// ---------------------------------------------------------------------------

export interface PassContext {
  state: ReducerInputState;
  grammar: GrammarSpec;
  /** SIR rejection from a prior processIntent attempt, if any. */
  priorRejection?: IntentRejection;
  /** Trust-class ceiling imposed by the hat context. */
  maxTrustClass?: TrustClass;
  /**
   * WI-B3 — HRR library for analogical pre-filter. When absent the
   * analogical_prefilter pass returns an empty contribution with confidence=1
   * (vacuously satisfied — cold library is not a failure).
   */
  analogicalLibrary?: { nearest(q: Float64Array, d: number, c: string, k: number, caps: Set<number>): Array<{ cellId: string; similarity: number }> } | null;
  /** Capability set for the analogical query. Defaults to empty set (all entries visible). */
  analogicalCapabilities?: Set<number>;
}

export interface PassResult {
  pass: Pass;
  /** Partial Intent fields contributed by this pass. */
  contribution: Partial<Intent>;
  /** 0–1 confidence for this pass's output. */
  confidence: number;
  /** Flags raised (low confidence fields, missing required fields, etc.). */
  flags: string[];
  /** When true, this pass is excluded from the composite confidence geometric mean.
   *  Used by augmentation passes (analogical_prefilter, analogical_rank) when they
   *  contribute no scoring signal (e.g. no library present). */
  skipInComposite?: boolean;
  /** RM-092 — losing candidates considered by passes that rank multiple
   *  options (rhetoric, relation). Always ordered by descending
   *  `confidence` and strictly below the winner's confidence. Bound to
   *  a small constant (currently 5) to keep traces compact. Absent when
   *  the pass has no choice to make. */
  alternatives?: ReadonlyArray<PassAlternative>;
}

export interface PassAlternative {
  /** Pass-specific candidate payload (e.g. `{ kind: 'SUPPORTS' }` for
   *  the relation pass, `{ action: 'approve_quote', category: ... }`
   *  for rhetoric). Opaque to the reducer; consumers narrow by
   *  inspecting the parent `pass` field on the PassResult. */
  candidate: unknown;
  /** 0–1 confidence — strictly less than the winner's. */
  confidence: number;
  /** Short human-readable reason the candidate lost (e.g.
   *  "matched DISPUTES (0.85) but SUPPORTS (0.95) ranked higher"). */
  reason: string;
}

/** Maximum number of `alternatives` a pass records in a single PassResult.
 *  Keeps traces compact; the underlying ranking is unbounded but we only
 *  surface the top-N losers to consumers. */
export const MAX_PASS_ALTERNATIVES = 5;

/**
 * A single reducer pass. Each pass receives the accumulated partial Intent
 * from all prior passes plus its own context, and returns its contribution.
 *
 * Passes MUST be pure given the same inputs. They MAY read from the
 * accumulated partial to avoid re-deriving upstream results (e.g. the
 * logic pass reads taxonomy.what from the grammar pass output).
 */
export type PassFn = (
  accumulated: Partial<Intent>,
  ctx: PassContext,
) => Promise<PassResult>;

// ---------------------------------------------------------------------------
// ReducerOptions / ReducerResult
// ---------------------------------------------------------------------------

export interface ReducerOptions {
  /** Per-pass confidence thresholds. Defaults: grammar=0.6, logic=0.5, rhetoric=0.7. */
  thresholds?: Partial<Record<Pass, number>>;
  /** If supplied, the previous SIR rejection is relayed to each pass as context. */
  priorRejection?: IntentRejection;
  /** Cap on trust class (hat ceiling propagated from HatContext). */
  maxTrustClass?: TrustClass;
  /**
   * WI-B3 — HRR library for analogical pre-filter. Optional; when absent
   * the pass runs but returns an empty contribution (cold library is fine).
   */
  analogicalLibrary?: PassContext['analogicalLibrary'];
  /** Capability set propagated from the hat context for analogical queries. */
  analogicalCapabilities?: Set<number>;
  /** RM-090 — per-pass observability. When supplied, the reducer emits
   *  a `reducer_pass_completed` StageEvent after each pass with the pass
   *  name, confidence, flags, contribution-key set, and wall-clock
   *  duration. When omitted (the default), the reducer stays silent. */
  logger?: Logger;
  /** RM-090 / RM-091 — correlation tag for emitted events. When the
   *  caller has already minted a correlationId at the producer boundary
   *  (RM-091), pass it through so all events from a single turn share
   *  the same id. The reducer never mints one — it's not the seam where
   *  correlation is born. */
  correlationId?: CorrelationId;
  /** RM-090 — optional intentId to stamp on emitted events. Most reducer
   *  runs are pre-intent (the intent is the reducer's output) so this is
   *  usually null; the field is here for callers that already know the
   *  intent id (e.g. a re-run from stage in RM-095). */
  intentId?: IntentId;
}

export const DEFAULT_THRESHOLDS: Record<Pass, number> = {
  grammar:              0.6,
  logic:                0.5,
  rhetoric:             0.7,
  relation:             0.0, // vacuously satisfied when no relation phrase detected
  arithmetic:           0.5,
  geometry:             0.4,
  music:                0.5,
  astronomy:            0.6,
  analogical_prefilter: 0.0, // vacuously satisfied when library is cold
  analogical_rank:      0.0, // vacuously satisfied when library is cold
};

export interface ReducerResult {
  intent: Intent;
  passResults: PassResult[];
  /** Composite confidence — geometric mean of per-pass confidences. */
  confidence: number;
  /** All flags raised across all passes. */
  flags: string[];
}

```
