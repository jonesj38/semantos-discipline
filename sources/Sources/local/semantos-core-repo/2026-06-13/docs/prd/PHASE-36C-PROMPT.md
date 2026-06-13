---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36C-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.668059+00:00
---

# Phase 36C Execution Prompt — Schema Inference Agent

> Paste this prompt into a fresh session to execute Phase 36C.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and shell for Semantos nodes. The kernel (cell engine, linearity, capability validation) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, protocol adapters, conversational shell, and loom UI.

Phase 36C builds the **Schema Inference Agent** — a structured pipeline that reads unfamiliar API responses and proposes new Extension Grammar JSONs as AFFINE draft semantic objects. The agent bootstraps connectors without requiring hand-crafted grammar development.

The agent is not a general-purpose LLM assistant. It is a deterministic pipeline with LLM assistance only for taxonomy mapping. Every inference step is confidence-scored. Low-confidence results are flagged for human review. All inferred grammars are AFFINE drafts, never auto-published.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These define the types, interfaces, and contracts you must implement against.

**Read first** (the PRD and architecture):
- `docs/prd/PHASE-36C-SCHEMA-INFERENCE-AGENT.md` — Phase 36C spec with all deliverables (D36C.1–D36C.6), architecture, gate tests, completion criteria
- `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` — Context: Phase 36 builds a generalised connector framework. Phase 36C infers grammars to bootstrap new connectors.
- `docs/prd/PHASE-36A-EXTENSION-GRAMMAR-SCHEMA.md` — ExtensionGrammar interface (your output format) and validateExtensionGrammar() (you call this to validate composed grammars)
- `docs/prd/PHASE-36B-SEMANTIC-EXTRACTION-PIPELINE.md` — The extraction pipeline that consumes grammars you infer. Read to understand the contract.

**Read second** (the protocol types and existing integrations):
- `packages/protocol-types/src/extension-grammar.ts` — ExtensionGrammar, EntityMapping, FieldMapping types
- `packages/protocol-types/src/extension-grammar-validator.ts` — validateExtensionGrammar() (you call this)
- `packages/protocol-types/src/intent-classifier.ts` — LLM integration pattern via OpenRouter (you follow this for TaxonomyMapper)
- `packages/extraction/src/pipeline.ts` — Extraction pipeline interface and types

**Read third** (shell and loom integration):
- `packages/shell/src/parser.ts` — Shell command parsing (for `semantos infer` subcommand)
- `packages/loom/src/services/LoomStore.ts` — Semantic object storage (you create AFFINE objects here)
- `docs/TAXONOMY-SEED-DESIGN.md` — WHAT/HOW/WHY axis definitions (used in taxonomy mapping prompts)

**Read fourth** (reference implementations):
- `configs/extensions/propertyme/grammar.json` — Reference PropertyMe grammar (from Phase 36A)
- `packages/__tests__/phase36a-extension-grammar.test.ts` — Validation test patterns

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. DETERMINISTIC WHERE POSSIBLE

Structure detection (entity boundaries, field types, nesting, cardinality) is **deterministic parsing**. You do not call the LLM for this. Period.

- Detect entities by finding arrays of similar objects or pagination markers
- Infer field types by sampling multiple responses and finding the most frequent non-null type
- Detect ID fields by name pattern (id, _id, *_id) or UUID format
- Detect timestamp fields by name pattern or ISO 8601 format
- Detect relationships by finding foreign key patterns and array homogeneity

If you find yourself calling LLM for any of this, STOP. That is not the inference agent, that is a cost-hemorrhaging mistake.

### 2. LLM ONLY FOR TAXONOMY, WITH CONFIDENCE SCORING

The ONLY LLM task is suggesting WHAT/HOW/WHY taxonomy coordinates for each inferred entity. Every LLM-based suggestion must have a confidence score (0.0–1.0).

- Pre-filter with embedding similarity (top-3 similar nodes) before calling LLM
- LLM returns suggested coordinates + confidence
- Cross-check LLM result against similarity pre-filter
- Score thresholds: >0.8 (high, auto-assign), 0.5–0.8 (medium, user approves), <0.5 (low, user must set)
- If LLM times out or returns unparseable JSON, confidence = 0.0

No LLM for structure. No LLM for type inference. No LLM for field mapping. LLM is a taxonomy suggester with confidence scoring.

### 3. CONFIDENCE SCORES ARE MANDATORY

Every inference step produces a confidence score:
- StructureAnalyzer: confidence on entity detection, field type detection, field cardinality
- TaxonomyMapper: confidence on WHAT/HOW/WHY suggestions (from LLM + similarity cross-check)
- GrammarDiffEngine: confidence on entity matches (based on field overlap %)
- GrammarComposer: validates grammar; flags low-confidence inferences in metadata

If an inference has no confidence score, it is incomplete.

### 4. GRAMMARS MUST VALIDATE BEFORE COMPOSITION

The `GrammarComposer` calls `validateExtensionGrammar()` on the composed grammar before returning. If validation fails, return validation errors. Do not hide failures behind a "valid: false" field and continue.

If the composed grammar cannot pass validation, something went wrong in an earlier stage. Debug and fix the root cause.

### 5. AFFINE DRAFTS ALWAYS, NEVER AUTO-PUBLISH

All inferred grammars are AFFINE semantic objects. They do not auto-transition to RELEVANT. They do not auto-publish to the marketplace. The user must explicitly approve via `semantos infer approve <id>` or through the governance ballot system (Phase 36D).

No background jobs. No auto-transition. No "publish if confidence > threshold" logic. AFFINE draft, human review required, every time.

### 6. NO CREDENTIALS IN THE GRAMMAR OR SHELL HISTORY

The `semantos infer <api-url> --auth-<field> <value>` command accepts credentials via flags **for sampling only**. These credentials do NOT persist in the grammar, CLI history, or anywhere else.

The composed grammar's `SourceDeclaration.auth.requiredCredentials` specifies what credentials are *needed*, not what they *are*. Binding (Phase 36D) handles credential management and storage.

### 7. FULL PROVENANCE IN EVIDENCE CHAINS

Every inferred grammar's evidence chain must include:
- Sampled API responses (hashed, not the full response)
- Inference parameters (API URL, sample count, confidence thresholds)
- LLM reasoning for taxonomy suggestions (for human review)
- Field type detection confidence per field
- Grammar diff results (new entities, matches, mismatches)
- Validation errors if any
- User approvals/rejections

The evidence chain is the audit trail and the learning signal.

### 8. GIT HYGIENE

- Branch: `phase-36c-schema-inference-agent`
- Commit convention: `phase-36c/D36C.N:` where N is the deliverable number
- Stage files explicitly, never `git add -A`
- Preserve git history with `git mv` for file renames
- One logical commit per deliverable

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /sessions/serene-lucid-einstein/mnt/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify prerequisites are complete

Phase 36A (Extension Grammar JSON schema) and Phase 36B (semantic extraction pipeline) must be complete.

```bash
# These files must exist
ls packages/protocol-types/src/extension-grammar.ts
ls packages/protocol-types/src/extension-grammar-validator.ts
ls packages/extraction/src/pipeline.ts
ls packages/protocol-types/src/intent-classifier.ts
```

All files must exist. If any are missing, prerequisites are incomplete — STOP and report.

### 0.4 Create Phase 36C branch

```bash
git checkout -b phase-36c-schema-inference-agent
```

---

## Step 1: Structure Analyzer (D36C.1)

### 1.1 Create file and implement analyzeStructure()

**File**: `packages/extraction/src/inference/structure-analyzer.ts`

Implement `analyzeStructure(responses: RawResponse[]): EntityGraph` with:

- **Entity detection**: Find arrays of similar objects or paginated results (dataPath in root)
- **Field type inference**: Sample across all responses; infer from most frequent non-null type
- **Required vs. optional fields**: Field is required if it appears in ALL samples
- **ID field detection**: Name pattern (id, _id, *_id) or UUID format
- **Timestamp field detection**: Name pattern (created*, updated*, *_at, *_time) or ISO 8601/Unix format
- **Enum field detection**: String field with ≤10 unique values
- **Relationship detection**: Foreign key patterns (entity_id matching another entity's ID), has_many (homogeneous arrays)
- **Nesting depth tracking**: Record but warn if >4 levels

Export `EntityGraph` interface.

**Validation**: Can you parse the PropertyMe reference grammar's sample responses and correctly detect `property`, `lease`, `tenant`, `maintenance_request` entities with their fields?

### 1.2 Write tests for StructureAnalyzer

**File**: Add to `packages/__tests__/phase36c-schema-inference-agent.test.ts` (or create if it doesn't exist)

- T1: analyzeStructure() detects entity boundaries from array of objects
- T2: analyzeStructure() infers field types (string, number, boolean, date, enum)
- T3: analyzeStructure() detects ID/timestamp fields and relationships

Run tests:
```bash
bun test --grep "StructureAnalyzer"
```

All three must pass.

### 1.3 Verify types export

```bash
bun run check 2>&1 | grep -i "analyzer\|entity.*graph"
```

Must show zero errors.

**Commit**: `phase-36c/D36C.1: implement StructureAnalyzer for entity/field type inference`

---

## Step 2: Taxonomy Mapper (D36C.2)

### 2.1 Create file and implement mapTaxonomy()

**File**: `packages/extraction/src/inference/taxonomy-mapper.ts`

Implement `mapTaxonomy(graph: EntityGraph, knownTaxonomy: TaxonomyTree): TaxonomyProposal` with:

- **Pre-filter with embeddings**: Compute vectors for entity names + sample field names. Find top-3 similar existing taxonomy nodes (use simple string similarity if no embedding model available).
- **Build LLM prompt**: Include entity name, sample field names, top-3 similar nodes, WHAT/HOW/WHY definitions from TAXONOMY-SEED-DESIGN.md
- **LLM call**: Use IntentClassifier (Phase 9.5) pattern via OpenRouter. Timeout 5 seconds per entity.
- **Confidence scoring**: Combine LLM confidence (returned in response) with similarity pre-filter. If LLM matches high-similarity node, boost confidence. If LLM contradicts pre-filter, apply skepticism.
- **Classify**: >0.8 (high), 0.5–0.8 (medium), <0.5 (low)

Export `TaxonomyProposal` interface with confidence scores.

**Validation**: Can you run mapTaxonomy on an inferred `lease` entity and get a WHAT coordinate like `what.property.lease` with confidence score?

### 2.2 Write tests for TaxonomyMapper

Add to test file:
- T4: mapTaxonomy() calls LLM and returns TaxonomyProposal with confidence scores
- T5: Confidence thresholds correctly applied (high/medium/low)
- T6: Embedding pre-filter reduces LLM calls and improves accuracy

Run tests:
```bash
bun test --grep "TaxonomyMapper"
```

All three must pass.

### 2.3 Verify integration with IntentClassifier

```bash
bun run check
```

Must resolve IntentClassifier imports and show zero errors.

**Commit**: `phase-36c/D36C.2: implement TaxonomyMapper with LLM + confidence scoring`

---

## Step 3: Grammar Diff Engine (D36C.3)

### 3.1 Create file and implement diffGrammars()

**File**: `packages/extraction/src/inference/grammar-diff.ts`

Implement `diffGrammars(proposed: EntityGraph, known: ExtensionGrammar[]): GrammarDiff` with:

- **Load installed grammars**: Iterate ExtensionRegistry
- **Field overlap matching**: For each proposed entity, check each grammar entity. Count overlapping fields. If >70% overlap and types match, flag as matched.
- **String similarity fallback**: Use Levenshtein distance for name mismatches (e.g., `maintenance_request` vs `MaintenanceRequest`)
- **Collect unmatched entities**: Entities with <70% overlap in any grammar
- **Collect unmapped fields**: Fields in proposed entities that don't appear in matched grammar entities
- **Detect type mismatches**: Fields where proposed type differs from grammar type

Export `GrammarDiff` interface.

**Validation**: Given an inferred lease entity that matches the PropertyMe grammar's lease entity, confirm >70% field overlap. For a completely new entity, confirm it's in `newEntities`.

### 3.2 Write tests for GrammarDiffEngine

Add to test file:
- T7: diffGrammars() matches entities with >70% field overlap
- T8: diffGrammars() identifies new entities
- T9: diffGrammars() detects type mismatches

Run tests:
```bash
bun test --grep "GrammarDiffEngine"
```

All three must pass.

### 3.3 Verify no unresolved imports

```bash
bun run check
```

Must show zero errors.

**Commit**: `phase-36c/D36C.3: implement GrammarDiffEngine for grammar matching`

---

## Step 4: Grammar Composer (D36C.4)

### 4.1 Create file and implement composeGrammar()

**File**: `packages/extraction/src/inference/grammar-composer.ts`

Implement `composeGrammar(graph: EntityGraph, taxonomy: TaxonomyProposal, diff: GrammarDiff, sourceConfig: Partial<SourceDeclaration>): ComposedGrammar` with:

- **Generate metadata**: grammarId (from source protocol + URL, sanitized), grammarVersion "0.1.0", author "Schema Inference Agent"
- **Populate source declaration**: Use sourceConfig for protocol/auth/rate limits. Add entities from graph.
- **Create ObjectTypeDeclarations**: One per entity. Use WHAT coordinate from taxonomy as typePath. Default linearity to AFFINE. Default phases to ["draft", "active"].
- **Create EntityMappings**: One per entity. Map source fields to target fields. Include taxonomy coordinates.
- **Flag unmatched entities**: Note new entities in metadata.
- **Flag low-confidence inferences**: Include `_lowConfidenceInferences` array in metadata for any coordinate with confidence < 0.8.
- **Validate**: Call validateExtensionGrammar(). If invalid, return errors.
- **Return ComposedGrammar** with grammar, valid flag, validation errors, low-confidence flags, and human-readable summary.

**Validation**: Compose a grammar from inferred PropertyMe data. Verify it passes validateExtensionGrammar(). Verify low-confidence fields are flagged.

### 4.2 Write tests for GrammarComposer

Add to test file:
- T10: composeGrammar() produces valid ExtensionGrammar that passes validateExtensionGrammar()
- T11: composeGrammar() includes low-confidence flags in metadata

Run tests:
```bash
bun test --grep "GrammarComposer"
```

Both must pass.

### 4.3 Verify validation integration

```bash
bun run check
```

Must resolve validateExtensionGrammar imports and show zero errors.

**Commit**: `phase-36c/D36C.4: implement GrammarComposer with validation`

---

## Step 5: Inference Pipeline Orchestrator (D36C.5)

### 5.1 Create file and implement InferenceAgent

**File**: `packages/extraction/src/inference/pipeline.ts`

Implement `InferenceAgent` class with `async infer(sampleResponses, sourceConfig, options?)` method:

- **Orchestrate pipeline**: StructureAnalyzer → TaxonomyMapper → GrammarDiffEngine → GrammarComposer
- **Handle errors**: If any stage fails, return with error details. Do not continue to next stage.
- **Create AFFINE semantic object**: After composition, create semantic object in LoomStore:
  - Type: `what.platform.extension.inferred-grammar`
  - Linearity: AFFINE
  - Payload: ComposedGrammar
  - Evidence chain: EntityGraph, TaxonomyProposal, GrammarDiff, low-confidence flags, validation results
  - Metadata: timestamp, hashed sample responses, inference parameters
- **Return InferenceResult** with: grammarId, grammar, valid, entityGraph, taxonomyProposal, grammarDiff, low-confidence flags, review summary, entity graph visualization

**Validation**: Run infer() on 3 PropertyMe API responses. Verify the pipeline completes and the AFFINE object is created in LoomStore.

### 5.2 Write tests for InferenceAgent

Add to test file:
- T12: infer() runs all stages and returns InferenceResult
- T13: infer() creates AFFINE semantic object in LoomStore with evidence chain

Run tests:
```bash
bun test --grep "InferenceAgent"
```

Both must pass.

### 5.3 Verify LoomStore integration

```bash
bun run check
```

Must resolve LoomStore imports and show zero errors.

**Commit**: `phase-36c/D36C.5: implement InferenceAgent pipeline orchestrator`

---

## Step 6: Shell Command (D36C.6)

### 6.1 Create inference subcommand router

**File**: Update `packages/shell/src/router.ts` or create `packages/shell/src/inference.ts`

Add new router entry for `semantos infer`:

```typescript
case 'infer':
  return handleInfer(args, options);
```

### 6.2 Implement infer subcommand handlers

**File**: `packages/shell/src/commands/infer.ts` (or within inference.ts)

Implement handlers for:

- `semantos infer <api-url> --auth <type> [--auth-<field> <value>]` — fetch live samples and infer
- `semantos infer <sample-file.json>` — read saved responses and infer
- `semantos infer review <grammar-id>` — display proposed grammar and flags
- `semantos infer approve <grammar-id> [--publish]` — approve (AFFINE → RELEVANT if --publish)
- `semantos infer reject <grammar-id> --reason "..."` — reject and archive
- `semantos infer list [--status draft|approved|rejected]` — list inferred grammars

**Credential handling**: `--auth-<field>` flags are read but NOT persisted. No shell history. No grammar embedding. Credentials are ephemeral for sampling.

### 6.3 Write tests for shell command

Add to test file:
- T14: `semantos infer review <id>` displays proposed grammar and flags; `semantos infer approve <id>` transitions to RELEVANT

Run tests:
```bash
bun test --grep "semantos infer"
```

Must pass.

### 6.4 Verify integration

```bash
bun run check
```

Must show zero errors. Test the command manually if possible:
```bash
bun run cli infer --help
```

**Commit**: `phase-36c/D36C.6: implement semantos infer shell subcommand`

---

## Step 7: Full Test Suite

### 7.1 Run all Phase 36C gate tests

```bash
bun test phase36c
```

Tests T1–T14 must all pass.

### 7.2 Verify no regressions

```bash
bun test
```

All existing tests must pass. No new failures.

### 7.3 Type check and build

```bash
bun run check
bun run build
```

Both must succeed. Zero TypeScript errors. Zero build errors.

**If any test fails or check shows errors**: Debug and fix before moving to step 8. Do not commit broken code.

**Commit**: (if any fixes needed) `phase-36c/cleanup: fix failing tests and type errors`

---

## Step 8: Errata Sprint

After all tests pass, run the errata protocol:

### 8.1 Adversarial review

Re-read PHASE-36C-SCHEMA-INFERENCE-AGENT.md. For each deliverable:
- Did you implement it exactly as specified?
- Did you miss any edge cases (empty responses, missing fields, circular relationships)?
- Are all confidence scores correctly calculated?
- Is the evidence chain complete?

### 8.2 Code quality checks

- Check for any LLM calls outside TaxonomyMapper. If found, remove.
- Check for any auto-publishing or AFFINE→RELEVANT transitions outside explicit approval. If found, remove.
- Check for any embedded credentials in grammars or logs. If found, remove.
- Check for any missing error handling (timeouts, unparseable LLM responses, invalid JSON). If found, add.

### 8.3 Documentation review

- Update `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` if dependencies changed
- Verify all references to Phase 36C are correct
- Add Phase 36C to README.md document tree if not already there

### 8.4 Final verification

```bash
# Scan for any LLM calls outside TaxonomyMapper
grep -rn "llm\|openRouter\|IntentClassifier" packages/extraction/src/inference/ --include="*.ts" | grep -v taxonomy-mapper

# Scan for any auto-publishing logic
grep -rn "auto.*publish\|transition.*RELEVANT.*inferred" packages/ --include="*.ts"

# Verify credentials not embedded
grep -rn "authValue\|--auth-\|credentials" packages/shell/src/commands/infer.ts | grep -v "requiredCredentials"
```

All three must return zero results (or only expected matches in error messages/comments).

### 8.5 Write errata doc

**File**: `docs/prd/PHASE-36C-ERRATA.md`

Document any issues found and fixed:
- Edge cases discovered during testing
- Confidence calculation adjustments
- Evidence chain completeness verification
- Shell command behavior clarifications

**Commit**: `phase-36c/errata: document edge cases and verification results`

---

## Completion Criteria

- [ ] D36C.1: StructureAnalyzer implemented and tested (T1–T3 pass)
- [ ] D36C.2: TaxonomyMapper implemented with LLM integration and confidence scoring (T4–T6 pass)
- [ ] D36C.3: GrammarDiffEngine implemented and tested (T7–T9 pass)
- [ ] D36C.4: GrammarComposer implemented with validation (T10–T11 pass)
- [ ] D36C.5: InferenceAgent orchestrator implemented with AFFINE semantic object creation (T12–T13 pass)
- [ ] D36C.6: `semantos infer` shell subcommand implemented (T14 passes)
- [ ] All gate tests T1–T14 pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing gate tests still pass (no regressions)
- [ ] All commits follow `phase-36c/D36C.N:` naming convention
- [ ] Branch is `phase-36c-schema-inference-agent`
- [ ] Errata sprint complete with `docs/prd/PHASE-36C-ERRATA.md`

---

## Key Implementation Notes

**LLM integration:** Follow the IntentClassifier pattern from Phase 9.5. Use OpenRouter API. Handle timeouts gracefully (default 5 seconds). If LLM returns unparseable JSON or times out, set confidence = 0.0 and continue.

**Confidence scoring:** No magic numbers. Document threshold rationale in code comments. Make configurable via InferenceAgent options if possible.

**Evidence chains:** The evidence chain IS the value proposition. Don't cut corners. Include sampled API responses (hashed, not full text to avoid PII/secrets), all inference results, user decisions, and validation errors.

**AFFINE drafts:** Every inferred grammar starts as AFFINE. It stays AFFINE until explicitly approved via `semantos infer approve --publish`. No auto-transitions. No background jobs. No "publish if confident" logic.

**Determinism:** If you find yourself unsure whether something is deterministic or LLM-based, err on the side of determinism. Structure detection, type inference, field mapping are all deterministic. Only taxonomy is probabilistic.

---

## Next Phase

Phase 36D implements the hierarchical governance model (L0, L1, L2) and the ballot/dispute system for approving/rejecting inferred grammars, publishing them to RELEVANT, and handling disputes between extension authors and consumers.
