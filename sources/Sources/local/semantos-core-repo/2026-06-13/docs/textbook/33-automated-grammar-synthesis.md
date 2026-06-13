---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/33-automated-grammar-synthesis.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.643400+00:00
---

# Automated Grammar Synthesis

**Part IX — Verticals and the Grammar Layer**

Chapter 31 described the extension grammar as a declarative document that a domain expert writes. Chapter 32 described how the intent reducer uses that grammar to compress utterances into SIR programs. This chapter describes how to generate grammars automatically — from API probing, Swagger/OpenAPI specs, and Pask-backed semantic inference — so that connecting a new external system does not require a domain expert to write field mappings by hand.

The central insight is that the most labour-intensive part of grammar authorship is not declaring the grammar's source protocol, authentication scheme, or capability requirements. Those are mechanical. The hard part is assigning taxonomy coordinates — deciding that this entity in the external system corresponds to `what.property.residential` rather than `what.property.commercial`, and that this field should map to `how.lifecycle.create` rather than `how.commercial.payment`. These decisions require semantic judgment.

Pask's interaction-propagation model provides that judgment automatically. By running trial API calls and propagating interaction strength through a graph whose nodes are field-path/taxonomy-path pairs, the system learns which semantic types each field most plausibly corresponds to — not by string matching but by co-activation in the same entity context, the same pattern of use across multiple API responses. The result is a `TaxonomyProposal` that the grammar composer can use to assemble a validated `ExtensionGrammar` draft.

---

## The inference pipeline

Grammar synthesis runs in five stages, each consuming the output of the previous:

```
API spec / live endpoint
  ↓ Structure analyzer → EntityGraph
  ↓ Pask TaxonomyMapper → TaxonomyProposal
  ↓ GrammarDiffEngine → GrammarDiff
  ↓ GrammarComposer → ComposedGrammar
  ↓ validateExtensionGrammar() → valid | errors
```

The entry point is:

```ts
// extensions/extraction/src/auto-grammar.ts

export interface AutoGrammarOptions {
  apiSpecUrl?: string;          // URL to Swagger/OpenAPI spec
  swaggerDoc?: OpenAPIObject;   // pre-parsed spec (alternative to URL)
  liveEndpoint?: string;        // base URL for live probing (alternative to spec)
  lexiconName: AnyLexicon['name']; // lexicon to bind the grammar to
  domainFlag: number;           // domain flag for the grammar
  grammarIdPrefix?: string;     // e.g. 'com.semantos' → 'com.semantos.example-api'
  paskStorePath?: string;       // path to pre-seeded Pask store (default: shared corpus)
  probeCount?: number;          // number of sample API calls for live probing (default: 5)
}

export interface AutoGrammarResult {
  grammar: ExtensionGrammar | null;
  manifest: ExtensionManifest | null;
  valid: boolean;
  validationErrors?: GrammarValidationError[];
  lowConfidenceFlags: InferenceFlag[];
  summary: string;
}

export async function autoGrammar(options: AutoGrammarOptions): Promise<AutoGrammarResult>;
```

The output is always AFFINE-linearity (`manifestLinearity: 'AFFINE'`). Graduation to RELEVANT requires human review and the governance ballot process described in Chapter 31. Automated synthesis does not graduate grammars; it drafts them.

---

## Stage 1 — Structure analyzer: EntityGraph

The structure analyzer produces an `EntityGraph`: a set of entity nodes, each with a list of typed fields and relationships to other entities, derived from either an API spec or live API probing.

### From Swagger/OpenAPI

The Swagger ingester (`swagger-ingester.ts`) parses an OpenAPI 3.x document and constructs the entity graph from the `paths` and `components/schemas` sections. Each schema that appears as a response body for a `GET` operation becomes an entity node. Fields are inferred from the schema's `properties`, with types mapped from JSON Schema types to `SourceFieldType`. Relationships are inferred from `$ref` chains and `allOf` compositions — a `$ref` from field A in entity B to schema C is a `belongs_to` relationship from B to C.

The ingester does not attempt to resolve every `$ref` chain; it stops at two levels deep to avoid combinatorial explosion in deeply nested schemas. The Pask TaxonomyMapper handles residual ambiguity in the relationship inference.

### From live probing

The API probe runner (`api-probe.ts`) issues a configurable number of sample requests (`probeCount`, default 5) to each `list` endpoint in the target API and observes the response shapes. It does not require credentials for read endpoints — the auth scheme is declared in the grammar and is irrelevant to structure inference. The probe runner uses heuristic field typing: ISO timestamp strings become `datetime`, integer strings become `number`, short strings with few distinct values become `enum` candidates.

The probe runner's output is identical in shape to the Swagger ingester's output: an `EntityGraph`. The two paths are interchangeable from the perspective of downstream stages.

---

## Stage 2 — Pask TaxonomyMapper: from field names to semantic coordinates

This is the central novelty of the automated grammar synthesis pipeline. The Pask TaxonomyMapper replaces the `grammar-diff.ts` Levenshtein name-similarity heuristic with semantic propagation.

### The Pask model for taxonomy mapping

Pask's `Store.interact(primary_cell_id, related_ids, strength)` propagates interaction strength through a graph. Nodes with high co-activation strength develop strong edge weights. After many interactions, the graph's edge weights encode learned associations — not similarity of names, but similarity of context.

The TaxonomyMapper uses this to learn field→taxonomy associations:

1. **Seed the store.** A dedicated Pask store is pre-seeded with known grammar field→taxonomy associations drawn from the existing grammar corpus (PropertyMe, oddjobz, SCADA, CDM, etc.). Each known association `(field_path, taxonomy_path)` is encoded as a pair of cell IDs. The seeding call is `store.interact(field_cell_id, [taxonomy_path_cell_id], 1.0)` for each confirmed association.

2. **Map new fields.** For each field in the EntityGraph, the TaxonomyMapper generates a set of candidate taxonomy paths from the entity's context (its surrounding fields, its relationship targets, and any type hints from the structure analyzer). For each candidate:

```ts
store.interact(
  hashToId(entityId + '.' + fieldName),   // field cell
  [
    hashToId(candidateTaxonomyPath),       // taxonomy candidate cell
    ...relatedKnownFieldCellIds,           // pull known fields into context
  ],
  candidateScore,                          // heuristic initial weight
);
```

3. **Propagate.** After all candidates have been inserted, the store's propagation pass runs (the same `pask_propagation` used by the cell engine). Strength flows through the graph — fields that co-activate with the same taxonomy paths as known fields in the same entity context receive higher weight.

4. **Extract top-k associations.** After propagation, the TaxonomyMapper reads the edge weights for each field cell and selects the highest-weight taxonomy path for each of the three required axes (`what`, `how`, `why`). The weight becomes the confidence score in the `TaxonomyProposal`.

```ts
interface TaxonomyCoordSuggestion {
  path: string;         // e.g. 'what.property.residential'
  confidence: number;   // Pask edge weight, normalised to 0–1
  basis: string;        // which known field drove this suggestion
}

interface TaxonomyProposal {
  entitySuggestions: Record<string, {
    what: TaxonomyCoordSuggestion;
    how: TaxonomyCoordSuggestion;
    why: TaxonomyCoordSuggestion;
    where?: TaxonomyCoordSuggestion;
  }>;
}
```

### Why Pask and not a classifier

A classifier would require a training set and produce a fixed mapping. Pask's propagation is incremental: every successfully deployed grammar becomes additional training data automatically. The store is seeded from the existing grammar corpus; as grammars are authored and deployed, they are added to the corpus; subsequent auto-grammar runs benefit from a richer corpus without any explicit retraining step.

This is the Pask model applied to grammatical learning: the system triangulates on semantic type paths through trial-and-error API calls, the same way Pask's interact() triangulates on relationship weights through trial-and-error interaction. The corpus IS the knowledge; propagation IS the inference.

The Pask store for grammar inference uses `propagation_depth: 3` and `learning_rate: 0.05` — a slower learning rate than the real-time Pask kernel, because the corpus is accumulated across many grammars rather than updated in real-time. Stability is more important than speed in the offline inference setting.

---

## Stage 3 — GrammarDiffEngine: compare against known grammars

Before assembling a new grammar, the diff engine compares the proposed EntityGraph against every installed grammar using field overlap and name similarity. This serves two purposes.

**Reuse detection.** If the proposed entities match an existing grammar at >= 70% field overlap (the `MATCH_THRESHOLD`), the new grammar should declare `extends` on the matching grammar rather than duplicating its field declarations. This keeps the grammar registry small and makes version management tractable.

**Flag divergence.** Fields that are present in the new entity graph but absent in the matching grammar are flagged as `unmappedFields`. Fields whose types differ between the proposal and the known grammar are flagged as `typeMismatches`. These flags appear in the `ComposedGrammar.lowConfidenceFlags` array and require human review before the grammar can graduate.

The diff engine does not modify the EntityGraph or the TaxonomyProposal. It only annotates the final composed grammar with flags that surface in the review UI.

---

## Stage 4 — GrammarComposer: assemble the ExtensionGrammar

The grammar composer assembles a complete `ExtensionGrammar` JSON from the EntityGraph, TaxonomyProposal, and GrammarDiff. Its entry point:

```ts
composeGrammar(
  graph: EntityGraph,
  taxonomy: TaxonomyProposal,
  diff: GrammarDiff,
  sourceConfig: Partial<SourceDeclaration>,
  options?: { thresholds?: ConfidenceThresholds; grammarIdPrefix?: string },
): ComposedGrammar
```

The composer produces field mappings that are intentionally conservative: all fields default to identity mappings (sourceField → targetField, no transform). Transforms (`concat`, `split`, `lookup`, `map_enum`, `compute`) require human authorship — the composer does not invent them. The `GrammarDiff.unmappedFields` are included with `required: false` and a `// inferred` annotation in the metadata, signalling that they need review.

Low-confidence taxonomy suggestions (below `thresholds.high`, default 0.7) are flagged with:

```
${axis.toUpperCase()} coordinate '${path}' has confidence ${score} (below ${threshold}).
```

These flags appear in the grammar review interface. A grammar with unflagged high-confidence taxonomy assignments and no type mismatches is a candidate for graduation to RELEVANT without further human authorship. A grammar with multiple low-confidence flags needs domain review before graduation.

---

## Stage 5 — Manifest wrapper: AFFINE draft

The manifest wrapper (`manifest-wrapper.ts`) wraps the composed grammar in an `ExtensionManifest`:

```ts
function wrapInManifest(
  grammar: ExtensionGrammar,
  options: ManifestWrapOptions,
): ExtensionManifest {
  return {
    id: grammar.grammarId.split('.').pop() ?? 'inferred',
    name: grammar.displayName,
    version: grammar.grammarVersion,
    taxonomyPath: `taxonomy/${grammar.taxonomyNamespace}.json`,
    flowsDir: 'flows',
    promptsDir: 'prompts',
    governanceConfig: {
      patchAcceptancePolicy: 'author_only',
      versionBumpRules: { major: 'author_only', minor: 'author_only', patch: 'author_only' },
      contributorHats: [],
      deprecationTimelineMinDays: 30,
      trustClass: 'cosmetic',     // conservative default — author elevates explicitly
      proofRequirement: 'none',
      executionAuthority: 'local_facet',
    },
    manifestLinearity: 'AFFINE',  // always; graduation is manual
    grammar,
  };
}
```

The governance config defaults to the most conservative possible settings: `author_only` patch acceptance, `cosmetic` trust class, `none` proof requirement, `local_facet` execution authority. The grammar author must explicitly elevate each of these if the domain requires it. The constraint engine will reject any elevation that is not accompanied by the required proof (for `formal`) or attestation chain (for `attestation`).

---

## The graduation path

An auto-generated AFFINE grammar graduates to RELEVANT through the following steps, which the automated pipeline cannot perform:

1. **Human review.** The domain expert inspects all `lowConfidenceFlags`, resolves type mismatches, and authors any required transforms. At minimum, they confirm that the taxonomy coordinates are semantically correct for the domain.

2. **Gate test.** A gate test (`phase36a-extension-grammar.test.ts`) validates the grammar against the full constraint suite: `validateExtensionGrammar`, `enforceL0Constraints`, and round-trip through `grammarToExtensionConfig`.

3. **Governance ballot.** If `patchAcceptancePolicy` is not `author_only`, or if the grammar targets a ballot-gated taxonomy namespace, the ballot machinery issues a vote among `contributorHats`. The existing Ballot object type handles this without additional infrastructure.

4. **`manifestLinearity` → RELEVANT.** The manifest is patched to `manifestLinearity: 'RELEVANT'` via the standard L1 patch acceptance process. Once RELEVANT, the grammar is published and cannot be reverted to AFFINE without a breaking-change ballot.

---

## The CLI entry point

The full pipeline is accessible from the command line via a Zig CLI module:

```sh
# From a Swagger/OpenAPI spec
cd core/cell-engine
zig build auto-grammar -- --swagger /path/to/openapi.json --lexicon jural --domain-flag 42

# From a live API endpoint (requires probeCount sample calls)
zig build auto-grammar -- --api https://api.example.com --lexicon property-management \
  --domain-flag 15 --probe-count 10 --grammar-id-prefix com.myorg
```

The output is written to `./output/<grammarId>/` with the composed grammar JSON and the AFFINE manifest. The summary line prints the entity count, match count, low-confidence flag count, and validation status.

---

## What the automation does and does not replace

**Does replace:** the mechanical work of declaring field types, endpoint paths, response shapes, and pagination config from an OpenAPI spec. The Swagger ingester does this completely. A spec-driven grammar generation for a well-documented REST API takes seconds, not hours.

**Partially replaces:** taxonomy coordinate assignment. Pask's inference is accurate for entities whose semantic type is well-represented in the existing grammar corpus. Novel entity types — a domain that has never been connected to Semantos before — may receive low-confidence suggestions that require human judgment to resolve.

**Does not replace:** domain expertise on transforms. A field that requires a `map_enum` transform (converting external status codes to Semantos phase names) or a `compute` expression (deriving a value from two source fields) requires a human to author the transform. The composer leaves these as identity mappings with flags.

**Does not replace:** governance decisions. The trust class, proof requirement, and execution authority declarations are always human decisions. The composer defaults to the most conservative settings; the author must elevate them explicitly.

**Does not replace:** taxonomy namespace design. If a new domain introduces entity types that do not fit anywhere in the existing taxonomy, the author must design the taxonomy extension nodes. The composer can generate a `taxonomyExtensions` stub but cannot invent the semantics of new taxonomy paths.

The automation is a first-draft tool. Its output is ready for review, not for production. The value is in eliminating the mechanical scaffolding so the domain expert can focus on the semantically interesting decisions: does this entity really belong at `what.property.residential`, or is it a kind of `what.property.commercial`? What jural category does a quote approval exercise — permission or power? The automation handles everything below that line of judgment.
