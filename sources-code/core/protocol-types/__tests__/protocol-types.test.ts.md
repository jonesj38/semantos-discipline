---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/protocol-types.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.858069+00:00
---

# core/protocol-types/__tests__/protocol-types.test.ts

```ts
/**
 * D0.2 — Protocol-types tests
 *
 * Validates that @semantos/protocol-types:
 * 1. Re-exports @semantos/core types (bridge, not reimplementation)
 * 2. Has correct generated enum values from constants.json
 * 3. CellHeaderLayout offsets match typeHashRegistry.ts
 * 4. WASM export contract matches CORE:WASM
 */

import { describe, test, expect } from "bun:test";
import {
  Linearity, CommercePhase, CellType, TaxonomyDimension,
  CELL_SIZE, HEADER_SIZE, PAYLOAD_SIZE,
  CellHeaderLayout, REQUIRED_WASM_EXPORTS,
  // Re-exports from @semantos/core
  SemanticType, CapabilityType, KernelError, TypeClassification,
} from "../src/index";

describe("generated constants re-exported correctly", () => {
  test("protocol sizes from FORTH:SEMOBJ", () => {
    expect(CELL_SIZE).toBe(1024);
    expect(HEADER_SIZE).toBe(256);
    expect(PAYLOAD_SIZE).toBe(768);
  });

  test("Linearity enum from FORTH:SEMOBJ lines 23-26", () => {
    expect(Linearity.LINEAR).toBe(1);
    expect(Linearity.AFFINE).toBe(2);
    expect(Linearity.RELEVANT).toBe(3);
    expect(Linearity.DEBUG).toBe(4);
  });

  test("CellType enum from PACKER:MAIN continuation types", () => {
    expect(CellType.BUMP).toBe(1);
    expect(CellType.ATOMIC_BEEF).toBe(2);
    expect(CellType.ENVELOPE).toBe(3);
    expect(CellType.DATA).toBe(4);
    expect(CellType.STATE).toBe(5);
  });
});

describe("@semantos/core re-exports (bridge, not reimplementation)", () => {
  test("SemanticType from CORE:SEMOBJ", () => {
    expect(SemanticType.LINEAR).toBe("LINEAR");
    expect(SemanticType.AFFINE).toBe("AFFINE");
    expect(SemanticType.RELEVANT).toBe("RELEVANT");
  });

  test("CapabilityType from CORE:CAPABILITY", () => {
    expect(CapabilityType.RECOVERY).toBe("RECOVERY");
    expect(CapabilityType.TRANSFER).toBe("TRANSFER");
  });

  test("KernelError from CORE:WASM", () => {
    expect(KernelError.SUCCESS).toBe(0);
    expect(KernelError.STACK_OVERFLOW).toBe(1);
    expect(KernelError.INVALID_OPCODE).toBe(4);
  });

  test("TypeClassification from CORE:WASM", () => {
    expect(TypeClassification.LINEAR).toBe(0);
    expect(TypeClassification.UNCLASSIFIED).toBe(-1);
  });
});

describe("CellHeaderLayout from typeHashRegistry.ts offsets", () => {
  test("typeHash at offset 30, size 32", () => {
    expect(CellHeaderLayout.typeHash).toEqual({ offset: 30, size: 32 });
  });

  test("parentHash at offset 96, size 32 (post-RM-032b chain field)", () => {
    expect(CellHeaderLayout.parentHash).toEqual({ offset: 96, size: 32 });
  });

  test("prevStateHash at offset 128, size 32 (post-RM-032b chain field)", () => {
    expect(CellHeaderLayout.prevStateHash).toEqual({ offset: 128, size: 32 });
  });

  test("domainPayloadRoot at offset 224, size 32 (Phase H §3.3)", () => {
    expect(CellHeaderLayout.domainPayloadRoot).toEqual({ offset: 224, size: 32 });
  });
});

describe("WASM export contract from CORE:WASM", () => {
  test("lists all 13 required exports from PlexusKernelWasm", () => {
    expect(REQUIRED_WASM_EXPORTS).toHaveLength(13);
    expect(REQUIRED_WASM_EXPORTS).toContain("kernel_init");
    expect(REQUIRED_WASM_EXPORTS).toContain("kernel_execute");
    expect(REQUIRED_WASM_EXPORTS).toContain("memory");
  });
});

```
