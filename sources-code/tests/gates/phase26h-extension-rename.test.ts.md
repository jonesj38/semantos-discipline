---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase26h-extension-rename.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.567768+00:00
---

# tests/gates/phase26h-extension-rename.test.ts

```ts
/**
 * Phase 26H Gate: Extension Rename Completeness
 *
 * Tests T1–T6 scan the entire codebase to verify that no "vertical"
 * identifiers remain in TypeScript source, configs, or documentation.
 *
 * T7–T16 verify that key renamed exports, types, and functions exist
 * and are correctly accessible from the barrel exports.
 */

import { describe, test, expect } from "bun:test";
import { join } from "path";
import { execSync } from "child_process";

const ROOT = join(import.meta.dir, "../..");

/**
 * Helper: run grep on the repo and return matching lines.
 * Returns empty array if no matches.
 */
function grepRepo(pattern: string, glob: string): string[] {
  try {
    const result = execSync(
      `grep -rn "${pattern}" ${ROOT} --include="${glob}" | grep -v node_modules | grep -v ".git/" | grep -v ".d.ts" | grep -v ".d.ts.map" | grep -v ".js.map" | grep -v "phase26h-extension-rename" | grep -v "PHASE-26H" | grep -v "vertical-align" | grep -v ".claude/"`,
      { encoding: "utf-8", maxBuffer: 1024 * 1024 },
    );
    return result.trim().split("\n").filter(Boolean);
  } catch {
    return []; // grep returns exit code 1 when no matches
  }
}

// ── Gate 1: Completeness Scans (T1–T6) ─────────────────────────

describe("Gate 1: No remaining vertical identifiers", () => {
  test("T1: no VerticalConfig/VerticalManifest/VerticalLoader/VerticalRegistry type names in .ts/.tsx", () => {
    const hits = grepRepo(
      "\\bVertical\\(Config\\|Manifest\\|Loader\\|Registry\\|Provider\\|LoadError\\|Context\\|ContextValue\\)\\b",
      "*.ts",
    );
    const tsxHits = grepRepo(
      "\\bVertical\\(Config\\|Manifest\\|Loader\\|Registry\\|Provider\\|LoadError\\|Context\\|ContextValue\\)\\b",
      "*.tsx",
    );
    const all = [...hits, ...tsxHits];
    if (all.length > 0) {
      console.error("Remaining Vertical type names:\n" + all.join("\n"));
    }
    expect(all.length).toBe(0);
  });

  test("T2: no verticalId/verticalPath/verticalName etc. identifiers in .ts/.tsx", () => {
    const hits = grepRepo(
      "\\bvertical\\(Id\\|Name\\|Path\\|Registrations\\|Capabilities\\|Config\\|Loader\\|Manifest\\)\\b",
      "*.ts",
    );
    const tsxHits = grepRepo(
      "\\bvertical\\(Id\\|Name\\|Path\\|Registrations\\|Capabilities\\|Config\\|Loader\\|Manifest\\)\\b",
      "*.tsx",
    );
    const all = [...hits, ...tsxHits];
    if (all.length > 0) {
      console.error("Remaining vertical identifiers:\n" + all.join("\n"));
    }
    expect(all.length).toBe(0);
  });

  test("T3: no configs/extensions path references in .ts/.tsx/.json", () => {
    const tsHits = grepRepo("configs/extensions", "*.ts");
    const tsxHits = grepRepo("configs/extensions", "*.tsx");
    const jsonHits = grepRepo("configs/extensions", "*.json");
    const all = [...tsHits, ...tsxHits, ...jsonHits];
    if (all.length > 0) {
      console.error("Remaining configs/extensions paths:\n" + all.join("\n"));
    }
    expect(all.length).toBe(0);
  });

  test("T4: no DEFAULT_VERTICAL or BUNDLED_VERTICALS constants", () => {
    const hits = grepRepo("\\b\\(DEFAULT_VERTICAL\\|BUNDLED_VERTICALS\\)\\b", "*.ts");
    if (hits.length > 0) {
      console.error("Remaining vertical constants:\n" + hits.join("\n"));
    }
    expect(hits.length).toBe(0);
  });

  test("T5: no switchVertical/registerVertical/useVertical function names", () => {
    const hits = grepRepo(
      "\\b\\(switchVertical\\|registerVertical\\|unregisterVertical\\|useVertical\\|validateVerticalConfig\\|validateVerticalManifest\\)\\b",
      "*.ts",
    );
    const tsxHits = grepRepo(
      "\\b\\(switchVertical\\|registerVertical\\|unregisterVertical\\|useVertical\\|validateVerticalConfig\\|validateVerticalManifest\\)\\b",
      "*.tsx",
    );
    const all = [...hits, ...tsxHits];
    if (all.length > 0) {
      console.error("Remaining vertical function names:\n" + all.join("\n"));
    }
    expect(all.length).toBe(0);
  });

  test("T6: no vertical-manifest/vertical-loader/vertical-registry import paths", () => {
    const hits = grepRepo(
      "\\(vertical-manifest\\|vertical-loader\\|vertical-registry\\)",
      "*.ts",
    );
    if (hits.length > 0) {
      console.error("Remaining vertical import paths:\n" + hits.join("\n"));
    }
    expect(hits.length).toBe(0);
  });
});

// ── Gate 2: Barrel Exports (T7–T10) ────────────────────────────

describe("Gate 2: Barrel exports use extension names", () => {
  test("T7: ExtensionManifest is exported from protocol-types", () => {
    const mod = require("../../core/protocol-types/src/index");
    expect(mod.validateExtensionManifest).toBeDefined();
    expect(typeof mod.validateExtensionManifest).toBe("function");
  });

  test("T8: ExtensionLoader is exported from protocol-types", () => {
    const mod = require("../../core/protocol-types/src/index");
    expect(mod.ExtensionLoader).toBeDefined();
    expect(mod.ExtensionLoadError).toBeDefined();
  });

  test("T9: ExtensionRegistry is exported from protocol-types", () => {
    const mod = require("../../core/protocol-types/src/index");
    expect(mod.ExtensionRegistry).toBeDefined();
  });

  test("T10: no Vertical* names in protocol-types exports", () => {
    const mod = require("../../core/protocol-types/src/index");
    const verticalExports = Object.keys(mod).filter((k) => k.startsWith("Vertical") || k.startsWith("validate Vertical"));
    expect(verticalExports).toEqual([]);
  });
});

// ── Gate 3: File Renames (T11–T13) ─────────────────────────────

describe("Gate 3: File renames are complete", () => {
  test("T11: extension-manifest.ts exists, vertical-manifest.ts does not", () => {
    const { existsSync } = require("fs");
    expect(existsSync(join(ROOT, "core/protocol-types/src/extension-manifest.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "packages/protocol-types/src/vertical-manifest.ts"))).toBe(false);
  });

  test("T12: extension-loader.ts exists, vertical-loader.ts does not", () => {
    const { existsSync } = require("fs");
    expect(existsSync(join(ROOT, "core/protocol-types/src/extension-loader.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "packages/protocol-types/src/vertical-loader.ts"))).toBe(false);
  });

  test("T13: configs/extensions/ exists, configs/extensions/ does not", () => {
    const { existsSync } = require("fs");
    expect(existsSync(join(ROOT, "configs/extensions"))).toBe(true);
    expect(existsSync(join(ROOT, "configs/extensions"))).toBe(false);
  });
});

// ── Gate 4: Renamed Types Work (T14–T16) ───────────────────────

describe("Gate 4: Renamed types and functions work correctly", () => {
  test("T14: validateExtensionManifest accepts valid manifest", () => {
    const { validateExtensionManifest } = require("../../core/protocol-types/src/extension-manifest");
    const manifest = validateExtensionManifest({
      id: "test",
      name: "Test",
      version: "1.0.0",
      taxonomyPath: "taxonomy/test.json",
      flowsDir: "flows",
      promptsDir: "prompts",
    });
    expect(manifest.id).toBe("test");
  });

  test("T15: validateExtensionManifest rejects invalid manifest", () => {
    const { validateExtensionManifest } = require("../../core/protocol-types/src/extension-manifest");
    expect(() => validateExtensionManifest({})).toThrow();
    expect(() => validateExtensionManifest(null)).toThrow();
  });

  test("T16: ExtensionConfig type is importable from extensionConfig", () => {
    const mod = require("../../runtime/services/src/config/extensionConfig");
    expect(mod.validateExtensionConfig).toBeDefined();
    expect(typeof mod.validateExtensionConfig).toBe("function");
  });
});

```
