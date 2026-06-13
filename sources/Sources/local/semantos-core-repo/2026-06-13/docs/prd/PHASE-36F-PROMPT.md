---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36F-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.662899+00:00
---

# Phase 36F Execution Prompt — Connector Reference Implementation (PropertyMe)

> Paste this prompt into a fresh session to execute Phase 36F.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer, shell, and UI for Semantos nodes. The kernel (cell engine, linearity, capability validation) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, protocol adapters, extraction pipeline, loom UI, and semantic shell.

Phases 36A–36D built the extension ecosystem architecture: Extension Grammar JSON schema (36A), semantic extraction pipeline (36B), schema inference agent (36C), and hierarchical governance model (36D). This phase proves the architecture works end-to-end by building the **first real connector: PropertyMe**.

PropertyMe is an Australian property management SaaS API. This connector serves three purposes:

1. **Validation** — proves that Extension Grammar + Extraction Pipeline + Governance Model can handle a real-world API with authentication, pagination, rate limits, complex field mappings, FSM transitions, and relationships
2. **Reference** — establishes the gold standard for how third-party developers should build connectors
3. **Revenue** — first-party extension sold on the marketplace, shipped with the property management product

Your task: build the PropertyMe connector entirely through the Phase 36 framework. No special-casing. No bypass of the pipeline. No hardcoded logic. If the framework can't handle PropertyMe, the framework is incomplete.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real specifications and reference implementations you are extending. If you haven't read them, you will miss critical details.

**Read first** (the PRD and master architecture):
- `docs/prd/PHASE-36F-CONNECTOR-REFERENCE-IMPL.md` — Phase 36F spec with complete deliverables D36F.1–D36F.7, PropertyMe API overview, field transforms, testing strategy, developer guide outline
- `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` — Architecture overview: Extension Grammar JSON, extraction pipeline contract, hierarchical governance (L0/L1/L2), cross-phase dependencies
- `docs/prd/PHASE-36A-EXTENSION-GRAMMAR-SCHEMA.md` — Extension Grammar JSON meta-schema, SourceDeclaration, EntityMapping, FieldMapping, FieldTransform, ObjectTypeDeclaration, with PropertyMe stub grammar
- `docs/prd/PHASE-36B-SEMANTIC-EXTRACTION-PIPELINE.md` — Five-stage pipeline (fetch → parse → typecheck → infer → commit), StorageAdapter contract, evidence chain structure
- `docs/prd/PHASE-36D-EXTENSION-GOVERNANCE-MODEL.md` — GovernancePolicy (L0), ExtensionManifest (L1), ConsumerBinding (L2), hierarchical constraints, patch acceptance rules

**Read second** (property management vertical context):
- `docs/PLATFORM-ARCHITECTURE.md` — Property management vertical object types (Property, Lease, Tenant, Owner, MaintenanceRequest, Inspection, Document), MaintenanceRequest FSM (new → triaged → awaiting_approval → approved → dispatched → in_progress → completed → invoiced → closed), dispatch model, linearity assignments
- `docs/design/SHOMEE-TO-SEMANTOS-MAPPING.md` — Object linearity patterns (RELEVANT, LINEAR, AFFINE), evidence chain anatomy, semantic object type design, Dispatch Envelope pattern

**Read third** (implementation reference):
- `configs/extensions/core.json` — base extension config structure, object type definitions format, flow definitions
- `configs/extensions/trades-services.json` — reference implementation of a real extension, field mappings, taxonomy coordinates, FSM transitions
- `packages/protocol-types/src/extension-grammar.ts` — ExtensionGrammar, SourceEntity, FieldMapping, FieldTransform, ObjectTypeDeclaration TypeScript interfaces
- `packages/protocol-types/src/adapters/fetch-adapter.ts` — FetchAdapter interface, OAuth2 token flow, pagination, rate limiting, webhook setup
- `packages/protocol-types/src/storage.ts` — StorageAdapter interface for the commit stage

**Read fourth** (Phase 36A/36B outputs):
- `configs/extensions/propertyme/grammar.json` — PropertyMe stub grammar from Phase 36A (reference only — you will complete it)
- `packages/protocol-types/src/extension-grammar-validator.ts` — validateExtensionGrammar() implementation
- `packages/protocol-types/src/grammar-config-bridge.ts` — grammarToExtensionConfig() bridge

**Read fifth** (testing patterns):
- `packages/__tests__/phase36a-extension-grammar.test.ts` — Grammar validation tests (reference pattern for Phase 36F tests)
- `packages/__tests__/phase36b-extraction-pipeline.test.ts` — Pipeline tests with StubFetchAdapter (reference pattern for D36F.6)

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO SPECIAL-CASING

Every PropertyMe-specific behavior must be expressed in the Extension Grammar JSON or declared field transforms. The extraction pipeline does not and must not contain PropertyMe-aware code. If you write `if (grammarId === 'com.semantos.propertyme')` in the pipeline, you have failed.

The pipeline reads the grammar at runtime. The grammar drives the extraction. This is the entire point of the framework.

### 2. ALL ENTITIES MUST BE MAPPED

PropertyMe has 11 core entities: Property, Lease, Tenant, Owner, MaintenanceRequest, Inspection, Document, Contact, Invoice, Receipt, OwnerStatement. You must declare complete source entity definitions and field mappings for all of them. Incomplete coverage means the reference doesn't prove the framework works.

### 3. FIELD TRANSFORMS ARE DECLARATIVE

PropertyMe has real-world data transformation needs (address composition, cost normalization, status mapping, date formatting). All transforms must be expressed as declarative FieldTransform entries in the grammar. No inline TypeScript functions. No imperative logic in the pipeline. Transforms are interpreted at runtime.

If a transformation cannot be expressed declaratively (concat, split, lookup, template, enum_map, compute), then the transform system is incomplete — file an issue, don't work around it.

### 4. RELATIONSHIPS MUST BE COMPLETE

Leases reference Properties. MaintenanceRequests reference both Properties and Tenants. Inspections reference Properties. Documents have polymorphic parents. All relationships must be declared in the grammar's SourceRelationship definitions and resolved correctly in the extraction pipeline's evidence chain.

Partial relationship mapping is a gap in the reference implementation.

### 5. GOVERNANCE VALIDATION IS NOT OPTIONAL

This is a first-party extension, so it goes through L0 and L1 validation just like any third-party connector. Don't assume exemptions. The governance config must pass validateGovernancePolicy() and validateExtensionManifest() checks.

### 6. FSM TRANSITIONS MUST USE COMMERCE PHASES

MaintenanceRequest has a 9-state FSM (new → triaged → awaiting_approval → approved → dispatched → in_progress → completed → invoiced → closed). All states must map to Semantos commerce phases (SOURCE, PARSE, TYPECHECK, ACTION, OUTCOME). The phaseMapping in the EntityMapping drives this. Verify in tests T5.

### 7. EVIDENCE CHAINS ARE COMPLETE

Every extracted object must carry a full evidence chain:
- Source record (API response hash, timestamp, endpoint)
- Parse record (grammar version, field mapping applied)
- Typecheck record (validation result, taxonomy coordinates)
- Commit record (cell ID, storage adapter, facet provenance)

The pipeline constructs this automatically. Your tests (T8) must verify it's present for every entity type.

### 8. TESTS MUST USE STUBS, NOT LIVE API

Write all tests using StubFetchAdapter, which mocks PropertyMe API responses. Do not make live API calls in tests. StubFetchAdapter responses are deterministic, repeatable, and don't require credentials.

### 9. DEVELOPER GUIDE USES REAL EXAMPLES

Every pattern in the developer guide (`DEVELOPER-GUIDE.md`) must reference actual PropertyMe implementation examples. Developers copy examples; vague guidance produces broken connectors. Show the grammar JSON. Show the field transforms. Show the test assertions.

### 10. COMMITS FOLLOW PHASE-36F CONVENTION

Every commit message follows the pattern: `phase-36f/D36F.N: <description>`. Example: `phase-36f/D36F.1: complete PropertyMe Extension Grammar with all entities and mappings`. Do not commit partially completed deliverables. Each commit should complete one deliverable or a logical chunk of one.

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

Phases 36A, 36B, 36D must be complete (36E recommended but not required).

```bash
# These files must exist
ls docs/prd/PHASE-36A-EXTENSION-GRAMMAR-SCHEMA.md
ls docs/prd/PHASE-36B-SEMANTIC-EXTRACTION-PIPELINE.md
ls docs/prd/PHASE-36D-EXTENSION-GOVERNANCE-MODEL.md
ls packages/protocol-types/src/extension-grammar.ts
ls packages/protocol-types/src/adapters/fetch-adapter.ts
ls packages/protocol-types/src/storage.ts
```

All files must exist. If any are missing, phases are incomplete — STOP and report.

### 0.4 Create Phase 36F branch

```bash
git checkout -b phase-36f-connector-reference-impl
```

---

## Step 1: Complete PropertyMe Extension Grammar (D36F.1)

### 1.1 Review the Phase 36A stub grammar

```bash
cat configs/extensions/propertyme/grammar.json | head -100
```

This is a template. Phase 36F completes it.

### 1.2 Build the full grammar JSON

File: `configs/extensions/propertyme/grammar.json`

Complete the grammar per the spec in PHASE-36F-CONNECTOR-REFERENCE-IMPL.md, deliverable D36F.1. This is a single, large JSON file (not multiple files). It must include:

**Top-level metadata** (grammarId, grammarVersion, author, etc.)

**Source declaration**:
- OAuth2 authentication config (client_id, client_secret, tenant_id required credentials)
- Rate limit: 100 requests per minute
- Cursor-based pagination
- All 11 source entities with full field definitions

**Entity mappings** (PropertyMapping → semantic object types):
- Property → property.dwelling (RELEVANT)
- Lease → property.lease (LINEAR with active/expiring/expired/terminated phases)
- Tenant → property.tenant (RELEVANT)
- Owner → property.owner (RELEVANT)
- MaintenanceRequest → property.maintenance-request (AFFINE with 9-phase FSM)
- Inspection → property.inspection (AFFINE with inspection workflow phases)
- Document → property.document (RELEVANT)
- Contact → contact.reference (RELEVANT) or similar
- Invoice → property.invoice (RELEVANT)
- Receipt → property.receipt (RELEVANT)
- OwnerStatement → property.statement (RELEVANT)

**Field mappings** for each entity:
- Address composition (street_number + street_name + ... + postcode → single address)
- Cost normalization (cents → dollars)
- Date normalization (various formats → ISO 8601)
- Status mapping (PropertyMe enums → commerce phases)
- Relationship links (property_id, tenant_id, etc.)

**Transforms**:
- concat: address composition
- compute: rent calculation, cost division
- map_enum: status → phase mapping
- coerce: date format normalization

**Taxonomy coordinates** for each entity (WHAT/HOW/WHY) per PLATFORM-ARCHITECTURE.md:
- Property → what.asset.property.dwelling, how.management.property-management, why.property.portfolio-tracking
- MaintenanceRequest → what.service.property.maintenance, how.dispatch.reactive, why.maintenance.repair
- etc.

**Capabilities** required:
- network.outbound (call PropertyMe API)
- storage.write (write extracted objects)
- identity.read (fetch credentials from binding)

### 1.3 Validate the grammar

```bash
# The shell command from Phase 36A should exist
semantos grammar validate configs/extensions/propertyme/grammar.json

# Or via TypeScript test
bun run test -- phase36a-extension-grammar.test.ts
```

Zero validation errors required.

### 1.4 Verify all entities and mappings

```bash
# Inspect the grammar to count entities and mappings
semantos grammar inspect com.semantos.propertyme

# Expected output: 11 source entities, 11+ object types, 11+ entity mappings
```

Commit: `phase-36f/D36F.1: complete PropertyMe Extension Grammar with 11 entities and field mappings`

---

## Step 2: Define PropertyMe Object Types (D36F.2)

### 2.1 Create types configuration

File: `configs/extensions/propertyme/types.json`

For each of the 11 PropertyMe entities, define an ObjectTypeDeclaration with:
- typePath (e.g., "property.dwelling")
- linearity assignment (RELEVANT, LINEAR, AFFINE per PLATFORM-ARCHITECTURE.md)
- commerce phases (SOURCE, PARSE, TYPECHECK, ACTION, OUTCOME for most; custom phases for MaintenanceRequest FSM)
- payloadSchema (JSON Schema for the object's payload)
- capabilities (per-operation capability requirements: read, write, approve, dispatch, triage, etc.)
- FSM transitions (phase guards, conditions)

**Linearity assignments** (per PLATFORM-ARCHITECTURE.md):
- Property (RELEVANT) — always accessible, shared across facets
- Lease (LINEAR) — one active lease per property
- Tenant (RELEVANT) — referenced by leases and maintenance
- Owner (RELEVANT) — landlord, immutable once stored
- MaintenanceRequest (AFFINE) — draft until dispatched, then RELEVANT after dispatch
- Inspection (AFFINE) — draft until published
- Document (RELEVANT) — immutable documents
- Contact (RELEVANT) — shared contact reference
- Invoice (RELEVANT) — immutable billing record
- Receipt (RELEVANT) — payment evidence
- OwnerStatement (RELEVANT) — financial summary

**MaintenanceRequest phases** (critical — validates FSM mapping):
SOURCE → TRIAGED → AWAITING_APPROVAL → APPROVED → DISPATCHED → IN_PROGRESS → COMPLETED → INVOICED → CLOSED

Transitions:
- new → triaged (always allowed)
- triaged → awaiting_approval (if estimated_cost exists)
- awaiting_approval → approved (guard: owner.maintenanceApprovalThreshold)
- approved → dispatched (manual dispatch)
- dispatched → in_progress (tradie starts work)
- in_progress → completed (photos + completion notes)
- completed → invoiced (tradie invoice received)
- invoiced → closed (owner approves/pays)
- Also: new → triaged → declined (if tenant_responsibility or owner declines)

### 2.2 Verify types config validity

```bash
# TypeScript type check
bun run check -- packages/protocol-types/src/extension-grammar.ts
```

Zero errors required.

Commit: `phase-36f/D36F.2: define PropertyMe object types with linearity and phases`

---

## Step 3: Implement PropertyMe Fetch Adapter Configuration (D36F.3)

### 3.1 Create fetch adapter config

File: `configs/extensions/propertyme/fetch-adapter.json`

Define:
- OAuth2 token acquisition (authorizationUrl, tokenUrl, scopes from grammar)
- Cursor pagination (pageSize: 50, cursorField: next_cursor)
- Rate limiter (100 req/min, 5 concurrent requests)
- Webhook listeners for real-time updates (property.updated, lease.updated, maintenance.created, inspection.updated)
- Error handling rules:
  - 429 (rate limit): retry with exponential backoff (2s, 4s, 8s)
  - 503 (service unavailable): retry with backoff
  - 401 (auth error): refresh token via ConsumerBinding
  - 404 (not found): log and skip record
  - 400 (validation error): skip record, log in evidence chain

### 3.2 Wire into FetchAdapter interface

File: `packages/protocol-types/src/adapters/propertyme-fetch-adapter.ts`

Implement `FetchAdapter` interface:

```typescript
interface FetchAdapter {
  authenticate(): Promise<void>;
  fetch(endpoint: string, options?: FetchOptions): Promise<ApiResponse>;
  setupWebhooks?(): Promise<void>;
  close(): Promise<void>;
}
```

Use the grammar's oauth2Config and rateLimits to configure behavior. No hardcoded URLs or credentials.

Commit: `phase-36f/D36F.3: implement PropertyMe fetch adapter with OAuth2, pagination, rate limiting`

---

## Step 4: Implement PropertyMe Field Transforms (D36F.4)

### 4.1 Add field transform implementations

File: `packages/protocol-types/src/adapters/propertyme-field-transforms.ts`

Implement all FieldTransform types used in the PropertyMe grammar:

**Address composition** (concat):
```
Input: { street_number: "123", street_name: "Main", street_type: "Street", suburb: "Sydney", state: "NSW", postcode: "2000" }
Output: "123 Main Street, Sydney NSW 2000"
```

**Rent calculation** (compute):
```
Input: weekly_rent: 350, rent_frequency: "fortnightly"
Output: 700 (for fortnightly), 1400 (for monthly), 350 (for weekly)
```

**Status mapping** (map_enum):
```
PropertyMe maintenance status → Semantos commerce phase
new → SOURCE
triaged → PARSE
awaiting_approval → TYPECHECK
approved → ACTION
dispatched → IN_PROGRESS
completed → COMPLETED
invoiced → INVOICED
closed → OUTCOME
```

**Date normalization** (coerce):
```
Input: "2024-03-15T14:30:00Z" (ISO)
Input: "15/03/2024" (Australian format)
Output: "2024-03-15" (ISO 8601)
```

**Cost normalization** (compute):
```
Input: estimated_cost: 28000 (cents)
Output: 280.00 (dollars)
```

All transforms must be declarative (no arbitrary code). The transform interpreter reads the grammar and applies these functions.

### 4.2 Wire transforms into pipeline

Update `packages/protocol-types/src/adapters/extraction-pipeline.ts` (or equivalent Phase 36B impl):

The `parse` stage reads FieldTransform from the grammar and applies transformations.

Commit: `phase-36f/D36F.4: implement PropertyMe field transforms (address, cost, date, status)`

---

## Step 5: Set Up PropertyMe Governance (D36F.5)

### 5.1 Create governance config

File: `configs/extensions/propertyme/governance.json`

Define:
- ExtensionManifest (L1):
  - grammarId: com.semantos.propertyme
  - author: Semantos Inc. (first-party)
  - version: 1.0.0
  - patchAcceptancePolicy: author_only (only Semantos can approve changes)
- ConsumerBinding (L2) sample:
  - consumerFacetId: test-consumer-facet (mock)
  - extensionId: com.semantos.propertyme
  - credentials:
    - client_id: "test-client-id"
    - client_secret: "test-client-secret"
    - tenant_id: "test-tenant-id"
  - customOverrides: (empty for reference impl)

### 5.2 Validate governance

```bash
# TypeScript validation (if Phase 36D implemented these)
bun run test -- phase36d-extension-governance.test.ts
```

All validation checks must pass (L0 meta-schema, L1 manifest integrity, L2 binding constraints).

Commit: `phase-36f/D36F.5: set up PropertyMe governance (L1 author + L2 sample binding)`

---

## Step 6: Write End-to-End Integration Tests (D36F.6)

### 6.1 Create test file

File: `packages/__tests__/phase36f-propertyme-connector.test.ts`

Write 14 gate tests using StubFetchAdapter. Each test is deterministic, repeatable, no live API calls.

**T1**: Grammar validation
```typescript
test("PropertyMe grammar validates via validateExtensionGrammar()", () => {
  const grammar = loadGrammarSync("configs/extensions/propertyme/grammar.json");
  const result = validateExtensionGrammar(grammar);
  expect(result.valid).toBe(true);
  expect(result.errors).toHaveLength(0);
});
```

**T2**: Bridge to ExtensionConfig
```typescript
test("PropertyMe grammar produces valid ExtensionConfig via bridge", () => {
  const grammar = loadGrammarSync("configs/extensions/propertyme/grammar.json");
  const config = grammarToExtensionConfig(grammar);
  expect(config).toBeDefined();
  expect(config.objectTypes.length).toBeGreaterThan(0);
});
```

**T3**: Pipeline fetch → parse → typecheck → commit
```typescript
test("Pipeline fetches, parses, typechecks, commits for Property entity", async () => {
  const stub = new StubFetchAdapter(mockPropertyMeResponses());
  const binding = createTestConsumerBinding("com.semantos.propertyme");
  const result = await extractionPipeline.execute({
    adapter: stub,
    grammar: loadGrammarSync("configs/extensions/propertyme/grammar.json"),
    binding,
    entityTypes: ["property"]
  });
  expect(result.commitCount).toBeGreaterThan(0);
});
```

**T4**: All 7+ entities
```typescript
test("Pipeline handles all 11 PropertyMe entity types", async () => {
  const stub = new StubFetchAdapter(mockPropertyMeResponses());
  const binding = createTestConsumerBinding("com.semantos.propertyme");
  const result = await extractionPipeline.execute({
    adapter: stub,
    grammar: loadGrammarSync("configs/extensions/propertyme/grammar.json"),
    binding,
    entityTypes: ["property", "lease", "tenant", "owner", "maintenance_request", "inspection", "document", ...]
  });
  expect(result.entityCounts).toMatchObject({
    property: expect.any(Number),
    lease: expect.any(Number),
    // ... all 11
  });
});
```

**T5**: MaintenanceRequest FSM
```typescript
test("MaintenanceRequest FSM transitions through all commerce phases", async () => {
  const mr = mockMaintenanceRequest({
    status: "new",
    approval_status: "pending_pm"
  });
  const stub = new StubFetchAdapter([mr]);
  const result = await extractionPipeline.execute({...});
  const mrObject = result.objects.find(o => o.typePath === "property.maintenance-request");
  expect(mrObject.phase).toBe("SOURCE");
  // Simulate state transitions...
  expect(mrObject.phase).toBe("PARSE"); // triaged
  expect(mrObject.phase).toBe("TYPECHECK"); // awaiting_approval
  expect(mrObject.phase).toBe("ACTION"); // approved
  expect(mrObject.phase).toBe("IN_PROGRESS"); // dispatched → in_progress
  expect(mrObject.phase).toBe("COMPLETED");
  expect(mrObject.phase).toBe("INVOICED");
  expect(mrObject.phase).toBe("OUTCOME"); // closed
});
```

**T6**: Field transforms correctness
```typescript
test("Field transforms produce correct output (address, cost, status, date)", async () => {
  const prop = mockProperty({
    address: {
      street_number: "123",
      street_name: "Main",
      street_type: "Street",
      suburb: "Sydney",
      state: "NSW",
      postcode: "2000"
    }
  });
  const result = await extractionPipeline.executeEntityMapping("property", [prop]);
  expect(result.objects[0].payload.address).toBe("123 Main Street, Sydney NSW 2000");
  
  const lease = mockLease({
    rent_amount: 35000, // cents
    rent_frequency: "fortnightly"
  });
  const result2 = await extractionPipeline.executeEntityMapping("lease", [lease]);
  expect(result2.objects[0].payload.rentAmount).toBe(350.00);
});
```

**T7**: Relationships resolved
```typescript
test("Relationships resolved correctly (Lease → Property, MaintenanceRequest → Property + Tenant)", async () => {
  const prop = mockProperty({ id: "prop-1" });
  const lease = mockLease({ id: "lease-1", property_id: "prop-1" });
  const mr = mockMaintenanceRequest({ id: "mr-1", property_id: "prop-1", tenant_id: "tenant-1" });
  const stub = new StubFetchAdapter([prop, lease, mr]);
  
  const result = await extractionPipeline.execute({...});
  
  const leaseObj = result.objects.find(o => o.id === "lease-1");
  expect(leaseObj.relations).toContainEqual({
    type: "belongs_to",
    target: "prop-1"
  });
  
  const mrObj = result.objects.find(o => o.id === "mr-1");
  expect(mrObj.relations).toContainEqual({
    type: "belongs_to",
    target: "prop-1"
  });
  expect(mrObj.relations).toContainEqual({
    type: "belongs_to",
    target: "tenant-1"
  });
});
```

**T8**: Evidence chains complete
```typescript
test("Evidence chains complete for all extracted objects", async () => {
  const stub = new StubFetchAdapter(mockPropertyMeResponses());
  const result = await extractionPipeline.execute({...});
  
  result.objects.forEach(obj => {
    expect(obj.evidenceChain).toBeDefined();
    expect(obj.evidenceChain.source).toBeDefined(); // API response hash, timestamp, endpoint
    expect(obj.evidenceChain.parse).toBeDefined(); // grammar version, field mapping
    expect(obj.evidenceChain.typecheck).toBeDefined(); // validation, taxonomy coords
    expect(obj.evidenceChain.commit).toBeDefined(); // cell ID, storage adapter
  });
});
```

**T9**: Idempotent re-extraction
```typescript
test("Idempotent re-extraction creates patches, not duplicates", async () => {
  const stub = new StubFetchAdapter(mockPropertyMeResponses());
  
  // First run
  const result1 = await extractionPipeline.execute({...});
  const firstCommitCount = result1.objects.length;
  
  // Second run (same data)
  const result2 = await extractionPipeline.execute({...});
  const secondCommitCount = result2.objects.filter(o => !o.isPatch).length;
  
  expect(secondCommitCount).toBe(0); // no new objects
  expect(result2.objects.filter(o => o.isPatch).length).toBeGreaterThan(0); // patches created
});
```

**T10**: ConsumerBinding with mock credentials
```typescript
test("ConsumerBinding creation with mock credentials passes L1 constraints", () => {
  const binding = createTestConsumerBinding("com.semantos.propertyme", {
    client_id: "test-id",
    client_secret: "test-secret",
    tenant_id: "test-tenant"
  });
  
  const validation = validateConsumerBinding(binding);
  expect(validation.valid).toBe(true);
  expect(validation.errors).toHaveLength(0);
});
```

**T11**: Governance validation
```typescript
test("Governance setup validates against L0 policy", () => {
  const governance = loadGovernanceSync("configs/extensions/propertyme/governance.json");
  
  const validation = validateExtensionManifest(governance.manifest);
  expect(validation.valid).toBe(true);
  
  const l0Validation = validateGovernancePolicy(governance.policy);
  expect(l0Validation.valid).toBe(true);
});
```

**T12**: Shell commands
```typescript
test("Shell commands work: semantos extract propertyme --dry-run", async () => {
  const result = await runShellCommand("semantos extract propertyme --dry-run", {
    grammar: "configs/extensions/propertyme/grammar.json",
    binding: createTestConsumerBinding("com.semantos.propertyme")
  });
  
  expect(result.exitCode).toBe(0);
  expect(result.stdout).toContain("Dry run: would commit");
});
```

**T13**: Incremental extraction (--since)
```typescript
test("Incremental extraction (--since) fetches only updated records", async () => {
  const timestamp = new Date("2024-03-01T00:00:00Z");
  
  const result = await runShellCommand("semantos extract propertyme --since 2024-03-01", {
    grammar: "configs/extensions/propertyme/grammar.json",
    binding: createTestConsumerBinding("com.semantos.propertyme")
  });
  
  // Verify the stub adapter received --since parameter
  expect(result.fetchedRecords).toBeLessThan(result.totalRecords);
});
```

**T14**: Error handling
```typescript
test("Error handling: 429 → retry, 401 → refresh, 400 → skip", async () => {
  const stub = new StubFetchAdapter(mockResponsesWithErrors());
  
  // T14a: 429 rate limit → retry
  const result429 = await extractionPipeline.execute({adapter: stub, ...});
  expect(result429.retries).toBeGreaterThan(0);
  expect(result429.success).toBe(true);
  
  // T14b: 401 auth error → refresh token
  const result401 = await extractionPipeline.execute({adapter: stub, ...});
  expect(result401.tokenRefreshAttempts).toBeGreaterThan(0);
  
  // T14c: 400 validation error → skip
  const result400 = await extractionPipeline.execute({adapter: stub, ...});
  expect(result400.skippedRecords).toBeGreaterThan(0);
  expect(result400.objects.length).toBeLessThan(result400.totalApiRecords);
});
```

### 6.2 Run tests

```bash
bun test phase36f-propertyme-connector.test.ts
```

All 14 tests must pass.

Commit: `phase-36f/D36F.6: add 14 end-to-end integration tests with StubFetchAdapter`

---

## Step 7: Write Developer Guide (D36F.7)

### 7.1 Create developer documentation

File: `configs/extensions/propertyme/DEVELOPER-GUIDE.md`

Comprehensive walkthrough for third-party developers. Sections (use PropertyMe as reference examples in every section):

1. **Overview** — what a connector is, three purposes (validation, reference, revenue), ecosystem context
2. **Building an Extension Grammar JSON** — complete walkthrough of PropertyMe grammar, explaining each top-level section, source entity definitions, pagination config, OAuth2 setup
3. **Entity Mapping** — how to map source API fields to semantic object payloads, with PropertyMe examples (Property → property.dwelling, Lease → property.lease with relationship resolution)
4. **Field Transforms** — detailed guide to each transform type (concat, split, lookup, template, enum_map, compute) with PropertyMe real examples:
   - Address composition (concat)
   - Cost calculation (compute)
   - Status mapping (enum_map)
   - Date normalization (coerce)
5. **Object Types & Linearity** — linearity assignments (RELEVANT, LINEAR, AFFINE) explained via PropertyMe objects (Property = RELEVANT, Lease = LINEAR, MaintenanceRequest = AFFINE), why each matters
6. **Commerce Phases & FSM Transitions** — MaintenanceRequest FSM as detailed example (9 states mapping to Semantos phases), phase guards, state transitions
7. **Fetch Configuration** — OAuth2 token flow (client_id, client_secret, tenant_id), pagination (cursor-based), rate limits (100 req/min PropertyMe), error handling (429, 401, 400, 404)
8. **Governance & Publishing** — creating ConsumerBinding, governance validation, versioning strategy (major vs. minor), publishing to marketplace
9. **Testing** — writing tests with StubFetchAdapter, mocking API responses, test patterns from Phase 36F
10. **Shell Commands** — `semantos extract propertyme`, `--dry-run`, `--since` for incremental extraction, debugging with `--verbose`
11. **Common Patterns** — address composition, cost/currency normalization, date format handling, polymorphic entities (Document with parent_id + parent_type), relationship resolution across entities
12. **Pitfalls & Anti-Patterns** — don't hardcode transforms in pipeline code, don't skip field mappings, don't forget relationships, don't ignore error handling, don't write imperative code in the grammar

Every section references actual PropertyMe code/grammar/tests. Developers copy examples; be specific.

### 7.2 Cross-reference with spec

Link back to:
- Phase 36A grammar schema
- Phase 36B extraction pipeline
- Phase 36D governance model
- Phase 36F gate tests

Commit: `phase-36f/D36F.7: write comprehensive developer guide with PropertyMe examples`

---

## Step 8: Final Verification

### 8.1 Type check and build

```bash
bun run check
bun run build
```

Both must succeed with zero errors.

### 8.2 Full test suite

```bash
bun test
```

All tests must pass, including the 14 Phase 36F gate tests and all existing gate tests from prior phases.

### 8.3 Completeness scan

```bash
# Verify all deliverables exist
ls configs/extensions/propertyme/grammar.json
ls configs/extensions/propertyme/types.json
ls configs/extensions/propertyme/fetch-adapter.json
ls packages/protocol-types/src/adapters/propertyme-field-transforms.ts
ls packages/protocol-types/src/adapters/propertyme-fetch-adapter.ts
ls configs/extensions/propertyme/governance.json
ls packages/__tests__/phase36f-propertyme-connector.test.ts
ls configs/extensions/propertyme/DEVELOPER-GUIDE.md
```

All files must exist.

### 8.4 Grammar inspection

```bash
semantos grammar inspect com.semantos.propertyme
```

Output must show:
- 11 source entities (Property, Lease, Tenant, Owner, MaintenanceRequest, Inspection, Document, Contact, Invoice, Receipt, OwnerStatement)
- 11 object types
- 11 entity mappings
- All field transforms declared

### 8.5 Documentation completeness

Verify `DEVELOPER-GUIDE.md`:
- 12 sections complete
- Every pattern references PropertyMe implementation
- Shell commands documented with examples
- Test patterns from Phase 36F referenced
- Pitfalls section includes 5+ anti-patterns

Commit: `phase-36f/D36F: final verification — all deliverables complete, tests passing, docs written`

---

## Step 9: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. **Adversarial grammar review** — check the PropertyMe grammar for inconsistencies, missing fields, undefined entity references
2. **Relationship integrity** — verify all foreign key references resolve, no dangling relationships
3. **Field transform validation** — test each transform type (concat, compute, enum_map, coerce) with real PropertyMe data shapes
4. **Evidence chain audit** — randomly sample 3 extracted objects, verify evidence chain structure and completeness
5. **Developer guide accuracy** — copy-paste a PropertyMe grammar code block from the guide, validate it
6. **Test isolation** — run tests in random order, verify no test pollution or shared state
7. **Error message clarity** — trigger intentional errors (bad grammar, missing credentials), verify error messages are developer-friendly
8. **Shell command coverage** — test `semantos extract propertyme --dry-run`, `--since`, `--verbose`, with various binding configs

Write errata doc: `docs/prd/PHASE-36F-ERRATA.md` with findings, changes made, and unresolved items.

---

## Completion Criteria

- [ ] PropertyMe Extension Grammar (`configs/extensions/propertyme/grammar.json`) complete with 11 entities, all field mappings, taxonomy coordinates
- [ ] Grammar validates via `validateExtensionGrammar()` with zero errors
- [ ] PropertyMe types config defines all 11 object types with correct linearity (RELEVANT, LINEAR, AFFINE)
- [ ] Fetch adapter config declares OAuth2, pagination, rate limits, error handling, webhooks
- [ ] All 4 field transform types implemented and tested (concat, compute, enum_map, coerce)
- [ ] Governance config passes L0/L1/L2 validation
- [ ] Tests T1–T14 all pass
- [ ] Developer guide complete with 12 sections and PropertyMe examples throughout
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] `bun test` passes (all 14 phase36f tests + all existing tests)
- [ ] Shell commands work: `semantos extract propertyme --dry-run`, `--since`, `--verbose`
- [ ] All commits follow `phase-36f/D36F.N:` naming convention
- [ ] Branch is `phase-36f-connector-reference-impl`
- [ ] Errata sprint complete with `docs/prd/PHASE-36F-ERRATA.md`

---

## What NOT to Do

- **Don't write `if (grammarId === 'com.semantos.propertyme')` in the pipeline.** The pipeline is generic. PropertyMe-specific behavior lives in the grammar.
- **Don't skip entities.** All 11 must be mapped. Partial coverage means the reference is incomplete.
- **Don't hardcode transforms.** Transforms are declarative. If you write TypeScript functions for address composition, you've failed.
- **Don't mock the grammar in tests.** Use the real grammar.json at runtime. Only mock API responses.
- **Don't skip relationships.** Leases reference Properties. MaintenanceRequests reference both. All must be declared and resolved.
- **Don't assume governance exemptions.** First-party extensions go through the same validation as third-party connectors.
- **Don't write vague developer guidance.** Every example must be real code from the PropertyMe implementation.
- **Don't test against live PropertyMe API.** Use StubFetchAdapter exclusively. Tests must be deterministic and repeatable.

---

## Next Phase

Phase 36E builds the Extension Manager UI in the loom: marketplace registry (browse, search, install), extension lifecycle (update, remove, disable), governance dashboard (author policies, L2 binding constraints), version compatibility matrix, trust signals (Glow weight, object count, version history). PropertyMe connector ships with the UI. Third-party developers can browse, install, and configure extensions via the UI.

Phase 36F proves the framework works end-to-end. Phase 36E makes it user-facing.
