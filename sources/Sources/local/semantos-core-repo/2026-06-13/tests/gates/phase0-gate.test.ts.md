---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase0-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.578342+00:00
---

# tests/gates/phase0-gate.test.ts

```ts
/**
 * Phase 0 Integration Gate — all 5 TDD gates from the PRD.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync, statSync } from "fs";
import { join } from "path";
import { createHash } from "crypto";
import { execSync } from "child_process";

const ROOT = join(import.meta.dir, "../..");
const CONSTANTS_JSON = join(ROOT, "core/constants/constants.json");
const GENERATED_TS = join(ROOT, "core/protocol-types/src/constants.ts");
const GENERATED_ZIG = join(ROOT, "core/cell-engine/src/constants.zig");
const CELL_ENGINE = join(ROOT, "core/cell-engine");
const WASM_PATH = join(CELL_ENGINE, "zig-out/bin/cell-engine.wasm");

describe("Gate 1: Constants round-trip", () => {
  test("idempotent generation", () => {
    execSync("bun run generate-constants", { cwd: ROOT });
    const ts1 = createHash("sha256").update(readFileSync(GENERATED_TS)).digest("hex");
    const zig1 = createHash("sha256").update(readFileSync(GENERATED_ZIG)).digest("hex");
    execSync("bun run generate-constants", { cwd: ROOT });
    expect(createHash("sha256").update(readFileSync(GENERATED_TS)).digest("hex")).toBe(ts1);
    expect(createHash("sha256").update(readFileSync(GENERATED_ZIG)).digest("hex")).toBe(zig1);
  });
});

describe("Gate 2: Protocol-types compile", () => {
  test("module loads with correct enum values", () => {
    const mod = require("../../core/protocol-types/src/constants");
    expect(mod.Linearity.LINEAR).toBe(1);
    expect(mod.CommercePhase.OUTCOME).toBe(7);
  });
});

describe("Gate 3: Zig scaffold compiles", () => {
  test("zig build succeeds", () => {
    // Skip if zig is not installed (same pattern as Phase 11 Lean gate)
    try {
      execSync("zig version", { stdio: "pipe" });
    } catch {
      console.log("SKIP: Zig not installed locally");
      return;
    }

    execSync("zig build", { cwd: CELL_ENGINE, timeout: 120000 });
  });
});

describe("Gate 4: WASM binary validation", () => {
  test("exists, under 256KB, exports kernel_init", async () => {
    if (!existsSync(WASM_PATH)) {
      console.log("SKIP: WASM binary not built yet (run zig build first)");
      return;
    }
    expect(statSync(WASM_PATH).size).toBeLessThan(262144); // 256KB — grew from Phase 0 stub through Phase 10
    const mod = await WebAssembly.compile(readFileSync(WASM_PATH));
    const names = WebAssembly.Module.exports(mod).map(e => e.name);
    expect(names).toContain("kernel_init");
    expect(names).toContain("memory");
  });
});

describe("Gate 5: Constants consistency (JSON === TS === Zig)", () => {
  test("CELL_SIZE=1024 across all three", () => {
    const json = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    const ts = readFileSync(GENERATED_TS, "utf-8");
    const zig = readFileSync(GENERATED_ZIG, "utf-8");
    expect(json.protocol.cellSize).toBe(1024);
    expect(ts).toContain("CELL_SIZE = 1024");
    expect(zig).toContain("pub const CELL_SIZE: u32 = 1024;");
  });

  test("MAGIC_1=0xDEADBEEF across all three", () => {
    const json = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    const ts = readFileSync(GENERATED_TS, "utf-8");
    const zig = readFileSync(GENERATED_ZIG, "utf-8");
    expect(json.magic.MAGIC_1).toBe("0xDEADBEEF");
    expect(ts).toContain("MAGIC_1 = 0xDEADBEEF");
    expect(zig).toContain("pub const MAGIC_1: u32 = 0xDEADBEEF;");
  });

  test("HEADER_OFFSET_TYPE_HASH=30 across all three", () => {
    const json = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    const ts = readFileSync(GENERATED_TS, "utf-8");
    const zig = readFileSync(GENERATED_ZIG, "utf-8");
    expect(json.headerOffsets.typeHash).toBe(30);
    expect(ts).toContain("typeHash: 30");
    expect(zig).toContain("pub const HEADER_OFFSET_TYPE_HASH: u16 = 30;");
  });
});

```
