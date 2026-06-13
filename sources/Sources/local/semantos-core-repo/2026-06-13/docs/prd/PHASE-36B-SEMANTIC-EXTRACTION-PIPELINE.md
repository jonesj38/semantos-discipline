---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36B-SEMANTIC-EXTRACTION-PIPELINE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.688189+00:00
---

# Phase 36B — Semantic Extraction Pipeline

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 3 weeks (4-day buffer)
**Prerequisites**: Phase 36A complete (Extension Grammar schema). Phase 30F.2 (CAS storage adapter). Phase 18 (metering control plane).
**Master document**: `PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md`
**Branch**: `phase-36b-semantic-extraction-pipeline`

---

## Context

Phase 36A defined the Extension Grammar JSON schema — the declarative contract that every connector implements to describe source entities, field mappings, taxonomy coordinates, and capability requirements. This phase implements the **semantic extraction pipeline**, the runtime that interprets an Extension Grammar and executes a five-stage flow: Fetch → Parse → Typecheck → Infer → Commit.

Each stage is a pure function that takes input + grammar and produces output + evidence. The pipeline is storage-adapter-agnostic and protocol-agnostic — the grammar declares everything protocol-specific (REST, GraphQL, file-based, event-driven). The pipeline does not care. Fetch adapters handle the protocol; the pipeline normalizes the response into an intermediate record. The pipeline then validates, infers, and commits. At each step, evidence is collected into an evidence chain that travels with the semantic object.

The extraction pipeline is the mechanism that turns an Extension Grammar into a running system: you plug in credentials, run extraction, and semantic objects appear in the VFS, queryable via shell, visible in loom.

### Design Principles

**Pure functions, not stateful processors.** Each stage takes input + grammar and produces output + evidence. No global state, no mutable caches, no side effects outside the specified outputs. This makes the pipeline composable: you can run stages independently for testing, or daisy-chain them for production.

**Evidence chains are mandatory.** Every object extracted through the pipeline carries a full evidence chain: source hash, parse mapping, typecheck result, inference record, commit cell ID. The evidence chain is not a nice-to-have — it is the value proposition. Consumers audit the provenance of every object.

**Protocol logic belongs in fetch adapters, not the pipeline.** The pipeline is generic. If you find yourself writing `if (protocol === 'rest')` in the pipeline, you've failed. REST details go in `RestFetchAdapter`. The pipeline reads `RawResponse[]` and doesn't care how they were fetched.

**AsyncGenerator for streaming.** The pipeline consumes and produces async generators, not arrays. This allows streaming large datasets without loading them into memory. The orchestrator collects results for reporting, but internal stages don't buffer.

**Idempotency by default.** If you run extraction twice for the same source + grammar version, you get one semantic object, not two. The commit stage detects duplicates and produces a patch instead of a new object.

---

## Architecture

```
Source API 
  ↓
[FetchStage]
  Source protocol (REST, GraphQL, file, etc.) → RawResponse[] (API response + metadata)
  ↓
[ParseStage]
  Grammar entity mappings → IntermediateRecord[] (normalized records, source→target fields)
  ↓
[TypecheckStage]
  Grammar object types + taxonomy + phase mapping → ValidatedRecord[] (schema-validated, phase-assigned)
  ↓
[InferStage]
  Known grammars → InferredRecord[] + GrammarPatch[] (enriched with inferred taxonomy, proposed schema changes)
  ↓
[CommitStage]
  LoomStore → SemanticObject[] (cells created with full evidence chains)
```

Each stage produces an `ExtractionEvidence` entry that gets appended to the semantic object's evidence chain:
- `FetchEvidence`: sourceHash, endpoint, timestamp, responseSize
- `ParseEvidence`: grammarVersion, fieldMappingApplied, sourceFieldsResolved
- `TypecheckEvidence`: validationResult (pass/fail), taxonomyAssigned, phaseAssigned
- `InferenceEvidence`: inferredTaxonomyPath, confidenceScore, proposedGrammarDiff
- `CommitEvidence`: cellId, storageAdapter, facetProvenance

---

## Source Files / References

| Alias | Path | What to read |
|-------|------|--------------|
| `GRAM:SCHEMA` | `packages/protocol-types/src/extension-grammar.ts` | ExtensionGrammar, FieldMapping, ObjectTypeDeclaration (Phase 36A output) |
| `GRAM:VALIDATOR` | `packages/protocol-types/src/extension-grammar-validator.ts` | validateExtensionGrammar() |
| `STORE:API` | `packages/loom/src/services/LoomStore.ts` | LoomStore, createObjectFromType(), attachEvidence() |
| `TYPES:PROTO` | `packages/protocol-types/src/index.ts` | SemanticObject, Cell, evidence chain interfaces |
| `TYPES:STORAGE` | `packages/protocol-types/src/storage.ts` | StorageAdapter interface, adapter implementations |
| `SHELL:TYPES` | `packages/shell/src/parser.ts` | ShellCommand infrastructure |
| `CONFIG:CORE` | `configs/extensions/core.json` | Object type definitions, phase FSM |
| `CFG:PROPERTYME` | `configs/extensions/propertyme/grammar.json` | Reference Extension Grammar (Phase 36A output) |
| `PLATFORM` | `docs/PLATFORM-ARCHITECTURE.md` | PropertyMe API context for reference implementation |

---

## Deliverables

### D36B.1 — Pipeline Stage Interfaces

**File**: `packages/extraction/src/stages.ts`

Define the five stage interfaces. Each stage is a pure function `Stage<I, O>(input: I, grammar: ExtensionGrammar, context: ExtractionContext): AsyncGenerator<O, ExtractionEvidence>`.

```typescript
// Input/output types for each stage
interface RawResponse {
  endpoint: string;
  statusCode: number;
  body: unknown;
  headers: Record<string, string>;
  timestamp: number;
  responseHash: string;  // SHA-256 of body for idempotency
}

interface IntermediateRecord {
  sourceEntityId: string;
  sourceFields: Record<string, unknown>;  // original API response fields
  mappedFields: Record<string, unknown>;  // after FieldMapping transforms
  sourceId: unknown;  // the ID field from source
}

interface ValidatedRecord extends IntermediateRecord {
  targetObjectType: string;
  taxonomy: { what: string; how: string; why: string; where?: string };
  phase: string;
  validationPassed: boolean;
  validationErrors: string[];
}

interface InferredRecord extends ValidatedRecord {
  inferredTaxonomy?: { confidence: number; suggestion: string };
  grammarPatchRequired?: boolean;
}

interface SemanticObject {
  cellId: string;
  objectType: string;
  payload: Record<string, unknown>;
  taxonomy: { what: string; how: string; why: string; where?: string };
  phase: string;
  evidenceChain: ExtractionEvidence[];
}

interface ExtractionContext {
  grammarId: string;
  grammarVersion: string;
  consumerId: string;
  storageAdapter: StorageAdapter;
  metering?: MeteringAdapter;  // for rate-limit tracking
}

// Stage interfaces
interface FetchStage {
  (entity: SourceEntity, credentials: Credentials, context: ExtractionContext):
    AsyncGenerator<RawResponse, void, void>;
}

interface ParseStage {
  (responses: AsyncIterable<RawResponse>, grammar: ExtensionGrammar, context: ExtractionContext):
    AsyncGenerator<IntermediateRecord, void, void>;
}

interface TypecheckStage {
  (records: AsyncIterable<IntermediateRecord>, grammar: ExtensionGrammar, context: ExtractionContext):
    AsyncGenerator<ValidatedRecord, void, void>;
}

interface InferStage {
  (records: AsyncIterable<ValidatedRecord>, grammar: ExtensionGrammar, context: ExtractionContext):
    AsyncGenerator<InferredRecord | GrammarPatch, void, void>;
}

interface CommitStage {
  (records: AsyncIterable<ValidatedRecord | InferredRecord>, grammar: ExtensionGrammar, context: ExtractionContext):
    AsyncGenerator<{ object: SemanticObject; isDuplicate: boolean }, void, void>;
}

// Evidence chain per stage
interface ExtractionEvidence {
  stage: 'fetch' | 'parse' | 'typecheck' | 'infer' | 'commit';
  timestamp: number;
  grammarVersion: string;
  stageData: FetchEvidence | ParseEvidence | TypecheckEvidence | InferenceEvidence | CommitEvidence;
}

interface FetchEvidence {
  endpoint: string;
  responseHash: string;
  statusCode: number;
  bytesReceived: number;
}

interface ParseEvidence {
  sourceEntityId: string;
  targetObjectType: string;
  fieldsMapped: number;
  transformsApplied: string[];
}

interface TypecheckEvidence {
  passed: boolean;
  errors: string[];
  taxonomyAssigned: string;
  phaseAssigned: string;
}

interface InferenceEvidence {
  inferenceApplied: boolean;
  suggestedTaxonomy?: string;
  confidenceScore?: number;
  grammarPatchProposed?: boolean;
}

interface CommitEvidence {
  cellId: string;
  storageAdapter: string;
  isNewObject: boolean;
  facetProvenance: { author: string; timestamp: number };
}
```

### D36B.2 — Fetch Adapters

**Directory**: `packages/extraction/src/fetch/`

Implement the `FetchAdapter` interface for multiple protocols. Each adapter is responsible for protocol-specific details: authentication, pagination, rate limiting, response parsing.

```typescript
// Adapter interface
interface FetchAdapter {
  fetch(entity: SourceEntity, credentials: Credentials): AsyncGenerator<RawResponse>;
}

// RestFetchAdapter — HTTP GET/POST with auth, pagination, rate limiting
class RestFetchAdapter implements FetchAdapter {
  async *fetch(entity: SourceEntity, credentials: Credentials): AsyncGenerator<RawResponse> {
    // GET or POST to entity.endpoint.list
    // Apply credentials from grammar.source.auth
    // Handle pagination (cursor, offset, page-number, link-header)
    // Yield RawResponse for each page
    // Respect rate limits from grammar.source.rateLimits
  }
}

// GraphQLFetchAdapter — construct query from grammar entity definitions
class GraphQLFetchAdapter implements FetchAdapter {
  async *fetch(entity: SourceEntity, credentials: Credentials): AsyncGenerator<RawResponse> {
    // Build GraphQL query from entity.fields and entity.relationships
    // POST to entity.endpoint.list as graphql query
    // Handle pagination via cursor/offset
    // Yield RawResponse per page
  }
}

// FileFetchAdapter — read from filesystem (CSV, JSON, XML, Parquet)
class FileFetchAdapter implements FetchAdapter {
  async *fetch(entity: SourceEntity, credentials: Credentials): AsyncGenerator<RawResponse> {
    // Read file at path in credentials (e.g., "/tmp/properties.csv")
    // Parse based on entity definition (CSV headers, JSON structure, XML path)
    // Yield RawResponse per batch of rows
  }
}

// StubFetchAdapter — testing only, returns canned responses
class StubFetchAdapter implements FetchAdapter {
  async *fetch(entity: SourceEntity, credentials: Credentials): AsyncGenerator<RawResponse> {
    // Yield pre-canned RawResponse objects for unit testing
  }
}
```

### D36B.3 — Parse Engine

**File**: `packages/extraction/src/parse.ts`

Consume `RawResponse[]` from the fetch stage, apply `FieldMapping` transforms from the grammar, resolve nested fields (dot-notation), handle relationships, produce `IntermediateRecord[]`.

**Transforms supported**:
- `concat`: Join source fields with delimiter
- `split`: Split source field on delimiter, take indexed value
- `lookup`: Map source value via a lookup table
- `template`: Mustache-style template substitution
- `lowercase` / `uppercase` / `trim`: String normalization
- `map_enum`: Map source enum value to target enum value
- `compute`: Safe expression evaluation (e.g., `source.bedrooms + source.bathrooms`)

**Nested fields**: Resolve dot-notation paths (e.g., `"property.address.street"`) from API response structure.

**Relationships**: If entity has `relationships`, resolve foreign keys and fetch related entities (or defer if configured).

```typescript
async function parseResponses(
  responses: AsyncIterable<RawResponse>,
  grammar: ExtensionGrammar,
  entity: SourceEntity,
  context: ExtractionContext
): AsyncGenerator<IntermediateRecord> {
  for await (const response of responses) {
    const records = extractRecordsFromResponse(response, entity);
    for (const record of records) {
      const mapping = findEntityMapping(grammar, entity.entityId);
      const intermediate: IntermediateRecord = {
        sourceEntityId: entity.entityId,
        sourceFields: record,
        mappedFields: applyFieldMappings(record, mapping.fieldMappings),
        sourceId: record[entity.responseShape.idField],
      };
      yield intermediate;
    }
  }
}
```

### D36B.4 — Typecheck Engine

**File**: `packages/extraction/src/typecheck.ts`

Consume `IntermediateRecord[]`, validate against the target object type's schema from the grammar:

1. All required fields present
2. Field types match target schema
3. Taxonomy coordinates are syntactically valid (dot-separated segments)
4. Linearity constraints satisfied (if LINEAR, one active state per owner)
5. Phase assignment: map source status → commerce phase via `phaseMapping`

```typescript
async function typecheckRecords(
  records: AsyncIterable<IntermediateRecord>,
  grammar: ExtensionGrammar,
  context: ExtractionContext
): AsyncGenerator<ValidatedRecord> {
  for await (const record of records) {
    const mapping = findEntityMapping(grammar, record.sourceEntityId);
    const objectType = findObjectType(grammar, mapping.targetObjectType);
    
    const errors: string[] = [];
    
    // Check required fields
    for (const [fieldName, fieldDef] of Object.entries(objectType.payloadSchema)) {
      if (fieldDef.type === 'required' && !(fieldName in record.mappedFields)) {
        errors.push(`Required field ${fieldName} missing`);
      }
    }
    
    // Validate taxonomy coordinates
    const taxonomy = mapping.taxonomy;
    if (!isValidTaxonomyPath(taxonomy.what)) errors.push(`Invalid what: ${taxonomy.what}`);
    if (!isValidTaxonomyPath(taxonomy.how)) errors.push(`Invalid how: ${taxonomy.how}`);
    if (!isValidTaxonomyPath(taxonomy.why)) errors.push(`Invalid why: ${taxonomy.why}`);
    
    // Assign phase
    const sourceStatus = record.sourceFields[mapping.phaseMapping?.keyField];
    const phase = mapping.phaseMapping?.[sourceStatus] || mapping.initialPhase;
    
    yield {
      ...record,
      targetObjectType: mapping.targetObjectType,
      taxonomy,
      phase,
      validationPassed: errors.length === 0,
      validationErrors: errors,
    };
  }
}
```

### D36B.5 — Infer Engine

**File**: `packages/extraction/src/infer.ts`

Consume `ValidatedRecord[]`, optionally enrich with inferred taxonomy using a lightweight inference agent. If the infer stage discovers fields not covered by the grammar, propose a `GrammarPatch` that extends the grammar.

```typescript
async function inferRecords(
  records: AsyncIterable<ValidatedRecord>,
  grammar: ExtensionGrammar,
  context: ExtractionContext,
  inferenceClient?: InferenceClient  // optional LLM for taxonomy suggestion
): AsyncGenerator<InferredRecord | GrammarPatch> {
  const discoveredFields = new Set<string>();
  
  for await (const record of records) {
    let inferred: Partial<InferredRecord> = { ...record };
    
    // Detect unmapped fields in source
    const mapping = findEntityMapping(grammar, record.sourceEntityId);
    for (const sourceField of Object.keys(record.sourceFields)) {
      if (!mapping.fieldMappings.some(fm => fm.sourceField === sourceField)) {
        discoveredFields.add(sourceField);
      }
    }
    
    // Optional: use inference client to suggest taxonomy
    if (inferenceClient && !record.taxonomy.what.includes('unknown')) {
      const suggestion = await inferenceClient.suggestTaxonomy(record);
      if (suggestion) {
        inferred.inferredTaxonomy = {
          confidence: suggestion.confidence,
          suggestion: suggestion.path,
        };
      }
    }
    
    yield inferred as InferredRecord;
  }
  
  // After processing all records, yield grammar patches if new fields discovered
  if (discoveredFields.size > 0) {
    yield {
      type: 'grammar-patch',
      targetGrammar: grammar.grammarId,
      proposedFieldMappings: Array.from(discoveredFields).map(field => ({
        sourceField: field,
        targetField: camelCase(field),
        required: false,
      })),
      confidence: 'low',
    } as GrammarPatch;
  }
}
```

### D36B.6 — Commit Engine

**File**: `packages/extraction/src/commit.ts`

Consume `ValidatedRecord[]` or `InferredRecord[]`, create semantic objects via `LoomStore.createObjectFromType()`, attach full evidence chain, handle idempotency.

**Idempotency**: Before creating a new object, check if an object for the same source ID + grammar version already exists. If it does, create a patch instead of a new object. This ensures that running extraction twice produces the same state.

```typescript
async function commitRecords(
  records: AsyncIterable<ValidatedRecord | InferredRecord>,
  grammar: ExtensionGrammar,
  context: ExtractionContext
): AsyncGenerator<{ object: SemanticObject; isDuplicate: boolean }> {
  const seenSourceIds = new Map<string, string>();  // sourceId -> cellId for idempotency
  
  for await (const record of records) {
    const sourceKey = `${grammar.grammarId}:${record.sourceId}`;
    
    // Check for existing object
    let cellId: string;
    let isDuplicate = false;
    
    if (seenSourceIds.has(sourceKey)) {
      // Duplicate in this batch — create patch
      cellId = seenSourceIds.get(sourceKey)!;
      isDuplicate = true;
    } else {
      // Check store for existing object (idempotency across runs)
      const existing = await context.storageAdapter.queryBySourceId(sourceKey, grammar.grammarVersion);
      if (existing) {
        cellId = existing.cellId;
        isDuplicate = true;
      } else {
        // Create new object
        const cell = await context.storageAdapter.createCell({
          objectType: record.targetObjectType,
          payload: record.mappedFields,
          taxonomy: record.taxonomy,
          phase: record.phase,
          linearity: record.taxonomy.linearity,
          sourceId: sourceKey,
          grammarId: grammar.grammarId,
          grammarVersion: grammar.grammarVersion,
        });
        cellId = cell.cellId;
        seenSourceIds.set(sourceKey, cellId);
      }
    }
    
    // Build evidence chain
    const evidenceChain: ExtractionEvidence[] = [
      { stage: 'fetch', timestamp: Date.now(), grammarVersion: grammar.grammarVersion, stageData: {} },
      { stage: 'parse', timestamp: Date.now(), grammarVersion: grammar.grammarVersion, stageData: {} },
      { stage: 'typecheck', timestamp: Date.now(), grammarVersion: grammar.grammarVersion, stageData: { passed: record.validationPassed } },
      ...(record.inferredTaxonomy ? [{ stage: 'infer', timestamp: Date.now(), grammarVersion: grammar.grammarVersion, stageData: { inferenceApplied: true } }] : []),
      { stage: 'commit', timestamp: Date.now(), grammarVersion: grammar.grammarVersion, stageData: { cellId, isNewObject: !isDuplicate } },
    ];
    
    // Attach evidence chain as patches
    await context.storageAdapter.attachEvidence(cellId, evidenceChain);
    
    yield {
      object: {
        cellId,
        objectType: record.targetObjectType,
        payload: record.mappedFields,
        taxonomy: record.taxonomy,
        phase: record.phase,
        evidenceChain,
      },
      isDuplicate,
    };
  }
}
```

### D36B.7 — Pipeline Orchestrator

**File**: `packages/extraction/src/pipeline.ts`

Orchestrate the five stages. Take a grammar and binding, instantiate fetch adapters, run stages sequentially, collect evidence, handle errors per-record (one failure doesn't abort the batch), emit progress events.

```typescript
class ExtractionPipeline {
  constructor(private store: LoomStore, private metering?: MeteringAdapter) {}
  
  async extract(
    grammar: ExtensionGrammar,
    binding: ConsumerBinding,
    options?: ExtractionOptions
  ): Promise<ExtractionResult> {
    const context: ExtractionContext = {
      grammarId: grammar.grammarId,
      grammarVersion: grammar.grammarVersion,
      consumerId: binding.consumerId,
      storageAdapter: this.store.adapter,
      metering: this.metering,
    };
    
    const results: ExtractionResult = {
      grammarId: grammar.grammarId,
      grammarVersion: grammar.grammarVersion,
      totalRecords: 0,
      createdObjects: 0,
      updatedObjects: 0,
      errors: [],
      startTime: Date.now(),
      endTime: 0,
    };
    
    try {
      // Choose fetch adapter based on grammar.source.protocol
      const fetchAdapter = selectFetchAdapter(grammar.source.protocol);
      
      // Run stages in sequence with async generators
      let processed = 0;
      for await (const entity of grammar.source.entities) {
        if (options?.entityFilter && entity.entityId !== options.entityFilter) continue;
        
        try {
          const rawResponses = fetchAdapter.fetch(entity, binding.credentials);
          const intermediateRecords = parseResponses(rawResponses, grammar, entity, context);
          const validatedRecords = typecheckRecords(intermediateRecords, grammar, context);
          const inferredRecords = inferRecords(validatedRecords, grammar, context);
          const committedObjects = commitRecords(inferredRecords, grammar, context);
          
          for await (const { object, isDuplicate } of committedObjects) {
            results.totalRecords++;
            if (isDuplicate) results.updatedObjects++;
            else results.createdObjects++;
            processed++;
            
            this.emitProgress({ processed, entity: entity.entityId });
          }
        } catch (err) {
          results.errors.push({
            entity: entity.entityId,
            error: err.message,
            timestamp: Date.now(),
          });
        }
      }
      
      results.endTime = Date.now();
      return results;
    } catch (err) {
      results.endTime = Date.now();
      results.errors.push({ error: err.message, timestamp: Date.now() });
      return results;
    }
  }
  
  private emitProgress(event: ProgressEvent) {
    // Emit to UI subscribers
  }
}

interface ExtractionOptions {
  entityFilter?: string;  // Extract only this entity
  dryRun?: boolean;       // Parse + typecheck but don't commit
  since?: Date;           // Incremental extraction (API-dependent)
}

interface ExtractionResult {
  grammarId: string;
  grammarVersion: string;
  totalRecords: number;
  createdObjects: number;
  updatedObjects: number;
  errors: Array<{ entity?: string; error: string; timestamp: number }>;
  startTime: number;
  endTime: number;
}
```

### D36B.8 — Shell Command: `semantos extract`

**File**: Update `packages/shell/src/commands/extract.ts`

Implement the shell command interface for extraction:

```bash
semantos extract <grammar-id>                    # Run extraction for installed grammar
semantos extract <grammar-id> --entity <name>    # Extract specific entity only
semantos extract <grammar-id> --dry-run          # Parse + typecheck but don't commit
semantos extract <grammar-id> --since <date>     # Incremental extraction
semantos extract status                          # Show last extraction status per grammar
```

**Implementation**:
- Load grammar from registry
- Load consumer binding for the grammar
- Instantiate ExtractionPipeline
- Call `extract(grammar, binding, options)`
- Stream progress to REPL
- Display summary: created, updated, errors

---

## Gate Tests

**File**: `packages/__tests__/phase36b-extraction-pipeline.test.ts`

### Stage Tests (T1–T15)

```typescript
describe("Extraction Pipeline Stages", () => {
  // T1: FetchStage with RestFetchAdapter consumes source config, yields RawResponse[]
  // T2: RestFetchAdapter respects rate limits from grammar
  // T3: RestFetchAdapter handles pagination (cursor, offset, page-number)
  // T4: GraphQLFetchAdapter constructs queries from entity definitions
  // T5: FileFetchAdapter reads CSV, JSON, XML correctly
  // T6: StubFetchAdapter yields canned responses for testing
  
  // T7: ParseStage applies FieldMapping transforms (concat, split, lookup, etc.)
  // T8: ParseStage resolves nested fields (dot-notation)
  // T9: ParseStage handles relationships (has_many, belongs_to)
  // T10: ParseStage produces IntermediateRecord with source + mapped fields
  
  // T11: TypecheckStage validates required fields
  // T12: TypecheckStage validates taxonomy coordinates
  // T13: TypecheckStage maps phase via phaseMapping
  // T14: TypecheckStage produces ValidatedRecord
  // T15: TypecheckStage collects validation errors without aborting batch
});
```

### Pipeline Tests (T16–T22)

```typescript
describe("ExtractionPipeline orchestrator", () => {
  // T16: ExtractionPipeline.extract() runs all five stages end-to-end
  // T17: Pipeline handles errors per-record (one error doesn't abort batch)
  // T18: Pipeline respects --dry-run flag (parse + typecheck, no commit)
  // T19: Pipeline respects --entity filter
  // T20: Idempotency: running extraction twice produces same result
  // T21: Pipeline returns ExtractionResult with counts and error list
  // T22: CLI `semantos extract <grammar-id>` invokes pipeline
});
```

### Adapter Tests (T23–T26)

```typescript
describe("Fetch adapters", () => {
  // T23: selectFetchAdapter() returns correct adapter for protocol
  // T24: All adapters implement FetchAdapter interface
  // T25: RestFetchAdapter injects auth headers from credentials
  // T26: StubFetchAdapter is deterministic (same seed = same output)
});
```

---

## Source Files Table

| Deliverable | File | LOC | Status |
|-------------|------|-----|--------|
| D36B.1 | `packages/extraction/src/stages.ts` | ~150 | Create |
| D36B.2 | `packages/extraction/src/fetch/adapters.ts` | ~300 | Create |
| D36B.2 | `packages/extraction/src/fetch/rest.ts` | ~150 | Create |
| D36B.2 | `packages/extraction/src/fetch/graphql.ts` | ~120 | Create |
| D36B.2 | `packages/extraction/src/fetch/file.ts` | ~100 | Create |
| D36B.3 | `packages/extraction/src/parse.ts` | ~200 | Create |
| D36B.4 | `packages/extraction/src/typecheck.ts` | ~180 | Create |
| D36B.5 | `packages/extraction/src/infer.ts` | ~150 | Create |
| D36B.6 | `packages/extraction/src/commit.ts` | ~200 | Create |
| D36B.7 | `packages/extraction/src/pipeline.ts` | ~220 | Create |
| D36B.8 | `packages/shell/src/commands/extract.ts` | ~180 | Create |
| Tests | `packages/__tests__/phase36b-extraction-pipeline.test.ts` | ~600 | Create |

---

## Completion Criteria

- [ ] All stage interfaces defined in `packages/extraction/src/stages.ts`
- [ ] FetchAdapter implementations for REST, GraphQL, file, stub protocols
- [ ] ParseStage applies FieldMapping transforms (concat, split, lookup, template, enum_map, compute)
- [ ] TypecheckStage validates schema, taxonomy, phase, linearity
- [ ] InferStage optionally proposes grammar patches for discovered fields
- [ ] CommitStage creates semantic objects via LoomStore with idempotency
- [ ] ExtractionPipeline orchestrator runs all five stages sequentially
- [ ] Evidence chains collected and attached to every created object
- [ ] Shell command `semantos extract` operational
- [ ] Tests T1–T26 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing tests still pass
- [ ] All commits follow `phase-36b/D36B.N:` naming convention
- [ ] Branch is `phase-36b-semantic-extraction-pipeline`

---

## What NOT to Do

- **Don't put protocol-specific logic in the pipeline.** REST authentication, GraphQL query construction, CSV parsing — these belong in fetch adapters. The pipeline reads generic `RawResponse[]` and doesn't care how they were obtained. If you find yourself writing `if (protocol === 'rest')`, you've failed.

- **Don't skip evidence chains for performance.** The evidence chain is the value proposition. Every extraction must produce a full chain: source hash, parse mapping, typecheck result, inference record, commit cell ID. No "fast path" that omits provenance.

- **Don't make stages stateful.** Each stage is a pure function: input + grammar → output + evidence. No global caches, no mutable registries, no side effects. This makes the pipeline composable and testable.

- **Don't use synchronous APIs in the pipeline.** Use `AsyncGenerator` for streaming. This allows consuming large datasets without loading them into memory. The orchestrator collects results for reporting; internal stages stream.

- **Don't bypass LoomStore.** All semantic object creation goes through `LoomStore.createObjectFromType()` with full evidence chains. No direct cell creation, no shortcuts.

- **Don't hardcode any API URLs or credentials.** Everything comes from the grammar (URLs, auth type, pagination strategy) and the binding (actual credentials, field overrides). The pipeline is configuration-driven.

- **Don't implement idempotency in the commit stage only.** Design the entire pipeline to handle re-runs gracefully. Use source ID + grammar version as the deduplication key. If an object exists for the same source, produce a patch, not a new object.

---

## Next Phase

Phase 36C implements the schema inference agent that reads unfamiliar API responses, diffs against known grammars, and proposes new Extension Grammar JSON as AFFINE draft objects. The agent uses the extraction pipeline (Phase 36B) to validate proposed grammars before suggesting them.
