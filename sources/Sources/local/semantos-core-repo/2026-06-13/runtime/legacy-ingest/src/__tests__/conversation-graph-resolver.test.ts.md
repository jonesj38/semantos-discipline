---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/conversation-graph-resolver.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.153525+00:00
---

# runtime/legacy-ingest/src/__tests__/conversation-graph-resolver.test.ts

```ts
import { describe, expect, it } from 'bun:test';
import { appendFileSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import {
  OddjobzConversationGraphResolver,
  type ConversationPaskQuery,
} from '../conversation/graph-resolver';
import type { ConversationDispatchResolverInput } from '../conversation/dispatch-router';
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
    text: 'Subject: Job 2512014150\nBody: Kitchen tap leaking at 12 Test St',
    timestamp: 1_700_000_000_000,
    writtenAt: 1_700_000_000_111,
    source: {
      providerItemId: 'gmail-1',
      contentType: 'email/rfc822',
      sourceBlobKey: 'legacy-ingest/gmail/gmail-1',
      subject: 'Job 2512014150',
      from: 'Alice <alice@example.com>',
      to: 'Todd <todd@oddjobtodd.info>',
    },
    target: {
      type: 'conversation-session',
      ref: 'email:thread-1',
    },
    ...overrides,
  };
}

function inputFor(
  patch: OddjobzMessagePatch,
  lane: ConversationDispatchResolverInput['lane'] = 'self',
): ConversationDispatchResolverInput {
  return {
    patch,
    lane,
    slot: `talk.${lane}`,
    text: patch.text,
  };
}

function writeJsonl(dir: string, name: string, rows: unknown[]): void {
  for (const row of rows) {
    appendFileSync(join(dir, name), `${JSON.stringify(row)}\n`);
  }
}

function makeGraphDir(): string {
  const root = mkdtempSync(join(tmpdir(), 'oddjobz-graph-'));
  mkdirSync(root, { recursive: true });
  writeJsonl(root, 'sites.jsonl', [
    {
      cellId: 'site-1',
      fullAddress: '12 Test St, Tewantin, QLD 4565',
      normalisedAddress: '12 test st, tewantin, qld 4565',
    },
  ]);
  writeJsonl(root, 'customers.jsonl', [
    {
      cellId: 'customer-1',
      display_name: 'Alice Example',
      email: 'alice@example.com',
      phone: '0412 345 678',
      role: 'tenant',
      siteRef: 'site-1',
      sourceProvenance: {
        providerId: 'gmail',
        providerItemId: 'gmail-1',
      },
    },
  ]);
  writeJsonl(root, 'jobs.jsonl', [
    {
      cellId: 'job-1',
      summary: 'Kitchen tap repair',
      state: 'lead',
      workOrderNumber: '2512014150',
      siteRef: 'site-1',
      customerRefs: [{ cellId: 'customer-1', primary: true, role: 'tenant' }],
    },
  ]);
  writeJsonl(root, 'attachments.jsonl', [
    {
      cellId: 'attachment-1',
      jobRef: 'job-1',
      sourceBlobKey: 'legacy-ingest/gmail/gmail-1',
    },
  ]);
  return root;
}

describe('OddjobzConversationGraphResolver', () => {
  it('resolves a source-neutral message onto job/customer/site graph candidates', async () => {
    const dir = makeGraphDir();
    try {
      const resolver = new OddjobzConversationGraphResolver({ oddjobzDir: dir });

      const candidates = await resolver.resolve(inputFor(makePatch(), 'self'));

      expect(candidates.map((c) => c.target.type)).toContain('job');
      expect(candidates.map((c) => c.target.type)).toContain('customer');
      expect(candidates.map((c) => c.target.type)).toContain('site');
      expect(candidates.find((c) => c.target.type === 'job')?.target.ref).toBe('job-1');
      expect(candidates.find((c) => c.target.type === 'customer')?.target.ref).toBe('customer-1');
      expect(candidates.find((c) => c.target.type === 'site')?.target.ref).toBe('site-1');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('returns a participant candidate for direct dispatch when a customer matches', async () => {
    const dir = makeGraphDir();
    try {
      const resolver = new OddjobzConversationGraphResolver({ oddjobzDir: dir });

      const candidates = await resolver.resolve(inputFor(makePatch(), 'direct'));

      const participant = candidates.find((c) => c.target.type === 'participant');
      expect(participant?.target.ref).toBe('alice@example.com');
      expect(participant?.target.label).toBe('Alice Example');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('matches jobs from work-order text even without a source blob key', async () => {
    const dir = makeGraphDir();
    try {
      const resolver = new OddjobzConversationGraphResolver({ oddjobzDir: dir });
      const patch = makePatch({
        recipientId: 'unknown@example.com',
        source: {
          providerItemId: 'other',
          contentType: 'email/rfc822',
          subject: 'Reference Number: 2512014150',
        },
      });

      const candidates = await resolver.resolve(inputFor(patch, 'self'));

      expect(candidates.find((c) => c.target.type === 'job')?.target.ref).toBe('job-1');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('uses Pask distance as a boost without making Pask mandatory', async () => {
    const dir = makeGraphDir();
    try {
      let seenCustomerPaskId: string | null = null;
      const pask: ConversationPaskQuery = {
        getActiveContext: () => 'ingest:session:email:thread-1',
        distance: (_from, to) => {
          if (to.startsWith('ingest:customer:')) {
            seenCustomerPaskId = to;
            return 0;
          }
          return Infinity;
        },
      };
      const resolver = new OddjobzConversationGraphResolver({ oddjobzDir: dir, pask });

      const candidates = await resolver.resolve(inputFor(makePatch(), 'self'));
      const customer = candidates.find((c) => c.target.type === 'customer');

      expect(customer?.target.source).toBe('pask');
      expect(customer?.target.score).toBeGreaterThan(0.82);
      expect(seenCustomerPaskId).toMatch(/^ingest:customer:/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

```
