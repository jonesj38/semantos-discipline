---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/tessera-adapter-consumption.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.580090+00:00
---

# tests/gates/tessera-adapter-consumption.test.ts

```ts
/**
 * Tessera adapter-consumption gate (Wave Tessera §9.7, V0.5).
 *
 * Mechanically enforces TESSERA-CARTRIDGE.md §0.1 discipline #2:
 *
 *   cartridges/tessera/ accesses substrate ONLY through
 *   @semantos/protocol-types/* — never @bsv/sdk, never
 *   @semantos/wallet-toolbox, never an LMDB binding, never a
 *   runtime/ import, never a relative path escaping cartridges/tessera.
 *
 * This is the greenfield guarantee that tessera never inherits the
 * brain-core-baked / direct-LMDB anti-pattern the lift PRDs are
 * correcting. Companion to tests/gates/no-tessera-in-brain-core.test.ts
 * (which enforces the inverse: no `tessera` string under
 * runtime/semantos-brain/src/). Pattern mirrors
 * tests/gates/import-boundaries.test.ts.
 */

import { describe, test, expect } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { resolve, join } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");
const TESSERA_ROOT = join(REPO_ROOT, "cartridges", "tessera");
// The discipline (§0.1 #2 / §9.7) governs cartridge *runtime source*
// substrate access. The cartridge's release-pipeline declaration
// (brain/release.config.ts) legitimately type-imports the shared
// `../../tools/release/lib` — the universal golden-path pattern every
// cartridge (oddjobz/chess/bsv-anchor-bundle) uses — so it is build
// tooling, not substrate, and is out of scope here.
const SCAN_ROOT = join(TESSERA_ROOT, "brain", "src");

/**
 * Allowed @semantos/* specifiers:
 *   - @semantos/protocol-types — the substrate adapter contracts.
 *   - @semantos/semantos-sir   — the lexicon canon (V0.4
 *     extension_re_export; oddjobz/brain/src/lexicon.ts mirrors this
 *     exactly). Not substrate; it is the canonical SIR/lexicon core.
 */
const ALLOWED_SCOPED = [
  "@semantos/protocol-types",
  "@semantos/semantos-sir",
];

/** Hard-forbidden substrate specifiers (prefix match). */
const FORBIDDEN = [
  "@bsv/sdk",
  "@semantos/wallet-toolbox",
  "@semantos/cell-engine",
  "lmdb",
  "node-lmdb",
];

function tsFiles(dir: string): string[] {
  const out: string[] = [];
  for (const ent of readdirSync(dir)) {
    if (ent === "node_modules" || ent === ".zig-cache" || ent === "zig") continue;
    const p = join(dir, ent);
    const s = statSync(p);
    if (s.isDirectory()) out.push(...tsFiles(p));
    else if (/\.(ts|tsx)$/.test(ent) && !/\.d\.ts$/.test(ent)) out.push(p);
  }
  return out;
}

/** Extract import/export-from specifiers from a TS source. */
function importSpecifiers(src: string): string[] {
  const specs: string[] = [];
  const re = /(?:import|export)\s[^;]*?\sfrom\s+["']([^"']+)["']/g;
  const bare = /\bimport\s+["']([^"']+)["']/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) specs.push(m[1]);
  while ((m = bare.exec(src)) !== null) specs.push(m[1]);
  return specs;
}

describe("Tessera adapter-consumption — substrate only via @semantos/protocol-types", () => {
  const files = tsFiles(SCAN_ROOT);

  test("there is tessera TS source to check", () => {
    expect(files.length).toBeGreaterThan(0);
  });

  test("no forbidden substrate import anywhere under cartridges/tessera/", () => {
    const violations: string[] = [];
    for (const f of files) {
      const src = readFileSync(f, "utf8");
      for (const spec of importSpecifiers(src)) {
        if (FORBIDDEN.some((bad) => spec === bad || spec.startsWith(bad + "/"))) {
          violations.push(`${f.replace(REPO_ROOT + "/", "")} → ${spec}`);
        }
      }
    }
    expect(violations).toEqual([]);
  });

  test("no @semantos/* substrate import outside the allowed adapter package", () => {
    const violations: string[] = [];
    for (const f of files) {
      const src = readFileSync(f, "utf8");
      for (const spec of importSpecifiers(src)) {
        if (!spec.startsWith("@semantos/")) continue;
        const ok = ALLOWED_SCOPED.some(
          (a) => spec === a || spec.startsWith(a + "/"),
        );
        if (!ok) violations.push(`${f.replace(REPO_ROOT + "/", "")} → ${spec}`);
      }
    }
    expect(violations).toEqual([]);
  });

  test("no relative import escaping cartridges/tessera/ and no runtime/ reach", () => {
    const violations: string[] = [];
    for (const f of files) {
      const src = readFileSync(f, "utf8");
      for (const spec of importSpecifiers(src)) {
        if (spec.startsWith(".")) {
          const abs = resolve(f, "..", spec);
          if (!abs.startsWith(TESSERA_ROOT)) {
            violations.push(`${f.replace(REPO_ROOT + "/", "")} → ${spec} (escapes cartridges/tessera/)`);
          }
        }
        if (spec.includes("runtime/") || spec.startsWith("@semantos/semantos-brain")) {
          violations.push(`${f.replace(REPO_ROOT + "/", "")} → ${spec} (runtime/ reach)`);
        }
      }
    }
    expect(violations).toEqual([]);
  });
});

```
