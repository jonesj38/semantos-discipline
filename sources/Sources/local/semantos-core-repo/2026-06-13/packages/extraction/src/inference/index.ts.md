---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.462558+00:00
---

# packages/extraction/src/inference/index.ts

```ts
/**
 * Phase 36C — Schema Inference Agent
 *
 * Barrel export for the inference pipeline.
 */

// Types
export type {
  RawResponse,
  EntityGraph,
  Entity,
  InferredField,
  EntityRelationship,
  TaxonomyProposal,
  TaxonomyCoordinates,
  GrammarDiff,
  GrammarMatch,
  TypeMismatch,
  ComposedGrammar,
  InferenceFlag,
  InferenceResult,
  LLMSettings,
  ConfidenceThresholds,
} from './types';

export { DEFAULT_CONFIDENCE_THRESHOLDS } from './types';

// Structure Analyzer (D36C.1)
export { analyzeStructure } from './structure-analyzer';

// Taxonomy Mapper (D36C.2)
export { mapTaxonomy } from './taxonomy-mapper';

// Grammar Diff Engine (D36C.3)
export { diffGrammars } from './grammar-diff';

// Grammar Composer (D36C.4)
export { composeGrammar } from './grammar-composer';

// Inference Pipeline (D36C.5)
export { InferenceAgent } from './pipeline';

// Pask Seed (G-1)
export { GRAMMAR_CORPUS, GRAMMAR_INFERENCE_PASK_CONFIG, seedPaskStore, fieldTaxonomyCell, taxonomyPathCell } from './pask-seed';
export type { CorpusEntry } from './pask-seed';

// Pask Taxonomy Mapper (G-2)
export { mapTaxonomyWithPask, createSeededAdapter } from './pask-taxonomy-mapper';

// API Probe (G-3)
export { probeApi } from './api-probe';
export type { ApiProbeOptions, ApiProbeResult } from './api-probe';

// Swagger Ingester (G-4)
export { ingestSwagger } from './swagger-ingester';
export type { SwaggerIngesterOptions, OpenAPIObject } from './swagger-ingester';

```
