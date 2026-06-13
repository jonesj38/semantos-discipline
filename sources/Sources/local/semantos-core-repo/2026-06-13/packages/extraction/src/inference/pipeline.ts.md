---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/pipeline.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.464000+00:00
---

# packages/extraction/src/inference/pipeline.ts

```ts
/**
 * D36C.5 — Inference Pipeline Orchestrator
 *
 * InferenceAgent class that orchestrates all inference stages:
 * StructureAnalyzer → TaxonomyMapper → GrammarDiffEngine → GrammarComposer
 *
 * Creates an AFFINE semantic object in LoomStore with full evidence chain.
 * Never auto-publishes — all inferred grammars are AFFINE drafts.
 */

import type { SourceDeclaration, ExtensionGrammar, ObjectTypeDefinition } from '@semantos/protocol-types';
import type { LoomStore } from '@semantos/runtime-services';
import type { ObjectPatch } from '@semantos/runtime-services';
import { analyzeStructure } from './structure-analyzer';
import { mapTaxonomy } from './taxonomy-mapper';
import { diffGrammars } from './grammar-diff';
import { composeGrammar } from './grammar-composer';
import type {
  RawResponse,
  LLMSettings,
  InferenceResult,
  ConfidenceThresholds,
} from './types';
import { DEFAULT_CONFIDENCE_THRESHOLDS } from './types';

// ── Inferred Grammar Type Definition ───────────────────────────

/**
 * Hardcoded ObjectTypeDefinition for inferred grammar objects.
 * typeHash computed from "platform.extension.inferred-grammar".
 */
export const INFERRED_GRAMMAR_TYPE: ObjectTypeDefinition = {
  typeHash: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
  name: 'InferredGrammar',
  icon: 'wand',
  linearity: 'AFFINE',
  defaultCapabilities: [],
  fields: [
    { name: 'grammarId', type: 'string' },
    { name: 'status', type: 'string' },
    { name: 'summary', type: 'string' },
  ],
  category: 'platform.extension',
};

// Compute typeHash at module load time if Bun.CryptoHasher is available
try {
  const hasher = new Bun.CryptoHasher('sha256');
  hasher.update('platform.extension.inferred-grammar');
  INFERRED_GRAMMAR_TYPE.typeHash = hasher.digest('hex');
} catch {
  // Keep fallback hash
}

// ── InferenceAgent ─────────────────────────────────────────────

export class InferenceAgent {
  private store: LoomStore;
  private settings: LLMSettings;
  private installedGrammars: ExtensionGrammar[];

  constructor(
    store: LoomStore,
    settings: LLMSettings,
    installedGrammars: ExtensionGrammar[],
  ) {
    this.store = store;
    this.settings = settings;
    this.installedGrammars = installedGrammars;
  }

  /**
   * Run the full inference pipeline on sample API responses.
   *
   * @param sampleResponses - Raw API responses to analyze
   * @param sourceConfig - Partial source configuration (protocol, auth, etc.)
   * @param options - Pipeline options (confidence thresholds, base grammar, etc.)
   */
  async infer(
    sampleResponses: RawResponse[],
    sourceConfig: Partial<SourceDeclaration>,
    options?: {
      baseGrammarId?: string;
      skipValidation?: boolean;
      confidence?: { min: number };
      thresholds?: ConfidenceThresholds;
    },
  ): Promise<InferenceResult> {
    const thresholds = options?.thresholds ?? DEFAULT_CONFIDENCE_THRESHOLDS;

    // Step 1: Validate inputs
    if (sampleResponses.length === 0) {
      throw new Error('InferenceAgent requires at least one sample response.');
    }

    // Step 2: Structure analysis (deterministic)
    const entityGraph = analyzeStructure(sampleResponses);

    if (entityGraph.nodes.length === 0) {
      throw new Error('No entities detected in sample responses. Check response format.');
    }

    // Step 3: Taxonomy mapping (LLM-assisted)
    const taxonomyProposal = await mapTaxonomy(entityGraph, this.settings, { thresholds });

    // Step 4: Grammar diff (deterministic)
    const grammarDiff = diffGrammars(entityGraph, this.installedGrammars);

    // Step 5: Grammar composition
    const composed = composeGrammar(entityGraph, taxonomyProposal, grammarDiff, sourceConfig, {
      thresholds,
    });

    // Step 6: Create AFFINE semantic object in LoomStore
    let objectId: string | undefined;
    try {
      objectId = this.store.createObjectFromType(INFERRED_GRAMMAR_TYPE, undefined, undefined, undefined, false);

      // Set payload fields
      this.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId, field: 'grammarId', value: composed.grammar.grammarId });
      this.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId, field: 'status', value: 'draft' });
      this.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId, field: 'summary', value: composed.summary });

      // Add evidence chain patches
      const evidencePatch: ObjectPatch = {
        id: `patch-${Date.now()}-inference`,
        kind: 'action',
        timestamp: Date.now(),
        delta: {
          action: 'schema_inferred',
          grammarId: composed.grammar.grammarId,
          grammarVersion: composed.grammar.grammarVersion,
          valid: composed.valid,
          entityCount: entityGraph.nodes.length,
          relationshipCount: entityGraph.edges.length,
          newEntities: grammarDiff.newEntities,
          matchedEntities: Object.keys(grammarDiff.matchedEntities),
          lowConfidenceCount: composed.lowConfidenceFlags.length,
          sampleHashes: sampleResponses.map(r => hashResponse(r)),
          inferenceParameters: {
            sampleCount: sampleResponses.length,
            thresholds,
            baseGrammarId: options?.baseGrammarId,
          },
        },
      };
      this.store.dispatch({ type: 'ADD_PATCH', objectId, patch: evidencePatch });

      // Add taxonomy reasoning as separate evidence
      if (Object.keys(taxonomyProposal.entitySuggestions).length > 0) {
        const taxonomyPatch: ObjectPatch = {
          id: `patch-${Date.now()}-taxonomy`,
          kind: 'action',
          timestamp: Date.now(),
          delta: {
            action: 'taxonomy_mapped',
            suggestions: Object.fromEntries(
              Object.entries(taxonomyProposal.entitySuggestions).map(([id, coords]) => [
                id,
                {
                  what: coords.what,
                  how: coords.how,
                  why: coords.why,
                  reasoning: coords.llmReasoning,
                },
              ]),
            ),
          },
        };
        this.store.dispatch({ type: 'ADD_PATCH', objectId, patch: taxonomyPatch });
      }

      // Add validation errors if any
      if (composed.validationErrors && composed.validationErrors.length > 0) {
        const validationPatch: ObjectPatch = {
          id: `patch-${Date.now()}-validation`,
          kind: 'action',
          timestamp: Date.now(),
          delta: {
            action: 'validation_result',
            valid: composed.valid,
            errors: composed.validationErrors,
          },
        };
        this.store.dispatch({ type: 'ADD_PATCH', objectId, patch: validationPatch });
      }
    } catch {
      // LoomStore integration failed — proceed without storing
      objectId = undefined;
    }

    // Step 7: Build review summary
    const reviewSummary = buildReviewSummary(entityGraph, grammarDiff, taxonomyProposal, thresholds);

    // Step 8: Build visualization data
    const entityGraphVisualization = {
      nodes: entityGraph.nodes.map(n => ({
        id: n.id,
        label: n.displayName,
        type: 'entity',
      })),
      edges: entityGraph.edges.map(e => ({
        source: e.source,
        target: e.target,
        label: `${e.type} (${e.foreignKey})`,
      })),
    };

    return {
      grammarId: composed.grammar.grammarId,
      grammar: composed.grammar,
      valid: composed.valid,
      entityGraph,
      taxonomyProposal,
      grammarDiff,
      lowConfidenceFlags: composed.lowConfidenceFlags,
      reviewSummary,
      entityGraphVisualization,
      objectId,
    };
  }
}

// ── Helpers ────────────────────────────────────────────────────

function buildReviewSummary(
  graph: { nodes: { id: string }[] },
  diff: { newEntities: string[]; matchedEntities: Record<string, unknown> },
  taxonomy: { entitySuggestions: Record<string, { what: { confidence: number }; how: { confidence: number }; why: { confidence: number } }> },
  thresholds: ConfidenceThresholds,
): InferenceResult['reviewSummary'] {
  let highConf = 0;
  let medConf = 0;
  let lowConf = 0;

  for (const coords of Object.values(taxonomy.entitySuggestions)) {
    for (const axis of [coords.what, coords.how, coords.why]) {
      if (axis.confidence >= thresholds.high) highConf++;
      else if (axis.confidence >= thresholds.medium) medConf++;
      else lowConf++;
    }
  }

  return {
    totalEntities: graph.nodes.length,
    newEntities: diff.newEntities.length,
    matchedEntities: Object.keys(diff.matchedEntities).length,
    highConfidenceCoordinates: highConf,
    mediumConfidenceCoordinates: medConf,
    lowConfidenceCoordinates: lowConf,
    unmappedFields: 0, // computed from diff if needed
  };
}

/**
 * Hash a raw response for evidence chain provenance.
 * Uses SHA-256 on the stringified body. Does not store the full response.
 */
function hashResponse(response: RawResponse): string {
  try {
    const hasher = new Bun.CryptoHasher('sha256');
    hasher.update(JSON.stringify(response.body));
    return hasher.digest('hex');
  } catch {
    // Fallback: simple string hash
    const str = JSON.stringify(response.body);
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32-bit integer
    }
    return Math.abs(hash).toString(16).padStart(8, '0');
  }
}

```
