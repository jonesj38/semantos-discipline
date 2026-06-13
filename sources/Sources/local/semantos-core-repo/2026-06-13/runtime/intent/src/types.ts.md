---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.343570+00:00
---

# runtime/intent/src/types.ts

```ts
/**
 * Intent pipeline — shared types.
 *
 * The Intent is the canonical action shape every input mode (NL, voice,
 * shell, UI, host.exec, network, governance, scheduler) produces. It flows
 * through `processIntent(intent, ctx)` → SIR → IR → bytes → cell engine.
 *
 * Design source of truth: docs/INTENT-PIPELINE.md.
 *
 * Slice 1 — this file declares the surface. Runtime wiring (sir-builder,
 * pipeline, hat-context, receipt, ui-hint, confidence) lands alongside.
 */

import type {
  TaxonomyCoordinates,
  TrustClass,
  SIRConstraint,
  SIRTarget,
  SIRFulfillment,
  SIRIdentity,
  TaggedCategory,
} from '@semantos/semantos-sir';

// ── Branded IDs ──────────────────────────────────────────────
//
// Branded string types prevent accidental mixing at compile time.
// A PatchId is not a CellId is not a CorrelationId — all three are
// strings at runtime, but passing one where another is expected is
// a type error. This is what makes "show me why we approved this
// quote" a typed graph traversal rather than a text search.

export type CorrelationId = string & { readonly __brand: 'CorrelationId' };
export type IntentId = string & { readonly __brand: 'IntentId' };
export type PatchId = string & { readonly __brand: 'PatchId' };
export type CellId = string & { readonly __brand: 'CellId' };

// ── Intent source ────────────────────────────────────────────

export type IntentSource =
  | 'nl'
  | 'voice'
  | 'shell'
  | 'ui'
  | 'host-exec'
  | 'network'
  | 'governance'
  | 'scheduler';

// ── Intent ───────────────────────────────────────────────────

/**
 * Canonical action shape. One producer per input mode; one consumer
 * (`processIntent`). Design: docs/INTENT-PIPELINE.md §"Intent".
 */
export interface Intent {
  /** Unique id for trace / dedup. UUID v7 (time-ordered). */
  id: IntentId;

  /**
   * Trace handle for the entire act — producer → retries → static
   * checks → kernel opcodes → resulting cell → UI render. UUID v7.
   * Optional from the producer; `processIntent` fills if missing.
   * Once set, it propagates unchanged through every `StageEvent`.
   */
  correlationId?: CorrelationId;

  /**
   * Structural link back to the conversation patch that caused this
   * intent to be proposed (the triage PROPOSES_INTENT outcome).
   * Undefined for intents that did not originate from a conversation
   * (shell, UI, host-exec, scheduler). See docs/INTENT-PIPELINE.md
   * §"Triage and conversation patches".
   */
  companionOf?: PatchId;

  /** Free-form summary for log display. */
  summary: string;

  /**
   * Category within a named lexicon — discriminated union that tags
   * the category's vocabulary. See `@semantos/semantos-sir`'s
   * `lexicons.ts` for the full set (jural / control-systems / cdm /
   * bills-of-lading / project-management / property-management /
   * risk-assessment / circuit-commands). Each branch carries its
   * strict category enum — a `control-systems` intent's
   * `category.category` narrows to `ControlSystemsCategory`.
   *
   * Construct via object literal: `{ lexicon: 'jural', category:
   * 'power' }`. TypeScript rejects mis-pairings (e.g.
   * `{ lexicon: 'jural', category: 'setpoint' }` is a type error).
   */
  category: TaggedCategory;

  /** Where in the active extension's taxonomy this lives. */
  taxonomy: TaxonomyCoordinates;

  /**
   * Primary action verb. Maps to the extension's action vocabulary,
   * which in turn maps to shell verbs and/or kernel opcodes.
   */
  action: string;

  /**
   * Constraints that must hold for this intent to be valid. Same
   * shape `lowerSIR` consumes.
   */
  constraints: SIRConstraint[];

  /** What the action targets — object id, type path, equipment id. */
  target?: SIRTarget;

  /** For transfers — receiving party. */
  transferTo?: SIRIdentity;

  /** For obligations — deadline + fulfilment criteria. */
  fulfillment?: SIRFulfillment;

  /**
   * Inferred confidence (see docs/INTENT-PIPELINE.md Decision #2).
   * 0–1. Deterministic input sources (shell, host-exec) should set 1.
   */
  confidence: number;

  /** Provenance. */
  source: IntentSource;

  /** Producer-specific metadata for debugging / replay. */
  producerMeta?: Record<string, unknown>;
}

// ── HatContext ───────────────────────────────────────────────

/**
 * The actor's runtime identity context. Populated by
 * `buildHatContext(services)` from IdentityStore + ConfigStore.
 * Precondition for the pipeline; null hat aborts before any stage
 * event fires.
 */
export interface HatContext {
  hatId: string;
  /** Null if the hat has not been published yet. */
  certId: string | null;
  capabilities: number[];
  extensionId: string;
  domainFlag: number;
  /** Caps the maximum trust class this hat can claim. */
  maxTrustClass: TrustClass;
}

// ── Triage outcomes ──────────────────────────────────────────

/**
 * Output of the triage classifier. Only NL / voice input modes pass
 * through triage; shell / UI / host-exec skip it (those inputs are
 * always either a mutation intent or a pure read).
 *
 * See docs/INTENT-PIPELINE.md §"Triage and conversation patches".
 */
export type TriageOutcome =
  | { kind: 'no_intent'; reason: string }
  | { kind: 'proposes'; intent: Intent }
  | { kind: 'ratifies'; pendingPatchId: PatchId; attestation: Signature };

/** Placeholder — to be replaced by the actual signature type from cert/plexus. */
export interface Signature {
  bytes: Uint8Array;
  algorithm: string;
  keyId: string;
}

/**
 * Ratification patch — the RATIFIES_INTENT outcome. Not a re-run of
 * SIR/IR/kernel; a signed pointer at an earlier pending intent's id.
 * The ratification IS the formal proof on the earlier authoritative-
 * tier state transition.
 */
export interface RatificationPatch {
  kind: 'ratification';
  ratifies: PatchId;
  signedBy: HatContext;
  attestation: Signature;
  correlationId: CorrelationId;
}

// ── Receipt / Cell / kernel result — placeholder surface ─────
//
// Slice 1 stakes out the interface; concrete bindings land with the
// pipeline implementation (Slice 1.6 / 1.7). Receipt becomes a
// converger that host.exec also adopts in Slice 3. See
// docs/INTENT-PIPELINE.md open-questions §1.

/** TODO(slice-1): resolve against core/cell-engine + host.exec receipt. */
export interface Receipt {
  correlationId: CorrelationId;
  signedBy: string;         // hat id
  resultSig: Uint8Array;
  issuedAt: number;
  finishedAt: number;
}

/** TODO(slice-1): import from cell-engine bindings. */
export interface ScriptResult {
  ok: boolean;
  stackDepth: number;
  opcount: number;
  gasUsed: number;
  errorCode?: number;
  errorMessage?: string;
}

/** TODO(slice-1): import from protocol-types. */
export interface Cell {
  id: CellId;
  bytes: Uint8Array;
}

// ── IntentResult / UIHint ────────────────────────────────────

export interface UIHint {
  /** What the user sees. */
  presentation: 'toast' | 'inspector' | 'inline' | 'silent';
  /** Object IDs that should re-render. */
  invalidate: string[];
  /** If a follow-up turn is required. */
  followUp?: { kind: 'confirm' | 'clarify'; prompt: string };
}

export interface IntentRejection {
  stage: 'sir' | 'kernel';
  code: string;
  message: string;
}

export interface IntentResult {
  ok: boolean;
  /**
   * Trace handle — same value as Intent.correlationId for this turn.
   * Surfaced so callers can correlate the result back to log events
   * without keeping the original Intent in scope.
   */
  correlationId: CorrelationId;
  /** On-chain artifact, or null if rejected before bytes. */
  cell: Cell | null;
  kernelResult: ScriptResult;
  receipt: Receipt;
  uiHint: UIHint;
  rejection?: IntentRejection;
}

// ── Stage events (observability) ─────────────────────────────

/**
 * Pipeline stage boundaries. Every `StageEvent` is tagged with the
 * Intent's `correlationId`; a failed turn is a single grep. See
 * docs/INTENT-PIPELINE.md §"Observability".
 */
export type StageName =
  // Happy-path forward events (7)
  | 'intent_extracted'
  | 'sir_built'
  | 'sir_lowered'
  | 'ir_emitted'
  | 'script_executed'
  | 'cell_written'
  | 'intent_completed'
  // Rejection event — replaces remaining happy-path events
  | 'intent_rejected'
  // Triage / conversation-cheap-path events
  | 'conversation_patch_written'
  | 'triage_decided'
  | 'ratification_issued'
  // Producer + reducer observability (RM-090 / RM-091)
  | 'intent_produced'
  | 'reducer_pass_completed';

export interface StageEvent {
  /** ISO 8601 with μs precision. */
  ts: string;
  correlationId: CorrelationId;
  intentId: IntentId | null;    // null for conversation-only turns
  stage: StageName;
  /** Wall time in this stage, monotonic. */
  durationMs: number;
  /** Who emitted; null for system intents. */
  hatId: string | null;
  source: IntentSource;
  /** Stage-specific shape — see doc's Observability table. */
  data: Record<string, unknown>;
}

// ── IntentContext ────────────────────────────────────────────

/**
 * Runtime plumbing passed into `processIntent`. Keep narrow —
 * everything here is either a service the pipeline calls or a
 * pluggable sink. No per-request state.
 */
export interface IntentContext {
  hat: HatContext;
  logger: Logger;
  /** Supplied if the producer already has a correlationId to thread through. */
  correlationId?: CorrelationId;
}

// Forward declaration — real interface lives in ./logger.ts.
// Re-imported here to avoid a circular module dep while keeping
// IntentContext self-describing at the types layer.
export interface Logger {
  emit(event: StageEvent): void;
}

```
