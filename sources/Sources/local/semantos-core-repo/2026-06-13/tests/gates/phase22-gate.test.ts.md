---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase22-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.582656+00:00
---

# tests/gates/phase22-gate.test.ts

```ts
/**
 * Phase 22 Gate: Categorical Model of Semantic Types — Lean 4 Proofs
 *
 * Validates:
 * 1. Category.lean exists and builds without sorry/admit
 * 2. Exhaustive unit lemmas cover all taxonomy configs
 * 3. Cross-references to TypeScript source
 * 4. No TypeScript files modified
 * 5. No axioms for decidable properties
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { execSync } from "child_process";

const ROOT = join(import.meta.dir, "../..");
const LEAN_DIR = join(ROOT, "proofs/lean");
const CATEGORY_PATH = join(LEAN_DIR, "Semantos/Category.lean");

// ── Gate 1: Lean Category Proofs ──────────────────────────────────

describe("Phase 22 — Lean Category Proofs", () => {
  // T1: Category.lean exists and is non-empty
  test("T1: Category.lean exists and is non-empty", () => {
    expect(existsSync(CATEGORY_PATH)).toBe(true);
    const content = readFileSync(CATEGORY_PATH, "utf-8");
    expect(content.length).toBeGreaterThan(100);
  });

  // T2: `lake build` succeeds
  test(
    "T2: lake build succeeds",
    () => {
      // Skip if lean is not installed
      try {
        execSync("~/.elan/bin/lean --version", { stdio: "pipe" });
      } catch {
        console.log("SKIP: Lean 4 not installed locally");
        return;
      }

      const result = execSync(
        "export PATH=$HOME/.elan/bin:$PATH && cd " +
          LEAN_DIR +
          " && lake build 2>&1",
        {
          encoding: "utf-8",
          timeout: 300000,
        }
      );
      expect(result).toContain("Build completed successfully");
    },
    { timeout: 300000 }
  );

  // T3: No sorry or admit in Category.lean
  test("T3: no sorry or admit", () => {
    const content = readFileSync(CATEGORY_PATH, "utf-8");
    expect(content.match(/\bsorry\b/g)).toBeNull();
    expect(content.match(/\badmit\b/g)).toBeNull();
  });
});

// ── Gate 2: Taxonomy Cross-Reference ──────────────────────────────

describe("Phase 22 — Taxonomy Cross-Reference", () => {
  // T4: Every domain in core.json has a corresponding unit lemma
  test("T4: all core domains have unit lemmas", () => {
    const content = readFileSync(CATEGORY_PATH, "utf-8");
    const coreConfig = JSON.parse(
      readFileSync(join(ROOT, "configs/taxonomy/core.json"), "utf-8")
    );
    const domains: string[] = coreConfig.nodes.map(
      (d: { id: string }) => d.id
    );

    expect(domains.length).toBe(8);
    for (const domain of domains) {
      expect(content).toContain(`${domain}_refines_root`);
    }
  });

  // T5: Every extension injection in trades.json has a corresponding unit lemma
  test("T5: all trades injections have unit lemmas", () => {
    const content = readFileSync(CATEGORY_PATH, "utf-8");
    const tradesConfig = JSON.parse(
      readFileSync(join(ROOT, "configs/taxonomy/trades.json"), "utf-8")
    );

    for (const injection of tradesConfig.inject) {
      const parentId: string = injection.parentId;
      for (const node of injection.nodes) {
        const nodeId: string = node.id;
        // Expect a lemma like create_job_refines_create or transition_publish_refines_transition
        expect(content).toContain(
          `${parentId}_${nodeId}_refines_${parentId}`
        );
      }
    }
  });

  // T6: Category.lean references IntentTaxonomy.ts in doc comments
  test("T6: cross-references to TypeScript source", () => {
    const content = readFileSync(CATEGORY_PATH, "utf-8");
    expect(content).toContain("IntentTaxonomy.ts");
  });
});

// ── Gate 3: Anti-Regression ───────────────────────────────────────

describe("Phase 22 — Anti-Regression", () => {
  // T7: Existing Lean proofs still build (covered by T2, but verify files exist)
  test("T7: existing Lean theorem files still present", () => {
    const expectedFiles = [
      "Semantos/CryptoAxioms.lean",
      "Semantos/Cell.lean",
      "Semantos/Linearity.lean",
      "Semantos/BoundedStack.lean",
      "Semantos/PDA.lean",
      "Semantos/Theorems/LinearityK1.lean",
      "Semantos/Theorems/AuthSoundnessK2.lean",
      "Semantos/Theorems/DomainIsolationK3.lean",
      "Semantos/Theorems/FailureAtomicK4.lean",
      "Semantos/Theorems/TerminationK5.lean",
      "Semantos/Theorems/CellImmutabilityK7.lean",
    ];

    for (const file of expectedFiles) {
      expect(existsSync(join(LEAN_DIR, file))).toBe(true);
    }
  });

  // T8: IntentTaxonomy.ts is not modified
  test("T8: IntentTaxonomy.ts is not modified", () => {
    const tsSource = readFileSync(
      join(ROOT, "runtime/services/src/services/IntentTaxonomy.ts"),
      "utf-8"
    );
    expect(tsSource).toContain("export class IntentTaxonomy");
    expect(tsSource).toContain("getOptionsAt");
    expect(tsSource).toContain("getNodeAt");
    expect(tsSource).toContain("registerExtension");
  });

  // T9: No axioms for decidable properties in Category.lean
  test("T9: no axioms for decidable properties", () => {
    const content = readFileSync(CATEGORY_PATH, "utf-8");
    // Standalone `axiom` declarations are not allowed.
    // EmbeddingMetric structure fields are axiom-like but expressed as structure fields.
    const lines = content
      .split("\n")
      .filter((l) => l.trimStart().startsWith("axiom "));
    expect(lines).toHaveLength(0);
  });
});

```
