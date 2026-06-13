---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36B-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.720393+00:00
---

# Phase 36B Execution Prompt — Semantic Extraction Pipeline

> Paste this prompt into a fresh session to execute Phase 36B.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and shell for Semantos nodes (npm: `@semantos/core`). Phase 36A defined the Extension Grammar JSON schema that every connector implements. This phase implements the **semantic extraction pipeline** — the runtime that interprets an Extension Grammar and executes the five-stage flow: Fetch → Parse → Typecheck → Infer → Commit.

Each stage is a pure function that takes input + grammar and produces output + evidence. The pipeline is storage-adapter-agnostic and protocol-agnostic — the grammar declares everything protocol-specific (REST, GraphQL, file-based). The pipeline does not care. Fetch adapters handle protocols; the pipeline normalizes and processes.

Your task is Phase 36B: build the five-stage extraction pipeline with evidence chains, fetch adapters for multiple protocols, and a shell command to run extraction.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations and architecture you are building on top of.

**Read first** (the PRDs and context):
- `docs/prd/PHASE-36B-SEMANTIC-EXTRACTION-PIPELINE.md` — Phase 36B spec with all deliverables D36B.1–D36B.8, gate tests, completion criteria, what-not-to-do
- `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` — Master context: why the extension ecosystem matters, cross-cutting concerns (grammar as semantic object, evidence chains, hierarchical governance), architecture diagram
- `docs/prd/PHASE-36A-EXTENSION-GRAMMAR-SCHEMA.md` — The Extension Grammar JSON schema (ExtensionGrammar, SourceEntity, FieldMapping, ObjectTypeDeclaration, CapabilityRequirement)
- `docs/prd/PHASE-18-METERING-CONTROL-PLANE.md` — First 50 lines for metering context (rate limits, capability validation)
- `docs/PLATFORM-ARCHITECTURE.md` — PropertyMe API context for reference implementation

**Read second** (the primary implementation targets — these are what you build the pipeline on top of):
- `packages/loom/src/services/LoomStore.ts` — The store interface: `createObjectFromType()`, `attachEvidence()`, `queryBySourceId()`. This is where semantic objects are created.
- `packages/protocol-types/src/index.ts` — SemanticObject, Cell, evidence chain interfaces, linearity and taxonomy types
- `packages/protocol-types/src/storage.ts` — StorageAdapter interface (the abstraction the pipeline must work with)
- `packages/protocol-types/src/extension-grammar.ts` — ExtensionGrammar types from Phase 36A (SourceEntity, FieldMapping, EntityMapping, ObjectTypeDeclaration)
- `packages/protocol-types/src/extension-grammar-validator.ts` — validateExtensionGrammar() (you will call this to validate grammars before extracting)

**Read third** (shell and config context):
- `packages/shell/src/repl.ts` — REPL entry point, how commands are registered
- `packages/shell/src/router.ts` — Command router, how commands are dispatched
- `packages/shell/src/parser.ts` — Shell parser and command infrastructure
- `configs/extensions/core.json` — Core extension config with object types and phase FSM
- `configs/extensions/propertyme/grammar.json` — PropertyMe stub grammar from Phase 36A (reference for what a real grammar looks like)

**Read fourth** (test infrastructure):
- `packages/__tests__/intent-taxonomy.test.ts` — Test structure and mocking patterns
- `packages/__tests__/phase26f-extension-loading.test.ts` — Extension loading test patterns (for reference)

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. PIPELINE STAGES ARE PURE FUNCTIONS

Every stage takes input + grammar and produces output + evidence. No global state, no mutable caches, no side effects outside the specified outputs. This makes stages testable and composable.

**Correct**: `async *parseResponses(responses: AsyncIterable<RawResponse>, grammar: ExtensionGrammar): AsyncGenerator<IntermediateRecord>`

**Wrong**: Global `let currentRecordBatch = []` that accumulates results

### 2. EVIDENCE CHAINS ARE MANDATORY

Every extraction must produce a full evidence chain:
- `FetchEvidence`: sourceHash, endpoint, timestamp, responseSize
- `ParseEvidence`: grammarVersion, fieldMappingApplied, sourceFieldsResolved
- `TypecheckEvidence`: validationResult, taxonomyAssigned, phaseAssigned
- `InferenceEvidence`: inferredTaxonomy, confidenceScore (optional)
- `CommitEvidence`: cellId, storageAdapter, facetProvenance

No "fast path" that skips evidence. No object creation without an evidence chain. Evidence is the value proposition.

### 3. NO PROTOCOL LOGIC IN THE PIPELINE

The pipeline is generic. REST auth, GraphQL query construction, CSV parsing — these belong in fetch adapters. The pipeline reads `RawResponse[]` and doesn't care how they were fetched.

**Correct**: `RestFetchAdapter` handles HTTP GET/POST, auth headers, pagination. Pipeline consumes the output.

**Wrong**: `if (protocol === 'rest') { fetch(...) }` in the pipeline code.

### 4. USE ASYNCGENERATOR FOR STREAMING

Don't load the entire dataset into memory. Use `AsyncGenerator` for streaming:
- FetchStage yields `RawResponse` one at a time
- ParseStage yields `IntermediateRecord` one at a time
- etc.

This allows the pipeline to process datasets larger than RAM. The orchestrator collects for reporting; internal stages stream.

**Correct**: `async *fetchResponses(): AsyncGenerator<RawResponse>`

**Wrong**: `async fetchAllResponses(): Promise<RawResponse[]>` that loads everything into memory

### 5. IDEMPOTENCY BY DEFAULT

If you run extraction twice for the same source + grammar version, you get one semantic object, not two. Use source ID + grammar version as the deduplication key. The commit stage checks `storageAdapter.queryBySourceId()` and creates a patch instead of a new object if it exists.

**Correct**: Before creating a new object, check if it already exists. If it does, patch it.

**Wrong**: Creating a new object every time, leaving cleanup to the user.

### 6. WRAP PROTOCOL DETAILS IN ADAPTERS

Every fetch protocol (REST, GraphQL, file, database, event-stream) is a separate adapter implementing `FetchAdapter`. The orchestrator selects the adapter based on `grammar.source.protocol` and calls its `fetch()` method. The pipeline never knows the protocol.

**Correct**: `selectFetchAdapter(grammar.source.protocol)` returns the right adapter

**Wrong**: Pipeline code that checks protocol and has different logic for each

### 7. WORKBENCHSTORE IS THE SOURCE OF TRUTH

All semantic object creation goes through `LoomStore.createObjectFromType()`. No direct cell creation, no shortcuts. The store handles linearity validation, capability checks, and storage routing.

**Correct**: `await context.storageAdapter.createCell({ objectType, payload, taxonomy, ... })`

**Wrong**: Direct cell creation bypassing the store's validation

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /path/to/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files.

### 0.3 Verify prerequisites are complete

Phase 36A (Extension Grammar schema) must be complete. Check:

```bash
ls packages/protocol-types/src/extension-grammar.ts
ls packages/protocol-types/src/extension-grammar-validator.ts
ls configs/extensions/propertyme/grammar.json
```

All files must exist.

### 0.4 Create Phase 36B branch

```bash
git checkout -b phase-36b-semantic-extraction-pipeline
```

---

## Step 1: Stage Interfaces + Types (D36B.1)

### 1.1 Create extraction package

```bash
mkdir -p packages/extraction/src/{fetch,utils}
```

### 1.2 Define stage interfaces

**File**: `packages/extraction/src/stages.ts`

Implement all interfaces from the PRD:
- `RawResponse`, `IntermediateRecord`, `ValidatedRecord`, `InferredRecord`, `SemanticObject`
- `ExtractionContext`
- `FetchStage`, `ParseStage`, `TypecheckStage`, `InferStage`, `CommitStage`
- Evidence chain interfaces: `ExtractionEvidence`, `FetchEvidence`, `ParseEvidence`, `TypecheckEvidence`, `InferenceEvidence`, `CommitEvidence`

All types must be exportable from the protocol-types barrel.

### 1.3 Export from protocol-types barrel

Update `packages/protocol-types/src/index.ts`:

```typescript
export * from '../extraction/stages';
```

### 1.4 Verify

```bash
bun run check 2>&1 | head -20
```

Commit: `phase-36b/D36B.1: define extraction pipeline stage interfaces and types`

---

## Step 2: Fetch Adapters (D36B.2)

### 2.1 Create FetchAdapter interface

**File**: `packages/extraction/src/fetch/adapter.ts`

```typescript
interface FetchAdapter {
  fetch(entity: SourceEntity, credentials: Credentials): AsyncGenerator<RawResponse>;
}

export function selectFetchAdapter(protocol: string): FetchAdapter {
  switch (protocol) {
    case 'rest': return new RestFetchAdapter();
    case 'graphql': return new GraphQLFetchAdapter();
    case 'file': return new FileFetchAdapter();
    case 'stub': return new StubFetchAdapter();
    default: throw new Error(`Unknown protocol: ${protocol}`);
  }
}
```

### 2.2 Implement RestFetchAdapter

**File**: `packages/extraction/src/fetch/rest.ts`

- HTTP GET/POST to `entity.endpoint.list`
- Apply auth from `grammar.source.auth` (Bearer token, API key, OAuth2, basic auth)
- Handle pagination: cursor, offset, page-number, link-header
- Respect rate limits from `grammar.source.rateLimits`
- Yield `RawResponse` for each page/batch
- Compute response hash for idempotency

### 2.3 Implement GraphQLFetchAdapter

**File**: `packages/extraction/src/fetch/graphql.ts`

- Construct GraphQL query from `entity.fields` and `entity.relationships`
- POST to `entity.endpoint.list` with the query
- Handle pagination via cursor/offset (GraphQL-specific)
- Yield `RawResponse` for each page

### 2.4 Implement FileFetchAdapter

**File**: `packages/extraction/src/fetch/file.ts`

- Read file at path from credentials (e.g., `"/tmp/properties.csv"`)
- Parse based on file extension and entity definition:
  - CSV: parse headers, yield rows as objects
  - JSON: parse, extract array at `entity.responseShape.dataPath`, yield objects
  - XML: parse, extract elements, yield objects
  - Parquet: use parquet library, yield batches
- Yield `RawResponse` for each batch of rows

### 2.5 Implement StubFetchAdapter

**File**: `packages/extraction/src/fetch/stub.ts`

- For testing: return canned responses from a seed
- Deterministic: same seed = same output
- Yield pre-canned `RawResponse` objects

### 2.6 Update barrel

`packages/extraction/src/fetch/index.ts`:

```typescript
export * from './adapter';
export * from './rest';
export * from './graphql';
export * from './file';
export * from './stub';
```

### 2.7 Verify

```bash
bun run check 2>&1 | grep -i "fetch\|adapter" | head -10
```

Commit: `phase-36b/D36B.2: implement fetch adapters (REST, GraphQL, file, stub)`

---

## Step 3: Parse Engine (D36B.3)

### 3.1 Create parse module

**File**: `packages/extraction/src/parse.ts`

Implement `parseResponses()`:

```typescript
async function parseResponses(
  responses: AsyncIterable<RawResponse>,
  grammar: ExtensionGrammar,
  entity: SourceEntity,
  context: ExtractionContext
): AsyncGenerator<IntermediateRecord>
```

**Responsibilities**:
- Extract records from API response using `entity.responseShape.dataPath`
- Apply `FieldMapping` transforms from the grammar
- Resolve nested fields (dot-notation: `"property.address.street"`)
- Handle relationships: resolve foreign keys, fetch related entities (or defer)
- Transform field values:
  - `concat`: join with delimiter
  - `split`: split on delimiter, take indexed value
  - `lookup`: map via lookup table
  - `template`: mustache substitution
  - `lowercase` / `uppercase` / `trim`: normalization
  - `map_enum`: enum mapping
  - `compute`: safe expression evaluation
- Yield `IntermediateRecord` with both source and mapped fields (for evidence)

**Helpers**:
- `applyFieldMapping(sourceValue, mapping, sourceRecord): unknown` — apply one field mapping
- `applyTransform(value, transform): unknown` — apply one transform
- `resolveNestedField(record, dotPath): unknown` — resolve dot-notation path
- `extractRecordsFromResponse(response, entity): object[]` — extract records from API response using JSONPath

### 3.2 Verify

```bash
bun run check 2>&1 | grep parse
```

Commit: `phase-36b/D36B.3: implement parse engine with field mappings and transforms`

---

## Step 4: Typecheck Engine (D36B.4)

### 4.1 Create typecheck module

**File**: `packages/extraction/src/typecheck.ts`

Implement `typecheckRecords()`:

```typescript
async function typecheckRecords(
  records: AsyncIterable<IntermediateRecord>,
  grammar: ExtensionGrammar,
  context: ExtractionContext
): AsyncGenerator<ValidatedRecord>
```

**Validation rules**:
1. All required fields from `grammar.objectTypes[].payloadSchema` are present
2. Field types match schema
3. Taxonomy coordinates are syntactically valid (dot-separated segments)
4. Linearity constraints: if LINEAR, check one active state per owner
5. Phase mapping: map source status → commerce phase via `phaseMapping`

**Error handling**: Collect validation errors, but yield the record with `validationPassed: false`. Do not abort the batch on one error.

**Helpers**:
- `findObjectType(grammar, typePath): ObjectTypeDeclaration`
- `findEntityMapping(grammar, entityId): EntityMapping`
- `isValidTaxonomyPath(path): boolean` — check dot-separated syntax
- `mapPhase(sourceStatus, mapping): string` — map source status to commerce phase

### 4.2 Verify

```bash
bun run check 2>&1 | grep typecheck
```

Commit: `phase-36b/D36B.4: implement typecheck engine with schema and taxonomy validation`

---

## Step 5: Infer Engine (D36B.5)

### 5.1 Create infer module

**File**: `packages/extraction/src/infer.ts`

Implement `inferRecords()`:

```typescript
async function inferRecords(
  records: AsyncIterable<ValidatedRecord>,
  grammar: ExtensionGrammar,
  context: ExtractionContext,
  inferenceClient?: InferenceClient
): AsyncGenerator<InferredRecord | GrammarPatch>
```

**Responsibilities**:
- Track unmapped source fields (fields in API response not covered by grammar)
- Optional: use inference client to suggest taxonomy for records (LLM-based)
- At the end, if new fields discovered, yield a `GrammarPatch` proposing new field mappings

**Inference client** (optional, can be a stub for this phase):
- `suggestTaxonomy(record): Promise<{ path: string; confidence: number }>`

**Helpers**:
- `findUnmappedFields(record, mapping): string[]` — detect unmapped source fields
- `proposedFieldMapping(sourceField): FieldMapping` — suggest a field mapping

### 5.2 Verify

```bash
bun run check 2>&1 | grep infer
```

Commit: `phase-36b/D36B.5: implement infer engine with taxonomy suggestion and grammar patching`

---

## Step 6: Commit Engine (D36B.6)

### 6.1 Create commit module

**File**: `packages/extraction/src/commit.ts`

Implement `commitRecords()`:

```typescript
async function commitRecords(
  records: AsyncIterable<ValidatedRecord | InferredRecord>,
  grammar: ExtensionGrammar,
  context: ExtractionContext
): AsyncGenerator<{ object: SemanticObject; isDuplicate: boolean }>
```

**Responsibilities**:
- For each record, build a source key: `"${grammar.grammarId}:${record.sourceId}"`
- Check if object already exists for this source key + grammar version (idempotency)
- If exists: patch it, set `isDuplicate: true`
- If not: create new object via `context.storageAdapter.createCell()`
- Build full evidence chain from all previous stages
- Attach evidence chain to the object via `context.storageAdapter.attachEvidence()`
- Yield `{ object, isDuplicate }`

**Idempotency**:
- Maintain a `Map<sourceKey, cellId>` for this batch (detect duplicates within batch)
- Call `context.storageAdapter.queryBySourceId(sourceKey, grammarVersion)` to check store
- If found in store, use existing cellId, patch it, set `isDuplicate: true`
- If not found, create new object

**Helpers**:
- `buildSourceKey(grammarId, sourceId): string`
- `buildEvidenceChain(record, grammarVersion): ExtractionEvidence[]` — collect evidence from all stages
- `createSemanticObject(cell, record, evidenceChain): SemanticObject`

### 6.2 Verify

```bash
bun run check 2>&1 | grep commit
```

Commit: `phase-36b/D36B.6: implement commit engine with idempotency and evidence chains`

---

## Step 7: Pipeline Orchestrator (D36B.7)

### 7.1 Create pipeline module

**File**: `packages/extraction/src/pipeline.ts`

Implement `ExtractionPipeline` class:

```typescript
class ExtractionPipeline {
  constructor(private store: LoomStore, private metering?: MeteringAdapter) {}
  
  async extract(
    grammar: ExtensionGrammar,
    binding: ConsumerBinding,
    options?: ExtractionOptions
  ): Promise<ExtractionResult>
}
```

**Responsibilities**:
1. Validate grammar with `validateExtensionGrammar()`
2. Create `ExtractionContext`
3. For each entity in grammar:
   - Optionally filter by `options.entityFilter`
   - Select fetch adapter: `selectFetchAdapter(grammar.source.protocol)`
   - Run stages sequentially:
     ```
     fetchResponses → parseResponses → typecheckRecords → inferRecords → commitRecords
     ```
   - Collect results: created, updated, error counts
   - Emit progress events
4. Handle errors per-entity (don't abort on one error)
5. Return `ExtractionResult`

**Options**:
- `entityFilter?: string` — extract only this entity
- `dryRun?: boolean` — parse + typecheck, don't commit
- `since?: Date` — incremental extraction

**Result**:
```typescript
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

**Helpers**:
- `selectFetchAdapter(protocol): FetchAdapter`
- `emitProgress(event): void` — for UI subscribers

### 7.2 Verify

```bash
bun run check 2>&1 | grep pipeline
```

Commit: `phase-36b/D36B.7: implement extraction pipeline orchestrator`

---

## Step 8: Shell Command (D36B.8)

### 8.1 Create extract command

**File**: `packages/shell/src/commands/extract.ts`

Implement shell command:

```bash
semantos extract <grammar-id>                    # Run extraction for installed grammar
semantos extract <grammar-id> --entity <name>    # Extract specific entity only
semantos extract <grammar-id> --dry-run          # Parse + typecheck but don't commit
semantos extract <grammar-id> --since <date>     # Incremental extraction
semantos extract status                          # Show last extraction status per grammar
```

**Implementation**:
- Load grammar from registry
- Load consumer binding for the grammar (get credentials)
- Instantiate `ExtractionPipeline`
- Call `extract(grammar, binding, options)`
- Stream progress to REPL with updates
- Display summary: created, updated, errors

### 8.2 Register command

Update `packages/shell/src/router.ts` to register the `extract` command.

### 8.3 Verify

```bash
bun run check 2>&1 | grep -i extract
semantos extract --help
```

Commit: `phase-36b/D36B.8: implement semantos extract shell command`

---

## Step 9: Gate Tests (D36B Tests)

### 9.1 Create test file

**File**: `packages/__tests__/phase36b-extraction-pipeline.test.ts`

Implement all tests T1–T26 from the PRD:

**Stage tests (T1–T15)**:
- FetchStage with each adapter (REST, GraphQL, file, stub)
- Rate limit handling
- Pagination
- ParseStage with transforms
- Nested field resolution
- Relationship handling
- TypecheckStage validation (required fields, taxonomy, phase)
- Error collection without abort

**Pipeline tests (T16–T22)**:
- End-to-end extraction
- Error handling per-record
- --dry-run flag
- --entity filter
- Idempotency test (run twice, get same result)
- ExtractionResult structure
- CLI invocation

**Adapter tests (T23–T26)**:
- selectFetchAdapter() returns correct adapter
- All adapters implement interface
- Auth header injection
- Stub determinism

### 9.2 Run tests

```bash
bun test phase36b
```

All tests must pass.

Commit: `phase-36b/D36B Tests: add comprehensive extraction pipeline gate tests`

---

## Step 10: Integration + Verification

### 10.1 Type check

```bash
bun run check
```

Zero errors.

### 10.2 Build

```bash
bun run build
```

Success.

### 10.3 Full test suite

```bash
bun test
```

All tests must pass, including new Phase 36B tests.

### 10.4 CLI smoke test

```bash
semantos extract propertyme --dry-run
```

Command must execute without errors (may use stub grammar + stub adapter for testing).

Commit: `phase-36b/Integration: verify type check, build, tests, and CLI`

---

## Step 11: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. **Adversarial code review**: Check every stage for missed requirements. Look for:
   - Evidence chains present at every commit
   - No protocol-specific logic in pipeline
   - All stages are pure functions
   - AsyncGenerator used throughout (no Promise arrays)
   - Idempotency checks in commit stage

2. **Integration test**: Run extraction with PropertyMe stub grammar end-to-end. Verify evidence chains are complete.

3. **Edge cases**:
   - Empty API response
   - Missing required fields
   - Unknown taxonomy paths
   - Duplicate records in a batch
   - Running extraction twice (idempotency)

4. **Documentation**: Write errata doc as `docs/prd/PHASE-36B-ERRATA.md` with any bugs fixed, lessons learned, and improvements for Phase 36C.

---

## Completion Criteria

- [ ] All stage interfaces defined (`RawResponse`, `IntermediateRecord`, `ValidatedRecord`, `InferredRecord`, `SemanticObject`)
- [ ] FetchAdapter interface and implementations (REST, GraphQL, file, stub)
- [ ] RestFetchAdapter: HTTP, auth, pagination, rate limits
- [ ] GraphQLFetchAdapter: query construction, cursor pagination
- [ ] FileFetchAdapter: CSV, JSON, XML, Parquet parsing
- [ ] ParseStage: field mappings, transforms (concat, split, lookup, template, enum_map, compute)
- [ ] ParseStage: nested field resolution (dot-notation)
- [ ] ParseStage: relationship handling (has_many, belongs_to, etc.)
- [ ] TypecheckStage: required field validation
- [ ] TypecheckStage: taxonomy coordinate validation
- [ ] TypecheckStage: phase mapping and assignment
- [ ] TypecheckStage: error collection without abort
- [ ] InferStage: unmapped field detection
- [ ] InferStage: optional taxonomy suggestion (inference client)
- [ ] InferStage: grammar patch proposal
- [ ] CommitStage: semantic object creation via LoomStore
- [ ] CommitStage: idempotency (check for existing, patch if found)
- [ ] CommitStage: full evidence chain attachment
- [ ] ExtractionPipeline: orchestrates all five stages
- [ ] ExtractionPipeline: error handling per-entity (no abort)
- [ ] ExtractionPipeline: --dry-run, --entity, --since options
- [ ] Shell command `semantos extract` operational
- [ ] Tests T1–T26 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing tests still pass
- [ ] All commits follow `phase-36b/D36B.N:` naming convention
- [ ] Branch is `phase-36b-semantic-extraction-pipeline`
- [ ] Errata sprint complete with `docs/prd/PHASE-36B-ERRATA.md`

---

## Next Phase

Phase 36C implements the schema inference agent that reads unfamiliar API responses, diffs against known grammars, and proposes new Extension Grammar JSON as AFFINE draft objects. The agent uses the extraction pipeline (Phase 36B) to validate proposed grammars before suggesting them.
