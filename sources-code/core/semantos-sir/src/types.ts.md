---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.813301+00:00
---

# core/semantos-sir/src/types.ts

```ts
/**
 * Semantic IR (SIR) — types for the jural-category representation layer.
 *
 * The SIR sits above the OIR (packages/semantos-ir) and captures *what* is
 * being expressed — the jural category, domain taxonomy, governance context,
 * and linearity — rather than *how* the machine enforces it.
 *
 * Pipeline:  SIRProgram ──lowerSIR()──► IRProgram ──emit()──► Uint8Array
 */

import type { IdentityRef, ComparisonOp, LinearityMode } from '@semantos/semantos-ir/expr';
import type { IRProgram } from '@semantos/semantos-ir/types';
import type { RelationKind } from '@semantos/scg-relations';
import type { TaggedCategory } from './lexicons';
import type { LexiconAuthority } from './authority';

// Re-export for convenience
export type { IdentityRef, ComparisonOp, LinearityMode };

// ── Jural Categories ─────────────────────────────────────────

/** The seven jural categories — Hohfeldian relations adapted for computational governance. */
export type JuralCategory =
  | 'declaration'    // assertion of fact or state
  | 'obligation'     // duty that must be fulfilled
  | 'permission'     // authorisation to act
  | 'prohibition'    // constraint that action must not occur
  | 'power'          // authority to change relations
  | 'condition'      // temporal or state-dependent trigger
  | 'transfer';      // movement of value, rights, or obligations

// ── Taxonomy Coordinates ─────────────────────────────────────

/** Six-axis coordinates into the domain taxonomy (RM-103).
 *
 * `what` / `how` / `why` are required since Wave 1; `where` joined in
 * Phase H; `who` and `when` were promoted to first-class in Wave 10
 * follow-up after the cell-on-rbs audit found the substrate already
 * had 4-axis taxonomy but operator transcripts naturally surface
 * "who" (subject — customer/contact/cert) and "when" (temporal
 * coordinate) too. Producers emit them when the transcript implies
 * them; downstream consumers (entity resolver, action router,
 * pask retrieval) treat them as optional discriminators. */
export interface TaxonomyCoordinates {
  what: string;           // e.g. "rates.swap.fixed-float", "sensor.pressure.gauge"
  how: string;            // e.g. "lifecycle.settlement", "command.valve.open"
  why: string;            // e.g. "obligation-fulfillment", "safety-interlock"
  where?: string;         // optional spatial/jurisdictional coordinate
  who?: string;           // optional subject ref — customer cellId,
                          // cert id, or operator-readable name when no
                          // cellId resolved yet (resolver upgrades to id)
  when?: string;          // optional temporal coordinate — ISO 8601
                          // datetime, ISO date, or natural-language
                          // bucket ("tomorrow morning" etc. that a
                          // downstream resolver normalises)
}

// ── Governance Context ───────────────────────────────────────

export type TrustClass = 'cosmetic' | 'interpretive' | 'authoritative';
export type ProofRequirement = 'none' | 'attestation' | 'formal';
export type ExecutionAuthority = 'local_facet' | 'hat_scoped' | 'delegated';

/** Governance context — carried through the IR, enforced at lowering. */
export interface GovernanceContext {
  trustClass: TrustClass;
  proofRequirement: ProofRequirement;
  executionAuthority: ExecutionAuthority;
  linearity: LinearityMode;
  /** OIR binding kinds this expression is allowed to emit. */
  allowedEmitOps?: string[];
  /** Maximum elaboration depth for nested expressions. */
  maxElaborationDepth?: number;
  /** Domain flag binding — which governance domain this expression belongs to. */
  domainBinding?: DomainBinding;
}

// ── Domain Binding ───────────────────────────────────────────

/** What kind of governance structure a domain represents. */
export type DomainType = 'trust' | 'estate' | 'realm' | 'corporate' | 'cooperative' | 'personal';

/** Binds a SIR node to a governance domain. */
export interface DomainBinding {
  /** The domain flag value (from client sovereignty namespace). */
  flag: number;
  /** What kind of governance structure this domain represents. */
  domainType: DomainType;
  /**
   * Optional — which lexicon this domain's SIR nodes use. When set,
   * should match `node.category.lexicon`. Lets extensions declare
   * (flag, domainType, lexicon) as one blob at config time;
   * consumers that only need the lexicon can read it here without
   * walking up to the node's `category` field. See
   * `./lexicons.ts` for the available Lexicon.name values.
   *
   * Orthogonal to `flag` (which is the numeric instance id used by
   * OP_CHECKDOMAINFLAG at the kernel layer) and to `domainType`
   * (governance structure — trust/corporate/etc.).
   */
  lexicon?: string;
  /** The governing instrument (trust deed, articles, constitution, etc.). */
  instrumentId?: string;
  /** Realm — jurisdictional scope, maps to taxonomy 'where' coordinate. */
  realm?: string;
  /** Parent domain flag, if this is a sub-domain (e.g. sub-trust). */
  parentFlag?: number;
  /** Delegation chain — who delegated authority and under what terms. */
  delegation?: DelegationChain;
}

/** Authority delegation chain within a governance domain. */
export interface DelegationChain {
  /** The delegating identity (grantor / settlor / parent trustee). */
  delegator: IdentityRef;
  /** The delegated identity (delegate / sub-trustee / officer). */
  delegate: IdentityRef;
  /** What powers are delegated (subset of the delegator's powers). */
  delegatedPowers: string[];
  /** Restrictions on the delegation (prohibitions the delegate must honour). */
  restrictions: string[];
  /** Whether the delegate can further sub-delegate. */
  canSubDelegate: boolean;
  /** Expiry — when the delegation lapses. */
  expiry?: string;
}

// ── Identity ─────────────────────────────────────────────────

/** Identity binding — who is expressing this. */
export interface SIRIdentity {
  subject: IdentityRef;
  hatId?: string;
  certId?: string;
}

// ── Constraints ──────────────────────────────────────────────

/** SIR constraint — a typed semantic constraint, not raw predicates. */
export type SIRConstraint =
  | { kind: 'capability'; required: number; name: string }
  | { kind: 'domain'; flag: number | string }
  | { kind: 'identity'; ref: IdentityRef }
  | { kind: 'temporal'; op: 'before' | 'after'; iso: string }
  | { kind: 'value'; field: string; op: ComparisonOp; value: number | string }
  | { kind: 'state'; requiredPhase: string }
  | { kind: 'interlock'; policyId: string; policyName: string }
  | { kind: 'composite'; op: 'and' | 'or' | 'not'; children: SIRConstraint[] }
  /**
   * SCG (Semantos Conversation Graph) typed relation. RM-020.
   *
   * `sourceId` and `targetId` are `sem_objects.id` references; they are
   * metadata at the SIR layer and Phase-1 lowering does not emit
   * predicates over them (the substrate is the DB, not the kernel).
   * Phase-5 (RM-082) replaces this with a schema-driven lowering that
   * reads source/target out of a real cell payload via the
   * Plexus schema registry.
   */
  | { kind: 'relation'; relationKind: RelationKind; sourceId?: string; targetId?: string };

// ── Target ───────────────────────────────────────────────────

/** What the expression targets. */
export interface SIRTarget {
  objectId?: string;
  typePath?: string;
  typeHash?: string;
  equipmentId?: string;     // SCADA
  productCellId?: string;   // CDM

  // ── Domain-bound entity refs (RM-Wave9 follow-up) ───────────────────
  // The producer-side resolver binds these from the active workspace
  // BEFORE the cell is minted so the brain's intent_action_router
  // doesn't have to re-derive entity identity from `intent_summary`
  // free text. Resolution heuristics live at the producer (it has
  // the operator's active job + contact list locally); the brain
  // honours them when present and falls back to the substring
  // heuristic only when unbound.
  /** Stable job id (oddjobz.job entity primary key). */
  jobId?: string;
  /** Stable customer id (oddjobz.customer entity primary key). */
  customerId?: string;

  // ── Money-bearing top-level fields (RM-Wave9 follow-up) ─────────────
  // Lift the price/currency out of free-text `summary` so consumers
  // don't regex-parse "$1000". Producer hoists when the transcript
  // implies them (quote / invoice flows); leave undefined when
  // the action is amount-less (schedule, close).
  /** Amount in the smallest unit of `currency` (cents for AUD/USD,
   *  sats for BSV). */
  amount?: number;
  /** ISO 4217 code or the substrate's currency tag (e.g. 'AUD',
   *  'USD', 'sats'). */
  currency?: string;
}

// ── Gate ──────────────────────────────────────────────────────

/** Temporal or state gate for conditions. */
export interface SIRGate {
  type: 'temporal' | 'state' | 'value';
  /** For temporal: ISO timestamp */
  deadline?: string;
  /** For state: required phase */
  requiredPhase?: string;
  /** For value: threshold */
  threshold?: { field: string; op: ComparisonOp; value: number };
}

// ── Fulfillment ──────────────────────────────────────────────

/** Fulfillment criteria for obligations. */
export interface SIRFulfillment {
  /** What event fulfills this obligation */
  fulfilledBy: string;
  /** Deadline for fulfillment */
  deadline?: string;
  /** What happens on default */
  defaultAction?: string;
}

// ── Provenance ───────────────────────────────────────────────

/** Provenance — where did this expression come from. */
export interface SIRProvenance {
  source: 'manual' | 'inferred' | 'voice' | 'api' | 'scheduler' | 'monitor';
  /** If inferred: confidence score (0.0–1.0) */
  confidence?: number;
  /** If inferred: the inference run ID */
  inferenceRunId?: string;
  /** Timestamp of expression */
  expressedAt: string;
  /** Trust tier at time of expression */
  trustAtExpression: TrustClass;
}

// ── SIR Node ─────────────────────────────────────────────────

/** The core SIR node — canonical representation of a meaningful expression. */
export interface SIRNode {
  /** Unique node ID (counter-based: "$s0", "$s1", ...) */
  id: string;
  /**
   * Category within a named lexicon — a discriminated union that
   * tags the category's vocabulary. See `./lexicons.ts` for the
   * full set (jural, control-systems, cdm, bills-of-lading,
   * project-management, property-management, risk-assessment,
   * circuit-commands). Each branch keeps its strict per-lexicon
   * category enum; adding a new lexicon extends the union (and
   * adds a sibling Lean injectivity proof).
   */
  category: TaggedCategory;
  /** What domain this expression operates in. */
  taxonomy: TaxonomyCoordinates;
  /** Who is expressing this and under what authority. */
  identity: SIRIdentity;
  /** Governance context — determines how this node lowers to OIR. */
  governance: GovernanceContext;
  /** The action being expressed (maps to shell verb or domain event). */
  action: string;
  /** The constraint that must hold for this expression to be valid. */
  constraint: SIRConstraint;
  /** Target of the expression (object ID, equipment ID, etc.). */
  target?: SIRTarget;
  /** For transfers: the receiving party. */
  transferTo?: SIRIdentity;
  /** For conditions: the temporal or state gate. */
  gate?: SIRGate;
  /** For obligations: the deadline and fulfillment criteria. */
  fulfillment?: SIRFulfillment;
  /** Source provenance (inference run, manual entry, voice, etc.). */
  provenance: SIRProvenance;
}

// ── SIR Program ──────────────────────────────────────────────

/** A complete SIR program — one or more nodes with a designated primary. */
export interface SIRProgram {
  nodes: SIRNode[];
  /** The primary node (what the program "does"). */
  primaryNodeId: string;
  /** Governance context for the whole program. */
  programGovernance: GovernanceContext;
  /**
   * Lexicon authority — the BRC-52 cert + grammar signature under which
   * this program was authored (D-A6). REQUIRED for programs whose
   * lowering would mint capabilities or extend a domain lexicon; the
   * lowering pass refuses to lower such a program if the cert fails
   * verification (`LEXICON_AUTHORITY_INVALID`) or the signature does
   * not bind the declared grammar to the cert
   * (`GRAMMAR_SIGNATURE_INVALID`).
   *
   * `compileToSIR` and other neutral seams that do not mint or extend
   * leave this unset — the synchronous lowering path skips verification
   * when `authority` is undefined.
   */
  authority?: LexiconAuthority;
}

// ── Lowering Result ──────────────────────────────────────────

/** Result of SIR → OIR lowering. Error objects, never exceptions. */
export type LoweringResult =
  | { ok: true; program: IRProgram }
  | { ok: false; code: string; message: string };

```
