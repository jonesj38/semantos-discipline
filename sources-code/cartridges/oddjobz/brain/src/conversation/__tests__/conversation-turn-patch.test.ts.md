---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/conversation-turn-patch.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.537765+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/conversation-turn-patch.test.ts

```ts
/**
 * Conversation-turn patch conformance.
 *
 * Original asserts (preserved verbatim, D-ODDJOBZ-quote-affordance /
 * existing audit-log surface): the emitted ConversationPatch carries
 * the structured IntakeTurnBody (input/output) AND the versioned
 * prompt + decision-tree descriptor; the jsonl sink writes one
 * parseable line per turn; ids/clock are injectable (deterministic
 * replay); distinct prompts → distinct prompt hashes in the log.
 *
 * D-ODDJOBZ-turns-as-sem-objects (this PR): dual-sink persistence.
 * The same `recordIntakeTurn` call ALSO emits the canonical
 * sem_objects payload pair (inbound + outbound) when a sem-object
 * sink is wired. Below we add coverage for:
 *  - dual-sink: jsonl AND sem-object sinks both fire for one call
 *  - canonical-payload mapping (§4 of architecture doc) round-trip
 *  - participantRole distinction (inbound external, outbound ai)
 *  - operator vs ai reply roles
 *  - default surface = widget (today's intake-handler entry)
 *  - sem-object sink failure does NOT regress the jsonl path
 */

import { describe, expect, test } from 'bun:test';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInMemoryLogger } from '@semantos/intent';
import {
  recordIntakeTurn,
  makeJsonlConversationSink,
  buildTurnRelations,
  buildReplyRelations,
  bindParticipantIdentity,
  identityTier,
  AI_CERT_PENDING_SENTINEL,
  type BelongsToEntityRelation,
  type RepliesToRelation,
  type IntakeTurnBody,
  type OddjobzConversationTurnPayload,
} from '../conversation-turn-patch.js';

function deps(
  write: (o: string, p: unknown) => void,
  opts?: {
    semObjectSink?: (turn: OddjobzConversationTurnPayload) => void;
    relationSink?: (rel: BelongsToEntityRelation) => void;
    replyRelationSink?: (rel: RepliesToRelation) => void | Promise<void>;
  },
) {
  let n = 0;
  return {
    write: write as never,
    logger: createInMemoryLogger(),
    generatePatchId: () => `patch-${++n}`,
    generateCorrelationId: () => `corr-${n}`,
    now: () => 1_700_000_000_000,
    ...(opts?.semObjectSink ? { semObjectSink: opts.semObjectSink } : {}),
    ...(opts?.relationSink ? { relationSink: opts.relationSink } : {}),
    ...(opts?.replyRelationSink
      ? { replyRelationSink: opts.replyRelationSink }
      : {}),
  };
}

const baseArgs = {
  objectId: 'conv-1',
  hatId: 'hat-op',
  message: 'I need a 20m colorbond fence',
  stateSummary: { jobType: 'fencing', scopeClarity: 40 },
  reply: 'Got it — is the ground level back there?',
  action: { type: 'present_estimate' },
  model: 'claude-haiku-4-5',
  assembledPrompt: 'BASE_SYSTEM v1\n\n[ROM from estimator: $1200–$1800]',
};

describe('recordIntakeTurn — existing jsonl audit-log surface', () => {
  test('emits a ConversationPatch whose body is the versioned IntakeTurnBody', async () => {
    const seen: { objectId: string; patch: any }[] = [];
    const r = await recordIntakeTurn(
      baseArgs,
      deps((objectId, patch) => seen.push({ objectId, patch: patch as any })),
    );
    expect(r.patchId).toBe('patch-1');
    expect(seen).toHaveLength(1);
    expect(seen[0].objectId).toBe('conv-1');
    const patch = seen[0].patch;
    expect(patch.kind).toBe('conversation');
    expect(patch.timestamp).toBe(1_700_000_000_000);
    const body = patch.delta.body as IntakeTurnBody;
    expect(body.kind).toBe('intake_turn');
    expect(body.message).toBe('I need a 20m colorbond fence');
    expect(body.reply).toBe('Got it — is the ground level back there?');
    expect(body.action.type).toBe('present_estimate');
    expect(body.model).toBe('claude-haiku-4-5');
    expect(body.stateSummary).toEqual({ jobType: 'fencing', scopeClarity: 40 });
    // The load-bearing bit: versioned prompt + decision-tree provenance.
    expect(body.prompt.prompt.id).toBe('oddjobz.intake.prompt');
    expect(body.prompt.prompt.version).toBe('1.0.0');
    expect(body.prompt.prompt.hash).toMatch(/^[0-9a-f]{64}$/);
    expect(body.prompt.decisionTree.id).toBe('oddjobz.intake.decision-tree');
    expect(body.prompt.decisionTree.version).toBe('2026-04');
    expect(body.prompt.decisionTree.hash).toMatch(/^[0-9a-f]{64}$/);
  });

  test('distinct assembled prompts → distinct logged prompt hashes', async () => {
    const hashes: string[] = [];
    const d = deps((_, p: any) =>
      hashes.push((p.delta.body as IntakeTurnBody).prompt.prompt.hash),
    );
    await recordIntakeTurn(baseArgs, d);
    await recordIntakeTurn({ ...baseArgs, assembledPrompt: 'BASE_SYSTEM v1\n\n[ROM from estimator: $1200–$2000]' }, d);
    expect(hashes[0]).not.toBe(hashes[1]);
  });

  test('jsonl sink writes one parseable line per turn', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'conv-jsonl-'));
    const file = join(dir, 'nested', 'conversation.jsonl');
    const sink = makeJsonlConversationSink(file);
    await recordIntakeTurn(baseArgs, deps(sink));
    await recordIntakeTurn({ ...baseArgs, message: 'second turn' }, deps(sink));
    const lines = readFileSync(file, 'utf8').trim().split('\n');
    expect(lines).toHaveLength(2);
    const rec0 = JSON.parse(lines[0]);
    expect(rec0.objectId).toBe('conv-1');
    expect(rec0.kind).toBe('conversation');
    expect((rec0.delta.body as IntakeTurnBody).prompt.prompt.version).toBe('1.0.0');
    expect((JSON.parse(lines[1]).delta.body as IntakeTurnBody).message).toBe('second turn');
  });
});

// ── D-ODDJOBZ-turns-as-sem-objects — dual-sink coverage ─────

describe('recordIntakeTurn — sem_objects dual-sink', () => {
  test('both sinks fire on one call (jsonl + sem_objects)', async () => {
    const jsonlSeen: unknown[] = [];
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      baseArgs,
      deps((_o, p) => jsonlSeen.push(p), {
        semObjectSink: (turn) => {
          semSeen.push(turn);
        },
      }),
    );
    // jsonl gets ONE patch per interaction (legacy shape).
    expect(jsonlSeen).toHaveLength(1);
    // sem_objects gets TWO canonical turns (inbound + outbound).
    expect(semSeen).toHaveLength(2);
    expect(semSeen[0]!.direction).toBe('inbound');
    expect(semSeen[1]!.direction).toBe('outbound');
  });

  test('canonical inbound turn carries the customer message + external role', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      baseArgs,
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    expect(inbound.direction).toBe('inbound');
    expect(inbound.bodyText).toBe('I need a 20m colorbond fence');
    expect(inbound.participantRole).toBe('external');
    expect(inbound.surface).toBe('widget'); // default for intake-handler
    expect(inbound.conversationId).toBe('conv-1');
    expect(inbound.correlationId).toBe('corr-1');
    expect(inbound.timestamp).toBe(1_700_000_000_000);
    // entityRef intentionally absent — D-OJ-conv-entity-anchoring binds it.
    expect(inbound.entityRef).toBeUndefined();
  });

  test('canonical outbound turn carries the reply + ai role + quotedTurnId', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      baseArgs,
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const outbound = semSeen[1]!;
    expect(outbound.direction).toBe('outbound');
    expect(outbound.bodyText).toBe('Got it — is the ground level back there?');
    expect(outbound.participantRole).toBe('ai'); // today's intake LLM
    expect(outbound.surface).toBe('widget');
    expect(outbound.quotedTurnId).toBe(semSeen[0]!.turnId);
    // bodyParts carries the legacy IntakeTurnBody (option (a) per §4.2).
    expect(outbound.bodyParts).toBeDefined();
    expect(outbound.bodyParts).toHaveLength(1);
    const meta = outbound.bodyParts![0];
    expect(meta!.kind).toBe('oddjobz-intake-meta');
    const intake = meta!.payload as IntakeTurnBody;
    expect(intake.kind).toBe('intake_turn');
    expect(intake.message).toBe('I need a 20m colorbond fence');
    expect(intake.reply).toBe('Got it — is the ground level back there?');
    expect(intake.action.type).toBe('present_estimate');
    expect(intake.model).toBe('claude-haiku-4-5');
    expect(intake.stateSummary).toEqual({
      jobType: 'fencing',
      scopeClarity: 40,
    });
    expect(intake.prompt.prompt.version).toBe('1.0.0');
  });

  test('round-trip: canonical → JSON.parse → canonical preserves all fields', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      baseArgs,
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    for (const t of semSeen) {
      const recovered = JSON.parse(
        JSON.stringify(t),
      ) as OddjobzConversationTurnPayload;
      expect(recovered.turnId).toBe(t.turnId);
      expect(recovered.conversationId).toBe(t.conversationId);
      expect(recovered.participantRole).toBe(t.participantRole);
      expect(recovered.surface).toBe(t.surface);
      expect(recovered.direction).toBe(t.direction);
      expect(recovered.bodyText).toBe(t.bodyText);
      expect(recovered.correlationId).toBe(t.correlationId);
      expect(recovered.timestamp).toBe(t.timestamp);
      if (t.bodyParts) {
        expect(recovered.bodyParts).toEqual(t.bodyParts as never);
      }
    }
  });

  test('operator reply role overrides ai default + binds operatorCertId', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      {
        ...baseArgs,
        outboundParticipantRole: 'operator',
        operatorCertId: 'cert_op_abc',
      },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const outbound = semSeen[1]!;
    expect(outbound.participantRole).toBe('operator');
    expect(outbound.actorCertId).toBe('cert_op_abc');
  });

  test('ai reply role binds agentCertId when provisioned', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      { ...baseArgs, agentCertId: 'cert_ai_xyz' },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const outbound = semSeen[1]!;
    expect(outbound.participantRole).toBe('ai');
    expect(outbound.actorCertId).toBe('cert_ai_xyz');
  });

  test('inbound role can be promoted from external when identity known', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      { ...baseArgs, inboundParticipantRole: 'tenant' },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    expect(semSeen[0]!.participantRole).toBe('tenant');
  });

  test('surface override carries through both turns', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      { ...baseArgs, surface: 'sms' },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    expect(semSeen[0]!.surface).toBe('sms');
    expect(semSeen[1]!.surface).toBe('sms');
  });

  test('sem-object sink failure does NOT regress the jsonl path', async () => {
    const jsonlSeen: unknown[] = [];
    const r = await recordIntakeTurn(
      baseArgs,
      deps((_o, p) => jsonlSeen.push(p), {
        semObjectSink: () => {
          throw new Error('boom');
        },
      }),
    );
    // jsonl still landed; caller's reply path is unaffected.
    expect(jsonlSeen).toHaveLength(1);
    expect(r.patchId).toBe('patch-1');
  });

  test('no sink wired → behaves exactly like the pre-PR path', async () => {
    const jsonlSeen: unknown[] = [];
    await recordIntakeTurn(
      baseArgs,
      deps((_o, p) => jsonlSeen.push(p)),
    );
    expect(jsonlSeen).toHaveLength(1);
    // Backward-compat: the jsonl shape is unchanged.
    const patch = jsonlSeen[0] as { delta: { body: IntakeTurnBody } };
    expect(patch.delta.body.kind).toBe('intake_turn');
  });
});

// ── D-OJ-conv-entity-anchoring — BELONGS_TO_ENTITY ──────────

describe('buildTurnRelations — one-per-turn enforcement', () => {
  const baseTurn: OddjobzConversationTurnPayload = {
    turnId: 'turn-1',
    conversationId: 'conv-1',
    participantRole: 'external',
    surface: 'widget',
    direction: 'inbound',
    bodyText: 'hello',
    correlationId: 'corr-1',
    timestamp: 1_700_000_000_000,
  };

  test('a turn with an entityRef yields exactly one BELONGS_TO_ENTITY', () => {
    const rels = buildTurnRelations({
      ...baseTurn,
      entityRef: { kind: 'job', cellHash: 'job-cell-abc' },
    });
    // One-per-turn is structural: the builder is the relation-pass-
    // equivalent rejection point; it can never produce two anchors.
    expect(rels).toHaveLength(1);
    expect(rels[0]!.kind).toBe('BELONGS_TO_ENTITY');
    expect(rels[0]!.turnId).toBe('turn-1'); // source = turn id
    expect(rels[0]!.entityCellHash).toBe('job-cell-abc'); // target = entity
    expect(rels[0]!.entityKind).toBe('job');
  });

  test('a turn with no entityRef yields zero relations', () => {
    expect(buildTurnRelations(baseTurn)).toHaveLength(0);
  });

  test('site / customer entity kinds carry through to the relation', () => {
    expect(
      buildTurnRelations({
        ...baseTurn,
        entityRef: { kind: 'site', cellHash: 'site-cell-1' },
      })[0]!.entityKind,
    ).toBe('site');
    expect(
      buildTurnRelations({
        ...baseTurn,
        entityRef: { kind: 'customer', cellHash: 'cust-cell-1' },
      })[0]!.entityKind,
    ).toBe('customer');
  });
});

describe('recordIntakeTurn — entity anchoring', () => {
  const jobArgs = {
    ...baseArgs,
    entityRef: { kind: 'job' as const, cellHash: 'job-cell-xyz' },
  };

  test('entityRef set on BOTH canonical turns when known', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      jobArgs,
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    expect(semSeen[0]!.entityRef).toEqual({
      kind: 'job',
      cellHash: 'job-cell-xyz',
    });
    expect(semSeen[1]!.entityRef).toEqual({
      kind: 'job',
      cellHash: 'job-cell-xyz',
    });
  });

  test('BELONGS_TO_ENTITY emitted per persisted turn with correct source/target', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    const relSeen: BelongsToEntityRelation[] = [];
    await recordIntakeTurn(
      jobArgs,
      deps(() => {}, {
        semObjectSink: (t) => semSeen.push(t),
        relationSink: (r) => relSeen.push(r),
      }),
    );
    // One relation per turn (inbound + outbound) = two total, each
    // one-per-turn.
    expect(relSeen).toHaveLength(2);
    // Source = the turn's id; target = the entity cell hash.
    expect(relSeen[0]!.kind).toBe('BELONGS_TO_ENTITY');
    expect(relSeen[0]!.turnId).toBe(semSeen[0]!.turnId);
    expect(relSeen[0]!.entityCellHash).toBe('job-cell-xyz');
    expect(relSeen[1]!.turnId).toBe(semSeen[1]!.turnId);
    expect(relSeen[1]!.entityCellHash).toBe('job-cell-xyz');
  });

  test('site entity anchors to the right kind', async () => {
    const relSeen: BelongsToEntityRelation[] = [];
    await recordIntakeTurn(
      { ...baseArgs, entityRef: { kind: 'site', cellHash: 'site-1' } },
      deps(() => {}, {
        semObjectSink: () => {},
        relationSink: (r) => relSeen.push(r),
      }),
    );
    expect(relSeen.every((r) => r.entityKind === 'site')).toBe(true);
    expect(relSeen.every((r) => r.entityCellHash === 'site-1')).toBe(true);
  });

  test('customer entity anchors to the right kind', async () => {
    const relSeen: BelongsToEntityRelation[] = [];
    await recordIntakeTurn(
      { ...baseArgs, entityRef: { kind: 'customer', cellHash: 'cust-1' } },
      deps(() => {}, {
        semObjectSink: () => {},
        relationSink: (r) => relSeen.push(r),
      }),
    );
    expect(relSeen.every((r) => r.entityKind === 'customer')).toBe(true);
  });

  test('no entityRef → no relation emitted (anchoring dormant)', async () => {
    const relSeen: BelongsToEntityRelation[] = [];
    await recordIntakeTurn(
      baseArgs, // no entityRef
      deps(() => {}, {
        semObjectSink: () => {},
        relationSink: (r) => relSeen.push(r),
      }),
    );
    expect(relSeen).toHaveLength(0);
  });

  test('relationSink absent → turns still persist (dormant path)', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      jobArgs,
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    // entityRef still denormalised on the rows even with no relation sink.
    expect(semSeen).toHaveLength(2);
    expect(semSeen[0]!.entityRef?.cellHash).toBe('job-cell-xyz');
  });

  test('relation-emit failure does NOT regress turn persistence or jsonl', async () => {
    const jsonlSeen: unknown[] = [];
    const semSeen: OddjobzConversationTurnPayload[] = [];
    const r = await recordIntakeTurn(
      jobArgs,
      deps((_o, p) => jsonlSeen.push(p), {
        semObjectSink: (t) => semSeen.push(t),
        relationSink: () => {
          throw new Error('relation boom');
        },
      }),
    );
    // jsonl + sem_objects both landed; the reply path is unaffected.
    expect(jsonlSeen).toHaveLength(1);
    expect(semSeen).toHaveLength(2);
    expect(r.patchId).toBe('patch-1');
  });
});

// ── D-SCG-oddjobz-consumer-cutover — REPLIES_TO ───────────────

describe('buildReplyRelations — one-per-turn REPLIES_TO', () => {
  const baseTurn: OddjobzConversationTurnPayload = {
    turnId: 'turn-1',
    conversationId: 'conv-1',
    participantRole: 'external',
    surface: 'widget',
    direction: 'inbound',
    bodyText: 'hello',
    correlationId: 'corr-1',
    timestamp: 1_700_000_000_000,
  };

  test('a turn that quotes a prior turn yields exactly one REPLIES_TO', () => {
    const rels = buildReplyRelations({
      ...baseTurn,
      quotedTurnId: 'turn-prior',
    });
    expect(rels).toHaveLength(1);
    expect(rels[0]!.kind).toBe('REPLIES_TO');
    expect(rels[0]!.turnId).toBe('turn-1'); // source = the quoting turn
    expect(rels[0]!.quotedTurnId).toBe('turn-prior'); // target = the quoted turn
  });

  test('a turn with no quotedTurnId yields zero relations (vacuous)', () => {
    expect(buildReplyRelations(baseTurn)).toHaveLength(0);
  });

  test('actorCertId carries through as the relation author', () => {
    const rels = buildReplyRelations({
      ...baseTurn,
      quotedTurnId: 'turn-prior',
      actorCertId: 'cert_ai_xyz',
    });
    expect(rels[0]!.authorCertId).toBe('cert_ai_xyz');
  });

  test('an un-cert’d quoting turn carries no authorCertId', () => {
    const rels = buildReplyRelations({
      ...baseTurn,
      quotedTurnId: 'turn-prior',
    });
    expect(rels[0]!.authorCertId).toBeUndefined();
  });
});

describe('recordIntakeTurn — REPLIES_TO auto-emit on quotedTurnId', () => {
  test('outbound turn (quotes its inbound) emits REPLIES_TO with correct source/target', async () => {
    // The foundation sets the OUTBOUND turn's quotedTurnId to THIS
    // interaction's inbound turn id, so a REPLIES_TO is always emitted
    // for the reply even with no surface-supplied inReplyToTurnId.
    const semSeen: OddjobzConversationTurnPayload[] = [];
    const replySeen: RepliesToRelation[] = [];
    await recordIntakeTurn(
      baseArgs,
      deps(() => {}, {
        semObjectSink: (t) => semSeen.push(t),
        replyRelationSink: (r) => replySeen.push(r),
      }),
    );
    const inbound = semSeen[0]!;
    const outbound = semSeen[1]!;
    // Only the outbound turn quotes (inbound has no inReplyToTurnId here).
    expect(replySeen).toHaveLength(1);
    expect(replySeen[0]!.kind).toBe('REPLIES_TO');
    expect(replySeen[0]!.turnId).toBe(outbound.turnId); // source = the reply
    expect(replySeen[0]!.quotedTurnId).toBe(inbound.turnId); // target = the message
  });

  test('inbound surface-supplied inReplyToTurnId ALSO emits REPLIES_TO (cross-interaction)', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    const replySeen: RepliesToRelation[] = [];
    await recordIntakeTurn(
      { ...baseArgs, inReplyToTurnId: 'turn-earlier-in-thread' },
      deps(() => {}, {
        semObjectSink: (t) => semSeen.push(t),
        replyRelationSink: (r) => replySeen.push(r),
      }),
    );
    // Both turns now quote: inbound → the earlier thread turn,
    // outbound → its own inbound turn.
    expect(replySeen).toHaveLength(2);
    const inbound = semSeen[0]!;
    const inboundReply = replySeen.find((r) => r.turnId === inbound.turnId)!;
    expect(inboundReply.quotedTurnId).toBe('turn-earlier-in-thread');
  });

  test('AI reply turn threads its actorCertId onto the REPLIES_TO author', async () => {
    const replySeen: RepliesToRelation[] = [];
    await recordIntakeTurn(
      { ...baseArgs, agentCertId: 'cert_ai_xyz' },
      deps(() => {}, {
        semObjectSink: () => {},
        replyRelationSink: (r) => replySeen.push(r),
      }),
    );
    expect(replySeen).toHaveLength(1);
    expect(replySeen[0]!.authorCertId).toBe('cert_ai_xyz');
  });

  test('replyRelationSink absent → turns still persist (dormant path)', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      baseArgs,
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    expect(semSeen).toHaveLength(2);
    // quotedTurnId still set on the outbound row even with no reply sink.
    expect(semSeen[1]!.quotedTurnId).toBe(semSeen[0]!.turnId);
  });

  test('reply-relation-emit failure does NOT regress turn persistence or jsonl', async () => {
    const jsonlSeen: unknown[] = [];
    const semSeen: OddjobzConversationTurnPayload[] = [];
    const r = await recordIntakeTurn(
      baseArgs,
      deps((_o, p) => jsonlSeen.push(p), {
        semObjectSink: (t) => semSeen.push(t),
        replyRelationSink: () => {
          throw new Error('replies-to boom');
        },
      }),
    );
    // jsonl + sem_objects both landed; the reply path is unaffected.
    expect(jsonlSeen).toHaveLength(1);
    expect(semSeen).toHaveLength(2);
    expect(r.patchId).toBe('patch-1');
  });
});

// ── D-ODDJOBZ-quote-affordance — explicit reply-reference ─────

describe('recordIntakeTurn — explicit quote affordance', () => {
  test('inReplyToTurnId set → inbound turn carries quotedTurnId', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      { ...baseArgs, inReplyToTurnId: 'turn-prior-xyz' },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    expect(inbound.direction).toBe('inbound');
    // The customer's new message explicitly quotes a prior turn.
    expect(inbound.quotedTurnId).toBe('turn-prior-xyz');
  });

  test('inReplyToTurnId absent → inbound quotedTurnId undefined (no fabrication)', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      baseArgs, // no inReplyToTurnId
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    expect(inbound.direction).toBe('inbound');
    // No explicit reply marker → no quote on the inbound side.
    expect(inbound.quotedTurnId).toBeUndefined();
  });

  test('explicit inbound quote does NOT clobber the outbound foundation quote', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      { ...baseArgs, inReplyToTurnId: 'turn-prior-xyz' },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    const outbound = semSeen[1]!;
    // Inbound quotes the explicit prior turn (cross-interaction).
    expect(inbound.quotedTurnId).toBe('turn-prior-xyz');
    // Outbound STILL quotes this interaction's inbound turn (foundation
    // intra-interaction reply) — the two are independent.
    expect(outbound.quotedTurnId).toBe(inbound.turnId);
    expect(outbound.quotedTurnId).not.toBe('turn-prior-xyz');
  });

  test('self-referential inReplyToTurnId is dropped (a turn cannot quote itself)', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    // ids are deterministic in tests: writeConversationPatch consumes
    // patch-1, so the inbound turn id is `turn-in-patch-2`. Reference
    // it and expect the self-quote to be dropped.
    await recordIntakeTurn(
      { ...baseArgs, inReplyToTurnId: 'turn-in-patch-2' },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    expect(inbound.turnId).toBe('turn-in-patch-2');
    expect(inbound.quotedTurnId).toBeUndefined(); // self-reference dropped
  });

  test('reply reference round-trips through BOTH sinks (jsonl + sem_objects)', async () => {
    const jsonlSeen: { objectId: string; patch: any }[] = [];
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      { ...baseArgs, inReplyToTurnId: 'turn-prior-xyz' },
      deps((objectId, patch) => jsonlSeen.push({ objectId, patch: patch as any }), {
        semObjectSink: (t) => semSeen.push(t),
      }),
    );
    // sem_objects sink: quotedTurnId survives JSON round-trip.
    const recovered = JSON.parse(
      JSON.stringify(semSeen[0]!),
    ) as OddjobzConversationTurnPayload;
    expect(recovered.quotedTurnId).toBe('turn-prior-xyz');
    // jsonl sink: the audit ConversationPatch still lands (one line per
    // interaction) and remains parseable. The reply-reference lives on
    // the canonical sem_objects shape (where REPLIES_TO consumes it);
    // the jsonl audit shape is unchanged (legacy IntakeTurnBody body).
    expect(jsonlSeen).toHaveLength(1);
    const body = jsonlSeen[0]!.patch.delta.body as IntakeTurnBody;
    expect(body.kind).toBe('intake_turn');
    const reJsonl = JSON.parse(JSON.stringify(jsonlSeen[0]!.patch));
    expect(reJsonl.delta.body.kind).toBe('intake_turn');
  });

  test('explicit quote on a non-widget surface (e.g. email In-Reply-To)', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      {
        ...baseArgs,
        surface: 'email',
        inboundEmail: 'sender@example.com',
        inReplyToTurnId: 'turn-email-thread-root',
      },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    expect(inbound.surface).toBe('email');
    expect(inbound.quotedTurnId).toBe('turn-email-thread-root');
  });
});

// ── D-OJ-conv-multiparty-identity — per-role binding + tiers ──

describe('bindParticipantIdentity — per-role binding (§5)', () => {
  test('operator → operator-root cert (L2), no handle', () => {
    const b = bindParticipantIdentity('operator', {
      operatorCertId: 'cert_op_root',
    });
    expect(b.role).toBe('operator');
    expect(b.actorCertId).toBe('cert_op_root');
    expect(b.identityHandle).toBeUndefined();
    expect(identityTier(b)).toBe('L2');
  });

  test('operator with no cert source → neither bound (surfaced, not invented)', () => {
    const b = bindParticipantIdentity('operator', {});
    expect(b.role).toBe('operator');
    expect(b.actorCertId).toBeUndefined();
    expect(b.identityHandle).toBeUndefined();
  });

  test('ai → agent cert when provisioned (L2)', () => {
    const b = bindParticipantIdentity('ai', { agentCertId: 'cert_ai_xyz' });
    expect(b.role).toBe('ai');
    expect(b.actorCertId).toBe('cert_ai_xyz');
    expect(identityTier(b)).toBe('L2');
  });

  test('ai with no cert yet → documented pending sentinel, still L2', () => {
    const b = bindParticipantIdentity('ai', {});
    expect(b.role).toBe('ai');
    expect(b.actorCertId).toBe(AI_CERT_PENDING_SENTINEL);
    // The sentinel makes the "real binding pending" state explicit
    // (D-OJ-conv-ai-participant binds the real cert later).
    expect(b.actorCertId).toContain('D-OJ-conv-ai-participant');
    expect(identityTier(b)).toBe('L2');
  });

  test("cert'd subcontractor → their own cert (L2)", () => {
    const b = bindParticipantIdentity('subcontractor', {
      subcontractorCertId: 'cert_sub_123',
    });
    expect(b.role).toBe('subcontractor');
    expect(b.actorCertId).toBe('cert_sub_123');
    expect(identityTier(b)).toBe('L2');
  });

  test("un-cert'd subcontractor → falls to external + L1 handle (§5.4)", () => {
    const b = bindParticipantIdentity('subcontractor', {
      phone: '+61400111222',
    });
    expect(b.role).toBe('external'); // narrowed — no invented guest cert
    expect(b.actorCertId).toBeUndefined();
    expect(b.identityHandle).toEqual({ kind: 'phone', value: '+61400111222' });
    expect(identityTier(b)).toBe('L1');
  });

  test('tradesman with no cert → external + L1', () => {
    const b = bindParticipantIdentity('tradesman', {
      email: 'tradie@example.com',
    });
    expect(b.role).toBe('external');
    expect(b.identityHandle).toEqual({
      kind: 'email',
      value: 'tradie@example.com',
    });
    expect(identityTier(b)).toBe('L1');
  });

  test('tenant via cookie → L0 handle, null cert', () => {
    const b = bindParticipantIdentity('tenant', { cookie: 'sess-abc' });
    expect(b.role).toBe('tenant');
    expect(b.actorCertId).toBeUndefined();
    expect(b.identityHandle).toEqual({ kind: 'cookie', value: 'sess-abc' });
    expect(identityTier(b)).toBe('L0');
  });

  test('tenant via phone → L1 handle', () => {
    const b = bindParticipantIdentity('tenant', { phone: '+61400999888' });
    expect(b.identityHandle).toEqual({ kind: 'phone', value: '+61400999888' });
    expect(identityTier(b)).toBe('L1');
  });

  test('phone/email (L1) preferred over cookie (L0) when both present', () => {
    const b = bindParticipantIdentity('owner', {
      cookie: 'sess-x',
      phone: '+61411222333',
    });
    expect(b.identityHandle).toEqual({ kind: 'phone', value: '+61411222333' });
    expect(identityTier(b)).toBe('L1');
  });

  test('external with no marker at all → neither cert nor handle (L0 floor)', () => {
    const b = bindParticipantIdentity('external', {});
    expect(b.actorCertId).toBeUndefined();
    expect(b.identityHandle).toBeUndefined();
    expect(identityTier(b)).toBe('L0');
  });
});

describe('identityTier — tier derivation (§13.2)', () => {
  test('L2 when actorCertId present', () => {
    expect(identityTier({ actorCertId: 'cert_x' })).toBe('L2');
  });
  test('L1 when handle is phone/email', () => {
    expect(identityTier({ identityHandle: { kind: 'phone', value: 'p' } })).toBe('L1');
    expect(identityTier({ identityHandle: { kind: 'email', value: 'e' } })).toBe('L1');
  });
  test('L0 when handle is cookie', () => {
    expect(identityTier({ identityHandle: { kind: 'cookie', value: 'c' } })).toBe('L0');
  });
  test('null cert + null handle → L0 floor', () => {
    expect(identityTier({ actorCertId: null, identityHandle: null })).toBe('L0');
  });
  test('cert wins over handle (defensive — invariant should prevent both)', () => {
    expect(
      identityTier({
        actorCertId: 'cert_x',
        identityHandle: { kind: 'phone', value: 'p' },
      }),
    ).toBe('L2');
  });
});

describe('recordIntakeTurn — multiparty identity on canonical turns', () => {
  test('operator reply → actorCertId set, no identityHandle, tier L2', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      {
        ...baseArgs,
        outboundParticipantRole: 'operator',
        operatorCertId: 'cert_op_root',
      },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const outbound = semSeen[1]!;
    expect(outbound.participantRole).toBe('operator');
    expect(outbound.actorCertId).toBe('cert_op_root');
    expect(outbound.identityHandle).toBeUndefined();
    expect(identityTier(outbound)).toBe('L2');
  });

  test('ai reply with provisioned cert → actorCertId = AI cert, tier L2', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      { ...baseArgs, agentCertId: 'cert_ai_xyz' },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const outbound = semSeen[1]!;
    expect(outbound.participantRole).toBe('ai');
    expect(outbound.actorCertId).toBe('cert_ai_xyz');
    expect(identityTier(outbound)).toBe('L2');
  });

  test('ai reply with NO cert yet → documented sentinel, tier L2', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      baseArgs, // no agentCertId — default ai role
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const outbound = semSeen[1]!;
    expect(outbound.participantRole).toBe('ai');
    expect(outbound.actorCertId).toBe(AI_CERT_PENDING_SENTINEL);
    expect(identityTier(outbound)).toBe('L2');
  });

  test('tenant via widget cookie → actorCertId null, cookie handle, tier L0', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      {
        ...baseArgs,
        inboundParticipantRole: 'tenant',
        inboundCookie: 'sess-abc',
      },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    expect(inbound.participantRole).toBe('tenant');
    expect(inbound.actorCertId).toBeUndefined();
    expect(inbound.identityHandle).toEqual({ kind: 'cookie', value: 'sess-abc' });
    expect(identityTier(inbound)).toBe('L0');
  });

  test('tenant via phone → phone handle, tier L1', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      {
        ...baseArgs,
        inboundParticipantRole: 'tenant',
        inboundPhone: '+61400999888',
      },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    expect(inbound.identityHandle).toEqual({
      kind: 'phone',
      value: '+61400999888',
    });
    expect(identityTier(inbound)).toBe('L1');
  });

  test('external email sender → email handle, tier L1', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      {
        ...baseArgs,
        surface: 'email',
        inboundParticipantRole: 'external',
        inboundEmail: 'sender@example.com',
      },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    expect(inbound.participantRole).toBe('external');
    expect(inbound.identityHandle).toEqual({
      kind: 'email',
      value: 'sender@example.com',
    });
    expect(identityTier(inbound)).toBe('L1');
  });

  test("cert'd inbound subcontractor → actorCertId set, tier L2", async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      {
        ...baseArgs,
        inboundParticipantRole: 'subcontractor',
        inboundActorCertId: 'cert_sub_123',
      },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    expect(inbound.participantRole).toBe('subcontractor');
    expect(inbound.actorCertId).toBe('cert_sub_123');
    expect(inbound.identityHandle).toBeUndefined();
    expect(identityTier(inbound)).toBe('L2');
  });

  test("un-cert'd inbound subcontractor → narrows to external + L1", async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      {
        ...baseArgs,
        inboundParticipantRole: 'subcontractor',
        inboundPhone: '+61400111222',
      },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const inbound = semSeen[0]!;
    expect(inbound.participantRole).toBe('external'); // §5.4 fall-through
    expect(inbound.actorCertId).toBeUndefined();
    expect(inbound.identityHandle).toEqual({
      kind: 'phone',
      value: '+61400111222',
    });
    expect(identityTier(inbound)).toBe('L1');
  });

  test('canonical turn round-trips identityHandle through JSON', async () => {
    const semSeen: OddjobzConversationTurnPayload[] = [];
    await recordIntakeTurn(
      {
        ...baseArgs,
        inboundParticipantRole: 'tenant',
        inboundPhone: '+61400999888',
      },
      deps(() => {}, { semObjectSink: (t) => semSeen.push(t) }),
    );
    const recovered = JSON.parse(
      JSON.stringify(semSeen[0]!),
    ) as OddjobzConversationTurnPayload;
    expect(recovered.identityHandle).toEqual({
      kind: 'phone',
      value: '+61400999888',
    });
  });
});

```
