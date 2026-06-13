---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/pask-taxonomy-mapper.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.463714+00:00
---

# packages/extraction/src/inference/pask-taxonomy-mapper.ts

```ts
/**
 * G-2 — Pask TaxonomyMapper.
 *
 * Replaces the Levenshtein + LLM heuristic in taxonomy-mapper.ts with
 * Pask interaction-propagation. Taxonomy coordinate assignment is learned
 * from the pre-seeded corpus (G-1) — not string matching, not LLM calls.
 *
 * Algorithm:
 * 1. Load the pre-seeded store (seedPaskStore builds the prior).
 * 2. For each new field in the EntityGraph, generate candidate taxonomy
 *    paths by looking up fields with similar names in the corpus.
 * 3. Insert candidate interactions into the store (strength = name
 *    similarity score × field detection confidence).
 * 4. Run finalize() to propagate.
 * 5. Read edge weights: the highest-weight taxonomy path cell for each
 *    axis wins. The weight becomes the confidence score.
 *
 * The mapper never calls an LLM. For novel domains with no corpus overlap,
 * confidence scores will be low and surfaced as InferenceFlags — the human
 * reviewer then authors the taxonomy coordinates.
 *
 * See docs/textbook/33-automated-grammar-synthesis.md §Stage 2
 */

import { PaskAdapter, loadPask, DEFAULT_PASK_CONFIG } from '../../../../core/pask/bindings/ts/src';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  seedPaskStore,
  fieldTaxonomyCell,
  taxonomyPathCell,
  GRAMMAR_CORPUS,
  GRAMMAR_INFERENCE_PASK_CONFIG,
  type CorpusEntry,
} from './pask-seed';
import type { EntityGraph, TaxonomyProposal, TaxonomyCoordinates, ConfidenceThresholds } from './types';
import { DEFAULT_CONFIDENCE_THRESHOLDS } from './types';

// ---------------------------------------------------------------------------
// All known taxonomy paths (axes × known paths from corpus)
// ---------------------------------------------------------------------------

const CORPUS_WHAT_PATHS = [...new Set(GRAMMAR_CORPUS.map(e => e.what))];
const CORPUS_HOW_PATHS  = [...new Set(GRAMMAR_CORPUS.map(e => e.how))];
const CORPUS_WHY_PATHS  = [...new Set(GRAMMAR_CORPUS.map(e => e.why))];

// Extended with the generic paths from taxonomy-mapper.ts for broader coverage
const EXTENDED_WHAT_PATHS = [
  ...CORPUS_WHAT_PATHS,
  'what.object.property', 'what.object.vehicle', 'what.object.device',
  'what.resource.material', 'what.resource.energy', 'what.resource.water',
  'what.person.tenant', 'what.person.owner', 'what.person.employee',
  'what.record.lease', 'what.record.contract', 'what.record.invoice',
  'what.record.receipt', 'what.record.certificate',
  'what.event.inspection', 'what.event.maintenance', 'what.event.payment',
  'what.service.property', 'what.service.maintenance', 'what.service.repair',
  'what.process.workflow', 'what.process.approval',
];
const EXTENDED_HOW_PATHS = [
  ...CORPUS_HOW_PATHS,
  'how.technical.api.rest', 'how.technical.api.graphql', 'how.technical.database',
  'how.physical.manual', 'how.digital.automated', 'how.commercial.transfer',
];
const EXTENDED_WHY_PATHS = [
  ...CORPUS_WHY_PATHS,
  'why.integration.data-sync', 'why.compliance.audit', 'why.operations.management',
  'why.maintenance.repair', 'why.maintenance.inspection',
  'why.finance.billing', 'why.finance.accounting', 'why.safety.alert',
  'why.safety.interlock', 'why.operations.monitoring', 'why.operations.control',
];

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

/**
 * Map taxonomy coordinates for each entity in the EntityGraph using Pask
 * propagation from the pre-seeded corpus.
 *
 * @param graph - EntityGraph from StructureAnalyzer
 * @param options - Confidence thresholds
 * @param existingAdapter - Optional pre-seeded adapter (avoids re-loading WASM)
 */
export async function mapTaxonomyWithPask(
  graph: EntityGraph,
  options?: { thresholds?: ConfidenceThresholds; adapter?: PaskAdapter },
): Promise<TaxonomyProposal> {
  const thresholds = options?.thresholds ?? DEFAULT_CONFIDENCE_THRESHOLDS;

  // Load and seed the Pask store if not provided
  const adapter = options?.adapter ?? await createSeededAdapter();

  const entitySuggestions: Record<string, TaxonomyCoordinates> = {};

  for (const entity of graph.nodes) {
    const coordinates = await inferEntityTaxonomy(entity, adapter, thresholds);
    entitySuggestions[entity.id] = coordinates;
  }

  return { entitySuggestions };
}

/**
 * Create a fresh PaskAdapter seeded with the grammar corpus.
 * Callers who process many grammars in one session should create once
 * and pass via options.adapter.
 */
export async function createSeededAdapter(): Promise<PaskAdapter> {
  const wasmPath = resolve(
    dirname(fileURLToPath(import.meta.url)),
    '../../../../core/pask/zig-out/bin/pask.wasm',
  );
  const wasmBytes = readFileSync(wasmPath);
  const instance = await loadPask(wasmBytes);
  const adapter = new PaskAdapter(instance, {
    ...DEFAULT_PASK_CONFIG,
    ...GRAMMAR_INFERENCE_PASK_CONFIG,
  });
  await seedPaskStore(adapter);
  return adapter;
}

// ---------------------------------------------------------------------------
// Per-entity inference
// ---------------------------------------------------------------------------

async function inferEntityTaxonomy(
  entity: { id: string; fields: { name: string; type: string; detectionConfidence: number }[] },
  adapter: PaskAdapter,
  thresholds: ConfidenceThresholds,
): Promise<TaxonomyCoordinates> {
  const nowMs = Date.now();

  // For each field × candidate taxonomy path, insert a candidate interaction
  // weighted by name similarity × field detection confidence.
  for (const field of entity.fields) {
    const fieldSim = fieldNameSimilarity(field.name);

    for (const axis of ['what', 'how', 'why'] as const) {
      const candidatePaths = axis === 'what' ? EXTENDED_WHAT_PATHS
                           : axis === 'how'  ? EXTENDED_HOW_PATHS
                           : EXTENDED_WHY_PATHS;

      // Find corpus entries that match this field name (partial / exact)
      const corpusMatches = findCorpusMatches(field.name, axis);
      const relatedKnownCells = corpusMatches.map(m =>
        fieldTaxonomyCell(m.field, axis, m[axis]),
      );

      for (const path of candidatePaths) {
        const pathSim = pathNameSimilarity(field.name, entity.id, path);
        const candidateStrength = pathSim * field.detectionConfidence * 0.7;
        if (candidateStrength < 0.05) continue; // skip very weak candidates

        await adapter.interact({
          cellId: fieldTaxonomyCell(field.name, axis, path),
          kind: `infer:${axis}`,
          strength: candidateStrength,
          relatedCells: [
            taxonomyPathCell(axis, path),
            ...relatedKnownCells.slice(0, 3),
          ],
          nowMs,
        });
      }
    }
  }

  adapter.finalize(nowMs);

  // Read best path for each axis by finding the highest hState among
  // taxonomy path cells.
  return {
    what: readBestAxis('what', adapter, thresholds),
    how:  readBestAxis('how',  adapter, thresholds),
    why:  readBestAxis('why',  adapter, thresholds),
  };
}

// ---------------------------------------------------------------------------
// Read best axis result from Pask store
// ---------------------------------------------------------------------------

function readBestAxis(
  axis: 'what' | 'how' | 'why',
  adapter: PaskAdapter,
  thresholds: ConfidenceThresholds,
): { path: string; confidence: number } {
  const paths = axis === 'what' ? EXTENDED_WHAT_PATHS
              : axis === 'how'  ? EXTENDED_HOW_PATHS
              : EXTENDED_WHY_PATHS;

  let bestPath = paths[0] ?? `${axis}.unknown`;
  let bestH = -Infinity;

  const snapshot = adapter.stableThreads(512);
  const stableIds = new Set(snapshot.map(t => t.cellId));

  // Among stable threads, find the taxonomy path cell with highest hState
  for (const path of paths) {
    const cellId = taxonomyPathCell(axis, path);
    const thread = snapshot.find(t => t.cellId === cellId);
    if (thread && thread.hState > bestH) {
      bestH = thread.hState;
      bestPath = path;
    }
  }

  // Normalize hState to [0, 1] confidence: hState is in [-1, 1] in Pask kernel
  const rawConfidence = bestH === -Infinity ? 0 : Math.max(0, Math.min(1, (bestH + 1) / 2));
  const confidence = isNaN(rawConfidence) ? 0 : rawConfidence;

  return { path: bestPath, confidence };
}

// ---------------------------------------------------------------------------
// Similarity helpers
// ---------------------------------------------------------------------------

function fieldNameSimilarity(fieldName: string): number {
  // Score: known corpus field names that partially match
  const norm = fieldName.toLowerCase().replace(/[_-]/g, '');
  let best = 0;
  for (const entry of GRAMMAR_CORPUS) {
    const entryNorm = entry.field.toLowerCase().replace(/[_-]/g, '');
    if (entryNorm === norm) return 1.0;
    if (norm.includes(entryNorm) || entryNorm.includes(norm)) {
      best = Math.max(best, 0.7);
    }
  }
  return best > 0 ? best : 0.2;
}

function findCorpusMatches(fieldName: string, axis: 'what' | 'how' | 'why'): CorpusEntry[] {
  const norm = fieldName.toLowerCase().replace(/[_-]/g, '');
  return GRAMMAR_CORPUS.filter(entry => {
    const entryNorm = entry.field.toLowerCase().replace(/[_-]/g, '');
    return entryNorm === norm || norm.includes(entryNorm) || entryNorm.includes(norm);
  });
}

function pathNameSimilarity(fieldName: string, entityId: string, path: string): number {
  const segments = path.split('.').slice(1); // drop axis prefix
  const norm = fieldName.toLowerCase().replace(/[_-]/g, '');
  const entityNorm = entityId.toLowerCase().replace(/[_-]/g, '');

  let best = 0;
  for (const seg of segments) {
    const segNorm = seg.toLowerCase();
    if (norm.includes(segNorm) || segNorm.includes(norm)) best = Math.max(best, 0.6);
    if (entityNorm.includes(segNorm) || segNorm.includes(entityNorm)) best = Math.max(best, 0.5);
    // Partial overlap scoring
    const overlapLen = Math.min(norm.length, segNorm.length);
    if (overlapLen > 3 && (norm.startsWith(segNorm.slice(0, 4)) || segNorm.startsWith(norm.slice(0, 4)))) {
      best = Math.max(best, 0.4);
    }
  }
  return best;
}

```
