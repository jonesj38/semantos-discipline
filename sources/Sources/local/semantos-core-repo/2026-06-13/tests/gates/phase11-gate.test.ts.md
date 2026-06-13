---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase11-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.566658+00:00
---

# tests/gates/phase11-gate.test.ts

```ts
/**
 * Phase 11 Gate: Formal Verification — Lean 4 Kernel Proofs
 *
 * Validates:
 * 1. Lean 4 project builds without sorry
 * 2. All theorem files present
 * 3. Lean model constants match Zig source constants
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { execSync } from "child_process";

const ROOT = join(import.meta.dir, "../..");
const LEAN_DIR = join(ROOT, "proofs/lean");
const LEAN_THEOREMS_DIR = join(LEAN_DIR, "Semantos/Theorems");
const ZIG_CONSTANTS = join(ROOT, "core/cell-engine/src/constants.zig");
const ZIG_LINEARITY = join(ROOT, "core/cell-engine/src/linearity.zig");

// ── Gate 1: Lean 4 project builds ──────────────────────────────

describe("Gate 1: Lean 4 project builds", () => {
  test("lake build succeeds", () => {
    // Skip if lean is not installed (CI will handle this)
    try {
      execSync("lean --version", { stdio: "pipe" });
    } catch {
      console.log("SKIP: Lean 4 not installed locally");
      return;
    }

    const result = execSync("cd " + LEAN_DIR + " && lake build 2>&1", {
      encoding: "utf-8",
      timeout: 300000,
    });
    expect(result).toContain("Build completed successfully");
  });

  test("no sorry in theorem files", () => {
    const theoremFiles = [
      "LinearityK1.lean",
      "AuthSoundnessK2.lean",
      "DomainIsolationK3.lean",
      "FailureAtomicK4.lean",
      "TerminationK5.lean",
      "CellImmutabilityK7.lean",
    ];

    for (const file of theoremFiles) {
      const path = join(LEAN_THEOREMS_DIR, file);
      expect(existsSync(path)).toBe(true);
      const content = readFileSync(path, "utf-8");
      const sorryMatches = content.match(/\bsorry\b/g);
      expect(sorryMatches).toBeNull();
    }
  });
});

// ── Gate 2: All theorem files present ──────────────────────────

describe("Gate 2: All theorem files present", () => {
  const expectedFiles = [
    "Semantos/CryptoAxioms.lean",
    "Semantos/Cell.lean",
    "Semantos/Linearity.lean",
    "Semantos/BoundedStack.lean",
    "Semantos/PDA.lean",
    "Semantos/Opcodes/Classify.lean",
    "Semantos/Opcodes/Standard.lean",
    "Semantos/Opcodes/Plexus.lean",
    "Semantos/Executor.lean",
    "Semantos/Theorems/LinearityK1.lean",
    "Semantos/Theorems/AuthSoundnessK2.lean",
    "Semantos/Theorems/DomainIsolationK3.lean",
    "Semantos/Theorems/FailureAtomicK4.lean",
    "Semantos/Theorems/TerminationK5.lean",
    "Semantos/Theorems/CellImmutabilityK7.lean",
  ];

  for (const file of expectedFiles) {
    test(`${file} exists`, () => {
      expect(existsSync(join(LEAN_DIR, file))).toBe(true);
    });
  }
});

// ── Gate 3: Lean model matches Zig source constants ────────────

describe("Gate 3: Lean model matches Zig source constants", () => {
  test("stack bounds match constants.zig", () => {
    const zigConstants = readFileSync(ZIG_CONSTANTS, "utf-8");
    const leanPDA = readFileSync(
      join(LEAN_DIR, "Semantos/PDA.lean"),
      "utf-8"
    );

    // Extract Zig values
    const mainMatch = zigConstants.match(
      /MAIN_STACK_CELLS:\s*u32\s*=\s*(\d+)/
    );
    const auxMatch = zigConstants.match(
      /AUX_STACK_CELLS:\s*u32\s*=\s*(\d+)/
    );
    expect(mainMatch).not.toBeNull();
    expect(auxMatch).not.toBeNull();

    const zigMain = parseInt(mainMatch![1]);
    const zigAux = parseInt(auxMatch![1]);

    // Extract Lean values
    const leanMainMatch = leanPDA.match(/mainStackDepth\s*:\s*Nat\s*:=\s*(\d+)/);
    const leanAuxMatch = leanPDA.match(/auxStackDepth\s*:\s*Nat\s*:=\s*(\d+)/);
    expect(leanMainMatch).not.toBeNull();
    expect(leanAuxMatch).not.toBeNull();

    expect(parseInt(leanMainMatch![1])).toBe(zigMain);
    expect(parseInt(leanAuxMatch![1])).toBe(zigAux);
  });

  test("linearity enum values match", () => {
    const zigLinearity = readFileSync(ZIG_LINEARITY, "utf-8");
    const leanLinearity = readFileSync(
      join(LEAN_DIR, "Semantos/Cell.lean"),
      "utf-8"
    );

    // Zig: linear = 1, affine = 2, relevant = 3, debug = 4
    expect(zigLinearity).toContain("linear = 1");
    expect(zigLinearity).toContain("affine = 2");
    expect(zigLinearity).toContain("relevant = 3");
    expect(zigLinearity).toContain("debug = 4");

    // Lean model has same enum order (linear, affine, relevant, debug)
    expect(leanLinearity).toContain("| linear");
    expect(leanLinearity).toContain("| affine");
    expect(leanLinearity).toContain("| relevant");
    expect(leanLinearity).toContain("| debug");
  });

  test("header offsets documented in Cell.lean match constants.zig", () => {
    const zigConstants = readFileSync(ZIG_CONSTANTS, "utf-8");
    const leanCell = readFileSync(
      join(LEAN_DIR, "Semantos/Cell.lean"),
      "utf-8"
    );

    // Key offsets to verify
    const offsets: Record<string, number> = {
      HEADER_OFFSET_LINEARITY: 16,
      HEADER_OFFSET_FLAGS: 24,
      HEADER_OFFSET_TYPE_HASH: 30,
      HEADER_OFFSET_OWNER_ID: 62,
    };

    for (const [name, expected] of Object.entries(offsets)) {
      const zigMatch = zigConstants.match(
        new RegExp(`${name}:\\s*u16\\s*=\\s*(\\d+)`)
      );
      expect(zigMatch).not.toBeNull();
      expect(parseInt(zigMatch![1])).toBe(expected);

      // Verify the offset is documented in the Lean model
      expect(leanCell).toContain(String(expected));
    }
  });

  test("cell/header/payload sizes match", () => {
    const zigConstants = readFileSync(ZIG_CONSTANTS, "utf-8");
    const leanCell = readFileSync(
      join(LEAN_DIR, "Semantos/Cell.lean"),
      "utf-8"
    );

    // Zig: CELL_SIZE=1024, HEADER_SIZE=256, PAYLOAD_SIZE=768
    expect(zigConstants).toContain("CELL_SIZE: u32 = 1024");
    expect(zigConstants).toContain("HEADER_SIZE: u32 = 256");
    expect(zigConstants).toContain("PAYLOAD_SIZE: u32 = 768");

    // Lean model
    expect(leanCell).toContain("cellSize : Nat := 1024");
    expect(leanCell).toContain("headerSize : Nat := 256");
    expect(leanCell).toContain("payloadSize : Nat := 768");
  });

  test("linearity permission table match", () => {
    const zigLinearity = readFileSync(ZIG_LINEARITY, "utf-8");
    const leanLinearity = readFileSync(
      join(LEAN_DIR, "Semantos/Linearity.lean"),
      "utf-8"
    );

    // Zig: 4 forbidden combinations
    expect(zigLinearity).toContain("error.cannot_duplicate_linear");
    expect(zigLinearity).toContain("error.cannot_discard_linear");
    expect(zigLinearity).toContain("error.cannot_duplicate_affine");
    expect(zigLinearity).toContain("error.cannot_discard_relevant");

    // Lean: same 4 forbidden combinations
    expect(leanLinearity).toContain(
      "| .linear,   .duplicate => false"
    );
    expect(leanLinearity).toContain(
      "| .linear,   .discard   => false"
    );
    expect(leanLinearity).toContain(
      "| .affine,   .duplicate => false"
    );
    expect(leanLinearity).toContain(
      "| .relevant, .discard   => false"
    );
  });
});

```
