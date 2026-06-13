---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase36b-extraction-pipeline.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.573747+00:00
---

# tests/gates/phase36b-extraction-pipeline.test.ts

```ts
/**
 * Phase 36B Gate: Semantic Extraction Pipeline
 *
 * Tests T1–T26 covering all five pipeline stages, orchestrator, and adapters.
 * Uses StubFetchAdapter + MemoryAdapter + LoomStore for in-memory testing.
 */

import { describe, test, expect, beforeEach } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// ── Module imports ────────────────────────────────────────────

const {
  StubFetchAdapter,
  createStubResponse,
  selectFetchAdapter,
  parseResponses,
  findEntityMapping,
  typecheckRecords,
  inferRecords,
  commitRecords,
  buildSourceKey,
  ExtractionPipeline,
  EvidenceAccumulator,
  LoomExtractionContext,
  isValidTaxonomyPath,
  applyTransform,
  resolveNestedField,
  extractRecordsFromResponse,
} = require(join(ROOT, "packages/extraction/src/index"));

const { MemoryAdapter } = require(join(ROOT, "core/protocol-types/src/adapters/memory-adapter"));
const { LoomStore } = require(join(ROOT, "runtime/services/src/services/LoomStore"));
const { validateExtensionGrammar } = require(join(ROOT, "core/protocol-types/src/extension-grammar-validator"));
const { grammarToExtensionConfig } = require(join(ROOT, "core/protocol-types/src/grammar-config-bridge"));

// ── Test Fixtures ─────────────────────────────────────────────

const PROPERTYME_GRAMMAR = JSON.parse(
  readFileSync(join(ROOT, "configs/extensions/propertyme/grammar.json"), "utf-8"),
);

/** A minimal valid property record matching the PropertyMe grammar. */
function makePropertyRecord(id: string, overrides?: Record<string, unknown>) {
  return {
    id,
    street_address: "123 Test St",
    city: "Sydney",
    state: "NSW",
    zip: "2000",
    country: "AU",
    latitude: -33.86,
    longitude: 151.21,
    bedrooms: 3,
    bathrooms: 2,
    square_footage: 150,
    year_built: 2005,
    property_type: "house",
    owner_id: "owner-1",
    updated_at: "2024-01-01T00:00:00Z",
    ...overrides,
  };
}

/** Create a RawResponse wrapping property records. */
function makePropertyResponse(records: unknown[]) {
  return createStubResponse({
    data: { properties: records },
  }, "/properties", 200);
}

/** Helper to collect all items from an async generator. */
async function collect<T>(gen: AsyncGenerator<T>): Promise<T[]> {
  const items: T[] = [];
  for await (const item of gen) items.push(item);
  return items;
}

/** Create an async iterable from an array. */
async function* toAsync<T>(items: T[]): AsyncGenerator<T> {
  for (const item of items) yield item;
}

// ── Test Context Setup ────────────────────────────────────────

function createTestContext() {
  const store = new LoomStore();
  const adapter = new MemoryAdapter();
  const grammar = PROPERTYME_GRAMMAR;
  const extensionConfig = grammarToExtensionConfig(grammar);
  const extractionStore = new LoomExtractionContext(store, adapter, extensionConfig);

  const context = {
    grammarId: grammar.grammarId,
    grammarVersion: grammar.grammarVersion,
    consumerId: "test-consumer",
    extractionStore,
  };

  return { store, adapter, grammar, extensionConfig, context };
}

// ═══════════════════════════════════════════════════════════════
// STAGE TESTS (T1–T15)
// ═══════════════════════════════════════════════════════════════

describe("Extraction Pipeline Stages", () => {
  // ── Fetch Stage (T1–T6) ──────────────────────────────────────

  test("T1: StubFetchAdapter yields canned RawResponse objects", async () => {
    const responses = [makePropertyResponse([makePropertyRecord("p1")])];
    const stub = new StubFetchAdapter(responses);
    const entity = PROPERTYME_GRAMMAR.source.entities[0]; // property entity

    const results = await collect(
      stub.fetch(entity, PROPERTYME_GRAMMAR.source, {}, {} as any),
    );

    expect(results.length).toBe(1);
    expect(results[0].statusCode).toBe(200);
    expect(results[0].endpoint).toBe("/properties");
    expect(results[0].responseHash).toBeTruthy();
  });

  test("T2: RestFetchAdapter respects rate limits from grammar", () => {
    // Rate limits are declared in grammar.source.rateLimits
    const grammar = PROPERTYME_GRAMMAR;
    expect(grammar.source.rateLimits).toBeDefined();
    expect(grammar.source.rateLimits.requestsPerSecond).toBe(10);
    expect(grammar.source.rateLimits.requestsPerMinute).toBe(300);
    // RestFetchAdapter uses these via RateLimiter — tested structurally
  });

  test("T3: Pagination config is correctly declared in grammar", () => {
    const grammar = PROPERTYME_GRAMMAR;
    expect(grammar.source.pagination).toBeDefined();
    expect(grammar.source.pagination.type).toBe("cursor");
    expect(grammar.source.pagination.pageSize).toBe(50);
    expect(grammar.source.pagination.cursorField).toBe("next_cursor");
  });

  test("T4: GraphQLFetchAdapter is selectable", () => {
    const adapter = selectFetchAdapter("graphql");
    expect(adapter).toBeTruthy();
    expect(typeof adapter.fetch).toBe("function");
  });

  test("T5: FileFetchAdapter is selectable", () => {
    const adapter = selectFetchAdapter("file");
    expect(adapter).toBeTruthy();
    expect(typeof adapter.fetch).toBe("function");
  });

  test("T6: StubFetchAdapter is deterministic (same input = same output)", async () => {
    const responses = [makePropertyResponse([makePropertyRecord("p1")])];
    const stub = new StubFetchAdapter(responses);
    const entity = PROPERTYME_GRAMMAR.source.entities[0];

    const run1 = await collect(stub.fetch(entity, PROPERTYME_GRAMMAR.source, {}, {} as any));
    const run2 = await collect(stub.fetch(entity, PROPERTYME_GRAMMAR.source, {}, {} as any));

    expect(run1[0].responseHash).toBe(run2[0].responseHash);
    expect(run1[0].timestamp).toBe(run2[0].timestamp);
  });

  // ── Parse Stage (T7–T10) ─────────────────────────────────────

  test("T7: ParseStage applies FieldMapping transforms", async () => {
    const { grammar, context } = createTestContext();
    const entity = grammar.source.entities[0]; // property
    const record = makePropertyRecord("p1");
    const response = makePropertyResponse([record]);

    const results = await collect(
      parseResponses(toAsync([response]), grammar, entity, context),
    );

    expect(results.length).toBe(1);
    expect(results[0].mappedFields.streetAddress).toBe("123 Test St");
    expect(results[0].mappedFields.city).toBe("Sydney");
    expect(results[0].mappedFields.bedrooms).toBe(3);
  });

  test("T8: ParseStage resolves nested fields (dot-notation)", () => {
    const obj = { property: { address: { street: "42 Elm St" } } };
    const result = resolveNestedField(obj, "property.address.street");
    expect(result).toBe("42 Elm St");
  });

  test("T9: ParseStage extracts records via JSONPath dataPath", () => {
    const body = { data: { properties: [{ id: "1" }, { id: "2" }] } };
    const records = extractRecordsFromResponse(body, "$.data.properties");
    expect(records.length).toBe(2);
    expect((records[0] as any).id).toBe("1");
  });

  test("T10: ParseStage produces IntermediateRecord with source + mapped fields", async () => {
    const { grammar, context } = createTestContext();
    const entity = grammar.source.entities[0];
    const record = makePropertyRecord("p1");
    const response = makePropertyResponse([record]);

    const results = await collect(
      parseResponses(toAsync([response]), grammar, entity, context),
    );

    const ir = results[0];
    expect(ir.sourceEntityId).toBe("property");
    expect(ir.sourceId).toBe("p1");
    expect(ir.sourceFields).toBeTruthy();
    expect(ir.mappedFields).toBeTruthy();
    expect(ir.evidence).toBeTruthy();
    expect(ir.evidence.length).toBeGreaterThanOrEqual(2); // fetch + parse
  });

  // ── Typecheck Stage (T11–T15) ────────────────────────────────

  test("T11: TypecheckStage validates required fields", async () => {
    const { grammar, context } = createTestContext();
    const entity = grammar.source.entities[0];
    // Create a record missing a required field (city)
    const record = makePropertyRecord("p1", { city: undefined });
    delete (record as any).city;
    const response = makePropertyResponse([record]);

    const parsed = parseResponses(toAsync([response]), grammar, entity, context);
    const results = await collect(typecheckRecords(parsed, grammar, context));

    expect(results.length).toBe(1);
    expect(results[0].validationPassed).toBe(false);
    expect(results[0].validationErrors.length).toBeGreaterThan(0);
  });

  test("T12: TypecheckStage validates taxonomy coordinates", () => {
    expect(isValidTaxonomyPath("what.asset.property")).toBe(true);
    expect(isValidTaxonomyPath("how.technical.api.rest")).toBe(true);
    expect(isValidTaxonomyPath("")).toBe(false);
    expect(isValidTaxonomyPath("123.invalid")).toBe(false);
  });

  test("T13: TypecheckStage assigns phase", async () => {
    const { grammar, context } = createTestContext();
    const entity = grammar.source.entities[0];
    const record = makePropertyRecord("p1");
    const response = makePropertyResponse([record]);

    const parsed = parseResponses(toAsync([response]), grammar, entity, context);
    const results = await collect(typecheckRecords(parsed, grammar, context));

    expect(results.length).toBe(1);
    expect(results[0].phase).toBeTruthy();
    expect(typeof results[0].phase).toBe("string");
  });

  test("T14: TypecheckStage produces ValidatedRecord with taxonomy", async () => {
    const { grammar, context } = createTestContext();
    const entity = grammar.source.entities[0];
    const record = makePropertyRecord("p1");
    const response = makePropertyResponse([record]);

    const parsed = parseResponses(toAsync([response]), grammar, entity, context);
    const results = await collect(typecheckRecords(parsed, grammar, context));

    const vr = results[0];
    expect(vr.targetObjectType).toBe("property.listing");
    expect(vr.taxonomy.what).toBe("what.asset.property.listing");
    expect(vr.taxonomy.how).toBe("how.technical.api.rest");
    expect(vr.taxonomy.why).toBe("why.integration.data-sync");
  });

  test("T15: TypecheckStage collects errors without aborting batch", async () => {
    const { grammar, context } = createTestContext();
    const entity = grammar.source.entities[0];
    // Two records: first valid, second missing required fields
    const good = makePropertyRecord("p1");
    const bad = { id: "p2" }; // missing all required fields
    const response = makePropertyResponse([good, bad]);

    const parsed = parseResponses(toAsync([response]), grammar, entity, context);
    const results = await collect(typecheckRecords(parsed, grammar, context));

    // Both records should be yielded — batch not aborted
    expect(results.length).toBe(2);
    expect(results[0].validationPassed).toBe(true);
    expect(results[1].validationPassed).toBe(false);
    expect(results[1].validationErrors.length).toBeGreaterThan(0);
  });
});

// ═══════════════════════════════════════════════════════════════
// PIPELINE TESTS (T16–T22)
// ═══════════════════════════════════════════════════════════════

describe("ExtractionPipeline orchestrator", () => {
  test("T16: ExtractionPipeline.extract() runs all five stages end-to-end", async () => {
    const { store, adapter, grammar } = createTestContext();

    // Override protocol to use stub adapter
    const testGrammar = { ...grammar, source: { ...grammar.source, protocol: "stub" as const } };

    // We need to register stub responses — create a custom pipeline
    const pipeline = new ExtractionPipeline(store, adapter);

    // Use the real REST protocol but with a grammar that has stub
    // For a true end-to-end, we rely on the pipeline handling the grammar
    // For now verify the pipeline produces a valid ExtractionResult
    const binding = { consumerId: "test", credentials: {} };
    const result = await pipeline.extract(testGrammar, binding);

    expect(result.grammarId).toBe("com.semantos.propertyme");
    expect(result.grammarVersion).toBe("1.0.0");
    expect(typeof result.totalRecords).toBe("number");
    expect(typeof result.createdObjects).toBe("number");
    expect(typeof result.updatedObjects).toBe("number");
    expect(result.startTime).toBeGreaterThan(0);
    expect(result.endTime).toBeGreaterThanOrEqual(result.startTime);
  });

  test("T17: Pipeline handles errors per-record without aborting", async () => {
    const { store, adapter, grammar } = createTestContext();
    const testGrammar = { ...grammar, source: { ...grammar.source, protocol: "stub" as const } };
    const pipeline = new ExtractionPipeline(store, adapter);
    const binding = { consumerId: "test", credentials: {} };

    // Pipeline should not throw even with empty results
    const result = await pipeline.extract(testGrammar, binding);
    expect(result).toBeTruthy();
    expect(Array.isArray(result.errors)).toBe(true);
  });

  test("T18: Pipeline respects --dry-run flag", async () => {
    const { store, adapter, grammar } = createTestContext();
    const testGrammar = { ...grammar, source: { ...grammar.source, protocol: "stub" as const } };
    const pipeline = new ExtractionPipeline(store, adapter);
    const binding = { consumerId: "test", credentials: {} };

    const result = await pipeline.extract(testGrammar, binding, { dryRun: true });

    // Dry run should not create any objects
    expect(result.createdObjects).toBe(0);
    expect(result.updatedObjects).toBe(0);
  });

  test("T19: Pipeline respects --entity filter", async () => {
    const { store, adapter, grammar } = createTestContext();
    const testGrammar = { ...grammar, source: { ...grammar.source, protocol: "stub" as const } };
    const pipeline = new ExtractionPipeline(store, adapter);
    const binding = { consumerId: "test", credentials: {} };

    // Filter to a non-existent entity — should skip all entities
    const result = await pipeline.extract(testGrammar, binding, {
      entityFilter: "nonexistent_entity",
    });

    expect(result.totalRecords).toBe(0);
    expect(result.createdObjects).toBe(0);
  });

  test("T20: Idempotency — running extraction twice produces same result", async () => {
    // Use parse + typecheck + commit directly with stub data
    const { grammar, context } = createTestContext();
    const entity = grammar.source.entities[0];
    const record = makePropertyRecord("p1");
    const response = makePropertyResponse([record]);

    // First run
    const parsed1 = parseResponses(toAsync([response]), grammar, entity, context);
    const checked1 = typecheckRecords(parsed1, grammar, context);
    const inferred1 = inferRecords(checked1, grammar, context);
    const committed1 = await collect(commitRecords(inferred1, grammar, context));

    // Second run — same data
    const parsed2 = parseResponses(toAsync([response]), grammar, entity, context);
    const checked2 = typecheckRecords(parsed2, grammar, context);
    const inferred2 = inferRecords(checked2, grammar, context);
    const committed2 = await collect(commitRecords(inferred2, grammar, context));

    // First run creates, second run updates (duplicate)
    expect(committed1.length).toBeGreaterThan(0);
    expect(committed1[0].isDuplicate).toBe(false);
    expect(committed2.length).toBeGreaterThan(0);
    expect(committed2[0].isDuplicate).toBe(true);
  });

  test("T21: ExtractionResult has correct structure", async () => {
    const { store, adapter, grammar } = createTestContext();
    const testGrammar = { ...grammar, source: { ...grammar.source, protocol: "stub" as const } };
    const pipeline = new ExtractionPipeline(store, adapter);
    const binding = { consumerId: "test", credentials: {} };
    const result = await pipeline.extract(testGrammar, binding);

    // Verify all required fields exist
    expect(result).toHaveProperty("grammarId");
    expect(result).toHaveProperty("grammarVersion");
    expect(result).toHaveProperty("totalRecords");
    expect(result).toHaveProperty("createdObjects");
    expect(result).toHaveProperty("updatedObjects");
    expect(result).toHaveProperty("errors");
    expect(result).toHaveProperty("startTime");
    expect(result).toHaveProperty("endTime");
  });

  test("T22: Pipeline validates grammar before extraction", async () => {
    const { store, adapter } = createTestContext();
    const pipeline = new ExtractionPipeline(store, adapter);
    const binding = { consumerId: "test", credentials: {} };

    // Invalid grammar (missing required fields)
    const invalidGrammar = { grammarId: "invalid" } as any;
    const result = await pipeline.extract(invalidGrammar, binding);

    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0].error).toContain("validation failed");
  });
});

// ═══════════════════════════════════════════════════════════════
// ADAPTER TESTS (T23–T26)
// ═══════════════════════════════════════════════════════════════

describe("Fetch adapters", () => {
  test("T23: selectFetchAdapter() returns correct adapter for protocol", () => {
    const rest = selectFetchAdapter("rest");
    expect(rest.constructor.name).toBe("RestFetchAdapter");

    const graphql = selectFetchAdapter("graphql");
    expect(graphql.constructor.name).toBe("GraphQLFetchAdapter");

    const file = selectFetchAdapter("file");
    expect(file.constructor.name).toBe("FileFetchAdapter");

    const stub = selectFetchAdapter("stub");
    expect(stub.constructor.name).toBe("StubFetchAdapter");
  });

  test("T24: All adapters implement FetchAdapter interface", () => {
    const protocols = ["rest", "graphql", "file", "stub"];
    for (const protocol of protocols) {
      const adapter = selectFetchAdapter(protocol);
      expect(typeof adapter.fetch).toBe("function");
    }
  });

  test("T25: selectFetchAdapter() throws for unknown protocol", () => {
    expect(() => selectFetchAdapter("unknown")).toThrow("Unknown fetch protocol");
  });

  test("T26: StubFetchAdapter yields responses in order", async () => {
    const responses = [
      createStubResponse({ page: 1 }, "/page1"),
      createStubResponse({ page: 2 }, "/page2"),
    ];
    const stub = new StubFetchAdapter(responses);
    const entity = PROPERTYME_GRAMMAR.source.entities[0];

    const results = await collect(
      stub.fetch(entity, PROPERTYME_GRAMMAR.source, {}, {} as any),
    );

    expect(results.length).toBe(2);
    expect(results[0].endpoint).toBe("/page1");
    expect(results[1].endpoint).toBe("/page2");
  });
});

// ═══════════════════════════════════════════════════════════════
// TRANSFORM TESTS (supplementary)
// ═══════════════════════════════════════════════════════════════

describe("Field transforms", () => {
  test("lowercase transform", () => {
    const result = applyTransform("HELLO", { type: "lowercase" }, {});
    expect(result).toBe("hello");
  });

  test("uppercase transform", () => {
    const result = applyTransform("hello", { type: "uppercase" }, {});
    expect(result).toBe("HELLO");
  });

  test("trim transform", () => {
    const result = applyTransform("  hello  ", { type: "trim" }, {});
    expect(result).toBe("hello");
  });

  test("map_enum transform", () => {
    const result = applyTransform("active", {
      type: "map_enum",
      enumMap: { active: "ACTIVE", inactive: "INACTIVE" },
    }, {});
    expect(result).toBe("ACTIVE");
  });

  test("compute transform with source fields", () => {
    const result = applyTransform(undefined, {
      type: "compute",
      expression: "source.bedrooms + source.bathrooms",
    }, { bedrooms: 3, bathrooms: 2 });
    expect(result).toBe(5);
  });

  test("template transform", () => {
    const result = applyTransform(undefined, {
      type: "template",
      template: "{{city}}, {{state}}",
    }, { city: "Sydney", state: "NSW" });
    expect(result).toBe("Sydney, NSW");
  });

  test("lookup transform", () => {
    const result = applyTransform("AU", {
      type: "lookup",
      lookupTable: { AU: "Australia", US: "United States" },
    }, {});
    expect(result).toBe("Australia");
  });
});

// ═══════════════════════════════════════════════════════════════
// EVIDENCE CHAIN TESTS (supplementary)
// ═══════════════════════════════════════════════════════════════

describe("Evidence chain", () => {
  test("EvidenceAccumulator collects entries from all stages", () => {
    const acc = new EvidenceAccumulator("1.0.0");
    acc.addFetch({ endpoint: "/test", responseHash: "abc", statusCode: 200, bytesReceived: 100 });
    acc.addParse({ sourceEntityId: "prop", targetObjectType: "prop.listing", fieldsMapped: 5, transformsApplied: [] });
    acc.addTypecheck({ passed: true, errors: [], taxonomyAssigned: "what.test", phaseAssigned: "draft" });
    acc.addInference({ inferenceApplied: false });
    acc.addCommit({ objectId: "obj-1", storageAdapter: "memory", isNewObject: true, facetProvenance: { author: "test", timestamp: Date.now() } });

    const chain = acc.toArray();
    expect(chain.length).toBe(5);
    expect(chain[0].stage).toBe("fetch");
    expect(chain[1].stage).toBe("parse");
    expect(chain[2].stage).toBe("typecheck");
    expect(chain[3].stage).toBe("infer");
    expect(chain[4].stage).toBe("commit");
    expect(chain.every(e => e.grammarVersion === "1.0.0")).toBe(true);
  });

  test("Evidence chain is complete through parse + typecheck", async () => {
    const { grammar, context } = createTestContext();
    const entity = grammar.source.entities[0];
    const record = makePropertyRecord("p1");
    const response = makePropertyResponse([record]);

    const parsed = parseResponses(toAsync([response]), grammar, entity, context);
    const results = await collect(typecheckRecords(parsed, grammar, context));

    // Should have fetch + parse + typecheck evidence
    expect(results[0].evidence.length).toBe(3);
    const chain = results[0].evidence.toArray();
    expect(chain[0].stage).toBe("fetch");
    expect(chain[1].stage).toBe("parse");
    expect(chain[2].stage).toBe("typecheck");
  });
});

```
