---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase25c-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.571238+00:00
---

# tests/gates/phase25c-gate.test.ts

```ts
/**
 * Phase 25C Gate: SemanticFS & Path Mapping
 *
 * Validates:
 * 1. Path validation (T1–T4)
 * 2. Queries (T5–T8)
 * 3. Reclassification (T9–T11)
 * 4. VFS integration (T12–T13)
 * 5. Anti-regression (T14–T16)
 */

import { describe, test, expect, beforeEach } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// Direct imports from source
import { CellStore, type CellRef, type CellValue } from "../../core/protocol-types/src/cell-store";
import { MemoryAdapter } from "../../core/protocol-types/src/adapters/memory-adapter";
import {
  SemanticFS,
  InvalidSemanticPathError,
  FLAGS_TOMBSTONE,
} from "../../core/protocol-types/src/semantic-fs";
import type { TaxonomyResolver, TaxonomyNode } from "../../core/protocol-types/src/taxonomy-resolver";
import { deserializeCellHeader } from "../../core/protocol-types/src/cell-header";
import { HEADER_SIZE, Linearity } from "../../core/protocol-types/src/constants";

// ── Test Taxonomy ─────────────────────────────────────────────────
// Mirrors the real taxonomy structure: core domains + trades injection

function buildTestTaxonomy(): TaxonomyResolver {
  const tree: TaxonomyNode[] = [
    {
      id: "create",
      label: "Create",
      children: [
        {
          id: "job",
          label: "Job",
          children: [
            { id: "plumbing", label: "Plumbing" },
            { id: "electrical", label: "Electrical" },
          ],
        },
        { id: "quote", label: "Quote" },
        { id: "thing", label: "Thing" },
      ],
    },
    {
      id: "navigate",
      label: "Navigate",
      children: [
        { id: "objects", label: "Objects" },
      ],
    },
    {
      id: "query",
      label: "Query",
      children: [
        { id: "freeform", label: "Freeform" },
      ],
    },
    { id: "consume", label: "Consume" },
    { id: "inspect", label: "Inspect" },
    { id: "govern", label: "Govern" },
    { id: "demo", label: "Demo" },
    {
      id: "transition",
      label: "Transition",
      children: [
        { id: "publish", label: "Publish" },
        { id: "revoke", label: "Revoke" },
      ],
    },
  ];

  return {
    getNodeAt(path: string[]): TaxonomyNode | null {
      if (path.length === 0) return null;
      let current: TaxonomyNode[] = tree;
      let node: TaxonomyNode | undefined;
      for (const segment of path) {
        node = current.find((n) => n.id === segment);
        if (!node) return null;
        current = node.children ?? [];
      }
      return node ?? null;
    },
    getOptionsAt(path: string[]): TaxonomyNode[] {
      if (path.length === 0) return tree;
      let current: TaxonomyNode[] = tree;
      for (const segment of path) {
        const found = current.find((n) => n.id === segment);
        if (!found) return [];
        current = found.children ?? [];
      }
      return current;
    },
  };
}

// ── Gate 1: Path Validation ───────────────────────────────────────

describe("Phase 25C — Path Validation", () => {
  let adapter: MemoryAdapter;
  let cellStore: CellStore;
  let fs: SemanticFS;

  beforeEach(() => {
    adapter = new MemoryAdapter();
    cellStore = new CellStore(adapter);
    fs = new SemanticFS({
      cellStore,
      adapter,
      taxonomy: buildTestTaxonomy(),
    });
  });

  // T1: Valid taxonomy path is accepted
  test("T1: valid path accepted", async () => {
    const data = new TextEncoder().encode("test job data");
    const ref = await fs.put("objects/create/job/plumbing/job-1774", data);
    expect(ref).toBeDefined();
    expect(ref.key).toBe("objects/create/job/plumbing/job-1774");
    expect(ref.version).toBe(1);
    expect(ref.contentHash).toBeTruthy();
  });

  // T2: Invalid taxonomy path is rejected
  test("T2: invalid path rejected", async () => {
    const data = new TextEncoder().encode("bad data");
    await expect(
      fs.put("objects/nonexistent/path/obj-1", data),
    ).rejects.toThrow(InvalidSemanticPathError);
  });

  // T3: Object ID after valid prefix is accepted (freeform)
  test("T3: object id after valid prefix", async () => {
    const data = new TextEncoder().encode("thing data");
    // "create/thing" resolves in taxonomy, "widget-42" is freeform object-id
    const ref = await fs.put("objects/create/thing/widget-42", data);
    expect(ref.key).toBe("objects/create/thing/widget-42");
  });

  // T4: Extension injected paths are accepted
  test("T4: injected paths valid", async () => {
    const data = new TextEncoder().encode("electrical job");
    // "create/job/electrical" comes from trades injection
    const ref = await fs.put("objects/create/job/electrical/job-99", data);
    expect(ref.key).toBe("objects/create/job/electrical/job-99");
  });
});

// ── Gate 2: Queries ───────────────────────────────────────────────

describe("Phase 25C — Queries", () => {
  let adapter: MemoryAdapter;
  let cellStore: CellStore;
  let fs: SemanticFS;

  beforeEach(async () => {
    adapter = new MemoryAdapter();
    cellStore = new CellStore(adapter);
    fs = new SemanticFS({
      cellStore,
      adapter,
      taxonomy: buildTestTaxonomy(),
    });

    // Seed some data
    const enc = new TextEncoder();
    await fs.put("objects/create/job/plumbing/job-001", enc.encode("plumbing job 1"));
    await fs.put("objects/create/job/plumbing/job-002", enc.encode("plumbing job 2"));
    await fs.put("objects/create/job/electrical/job-003", enc.encode("electrical job"));
    await fs.put("objects/create/quote/quote-001", enc.encode("a quote"));
  });

  // T5: list with prefix returns all descendants
  test("T5: prefix query", async () => {
    const refs = await fs.list("objects/create/job");
    // Should find plumbing/job-001, plumbing/job-002, electrical/job-003
    expect(refs.length).toBe(3);
    const keys = refs.map((r) => r.key);
    expect(keys).toContain("objects/create/job/plumbing/job-001");
    expect(keys).toContain("objects/create/job/plumbing/job-002");
    expect(keys).toContain("objects/create/job/electrical/job-003");
  });

  // T6: list with depth=1 returns only direct children level
  test("T6: depth query", async () => {
    const refs = await fs.list("objects/create/job", { depth: 1 });
    // depth=1 means keys with only 1 segment after prefix — "plumbing" and "electrical" dirs
    // But since the actual objects are at depth 2, depth=1 should return nothing
    // (objects are at plumbing/job-001 which is depth 2)
    expect(refs.length).toBe(0);
  });

  // T7: queryByType returns correct results
  test("T7: type query", async () => {
    const refs = await fs.queryByType("create.job.plumbing");
    expect(refs.length).toBe(2);
    const keys = refs.map((r) => r.key);
    expect(keys).toContain("objects/create/job/plumbing/job-001");
    expect(keys).toContain("objects/create/job/plumbing/job-002");
  });

  // T8: findByContent works through SemanticFS
  test("T8: content query", async () => {
    // Write same content to two different paths
    const data = new TextEncoder().encode("duplicate content");
    const ref1 = await fs.put("objects/create/thing/thing-001", data);
    const ref2 = await fs.put("objects/create/quote/quote-dup", data);

    expect(ref1.contentHash).toBe(ref2.contentHash);

    const found = await fs.findByContent(ref1.contentHash);
    expect(found.length).toBeGreaterThanOrEqual(2);
  });
});

// ── Gate 3: Reclassification ──────────────────────────────────────

describe("Phase 25C — Reclassification", () => {
  let adapter: MemoryAdapter;
  let cellStore: CellStore;
  let fs: SemanticFS;

  beforeEach(async () => {
    adapter = new MemoryAdapter();
    cellStore = new CellStore(adapter);
    fs = new SemanticFS({
      cellStore,
      adapter,
      taxonomy: buildTestTaxonomy(),
    });
  });

  // T9: reclassify creates tombstone at old path
  test("T9: tombstone created", async () => {
    const data = new TextEncoder().encode("reclassify me");
    await fs.put("objects/create/job/plumbing/job-100", data);

    const result = await fs.reclassify(
      "objects/create/job/plumbing/job-100",
      "objects/create/job/electrical/job-100",
    );

    expect(result.tombstone).toBeDefined();
    expect(result.newVersion).toBeDefined();
    expect(result.newVersion.key).toBe("objects/create/job/electrical/job-100");

    // Verify tombstone has FLAGS_TOMBSTONE set
    const tombstoneBytes = await adapter.read("objects/create/job/plumbing/job-100");
    expect(tombstoneBytes).not.toBeNull();
    const header = deserializeCellHeader(tombstoneBytes!);
    expect(header.flags & FLAGS_TOMBSTONE).toBe(FLAGS_TOMBSTONE);
  });

  // T10: get on tombstone path auto-resolves to new location
  test("T10: tombstone resolution", async () => {
    const data = new TextEncoder().encode("follow the redirect");
    await fs.put("objects/create/job/plumbing/job-200", data);
    await fs.reclassify(
      "objects/create/job/plumbing/job-200",
      "objects/create/job/electrical/job-200",
    );

    // get() on old path should auto-resolve to new location
    const cell = await fs.get("objects/create/job/plumbing/job-200");
    expect(cell).not.toBeNull();
    expect(new TextDecoder().decode(cell!.payload)).toBe("follow the redirect");
  });

  // T11: history spans the reclassification (includes tombstone)
  test("T11: cross-reclassification history", async () => {
    const data = new TextEncoder().encode("versioned data");
    await fs.put("objects/create/job/plumbing/job-300", data);

    // Reclassify
    await fs.reclassify(
      "objects/create/job/plumbing/job-300",
      "objects/create/job/electrical/job-300",
    );

    // History at old path should show original + tombstone
    const oldHistory = await fs.history("objects/create/job/plumbing/job-300");
    expect(oldHistory.length).toBe(2); // original v1 + tombstone v2

    // History at new path should show the reclassified version
    const newHistory = await fs.history("objects/create/job/electrical/job-300");
    expect(newHistory.length).toBeGreaterThanOrEqual(1);
  });
});

// ── Gate 4: VFS Integration ──────────────────────────────────────

describe("Phase 25C — VFS Integration", () => {
  // T12: VFS resolver has SemanticFS-aware async methods
  test("T12: VfsPathResolver has async methods", () => {
    // Structural check that VfsPathResolver exposes the async API
    const { VfsPathResolver } = require("../../runtime/shell/src/vfs/pathResolver");
    expect(typeof VfsPathResolver.prototype.readdirAsync).toBe("function");
    expect(typeof VfsPathResolver.prototype.readAsync).toBe("function");
    expect(typeof VfsPathResolver.prototype.getattrAsync).toBe("function");
  });

  // T13: VFS readAsync falls back when SemanticFS not provided
  test("T13: VFS fallback without SemanticFS", async () => {
    const { VfsPathResolver } = require("../../runtime/shell/src/vfs/pathResolver");

    // Create resolver without SemanticFS — uses mock stores
    const mockStore = { getState: () => ({ objects: new Map() }) };
    const mockIdentity = { getIdentity: () => null };
    const mockConfig = { getConfig: () => null };

    const resolver = new VfsPathResolver(mockStore, mockIdentity, mockConfig);

    // Root readdir should still work (sync fallback)
    const entries = await resolver.readdirAsync("");
    expect(entries).toContain("objects");
    expect(entries).toContain("identities");
  });
});

// ── Gate 5: Anti-Regression ──────────────────────────────────────

describe("Phase 25C — Anti-Regression", () => {
  // T14: Phase 25A, 25B, and 25C exports intact
  test("T14: previous phase exports intact", () => {
    // Phase 25A — direct import verification
    expect(MemoryAdapter).toBeDefined();
    expect(typeof MemoryAdapter).toBe("function");

    // Phase 25B
    expect(CellStore).toBeDefined();
    expect(typeof CellStore).toBe("function");

    // Phase 25C
    expect(SemanticFS).toBeDefined();
    expect(typeof SemanticFS).toBe("function");
    expect(InvalidSemanticPathError).toBeDefined();
    expect(FLAGS_TOMBSTONE).toBe(0x0001);
  });

  // T15: Taxonomy assembly still works
  test("T15: taxonomy intact", () => {
    const corePath = join(ROOT, "configs/taxonomy/core.json");
    const tradesPath = join(ROOT, "configs/taxonomy/trades.json");
    const genericPath = join(ROOT, "configs/taxonomy/generic.json");

    expect(existsSync(corePath)).toBe(true);
    expect(existsSync(tradesPath)).toBe(true);
    expect(existsSync(genericPath)).toBe(true);

    const core = JSON.parse(readFileSync(corePath, "utf-8"));
    expect(core.nodes).toBeDefined();
    expect(core.nodes.length).toBe(8); // 8 root domains

    const trades = JSON.parse(readFileSync(tradesPath, "utf-8"));
    expect(trades.extensionId).toBe("trades-services");
    expect(trades.inject).toBeDefined();
  });

  // T16: Phase 22 Lean proofs unmodified
  test("T16: lean proofs intact", () => {
    const leanPath = join(ROOT, "proofs/lean/Semantos/Category.lean");
    expect(existsSync(leanPath)).toBe(true);

    const content = readFileSync(leanPath, "utf-8");
    // Must contain key definitions and no sorry/admit
    expect(content).toContain("def refines");
    expect(content).toContain("def inject");
    expect(content).not.toContain("sorry");
    expect(content).not.toContain("admit");
  });
});

```
