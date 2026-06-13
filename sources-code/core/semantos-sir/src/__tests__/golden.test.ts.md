---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/__tests__/golden.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.815605+00:00
---

# core/semantos-sir/src/__tests__/golden.test.ts

```ts
/**
 * Golden-file test suite for the Semantic IR (SIR) lowering pass.
 *
 * Each test case:
 *   1. Constructs a SIRNode with a specific jural category
 *   2. Wraps it in a SIRProgram
 *   3. Lowers it via lowerSIR()
 *   4. Verifies the OIR structure matches expectations
 *
 * Tests SG1–SG7: one per jural category (declaration through transfer)
 * Tests SG8–SG10: trust-tier and allowedEmitOps enforcement rejections
 * Test  SG11: allowedEmitOps pass case
 * Test  SG12: end-to-end bytes via emit()
 */

import { describe, test, expect } from 'bun:test';
import { lowerSIR } from '../lower-sir';
import { emit } from '@semantos/semantos-ir';
import type { SIRNode, SIRProgram, GovernanceContext, SIRConstraint, DomainBinding } from '../types';

// ── Fixtures ─────────────────────────────────────────────────

/** Default governance context: interpretive, attestation, hat_scoped. */
function defaultGovernance(overrides: Partial<GovernanceContext> = {}): GovernanceContext {
  return {
    trustClass: 'interpretive',
    proofRequirement: 'attestation',
    executionAuthority: 'hat_scoped',
    linearity: 'LINEAR',
    ...overrides,
  };
}

/** Wrap a single SIR node in a program. */
function program(node: SIRNode, govOverrides: Partial<GovernanceContext> = {}): SIRProgram {
  return {
    nodes: [node],
    primaryNodeId: node.id,
    programGovernance: defaultGovernance(govOverrides),
  };
}

/** Default provenance. */
const prov = {
  source: 'manual' as const,
  expressedAt: '2026-04-17T00:00:00Z',
  trustAtExpression: 'interpretive' as const,
};

// ── SG1: Declaration ─────────────────────────────────────────

describe('Semantic IR — Golden-File Tests', () => {

  test('SG1: Declaration (CDM confirmation) → domainCheck + comparison + logical_and', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'declaration' },
      taxonomy: { what: 'rates.swap', how: 'lifecycle.confirmation', why: 'compliance' },
      identity: { subject: { type: 'domainFlag', flag: 0x05 } },
      governance: defaultGovernance(),
      action: 'confirm',
      constraint: {
        kind: 'composite', op: 'and', children: [
          { kind: 'domain', flag: 0x05 },
          { kind: 'value', field: 'status', op: '=', value: 'executed' },
        ],
      },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.program.bindings).toHaveLength(3);
    expect(result.program.bindings[0].kind).toBe('domainCheck');
    expect(result.program.bindings[0].domainFlag).toBe(0x05);
    expect(result.program.bindings[1].kind).toBe('comparison');
    expect(result.program.bindings[1].field).toBe('status');
    expect(result.program.bindings[1].value).toBe('executed');
    expect(result.program.bindings[2].kind).toBe('logical_and');
    expect(result.program.bindings[2].operands).toEqual(['$0', '$1']);
    expect(result.program.result).toBe('$2');
  });

  // ── SG2: Obligation ──────────────────────────────────────────

  test('SG2: Obligation (margin call with deadline) → domainCheck + timeConstraint + capability + logical_and', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'obligation' },
      taxonomy: { what: 'rates.swap', how: 'lifecycle.margin', why: 'risk-mitigation' },
      identity: { subject: { type: 'role', name: 'clearing-member' } },
      governance: defaultGovernance(),
      action: 'margin-post',
      constraint: {
        kind: 'composite', op: 'and', children: [
          { kind: 'domain', flag: 'clearing-member-flag' },
          { kind: 'capability', required: 5, name: 'METERING' },
        ],
      },
      fulfillment: {
        fulfilledBy: 'margin-receipt',
        deadline: '2026-04-22T17:00:00Z',
      },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    // Should have: domainCheck, capability, logical_and(constraint), timeBefore(deadline), logical_and(outer)
    const kinds = result.program.bindings.map(b => b.kind);
    expect(kinds).toContain('domainCheck');
    expect(kinds).toContain('capability');
    expect(kinds).toContain('timeConstraint');

    // The deadline should be a timeBefore.
    const timeBind = result.program.bindings.find(b => b.kind === 'timeConstraint');
    expect(timeBind?.timeOp).toBe('timeBefore');
    expect(timeBind?.timestamp).toBe(Math.floor(new Date('2026-04-22T17:00:00Z').getTime() / 1000));
  });

  // ── SG3: Permission ──────────────────────────────────────────

  test('SG3: Permission (valve capability) → single capability binding', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'permission' },
      taxonomy: { what: 'scada.valve', how: 'command.operate', why: 'operational' },
      identity: { subject: { type: 'role', name: 'shift-supervisor' } },
      governance: defaultGovernance(),
      action: 'operate-valves',
      constraint: { kind: 'capability', required: 3, name: 'OPERATE_VALVES' },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.program.bindings).toHaveLength(1);
    expect(result.program.bindings[0].kind).toBe('capability');
    expect(result.program.bindings[0].capabilityNumber).toBe(3);
    expect(result.program.result).toBe('$0');
  });

  // ── SG4: Prohibition ─────────────────────────────────────────

  test('SG4: Prohibition (pressure interlock) → comparison + logical_not', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'prohibition' },
      taxonomy: { what: 'scada.pressure', how: 'interlock.safety', why: 'safety-interlock' },
      identity: { subject: { type: 'role', name: 'system' } },
      governance: defaultGovernance(),
      action: 'valve.open',
      constraint: { kind: 'value', field: 'pressure', op: '>', value: 150 },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.program.bindings).toHaveLength(2);
    expect(result.program.bindings[0].kind).toBe('comparison');
    expect(result.program.bindings[0].field).toBe('pressure');
    expect(result.program.bindings[0].op).toBe('>');
    expect(result.program.bindings[0].value).toBe(150);
    expect(result.program.bindings[1].kind).toBe('logical_not');
    expect(result.program.bindings[1].operands).toEqual(['$0']);
    expect(result.program.result).toBe('$1');
  });

  // ── SG5: Power ────────────────────────────────────────────────

  test('SG5: Power (publish) → domainCheck + capability + typeHashCheck + logical_and', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'power' },
      taxonomy: { what: 'governance.manifest', how: 'lifecycle.publish', why: 'authority' },
      identity: { subject: { type: 'domainFlag', flag: 0x0a } },
      governance: defaultGovernance(),
      action: 'publish',
      constraint: {
        kind: 'composite', op: 'and', children: [
          { kind: 'domain', flag: 0x0a },
          { kind: 'capability', required: 5, name: 'PUBLISH' },
        ],
      },
      target: {
        typeHash: '1a3771053c73eca4ec4c5ef0c662811117e58a5ed1e49d499fda5ac37b7a0afd',
      },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const kinds = result.program.bindings.map(b => b.kind);
    expect(kinds).toContain('domainCheck');
    expect(kinds).toContain('capability');
    expect(kinds).toContain('typeHashCheck');
    expect(kinds).toContain('logical_and');

    const hashBind = result.program.bindings.find(b => b.kind === 'typeHashCheck');
    expect(hashBind?.expectedHash).toBe('1a3771053c73eca4ec4c5ef0c662811117e58a5ed1e49d499fda5ac37b7a0afd');
  });

  // ── SG6: Condition ────────────────────────────────────────────

  test('SG6: Condition (temporal gate) → single timeConstraint binding', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'condition' },
      taxonomy: { what: 'temporal', how: 'gate.after', why: 'contractual-mechanism' },
      identity: { subject: { type: 'role', name: 'system' } },
      governance: defaultGovernance({ linearity: 'AFFINE' }),
      action: 'evaluate',
      constraint: { kind: 'temporal', op: 'after', iso: '2026-04-22T00:00:00Z' },
      gate: { type: 'temporal', deadline: '2026-04-22T00:00:00Z' },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.program.bindings).toHaveLength(1);
    expect(result.program.bindings[0].kind).toBe('timeConstraint');
    expect(result.program.bindings[0].timeOp).toBe('timeAfter');
    expect(result.program.bindings[0].timestamp).toBe(Math.floor(new Date('2026-04-22T00:00:00Z').getTime() / 1000));
    expect(result.program.result).toBe('$0');
  });

  // ── SG7: Transfer ─────────────────────────────────────────────

  test('SG7: Transfer (settlement) → domainCheck + capability(TRANSFER) + capability(METERING) + logical_and', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'transfer' },
      taxonomy: { what: 'rates.swap', how: 'lifecycle.settlement', why: 'obligation-fulfillment' },
      identity: { subject: { type: 'domainFlag', flag: 0x03 } },
      governance: defaultGovernance(),
      action: 'settlement',
      constraint: {
        kind: 'composite', op: 'and', children: [
          { kind: 'domain', flag: 0x03 },
          { kind: 'capability', required: 9, name: 'TRANSFER' },
          { kind: 'capability', required: 5, name: 'METERING' },
        ],
      },
      transferTo: { subject: { type: 'domainFlag', flag: 0x04 } },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const kinds = result.program.bindings.map(b => b.kind);
    expect(kinds).toContain('domainCheck');
    expect(kinds.filter(k => k === 'capability')).toHaveLength(2);
    expect(kinds).toContain('logical_and');
  });

  // ── SG8: Trust-tier rejection ─────────────────────────────────

  test('SG8: Authoritative + non-formal → TRUST_TIER_VIOLATION', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'power' },
      taxonomy: { what: 'governance', how: 'lifecycle.publish', why: 'authority' },
      identity: { subject: { type: 'role', name: 'governor' } },
      governance: defaultGovernance({
        trustClass: 'authoritative',
        proofRequirement: 'attestation', // NOT formal — should be rejected
      }),
      action: 'publish',
      constraint: { kind: 'capability', required: 5, name: 'PUBLISH' },
      provenance: prov,
    };

    const result = lowerSIR(program(node, {
      trustClass: 'authoritative',
      proofRequirement: 'attestation',
    }));
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('TRUST_TIER_VIOLATION');
  });

  // ── SG9: Delegated rejection ──────────────────────────────────

  test('SG9: Delegated execution authority → DELEGATED_NOT_IMPLEMENTED', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'power' },
      taxonomy: { what: 'governance', how: 'lifecycle.publish', why: 'authority' },
      identity: { subject: { type: 'role', name: 'governor' } },
      governance: defaultGovernance({ executionAuthority: 'delegated' }),
      action: 'publish',
      constraint: { kind: 'capability', required: 5, name: 'PUBLISH' },
      provenance: prov,
    };

    const result = lowerSIR(program(node, { executionAuthority: 'delegated' }));
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('DELEGATED_NOT_IMPLEMENTED');
  });

  // ── SG10: AllowedEmitOps rejection ────────────────────────────

  test('SG10: AllowedEmitOps whitelist violation → EMIT_OP_NOT_ALLOWED', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'prohibition' },
      taxonomy: { what: 'scada.pressure', how: 'interlock.safety', why: 'safety' },
      identity: { subject: { type: 'role', name: 'system' } },
      governance: defaultGovernance({
        // Only allow comparison — logical_not will violate.
        allowedEmitOps: ['comparison'],
      }),
      action: 'valve.open',
      constraint: { kind: 'value', field: 'pressure', op: '>', value: 150 },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('EMIT_OP_NOT_ALLOWED');
    expect(result.message).toContain('logical_not');
  });

  // ── SG11: AllowedEmitOps pass ─────────────────────────────────

  test('SG11: AllowedEmitOps with correct whitelist → ok', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'prohibition' },
      taxonomy: { what: 'scada.pressure', how: 'interlock.safety', why: 'safety' },
      identity: { subject: { type: 'role', name: 'system' } },
      governance: defaultGovernance({
        allowedEmitOps: ['comparison', 'logical_not'],
      }),
      action: 'valve.open',
      constraint: { kind: 'value', field: 'pressure', op: '>', value: 150 },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.program.bindings).toHaveLength(2);
  });

  // ── SG12: End-to-end bytes ────────────────────────────────────

  test('SG12: Power node → lowerSIR → emit → bytes match manual OIR construction', () => {
    // SIR: power node with domainCheck + capability, verified against manual OIR.
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'power' },
      taxonomy: { what: 'host.process', how: 'exec.kill', why: 'operational' },
      identity: { subject: { type: 'domainFlag', flag: 0x0d } },
      governance: defaultGovernance(),
      action: 'host.exec',
      constraint: {
        kind: 'composite', op: 'and', children: [
          { kind: 'capability', required: 11, name: 'HOST_EXEC' },
          { kind: 'domain', flag: 0x0d },
        ],
      },
      provenance: { ...prov, source: 'voice' },
    };

    const sirResult = lowerSIR(program(node));
    expect(sirResult.ok).toBe(true);
    if (!sirResult.ok) return;

    // Verify OIR structure matches the architecture doc §9 example.
    const { bindings, result } = sirResult.program;
    expect(bindings).toHaveLength(3);
    expect(bindings[0].kind).toBe('capability');
    expect(bindings[0].capabilityNumber).toBe(11);
    expect(bindings[1].kind).toBe('domainCheck');
    expect(bindings[1].domainFlag).toBe(0x0d);
    expect(bindings[2].kind).toBe('logical_and');
    expect(bindings[2].operands).toEqual(['$0', '$1']);
    expect(result).toBe('$2');

    // Emit bytes from the SIR-derived OIR.
    const sirBytes = emit(sirResult.program);

    // Manually construct the same OIR and emit — bytes must match.
    const manualOIR = {
      bindings: [
        { name: '$0', kind: 'capability' as const, capabilityNumber: 11 },
        { name: '$1', kind: 'domainCheck' as const, domainFlag: 0x0d },
        { name: '$2', kind: 'logical_and' as const, operands: ['$0', '$1'] },
      ],
      result: '$2',
    };
    const manualBytes = emit(manualOIR);

    expect(Array.from(sirBytes)).toEqual(Array.from(manualBytes));
  });

  // ── SG13: Domain binding emits domainCheck ────────────────────

  test('SG13: Node with domainBinding emits domainCheck for the bound flag', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'declaration' },
      taxonomy: { what: 'trust.discretionary.family', how: 'instrument.trust-deed', why: 'estate-planning', where: 'au.qld' },
      identity: { subject: { type: 'role', name: 'trustee' } },
      governance: defaultGovernance({
        linearity: 'RELEVANT',
        domainBinding: {
          flag: 0x00020001,
          domainType: 'trust',
          realm: 'au.qld',
        },
      }),
      action: 'declare',
      constraint: { kind: 'domain', flag: 0x00020001 },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    // The domain binding's flag should appear as a domainCheck binding.
    const domainChecks = result.program.bindings.filter(b => b.kind === 'domainCheck');
    expect(domainChecks.length).toBeGreaterThanOrEqual(1);
    expect(domainChecks.some(b => b.domainFlag === 0x00020001)).toBe(true);
  });

  // ── SG14: Domain binding with parentFlag emits both checks ────

  test('SG14: domainBinding with parentFlag emits checks for both child and parent flags', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'power' },
      taxonomy: { what: 'trust.sub-trust', how: 'lifecycle.distribute', why: 'beneficiary-distribution' },
      identity: { subject: { type: 'domainFlag', flag: 0x00020002 } },
      governance: defaultGovernance({
        domainBinding: {
          flag: 0x00020002,
          domainType: 'trust',
          parentFlag: 0x00020001,
        },
      }),
      action: 'distribute',
      constraint: { kind: 'capability', required: 9, name: 'TRANSFER' },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    // Must have domain checks for BOTH flags.
    const domainChecks = result.program.bindings.filter(b => b.kind === 'domainCheck');
    expect(domainChecks.length).toBeGreaterThanOrEqual(2);
    const flags = domainChecks.map(b => b.domainFlag);
    expect(flags).toContain(0x00020002); // child
    expect(flags).toContain(0x00020001); // parent

    // All checks should be AND'd together in the result.
    const andBindings = result.program.bindings.filter(b => b.kind === 'logical_and');
    expect(andBindings.length).toBeGreaterThanOrEqual(1);
  });

  // ── SG15: Domain binding without parentFlag emits only child ──

  test('SG15: domainBinding without parentFlag emits only the child flag check', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'permission' },
      taxonomy: { what: 'corporate.operations', how: 'auth.capability', why: 'operational' },
      identity: { subject: { type: 'role', name: 'officer' } },
      governance: defaultGovernance({
        domainBinding: {
          flag: 0x00030001,
          domainType: 'corporate',
        },
      }),
      action: 'operate',
      constraint: { kind: 'capability', required: 3, name: 'OPERATE' },
      provenance: prov,
    };

    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const domainChecks = result.program.bindings.filter(b => b.kind === 'domainCheck');
    // Only the child flag, no parent.
    expect(domainChecks.length).toBe(1);
    expect(domainChecks[0].domainFlag).toBe(0x00030001);
  });

  // ── SG16: End-to-end domain binding bytes ─────────────────────

  test('SG16: Domain-bound power node → lowerSIR → emit → bytes include both flag checks', () => {
    const node: SIRNode = {
      id: '$s0',
      category: { lexicon: 'jural', category: 'power' },
      taxonomy: { what: 'trust.investment', how: 'lifecycle.invest', why: 'fiduciary-duty' },
      identity: { subject: { type: 'domainFlag', flag: 0x00020002 } },
      governance: defaultGovernance({
        domainBinding: {
          flag: 0x00020002,
          domainType: 'trust',
          parentFlag: 0x00020001,
        },
      }),
      action: 'invest',
      constraint: {
        kind: 'composite', op: 'and', children: [
          { kind: 'capability', required: 5, name: 'INVEST' },
          { kind: 'domain', flag: 0x00020002 },
        ],
      },
      provenance: prov,
    };

    const sirResult = lowerSIR(program(node));
    expect(sirResult.ok).toBe(true);
    if (!sirResult.ok) return;

    // Should emit bytes without error.
    const bytes = emit(sirResult.program);
    expect(bytes.length).toBeGreaterThan(0);

    // Verify the parent flag check is present in the bindings.
    const parentCheck = sirResult.program.bindings.find(
      b => b.kind === 'domainCheck' && b.domainFlag === 0x00020001,
    );
    expect(parentCheck).toBeDefined();
  });
});

```
