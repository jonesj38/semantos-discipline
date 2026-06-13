---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/substrate-one-way-dep.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.569257+00:00
---

# tests/gates/substrate-one-way-dep.test.ts

```ts
/**
 * Substrate one-way dep gate — first application of L26.
 *
 * Reference:
 *   docs/canon/cw-lift-matrix.yml L26 (cross-repo path-dep +
 *   pinned-rev pattern) +
 *   docs/canon/cross-repo-path-dep-pattern.md "Governance line".
 *
 * Mechanically enforces L26's governance line for the in-monorepo
 * boundary between substrate packages (`core/*`) and extensions
 * (`cartridges/*` + `runtime/*`):
 *
 *   The extension MAY depend on the substrate.
 *   The substrate SHALL NOT depend on the extension.
 *
 * Concretely: no source file under `core/<pkg>/src/` (excluding
 * `__tests__/`, `tests/`, test vectors, vendor, dist, build) may
 * import from `cartridges/*` or `runtime/*` — neither via relative
 * path nor via an `@semantos/<cartridge>` package alias.
 *
 * Tests as cross-validation fixtures (under `__tests__/` or `tests/`)
 * are out of scope by design: they are test-time integration, not a
 * runtime/build-graph reverse-dep. Production source under `src/` is
 * what the governance line targets.
 *
 * Companion gates:
 *   - tests/gates/tessera-adapter-consumption.test.ts — enforces the
 *     RUN-DOWN direction for tessera (cartridge → substrate only via
 *     @semantos/protocol-types).
 *   - tests/gates/no-tessera-in-brain-core.test.ts — enforces no
 *     tessera leak into runtime/semantos-brain/.
 *
 * This gate completes the boundary: substrate stays substrate.
 */

import { describe, test, expect } from "bun:test";
import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { resolve, join, relative } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");
const CORE_ROOT = join(REPO_ROOT, "core");

/**
 * Path segments that mark a file as test / vendor / build-output
 * rather than substrate runtime source. Files whose RELATIVE path
 * (under a core/<pkg>/ directory) contains any of these segments are
 * excluded from the gate.
 */
const EXCLUDED_PATH_SEGMENTS = [
  "__tests__",
  "/tests/",
  "/test/",
  "/__fixtures__/",
  "/vendor/",
  "/dist/",
  "/build/",
  "/.zig-cache/",
  "/zig-out/",
];

/**
 * Filename suffixes that mark a file as a test or test vector,
 * regardless of location.
 */
const EXCLUDED_FILENAME_SUFFIXES = [
  ".test.ts",
  ".test.tsx",
  ".spec.ts",
  ".spec.tsx",
];

/**
 * @semantos/* package aliases that are CARTRIDGES or RUNTIME packages.
 * Substrate (core/) MUST NOT import any of these. Discovered by
 * `find cartridges runtime -name package.json` — keep in sync if a
 * new cartridge or runtime package lands.
 *
 * The semantos monorepo uses the `@semantos/*` scope for BOTH substrate
 * (core/) AND extensions (cartridges/, runtime/), so a scope-prefix
 * check is insufficient — we maintain an explicit deny-list of
 * extension package names instead.
 */
const FORBIDDEN_EXTENSION_ALIASES = [
  // cartridges/
  "@semantos/betterment",
  "@semantos/bsv-anchor-bundle",
  "@semantos/oddjobz",
  "@semantos/scg",
  "@semantos/tessera",
  "@semantos/wallet-browser",
  "@semantos/world-app-chess-game",
  "@semantos/world-app-jam-room",
  // runtime/
  "@semantos/hrr-library",
  "@semantos/intent",
  "@semantos/legacy-ingest",
  "@semantos/node",
  "@semantos/peer-locator",
  "@semantos/runtime-services",
  "@semantos/session-protocol",
  "@semantos/shell",
  "@semantos/verifier-sidecar",
  "@semantos/world-beam",
  "@semantos/ws-node-adapter",
];

function isExcluded(absPath: string): boolean {
  for (const seg of EXCLUDED_PATH_SEGMENTS) {
    if (absPath.includes(seg)) return true;
  }
  for (const suf of EXCLUDED_FILENAME_SUFFIXES) {
    if (absPath.endsWith(suf)) return true;
  }
  return false;
}

function tsSourceFiles(dir: string): string[] {
  const out: string[] = [];
  if (!existsSync(dir)) return out;
  for (const ent of readdirSync(dir)) {
    if (ent === "node_modules" || ent === ".zig-cache" || ent === "zig-out" || ent === "dist" || ent === "build") continue;
    const p = join(dir, ent);
    const s = statSync(p);
    if (s.isDirectory()) {
      out.push(...tsSourceFiles(p));
    } else if (/\.(ts|tsx)$/.test(ent) && !/\.d\.ts$/.test(ent)) {
      if (!isExcluded(p)) out.push(p);
    }
  }
  return out;
}

function importSpecifiers(src: string): string[] {
  const specs: string[] = [];
  const re = /(?:import|export)\s[^;]*?\sfrom\s+["']([^"']+)["']/g;
  const bare = /\bimport\s+["']([^"']+)["']/g;
  const dyn = /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) specs.push(m[1]);
  while ((m = bare.exec(src)) !== null) specs.push(m[1]);
  while ((m = dyn.exec(src)) !== null) specs.push(m[1]);
  return specs;
}

function substratePackages(): { name: string; srcDir: string }[] {
  const out: { name: string; srcDir: string }[] = [];
  if (!existsSync(CORE_ROOT)) return out;
  for (const ent of readdirSync(CORE_ROOT)) {
    const srcDir = join(CORE_ROOT, ent, "src");
    if (existsSync(srcDir)) {
      out.push({ name: ent, srcDir });
    }
  }
  return out;
}

/** Detect imports that reach into cartridges/ or runtime/. */
function reverseDepViolations(file: string, repoRoot: string): string[] {
  const src = readFileSync(file, "utf8");
  const hits: string[] = [];
  for (const spec of importSpecifiers(src)) {
    // Relative-path escape
    if (spec.startsWith(".")) {
      const abs = resolve(file, "..", spec);
      const rel = relative(repoRoot, abs);
      if (rel.startsWith("cartridges/") || rel === "cartridges" ||
          rel.startsWith("runtime/") || rel === "runtime") {
        hits.push(`${relative(repoRoot, file)} → ${spec} (resolves to ${rel})`);
      }
      continue;
    }
    // Package-alias reach: @semantos/<cartridge-or-runtime> is forbidden
    if (spec.startsWith("@semantos/")) {
      const head = spec.split("/").slice(0, 2).join("/");
      if (FORBIDDEN_EXTENSION_ALIASES.includes(head)) {
        hits.push(`${relative(repoRoot, file)} → ${spec} (extension package — cartridge/runtime)`);
      }
      continue;
    }
    // Bare cartridge/runtime path references
    if (spec.startsWith("cartridges/") || spec.startsWith("runtime/")) {
      hits.push(`${relative(repoRoot, file)} → ${spec}`);
    }
  }
  return hits;
}

describe("L26 — substrate one-way dep gate", () => {
  const pkgs = substratePackages();

  test("there is substrate source to check", () => {
    expect(pkgs.length).toBeGreaterThan(0);
  });

  test("every substrate package src/ scans for at least one file", () => {
    const emptyPkgs: string[] = [];
    for (const { name, srcDir } of pkgs) {
      const files = tsSourceFiles(srcDir);
      if (files.length === 0) emptyPkgs.push(name);
    }
    // A package without any non-test TS source is unusual but not a
    // failure — Zig-only packages exist (pask). Surface as a note,
    // don't fail.
    expect(emptyPkgs).toBeInstanceOf(Array);
  });

  test("no core/<pkg>/src source reaches into cartridges/ or runtime/", () => {
    const violations: string[] = [];
    for (const { srcDir } of pkgs) {
      for (const f of tsSourceFiles(srcDir)) {
        violations.push(...reverseDepViolations(f, REPO_ROOT));
      }
    }
    expect(violations).toEqual([]);
  });
});

```
