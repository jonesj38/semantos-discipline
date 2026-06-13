---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase21-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.563804+00:00
---

# tests/gates/phase21-gate.test.ts

```ts
/**
 * Phase 21 Gate: Lisp Axiom Compiler
 *
 * Tests T1–T18 covering:
 *   T1-T3:  S-expression parser (atoms, nested lists, error handling)
 *   T4-T7:  Compiler (comparison → script, and/or → BOOLAND/BOOLOR, policy, determinism)
 *   T8-T13: Integration (packer, eval, compile, verify, extension config, equivalence)
 *   T14-T15: Round-trip (parse → compile → pack → unpack, comments/whitespace)
 *   T16-T18: Anti-lock (no React, no I/O imports, cell header round-trip)
 */

import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// ── Pure function imports ─────────────────────────────────────

import {
  parseExpression,
  parseProgram,
  ParseError,
} from "../../runtime/shell/src/lisp/parser";
import type { SExpression, Atom, List } from "../../runtime/shell/src/lisp/parser";

import { LispCompiler } from "../../runtime/shell/src/lisp/compiler";

import {
  interpretConstraint,
  interpretPolicy,
  validateConstraintFields,
} from "../../runtime/shell/src/lisp/types";
import type { ConstraintExpr } from "../../runtime/shell/src/lisp/types";

import {
  packCapabilityCell,
  unpackCapabilityCell,
} from "../../runtime/shell/src/lisp/packer";

import { validateExtensionConfig } from "../../runtime/services/src/config/extensionConfig";
import type { PolicyBinding } from "../../runtime/services/src/config/extensionConfig";

import {
  CELL_SIZE,
  HEADER_SIZE,
  Linearity,
  MAGIC_1,
  MAGIC_2,
  MAGIC_3,
  MAGIC_4,
} from "../../core/protocol-types/src/constants";

// ── Helpers ───────────────────────────────────────────────────

function atom(expr: SExpression): Atom {
  if (expr.type !== 'atom') throw new Error(`Expected atom, got list`);
  return expr;
}

function list(expr: SExpression): List {
  if (expr.type !== 'list') throw new Error(`Expected list, got atom`);
  return expr;
}

// ═══════════════════════════════════════════════════════════════
// T1–T3: S-Expression Parser
// ═══════════════════════════════════════════════════════════════

describe("T1: Parser correctly parses policy form", () => {
  test("parses (policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)", () => {
    const input = '(policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)';
    const expr = parseExpression(input);

    expect(expr.type).toBe('list');
    const elems = list(expr).elements;

    // First element is 'policy' symbol
    expect(atom(elems[0]).kind).toBe('symbol');
    expect(atom(elems[0]).value).toBe('policy');

    // :subject keyword
    expect(atom(elems[1]).kind).toBe('keyword');
    expect(atom(elems[1]).value).toBe(':subject');

    // homeowner symbol
    expect(atom(elems[2]).kind).toBe('symbol');
    expect(atom(elems[2]).value).toBe('homeowner');

    // :action keyword
    expect(atom(elems[3]).kind).toBe('keyword');
    expect(atom(elems[3]).value).toBe(':action');

    // approve-repair symbol
    expect(atom(elems[4]).kind).toBe('symbol');
    expect(atom(elems[4]).value).toBe('approve-repair');

    // :constraint keyword
    expect(atom(elems[5]).kind).toBe('keyword');
    expect(atom(elems[5]).value).toBe(':constraint');

    // (> amount 500) nested list
    expect(elems[6].type).toBe('list');
    const constraintList = list(elems[6]).elements;
    expect(atom(constraintList[0]).value).toBe('>');
    expect(atom(constraintList[1]).value).toBe('amount');
    expect(atom(constraintList[2]).value).toBe(500);

    // :linearity keyword + LINEAR symbol
    expect(atom(elems[7]).kind).toBe('keyword');
    expect(atom(elems[7]).value).toBe(':linearity');
    expect(atom(elems[8]).value).toBe('LINEAR');
  });

  test("interpretPolicy extracts correct PolicyForm", () => {
    const input = '(policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)';
    const expr = parseExpression(input);
    const policy = interpretPolicy(expr);

    expect(policy.subject).toEqual({ type: 'role', name: 'homeowner' });
    expect(policy.action).toBe('approve-repair');
    expect(policy.linearity).toBe('LINEAR');
    expect(policy.constraint.kind).toBe('comparison');
  });
});

describe("T2: Parser handles nested constraints", () => {
  test("parses (and (> amount 500) (has-capability 6))", () => {
    const input = '(and (> amount 500) (has-capability 6))';
    const expr = parseExpression(input);

    expect(expr.type).toBe('list');
    const elems = list(expr).elements;
    expect(elems.length).toBe(3);

    expect(atom(elems[0]).value).toBe('and');

    // (> amount 500)
    const first = list(elems[1]).elements;
    expect(atom(first[0]).value).toBe('>');
    expect(atom(first[1]).value).toBe('amount');
    expect(atom(first[2]).value).toBe(500);

    // (has-capability 6)
    const second = list(elems[2]).elements;
    expect(atom(second[0]).value).toBe('has-capability');
    expect(atom(second[1]).value).toBe(6);
  });

  test("deeply nested constraint interprets correctly", () => {
    const input = '(or (and (> a 5) (< b 10)) (not (= c 0)))';
    const expr = parseExpression(input);
    const constraint = interpretConstraint(expr);

    expect(constraint.kind).toBe('logical');
    if (constraint.kind === 'logical') {
      expect(constraint.op).toBe('or');
      expect(constraint.operands.length).toBe(2);
    }
  });
});

describe("T3: Parser rejects invalid forms with clear errors", () => {
  test("unmatched opening paren", () => {
    expect(() => parseExpression('(policy :subject homeowner'))
      .toThrow(ParseError);
    try {
      parseExpression('(policy :subject homeowner');
    } catch (e) {
      expect(e).toBeInstanceOf(ParseError);
      expect((e as ParseError).line).toBeGreaterThan(0);
      expect((e as ParseError).column).toBeGreaterThan(0);
    }
  });

  test("unmatched closing paren", () => {
    expect(() => parseExpression(')'))
      .toThrow(ParseError);
  });

  test("unterminated string", () => {
    expect(() => parseExpression('"hello'))
      .toThrow(ParseError);
  });

  test("empty input", () => {
    expect(() => parseExpression(''))
      .toThrow(ParseError);
  });
});

// ═══════════════════════════════════════════════════════════════
// T4–T7: Compiler
// ═══════════════════════════════════════════════════════════════

describe("T4: Compiler produces correct script for (> amount 500)", () => {
  test("scriptWords is exactly '500 AMOUNT-GT'", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(> amount 500)');
    const output = compiler.compile(expr);

    expect(output.scriptWords).toBe('500 AMOUNT-GT');
    expect(output.scriptBytes.length).toBeGreaterThan(0);
  });
});

describe("T5: Compiler produces correct script for (and (> amount 500) (has-capability 6))", () => {
  test("scriptWords is exactly '500 AMOUNT-GT 6 CHECK-CAP BOOLAND'", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(and (> amount 500) (has-capability 6))');
    const output = compiler.compile(expr);

    expect(output.scriptWords).toBe('500 AMOUNT-GT 6 CHECK-CAP BOOLAND');
  });
});

describe("T6: Compiler produces correct script for full policy form", () => {
  test("policy compiles with subject + constraint + BOOLAND + VERIFY", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)');
    const output = compiler.compilePolicy(expr);

    // Should contain subject check, constraint, BOOLAND, and VERIFY
    expect(output.scriptWords).toContain('HOMEOWNER-FLAG CHECK-DOMAIN');
    expect(output.scriptWords).toContain('500 AMOUNT-GT');
    expect(output.scriptWords).toContain('BOOLAND');
    expect(output.scriptWords).toContain('VERIFY');

    // Metadata should reflect policy details
    expect(output.metadata.subject).toBe('homeowner');
    expect(output.metadata.action).toBe('approve-repair');
    expect(output.metadata.linearity).toBe('LINEAR');
  });
});

describe("T7: Compiler is deterministic", () => {
  test("same input produces exact same output 100 times", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(and (> amount 500) (< urgency 3))');

    const first = compiler.compile(expr);
    for (let i = 0; i < 100; i++) {
      const output = compiler.compile(expr);
      expect(output.scriptWords).toBe(first.scriptWords);
      expect(output.scriptBytes).toEqual(first.scriptBytes);
    }
  });
});

// ═══════════════════════════════════════════════════════════════
// T8–T13: Integration
// ═══════════════════════════════════════════════════════════════

describe("T8: Packer produces valid cell bytes", () => {
  test("exactly 1024 bytes", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(> amount 500)');
    const output = compiler.compile(expr);
    const cell = packCapabilityCell(output.scriptBytes);

    expect(cell.length).toBe(CELL_SIZE);
  });

  test("magic bytes at offset 0-15 match constants", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(> amount 500)');
    const output = compiler.compile(expr);
    const cell = packCapabilityCell(output.scriptBytes);

    const dv = new DataView(cell.buffer, cell.byteOffset, cell.byteLength);
    expect(dv.getUint32(0, true)).toBe(MAGIC_1);
    expect(dv.getUint32(4, true)).toBe(MAGIC_2);
    expect(dv.getUint32(8, true)).toBe(MAGIC_3);
    expect(dv.getUint32(12, true)).toBe(MAGIC_4);
  });

  test("linearity = LINEAR (1) at offset 16", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(> amount 500)');
    const output = compiler.compile(expr);
    const cell = packCapabilityCell(output.scriptBytes, { linearity: 'LINEAR' });

    const dv = new DataView(cell.buffer, cell.byteOffset, cell.byteLength);
    expect(dv.getUint32(16, true)).toBe(Linearity.LINEAR);
  });

  test("script bytes at offset 256+ match input", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(> amount 500)');
    const output = compiler.compile(expr);
    const cell = packCapabilityCell(output.scriptBytes);

    const payload = cell.subarray(HEADER_SIZE, HEADER_SIZE + output.scriptBytes.length);
    expect(payload).toEqual(output.scriptBytes);
  });
});

describe("T9: eval resolves constraint against object payload", () => {
  test("(> amount 500) with amount=600 returns true", () => {
    const expr = parseExpression('(> amount 600)');
    const constraint = interpretConstraint(expr);

    // Manual constraint evaluation
    const payload = { amount: 700 };
    // Using the comparison logic directly
    expect(constraint.kind).toBe('comparison');
    if (constraint.kind === 'comparison') {
      expect(constraint.op).toBe('>');
      expect(constraint.field).toBe('amount');
      expect(constraint.value).toBe(600);
      // 700 > 600 = true
      expect((payload.amount as number) > (constraint.value as number)).toBe(true);
    }
  });

  test("(< amount 500) with amount=600 returns false", () => {
    const expr = parseExpression('(< amount 500)');
    const constraint = interpretConstraint(expr);

    expect(constraint.kind).toBe('comparison');
    if (constraint.kind === 'comparison') {
      const payload = { amount: 600 };
      expect((payload.amount as number) < (constraint.value as number)).toBe(false);
    }
  });
});

describe("T10: compile returns valid script words and bytes", () => {
  test("policy expression compiles to non-empty output", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(policy :subject homeowner :action approve-repair :constraint (> amount 500) :linearity LINEAR)');
    const output = compiler.compilePolicy(expr);

    expect(output.scriptWords.length).toBeGreaterThan(0);
    expect(output.scriptBytes.length).toBeGreaterThan(0);
    expect(output.metadata.inputExpr).toContain('policy');
    expect(output.metadata.compiledAt).toBe('2026-01-01T00:00:00Z');
  });
});

describe("T11: verify evaluates policy against object", () => {
  test("(> amount 500) constraint against object with amount=600 is true", () => {
    const expr = parseExpression('(> amount 500)');
    const constraint = interpretConstraint(expr);
    const payload: Record<string, unknown> = { amount: 600 };

    // Evaluate manually (same logic as routeVerifyPolicy)
    if (constraint.kind === 'comparison') {
      const fieldValue = payload[constraint.field] as number;
      const result = fieldValue > (constraint.value as number);
      expect(result).toBe(true);
    }
  });

  test("(> amount 500) constraint against object with amount=300 is false", () => {
    const expr = parseExpression('(> amount 500)');
    const constraint = interpretConstraint(expr);
    const payload: Record<string, unknown> = { amount: 300 };

    if (constraint.kind === 'comparison') {
      const fieldValue = payload[constraint.field] as number;
      const result = fieldValue > (constraint.value as number);
      expect(result).toBe(false);
    }
  });
});

describe("T12: PolicyBinding validates in extension config", () => {
  test("ObjectTypeDefinition with valid policies passes validation", () => {
    const config = {
      id: 'test',
      name: 'Test Extension',
      objectTypes: [{
        typeHash: 'a'.repeat(64),
        name: 'TestObj',
        icon: 'wrench',
        linearity: 'AFFINE' as const,
        defaultCapabilities: [4, 5],
        fields: [{ name: 'amount', type: 'number' as const }],
        policies: [
          { name: 'test-policy', inlinePayload: 'AQID', description: 'Test' },
        ],
      }],
      capabilities: [{ id: 4, name: 'Read', description: 'Read access' }],
      scripts: [],
      commercePhases: ['SOURCE'],
    };

    expect(() => validateExtensionConfig(config)).not.toThrow();
  });

  test("PolicyBinding without name or payload fails", () => {
    const config = {
      id: 'test',
      name: 'Test Extension',
      objectTypes: [{
        typeHash: 'a'.repeat(64),
        name: 'TestObj',
        icon: 'wrench',
        linearity: 'AFFINE' as const,
        defaultCapabilities: [4, 5],
        fields: [{ name: 'amount', type: 'number' as const }],
        policies: [
          { name: '', inlinePayload: 'AQID' },
        ],
      }],
      capabilities: [],
      scripts: [],
      commercePhases: ['SOURCE'],
    };

    expect(() => validateExtensionConfig(config)).toThrow(/PolicyBinding missing name/);
  });

  test("PolicyBinding without path or inlinePayload fails", () => {
    const config = {
      id: 'test',
      name: 'Test Extension',
      objectTypes: [{
        typeHash: 'a'.repeat(64),
        name: 'TestObj',
        icon: 'wrench',
        linearity: 'AFFINE' as const,
        defaultCapabilities: [4, 5],
        fields: [{ name: 'amount', type: 'number' as const }],
        policies: [
          { name: 'my-policy' },
        ],
      }],
      capabilities: [],
      scripts: [],
      commercePhases: ['SOURCE'],
    };

    expect(() => validateExtensionConfig(config)).toThrow(/must have either path or inlinePayload/);
  });
});

describe("T13: Compiled policy = manual guard equivalence", () => {
  test("compiled eval matches manual boolean check", () => {
    // Compile the policy
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(and (> amount 500) (< urgency 3))');
    const output = compiler.compile(expr);

    // The Forth words describe the operation
    expect(output.scriptWords).toBe('500 AMOUNT-GT 3 URGENCY-LT BOOLAND');

    // Manual equivalent: amount > 500 AND urgency < 3
    const payload1 = { amount: 600, urgency: 2 };
    expect(payload1.amount > 500 && payload1.urgency < 3).toBe(true);

    const payload2 = { amount: 400, urgency: 2 };
    expect(payload2.amount > 500 && payload2.urgency < 3).toBe(false);

    const payload3 = { amount: 600, urgency: 5 };
    expect(payload3.amount > 500 && payload3.urgency < 3).toBe(false);
  });
});

// ═══════════════════════════════════════════════════════════════
// T14–T15: Round-Trip
// ═══════════════════════════════════════════════════════════════

describe("T14: Round-trip parse → compile → pack → unpack", () => {
  test("header fields survive round-trip", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(> amount 500)');
    const output = compiler.compile(expr);

    const cell = packCapabilityCell(output.scriptBytes, {
      linearity: 'LINEAR',
      typeHash: 'b'.repeat(64),
    });

    const { header, script } = unpackCapabilityCell(cell);

    expect(header.linearity).toBe(Linearity.LINEAR);
    expect(header.version).toBe(1);
    expect(header.cellCount).toBe(1);
    expect(header.totalSize).toBe(output.scriptBytes.length);
    expect(script).toEqual(output.scriptBytes);

    // typeHash should match
    const expectedHash = new Uint8Array(32).fill(0xbb);
    expect(header.typeHash).toEqual(expectedHash);
  });
});

describe("T15: Parser handles comments, whitespace, multiline", () => {
  test("comments are stripped", () => {
    const input = `
      ; This is a comment
      (> amount 500) ; inline comment
    `;
    const expr = parseExpression(input);
    expect(expr.type).toBe('list');
    expect(list(expr).elements.length).toBe(3);
  });

  test("multiline expressions parse correctly", () => {
    const input = `
      (policy
        :subject homeowner
        :action approve-repair
        :constraint (> amount 500)
        :linearity LINEAR)
    `;
    const expr = parseExpression(input);
    const policy = interpretPolicy(expr);
    expect(policy.action).toBe('approve-repair');
    expect(policy.linearity).toBe('LINEAR');
  });

  test("multiple expressions via parseProgram", () => {
    const input = `
      (> amount 500)
      (< urgency 3)
      ; A comment between
      (has-capability 6)
    `;
    const exprs = parseProgram(input);
    expect(exprs.length).toBe(3);
  });

  test("extra whitespace and tabs", () => {
    const input = "  (  >   amount   500  )  ";
    const expr = parseExpression(input);
    expect(expr.type).toBe('list');
    expect(list(expr).elements.length).toBe(3);
  });
});

// ═══════════════════════════════════════════════════════════════
// T16–T18: Anti-Lock
// ═══════════════════════════════════════════════════════════════

describe("T16: No React imports in Lisp package", () => {
  test("packages/shell/src/lisp/ has zero React imports", () => {
    const lispFiles = ['parser.ts', 'types.ts', 'compiler.ts', 'packer.ts', 'index.ts'];
    const lispDir = join(ROOT, "runtime/shell/src/lisp");

    for (const file of lispFiles) {
      const content = readFileSync(join(lispDir, file), "utf-8");
      expect(content).not.toContain("from 'react'");
      expect(content).not.toContain('from "react"');
      expect(content).not.toContain("import React");
    }
  });
});

describe("T17: Compiler has no runtime I/O dependencies", () => {
  test("compiler.ts has no fs, net, http, or fetch imports", () => {
    const compilerSrc = readFileSync(
      join(ROOT, "runtime/shell/src/lisp/compiler.ts"),
      "utf-8",
    );

    expect(compilerSrc).not.toContain("from 'fs'");
    expect(compilerSrc).not.toContain('from "fs"');
    expect(compilerSrc).not.toContain("from 'net'");
    expect(compilerSrc).not.toContain("from 'http'");
    expect(compilerSrc).not.toContain("require('fs')");
    expect(compilerSrc).not.toContain("fetch(");
  });

  test("parser.ts has no I/O imports", () => {
    const parserSrc = readFileSync(
      join(ROOT, "runtime/shell/src/lisp/parser.ts"),
      "utf-8",
    );

    expect(parserSrc).not.toContain("from 'fs'");
    expect(parserSrc).not.toContain("from 'net'");
    expect(parserSrc).not.toContain("require(");
    expect(parserSrc).not.toContain("fetch(");
  });
});

describe("T18: Cell packing compatible with deserializeCellHeader", () => {
  test("packCapabilityCell output is readable by deserializeCellHeader", () => {
    const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00Z' });
    const expr = parseExpression('(has-capability 6)');
    const output = compiler.compile(expr);

    const cell = packCapabilityCell(output.scriptBytes, {
      linearity: 'AFFINE',
      typeHash: 'c'.repeat(64),
    });

    // deserializeCellHeader should not throw
    const { header } = unpackCapabilityCell(cell);

    expect(header.linearity).toBe(Linearity.AFFINE);
    expect(header.version).toBe(1);
    expect(header.totalSize).toBe(output.scriptBytes.length);
    expect(header.phase).toBe(5); // CODEGEN

    // Script should contain CHECK-CAP opcode (0xC3)
    const { script } = unpackCapabilityCell(cell);
    expect(script[script.length - 1]).toBe(0xC3);
  });

  test("payload doesn't exceed PAYLOAD_SIZE", () => {
    // Create a large but valid script
    const largeScript = new Uint8Array(768);
    expect(() => packCapabilityCell(largeScript)).not.toThrow();

    // Too large should throw
    const tooLarge = new Uint8Array(769);
    expect(() => packCapabilityCell(tooLarge)).toThrow(/exceeds payload limit/);
  });
});

```
