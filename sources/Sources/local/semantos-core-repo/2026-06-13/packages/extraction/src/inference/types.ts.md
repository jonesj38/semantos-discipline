---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.463428+00:00
---

# packages/extraction/src/inference/types.ts

```ts
/**
 * Phase 36C — Schema Inference Agent types.
 *
 * All type definitions for the inference pipeline: structure analysis,
 * taxonomy mapping, grammar diffing, composition, and orchestration.
 *
 * These types are domain-specific to the inference pipeline and live here
 * rather than in protocol-types. They reference ExtensionGrammar types via import.
 */

import type {
  ExtensionGrammar,
  GrammarValidationError,
  SourceDeclaration,
} from '@semantos/protocol-types';

// ── Raw Input ──────────────────────────────────────────────────

export interface RawResponse {
  /** Optional URL the response was fetched from. */
  url?: string;
  /** Optional response headers. */
  headers?: Record<string, string>;
  /** Parsed JSON body. */
  body: unknown;
  /** HTTP status code. */
  statusCode?: number;
  /** ISO 8601 timestamp when this was sampled. */
  sampledAt: string;
}

// ── Structure Analyzer (D36C.1) ────────────────────────────────

export interface EntityGraph {
  nodes: Entity[];
  edges: EntityRelationship[];
  /** JSONPath → entity chain for nested structures. */
  nestedPaths: Record<string, string[]>;
}

export interface Entity {
  /** Entity identifier (e.g., "property"). */
  id: string;
  /** Human-readable name (e.g., "Property"). */
  displayName: string;
  /** Detected fields. */
  fields: InferredField[];
  /** Nesting depth in the response structure. */
  nestingLevel: number;
  /** Number of sample responses this entity appeared in. */
  sampleCount: number;
}

export interface InferredField {
  name: string;
  type: string;
  required: boolean;
  /** Array length range if type is 'array'. */
  cardinality?: { min: number; max: number };
  /** Collected enum values if type is 'enum'. */
  enumValues?: string[];
  /** First 3 non-null sample values. */
  sampleValues: unknown[];
  /** Confidence based on type consistency across samples (0.0–1.0). */
  detectionConfidence: number;
}

export interface EntityRelationship {
  source: string;
  target: string;
  type: 'has_many' | 'has_one' | 'belongs_to';
  foreignKey: string;
  /** Confidence based on detection heuristic strength (0.0–1.0). */
  confidence: number;
}

// ── Taxonomy Mapper (D36C.2) ───────────────────────────────────

export interface TaxonomyProposal {
  /** Entity ID → suggested coordinates. */
  entitySuggestions: Record<string, TaxonomyCoordinates>;
}

export interface TaxonomyCoordinates {
  what: { path: string; confidence: number };
  how: { path: string; confidence: number };
  why: { path: string; confidence: number };
  where?: { path: string; confidence: number };
  /** LLM explanation for human review. */
  llmReasoning?: string;
}

// ── Grammar Diff Engine (D36C.3) ──────────────────────────────

export interface GrammarDiff {
  /** Entity IDs with no match in existing grammars. */
  newEntities: string[];
  /** Entity ID → best grammar match. */
  matchedEntities: Record<string, GrammarMatch>;
  /** Entity ID → fields not found in matched grammar. */
  unmappedFields: Record<string, InferredField[]>;
  /** Entity ID → type mismatches against matched grammar. */
  typeMismatches: Record<string, TypeMismatch[]>;
}

export interface GrammarMatch {
  grammarId: string;
  grammarEntityId: string;
  fieldOverlapPercent: number;
  confidence: number;
}

export interface TypeMismatch {
  field: string;
  proposedType: string;
  grammarType: string;
  grammarId: string;
}

// ── Grammar Composer (D36C.4) ─────────────────────────────────

export interface ComposedGrammar {
  grammar: ExtensionGrammar;
  valid: boolean;
  validationErrors?: GrammarValidationError[];
  lowConfidenceFlags: InferenceFlag[];
  /** Human-readable summary of the composed grammar. */
  summary: string;
}

export interface InferenceFlag {
  type: 'low_confidence_taxonomy' | 'type_detection_mismatch' | 'unknown_entity';
  entity: string;
  field?: string;
  message: string;
  confidence?: number;
  suggestion?: string;
}

// ── Inference Pipeline (D36C.5) ───────────────────────────────

export interface InferenceResult {
  grammarId: string;
  grammar: ExtensionGrammar;
  valid: boolean;
  entityGraph: EntityGraph;
  taxonomyProposal: TaxonomyProposal;
  grammarDiff: GrammarDiff;
  lowConfidenceFlags: InferenceFlag[];
  reviewSummary: {
    totalEntities: number;
    newEntities: number;
    matchedEntities: number;
    highConfidenceCoordinates: number;
    mediumConfidenceCoordinates: number;
    lowConfidenceCoordinates: number;
    unmappedFields: number;
  };
  entityGraphVisualization: {
    nodes: { id: string; label: string; type: string }[];
    edges: { source: string; target: string; label: string }[];
  };
  /** LoomStore object ID for the AFFINE draft. */
  objectId?: string;
}

// ── LLM Client ────────────────────────────────────────────────

export interface LLMSettings {
  openRouterApiKey: string | null;
  modelId: string;
  temperature: number;
}

// ── Confidence Thresholds ─────────────────────────────────────

export interface ConfidenceThresholds {
  /** Minimum confidence to auto-assign (default 0.8). */
  high: number;
  /** Minimum confidence for medium classification (default 0.5). */
  medium: number;
}

export const DEFAULT_CONFIDENCE_THRESHOLDS: ConfidenceThresholds = {
  high: 0.8,
  medium: 0.5,
};

```
