---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/auto-grammar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.454495+00:00
---

# packages/extraction/src/auto-grammar.ts

```ts
/**
 * G-5 — Grammar automation entry point.
 *
 * `autoGrammar` runs the full five-stage inference pipeline:
 *
 *   1. Structure analyzer → EntityGraph
 *      (from Swagger spec OR live API probing)
 *   2. Pask TaxonomyMapper → TaxonomyProposal
 *      (replaces LLM + Levenshtein with Pask propagation)
 *   3. GrammarDiffEngine → GrammarDiff
 *      (compares against installed grammars; detects reuse opportunities)
 *   4. GrammarComposer → ComposedGrammar
 *      (assembles the ExtensionGrammar JSON with identity mappings)
 *   5. validateExtensionGrammar → valid | errors
 *
 * Output is always AFFINE. Graduation to RELEVANT requires human review
 * + gate test + governance ballot. See Chapter 31 §Graduation path.
 *
 * See docs/textbook/33-automated-grammar-synthesis.md
 */

import type { ExtensionGrammar, SourceDeclaration } from '@semantos/protocol-types';
import type { AnyLexicon } from '@semantos/semantos-sir';
import type { PaskAdapter } from '../../../core/pask/bindings/ts/src';
import { probeApi } from './inference/api-probe';
import { ingestSwagger, type OpenAPIObject } from './inference/swagger-ingester';
import { mapTaxonomyWithPask, createSeededAdapter } from './inference/pask-taxonomy-mapper';
import { diffGrammars } from './inference/grammar-diff';
import { composeGrammar } from './inference/grammar-composer';
import type { EntityGraph, InferenceFlag, ConfidenceThresholds } from './inference/types';
import { DEFAULT_CONFIDENCE_THRESHOLDS } from './inference/types';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export interface AutoGrammarOptions {
  /** URL to a Swagger/OpenAPI 3.x spec (fetched at runtime). */
  apiSpecUrl?: string;
  /** Pre-parsed OpenAPI doc (alternative to apiSpecUrl). */
  swaggerDoc?: OpenAPIObject;
  /** Base URL for live API probing (alternative to spec). */
  liveEndpoint?: string;
  /** Additional paths to probe when using liveEndpoint. */
  probePaths?: string[];
  /** Number of probe requests per path (default 5). */
  probeCount?: number;
  /** Optional headers for authenticated probe requests. */
  probeHeaders?: Record<string, string>;
  /**
   * Lexicon name to bind the grammar to. Used in the grammar's
   * ExtensionGrammarSpec section. Not yet enforced by autoGrammar itself —
   * the grammar reviewer selects the appropriate lexicon during human review.
   */
  lexiconName?: AnyLexicon['name'];
  /** Domain flag for the grammar's SIR nodes (must be unique per deployment). */
  domainFlag: number;
  /** Grammar ID prefix (e.g. 'com.semantos' → 'com.semantos.example-api'). */
  grammarIdPrefix?: string;
  /** Partial source config (auth, baseUrl, rateLimits, pagination). */
  sourceConfig?: Partial<SourceDeclaration>;
  /** Installed grammars to diff against (for reuse detection). */
  installedGrammars?: ExtensionGrammar[];
  /** Confidence thresholds for low-confidence flags (default: high=0.8, medium=0.5). */
  thresholds?: ConfidenceThresholds;
  /**
   * Pre-seeded Pask adapter. Callers processing many grammars in one session
   * should create once via createSeededAdapter() and pass here to avoid
   * repeated WASM loading.
   */
  adapter?: PaskAdapter;
}

export interface AutoGrammarResult {
  grammar: ExtensionGrammar | null;
  valid: boolean;
  validationErrors?: import('@semantos/protocol-types').GrammarValidationError[];
  lowConfidenceFlags: InferenceFlag[];
  entityGraph: EntityGraph;
  summary: string;
}

// ---------------------------------------------------------------------------
// Main orchestration
// ---------------------------------------------------------------------------

/**
 * Run the full grammar inference pipeline. Returns an AFFINE draft grammar
 * (or null if inference failed entirely).
 *
 * @example
 * const result = await autoGrammar({
 *   apiSpecUrl: 'https://api.propertyme.com/openapi.json',
 *   domainFlag: 42,
 *   grammarIdPrefix: 'com.acme',
 * });
 */
export async function autoGrammar(options: AutoGrammarOptions): Promise<AutoGrammarResult> {
  const thresholds = options.thresholds ?? DEFAULT_CONFIDENCE_THRESHOLDS;

  // ── Stage 1: Build EntityGraph ─────────────────────────────────
  let entityGraph: EntityGraph;

  if (options.swaggerDoc) {
    entityGraph = ingestSwagger({ spec: options.swaggerDoc });
  } else if (options.apiSpecUrl) {
    const spec = await fetchSpec(options.apiSpecUrl);
    entityGraph = ingestSwagger({ spec, sourceUrl: options.apiSpecUrl });
  } else if (options.liveEndpoint) {
    const result = await probeApi({
      baseUrl: options.liveEndpoint,
      paths: options.probePaths,
      probeCount: options.probeCount ?? 5,
      headers: options.probeHeaders,
    });
    entityGraph = result.entityGraph;
  } else {
    return {
      grammar: null,
      valid: false,
      lowConfidenceFlags: [],
      entityGraph: { nodes: [], edges: [], nestedPaths: {} },
      summary: 'Error: one of apiSpecUrl, swaggerDoc, or liveEndpoint is required.',
    };
  }

  if (entityGraph.nodes.length === 0) {
    return {
      grammar: null,
      valid: false,
      lowConfidenceFlags: [],
      entityGraph,
      summary: 'No entities detected from the provided API spec/endpoint.',
    };
  }

  // ── Stage 2: Pask TaxonomyMapper ──────────────────────────────
  const adapter = options.adapter ?? await createSeededAdapter();
  const taxonomy = await mapTaxonomyWithPask(entityGraph, { thresholds, adapter });

  // ── Stage 3: GrammarDiff ───────────────────────────────────────
  const diff = diffGrammars(entityGraph, options.installedGrammars ?? []);

  // ── Stage 4: GrammarComposer ───────────────────────────────────
  const sourceConfig: Partial<SourceDeclaration> = {
    protocol: 'rest',
    baseUrlTemplate: options.liveEndpoint ?? options.apiSpecUrl ?? 'https://api.example.com',
    auth: { type: 'none', requiredCredentials: [] },
    ...options.sourceConfig,
  };

  const composed = composeGrammar(entityGraph, taxonomy, diff, sourceConfig, {
    thresholds,
    grammarIdPrefix: options.grammarIdPrefix,
  });

  // ── Stage 5: Summary ──────────────────────────────────────────
  const highConf = Object.values(taxonomy.entitySuggestions).filter(
    s => s.what.confidence >= thresholds.high && s.how.confidence >= thresholds.high,
  ).length;
  const lowConfCount = composed.lowConfidenceFlags.length;

  const summary = [
    `Entities: ${entityGraph.nodes.length}`,
    `New: ${diff.newEntities.length}, Matched: ${Object.keys(diff.matchedEntities).length}`,
    `High-confidence: ${highConf}/${entityGraph.nodes.length}`,
    `Low-confidence flags: ${lowConfCount}`,
    `Valid: ${composed.valid}`,
    composed.validationErrors?.length
      ? `Validation errors: ${composed.validationErrors.map(e => e.message).join('; ')}`
      : '',
  ].filter(Boolean).join(' | ');

  return {
    grammar: composed.grammar,
    valid: composed.valid,
    validationErrors: composed.validationErrors,
    lowConfidenceFlags: composed.lowConfidenceFlags,
    entityGraph,
    summary,
  };
}

// ---------------------------------------------------------------------------
// Spec fetcher
// ---------------------------------------------------------------------------

async function fetchSpec(url: string): Promise<OpenAPIObject> {
  const response = await fetch(url, {
    headers: { Accept: 'application/json, application/yaml, */*' },
  });
  if (!response.ok) {
    throw new Error(`Failed to fetch OpenAPI spec from ${url}: HTTP ${response.status}`);
  }
  const text = await response.text();
  try {
    return JSON.parse(text) as OpenAPIObject;
  } catch {
    throw new Error(`OpenAPI spec at ${url} is not valid JSON. YAML specs must be pre-parsed.`);
  }
}

```
