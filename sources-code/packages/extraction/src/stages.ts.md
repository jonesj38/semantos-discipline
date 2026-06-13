---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/stages.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.455037+00:00
---

# packages/extraction/src/stages.ts

```ts
/**
 * Extraction pipeline stage interfaces and types.
 *
 * Every stage is a pure async generator: input + grammar → output + evidence.
 * No global state, no side effects outside specified outputs.
 *
 * Cross-references:
 *   evidence.ts   → EvidenceAccumulator
 *   context.ts    → ExtractionStorageContext
 *   extension-grammar.ts → ExtensionGrammar, SourceEntity, EntityMapping
 */

import type { EvidenceAccumulator } from './evidence';

// ── Stage I/O Types ─────────────────────────────────────────────

/** Raw API response from a fetch adapter. */
export interface RawResponse {
  endpoint: string;
  statusCode: number;
  body: unknown;
  headers: Record<string, string>;
  timestamp: number;
  /** SHA-256 hex of the serialized body — for idempotency. */
  responseHash: string;
}

/** Parsed record after field mapping, before validation. */
export interface IntermediateRecord {
  sourceEntityId: string;
  sourceFields: Record<string, unknown>;
  mappedFields: Record<string, unknown>;
  sourceId: unknown;
  evidence: EvidenceAccumulator;
}

/** Record after schema + taxonomy validation. */
export interface ValidatedRecord extends IntermediateRecord {
  targetObjectType: string;
  taxonomy: TaxonomyCoordinate;
  phase: string;
  validationPassed: boolean;
  validationErrors: string[];
}

/** Record after optional inference enrichment. */
export interface InferredRecord extends ValidatedRecord {
  inferredTaxonomy?: { confidence: number; suggestion: string };
  grammarPatchRequired?: boolean;
}

/** Semantic object produced by the commit stage. */
export interface ExtractedSemanticObject {
  objectId: string;
  objectType: string;
  payload: Record<string, unknown>;
  taxonomy: TaxonomyCoordinate;
  phase: string;
  evidenceChain: ExtractionEvidence[];
}

/** Taxonomy coordinate (WHAT/HOW/WHY + optional WHERE). */
export interface TaxonomyCoordinate {
  what: string;
  how: string;
  why: string;
  where?: string;
}

// ── Credentials & Binding ───────────────────────────────────────

/** Flat key-value credential map — keys match grammar.source.auth.requiredCredentials. */
export type Credentials = Record<string, string>;

/** Consumer binding: who is extracting, with what credentials. */
export interface ConsumerBinding {
  consumerId: string;
  credentials: Credentials;
  overrides?: Record<string, unknown>;
}

// ── Extraction Context ──────────────────────────────────────────

import type { ExtractionStorageContext } from './context';

/** Runtime context threaded through all pipeline stages. */
export interface ExtractionContext {
  grammarId: string;
  grammarVersion: string;
  consumerId: string;
  extractionStore: ExtractionStorageContext;
}

// ── Evidence Chain ──────────────────────────────────────────────

/** Evidence entry for one pipeline stage. */
export interface ExtractionEvidence {
  stage: 'fetch' | 'parse' | 'typecheck' | 'infer' | 'commit';
  timestamp: number;
  grammarVersion: string;
  stageData: FetchEvidence | ParseEvidence | TypecheckEvidence | InferenceEvidence | CommitEvidence;
}

export interface FetchEvidence {
  endpoint: string;
  responseHash: string;
  statusCode: number;
  bytesReceived: number;
}

export interface ParseEvidence {
  sourceEntityId: string;
  targetObjectType: string;
  fieldsMapped: number;
  transformsApplied: string[];
}

export interface TypecheckEvidence {
  passed: boolean;
  errors: string[];
  taxonomyAssigned: string;
  phaseAssigned: string;
}

export interface InferenceEvidence {
  inferenceApplied: boolean;
  suggestedTaxonomy?: string;
  confidenceScore?: number;
  grammarPatchProposed?: boolean;
}

export interface CommitEvidence {
  objectId: string;
  storageAdapter: string;
  isNewObject: boolean;
  facetProvenance: { author: string; timestamp: number };
}

// ── Pipeline Result ─────────────────────────────────────────────

export interface ExtractionResult {
  grammarId: string;
  grammarVersion: string;
  totalRecords: number;
  createdObjects: number;
  updatedObjects: number;
  errors: Array<{ entity?: string; error: string; timestamp: number }>;
  startTime: number;
  endTime: number;
}

export interface ExtractionOptions {
  /** Extract only this entity. */
  entityFilter?: string;
  /** Parse + typecheck but don't commit. */
  dryRun?: boolean;
  /** Incremental extraction since this date. */
  since?: Date;

  // ── Phase 36D: Governance integration ──

  /** Governed consumer binding (persistent object with encrypted credentials). */
  governedBinding?: import('@semantos/protocol-types').GovernedConsumerBinding;
  /** Extension manifest with governance config (for L1 constraint checks). */
  manifest?: import('@semantos/protocol-types').ExtensionManifest;
}

// ── Grammar Patch ───────────────────────────────────────────────

/** Proposed grammar patch when the infer stage discovers unmapped fields. */
export interface GrammarPatch {
  type: 'grammar-patch';
  targetGrammar: string;
  proposedFieldMappings: Array<{
    sourceField: string;
    targetField: string;
    required: boolean;
  }>;
  confidence: 'low' | 'medium' | 'high';
}

// ── Inference Client (stub for Phase 36C) ───────────────────────

/** Optional inference client for taxonomy suggestion. */
export interface InferenceClient {
  suggestTaxonomy(record: ValidatedRecord): Promise<{ path: string; confidence: number } | null>;
}

```
