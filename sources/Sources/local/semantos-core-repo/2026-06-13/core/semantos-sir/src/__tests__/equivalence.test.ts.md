---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/__tests__/equivalence.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.816177+00:00
---

# core/semantos-sir/src/__tests__/equivalence.test.ts

```ts
/**
 * SIR wiring equivalence test — Phase 3d.
 *
 * Proves that for every supported Lisp expression, the new pipeline
 *
 *   ConstraintExpr ──compileToSIR──► SIRProgram ──lowerSIR──► IRProgram
 *
 * produces an IR program α-equivalent (same canonicalized JSON) to the
 * direct `lower()` path that has always shipped:
 *
 *   ConstraintExpr ──lower──► IRProgram
 *
 * α-equivalence, not byte-identity: the two passes may generate binding
 * names in different orders ($0 vs $s0), so we compare the canonicalized
 * programs after stripping names. This is the seam's contract — adding
 * the SIR layer must not change observable behaviour for the existing
 * Lisp corpus.
 */

import { describe, test, expect } from "bun:test";
import { lower, canonicalize } from "@semantos/semantos-ir";
import type {
  IRProgram,
  IRBinding,
} from "@semantos/semantos-ir/types";
import type { ConstraintExpr } from "@semantos/semantos-ir/expr";
import { compileToSIR } from "../compile-to-sir";
import { lowerSIR } from "../lower-sir";

/**
 * Strip binding names (they're counter-generated and can differ between
 * passes). Rewire cross-binding references in the same stripping step so
 * the program remains structurally comparable.
 */
function alphaNormalize(program: IRProgram): IRProgram {
  // Old name → new canonical name (sequential)
  const rename = new Map<string, string>();
  program.bindings.forEach((b, i) => rename.set(b.name, `#${i}`));

  const renamed = program.bindings.map((b): IRBinding => {
    const next: IRBinding = { ...b, name: rename.get(b.name)! };
    // logical_* bindings reference operand names
    if (next.kind === "logical_and" || next.kind === "logical_or" || next.kind === "logical_not") {
      const l = next as Extract<IRBinding, { operands: string[] }>;
      l.operands = l.operands.map((op) => rename.get(op) ?? op);
    }
    return next;
  });

  return {
    ...program,
    bindings: renamed,
    rootBinding: rename.get(program.rootBinding) ?? program.rootBinding,
  };
}

function equivalentPrograms(a: IRProgram, b: IRProgram): boolean {
  return canonicalize(alphaNormalize(a)) === canonicalize(alphaNormalize(b));
}

function lowerDirect(expr: ConstraintExpr): IRProgram {
  return lower(expr);
}

function lowerViaSIR(expr: ConstraintExpr): IRProgram {
  const result = lowerSIR(compileToSIR(expr));
  if (!result.ok) {
    throw new Error(`lowerSIR rejected trivial wrapping: ${result.code} — ${result.message}`);
  }
  return result.program;
}

// ── Corpus ───────────────────────────────────────────────────────
// Each entry is a ConstraintExpr we expect to round-trip. Covers the
// kinds SIRConstraint supports: comparison, capability, domainCheck,
// timeConstraint, hostCall, logical (and/or/not).

const CORPUS: Array<{ name: string; expr: ConstraintExpr }> = [
  {
    name: "capability(7)",
    expr: { kind: "capability", capabilityNumber: 7 },
  },
  {
    name: "domainCheck(5)",
    expr: { kind: "domainCheck", domainFlag: 5 },
  },
  {
    name: "comparison amount > 100",
    expr: { kind: "comparison", op: ">", field: "amount", value: 100 },
  },
  {
    name: "comparison phase = draft",
    expr: { kind: "comparison", op: "=", field: "phase", value: "draft" },
  },
  {
    name: "timeConstraint after 2026-01-01",
    expr: { kind: "timeConstraint", op: "timeAfter", isoTimestamp: "2026-01-01T00:00:00.000Z" },
  },
  // NOTE: hostCall deliberately NOT in the round-trip corpus. See the
  // `hostCall is a known non-equivalence` test below for the rationale.
  {
    name: "logical AND (cap, domain)",
    expr: {
      kind: "logical",
      op: "and",
      operands: [
        { kind: "capability", capabilityNumber: 2 },
        { kind: "domainCheck", domainFlag: 1 },
      ],
    },
  },
  {
    name: "logical OR (cmp, cap)",
    expr: {
      kind: "logical",
      op: "or",
      operands: [
        { kind: "comparison", op: "<", field: "y", value: 10 },
        { kind: "capability", capabilityNumber: 3 },
      ],
    },
  },
  {
    name: "logical NOT (comparison)",
    expr: {
      kind: "logical",
      op: "not",
      operands: [
        { kind: "comparison", op: ">", field: "x", value: 50 },
      ],
    },
  },
  {
    name: "nested AND of (OR, NOT)",
    expr: {
      kind: "logical",
      op: "and",
      operands: [
        {
          kind: "logical",
          op: "or",
          operands: [
            { kind: "comparison", op: ">", field: "x", value: 1 },
            { kind: "capability", capabilityNumber: 5 },
          ],
        },
        {
          kind: "logical",
          op: "not",
          operands: [{ kind: "domainCheck", domainFlag: 8 }],
        },
      ],
    },
  },
];

// ── Tests ────────────────────────────────────────────────────────

describe("Phase 3d — SIR seam α-equivalence against direct lower()", () => {
  for (const { name, expr } of CORPUS) {
    test(`${name}: compileToSIR → lowerSIR ≡ lower()`, () => {
      const direct = lowerDirect(expr);
      const viaSIR = lowerViaSIR(expr);
      expect(equivalentPrograms(direct, viaSIR)).toBe(true);
    });
  }

  test("hostCall is a known non-equivalence (SIR prefixes function names with 'interlock:')", () => {
    // SIR's `interlock` constraint lowers to a hostCall with the function
    // name prefixed by "interlock:" — a deliberate namespace convention.
    // That means a Lisp hostCall("X") does NOT round-trip through SIR as
    // the same hostCall("X") that direct lower() produces. This is a
    // semantic difference the seam surfaces, not a bug. If Lisp ever needs
    // to express "raw" hostCalls without the interlock framing, SIRConstraint
    // will need a new kind ('hostCall' or 'raw') and lowerSIR a corresponding
    // pass-through lowering. Keeping the test documents the finding.
    const expr: ConstraintExpr = { kind: "hostCall", functionName: "policy-check" };
    const direct = lowerDirect(expr);
    const viaSIR = lowerViaSIR(expr);
    expect(equivalentPrograms(direct, viaSIR)).toBe(false);
  });

  test("compileToSIR throws for typeHashCheck (no SIR equivalent yet)", () => {
    const expr: ConstraintExpr = {
      kind: "typeHashCheck",
      expectedHash: "00".repeat(32),
    };
    expect(() => compileToSIR(expr)).toThrow(/typeHashCheck/);
  });

  test("compileToSIR throws for deref (no SIR equivalent yet)", () => {
    const expr: ConstraintExpr = { kind: "deref" };
    expect(() => compileToSIR(expr)).toThrow(/deref/);
  });
});

```
