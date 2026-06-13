---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/import-boundaries.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.566380+00:00
---

# tests/gates/import-boundaries.test.ts

```ts
/**
 * Phase 3e: import-boundary gate.
 *
 * Mechanically enforces the architectural invariants the
 * core/runtime/cartridges/apps split is supposed to express:
 *
 *   core/         imports nothing outside core/
 *   runtime/      imports core/ + runtime/, nothing else
 *   cartridges/   imports core/ + runtime/ + cartridges/
 *   apps/         imports core/ + runtime/ + cartridges/, never another app
 *   archive/      not enforced
 *
 * Implementation: for each .ts/.tsx file under the four active tiers,
 * scan import specifiers (both workspace `@semantos/X` form and relative
 * `../../...` paths) and check the cross-tier rules.
 *
 * Violations failing-old: an explicit allowlist captures known existing
 * crossings that pre-date this gate. New violations fail; the allowlist
 * shrinks over time as the underlying issues are fixed.
 */

import { describe, test, expect } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { resolve, relative, dirname, join } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

type Tier = "core" | "runtime" | "cartridges" | "apps" | "archive";
const TIERS: Tier[] = ["core", "runtime", "cartridges", "apps"];

/** Allowed-direction map. tier-A may import from tier-B if B in ALLOWED[A]. */
const ALLOWED: Record<Tier, Tier[]> = {
  core: ["core"],
  runtime: ["core", "runtime"],
  cartridges: ["core", "runtime", "cartridges"],
  apps: ["core", "runtime", "cartridges"], // explicitly NOT apps
  archive: ["core", "runtime", "cartridges", "apps", "archive"],
};

// ── package-name → tier map (built from the workspace) ──────────

interface PackageInfo {
  name: string;
  tier: Tier;
  packageDirAbs: string; // absolute path to the package root
}

function buildPackageMap(): Map<string, PackageInfo> {
  const map = new Map<string, PackageInfo>();
  for (const tier of TIERS) {
    const tierDir = resolve(REPO_ROOT, tier);
    let entries: string[];
    try {
      entries = readdirSync(tierDir);
    } catch {
      continue;
    }
    for (const entry of entries) {
      const pkgDir = resolve(tierDir, entry);
      try {
        const pkgJsonPath = resolve(pkgDir, "package.json");
        const pkgJson = JSON.parse(readFileSync(pkgJsonPath, "utf8"));
        if (pkgJson.name) {
          map.set(pkgJson.name, { name: pkgJson.name, tier, packageDirAbs: pkgDir });
        }
      } catch {
        // not a package
      }
    }
  }
  return map;
}

// ── source-file walker ──────────────────────────────────────────

function walkSourceFiles(rootAbs: string): string[] {
  const out: string[] = [];
  function recurse(dirAbs: string) {
    let entries: string[];
    try {
      entries = readdirSync(dirAbs);
    } catch {
      return;
    }
    for (const entry of entries) {
      // skip noise
      if (
        entry === "node_modules" ||
        entry === "dist" ||
        entry === "zig-out" ||
        entry === "build" ||
        entry === ".vite" ||
        entry === ".lake" ||
        entry === "coverage" ||
        entry.startsWith(".")
      ) {
        continue;
      }
      const fullPath = resolve(dirAbs, entry);
      let stat;
      try {
        stat = statSync(fullPath);
      } catch {
        continue;
      }
      if (stat.isDirectory()) {
        recurse(fullPath);
      } else if (
        (entry.endsWith(".ts") || entry.endsWith(".tsx")) &&
        !entry.endsWith(".d.ts")
      ) {
        out.push(fullPath);
      }
    }
  }
  recurse(rootAbs);
  return out;
}

// ── import-specifier extraction ─────────────────────────────────

const IMPORT_RE =
  /(?:^|[^a-zA-Z0-9_$])(?:import|export)\b[^'"`]*?(?:from\s*)?['"`]([^'"`\n]+)['"`]/g;

function extractImports(source: string): string[] {
  const out: string[] = [];
  let match: RegExpExecArray | null;
  while ((match = IMPORT_RE.exec(source))) {
    out.push(match[1]);
  }
  return out;
}

// ── tier resolution for each import ─────────────────────────────

function tierOfPath(absPath: string): Tier | null {
  const rel = relative(REPO_ROOT, absPath);
  const top = rel.split("/")[0] as Tier;
  if (TIERS.includes(top) || top === "archive") return top;
  return null;
}

function resolveImport(
  importer: string,
  spec: string,
  packages: Map<string, PackageInfo>,
): { kind: "workspace" | "relative"; targetTier: Tier; targetSpec: string } | null {
  // Workspace package — match name OR name with subpath
  for (const [name, info] of packages) {
    if (spec === name || spec.startsWith(name + "/")) {
      return { kind: "workspace", targetTier: info.tier, targetSpec: name };
    }
  }
  // Relative import: resolve against importer's directory and ask what tier it's in
  if (spec.startsWith(".")) {
    const targetAbs = resolve(dirname(importer), spec);
    const tier = tierOfPath(targetAbs);
    if (tier) {
      return { kind: "relative", targetTier: tier, targetSpec: relative(REPO_ROOT, targetAbs) };
    }
  }
  return null;
}

// ── allowlist: known pre-existing violations ────────────────────

interface AllowlistEntry {
  importerSubstr: string;
  importContains: string;
  reason: string;
}

const ALLOWLIST: AllowlistEntry[] = [
  // ── Resolved by promoting games + game-sdk to cartridges/ ────────
  // The previous allowlist had four entries here for mud, poker-agent,
  // and settlement reaching into apps/game-sdk and apps/games. After
  // those packages moved to cartridges/, the same imports are now
  // legal under the apps/→cartridges/ rule. Entries removed.

  // ── core/semantos-ir test fixtures use the Lisp parser + compiler ──
  // The PRODUCTION-code dependency on the Lisp AST has been resolved by
  // hoisting ConstraintExpr (and IdentityRef, ComparisonOp, LinearityMode)
  // to @semantos/semantos-ir/expr. Only the IR's golden-file test still
  // imports the Lisp parser + compiler — for *generating* test input
  // expressions to feed lower(). Tests are allowed to know about both
  // layers (test code is meta-code); this entry narrows the scope to
  // just the test file rather than the broader core/semantos-{ir,sir}/
  // directories the original entry covered.
  {
    importerSubstr: "core/semantos-ir/src/__tests__/",
    importContains: "runtime/shell/src/lisp/compiler",
    reason: "IR golden-test uses LispCompiler to generate test inputs (test code only; no production dep)",
  },
  {
    importerSubstr: "core/semantos-ir/src/__tests__/",
    importContains: "runtime/shell/src/lisp/parser",
    reason: "IR golden-test uses parseExpression for test fixtures (test code only)",
  },

  // ── Resolved by migrating shell to @semantos/runtime-services ────
  // Was: runtime/shell/* → @semantos/loom (shim) — 25+ importers.
  // This commit's primary work flipped every shell file's import from
  // the deprecated `@semantos/loom` shim to `@semantos/runtime-services`
  // directly, removing the runtime/→apps/ violation entirely. Entry
  // removed.

  // ── core/ → runtime/shell/src/lisp/types — pre-existing dep on Lisp AST ──
  // The OIR (semantos-ir) and SIR (semantos-sir) types reference
  // ConstraintExpr — the Lisp AST — defined in runtime/shell/src/lisp/.
  // Real architectural inversion: the surface grammar's AST ought to
  // live in core/ alongside the IRs that consume it (or under
  // runtime/services/ as a shared type), not under shell. Surfaced
  // by the gate now that PR #99's path fixes resolve cleanly on top
  // of PR #100. Allowlisted while we plan the AST move.
  {
    importerSubstr: "core/semantos-ir/",
    importContains: "runtime/shell/src/lisp",
    reason: "OIR types depend on Lisp AST (TODO: hoist ConstraintExpr to core/ — it's the surface-grammar primitive)",
  },
  {
    importerSubstr: "core/semantos-sir/",
    importContains: "runtime/shell/src/lisp",
    reason: "SIR types + compileToSIR depend on Lisp AST (TODO: hoist ConstraintExpr to core/)",
  },

  // ── runtime/shell relative-path import of cartridges ──
  // Same shape as the @semantos/extraction allowlist below, but the
  // import is via a cross-tier relative path (../../../cartridges/...)
  // instead of a workspace specifier. Allowlist needs both forms.
  {
    importerSubstr: "runtime/shell/src/chat.ts",
    importContains: "packages/extraction",
    reason: "shell chat.ts pulls extraction's commerce-constraint engine via relative path (TODO: invert via handler registry)",
  },

  // ── Resolved by migrating game verb to handler-registry ────────
  // CDM, extraction, and games handlers all moved into their respective
  // cartridges/ packages, self-register with the runtime-services verb
  // registry, and are loaded dynamically by shell at startup. Shell has
  // zero static imports of any extension package now.

  // ── Resolved by deleting the @semantos/loom shim ────────────────
  // Was: packages/extraction → @semantos/loom (4 type-only imports
  // of LoomObject and ObjectPatch). Migrated to
  // @semantos/runtime-services/types as part of the shim deletion.
  // The apps/loom/ shim package itself is gone — there is no
  // @semantos/loom anywhere in the repo to import from anymore.
  // ── Test/vector fixtures that intentionally cross tiers ─────────
  // These are not production dependencies, but the gate scans tests and
  // fixture-generation scripts so they must be explicit. Prefer moving
  // shared fixtures into tests/fixtures or a neutral package when these
  // become long-lived.
  {
    importerSubstr: "core/conversation-graph/src/__tests__/",
    importContains: "@semantos/intent/reducer",
    reason: "conversation-graph end-to-end test validates against runtime intent reducer (test-only fixture)",
  },
  {
    importerSubstr: "core/cell-ops/tests/vectors/",
    importContains: "runtime/legacy-ingest/src/cell-writer/brain-rpc",
    reason: "cell-ops vector generator reuses legacy-ingest RPC writer for dogfood vectors (test/vector tooling only)",
  },
  {
    importerSubstr: "core/cell-ops/src/__tests__/",
    importContains: "runtime/legacy-ingest/src/cell-writer/brain-rpc",
    reason: "cell-ops derivation test reuses legacy-ingest RPC writer for parity coverage (test-only)",
  },

];

function isAllowed(importer: string, spec: string): boolean {
  const importerRel = relative(REPO_ROOT, importer);
  return ALLOWLIST.some(
    (a) => importerRel.includes(a.importerSubstr) && spec.includes(a.importContains),
  );
}

// ── the gate ────────────────────────────────────────────────────

interface Violation {
  importer: string;
  importerTier: Tier;
  spec: string;
  targetTier: Tier;
  kind: "workspace" | "relative";
}

function findViolations(): Violation[] {
  const packages = buildPackageMap();
  const violations: Violation[] = [];

  for (const tier of TIERS) {
    const tierAbs = resolve(REPO_ROOT, tier);
    const files = walkSourceFiles(tierAbs);

    for (const file of files) {
      const importerTier = tierOfPath(file)!;
      const allowed = ALLOWED[importerTier];
      const source = readFileSync(file, "utf8");

      for (const spec of extractImports(source)) {
        const resolved = resolveImport(file, spec, packages);
        if (!resolved) continue; // node built-in, npm dep, unresolved

        // Same-tier or self-import — always allowed
        if (resolved.targetTier === importerTier) continue;

        if (!allowed.includes(resolved.targetTier)) {
          if (isAllowed(file, spec)) continue;
          violations.push({
            importer: relative(REPO_ROOT, file),
            importerTier,
            spec,
            targetTier: resolved.targetTier,
            kind: resolved.kind,
          });
        }
      }
    }
  }

  return violations;
}

// ── tests ────────────────────────────────────────────────────────

describe("Phase 3e — import-boundary gate", () => {
  test("no cross-tier violations beyond the documented allowlist", () => {
    const violations = findViolations();
    if (violations.length > 0) {
      const grouped = violations.map(
        (v) =>
          `  ${v.importerTier}/ → ${v.targetTier}/   ${v.importer}   imports   ${v.spec}`,
      );
      const message =
        `Found ${violations.length} import-boundary violation(s):\n\n` +
        grouped.join("\n") +
        `\n\nIf these are intentional / pre-existing, add an entry to ALLOWLIST in this file.\n`;
      expect(message).toBe("");
    }
    expect(violations.length).toBe(0);
  });

  test("apps/* never imports from another apps/* (sibling-app rule)", () => {
    const violations = findViolations().filter(
      (v) => v.importerTier === "apps" && v.targetTier === "apps",
    );
    // (Sibling-app violations are also covered by the main test above
    // when they're not allowlisted; this test exists to make the rule
    // explicit and easy to scan in failure output.)
    expect(violations.length).toBe(0);
  });

  test("core production code imports nothing from runtime|cartridges|apps", () => {
    const violations = findViolations().filter((v) => {
      if (v.importerTier !== "core" || v.targetTier === "core") return false;
      // Test/vector tooling may cross tiers only through documented ALLOWLIST entries.
      // Production source remains a hard no-crossing boundary.
      return (
        !v.importer.includes("/__tests__/") &&
        !v.importer.includes("/tests/") &&
        !v.importer.endsWith(".test.ts") &&
        !v.importer.endsWith(".test.tsx") &&
        !v.importer.endsWith(".spec.ts")
      );
    });
    expect(violations.length).toBe(0);
  });

  // Production source files reach the @semantos/core package via the
  // published subpath (`@semantos/core/...`) — never via a relative
  // traversal into the repo-root `src/` directory. Relative paths of
  // the form `../../src/`, `../../../src/`, etc. bypass the package
  // alias, break the build when the package is published, and make
  // dead imports invisible to workspace tooling.
  //
  // Tests are exempt — several gate tests reach into runtime/shell/src
  // via `../../src/...` intentionally to exercise internals.
  test("production code never uses ../..src/ relative traversal into repo-root @semantos/core", () => {
    const rootSrcAbs = resolve(REPO_ROOT, "src");
    const offenders: { importer: string; spec: string }[] = [];

    for (const tier of TIERS) {
      const tierAbs = resolve(REPO_ROOT, tier);
      for (const file of walkSourceFiles(tierAbs)) {
        // Only production source — skip tests/specs/gates.
        const rel = relative(REPO_ROOT, file);
        if (
          rel.includes("/__tests__/") ||
          rel.includes("/tests/") ||
          rel.endsWith(".test.ts") ||
          rel.endsWith(".test.tsx") ||
          rel.endsWith(".spec.ts")
        ) {
          continue;
        }

        const source = readFileSync(file, "utf8");
        for (const spec of extractImports(source)) {
          if (!spec.startsWith(".")) continue;
          const targetAbs = resolve(dirname(file), spec);
          if (
            targetAbs === rootSrcAbs ||
            targetAbs.startsWith(rootSrcAbs + "/")
          ) {
            offenders.push({ importer: rel, spec });
          }
        }
      }
    }

    if (offenders.length > 0) {
      const lines = offenders.map((o) => `  ${o.importer}   imports   ${o.spec}`);
      const message =
        `Found ${offenders.length} relative import(s) into repo-root src/ from production code.\n\n` +
        lines.join("\n") +
        `\n\nUse the '@semantos/core/…' subpath instead. Add the workspace\n` +
        `dep (file:../../) and a tsconfig path alias if the package doesn't\n` +
        `already have them.\n`;
      expect(message).toBe("");
    }
    expect(offenders.length).toBe(0);
  });
});

```
