---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/attention-projector.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.142293+00:00
---

# runtime/legacy-ingest/src/__tests__/attention-projector.test.ts

```ts
import { describe, expect, it } from 'bun:test';
import { appendFileSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  OddjobzAttentionPaskProjector,
  createOddjobzAttentionSource,
  installOddjobzAttentionPipeline,
  type OddjobzAttentionSignalSource,
} from '../attention-projector';
import type { PaskInteractFn } from '../pask-bridge';

function writeJsonl(path: string, rows: unknown[]): void {
  for (const row of rows) {
    appendFileSync(path, `${JSON.stringify(row)}\n`);
  }
}

function makeFixture(): {
  root: string;
  oddjobzDir: string;
  messagesPath: string;
  dispatchPath: string;
} {
  const root = mkdtempSync(join(tmpdir(), 'oddjobz-attention-'));
  const oddjobzDir = join(root, 'data', 'oddjobz');
  mkdirSync(oddjobzDir, { recursive: true });
  const messagesPath = join(oddjobzDir, 'messages.jsonl');
  const dispatchPath = join(oddjobzDir, 'dispatch-decisions.jsonl');

  writeJsonl(join(oddjobzDir, 'sites.jsonl'), [
    {
      cellId: 'site-1',
      fullAddress: '12 Test St, Tewantin, QLD 4565',
      normalisedAddress: '12 test st, tewantin, qld 4565',
      keyNumber: 'K-42',
      createdAt: 1_700_000_000_000,
    },
  ]);
  writeJsonl(join(oddjobzDir, 'customers.jsonl'), [
    {
      cellId: 'customer-1',
      display_name: 'Alice Example',
      email: 'alice@example.com',
      phone: '0412 345 678',
      role: 'owner',
      siteRef: 'site-1',
      createdAt: 1_700_000_001_000,
    },
  ]);
  writeJsonl(join(oddjobzDir, 'jobs.jsonl'), [
    {
      cellId: 'job-1',
      summary: 'Kitchen tap repair',
      state: 'completed',
      workOrderNumber: '2512014150',
      dueDate: '2026-05-08',
      siteRef: 'site-1',
      customerRefs: [{ cellId: 'customer-1', primary: true, role: 'owner' }],
      hasPhotos: true,
      photoCount: 2,
      updatedAt: 1_700_000_002_000,
    },
  ]);
  writeJsonl(join(oddjobzDir, 'attachments.jsonl'), [
    {
      cellId: 'attachment-1',
      jobRef: 'job-1',
      sourceBlobKey: 'legacy-ingest/gmail/gmail-1',
    },
  ]);
  writeJsonl(messagesPath, [
    {
      schema: 'oddjobz.message.v1',
      patchId: 'msg-1',
      op: 'oddjobz.message.v1',
      providerId: 'gmail',
      sessionId: 'email:thread-1',
      channel: 'email',
      recipientId: 'alice@example.com',
      role: 'customer',
      text: 'Can you send the invoice for the kitchen tap?',
      timestamp: 1_700_000_003_000,
      writtenAt: 1_700_000_003_500,
      source: {
        providerItemId: 'gmail-1',
        contentType: 'email/rfc822',
        subject: 'Invoice for kitchen tap',
        from: 'Alice <alice@example.com>',
      },
      target: {
        type: 'conversation-session',
        ref: 'email:thread-1',
      },
    },
  ]);
  writeJsonl(dispatchPath, [
    {
      schema: 'oddjobz.dispatch.v1',
      op: 'oddjobz.dispatch.v1',
      decisionId: 'dispatch-1',
      writtenAt: 1_700_000_004_000,
      sourcePatchId: 'msg-1',
      providerId: 'gmail',
      sessionId: 'email:thread-1',
      lane: 'self',
      slot: 'talk.self',
      transport: 'none',
      text: 'Can you send the invoice for the kitchen tap?',
      confidence: 0.91,
      requiresRatification: true,
      reason: 'invoice action needs operator approval',
      primaryTarget: {
        type: 'job',
        ref: 'job-1',
        label: 'Kitchen tap repair',
        score: 0.95,
        source: 'graph',
      },
      targets: [],
      candidateReasons: ['work order match'],
      parallelizable: false,
    },
  ]);

  return { root, oddjobzDir, messagesPath, dispatchPath };
}

describe('OddjobzAttentionPaskProjector', () => {
  it('surfaces jobs, dispatch decisions, and messages as attention signals', () => {
    const fixture = makeFixture();
    try {
      const projector = new OddjobzAttentionPaskProjector({
        ...fixture,
        maxSignals: 10,
        signalTtlMs: 1_000,
      });

      const signals = projector.pollSignals(2_000_000_000_000);
      const ids = signals.map((s) => s.synthesizesObject?.id);

      expect(ids).toContain('oddjobz:job:job-1');
      expect(ids).toContain('oddjobz:dispatch:dispatch-1');
      expect(ids).toContain('ingest:message:msg-1');
      expect(signals[0]?.synthesizesObject?.id).toBe('oddjobz:job:job-1');
      expect(signals[0]?.factor.signal).toBe('Work complete - invoice needed');
      expect(signals.every((s) => s.sourceId === 'oddjobz-attention')).toBe(true);
    } finally {
      rmSync(fixture.root, { recursive: true, force: true });
    }
  });

  it('replays the complete Oddjobz graph into Pask interactions', () => {
    const fixture = makeFixture();
    try {
      const calls: Parameters<PaskInteractFn['interact']>[0][] = [];
      const pask: PaskInteractFn = {
        interact(args) {
          calls.push(args);
        },
      };
      const projector = new OddjobzAttentionPaskProjector({ ...fixture, pask });

      const summary = projector.replayToPask();

      expect(summary).toMatchObject({
        sites: 1,
        customers: 1,
        jobs: 1,
        messages: 1,
        dispatches: 1,
        interactions: 5,
      });
      expect(calls.map((c) => c.cellId)).toContain('oddjobz:site:site-1');
      expect(calls.map((c) => c.cellId)).toContain('oddjobz:customer:customer-1');
      expect(calls.map((c) => c.cellId)).toContain('oddjobz:job:job-1');
      expect(calls.map((c) => c.cellId)).toContain('ingest:message:msg-1');
      expect(calls.map((c) => c.cellId)).toContain('oddjobz:dispatch:dispatch-1');
      expect(calls.find((c) => c.cellId === 'oddjobz:dispatch:dispatch-1')?.relatedCells)
        .toContain('oddjobz:job:job-1');
    } finally {
      rmSync(fixture.root, { recursive: true, force: true });
    }
  });

  it('can be registered as an AttentionSignalSource', async () => {
    const fixture = makeFixture();
    try {
      const source = createOddjobzAttentionSource({
        ...fixture,
        maxSignals: 2,
      });

      const signals = await source.poll?.(2_000_000_000_000);

      expect(source.id).toBe('oddjobz-attention');
      expect(signals?.length).toBe(2);
      expect(signals?.map((s) => s.synthesizesObject?.id)).toContain('oddjobz:dispatch:dispatch-1');
      expect(signals?.map((s) => s.synthesizesObject?.id)).toContain('ingest:message:msg-1');
    } finally {
      rmSync(fixture.root, { recursive: true, force: true });
    }
  });

  it('installs into an attention registry and optionally replays to Pask', () => {
    const fixture = makeFixture();
    try {
      const calls: Parameters<PaskInteractFn['interact']>[0][] = [];
      const registered: Array<{
        source: OddjobzAttentionSignalSource;
        enabled: boolean | undefined;
      }> = [];
      const installed = installOddjobzAttentionPipeline({
        ...fixture,
        pask: {
          interact(args) {
            calls.push(args);
          },
        },
        signals: {
          register(source, opts) {
            registered.push({ source, enabled: opts?.enabled });
          },
        },
        replayToPask: true,
        enabled: false,
      });

      expect(registered).toHaveLength(1);
      expect(registered[0]?.source.id).toBe('oddjobz-attention');
      expect(registered[0]?.enabled).toBe(false);
      expect(installed.replaySummary?.interactions).toBe(5);
      expect(calls.map((c) => c.cellId)).toContain('oddjobz:dispatch:dispatch-1');
    } finally {
      rmSync(fixture.root, { recursive: true, force: true });
    }
  });
});

```
