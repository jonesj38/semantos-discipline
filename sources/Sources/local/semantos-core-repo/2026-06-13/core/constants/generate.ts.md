---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/constants/generate.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.794324+00:00
---

# core/constants/generate.ts

```ts
#!/usr/bin/env bun
/**
 * Constants Code Generator
 *
 * Reads constants.json → produces constants.zig + constants.ts
 * Both outputs are deterministic (same input → byte-identical output).
 */

import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const CONSTANTS_PATH = join(import.meta.dir, "constants.json");
const ZIG_OUT = join(ROOT, "core/cell-engine/src/constants.zig");
const TS_OUT = join(ROOT, "core/protocol-types/src/constants.ts");

const constants = JSON.parse(readFileSync(CONSTANTS_PATH, "utf-8"));

function toUpperSnake(s: string): string {
  return s.replace(/([a-z0-9])([A-Z])/g, "$1_$2").replace(/([A-Z])([A-Z][a-z])/g, "$1_$2").toUpperCase();
}

// ── Zig Generator ──

function generateZig(): string {
  const lines: string[] = [
    "// AUTO-GENERATED from constants.json — DO NOT EDIT",
    "// Run `bun run generate-constants` to regenerate.",
    "",
  ];

  const section = (title: string, entries: [string, string][]) => {
    lines.push(`// ── ${title} ──`);
    for (const [name, decl] of entries.sort(([a], [b]) => a.localeCompare(b))) {
      lines.push(decl);
    }
    lines.push("");
  };

  // Protocol
  section("Protocol", Object.entries(constants.protocol).map(([k, v]) =>
    [k, `pub const ${toUpperSnake(k)}: u32 = ${v};`]));

  // Stacks
  section("Stacks", Object.entries(constants.stacks).map(([k, v]) =>
    [k, `pub const ${toUpperSnake(k)}: u32 = ${v};`]));

  // Magic — keys already have underscores (MAGIC_1, etc.)
  section("Magic Numbers", Object.entries(constants.magic).map(([k, v]) =>
    [k, `pub const ${k}: u32 = ${v};`]));

  // Linearity
  section("Linearity", Object.entries(constants.linearity).map(([k, v]) =>
    [k, `pub const LINEARITY_${k}: u8 = ${v};`]));

  // Commerce Phase
  section("Commerce Phase", Object.entries(constants.commercePhase).map(([k, v]) =>
    [k, `pub const COMMERCE_PHASE_${k}: u8 = ${v};`]));

  // Taxonomy Dimension
  section("Taxonomy Dimension", Object.entries(constants.taxonomyDimension).map(([k, v]) =>
    [k, `pub const TAXONOMY_DIM_${k}: u8 = ${v};`]));

  // Cell Type
  section("Cell Type", Object.entries(constants.cellType).map(([k, v]) =>
    [k, `pub const CELL_TYPE_${k}: u8 = ${v};`]));

  // Header Offsets
  section("Header Offsets (packed wire format from typeHashRegistry.ts)",
    Object.entries(constants.headerOffsets).map(([k, v]) => {
      const name = k.endsWith("Size")
        ? `HEADER_SIZE_${toUpperSnake(k.replace(/Size$/, ""))}`
        : `HEADER_OFFSET_${toUpperSnake(k)}`;
      return [k, `pub const ${name}: u16 = ${v};`];
    }));

  // Opcode Ranges
  section("Opcode Ranges", Object.entries(constants.opcodeRanges).map(([k, v]) =>
    [k, `pub const OPCODE_${toUpperSnake(k)}: u8 = ${v};`]));

  // Opcodes — named Plexus/hostcall opcodes the executor dispatches on
  // (plexus.zig, executor.zig). Keys are already SCREAMING_SNAKE and are
  // emitted verbatim; values are decimal u8. These are the canonical source
  // the Zig switch prongs reference (constants.OP_*), like OP_BRANCHONOUTPUT.
  section("Opcodes", Object.entries(constants.opcodes).map(([k, v]) =>
    [k, `pub const ${k}: u8 = ${v};`]));

  // Routing Opcodes — verbatim SCREAMING_SNAKE names, u8, with the hand-authored
  // section title + spec-ref comment preserved so regeneration stays non-lossy.
  {
    const ro = constants.routingOpcodes;
    lines.push(`// ── ${ro.title} ──`);
    lines.push(`// Spec: ${ro.spec}`);
    for (const [k, v] of Object.entries(ro.values).sort(([a], [b]) => a.localeCompare(b))) {
      lines.push(`pub const ${k}: u8 = ${v};`);
    }
    lines.push("");
  }

  // Domain Flags
  section("Domain Flags", Object.entries(constants.domainFlags).map(([k, v]) =>
    [k, `pub const DOMAIN_FLAG_${toUpperSnake(k)}: u32 = ${v};`]));

  // Binding
  section("Binding", Object.entries(constants.binding).map(([k, v]) =>
    [k, `pub const BINDING_${toUpperSnake(k)}: u32 = ${v};`]));

  // BCA
  section("BCA", Object.entries(constants.bca).map(([k, v]) =>
    [k, `pub const BCA_${toUpperSnake(k)}: u32 = ${v};`]));

  // Extension Pages — per-extension page allocation in Tier 3 operator-sovereignty.
  // Keys are emitted verbatim (already SCREAMING_SNAKE_CASE in source).
  section("Extension Pages", Object.entries(constants.extensionPages).map(([k, v]) =>
    [k, `pub const ${k}: u32 = ${v};`]));

  return lines.join("\n");
}

// ── TypeScript Generator ──

function generateTs(): string {
  const lines: string[] = [
    "// AUTO-GENERATED from constants.json — DO NOT EDIT",
    "// Run `bun run generate-constants` to regenerate.",
    "",
  ];

  // Protocol
  lines.push("// ── Protocol ──");
  for (const [k, v] of Object.entries(constants.protocol).sort(([a], [b]) => a.localeCompare(b))) {
    lines.push(`export const ${toUpperSnake(k)} = ${v} as const;`);
  }
  lines.push("");

  // Stacks
  lines.push("// ── Stacks ──");
  for (const [k, v] of Object.entries(constants.stacks).sort(([a], [b]) => a.localeCompare(b))) {
    lines.push(`export const ${toUpperSnake(k)} = ${v} as const;`);
  }
  lines.push("");

  // Magic — preserve underscore naming
  lines.push("// ── Magic Numbers ──");
  for (const [k, v] of Object.entries(constants.magic).sort(([a], [b]) => a.localeCompare(b))) {
    lines.push(`export const ${k} = ${v} as const;`);
  }
  lines.push("");

  // Enums
  const emitEnum = (name: string, entries: Record<string, number>) => {
    lines.push(`export const enum ${name} {`);
    for (const [k, v] of Object.entries(entries).sort(([a], [b]) => a.localeCompare(b))) {
      lines.push(`  ${k} = ${v},`);
    }
    lines.push("}");
    lines.push("");
  };

  lines.push("// ── Linearity ──");
  emitEnum("Linearity", constants.linearity);

  lines.push("// ── Commerce Phase ──");
  emitEnum("CommercePhase", constants.commercePhase);

  lines.push("// ── Taxonomy Dimension ──");
  emitEnum("TaxonomyDimension", constants.taxonomyDimension);

  lines.push("// ── Cell Type ──");
  emitEnum("CellType", constants.cellType);

  // Header Offsets as const object
  lines.push("// ── Header Offsets (packed wire format) ──");
  lines.push("export const HeaderOffsets = {");
  for (const [k, v] of Object.entries(constants.headerOffsets).sort(([a], [b]) => a.localeCompare(b))) {
    lines.push(`  ${k}: ${v},`);
  }
  lines.push("} as const;");
  lines.push("");

  // Extension Pages — per-extension page allocation in Tier 3 operator-sovereignty.
  lines.push("// ── Extension Pages ──");
  for (const [k, v] of Object.entries(constants.extensionPages).sort(([a], [b]) => a.localeCompare(b))) {
    lines.push(`export const ${k} = ${v} as const;`);
  }
  lines.push("");

  return lines.join("\n");
}

// ── Main ──
mkdirSync(join(ROOT, "core/cell-engine/src"), { recursive: true });
mkdirSync(join(ROOT, "core/protocol-types/src"), { recursive: true });

writeFileSync(ZIG_OUT, generateZig(), "utf-8");
writeFileSync(TS_OUT, generateTs(), "utf-8");

console.log(`Generated: ${ZIG_OUT}`);
console.log(`Generated: ${TS_OUT}`);

```
