---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase12-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.568032+00:00
---

# tests/gates/phase12-gate.test.ts

```ts
/**
 * Phase 12 Gate: Implementation Bridge
 *
 * Validates: fuzz harnesses, differential test vectors, mutation testing,
 * reproducible WASM build, P4.1 capstone, compliance matrix.
 *
 * Uses real artifacts. No stubs, no mocks.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync, readdirSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const CELL_ENGINE = join(ROOT, "core/cell-engine");
const PROOFS = join(ROOT, "proofs");

// ── Gate 1: Fuzz harnesses exist and are real ──────────────────

describe("Gate 1: Fuzz harnesses", () => {
  const FUZZ_DIR = join(CELL_ENGINE, "fuzz");
  const EXPECTED_FILES = [
    "linearity_fuzz.zig",
    "opcode_fuzz.zig",
    "stack_bounds_fuzz.zig",
    "plexus_atomic_fuzz.zig",
  ];

  test("fuzz/ directory exists with 4 harness files", () => {
    expect(existsSync(FUZZ_DIR)).toBe(true);
    for (const file of EXPECTED_FILES) {
      expect(existsSync(join(FUZZ_DIR, file))).toBe(true);
    }
  });

  test("each harness contains real test declarations (not stubs)", () => {
    for (const file of EXPECTED_FILES) {
      const content = readFileSync(join(FUZZ_DIR, file), "utf-8");
      expect(content.length).toBeGreaterThan(500);
      // Must contain actual Zig test declarations
      expect(content).toContain('test "fuzz:');
      // Must use random number generation (real fuzzing, not hardcoded)
      expect(content).toContain("Xoshiro256");
      // Must have iteration counts ≥ 50,000
      expect(content).toMatch(/ITERATIONS.*=\s*(5|10)0_000/);
    }
  });

  test("linearity fuzz checks BOTH stacks (main + aux)", () => {
    const content = readFileSync(join(FUZZ_DIR, "linearity_fuzz.zig"), "utf-8");
    expect(content).toContain("main_sp");
    expect(content).toContain("aux_sp");
    expect(content).toContain("countLinearCells");
  });

  test("build.zig includes fuzz harness compilation units", () => {
    const buildZig = readFileSync(join(CELL_ENGINE, "build.zig"), "utf-8");
    expect(buildZig).toContain("fuzz-linearity");
    expect(buildZig).toContain("fuzz-opcodes");
    expect(buildZig).toContain("fuzz-stack");
    expect(buildZig).toContain("fuzz-plexus");
  });
});

// ── Gate 2: Differential test vectors ──────────────────

describe("Gate 2: Differential test vectors", () => {
  const VECTORS_DIR = join(PROOFS, "vectors");

  test("three vector JSON files exist", () => {
    expect(existsSync(join(VECTORS_DIR, "linearity-vectors.json"))).toBe(true);
    expect(existsSync(join(VECTORS_DIR, "plexus-vectors.json"))).toBe(true);
    expect(existsSync(join(VECTORS_DIR, "stack-vectors.json"))).toBe(true);
  });

  test("≥50 total vectors across all files", () => {
    const lin = JSON.parse(readFileSync(join(VECTORS_DIR, "linearity-vectors.json"), "utf-8"));
    const plex = JSON.parse(readFileSync(join(VECTORS_DIR, "plexus-vectors.json"), "utf-8"));
    const stack = JSON.parse(readFileSync(join(VECTORS_DIR, "stack-vectors.json"), "utf-8"));
    const total = lin.length + plex.length + stack.length;
    expect(total).toBeGreaterThanOrEqual(50);
  });

  test("each vector has required fields", () => {
    const files = ["linearity-vectors.json", "plexus-vectors.json", "stack-vectors.json"];
    for (const file of files) {
      const vectors = JSON.parse(readFileSync(join(VECTORS_DIR, file), "utf-8"));
      for (const v of vectors) {
        expect(v).toHaveProperty("test_id");
        expect(v).toHaveProperty("description");
        expect(v).toHaveProperty("kernel_invariant");
        expect(v).toHaveProperty("setup");
        expect(v).toHaveProperty("expected");
        expect(v.expected).toHaveProperty("result");
      }
    }
  });

  test("vectors cover all Plexus opcodes 0xC0-0xCF", () => {
    const plex = JSON.parse(readFileSync(join(VECTORS_DIR, "plexus-vectors.json"), "utf-8"));
    const opcodes = new Set(plex.filter((v: any) => v.operation?.opcode).map((v: any) => v.operation.opcode));
    // Must cover 0xC0-0xC7 (implemented) + at least some reserved (0xC9-0xCF)
    for (let op = 0xC0; op <= 0xC7; op++) {
      expect(opcodes.has(op)).toBe(true);
    }
    // At least one reserved opcode tested
    const hasReserved = [0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF].some(op => opcodes.has(op));
    expect(hasReserved).toBe(true);
  });

  test("Zig differential conformance runner exists", () => {
    expect(existsSync(join(CELL_ENGINE, "tests/differential_conformance.zig"))).toBe(true);
    const content = readFileSync(join(CELL_ENGINE, "tests/differential_conformance.zig"), "utf-8");
    expect(content).toContain('test "differential:');
    // Must test K1-K5 and K7
    expect(content).toContain("K1");
    expect(content).toContain("K2");
    expect(content).toContain("K3");
    expect(content).toContain("K4");
    expect(content).toContain("K5");
    expect(content).toContain("K7");
  });

  test("generate-vectors.ts exists", () => {
    expect(existsSync(join(VECTORS_DIR, "generate-vectors.ts"))).toBe(true);
  });
});

// ── Gate 3: Mutation testing ──────────────────

describe("Gate 3: Mutation testing results", () => {
  const MUTATIONS_DIR = join(CELL_ENGINE, "mutations");

  test("mutation docs exist", () => {
    expect(existsSync(join(MUTATIONS_DIR, "linearity_mutations.md"))).toBe(true);
    expect(existsSync(join(MUTATIONS_DIR, "plexus_mutations.md"))).toBe(true);
  });

  test("mutation script exists", () => {
    expect(existsSync(join(MUTATIONS_DIR, "run-mutations.sh"))).toBe(true);
  });

  test("10 mutations documented with 100% kill rate", () => {
    const linDoc = readFileSync(join(MUTATIONS_DIR, "linearity_mutations.md"), "utf-8");
    const plexDoc = readFileSync(join(MUTATIONS_DIR, "plexus_mutations.md"), "utf-8");

    // Count KILLED entries
    const linKilled = (linDoc.match(/KILLED/g) || []).length;
    const plexKilled = (plexDoc.match(/KILLED/g) || []).length;
    expect(linKilled).toBeGreaterThanOrEqual(4);
    expect(plexKilled).toBeGreaterThanOrEqual(6);
    expect(linKilled + plexKilled).toBeGreaterThanOrEqual(10);

    // 100% kill rate mentioned
    expect(linDoc).toContain("100%");
    expect(plexDoc).toContain("100%");
  });
});

// ── Gate 4: WASM manifest ──────────────────

describe("Gate 4: WASM manifest", () => {
  test("WASM-MANIFEST.json exists and is valid", () => {
    const path = join(CELL_ENGINE, "WASM-MANIFEST.json");
    expect(existsSync(path)).toBe(true);

    const manifest = JSON.parse(readFileSync(path, "utf-8"));
    expect(manifest).toHaveProperty("sha256");
    expect(manifest).toHaveProperty("zigVersion");
    expect(manifest).toHaveProperty("sizeBytes");
    expect(manifest).toHaveProperty("sourceCommit");

    // SHA-256 is 64 hex chars
    expect(manifest.sha256).toMatch(/^[0-9a-f]{64}$/);
    // Size is reasonable (10KB - 100KB)
    expect(manifest.sizeBytes).toBeGreaterThan(10000);
    expect(manifest.sizeBytes).toBeLessThan(100000);
    // Source commit is 40 hex chars
    expect(manifest.sourceCommit).toMatch(/^[0-9a-f]{40}$/);
  });

  test("reproducible build script exists", () => {
    expect(existsSync(join(CELL_ENGINE, "scripts/reproducible-build.sh"))).toBe(true);
  });
});

// ── Gate 5: P4.1 capstone ──────────────────

describe("Gate 5: P4.1 capstone document", () => {
  test("capstone document exists", () => {
    expect(existsSync(join(PROOFS, "paper/P4.1-CAPSTONE.md"))).toBe(true);
  });

  test("all required sections present", () => {
    const content = readFileSync(join(PROOFS, "paper/P4.1-CAPSTONE.md"), "utf-8");
    expect(content).toContain("## 1. Kernel Invariants");
    expect(content).toContain("## 2. Protocol Properties");
    expect(content).toContain("## 3. Implementation Conformance");
    expect(content).toContain("## 4. Binary Integrity");
    expect(content).toContain("## 5. No Configuration Pathway");
    expect(content).toContain("## 6. Database Irrelevant");
    expect(content).toContain("## 7. Compliance Test Coverage");
    expect(content).toContain("## 8. Cryptographic Assumptions");
    expect(content).toContain("## 9. Limitations");
  });

  test("no TODO or TBD markers", () => {
    const content = readFileSync(join(PROOFS, "paper/P4.1-CAPSTONE.md"), "utf-8");
    expect(content).not.toContain("TODO");
    expect(content).not.toContain("TBD");
    expect(content).not.toContain("FIXME");
  });

  test("references real proof artifacts", () => {
    const content = readFileSync(join(PROOFS, "paper/P4.1-CAPSTONE.md"), "utf-8");
    // Must reference Lean theorem files
    expect(content).toContain("LinearityK1.lean");
    expect(content).toContain("FailureAtomicK4.lean");
    expect(content).toContain("TerminationK5.lean");
    // Must reference TLA+ files
    expect(content).toContain("EvidenceChain.tla");
    expect(content).toContain("ReplayPrevention.tla");
    // Must reference fuzz harnesses
    expect(content).toContain("linearity_fuzz.zig");
    // Must reference WASM manifest
    expect(content).toContain("WASM-MANIFEST.json");
  });
});

// ── Gate 6: Compliance matrix ──────────────────

describe("Gate 6: Compliance coverage matrix", () => {
  test("compliance-matrix.json exists", () => {
    expect(existsSync(join(PROOFS, "compliance-matrix.json"))).toBe(true);
  });

  test("≥25 compliance tests", () => {
    const matrix = JSON.parse(readFileSync(join(PROOFS, "compliance-matrix.json"), "utf-8"));
    expect(matrix.length).toBeGreaterThanOrEqual(25);
  });

  test("all tests have status 'supported'", () => {
    const matrix = JSON.parse(readFileSync(join(PROOFS, "compliance-matrix.json"), "utf-8"));
    for (const test of matrix) {
      expect(test.status).toBe("supported");
    }
  });

  test("every test has ≥1 proof artifact", () => {
    const matrix = JSON.parse(readFileSync(join(PROOFS, "compliance-matrix.json"), "utf-8"));
    for (const test of matrix) {
      expect(test.proofArtifacts.length).toBeGreaterThanOrEqual(1);
    }
  });

  test("all 7 frameworks covered", () => {
    const matrix = JSON.parse(readFileSync(join(PROOFS, "compliance-matrix.json"), "utf-8"));
    const frameworks = new Set(matrix.map((t: any) => t.framework));
    expect(frameworks.has("IEC 62443")).toBe(true);
    expect(frameworks.has("EU AI Act")).toBe(true);
    expect(frameworks.has("GDPR")).toBe(true);
    expect(frameworks.has("Basel III/IV")).toBe(true);
    expect(frameworks.has("HIPAA")).toBe(true);
    expect(frameworks.has("NIS2")).toBe(true);
    expect(frameworks.has("Cross-Framework")).toBe(true);
  });

  test("all referenced proof artifact files exist", () => {
    const matrix = JSON.parse(readFileSync(join(PROOFS, "compliance-matrix.json"), "utf-8"));
    const files = new Set(matrix.flatMap((t: any) => t.proofArtifacts.map((a: any) => a.file)));
    for (const file of files) {
      const fullPath = join(ROOT, file);
      expect(existsSync(fullPath)).toBe(true);
    }
  });
});

// ── Gate 7: Anti-regression ──────────────────

describe("Gate 7: Anti-regression", () => {
  test("Lean theorem files exist with zero sorry", () => {
    const theoremDir = join(PROOFS, "lean/Semantos/Theorems");
    expect(existsSync(theoremDir)).toBe(true);

    const theoremFiles = [
      "LinearityK1.lean",
      "AuthSoundnessK2.lean",
      "DomainIsolationK3.lean",
      "FailureAtomicK4.lean",
      "TerminationK5.lean",
      "CellImmutabilityK7.lean",
    ];

    for (const file of theoremFiles) {
      const fullPath = join(theoremDir, file);
      expect(existsSync(fullPath)).toBe(true);
      const content = readFileSync(fullPath, "utf-8");
      expect(content).not.toContain("sorry");
    }
  });

  test("TLA+ spec files exist", () => {
    const tlaDir = join(PROOFS, "tla");
    expect(existsSync(tlaDir)).toBe(true);

    const tlaFiles = [
      "EvidenceChain.tla",
      "ReplayPrevention.tla",
      "CertRevocation.tla",
      "MeteringFSM.tla",
      "ZoneBoundary.tla",
      "PartitionResilience.tla",
    ];

    for (const file of tlaFiles) {
      expect(existsSync(join(tlaDir, file))).toBe(true);
    }
  });

  test("Zig conformance test count is stable", () => {
    const testsDir = join(CELL_ENGINE, "tests");
    const testFiles = readdirSync(testsDir).filter(f => f.endsWith("_conformance.zig"));
    // We had 12 conformance files + 1 new differential = at least 13
    expect(testFiles.length).toBeGreaterThanOrEqual(13);
  });
});

```
