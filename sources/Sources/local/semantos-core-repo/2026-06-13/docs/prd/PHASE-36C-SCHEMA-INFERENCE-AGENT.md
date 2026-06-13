---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36C-SCHEMA-INFERENCE-AGENT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.675413+00:00
---

# Phase 36C — Schema Inference Agent

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 2 weeks (with 3-day buffer)
**Prerequisites**: Phase 36A complete (Extension Grammar JSON schema). Phase 36B complete (semantic extraction pipeline). Phase 9.5 complete (IntentClassifier/LLM integration via OpenRouter).
**Master document**: `PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md`
**Branch**: `phase-36c-schema-inference-agent`

---

## Context

When a Semantos node encounters a new API it has never seen before — say, a custom CRM system, a niche property management API, a SCADA historian with a proprietary REST interface — it needs to bootstrap its own connector without requiring a developer to hand-craft an Extension Grammar JSON. The **Schema Inference Agent** solves this problem by reading sample API responses and proposing a complete Extension Grammar as an AFFINE draft semantic object, ready for human review and approval.

The agent is not a general-purpose AI. It is a structured inference pipeline with three key properties:

1. **Deterministic where possible** — structure detection, field type inference, and entity boundary detection are pure parsing. No LLM calls for tasks that can be deterministically solved.
2. **LLM only for taxonomy** — the only LLM task is suggesting WHAT/HOW/WHY taxonomy coordinates for inferred entities, with confidence scores.
3. **Confidence-scored every step** — every inference step produces a confidence score (0.0–1.0). Low-confidence suggestions are flagged for human review. High-confidence suggestions can be auto-accepted.

The output is never auto-published. It always becomes an AFFINE draft object in the loom's semantic store, pending human review via the governance ballot system (Phase 36D). The agent does not write to the API, does not modify credentials, does not auto-approve grammars.

### Design Principles

**Staged inference, not end-to-end guessing.** The pipeline has five sequential stages: (1) detect entity boundaries and field types from raw responses, (2) build an entity graph with relationships, (3) suggest taxonomy coordinates using LLM + confidence scoring, (4) diff against known grammars to identify new vs. existing entities, (5) compose a complete Extension Grammar JSON and validate it.

**Human in the loop everywhere.** After each stage, the results are presented in the loom. A developer can adjust the inferred entity boundaries, re-run taxonomy mapping, or override a field type before composition. The agent is a suggestion engine, not a decision engine.

**Evidence chain continuity.** The inferred grammar carries full provenance: which responses were sampled, which inference steps ran, what confidence scores were assigned, what the developer changed in review. If the grammar is published later, this inference history is part of the semantic object's evidence chain.

---

## Source Files / References

| Alias | Path | What to read |
|-------|------|--------------|
| `GRAMMAR` | `packages/protocol-types/src/extension-grammar.ts` | ExtensionGrammar types (D36A.1 output) |
| `VALIDATOR` | `packages/protocol-types/src/extension-grammar-validator.ts` | validateExtensionGrammar() (D36A.2 output) |
| `PIPELINE` | `packages/extraction/src/pipeline.ts` | Extraction pipeline interface (D36B.1 output) |
| `EXTRACTOR` | `packages/extraction/src/extractor.ts` | SourceEntity, EntityGraph types (D36B.2 output) |
| `INTENT` | `packages/protocol-types/src/intent-classifier.ts` | LLM integration pattern via OpenRouter |
| `STORE` | `packages/loom/src/services/LoomStore.ts` | Semantic object storage (AFFINE objects) |
| `TAXONOMY` | `docs/TAXONOMY-SEED-DESIGN.md` | WHAT/HOW/WHY axis definitions |
| `SHELL` | `packages/shell/src/parser.ts` | Shell command parsing |

---

## Architecture

```
Raw API Response(s)
    ↓
[StructureAnalyzer] — detect entities, fields, types, nesting
    ↓
EntityGraph (nodes = entities, edges = relationships)
    ↓
[TaxonomyMapper] — LLM-assisted WHAT/HOW/WHY coordinate suggestion
    ↓
TaxonomyProposal (confidence-scored coordinates per entity)
    ↓
[GrammarDiffEngine] — compare against known grammars
    ↓
GrammarDiff (new entities, missing mappings, type mismatches)
    ↓
[GrammarComposer] — assemble proposed ExtensionGrammar JSON
    ↓
AFFINE Draft Grammar Object (pending human review)
```

---

## Deliverables

### D36C.1 — Structure Analyzer

**File**: `packages/extraction/src/inference/structure-analyzer.ts`

`analyzeStructure(responses: RawResponse[]): EntityGraph` — parses raw API responses and detects entity boundaries, field types, nesting, cardinality, and relationships.

**Detection rules:**

- **Entity boundaries**: If the response is an object containing an array of similar objects, each array element is an entity. If the response is a paginated result with a `data` field, objects in `data` are entities. If multiple responses are provided, infer the entity type from the root level (e.g., all responses have a `property` object → entity type `property`).

- **Field types**: Sample multiple responses; infer from the most frequent non-null value. Detect: `string`, `number`, `boolean`, `date` (ISO 8601 format), `datetime` (with time component), `array`, `object`, `enum` (small cardinality string field). Record cardinality.

- **Required vs. optional**: Field is required if it appears in ALL sampled responses; optional otherwise.

- **ID fields**: Heuristic detection — field named `id`, `_id`, `*_id`, or matching UUID pattern.

- **Timestamp fields**: Heuristic detection — field named `created*`, `updated*`, `*_at`, `*_time`, or matching ISO 8601/Unix timestamp format.

- **Enum fields**: If a string field has ≤10 unique values across samples, it's likely an enum. Collect all seen values.

- **Relationships**: If one entity contains a foreign key field (e.g., `property_id`) that matches another entity's ID field pattern, infer a `belongs_to` relationship. If an entity contains an array of objects with the same structure across samples, infer a `has_many` relationship.

- **Nesting depth**: Track and report; warn if depth > 4 levels (may indicate over-normalized API structure).

Output: `EntityGraph` with typed nodes and directional edges.

```typescript
interface EntityGraph {
  nodes: Entity[];
  edges: EntityRelationship[];
  nestedPaths: Map<string, string[]>;  // JSONPath → entity chain
}

interface Entity {
  id: string;                    // e.g., "property"
  displayName: string;           // e.g., "Property"
  fields: InferredField[];
  nestingLevel: number;
  sampleCount: number;           // how many responses this entity appeared in
}

interface InferredField {
  name: string;
  type: string;
  required: boolean;
  cardinality?: { min: number; max: number };  // array length range
  enumValues?: string[];
  sampleValues: unknown[];       // first 3 non-null examples
  detectionConfidence: number;   // 0.0-1.0, based on consistency
}

interface EntityRelationship {
  source: string;
  target: string;
  type: 'has_many' | 'has_one' | 'belongs_to';
  foreignKey: string;
  confidence: number;            // 0.0-1.0
}
```

**Test case**: Given a PropertyMe API response with Properties and Leases, detect `property` and `lease` entities, all required/optional fields, ID and timestamp fields, and the `property → lease` relationship.

### D36C.2 — Taxonomy Mapper

**File**: `packages/extraction/src/inference/taxonomy-mapper.ts`

`mapTaxonomy(graph: EntityGraph, knownTaxonomy: TaxonomyTree): TaxonomyProposal` — uses LLM calls via OpenRouter to suggest WHAT/HOW/WHY taxonomy coordinates for each entity in the graph.

**Process:**

1. **Pre-filter with embedding similarity** — before calling LLM, compute embedding vectors for each entity's name, description (from sample values), and field names using a local embedding model (or cached embeddings if available). Find the top-3 most-similar taxonomy nodes already in the system. Use these as context for the LLM prompt.

2. **Build LLM prompt** — for each entity, provide:
   - Entity name and sample field names
   - 3–5 sample values from the entity (anonymized if they contain PII)
   - Top-3 similar taxonomy nodes from step 1
   - Definition of WHAT/HOW/WHY axes (copied from TAXONOMY-SEED-DESIGN.md)
   - Instruction: "Given this entity and sample data, suggest a WHAT coordinate (object category), a HOW coordinate (how it is structured/accessed), and a WHY coordinate (business purpose). Respond as JSON: `{what: "path", how: "path", why: "path", confidence: 0.0-1.0}`. If you cannot confidently assign a coordinate, set confidence < 0.5."

3. **LLM call** — call IntentClassifier (Phase 9.5) with the prompt. Timeout: 5 seconds per entity. If LLM times out or returns unparseable JSON, confidence = 0.0.

4. **Score confidence** — the LLM returns a confidence score. Cross-reference against similarity scores from step 1. If the LLM suggestion matches a high-similarity node and the LLM confidence is high, boost confidence. If LLM suggestion contradicts the similarity pre-filter, apply skepticism.

5. **Classify suggestions**:
   - **High (>0.8)**: Auto-assign, user can override.
   - **Medium (0.5–0.8)**: Suggest with flag, user must approve or change.
   - **Low (<0.5)**: Leave unassigned, user must manually classify.

Output: `TaxonomyProposal`.

```typescript
interface TaxonomyProposal {
  entitySuggestions: Map<string, TaxonomyCoordinates>;  // entity ID → coordinates
}

interface TaxonomyCoordinates {
  what: { path: string; confidence: number };
  how: { path: string; confidence: number };
  why: { path: string; confidence: number };
  where?: { path: string; confidence: number };
  llmReasoning?: string;  // explanation from LLM for human review
}
```

**Test case**: Given an entity representing a property maintenance request, suggest `what.service.property.maintenance`, `how.technical.api.rest`, `why.maintenance.repair`.

### D36C.3 — Grammar Diff Engine

**File**: `packages/extraction/src/inference/grammar-diff.ts`

`diffGrammars(proposed: EntityGraph, known: ExtensionGrammar[]): GrammarDiff` — compares the inferred entity graph against all installed Extension Grammars to identify new entities, existing entities (with mapping), and unhandled fields.

**Algorithm:**

1. **Load all installed grammars** from the ExtensionRegistry.

2. **For each proposed entity**, check each installed grammar:
   - **Field overlap**: Count how many of the proposed entity's fields appear in any entity defined in the grammar. If overlap > 70% and field types match, consider it a match to that grammar's entity.
   - **Name similarity**: Use string distance (Levenshtein) to catch renames. If `maintenance_request` (proposed) has >80% similarity to `MaintenanceRequest` (in grammar), flag as potential match.

3. **Build diff output** with:
   - `newEntities`: entities in the proposal that don't match any existing grammar entity (overlap < 70%)
   - `matchedEntities`: entities in the proposal that match existing grammar entities (with mapping to grammar ID + entity ID)
   - `unmappedFields`: fields in proposed entities that don't appear in any matched grammar entity (may be new fields added by the API)
   - `typeMismatches`: fields where the proposed type differs from the matched grammar type (e.g., proposed `user_id` is string, grammar expects number)

Output: `GrammarDiff`.

```typescript
interface GrammarDiff {
  newEntities: string[];         // entity IDs with no match
  matchedEntities: Map<string, GrammarMatch>;
  unmappedFields: Map<string, InferredField[]>;  // entity ID → fields
  typeMismatches: Map<string, TypeMismatch[]>;   // entity ID → mismatches
}

interface GrammarMatch {
  grammarId: string;
  grammarEntityId: string;
  fieldOverlapPercent: number;
  confidence: number;            // 0.0-1.0
}

interface TypeMismatch {
  field: string;
  proposedType: string;
  grammarType: string;
  grammarId: string;
}
```

**Test case**: Given an inferred `lease` entity and an existing PropertyMe grammar with a `lease` entity, confirm match with 90%+ field overlap. For a completely new entity `inspectionSchedule`, report as new.

### D36C.4 — Grammar Composer

**File**: `packages/extraction/src/inference/grammar-composer.ts`

`composeGrammar(graph: EntityGraph, taxonomy: TaxonomyProposal, diff: GrammarDiff, sourceConfig: Partial<SourceDeclaration>): ComposedGrammar` — assembles a complete Extension Grammar JSON from the inference pipeline's outputs.

**Process:**

1. **Create top-level structure**:
   - `grammarId`: generate from source protocol + base URL (sanitized), e.g., `com.semantos.inferred.api-v2-propertyme-com`
   - `grammarVersion`: "0.1.0" (pre-release draft)
   - `metaSchemaVersion`: current meta-schema version (from GRAMMAR)
   - `displayName`: inferred from source (e.g., "Inferred PropertyMe Connector")
   - `description`: "Auto-inferred grammar from API sampling on [date]"
   - `author`: `{ certId: "inferred", name: "Schema Inference Agent" }`

2. **Populate source declaration**:
   - Use `sourceConfig` parameter for protocol, auth, rate limits
   - Add detected entities to `source.entities` (from EntityGraph)

3. **Create object type declarations**:
   - For each entity in the graph, create an ObjectTypeDeclaration with:
     - `typePath`: from TaxonomyProposal's WHAT coordinate (or fallback to `what.inferred.${entityId}`)
     - `displayName` and `description` from entity
     - `linearity`: default to "AFFINE" (all inferred objects are AFFINE until explicitly upgraded)
     - `phases`: default to `["draft", "active"]` (can be overridden by developer)
     - `payloadSchema`: generated from InferredField types (JSON Schema format)

4. **Create entity mappings**:
   - For each entity in the graph, create an EntityMapping with:
     - `sourceEntityId` from entity ID
     - `targetObjectType` from typePath
     - `fieldMappings`: auto-map source field → target field (usually 1:1, unless transform needed)
     - `taxonomy`: from TaxonomyProposal

5. **Flag unmatched entities**:
   - For entities with no match in existing grammars (from GrammarDiff), include a comment in the grammar metadata noting they are new and pending human review.

6. **Flag low-confidence inferences**:
   - For any taxonomy coordinate with confidence < 0.8, include in metadata: `_lowConfidenceInferences: [{ entity, coordinate, confidence, llmReasoning }]`
   - For any field with low type detection confidence, include in metadata

7. **Validate the composed grammar**:
   - Call `validateExtensionGrammar()` (D36A.2). If validation fails, include validation errors in the result.
   - If validation passes, mark grammar as valid.

Output: `ComposedGrammar`.

```typescript
interface ComposedGrammar {
  grammar: ExtensionGrammar;
  valid: boolean;
  validationErrors?: ValidationError[];
  lowConfidenceFlags: InferenceFlag[];
  summary: string;               // human-readable summary
}

interface InferenceFlag {
  type: 'low_confidence_taxonomy' | 'type_detection_mismatch' | 'unknown_entity';
  entity: string;
  field?: string;
  message: string;
  confidence?: number;
  suggestion?: string;
}
```

**Test case**: Compose a grammar from inferred PropertyMe data, validate it, and ensure all low-confidence taxonomy suggestions are flagged.

### D36C.5 — Inference Pipeline Orchestrator

**File**: `packages/extraction/src/inference/pipeline.ts`

`InferenceAgent` class with:

```typescript
class InferenceAgent {
  async infer(
    sampleResponses: RawResponse[],
    sourceConfig: Partial<SourceDeclaration>,
    options?: {
      baseGrammarId?: string;  // if extending an existing grammar
      skipValidation?: boolean;
      confidence?: { min: number };  // only suggest taxonomies with confidence >= min
    }
  ): Promise<InferenceResult>;
}

interface InferenceResult {
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
}
```

**Pipeline steps:**

1. Validate input: `sampleResponses` is non-empty, `sourceConfig` has required fields.
2. Run StructureAnalyzer → EntityGraph
3. Run TaxonomyMapper → TaxonomyProposal
4. Run GrammarDiffEngine → GrammarDiff
5. Run GrammarComposer → ComposedGrammar
6. **Create AFFINE semantic object** in LoomStore:
   - Create a semantic object of type `what.platform.extension.inferred-grammar`
   - Linearity: AFFINE (draft, not yet RELEVANT)
   - Payload: the ComposedGrammar
   - Evidence chain: include all inferred data (EntityGraph, TaxonomyProposal, GrammarDiff, flags)
   - Metadata: timestamp, sampled API responses (hashed), inference parameters
7. Return InferenceResult with visualization data for loom rendering

**Test case**: Infer a grammar from 3 PropertyMe API responses, verify the pipeline runs all stages, and confirm the resulting semantic object is stored as AFFINE in LoomStore.

### D36C.6 — Shell Command: `semantos infer`

**File**: Update `packages/shell/src/` (parser, router, inference subcommand)

New shell subcommand for inference operations:

```bash
semantos infer <api-url> --auth <type> [--auth-<field> <value>]
  # Sample live API and propose grammar
  # Example: semantos infer https://api.example.com/v2 --auth api-key --auth-header X-API-Key --auth-value sk-123

semantos infer <sample-file.json> [--source-type rest|graphql|grpc]
  # Infer grammar from saved API response file

semantos infer review <grammar-id>
  # Show proposed grammar, mark low-confidence fields, show entity graph

semantos infer approve <grammar-id> [--publish]
  # Approve inferred grammar (AFFINE → RELEVANT if --publish, else stays AFFINE)

semantos infer reject <grammar-id> --reason "reason text"
  # Reject with reason (grammar is archived, reason stored in evidence chain)

semantos infer list [--status draft|approved|rejected]
  # List inferred grammars by status
```

**Behavior:**

- `infer <api-url>` fetches live samples (default 3 requests, configurable with `--samples N`). Does NOT store credentials in the grammar or shell history. Credentials come from `--auth-*` flags, never persisted.
- `infer review` renders the proposed grammar, flags low-confidence items, displays entity graph in JSON.
- `infer approve` transitions the AFFINE draft to RELEVANT and optionally publishes (if `--publish`). Creates a ballot object for governance (Phase 36D).
- `infer reject` archives the grammar with reason. Reason is stored in the evidence chain.

**Test case**: Run `semantos infer <sample-file.json>`, review the result, then approve with `semantos infer approve <id>`.

---

## Gate Tests

**File**: `packages/__tests__/phase36c-schema-inference-agent.test.ts`

### Structure Analysis Tests (T1–T3)

```typescript
describe("StructureAnalyzer", () => {
  // T1: analyzeStructure() detects entity boundaries from array of objects
  // T2: analyzeStructure() infers field types (string, number, boolean, date, enum, array)
  // T3: analyzeStructure() detects ID and timestamp fields, relationships (has_many, belongs_to)
});
```

### Taxonomy Mapping Tests (T4–T6)

```typescript
describe("TaxonomyMapper", () => {
  // T4: mapTaxonomy() calls LLM and returns TaxonomyProposal with confidence scores
  // T5: Confidence >0.8 marked as high, 0.5–0.8 as medium, <0.5 as low
  // T6: mapTaxonomy() pre-filters with embedding similarity (top-3 similar nodes in LLM context)
});
```

### Grammar Diff Engine Tests (T7–T9)

```typescript
describe("GrammarDiffEngine", () => {
  // T7: diffGrammars() matches entities with >70% field overlap to existing grammar entities
  // T8: diffGrammars() identifies new entities (no match found)
  // T9: diffGrammars() detects type mismatches (proposed vs. existing grammar types)
});
```

### Grammar Composition Tests (T10–T11)

```typescript
describe("GrammarComposer", () => {
  // T10: composeGrammar() produces valid ExtensionGrammar that passes validateExtensionGrammar()
  // T11: composeGrammar() includes low-confidence flags in metadata
});
```

### Pipeline Tests (T12–T13)

```typescript
describe("InferenceAgent pipeline", () => {
  // T12: infer() runs all stages (StructureAnalyzer → TaxonomyMapper → DiffEngine → Composer) and returns InferenceResult
  // T13: infer() creates AFFINE semantic object in LoomStore with full evidence chain
});
```

### Shell Command Tests (T14)

```typescript
describe("semantos infer shell command", () => {
  // T14: `semantos infer review <id>` displays proposed grammar and flags; `semantos infer approve <id>` transitions to RELEVANT
});
```

---

## Completion Criteria

- [ ] `StructureAnalyzer` detects entities, fields, types, ID/timestamp fields, relationships
- [ ] `TaxonomyMapper` uses LLM (OpenRouter) with embedding pre-filter and confidence scoring
- [ ] `GrammarDiffEngine` compares proposed entities against installed grammars
- [ ] `GrammarComposer` assembles valid ExtensionGrammar and flags low-confidence inferences
- [ ] `InferenceAgent` orchestrates all stages and creates AFFINE semantic object in LoomStore
- [ ] `semantos infer` shell commands operational (infer, review, approve, reject, list)
- [ ] Tests T1–T14 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing gate tests still pass
- [ ] All commits follow `phase-36c/D36C.N:` naming convention
- [ ] Branch is `phase-36c-schema-inference-agent`

---

## What NOT to Do

- **Don't make the agent autonomous.** All inferred grammars are AFFINE drafts. The `infer approve` command with `--publish` requires explicit user action; no auto-publishing. No background job that auto-transitions inferred grammars to RELEVANT.

- **Don't use LLM for structural analysis.** Structure detection (entities, fields, types) is deterministic parsing. Only use LLM for taxonomy coordinate suggestion. If you find yourself calling LLM to detect fields or entity boundaries, you've failed.

- **Don't skip confidence scores.** Every inference must be confidence-scored. If an inference has no confidence attached, it's incomplete.

- **Don't propose grammars that fail validation.** The `GrammarComposer` must call `validateExtensionGrammar()` before returning. If the composed grammar is invalid, return errors; do not hide them.

- **Don't embed API credentials in the inference pipeline or the proposed grammar.** Credentials are ephemeral, used only for sampling. The grammar's `SourceDeclaration` specifies what credentials are *required*, not what they *are*. Binding (Phase 36D) handles credential management.

- **Don't hardcode confidence thresholds.** The thresholds (0.8 for high, 0.5 for medium) are conventions shown here; make them configurable in InferenceAgent options.

- **Don't lose provenance.** Every inferred grammar's evidence chain must include: sample responses (hashed), inference parameters, LLM reasoning for taxonomy suggestions, field type detection confidence, grammar diff results, and validation errors if any.

---

## Next Phase

Phase 36D implements the hierarchical governance model (L0 meta-schema policy, L1 extension author governance, L2 consumer binding) and the ballot/dispute system for approving/rejecting inferred grammars.
