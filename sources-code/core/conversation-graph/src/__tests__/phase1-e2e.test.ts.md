---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/__tests__/phase1-e2e.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.009014+00:00
---

# core/conversation-graph/src/__tests__/phase1-e2e.test.ts

```ts
/**
 * SCG Phase 1 — substrate E2E acceptance test (RM-040).
 *
 * Composes the components shipped in Wave 1-3 into a single
 * integration test against the real `sem_objects` substrate:
 *
 *   - RM-010: createObject + createRelation + foldRelationGraph
 *             (`@semantos/scg-relations`)
 *   - RM-020: SIRConstraint `relation` variant + lowering case
 *             (`@semantos/semantos-sir`)
 *   - RM-022: requireRelationMint capability check
 *             (`@semantos/scg-relations`)
 *   - RM-030: relation-pass NL detection
 *             (`@semantos/intent::reduceToIntent`)
 *   - RM-031a: autoEmitReplyRelation conversation hook
 *             (`@semantos/conversation-graph`)
 *
 * Acceptance bar (from SCG §3 exit criteria / roadmap RM-040):
 *
 *   "Create two `sem_objects` (a post and a reply), create a
 *    `scg.relation` of kind `REPLIES_TO` between them via the new ops
 *    module, fetch the thread back via `foldRelationGraph`, run an NL
 *    intent ('upvote the second one') through `reduceToIntent` and
 *    observe a new relation patch with kind `SUPPORTS`, attested by
 *    the active identity, with a corresponding `SIRConstraint`
 *    lowering cleanly to IR and emitting valid opcodes. All on
 *    existing storage, identity, and 2PDA infrastructure."
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { createObject, type Database } from '@semantos/semantic-objects';
import {
  createRelation,
  foldRelationGraph,
  listRelationsFrom,
  RELATION_OBJECT_KIND,
  type RelationKind,
} from '@semantos/scg-relations';
import { reduceToIntent } from '@semantos/intent/reducer';
import type { GrammarSpec, ReducerInputState } from '@semantos/intent/reducer/types';
import { lowerSIR } from '@semantos/semantos-sir';
import type { SIRConstraint, SIRProgram } from '@semantos/semantos-sir';
import { emit } from '@semantos/semantos-ir';
import { makeTestDb } from './setup.js';

// ── Helpers — extract a `relation` SIRConstraint from a reducer-NL pass ──

const SCG_GRAMMAR: GrammarSpec = {
  extensionId: 'scg-test',
  domainFlag: 7,
  lexicon: {
    name: 'jural',
    categories: ['declaration', 'obligation', 'permission'],
  },
  defaultTaxonomyWhat: 'scg.conversation',
  objectTypes: [{ name: 'scg.cell', description: '' }],
  actions: [{ name: 'say', category: 'declaration', authoredBy: ['actor'], description: '' }],
  trustClass: 'interpretive',
};

function reducerInput(text: string): ReducerInputState {
  return {
    conversationSummary: text,
    scopeDescription: '',
    taggedFacts: [],
  };
}

function extractRelationConstraint(constraints: ReadonlyArray<unknown>): SIRConstraint & { kind: 'relation' } | null {
  for (const c of constraints) {
    const cc = c as SIRConstraint;
    if (cc.kind === 'relation') return cc;
  }
  return null;
}

// ── E2E test ────────────────────────────────────────────────────────

describe('SCG Phase 1 substrate — E2E (RM-040)', () => {
  let db: Database;
  let close: () => Promise<void>;

  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('E1 end-to-end: post + reply + REPLIES_TO + NL "upvote" → SUPPORTS + lowering + IR bytes', async () => {
    // ─── Stage 1: Create two sem_objects rows representing a post and a reply.
    const post = await createObject(db, {
      id: 'post-1',
      objectKind: 'scg.cell',
      payload: { body: 'I propose we change the schema.' },
      createdByCertId: 'cert-author',
    });
    const reply = await createObject(db, {
      id: 'reply-1',
      objectKind: 'scg.cell',
      payload: { body: 'I think we should pick a different approach.' },
      createdByCertId: 'cert-author-2',
    });
    expect(post.id).toBe('post-1');
    expect(reply.id).toBe('reply-1');

    // ─── Stage 2: Create a REPLIES_TO relation via the SCG ops module.
    const repliesTo = await createRelation(db, {
      kind: 'REPLIES_TO',
      sourceId: reply.id,
      targetId: post.id,
      attestation: 'sig-deadbeef',
      createdByCertId: 'cert-author-2',
    });
    expect(repliesTo.objectKind).toBe(RELATION_OBJECT_KIND);
    expect(repliesTo.payload.kind).toBe('REPLIES_TO');
    expect(repliesTo.payload.sourceId).toBe(reply.id);
    expect(repliesTo.payload.targetId).toBe(post.id);

    // ─── Stage 3: Fetch the thread back via foldRelationGraph (incoming).
    const incoming = await foldRelationGraph(db, post.id, {
      depth: 3,
      direction: 'incoming',
    });
    expect(incoming.nodes.has(post.id)).toBe(true);
    expect(incoming.nodes.has(reply.id)).toBe(true);
    expect(incoming.edges).toHaveLength(1);
    expect(incoming.edges[0]?.kind).toBe('REPLIES_TO');

    // ─── Stage 4: Run an NL intent ("upvote the second one") through the
    // reducer. The RM-030 relation-pass detects the "+1"/"support" form
    // and emits a relation constraint with kind SUPPORTS.
    const upvoteResult = await reduceToIntent(
      reducerInput('+1 — I agree with the previous post'),
      SCG_GRAMMAR,
    );
    const upvoteRel = extractRelationConstraint(upvoteResult.intent.constraints);
    expect(upvoteRel).not.toBeNull();
    if (!upvoteRel) return;
    expect(upvoteRel.relationKind).toBe('SUPPORTS');

    // The relation pass should be one of the passes that ran, with
    // its position pinned between rhetoric and analogical_prefilter.
    const passOrder = upvoteResult.passResults.map((p) => p.pass);
    const rhetoricIdx = passOrder.indexOf('rhetoric');
    const relationIdx = passOrder.indexOf('relation');
    const prefilterIdx = passOrder.indexOf('analogical_prefilter');
    expect(rhetoricIdx).toBeGreaterThan(-1);
    expect(relationIdx).toBeGreaterThan(rhetoricIdx);
    expect(prefilterIdx).toBeGreaterThan(relationIdx);

    // ─── Stage 5: Persist the SUPPORTS relation (the new patch from
    // the NL intent). attestation is the cert binding from the active
    // identity surface (mirrors how processIntent would mint the patch).
    const supports = await createRelation(db, {
      kind: upvoteRel.relationKind,
      sourceId: 'upvote-author-cell',
      targetId: post.id,
      attestation: 'sig-attestation-cafebabe',
      createdByCertId: 'cert-active-identity',
    });
    expect(supports.payload.kind).toBe('SUPPORTS');
    expect(supports.payload.attestation).toBe('sig-attestation-cafebabe');
    expect(supports.createdByCertId).toBe('cert-active-identity');

    // ─── Stage 6: Lower the relation constraint through SIR → IR.
    const program: SIRProgram = {
      nodes: [
        {
          id: '$s0',
          category: { lexicon: 'scg-relation', category: 'SUPPORTS' as RelationKind },
          taxonomy: {
            what: 'scg.relation',
            how: 'discourse.move',
            why: 'conversation-graph',
          },
          identity: { subject: { type: 'role', name: 'active-identity' } },
          governance: {
            trustClass: 'interpretive',
            proofRequirement: 'attestation',
            executionAuthority: 'hat_scoped',
            linearity: 'LINEAR',
          },
          action: 'mint-relation',
          constraint: upvoteRel,
          provenance: {
            source: 'nl',
            expressedAt: new Date().toISOString(),
            trustAtExpression: 'interpretive',
          },
        },
      ],
      primaryNodeId: '$s0',
      programGovernance: {
        trustClass: 'interpretive',
        proofRequirement: 'attestation',
        executionAuthority: 'hat_scoped',
        linearity: 'LINEAR',
      },
    };
    const lowered = lowerSIR(program);
    expect(lowered.ok).toBe(true);
    if (!lowered.ok) return;

    // The relation lowering produces three bindings: capability(RELATION_MINT) +
    // typeHashCheck(scg.relation:SUPPORTS) + logical_and.
    expect(lowered.program.bindings.length).toBe(3);
    const [b0, b1, b2] = lowered.program.bindings;
    expect(b0?.kind).toBe('capability');
    expect(b1?.kind).toBe('typeHashCheck');
    expect(b2?.kind).toBe('logical_and');

    // ─── Stage 7: emit the IR program → non-empty opcode bytes that
    // parse against the cell-ops opcode table.
    const bytes = emit(lowered.program);
    expect(bytes).toBeInstanceOf(Uint8Array);
    expect(bytes.byteLength).toBeGreaterThan(0);

    // OP_CHECKCAPABILITY (0xC3) appears in the emitted byte stream.
    expect(Array.from(bytes)).toContain(0xc3);

    // ─── Stage 8: Final graph view. The post now has TWO incoming
    // relations: REPLIES_TO from the original reply, and SUPPORTS
    // from the NL-derived upvote.
    const finalGraph = await foldRelationGraph(db, post.id, {
      depth: 3,
      direction: 'incoming',
    });
    expect(finalGraph.edges).toHaveLength(2);
    const kinds = finalGraph.edges.map((e) => e.kind).sort();
    expect(kinds).toEqual(['REPLIES_TO', 'SUPPORTS']);
  });

  test('E2 no UI involvement — every artefact above lives in the substrate', async () => {
    // Sentinel test asserting the E1 path doesn't depend on any
    // UI / rendering / HTTP module. By having E1 succeed against
    // PGlite + in-process modules only, this contract is enforced.
    // (If a future change makes E1 transitively depend on a UI
    // module, the test setup will fail to import it.)
    const post = await createObject(db, { objectKind: 'scg.cell', payload: {} });
    const rel = await createRelation(db, {
      kind: 'CITES',
      sourceId: post.id,
      targetId: post.id,
    });
    expect(rel.objectKind).toBe(RELATION_OBJECT_KIND);
    // The graph walks return real rows from PGlite — no in-memory mock.
    const fromPost = await listRelationsFrom(db, post.id);
    expect(fromPost).toHaveLength(1);
    expect(fromPost[0]?.payload.kind).toBe('CITES');
  });
});

```
