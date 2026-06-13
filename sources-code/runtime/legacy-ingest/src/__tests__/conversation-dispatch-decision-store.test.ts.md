---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/conversation-dispatch-decision-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.154413+00:00
---

# runtime/legacy-ingest/src/__tests__/conversation-dispatch-decision-store.test.ts

```ts
import { describe, expect, it } from 'bun:test';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { ConversationDispatchRouter } from '../conversation/dispatch-router';
import {
  JsonlConversationDispatchDecisionSink,
  dispatchDecisionToRecord,
} from '../conversation/dispatch-decision-store';
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

describe('conversation dispatch decision store', () => {
  it('records a dispatch decision as oddjobz.dispatch.v1 JSONL', async () => {
    const root = mkdtempSync(join(tmpdir(), 'semantos-dispatch-'));
    try {
      const sink = new JsonlConversationDispatchDecisionSink({
        root,
        now: () => 1_700_000_000_222,
      });

      const wrote = await sink.append(makePatch());

      expect(wrote).toBe(true);
      const path = join(root, 'data', 'oddjobz', 'dispatch-decisions.jsonl');
      const row = JSON.parse(readFileSync(path, 'utf8').trim());
      expect(row.schema).toBe('oddjobz.dispatch.v1');
      expect(row.op).toBe('oddjobz.dispatch.v1');
      expect(row.decisionId).toMatch(/^dispatch_[0-9a-f]{16}$/);
      expect(row.sourcePatchId).toBe('msg_0011223344556677');
      expect(row.lane).toBe('direct');
      expect(row.primaryTarget.ref).toBe('alice@example.com');
      expect(row.writtenAt).toBe(1_700_000_000_222);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('deduplicates decisions for the same source patch and primary route', async () => {
    const root = mkdtempSync(join(tmpdir(), 'semantos-dispatch-'));
    try {
      const sink = new JsonlConversationDispatchDecisionSink({ root });
      const patch = makePatch();

      await sink.append(patch);
      await sink.append(patch);

      const path = join(root, 'data', 'oddjobz', 'dispatch-decisions.jsonl');
      const lines = readFileSync(path, 'utf8').trim().split('\n');
      expect(lines).toHaveLength(1);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('can use a graph-aware router supplied by the host', async () => {
    const root = mkdtempSync(join(tmpdir(), 'semantos-dispatch-'));
    try {
      const router = new ConversationDispatchRouter({
        resolveCandidates: () => [{
          lane: 'self',
          target: {
            type: 'job',
            ref: 'job-1',
            label: 'Kitchen tap repair',
            score: 0.95,
            source: 'graph',
          },
        }],
      });
      const sink = new JsonlConversationDispatchDecisionSink({
        root,
        router,
        routeOpts: { lane: 'self' },
      });

      await sink.append(makePatch({ role: 'operator', text: 'note to self' }));

      const path = join(root, 'data', 'oddjobz', 'dispatch-decisions.jsonl');
      const row = JSON.parse(readFileSync(path, 'utf8').trim());
      expect(row.lane).toBe('self');
      expect(row.primaryTarget).toMatchObject({ type: 'job', ref: 'job-1' });
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('turns a decision into a stable record', async () => {
    const router = new ConversationDispatchRouter();
    const decision = await router.route(makePatch());

    const a = dispatchDecisionToRecord(decision, 1);
    const b = dispatchDecisionToRecord(decision, 2);

    expect(a.decisionId).toBe(b.decisionId);
    expect(a.writtenAt).toBe(1);
    expect(b.writtenAt).toBe(2);
  });
});

```
