---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/__tests__/lower-relation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.815054+00:00
---

# core/semantos-sir/src/__tests__/lower-relation.test.ts

```ts
/**
 * SIR `relation` constraint lowering tests — RM-020.
 *
 * Exercises the new `SIRConstraint { kind: 'relation' }` variant added in
 * `core/semantos-sir/src/types.ts` and the lowering case added in
 * `core/semantos-sir/src/lower-sir.ts::lowerConstraint`.
 *
 * Acceptance bar (from `docs/SCG-AND-PHASE-H-ROADMAP.md` RM-020):
 *   - SIRConstraint { kind: 'relation', ... } lowers to a valid IRProgram
 *   - emit() produces non-empty opcode bytes parsing per
 *     core/cell-ops/src/opcodes.ts
 */

import { describe, test, expect } from 'bun:test';
import { lowerSIR } from '../lower-sir';
import { emit } from '@semantos/semantos-ir';
import type { SIRNode, SIRProgram, GovernanceContext } from '../types';

/** `OP_CHECKCAPABILITY` per `core/cell-ops/src/opcodes.ts` (Plexus range 0xC0–0xCF). */
const OP_CHECKCAPABILITY = 0xc3;

function gov(over: Partial<GovernanceContext> = {}): GovernanceContext {
  return {
    trustClass: 'interpretive',
    proofRequirement: 'attestation',
    executionAuthority: 'hat_scoped',
    linearity: 'LINEAR',
    ...over,
  };
}

function relationNode(
  relationKind:
    | 'REPLIES_TO'
    | 'SUPPORTS'
    | 'DISPUTES'
    | 'CITES'
    | 'PAYS',
  sourceId?: string,
  targetId?: string,
): SIRNode {
  return {
    id: '$s0',
    category: { lexicon: 'scg-relation', category: relationKind },
    taxonomy: {
      what: 'scg.relation',
      how: 'discourse.move',
      why: 'conversation-graph',
    },
    identity: { subject: { type: 'role', name: 'author' } },
    governance: gov(),
    action: 'mint-relation',
    constraint: {
      kind: 'relation',
      relationKind,
      ...(sourceId !== undefined ? { sourceId } : {}),
      ...(targetId !== undefined ? { targetId } : {}),
    },
    provenance: {
      source: 'manual',
      expressedAt: '2026-05-13T00:00:00Z',
      trustAtExpression: 'interpretive',
    },
  };
}

function program(node: SIRNode): SIRProgram {
  return {
    nodes: [node],
    primaryNodeId: node.id,
    programGovernance: gov(),
  };
}

describe('SIR relation constraint lowering (RM-020)', () => {
  test('R1 relation lowers to capability + typeHashCheck + logical_and', () => {
    const node = relationNode('REPLIES_TO', 'reply-1', 'post-1');
    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.program.bindings).toHaveLength(3);

    const [b0, b1, b2] = result.program.bindings;
    expect(b0?.kind).toBe('capability');
    // RELATION_MINT slot per RM-004.
    expect((b0 as { capabilityNumber: number }).capabilityNumber).toBe(0x0001000c);

    expect(b1?.kind).toBe('typeHashCheck');
    expect((b1 as { expectedHash: string }).expectedHash).toBe('scg.relation:REPLIES_TO');

    expect(b2?.kind).toBe('logical_and');
    expect((b2 as { operands: string[] }).operands).toEqual([b0!.name, b1!.name]);

    expect(result.program.result).toBe(b2!.name);
  });

  test('R2 lowering produces distinct typeHash per RelationKind', () => {
    const supportsResult = lowerSIR(program(relationNode('SUPPORTS')));
    const disputesResult = lowerSIR(program(relationNode('DISPUTES')));
    expect(supportsResult.ok).toBe(true);
    expect(disputesResult.ok).toBe(true);
    if (!supportsResult.ok || !disputesResult.ok) return;

    const supportsHash = supportsResult.program.bindings.find(
      (b) => b.kind === 'typeHashCheck',
    );
    const disputesHash = disputesResult.program.bindings.find(
      (b) => b.kind === 'typeHashCheck',
    );

    expect((supportsHash as { expectedHash: string }).expectedHash).toBe('scg.relation:SUPPORTS');
    expect((disputesHash as { expectedHash: string }).expectedHash).toBe('scg.relation:DISPUTES');
    expect(supportsHash).not.toEqual(disputesHash);
  });

  test('R3 sourceId / targetId on the constraint are metadata only', () => {
    // Phase-1: sourceId/targetId don't emit predicates (relations are
    // DB rows, not kernel cells). The IR bindings are identical with
    // or without those fields. RM-082 changes this.
    const withIds = lowerSIR(program(relationNode('CITES', 'a', 'b')));
    const withoutIds = lowerSIR(program(relationNode('CITES')));
    expect(withIds.ok).toBe(true);
    expect(withoutIds.ok).toBe(true);
    if (!withIds.ok || !withoutIds.ok) return;

    expect(withIds.program.bindings).toHaveLength(withoutIds.program.bindings.length);
    // Per-binding kinds match.
    expect(withIds.program.bindings.map((b) => b.kind)).toEqual(
      withoutIds.program.bindings.map((b) => b.kind),
    );
  });

  test('R4 lowered IR program emits non-empty opcode bytes', () => {
    const node = relationNode('PAYS', 'invoice-1', 'cust-7');
    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const bytes = emit(result.program);
    expect(bytes).toBeInstanceOf(Uint8Array);
    expect(bytes.byteLength).toBeGreaterThan(0);

    // Sanity: emitted bytes mention a Plexus opcode in the 0xC0–0xCF
    // range. `OP_CHECKCAPABILITY` (0xC3) is part of the lowering
    // surface and should appear in the byte stream. (We don't decode
    // here — that's `core/cell-ops`'s job — just confirm presence.)
    expect(Array.from(bytes)).toContain(OP_CHECKCAPABILITY);
  });

  test('R5 relation constraint composes inside a composite', () => {
    // Verify that the new variant plays nicely with the existing
    // 'composite' arm — a typical reducer-produced pattern.
    const node: SIRNode = {
      ...relationNode('REPLIES_TO'),
      constraint: {
        kind: 'composite',
        op: 'and',
        children: [
          { kind: 'capability', required: 0x05, name: 'ATTESTATION' },
          { kind: 'relation', relationKind: 'REPLIES_TO' },
        ],
      },
    };
    const result = lowerSIR(program(node));
    expect(result.ok).toBe(true);
    if (!result.ok) return;

    // Outer capability + relation-lowering's three bindings + outer
    // logical_and = 5 bindings.
    expect(result.program.bindings.length).toBe(5);
    const kinds = result.program.bindings.map((b) => b.kind);
    expect(kinds).toEqual(['capability', 'capability', 'typeHashCheck', 'logical_and', 'logical_and']);
  });
});

```
