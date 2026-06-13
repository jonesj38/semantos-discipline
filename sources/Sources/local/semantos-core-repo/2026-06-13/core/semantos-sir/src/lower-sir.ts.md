---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/lower-sir.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.813596+00:00
---

# core/semantos-sir/src/lower-sir.ts

```ts
/**
 * SIR → OIR lowering pass.
 *
 * Converts semantic jural categories into computational predicates (ANF bindings).
 * Trust-tier enforcement is structural — the lowering pass refuses to produce
 * OIR if governance constraints are violated.
 *
 * Pipeline:  SIRProgram ──lowerSIR()──► IRProgram ──emit()──► Uint8Array
 */

import type { IRBinding, IRKind, IRProgram } from '@semantos/semantos-ir/types';
import type {
  SIRProgram,
  SIRNode,
  SIRConstraint,
  LoweringResult,
  GovernanceContext,
} from './types';
import type {
  AuthorityVerifier,
  AuthorityVerificationResult,
  LexiconAuthority,
} from './authority';
import { RejectAuthorityVerifier } from './authority';

// ── Name Generator ───────────────────────────────────────────

class NameGen {
  private counter = 0;
  next(): string {
    return `$${this.counter++}`;
  }
}

// ── Trust-Tier Enforcement ───────────────────────────────────

function enforceTrustTier(governance: GovernanceContext): LoweringResult | null {
  if (governance.trustClass === 'authoritative' && governance.proofRequirement !== 'formal') {
    return {
      ok: false,
      code: 'TRUST_TIER_VIOLATION',
      message: `Cannot lower authoritative expression without formal proof requirement`,
    };
  }
  if (governance.executionAuthority === 'delegated') {
    return {
      ok: false,
      code: 'DELEGATED_NOT_IMPLEMENTED',
      message: `Delegated execution authority not yet implemented`,
    };
  }
  return null;
}

// ── AllowedEmitOps Enforcement ───────────────────────────────

function enforceAllowedEmitOps(
  bindings: IRBinding[],
  allowedEmitOps: string[],
  nodeId: string,
): LoweringResult | null {
  for (const binding of bindings) {
    if (!allowedEmitOps.includes(binding.kind)) {
      return {
        ok: false,
        code: 'EMIT_OP_NOT_ALLOWED',
        message: `OIR binding kind '${binding.kind}' not in allowedEmitOps for ${nodeId}. Whitelist: [${allowedEmitOps.join(', ')}]`,
      };
    }
  }
  return null;
}

// ── Constraint Lowering ──────────────────────────────────────

/**
 * Lower a SIR constraint to OIR bindings. Returns the binding name
 * of the result (so parent expressions can reference it).
 */
function lowerConstraint(
  constraint: SIRConstraint,
  names: NameGen,
  bindings: IRBinding[],
): string {
  switch (constraint.kind) {
    case 'capability': {
      const name = names.next();
      bindings.push({ name, kind: 'capability', capabilityNumber: constraint.required });
      return name;
    }
    case 'domain': {
      const name = names.next();
      bindings.push({ name, kind: 'domainCheck', domainFlag: constraint.flag });
      return name;
    }
    case 'identity': {
      // Identity refs lower as domain checks for domainFlag type,
      // or as a no-op for role/cert patterns (the governance plane handles those).
      const ref = constraint.ref;
      if (ref.type === 'domainFlag') {
        const name = names.next();
        bindings.push({ name, kind: 'domainCheck', domainFlag: ref.flag });
        return name;
      }
      // For role/cert patterns, emit a placeholder domain check.
      // The governance plane provides the actual verification.
      const name = names.next();
      bindings.push({ name, kind: 'domainCheck', domainFlag: ref.type === 'role' ? ref.name : 0 });
      return name;
    }
    case 'temporal': {
      const name = names.next();
      const timeOp = constraint.op === 'after' ? 'timeAfter' as const : 'timeBefore' as const;
      const timestamp = Math.floor(new Date(constraint.iso).getTime() / 1000);
      bindings.push({ name, kind: 'timeConstraint', timeOp, timestamp });
      return name;
    }
    case 'value': {
      const name = names.next();
      bindings.push({
        name,
        kind: 'comparison',
        op: constraint.op,
        field: constraint.field,
        value: constraint.value,
      });
      return name;
    }
    case 'state': {
      // State constraints lower as a comparison against the 'phase' field.
      const name = names.next();
      bindings.push({
        name,
        kind: 'comparison',
        op: '=',
        field: 'phase',
        value: constraint.requiredPhase,
      });
      return name;
    }
    case 'interlock': {
      // Interlock policies lower as a host call referencing the policy.
      const name = names.next();
      bindings.push({
        name,
        kind: 'hostCall',
        functionName: `interlock:${constraint.policyId}`,
      });
      return name;
    }
    case 'composite': {
      // Lower all children first, then emit the combinator.
      const childNames = constraint.children.map(c => lowerConstraint(c, names, bindings));

      if (constraint.op === 'not') {
        // NOT applies to the single child.
        const name = names.next();
        bindings.push({ name, kind: 'logical_not', operands: [childNames[0]] });
        return name;
      }

      const kind: IRKind = constraint.op === 'and' ? 'logical_and' : 'logical_or';
      const name = names.next();
      bindings.push({ name, kind, operands: childNames });
      return name;
    }
    case 'relation': {
      // SCG typed-relation constraint (RM-020). Phase-1 lowering is a
      // composite of:
      //   1. Capability check on RELATION_MINT (0x0001000c per RM-004) —
      //      authoring identity holds the mint capability.
      //   2. typeHashCheck against a sentinel hash derived from the
      //      RelationKind — "this script is over a kind-X SCG relation".
      //
      // sourceId / targetId are metadata only at this layer (relations
      // are sem_objects rows, not kernel cells, in Phase 1). RM-082
      // replaces the sentinel with a real payload-binding predicate
      // once the schema registry lands.
      const capName = names.next();
      bindings.push({
        name: capName,
        kind: 'capability',
        capabilityNumber: SCG_RELATION_MINT_CAPABILITY,
      });

      const hashName = names.next();
      bindings.push({
        name: hashName,
        kind: 'typeHashCheck',
        expectedHash: `scg.relation:${constraint.relationKind}`,
      });

      const andName = names.next();
      bindings.push({
        name: andName,
        kind: 'logical_and',
        operands: [capName, hashName],
      });
      return andName;
    }
  }
}

/**
 * `RELATION_MINT` capability slot per RM-004 (recorded in
 * `docs/SCG-AND-PHASE-H-ROADMAP.md`). Numeric value is applied to
 * `ClientDomainFlags` by RM-022 when capability binding is wired in.
 */
const SCG_RELATION_MINT_CAPABILITY = 0x0001000c;

// ── Category-Specific Lowering ───────────────────────────────

/**
 * Lower a SIR node to OIR bindings based on its (lexicon, category)
 * pair. The outer gate on `node.category.lexicon` routes to the
 * lexicon's lowering profile; the inner switch handles per-category
 * patterns within that lexicon.
 *
 * Jural is the fully-specialised lexicon (the 7 canonical patterns
 * below). Other lexicons (control-systems, cdm, bills-of-lading,
 * project-management, property-management, risk-assessment,
 * circuit-commands) currently fall back to constraint-only lowering
 * — a safe default that preserves the intent's constraint semantics
 * without inventing lowering rules we haven't validated yet. Lexicon-
 * specific rules can plug in here as patterns solidify in each
 * domain.
 */
function lowerCategory(
  node: SIRNode,
  names: NameGen,
  bindings: IRBinding[],
): string {
  // Non-jural lexicons: safe default — lower the constraint directly.
  // Extensions that need richer per-category lowering add a branch
  // before this fallback.
  if (node.category.lexicon !== 'jural') {
    return lowerConstraint(node.constraint, names, bindings);
  }

  // Jural lexicon: the 7 Hohfeldian categories get bespoke lowering
  // patterns that carry governance intent through to OIR.
  switch (node.category.category) {
    case 'declaration': {
      // Declaration → identity/domain check + constraint assertions + logical_and
      const constraintName = lowerConstraint(node.constraint, names, bindings);
      return constraintName;
    }

    case 'obligation': {
      // Obligation → constraint + temporal gate (deadline) + logical_and
      const parts: string[] = [];
      parts.push(lowerConstraint(node.constraint, names, bindings));

      // Add temporal gate from fulfillment deadline if present.
      if (node.fulfillment?.deadline) {
        const deadlineName = names.next();
        const timestamp = Math.floor(new Date(node.fulfillment.deadline).getTime() / 1000);
        bindings.push({ name: deadlineName, kind: 'timeConstraint', timeOp: 'timeBefore', timestamp });
        parts.push(deadlineName);
      }

      if (parts.length === 1) return parts[0];
      const andName = names.next();
      bindings.push({ name: andName, kind: 'logical_and', operands: parts });
      return andName;
    }

    case 'permission': {
      // Permission → capability check (the simplest lowering)
      return lowerConstraint(node.constraint, names, bindings);
    }

    case 'prohibition': {
      // Prohibition → constraint + NOT (the dangerous condition must NOT hold)
      const innerName = lowerConstraint(node.constraint, names, bindings);
      const notName = names.next();
      bindings.push({ name: notName, kind: 'logical_not', operands: [innerName] });
      return notName;
    }

    case 'power': {
      // Power → identity/domain check + capability + optional typeHashCheck + logical_and
      const parts: string[] = [];
      parts.push(lowerConstraint(node.constraint, names, bindings));

      // Add type hash check if target has one.
      if (node.target?.typeHash) {
        const hashName = names.next();
        bindings.push({ name: hashName, kind: 'typeHashCheck', expectedHash: node.target.typeHash });
        parts.push(hashName);
      }

      if (parts.length === 1) return parts[0];
      const andName = names.next();
      bindings.push({ name: andName, kind: 'logical_and', operands: parts });
      return andName;
    }

    case 'condition': {
      // Condition → temporal or state predicate
      if (node.gate) {
        if (node.gate.type === 'temporal' && node.gate.deadline) {
          const name = names.next();
          const timestamp = Math.floor(new Date(node.gate.deadline).getTime() / 1000);
          bindings.push({ name, kind: 'timeConstraint', timeOp: 'timeAfter', timestamp });
          return name;
        }
        if (node.gate.type === 'state' && node.gate.requiredPhase) {
          const name = names.next();
          bindings.push({ name, kind: 'comparison', op: '=', field: 'phase', value: node.gate.requiredPhase });
          return name;
        }
        if (node.gate.type === 'value' && node.gate.threshold) {
          const name = names.next();
          const { field, op, value } = node.gate.threshold;
          bindings.push({ name, kind: 'comparison', op, field, value });
          return name;
        }
      }
      // Fallback: lower the node's constraint directly.
      return lowerConstraint(node.constraint, names, bindings);
    }

    case 'transfer': {
      // Transfer → identity/domain check (sender) + capability checks + logical_and
      const parts: string[] = [];
      parts.push(lowerConstraint(node.constraint, names, bindings));

      if (parts.length === 1) return parts[0];
      const andName = names.next();
      bindings.push({ name: andName, kind: 'logical_and', operands: parts });
      return andName;
    }
  }
}

// ── Authority enforcement (D-A6) ─────────────────────────────

/**
 * If the program declares a lexicon authority, fold the verification
 * result into a `LoweringResult` rejection on failure. On success,
 * returns null and the caller continues lowering.
 *
 * The sync `lowerSIR` accepts a pre-computed verification result so it
 * can stay synchronous (the verifier itself may be async — the
 * `lowerSIRWithAuthority` async wrapper drives it). Direct callers of
 * `lowerSIR` that pass an `authority` without a precomputed result get
 * a `LEXICON_AUTHORITY_INVALID` rejection — the safe default that
 * forces an explicit verification path.
 */
function enforceAuthority(
  authority: LexiconAuthority | undefined,
  precomputed: AuthorityVerificationResult | null,
): LoweringResult | null {
  if (!authority) return null; // No authority declared — neutral seam.
  if (!precomputed) {
    return {
      ok: false,
      code: 'LEXICON_AUTHORITY_INVALID',
      message:
        'lowerSIR called with an authority but no verification result; ' +
        'use lowerSIRWithAuthority or pre-verify and pass through opts',
    };
  }
  if (!precomputed.ok) {
    const code =
      precomputed.code === 'grammar_signature_invalid' ||
      precomputed.code === 'grammar_signature_missing'
        ? 'GRAMMAR_SIGNATURE_INVALID'
        : 'LEXICON_AUTHORITY_INVALID';
    return {
      ok: false,
      code,
      message: `${precomputed.code}: ${precomputed.message}`,
    };
  }
  return null;
}

// ── Public API ───────────────────────────────────────────────

/**
 * Options accepted by `lowerSIR`. `authorityVerification` lets a caller
 * (typically `lowerSIRWithAuthority`) pre-verify the program's
 * `authority` field and pass the result in synchronously.
 */
export interface LowerSIROptions {
  /**
   * Pre-computed authority verification result. Required when the
   * program declares an `authority` and the call is synchronous; the
   * async `lowerSIRWithAuthority` wrapper computes this for you.
   */
  authorityVerification?: AuthorityVerificationResult;
}

/**
 * Lower a SIR program to OIR. Returns a structured result — never throws.
 *
 * Enforcement points:
 *   1. Trust-tier: authoritative requires formal proof
 *   2. Execution authority: delegated is rejected
 *   3. AllowedEmitOps: emitted binding kinds must be in the whitelist
 *   4. Lexicon authority (D-A6): if `program.authority` is set, the
 *      pre-computed verification result MUST be ok. Failure surfaces
 *      as `LEXICON_AUTHORITY_INVALID` or `GRAMMAR_SIGNATURE_INVALID`.
 */
export function lowerSIR(program: SIRProgram, opts: LowerSIROptions = {}): LoweringResult {
  // Find primary node.
  const primary = program.nodes.find(n => n.id === program.primaryNodeId);
  if (!primary) {
    return {
      ok: false,
      code: 'PRIMARY_NODE_NOT_FOUND',
      message: `No node with id '${program.primaryNodeId}' in program`,
    };
  }

  // Trust-tier enforcement on both program governance and node governance.
  const programTierError = enforceTrustTier(program.programGovernance);
  if (programTierError) return programTierError;

  const nodeTierError = enforceTrustTier(primary.governance);
  if (nodeTierError) return nodeTierError;

  // Authority enforcement (D-A6) — fail fast if the declared authority
  // didn't verify. If no authority is declared, this is a no-op.
  const authorityError = enforceAuthority(
    program.authority,
    opts.authorityVerification ?? null,
  );
  if (authorityError) return authorityError;

  // Lower the primary node.
  const names = new NameGen();
  const bindings: IRBinding[] = [];
  let result = lowerCategory(primary, names, bindings);

  // Domain binding enforcement: emit domainCheck for bound flag (and parent).
  const db = primary.governance.domainBinding;
  if (db) {
    const domainParts: string[] = [result];

    // Child domain flag check.
    const childName = names.next();
    bindings.push({ name: childName, kind: 'domainCheck', domainFlag: db.flag });
    domainParts.push(childName);

    // Parent domain flag check (hierarchical enforcement).
    if (db.parentFlag !== undefined) {
      const parentName = names.next();
      bindings.push({ name: parentName, kind: 'domainCheck', domainFlag: db.parentFlag });
      domainParts.push(parentName);
    }

    // AND everything together.
    const andName = names.next();
    bindings.push({ name: andName, kind: 'logical_and', operands: domainParts });
    result = andName;
  }

  // Authority-scope binding (D-A6): when a verified authority is
  // declared, AND the result of the primary lowering with the program's
  // own bindings, with a domainCheck whose flag IS the authority's
  // cert_id. Two extensions with different cert_ids → different
  // domainFlag values → kernel OP_CHECKDOMAINFLAG refuses to satisfy a
  // capability mint with the wrong authority. This is the structural
  // boundary for capability-scope isolation.
  if (program.authority) {
    const authorityName = names.next();
    bindings.push({
      name: authorityName,
      kind: 'domainCheck',
      // Passing the cert_id as the domainFlag value (string form) keeps
      // the kernel-side check uniform with normal domain-flag matching.
      // The OP_CHECKDOMAINFLAG implementation hashes the string when the
      // flag is non-numeric (existing behaviour for the 'role' identity
      // pattern in lowerConstraint).
      domainFlag: program.authority.cert.certId,
    });
    const andName = names.next();
    bindings.push({
      name: andName,
      kind: 'logical_and',
      operands: [result, authorityName],
    });
    result = andName;
  }

  // AllowedEmitOps enforcement.
  if (primary.governance.allowedEmitOps) {
    const emitOpsError = enforceAllowedEmitOps(bindings, primary.governance.allowedEmitOps, primary.id);
    if (emitOpsError) return emitOpsError;
  }

  return { ok: true, program: { bindings, result } };
}

/**
 * Async wrapper around `lowerSIR` that drives an `AuthorityVerifier` to
 * verify `program.authority` (when present) before delegating to the
 * synchronous lowering pass.
 *
 * Programs with no authority pass through unchanged (verifier never
 * called). Programs with an authority but no `verifier` argument get
 * the safe default: `RejectAuthorityVerifier` rejects them with
 * `LEXICON_AUTHORITY_INVALID`. This is K2-aligned — the lowering pass
 * MUST NOT silently accept an authority whose verification path was
 * never wired up.
 *
 * Use this entry point in adapters that load extensions
 * (`extension-loader`, the intent-pipeline's pre-lowering hook, etc.).
 * Tests and pure-data seams (`compileToSIR` for the Lisp identity) keep
 * using sync `lowerSIR` because they never declare an authority.
 */
export async function lowerSIRWithAuthority(
  program: SIRProgram,
  verifier: AuthorityVerifier = new RejectAuthorityVerifier(),
): Promise<LoweringResult> {
  if (!program.authority) {
    // No authority declared — synchronous path, no verification.
    return lowerSIR(program);
  }
  const verification = await verifier.verifyAuthority(program.authority);
  return lowerSIR(program, { authorityVerification: verification });
}

```
