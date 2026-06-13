---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase25a-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.574030+00:00
---

# tests/gates/phase25a-gate.test.ts

```ts
/**
 * Phase 25A Gate: StorageAdapter Interface & Backend Implementations
 *
 * Validates:
 * 1. StorageAdapter interface and adapter exports (T26–T28)
 * 2. NodeFsAdapter mkdir recursive (T29)
 * 3. OverlayAdapter read-through (T30)
 * 4. Migration: no fs in EmbeddingService (T31)
 * 5. Migration: stores accept StorageAdapter (T32–T34)
 * 6. Anti-regression (T35–T39)
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { mkdtemp, rm } from "fs/promises";
import { join } from "path";
import { tmpdir } from "os";

const ROOT = join(import.meta.dir, "../..");

// ── Gate 1: StorageAdapter Interface ──────────────────────────────

describe("Phase 25A — StorageAdapter", () => {
  // T26: StorageAdapter interface is exported from protocol-types
  test("T26: StorageAdapter exported from protocol-types", () => {
    const indexSource = readFileSync(
      join(ROOT, "core/protocol-types/src/index.ts"),
      "utf-8",
    );
    expect(indexSource).toContain("StorageAdapter");
    expect(indexSource).toContain("StorageStat");
    expect(indexSource).toContain("StorageEvent");
    expect(indexSource).toContain("MemoryAdapter");
    expect(indexSource).toContain("createAdapter");
  });

  // T27: createAdapter() returns a MemoryAdapter in test environment
  test("T27: createAdapter returns MemoryAdapter in test", async () => {
    const { createAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/create-adapter.ts"),
    );
    const { MemoryAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/memory-adapter.ts"),
    );
    const adapter = await createAdapter();
    expect(adapter).toBeInstanceOf(MemoryAdapter);
  });

  // T28: createAdapter with explicit adapter uses it directly
  test("T28: createAdapter with override", async () => {
    const { createAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/create-adapter.ts"),
    );
    const { MemoryAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/memory-adapter.ts"),
    );
    const custom = new MemoryAdapter();
    const adapter = await createAdapter({ adapter: custom });
    expect(adapter).toBe(custom);
  });

  // T29: NodeFsAdapter creates directories on write
  test("T29: NodeFsAdapter mkdir recursive", async () => {
    const { NodeFsAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/node-fs-adapter.ts"),
    );
    const testRoot = await mkdtemp(join(tmpdir(), "semantos-t29-"));
    try {
      const adapter = new NodeFsAdapter(testRoot);
      const data = new Uint8Array([42]);
      await adapter.write("deep/nested/file.bin", data);
      const result = await adapter.read("deep/nested/file.bin");
      expect(result).toEqual(data);
    } finally {
      await rm(testRoot, { recursive: true, force: true });
    }
  });

  // T30: OverlayAdapter falls through on read
  test("T30: OverlayAdapter read-through", async () => {
    const { MemoryAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/memory-adapter.ts"),
    );
    const { OverlayAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/overlay-adapter.ts"),
    );
    const primary = new MemoryAdapter();
    const fallback = new MemoryAdapter();
    const overlay = new OverlayAdapter(primary, fallback);

    const data = new Uint8Array([1, 2, 3]);
    await fallback.write("config/x.json", data);

    const result = await overlay.read("config/x.json");
    expect(result).toEqual(data);
  });
});

// ── Gate 2: Migration ─────────────────────────────────────────────

describe("Phase 25A — Migration", () => {
  // T31: EmbeddingService has no 'fs' import
  test("T31: no fs import in EmbeddingService", () => {
    const source = readFileSync(
      join(ROOT, "runtime/services/src/services/EmbeddingService.ts"),
      "utf-8",
    );
    expect(source).not.toMatch(/import.*from\s+['"]fs['"]/);
    expect(source).not.toMatch(/require\s*\(\s*['"]fs['"]\s*\)/);
    expect(source).not.toMatch(/import.*from\s+['"]fs\/promises['"]/);
  });

  // T32: IdentityStore accepts StorageAdapter
  test("T32: IdentityStore accepts StorageAdapter", () => {
    const source = readFileSync(
      join(ROOT, "runtime/services/src/services/IdentityStore.ts"),
      "utf-8",
    );
    expect(source).toContain("StorageAdapter");
    expect(source).toContain("_adapter");
  });

  // T33: ConfigStore accepts StorageAdapter
  test("T33: ConfigStore accepts StorageAdapter", () => {
    const source = readFileSync(
      join(ROOT, "runtime/services/src/services/ConfigStore.ts"),
      "utf-8",
    );
    expect(source).toContain("StorageAdapter");
    expect(source).toContain("_adapter");
  });

  // T34: SettingsStore accepts StorageAdapter
  test("T34: SettingsStore accepts StorageAdapter", () => {
    const source = readFileSync(
      join(ROOT, "runtime/services/src/services/SettingsStore.ts"),
      "utf-8",
    );
    expect(source).toContain("StorageAdapter");
    expect(source).toContain("_adapter");
  });
});

// ── Gate 3: Anti-Regression ───────────────────────────────────────

describe("Phase 25A — Anti-Regression", () => {
  // T35: Key previous phase source files still exist
  test("T35: previous phase artifacts intact", () => {
    expect(existsSync(join(ROOT, "core/protocol-types/src/constants.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "runtime/services/src/services/IdentityStore.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "runtime/services/src/services/ConfigStore.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "core/protocol-types/src/cell-header.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "runtime/services/src/services/EmbeddingService.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "runtime/services/src/services/TaxonomyCoherence.ts"))).toBe(true);
  });

  // T36: Shell router still exports route function with key verbs
  test("T36: shell router exports route function", () => {
    const source = readFileSync(
      join(ROOT, "runtime/shell/src/router.ts"),
      "utf-8",
    );
    expect(source).toContain("export async function route");
    expect(source).toContain("taxonomy");
    expect(source).toContain("identity");
    expect(source).toContain("compile");
  });

  // T37: No sorry/admit in Lean proofs
  test("T37: lean proofs intact", () => {
    const leanDir = join(ROOT, "proofs/lean/Semantos");
    if (existsSync(leanDir)) {
      const { readdirSync } = require("fs");
      const leanFiles = readdirSync(leanDir).filter((f: string) => f.endsWith(".lean"));
      for (const file of leanFiles) {
        const content = readFileSync(join(leanDir, file), "utf-8");
        expect(content).not.toContain("sorry");
        expect(content).not.toContain("admit");
      }
    }
  });

  // T38: No third-party storage abstraction dependencies
  test("T38: no third-party storage abstractions", () => {
    const pkgFiles = [
      join(ROOT, "package.json"),
      join(ROOT, "core/protocol-types/package.json"),
    ];
    const banned = ["localforage", "idb", "keyv", "level", "unstorage", "abstract-level"];
    for (const pkgPath of pkgFiles) {
      if (!existsSync(pkgPath)) continue;
      const pkg = JSON.parse(readFileSync(pkgPath, "utf-8"));
      const allDeps = { ...(pkg.dependencies ?? {}), ...(pkg.devDependencies ?? {}) };
      for (const dep of banned) {
        expect(allDeps).not.toHaveProperty(dep);
      }
    }
  });

  // T39: StorageAdapter interface has all required methods
  test("T39: StorageAdapter interface completeness", () => {
    const source = readFileSync(
      join(ROOT, "core/protocol-types/src/storage.ts"),
      "utf-8",
    );
    const methods = ["read(", "write(", "exists(", "list(", "delete(", "stat(", "watch?("];
    for (const method of methods) {
      expect(source).toContain(method);
    }
  });
});

```
