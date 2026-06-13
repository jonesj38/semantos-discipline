---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/conversation-dispatch-router.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.154963+00:00
---

# runtime/legacy-ingest/src/__tests__/conversation-dispatch-router.test.ts

```ts
import { describe, expect, it } from 'bun:test';
import {
  ConversationDispatchRouter,
  routeConversationDispatch,
  type ConversationDispatchCandidate,
} from '../conversation/dispatch-router';
import type { OddjobzMessagePatch } from '../conversation/turn-patch-store';

function makePatch(overrides: Partial<OddjobzMessagePatch> = {}): OddjobzMessagePatch {
  return {
    schema: 'oddjobz.message.v1',
    patchId: 'msg_0011223344556677',
    op: 'oddjobz.message.v1',
    providerId: 'gmail',
    sessionId: 'email:thread-1',
    channel: 'email',
    recipientId: 'alice@example.com',
    role: 'customer',
    text: 'Need the kitchen tap fixed',
    timestamp: 1_700_000_000_000,
    writtenAt: 1_700_000_000_111,
    target: {
      type: 'conversation-session',
      ref: 'email:thread-1',
    },
    ...overrides,
  };
}

describe('ConversationDispatchRouter', () => {
  it('routes inbound customer messages to the direct lane', async () => {
    const decision = await routeConversationDispatch(makePatch());

    expect(decision.lane).toBe('direct');
    expect(decision.slot).toBe('talk.direct');
    expect(decision.transport).toBe('direct');
    expect(decision.primaryTarget).toMatchObject({
      type: 'participant',
      ref: 'alice@example.com',
    });
    expect(decision.requiresRatification).toBe(false);
  });

  it('routes explicit squad language to multicast', async () => {
    const decision = await routeConversationDispatch(makePatch({
      role: 'operator',
      text: 'Squad, bring the big ladder to the front',
    }));

    expect(decision.lane).toBe('squad');
    expect(decision.slot).toBe('talk.squad');
    expect(decision.transport).toBe('multicast');
    expect(decision.primaryTarget).toMatchObject({
      type: 'squad',
      ref: 'squad:default',
    });
  });

  it('routes broadcast language to the broadcast lane and requires ratification', async () => {
    const decision = await routeConversationDispatch(makePatch({
      role: 'operator',
      text: 'Broadcast: bookings are full until next Thursday',
    }));

    expect(decision.lane).toBe('broadcast');
    expect(decision.transport).toBe('broadcast');
    expect(decision.requiresRatification).toBe(true);
  });

  it('defaults unresolved operator notes to self', async () => {
    const decision = await routeConversationDispatch(makePatch({
      role: 'operator',
      text: 'Need to pick up washers before this one',
    }));

    expect(decision.lane).toBe('self');
    expect(decision.slot).toBe('talk.self');
    expect(decision.transport).toBe('none');
  });

  it('lets an explicit UI lane override text heuristics', async () => {
    const decision = await routeConversationDispatch(makePatch({
      role: 'operator',
      text: 'Broadcast this later',
    }), {
      lane: 'self',
    });

    expect(decision.lane).toBe('self');
    expect(decision.reason).toBe('explicit UI lane');
    expect(decision.requiresRatification).toBe(false);
  });

  it('promotes Pask/context candidates for the selected lane', async () => {
    const candidates: ConversationDispatchCandidate[] = [
      {
        lane: 'self',
        target: {
          type: 'job',
          ref: 'job_42',
          label: 'Kitchen tap repair',
          score: 0.94,
          source: 'pask',
        },
        reason: 'active job is nearest to this session',
      },
      {
        lane: 'broadcast',
        target: {
          type: 'broadcast-channel',
          ref: 'website',
          score: 0.99,
          source: 'pask',
        },
      },
    ];
    const router = new ConversationDispatchRouter({
      resolveCandidates: ({ lane }) => candidates.filter((c) => c.lane === lane),
    });

    const decision = await router.route(makePatch({
      role: 'operator',
      text: 'note to self: quote this as mixer replacement',
    }));

    expect(decision.lane).toBe('self');
    expect(decision.primaryTarget).toMatchObject({
      type: 'job',
      ref: 'job_42',
      source: 'pask',
    });
    expect(decision.candidateReasons).toContain('active job is nearest to this session');
  });

  it('marks direct dispatch as parallelizable when several recipients resolve', async () => {
    const router = new ConversationDispatchRouter({
      resolveCandidates: () => [
        {
          lane: 'direct',
          target: {
            type: 'participant',
            ref: 'sparky@example.com',
            score: 0.86,
            source: 'pask',
          },
        },
      ],
    });

    const decision = await router.route(makePatch({
      role: 'operator',
      text: 'Tell the sparky not to come until 2',
    }));

    expect(decision.lane).toBe('direct');
    expect(decision.targets.map((t) => t.ref)).toContain('alice@example.com');
    expect(decision.targets.map((t) => t.ref)).toContain('sparky@example.com');
    expect(decision.parallelizable).toBe(true);
  });
});

```
