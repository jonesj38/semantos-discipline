---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/consciousness/consciousness/src/types/consciousness-objects.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.722407+00:00
---

# archive/consciousness/consciousness/src/types/consciousness-objects.ts

```ts
/**
 * Consciousness Process: Self-Improvement Extension Grammar
 *
 * Models the self as a semantic object undergoing release/receive cycles.
 * Consumption semantics map directly to personal development:
 *
 *   LINEAR  → Release (consumed once — you let go, it's gone)
 *   LINEAR  → Session (consumed once — you practiced, it's done)
 *   AFFINE  → Intention (acknowledge or discard — both valid completions)
 *   RELEVANT → Insight (wisdom persists, always accessible, revocable)
 *   RELEVANT → Pattern (accumulated self-knowledge from many releases)
 *
 * @module @semantos/consciousness
 */

import {
  SemanticType,
  type LinearObject,
  type AffineObject,
  type RelevantObject,
  type ConsumptionProof,
  type RevocationProof,
} from '@semantos/core';

// ─── Elevation (consciousness-specific) ────────────────────────────

/**
 * The 6 elevation levels in the consciousness tower model.
 * Foundation (1) through Completion (6).
 */
export enum ElevationLevel {
  FOUNDATION = 1,
  PRACTICE = 2,
  AWARENESS = 3,
  ENERGETICS = 4,
  ORGANISATION = 5,
  COMPLETION = 6,
}

// ─── Domain Flags (Client Sovereign range 0x0001xxxx) ───────────────

/** Domain flag for self-inquiry and introspection keys. */
export const SELF_INQUIRY = 0x00010001;

/** Domain flag for release writing sessions. */
export const RELEASE_WRITING = 0x00010002;

/** Domain flag for attention/meditation practice. */
export const ATTENTION_TRAINING = 0x00010003;

/** Domain flag for energetic/visualization practice. */
export const ENERGETIC_PRACTICE = 0x00010004;

/** Domain flag for connection/intelligence receiving. */
export const CONNECTION_RECEIVING = 0x00010005;

// ─── Enums ──────────────────────────────────────────────────────────

/** The seven life dimensions tracked across the consciousness process. */
export enum LifeDimension {
  MENTAL = 'MENTAL',
  PHYSICAL = 'PHYSICAL',
  SPIRITUAL = 'SPIRITUAL',
  SOCIAL = 'SOCIAL',
  VOCATIONAL = 'VOCATIONAL',
  FINANCIAL = 'FINANCIAL',
  FAMILIAL = 'FAMILIAL',
}

/** Source modality for a release entry. */
export type ReleaseSource =
  | 'voice'        // voice-to-text transcription
  | 'keyboard'     // typed stream-of-consciousness
  | 'photo'        // photographed handwritten journal, OCR'd
  | 'import';      // imported from external source

/** The prompt that initiated a release. */
export type ReleasePrompt =
  | 'I feel...'
  | 'I release...'
  | 'I am...'
  | 'I choose...'
  | 'freeform';

/** Connection target for intelligence receiving. */
export type ConnectionTarget =
  | 'highest-expression'
  | 'inner-child'
  | 'future-self'
  | 'ancestors'
  | 'highest-good'
  | 'custom';

/** Category of extracted pattern. */
export type PatternCategory =
  | 'belief'        // recurring belief (limiting or empowering)
  | 'emotion'       // recurring emotional theme
  | 'relationship'  // relational pattern
  | 'behavior'      // habitual action/reaction
  | 'desire'        // recurring want/need
  | 'resistance';   // recurring avoidance/block

// ─── Consumption Proofs ─────────────────────────────────────────────

/**
 * Proof that a Release was consumed (processed and released).
 * The act of completing the writing session IS the consumption.
 */
export interface ReleaseConsumptionProof extends ConsumptionProof {
  /** Duration in seconds of the writing/speaking session. */
  sessionDurationSec: number;

  /** Word count of the raw release text. */
  wordCount: number;

  /** Number of Insight objects extracted from this release. */
  insightsExtracted: number;

  /** Number of Pattern references identified. */
  patternsIdentified: number;
}

/**
 * Proof that a Session was consumed (practice completed).
 */
export interface SessionConsumptionProof extends ConsumptionProof {
  /** Total duration of all practices in this session. */
  totalDurationSec: number;

  /** Resource IDs of all objects created during this session. */
  objectsCreated: string[];

  /** Elevation level at time of session completion. */
  elevationAtCompletion: ElevationLevel;
}

// ─── LINEAR Objects ───────────────────────────────��─────────────────

/**
 * Release: A stream-of-consciousness writing/speaking session.
 *
 * LINEAR — must be consumed exactly once. You write to release.
 * The kernel enforces that once released, you cannot re-consume
 * (cling to) what you let go of.
 */
export interface Release extends LinearObject<ReleaseConsumptionProof> {
  semanticType: SemanticType.LINEAR;
  source: ReleaseSource;
  prompt: ReleasePrompt;
  rawText: string;
  journalImageRef?: string;
  elevation: ElevationLevel;
  dimensions: LifeDimension[];
  extractedSummary?: string;
  extractedInsightIds: string[];
  referencedPatternIds: string[];
  valence?: number;
  themes: string[];
}

/**
 * Session: A daily practice container.
 *
 * LINEAR — you sit down, you practice, it's consumed.
 */
export interface Session extends LinearObject<SessionConsumptionProof> {
  semanticType: SemanticType.LINEAR;
  date: string;
  elevation: ElevationLevel;
  practices: SessionPractice[];
  releaseIds: string[];
  insightIds: string[];
  intentionIds: string[];
  reflection?: string;
}

/** A practice performed within a session. */
export interface SessionPractice {
  type: 'release-writing' | 'focus-timer' | 'cosmic-vacuum' | 'connection' | 'review';
  durationSec: number;
  completed: boolean;
  notes?: string;
}

// ─── AFFINE Objects ─────────────────────────────────────────────────

/** Metadata for an acknowledged intention. */
export interface IntentionMeta {
  completionType: 'fulfilled' | 'transformed' | 'outgrown';
  reflection?: string;
  completedAt: number;
}

/**
 * Intention: A choice or commitment.
 *
 * AFFINE — can be acknowledged (completed) or discarded (released).
 */
export interface Intention extends AffineObject<IntentionMeta> {
  semanticType: SemanticType.AFFINE;
  statement: string;
  dimensions: LifeDimension[];
  elevation: ElevationLevel;
  targetDate?: string;
  sourceObjectId?: string;
}

// ─── RELEVANT Objects ───────────────────────────────────────────────

/**
 * Insight: Wisdom received during practice.
 *
 * RELEVANT — persists, always accessible, can be revoked if outgrown.
 */
export interface Insight extends RelevantObject<RevocationProof> {
  semanticType: SemanticType.RELEVANT;
  content: string;
  source: 'release-extraction' | 'connection' | 'review' | 'meditation' | 'manual';
  connectionTarget?: ConnectionTarget;
  dimensions: LifeDimension[];
  elevation: ElevationLevel;
  sourceObjectId?: string;
  significance: number;
  tags: string[];
}

/**
 * Pattern: A recurring theme identified across multiple releases.
 *
 * RELEVANT — accumulated self-knowledge that persists.
 */
export interface Pattern extends RelevantObject<RevocationProof> {
  semanticType: SemanticType.RELEVANT;
  description: string;
  category: PatternCategory;
  dimensions: LifeDimension[];
  polarity: 'limiting' | 'empowering' | 'neutral';
  evidenceReleaseIds: string[];
  occurrenceCount: number;
  firstObservedAt: number;
  lastObservedAt: number;
  analysis?: string;
  strength: number;
}

// ─── LINEAR Action Objects ──────────────────────────────────────────

/**
 * Connection: A deliberate connection to an aspect of self or consciousness.
 * LINEAR — you connect, you receive, it's consumed.
 */
export interface Connection extends LinearObject<ConsumptionProof> {
  semanticType: SemanticType.LINEAR;
  target: ConnectionTarget;
  customTarget?: string;
  question?: string;
  receivedIntelligence: string;
  elevation: ElevationLevel;
  extractedInsightIds: string[];
}

/**
 * VacuumSession: A QSE vacuum cleaner invocation.
 * LINEAR — invoke, release, integrate, done.
 */
export interface VacuumSession extends LinearObject<ConsumptionProof> {
  semanticType: SemanticType.LINEAR;
  releaseIntentions: string;
  integrateIntentions: string;
  elevation: ElevationLevel;
  perceivedShift: boolean;
  notes?: string;
}

/**
 * GoldSeal: The gold energy seal for permanence.
 * LINEAR — invoke gold, seal, done.
 */
export interface GoldSeal extends LinearObject<ConsumptionProof> {
  semanticType: SemanticType.LINEAR;
  sealVisualization: 'light' | 'powder' | 'ointment' | 'block' | 'molten' | 'custom';
  sealedReleaseIds: string[];
  sealedVacuumId?: string;
  elevation: ElevationLevel;
}

// ─── LLM Extraction Schemas ────────────────────────────────────────

/** Schema for LLM extraction from raw release text. */
export interface ReleaseExtractionResult {
  summary: string;
  valence: number;
  themes: string[];
  dimensions: LifeDimension[];
  insights: Array<{
    content: string;
    significance: number;
    dimensions: LifeDimension[];
    tags: string[];
  }>;
  patterns: Array<{
    description: string;
    category: PatternCategory;
    polarity: 'limiting' | 'empowering' | 'neutral';
    dimensions: LifeDimension[];
    existingPatternId?: string;
  }>;
  intentions: Array<{
    statement: string;
    dimensions: LifeDimension[];
  }>;
}

/** Schema for LLM extraction from a photographed journal page. */
export interface JournalPhotoExtractionResult {
  transcribedText: string;
  ocrConfidence: number;
  extraction: ReleaseExtractionResult;
}

```
