---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/taxonomy-mapper.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.463136+00:00
---

# packages/extraction/src/inference/taxonomy-mapper.ts

```ts
/**
 * D36C.2 — Taxonomy Mapper
 *
 * Uses LLM calls via OpenRouter to suggest WHAT/HOW/WHY taxonomy
 * coordinates for each entity in an EntityGraph. This is the ONLY
 * module in the inference pipeline that calls LLM.
 *
 * Process:
 * 1. Pre-filter with string similarity to find top-3 similar taxonomy nodes
 * 2. Build LLM prompt with entity context + similar nodes
 * 3. Call LLM with 5-second timeout per entity
 * 4. Cross-check LLM result against pre-filter for confidence adjustment
 * 5. Classify: high (>0.8), medium (0.5–0.8), low (<0.5)
 */

import type {
  EntityGraph,
  TaxonomyProposal,
  TaxonomyCoordinates,
  LLMSettings,
  ConfidenceThresholds,
} from './types';
import { DEFAULT_CONFIDENCE_THRESHOLDS } from './types';
import { callTaxonomyLLM } from './llm-client';

// ── Constants ──────────────────────────────────────────────────

/** Max fields to include in LLM prompt to avoid context window bloat. */
const MAX_FIELDS_IN_PROMPT = 20;

/** Default LLM timeout per entity (ms). */
const DEFAULT_TIMEOUT_MS = 5000;

// ── Known taxonomy paths for pre-filtering ─────────────────────

/** Seed taxonomy paths for similarity matching. */
const KNOWN_TAXONOMY_PATHS: string[] = [
  'what.object.property', 'what.object.vehicle', 'what.object.device',
  'what.resource.material', 'what.resource.energy', 'what.resource.water',
  'what.person.tenant', 'what.person.owner', 'what.person.employee',
  'what.record.lease', 'what.record.contract', 'what.record.invoice',
  'what.record.receipt', 'what.record.certificate',
  'what.event.inspection', 'what.event.maintenance', 'what.event.payment',
  'what.service.property', 'what.service.maintenance', 'what.service.repair',
  'what.process.workflow', 'what.process.approval',
  'how.technical.api.rest', 'how.technical.api.graphql', 'how.technical.database',
  'how.physical.manual', 'how.digital.automated',
  'why.integration.data-sync', 'why.compliance.audit', 'why.operations.management',
  'why.maintenance.repair', 'why.maintenance.inspection',
  'why.finance.billing', 'why.finance.accounting',
];

// ── Main Entry Point ───────────────────────────────────────────

/**
 * Map taxonomy coordinates for each entity in the graph using LLM.
 *
 * @param graph - EntityGraph from StructureAnalyzer
 * @param settings - LLM connection settings
 * @param options - Confidence thresholds and timeout configuration
 */
export async function mapTaxonomy(
  graph: EntityGraph,
  settings: LLMSettings,
  options?: {
    thresholds?: ConfidenceThresholds;
    timeoutMs?: number;
  },
): Promise<TaxonomyProposal> {
  const thresholds = options?.thresholds ?? DEFAULT_CONFIDENCE_THRESHOLDS;
  const timeoutMs = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const entitySuggestions: Record<string, TaxonomyCoordinates> = {};

  for (const entity of graph.nodes) {
    const coordinates = await inferEntityTaxonomy(entity, settings, thresholds, timeoutMs);
    entitySuggestions[entity.id] = coordinates;
  }

  return { entitySuggestions };
}

// ── Per-Entity Inference ───────────────────────────────────────

async function inferEntityTaxonomy(
  entity: { id: string; displayName: string; fields: { name: string; type: string; sampleValues: unknown[] }[] },
  settings: LLMSettings,
  thresholds: ConfidenceThresholds,
  timeoutMs: number,
): Promise<TaxonomyCoordinates> {
  // Step 1: Pre-filter with string similarity — find top-3 similar paths
  const similarPaths = findSimilarTaxonomyPaths(entity.id, entity.fields.map(f => f.name));

  // Step 2: Build LLM prompt
  const { systemPrompt, userMessage } = buildTaxonomyPrompt(entity, similarPaths);

  // Step 3: Call LLM
  const llmResponse = await callTaxonomyLLM(systemPrompt, userMessage, settings, timeoutMs);

  if (!llmResponse) {
    // LLM unavailable or timed out — return zero-confidence placeholder
    return zeroConfidenceCoordinates(entity.id, similarPaths);
  }

  // Step 4: Parse and cross-check
  return parseTaxonomyResponse(llmResponse, similarPaths, thresholds);
}

// ── Pre-Filter with String Similarity ──────────────────────────

/** Compute Levenshtein distance between two strings. */
function levenshtein(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  const dp: number[][] = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1]
        : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
    }
  }
  return dp[m][n];
}

/** Normalized similarity score (0.0–1.0) based on Levenshtein distance. */
function similarity(a: string, b: string): number {
  if (a === b) return 1.0;
  const maxLen = Math.max(a.length, b.length);
  if (maxLen === 0) return 1.0;
  return 1.0 - levenshtein(a.toLowerCase(), b.toLowerCase()) / maxLen;
}

interface SimilarPath {
  path: string;
  score: number;
}

/**
 * Find top-3 most similar known taxonomy paths for a given entity.
 * Uses string similarity against entity name and field names.
 */
function findSimilarTaxonomyPaths(entityId: string, fieldNames: string[]): SimilarPath[] {
  const scored: SimilarPath[] = [];

  for (const path of KNOWN_TAXONOMY_PATHS) {
    const pathSegments = path.split('.').slice(1); // drop axis prefix ("what.", "how.", etc.)
    const lastSegment = pathSegments[pathSegments.length - 1] || '';

    // Score against entity name
    let bestScore = similarity(entityId, lastSegment);

    // Also score against full path tail
    const pathTail = pathSegments.join('.');
    bestScore = Math.max(bestScore, similarity(entityId, pathTail) * 0.8);

    // Score against field names (boost if any field matches a path segment)
    for (const fieldName of fieldNames.slice(0, MAX_FIELDS_IN_PROMPT)) {
      for (const segment of pathSegments) {
        const fieldScore = similarity(fieldName.replace(/_/g, ''), segment) * 0.5;
        bestScore = Math.max(bestScore, fieldScore);
      }
    }

    scored.push({ path, score: bestScore });
  }

  return scored
    .sort((a, b) => b.score - a.score)
    .slice(0, 3);
}

// ── LLM Prompt Construction ────────────────────────────────────

function buildTaxonomyPrompt(
  entity: { id: string; displayName: string; fields: { name: string; type: string; sampleValues: unknown[] }[] },
  similarPaths: SimilarPath[],
): { systemPrompt: string; userMessage: string } {
  const systemPrompt = `You are a taxonomy classification assistant for Semantos, a semantic type system.

Given an entity detected from an API response, suggest taxonomy coordinates on three axes:

- WHAT: What the entity is — a dot-separated path describing the object category.
  Examples: "what.object.property", "what.record.lease", "what.person.tenant"

- HOW: How it is structured or accessed — a dot-separated path.
  Examples: "how.technical.api.rest", "how.digital.automated"

- WHY: What business purpose it serves — a dot-separated path.
  Examples: "why.integration.data-sync", "why.maintenance.repair"

Respond ONLY as JSON: {"what": "path", "how": "path", "why": "path", "confidence": 0.0-1.0}

Set confidence < 0.5 if you cannot confidently assign a coordinate.
Paths must start with the axis name (what., how., why.).`;

  // Prune fields: strip ID fields, boolean flags; keep the most semantic fields
  const semanticFields = selectSemanticFields(entity.fields);

  const fieldList = semanticFields
    .map(f => {
      const samples = f.sampleValues.slice(0, 2).map(v => JSON.stringify(v)).join(', ');
      return `  - ${f.name} (${f.type})${samples ? `: ${samples}` : ''}`;
    })
    .join('\n');

  const similarSection = similarPaths.length > 0
    ? `\nSimilar existing taxonomy nodes:\n${similarPaths.map(s => `  - ${s.path} (similarity: ${s.score.toFixed(2)})`).join('\n')}`
    : '';

  const userMessage = `Entity: "${entity.displayName}" (id: ${entity.id})

Fields:
${fieldList}
${similarSection}

Suggest WHAT/HOW/WHY taxonomy coordinates for this entity.`;

  return { systemPrompt, userMessage };
}

/**
 * Select the most semantically meaningful fields for LLM context.
 * Strips raw boolean flags and generic _id fields; caps at MAX_FIELDS_IN_PROMPT.
 */
function selectSemanticFields(
  fields: { name: string; type: string; sampleValues: unknown[] }[],
): { name: string; type: string; sampleValues: unknown[] }[] {
  // Prioritize: non-ID, non-boolean fields first, then enum fields, then the rest
  const scored = fields.map(f => {
    let priority = 1;
    if (f.type === 'enum') priority = 3;
    else if (f.type === 'date' || f.type === 'datetime') priority = 2;
    else if (f.type === 'string' && !f.name.endsWith('_id') && f.name !== 'id') priority = 2;
    else if (f.type === 'boolean') priority = 0;
    else if (f.name === 'id' || f.name.endsWith('_id')) priority = 0;
    return { field: f, priority };
  });

  return scored
    .sort((a, b) => b.priority - a.priority)
    .slice(0, MAX_FIELDS_IN_PROMPT)
    .map(s => s.field);
}

// ── Response Parsing ───────────────────────────────────────────

function parseTaxonomyResponse(
  llmResponse: string,
  similarPaths: SimilarPath[],
  _thresholds: ConfidenceThresholds,
): TaxonomyCoordinates {
  let parsed: { what?: string; how?: string; why?: string; confidence?: number };
  try {
    parsed = JSON.parse(llmResponse);
  } catch {
    return zeroConfidenceCoordinates('unknown', similarPaths);
  }

  const rawConfidence = typeof parsed.confidence === 'number'
    ? Math.max(0, Math.min(1, parsed.confidence))
    : 0.0;

  // Cross-check: boost confidence if LLM suggestion matches high-similarity pre-filter
  const whatPath = typeof parsed.what === 'string' ? parsed.what : '';
  const howPath = typeof parsed.how === 'string' ? parsed.how : '';
  const whyPath = typeof parsed.why === 'string' ? parsed.why : '';

  const whatConfidence = adjustConfidence(rawConfidence, whatPath, similarPaths);
  const howConfidence = adjustConfidence(rawConfidence, howPath, similarPaths);
  const whyConfidence = adjustConfidence(rawConfidence, whyPath, similarPaths);

  return {
    what: { path: whatPath || 'what.unknown', confidence: whatConfidence },
    how: { path: howPath || 'how.unknown', confidence: howConfidence },
    why: { path: whyPath || 'why.unknown', confidence: whyConfidence },
    llmReasoning: llmResponse,
  };
}

/**
 * Adjust LLM confidence based on pre-filter similarity scores.
 * If LLM suggestion matches a high-similarity node, boost confidence.
 * If it contradicts (low similarity), apply skepticism.
 */
function adjustConfidence(
  rawConfidence: number,
  suggestedPath: string,
  similarPaths: SimilarPath[],
): number {
  if (similarPaths.length === 0 || !suggestedPath) return rawConfidence;

  // Check if the suggestion matches any pre-filtered path
  const matchingPreFilter = similarPaths.find(sp =>
    suggestedPath.startsWith(sp.path) || sp.path.startsWith(suggestedPath),
  );

  if (matchingPreFilter && matchingPreFilter.score > 0.6) {
    // LLM agrees with high-similarity pre-filter — boost
    return Math.min(1.0, rawConfidence + 0.05);
  }

  // Check for contradiction: LLM suggested something very different from pre-filter
  const bestPreFilterScore = similarPaths[0]?.score ?? 0;
  if (bestPreFilterScore > 0.7) {
    // Pre-filter had a strong match but LLM didn't match it — apply skepticism
    return Math.max(0, rawConfidence - 0.10);
  }

  return rawConfidence;
}

/** Return zero-confidence coordinates when LLM is unavailable. */
function zeroConfidenceCoordinates(
  entityId: string,
  similarPaths: SimilarPath[],
): TaxonomyCoordinates {
  // Use best similar path as fallback suggestion if available
  const bestWhat = similarPaths.find(s => s.path.startsWith('what.'));
  const bestHow = similarPaths.find(s => s.path.startsWith('how.'));
  const bestWhy = similarPaths.find(s => s.path.startsWith('why.'));

  return {
    what: { path: bestWhat?.path ?? `what.inferred.${entityId}`, confidence: 0.0 },
    how: { path: bestHow?.path ?? 'how.technical.api.rest', confidence: 0.0 },
    why: { path: bestWhy?.path ?? 'why.integration.data-sync', confidence: 0.0 },
    llmReasoning: 'LLM unavailable — zero confidence fallback.',
  };
}

```
