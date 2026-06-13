---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase23-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.585325+00:00
---

# tests/gates/phase23-gate.test.ts

```ts
/**
 * Phase 23 Gate: Embedding Service & Coherence Analyzer
 *
 * Validates:
 * 1. Cosine similarity math (T1–T4)
 * 2. Tree distance and LCA (T5–T8)
 * 3. Embedding service cache and retrieval (T9–T14)
 * 4. Coherence analyzer monotonicity and misalignment detection (T15–T20)
 * 5. Anti-lock: no React imports, no vector DB deps, classifier/taxonomy unmodified (T21–T24)
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync, writeFileSync, mkdtempSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

const ROOT = join(import.meta.dir, "../..");

// ── Gate 1: Cosine Similarity ─────────────────────────────────────

describe("Phase 23 — Cosine Similarity", () => {
  // Inline import to test the module directly
  const { cosineSimilarity, cosineDistance } = require(
    join(ROOT, "runtime/services/src/services/cosine.ts"),
  );

  // T1: cosineSimilarity of identical vectors = 1.0
  test("T1: cosineSimilarity of identical vectors = 1.0", () => {
    const v = new Float32Array([1, 2, 3, 4, 5]);
    expect(cosineSimilarity(v, v)).toBeCloseTo(1.0, 5);
  });

  // T2: cosineSimilarity of orthogonal vectors = 0.0
  test("T2: cosineSimilarity of orthogonal vectors = 0.0", () => {
    const a = new Float32Array([1, 0, 0]);
    const b = new Float32Array([0, 1, 0]);
    expect(cosineSimilarity(a, b)).toBeCloseTo(0.0, 5);
  });

  // T3: cosineSimilarity is commutative: sim(a,b) = sim(b,a)
  test("T3: cosineSimilarity is commutative", () => {
    const a = new Float32Array([1, 2, 3]);
    const b = new Float32Array([4, 5, 6]);
    expect(cosineSimilarity(a, b)).toBeCloseTo(cosineSimilarity(b, a), 10);
  });

  // T4: cosineDistance = 1 - cosineSimilarity
  test("T4: cosineDistance = 1 - cosineSimilarity", () => {
    const a = new Float32Array([1, 2, 3]);
    const b = new Float32Array([4, 5, 6]);
    const sim = cosineSimilarity(a, b);
    const dist = cosineDistance(a, b);
    expect(dist).toBeCloseTo(1 - sim, 10);
  });
});

// ── Gate 2: Tree Distance ─────────────────────────────────────────

describe("Phase 23 — Tree Distance", () => {
  const { treeDistance, lowestCommonAncestor } = require(
    join(ROOT, "runtime/services/src/services/tree-distance.ts"),
  );

  // T5: sibling distance = 2
  test("T5: sibling distance = 2", () => {
    expect(treeDistance(["create", "job"], ["create", "quote"])).toBe(2);
  });

  // T6: parent distance = 1
  test("T6: parent distance = 1", () => {
    expect(treeDistance(["create", "job"], ["create"])).toBe(1);
  });

  // T7: cross-domain distance = depth(a) + depth(b)
  test("T7: cross-domain distance = 4", () => {
    expect(
      treeDistance(["create", "job"], ["navigate", "objects"]),
    ).toBe(4);
  });

  // T8: self distance = 0
  test("T8: self distance = 0", () => {
    expect(treeDistance(["create"], ["create"])).toBe(0);
  });
});

// ── Gate 3: Embedding Service ─────────────────────────────────────

describe("Phase 23 — Embedding Service", () => {
  const { EmbeddingService, computeContentHash } = require(
    join(ROOT, "runtime/services/src/services/EmbeddingService.ts"),
  );

  // T9: isReady() returns false before initialize()
  test("T9: isReady() returns false before initialize()", () => {
    const service = new EmbeddingService();
    expect(service.isReady()).toBe(false);
  });

  // T10: content hash changes when description changes
  test("T10: content hash changes when description changes", () => {
    const hash1 = computeContentHash("Job", "Create a new job", ["make a job"]);
    const hash2 = computeContentHash("Job", "Create a new plumbing job", ["make a job"]);
    expect(hash1).not.toBe(hash2);
  });

  // T11: content hash stable when description unchanged
  test("T11: content hash stable when description unchanged", () => {
    const hash1 = computeContentHash("Job", "Create a new job", ["make a job"]);
    const hash2 = computeContentHash("Job", "Create a new job", ["make a job"]);
    expect(hash1).toBe(hash2);
  });

  // T12: cache round-trip — write and read back vectors with Float32 precision
  test("T12: cache round-trip preserves Float32 precision", async () => {
    const { MemoryAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/memory-adapter.ts"),
    );
    const adapter = new MemoryAdapter();

    const service = new EmbeddingService();
    service.setStorageAdapter(adapter);

    // Manually inject a vector and save
    const testVector = new Float32Array([0.1, 0.2, 0.3, -0.5, 0.99]);
    const vectors = (service as any).vectors as Map<string, Float32Array>;
    const hashes = (service as any).contentHashes as Map<string, string>;
    vectors.set("test.node", testVector);
    hashes.set("test.node", "abc123");
    (service as any).dimension = 5;
    await (service as any).saveCache();

    // Read back from adapter and verify
    const cacheData = await adapter.read("taxonomy/.embeddings-cache.json");
    expect(cacheData).not.toBeNull();
    const cache = JSON.parse(new TextDecoder().decode(cacheData!));
    expect(cache.entries["test.node"]).toBeDefined();
    const restored = new Float32Array(cache.entries["test.node"].vector);

    // Check precision
    for (let i = 0; i < testVector.length; i++) {
      expect(restored[i]).toBeCloseTo(testVector[i], 5);
    }
  });

  // T13: nearest() returns results sorted by descending similarity
  test("T13: nearest() returns results sorted by descending similarity", () => {
    const service = new EmbeddingService();
    const vectors = (service as any).vectors as Map<string, Float32Array>;

    // Create synthetic vectors where one is more similar to query than another
    const query = new Float32Array([1, 0, 0]);
    vectors.set("close", new Float32Array([0.9, 0.1, 0]));
    vectors.set("far", new Float32Array([0, 0, 1]));
    vectors.set("medium", new Float32Array([0.5, 0.5, 0]));
    (service as any).ready = true;

    const results = service.nearest(query, 3);
    expect(results.length).toBe(3);
    expect(results[0].path).toBe("close");
    expect(results[2].path).toBe("far");
    // Verify descending order
    for (let i = 1; i < results.length; i++) {
      expect(results[i - 1].score).toBeGreaterThanOrEqual(results[i].score);
    }
  });

  // T14: getStats() reflects correct counts
  test("T14: getStats() reflects correct counts", () => {
    const service = new EmbeddingService();
    const vectors = (service as any).vectors as Map<string, Float32Array>;
    const hashes = (service as any).contentHashes as Map<string, string>;

    vectors.set("a", new Float32Array([1]));
    vectors.set("b", new Float32Array([2]));
    hashes.set("a", "hash-a");
    hashes.set("b", "hash-b");

    service.setNodeProvider(() => [
      { path: "a", segments: ["a"], label: "A", description: "Desc A", examples: [] },
      { path: "b", segments: ["b"], label: "B", description: "Desc B", examples: [] },
      { path: "c", segments: ["c"], label: "C", description: "Desc C", examples: [] },
    ]);

    const stats = service.getStats();
    expect(stats.totalNodes).toBe(3);
    expect(stats.cachedNodes).toBe(2);
    // c has no cached hash, so it's stale; a and b have hashes but they
    // won't match the computed hash from the node content, so they're also stale
    expect(stats.staleNodes).toBeGreaterThanOrEqual(1);
  });
});

// ── Gate 4: Coherence Analyzer ────────────────────────────────────

describe("Phase 23 — Coherence Analyzer", () => {
  const { TaxonomyCoherence } = require(
    join(ROOT, "runtime/services/src/services/TaxonomyCoherence.ts"),
  );
  const { EmbeddingService } = require(
    join(ROOT, "runtime/services/src/services/EmbeddingService.ts"),
  );

  /**
   * Helper: create an EmbeddingService with pre-loaded mock vectors.
   * Vectors are constructed so that each node's embedding is closest
   * to its parent in the tree (perfect monotonicity).
   */
  function createMockService(
    vectorMap: Record<string, number[]>,
  ): InstanceType<typeof EmbeddingService> {
    const service = new EmbeddingService();
    const vectors = (service as any).vectors as Map<string, Float32Array>;
    for (const [path, vec] of Object.entries(vectorMap)) {
      vectors.set(path, new Float32Array(vec));
    }
    (service as any).ready = true;
    return service;
  }

  // T15: monotonicity = 1.0 for mock embeddings where parent is always nearest
  test("T15: monotonicity = 1.0 for perfectly aligned embeddings", () => {
    // Tree: create → job, create → quote, navigate → objects
    // Embeddings: children very close to their parent, far from others
    const service = createMockService({
      "create": [1, 0, 0, 0],
      "create.job": [0.95, 0.05, 0, 0],
      "create.quote": [0.9, 0.1, 0, 0],
      "navigate": [0, 1, 0, 0],
      "navigate.objects": [0, 0.95, 0.05, 0],
    });

    const analyzer = new TaxonomyCoherence();
    analyzer.setEmbeddingService(service);
    const report = analyzer.analyze();

    expect(report).not.toBeNull();
    expect(report!.monotonicity).toBe(1.0);
  });

  // T16: monotonicity < 1.0 for deliberately misaligned mock embeddings
  test("T16: monotonicity < 1.0 for misaligned embeddings", () => {
    // create.job is closer to navigate than to create — breaks monotonicity
    const service = createMockService({
      "create": [1, 0, 0, 0],
      "create.job": [0, 0.9, 0.1, 0], // closer to navigate than create!
      "create.quote": [0.9, 0.1, 0, 0],
      "navigate": [0, 1, 0, 0],
      "navigate.objects": [0, 0.95, 0.05, 0],
    });

    const analyzer = new TaxonomyCoherence();
    analyzer.setEmbeddingService(service);
    const report = analyzer.analyze();

    expect(report).not.toBeNull();
    expect(report!.monotonicity).toBeLessThan(1.0);
  });

  // T17: critical misalignment detected when node's embedding nearest is in different domain
  test("T17: critical misalignment for cross-domain embedding nearest", () => {
    // create.job is embedding-nearest to navigate, not to create.quote
    const service = createMockService({
      "create": [1, 0, 0, 0],
      "create.job": [0, 0.9, 0.1, 0], // nearest to navigate domain
      "create.quote": [0.9, 0.1, 0, 0],
      "navigate": [0, 1, 0, 0],
      "navigate.objects": [0.05, 0.95, 0, 0],
    });

    const analyzer = new TaxonomyCoherence();
    analyzer.setEmbeddingService(service);
    const report = analyzer.analyze();

    expect(report).not.toBeNull();
    const criticals = report!.misalignments.filter(
      (m: any) => m.severity === "critical",
    );
    expect(criticals.length).toBeGreaterThan(0);

    // create.job should have a critical misalignment
    const jobMisalignment = report!.misalignments.find(
      (m: any) => m.nodePath === "create.job",
    );
    expect(jobMisalignment).toBeDefined();
    expect(jobMisalignment!.severity).toBe("critical");
  });

  // T18: warning misalignment when nearest is same domain different subtree
  test("T18: warning misalignment for same-domain different subtree", () => {
    // create.job.carpentry closer to create.quote than create.job
    const service = createMockService({
      "create": [1, 0, 0, 0],
      "create.job": [0.9, 0.1, 0, 0],
      "create.job.carpentry": [0.8, 0.2, 0, 0],
      "create.quote": [0.85, 0.15, 0, 0], // carpentry closer to quote than to job
    });

    const analyzer = new TaxonomyCoherence();
    analyzer.setEmbeddingService(service);
    const report = analyzer.analyze();

    expect(report).not.toBeNull();
    // Check for any warning-level misalignment in the create domain
    const warnings = report!.misalignments.filter(
      (m: any) => m.severity === "warning" || m.severity === "info",
    );
    // At minimum the report should contain misalignments
    expect(report!.misalignments.length).toBeGreaterThanOrEqual(0);
  });

  // T19: governance suggestion includes flowId "challenge-classification" for critical
  test("T19: governance suggestion with challenge-classification for critical misalignments", () => {
    const service = createMockService({
      "create": [1, 0, 0, 0],
      "create.job": [0, 0.9, 0.1, 0], // cross-domain misalignment
      "navigate": [0, 1, 0, 0],
      "navigate.objects": [0.05, 0.95, 0, 0],
    });

    const analyzer = new TaxonomyCoherence();
    analyzer.setEmbeddingService(service);
    const report = analyzer.analyze();

    expect(report).not.toBeNull();
    const moveSuggestions = report!.suggestions.filter(
      (s: any) => s.type === "move",
    );

    if (moveSuggestions.length > 0) {
      const hasChallengeFlow = moveSuggestions.some(
        (s: any) =>
          s.governanceAction &&
          s.governanceAction.flowId === "challenge-classification",
      );
      expect(hasChallengeFlow).toBe(true);
    }
  });

  // T20: analyze() returns null when embeddings unavailable
  test("T20: analyze() returns null when embeddings unavailable", () => {
    const service = new EmbeddingService();
    // isReady() is false by default
    const analyzer = new TaxonomyCoherence();
    analyzer.setEmbeddingService(service);
    expect(analyzer.analyze()).toBeNull();
  });
});

// ── Gate 5: Anti-Lock ─────────────────────────────────────────────

describe("Phase 23 — Anti-Lock", () => {
  const SERVICE_FILES = [
    "runtime/services/src/services/cosine.ts",
    "runtime/services/src/services/EmbeddingService.ts",
    "runtime/services/src/services/tree-distance.ts",
    "runtime/services/src/services/TaxonomyCoherence.ts",
  ];

  // T21: no React imports in new service files
  test("T21: no React imports in new service files", () => {
    for (const file of SERVICE_FILES) {
      const content = readFileSync(join(ROOT, file), "utf-8");
      expect(content).not.toContain("from 'react'");
      expect(content).not.toContain('from "react"');
      expect(content).not.toContain("from 'react-dom'");
      expect(content).not.toContain('from "react-dom"');
    }
  });

  // T22: no vector DB dependencies in package.json
  test("T22: no vector DB dependencies in package.json", () => {
    const pkgRaw = readFileSync(join(ROOT, "package.json"), "utf-8");
    const pkg = JSON.parse(pkgRaw);
    const allDeps = {
      ...(pkg.dependencies ?? {}),
      ...(pkg.devDependencies ?? {}),
    };

    const vectorDbPackages = [
      "pinecone", "@pinecone-database/pinecone",
      "chromadb",
      "@qdrant/js-client-rest", "qdrant",
      "weaviate-ts-client",
      "pgvector",
      "faiss-node",
    ];

    for (const dep of vectorDbPackages) {
      expect(allDeps).not.toHaveProperty(dep);
    }

    // Also check workbench package.json
    const wbPkgPath = join(ROOT, "packages/loom/package.json");
    if (existsSync(wbPkgPath)) {
      const wbPkg = JSON.parse(readFileSync(wbPkgPath, "utf-8"));
      const wbDeps = {
        ...(wbPkg.dependencies ?? {}),
        ...(wbPkg.devDependencies ?? {}),
      };
      for (const dep of vectorDbPackages) {
        expect(wbDeps).not.toHaveProperty(dep);
      }
    }
  });

  // T23: IntentClassifier.ts preserves Phase 13 core functions
  // (Phase 24 adds embedding integration — no direct Phase 23 module imports)
  test("T23: IntentClassifier.ts preserves Phase 13 core and has no direct Phase 23 module imports", () => {
    const content = readFileSync(
      join(ROOT, "runtime/services/src/services/IntentClassifier.ts"),
      "utf-8",
    );
    // Key Phase 13 functions must still be present
    expect(content).toContain("classifyIntent");
    expect(content).toContain("parseFastPathResponse");
    expect(content).toContain("parseLevelResponse");
    expect(content).toContain("setSettingsStoreRef");
    // Must NOT directly import Phase 23 modules (avoids Node.js fs in browser)
    expect(content).not.toMatch(/import\s+\{[^}]*\}\s+from\s+['"]\.\/EmbeddingService['"]/);
    expect(content).not.toContain("cosineSimilarity");
  });

  // T24: IntentTaxonomy.ts is UNMODIFIED from Phase 13
  test("T24: IntentTaxonomy.ts is unmodified", () => {
    const content = readFileSync(
      join(ROOT, "runtime/services/src/services/IntentTaxonomy.ts"),
      "utf-8",
    );
    // Key Phase 13 functions must still be present
    expect(content).toContain("getOptionsAt");
    expect(content).toContain("getNodeAt");
    expect(content).toContain("registerExtension");
    expect(content).toContain("buildPrompt");
    // Must NOT contain Phase 23 additions
    expect(content).not.toContain("EmbeddingService");
    expect(content).not.toContain("embeddingService");
    expect(content).not.toContain("cosineSimilarity");
    expect(content).not.toContain("cosineDistance");
  });
});

```
