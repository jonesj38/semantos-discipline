---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/compile-to-sir.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.813875+00:00
---

# core/semantos-sir/src/compile-to-sir.ts

```ts
/**
 * compileToSIR — wrap a ConstraintExpr as a trivial SIR program.
 *
 * The "seam" that lets the Lisp compiler's output route through SIR before
 * being lowered to OIR. Phase 3d of the restructure: implement the trivial
 * identity pass so that for the existing Lisp golden corpus,
 *
 *   canonicalize(lower(expr))  ≡  canonicalize(lowerSIR(compileToSIR(expr)).program)
 *
 * Neutral governance context (informal trust, no proof required, local
 * authority) keeps the lowering pass's trust-tier enforcement quiet — the
 * Lisp layer doesn't carry governance semantics. When a richer surface
 * grammar lands (LaTeX, Ricardian), it populates governance directly.
 *
 * Scope: supports ConstraintExpr kinds that have a clean SIR equivalent
 * (comparison, capability, domainCheck, timeConstraint, logical, hostCall).
 * typeHashCheck and deref have no SIR equivalent yet — compileToSIR throws
 * rather than producing a lossy round-trip. This is deliberate: a failing
 * program in the golden-equivalence test is the design signal that SIR
 * needs an extension, not that the wiring is broken.
 */

import type { ConstraintExpr } from "@semantos/semantos-ir/expr";
import type {
  SIRProgram,
  SIRNode,
  SIRConstraint,
  GovernanceContext,
  TaxonomyCoordinates,
  SIRIdentity,
  SIRProvenance,
} from "./types";

/**
 * Neutral governance — no trust claims, no proof obligations, local execution.
 * TrustClass = 'cosmetic' (weakest defined tier). Lisp doesn't carry governance
 * semantics, so defaults satisfy lowerSIR's trust-tier enforcement silently.
 */
const NEUTRAL_GOVERNANCE: GovernanceContext = {
  trustClass: "cosmetic",
  proofRequirement: "none",
  executionAuthority: "local_facet",
  linearity: "AFFINE",
};

const NEUTRAL_TAXONOMY: TaxonomyCoordinates = {
  what: "lisp.compiled",
  how: "identity-lowering",
  why: "seam",
};

const NEUTRAL_IDENTITY: SIRIdentity = {
  subject: { type: "role", name: "lisp-compiler" },
};

const NEUTRAL_PROVENANCE: SIRProvenance = {
  source: "manual",
  expressedAt: "1970-01-01T00:00:00.000Z",
  trustAtExpression: "cosmetic",
};

/**
 * Convert a ConstraintExpr into a SIRConstraint. Structure-preserving —
 * every AST node maps 1:1 to an SIR node of compatible shape.
 */
function constraintExprToSIRConstraint(expr: ConstraintExpr): SIRConstraint {
  switch (expr.kind) {
    case "comparison":
      return {
        kind: "value",
        field: expr.field,
        op: expr.op,
        value: expr.value,
      };

    case "capability":
      return {
        kind: "capability",
        required: expr.capabilityNumber,
        name: `cap-${expr.capabilityNumber}`,
      };

    case "domainCheck":
      return {
        kind: "domain",
        flag: expr.domainFlag,
      };

    case "timeConstraint":
      return {
        kind: "temporal",
        op: expr.op === "timeAfter" ? "after" : "before",
        iso: expr.isoTimestamp,
      };

    case "hostCall":
      return {
        kind: "interlock",
        policyId: expr.functionName,
        policyName: expr.functionName,
      };

    case "logical":
      return {
        kind: "composite",
        op: expr.op,
        children: expr.operands.map(constraintExprToSIRConstraint),
      };

    case "typeHashCheck":
    case "deref":
      throw new Error(
        `compileToSIR: ConstraintExpr kind '${expr.kind}' has no SIR equivalent yet. ` +
        `Extend SIRConstraint if this path needs the trivial seam to round-trip.`,
      );
  }
}

/**
 * Wrap a ConstraintExpr as a single-node SIRProgram with neutral governance.
 * The node's jural category is 'declaration' — a neutral assertion, since
 * the Lisp layer doesn't carry jural semantics.
 */
export function compileToSIR(expr: ConstraintExpr): SIRProgram {
  const sirConstraint = constraintExprToSIRConstraint(expr);

  const node: SIRNode = {
    id: "$s0",
    // TaggedCategory — jural/declaration is the neutral default the
    // Lisp layer produces. Richer surface grammars populate this with
    // the lexicon + category they're authoring under.
    category: { lexicon: 'jural', category: 'declaration' },
    taxonomy: NEUTRAL_TAXONOMY,
    identity: NEUTRAL_IDENTITY,
    governance: NEUTRAL_GOVERNANCE,
    action: "compile",
    constraint: sirConstraint,
    provenance: NEUTRAL_PROVENANCE,
  };

  return {
    nodes: [node],
    primaryNodeId: "$s0",
    programGovernance: NEUTRAL_GOVERNANCE,
  };
}

```
