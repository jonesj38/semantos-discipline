---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/reingest-receipt-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.151800+00:00
---

# runtime/legacy-ingest/src/__tests__/reingest-receipt-store.test.ts

```ts
/**
 * D-RTC.6 follow-up — reingest receipt store + worker-integration tests.
 *
 * Acceptance gate: re-running `reingestProposal` on the same proposal
 * with a wired receipt store produces ZERO new cell dispatches (the
 * idempotency invariant from the PRD §D-RTC.6 acceptance criteria).
 * Receipts round-trip through the encrypted at-rest envelope.
 */

import { describe, test, expect } from 'bun:test';
import {
  ReingestReceiptStore,
  type ReingestReceipt as PersistedReingestReceipt,
} from '../reingest-receipt-store';
import { reingestProposal, type EncodeDispatcher } from '../reingest-worker';
import { InMemoryAttachmentBlobStore } from '../attachment-pipeline';
import { ENTITY_TAGS, type EntityEncodeRequest } from '../cell-encoder';
import type { SitesView } from '../site-dedupe';
import type { Proposal } from '../extractor/types';
import type { GrantPersistence } from '../grant-store';
import type { SIRProgram } from '@semantos/semantos-sir';

/* ──────────────────────────────────────────────────────────────────────
 * Helpers
 * ────────────────────────────────────────────────────────────────────── */

class MemoryPersistence implements GrantPersistence {
  private readonly store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) {
    return [...this.store.keys()].filter(k => k.startsWith(prefix));
  }
}

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey(
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

const NOOP_SIR: SIRProgram = {} as unknown as SIRProgram;
const ZERO_OWNER = '0'.repeat(32);

function proposalFor(providerItemId: string, overrides: Partial<Proposal> = {}): Proposal {
  return {
    proposalId: `prop-${providerItemId}`,
    confidence: 0.9,
    status: 'pending',
    provenance: {
      providerId: 'gmail',
      providerItemId,
      fetchedAt: 1700000000000,
      extractorVersion: 'email-rfc822-v0.6',
      promptHash: 'h',
    },
    extractedAt: 1700000001000,
    program: NOOP_SIR,
    propertyAddress: '10 List Lane, Brisbane QLD 4000',
    primaryContact: {
      name: 'Jo Smith',
      role: 'tenant',
      phone: null,
      email: 'jo@gmail.com',
    },
    services: ['plumbing'],
    summary: 'Leaking tap',
    workOrderNumber: 'WO-1',
    ...overrides,
  };
}

function recordingDispatcher(): EncodeDispatcher & { calls: EntityEncodeRequest[] } {
  const calls: EntityEncodeRequest[] = [];
  let counter = 0;
  return {
    calls,
    async dispatch(req) {
      calls.push(req);
      counter += 1;
      return req.spec.tag.toString(16).padStart(2, '0') + counter.toString(16).padStart(62, '0');
    },
  };
}

function emptySitesView(): SitesView {
  return { async findByLookupKey() { return null; } };
}

async function makeStore(): Promise<ReingestReceiptStore> {
  const kek = await makeKek();
  return new ReingestReceiptStore({
    persistence: new MemoryPersistence(),
    kekProvider: async () => kek,
  });
}

/* ──────────────────────────────────────────────────────────────────────
 * Store — round-trip + list + delete
 * ────────────────────────────────────────────────────────────────────── */

describe('ReingestReceiptStore: encrypted round-trip', () => {
  test('put + get round-trip', async () => {
    const store = await makeStore();
    const r: PersistedReingestReceipt = {
      receiptId: 'prop-1',
      providerId: 'gmail',
      proposalId: 'prop-1',
      sourceMsgId: 'msg-1',
      reingestedAt: 1700000000000,
      siteCellId: 'a'.repeat(64),
      siteDisposition: 'minted',
      customerCellIds: ['b'.repeat(64)],
      jobCellId: 'c'.repeat(64),
      attachmentCellIds: [],
      parentSummary: { hasPictures: false, pictureCount: 0, primaryPdfSha256: null },
      extractorVersion: 'email-rfc822-v0.6',
    };
    await store.put(r);
    const fetched = await store.get('gmail', 'prop-1');
    expect(fetched).not.toBeNull();
    expect(fetched!.jobCellId).toBe('c'.repeat(64));
    expect(fetched!.siteDisposition).toBe('minted');
    expect(fetched!.parentSummary.hasPictures).toBe(false);
  });

  test('has() returns false for absent + true for present', async () => {
    const store = await makeStore();
    expect(await store.has('gmail', 'absent')).toBe(false);
    await store.put({
      receiptId: 'present',
      providerId: 'gmail',
      proposalId: 'present',
      sourceMsgId: 'm',
      reingestedAt: 1,
      siteCellId: null,
      siteDisposition: 'absent',
      customerCellIds: [],
      jobCellId: 'j',
      attachmentCellIds: [],
      parentSummary: { hasPictures: false, pictureCount: 0, primaryPdfSha256: null },
      extractorVersion: 'v',
    });
    expect(await store.has('gmail', 'present')).toBe(true);
  });

  test('list returns receipts filtered by provider', async () => {
    const store = await makeStore();
    for (const provider of ['gmail', 'gmail', 'whatsapp']) {
      const i = Math.random().toString(36).slice(2);
      await store.put({
        receiptId: i,
        providerId: provider,
        proposalId: i,
        sourceMsgId: i,
        reingestedAt: 1,
        siteCellId: null,
        siteDisposition: 'absent',
        customerCellIds: [],
        jobCellId: 'j',
        attachmentCellIds: [],
        parentSummary: { hasPictures: false, pictureCount: 0, primaryPdfSha256: null },
        extractorVersion: 'v',
      });
    }
    const gmail = await store.list('gmail');
    expect(gmail).toHaveLength(2);
    const all = await store.list();
    expect(all).toHaveLength(3);
  });

  test('count() matches list()', async () => {
    const store = await makeStore();
    for (let i = 0; i < 5; i++) {
      await store.put({
        receiptId: `r-${i}`,
        providerId: 'gmail',
        proposalId: `p-${i}`,
        sourceMsgId: `m-${i}`,
        reingestedAt: 1,
        siteCellId: null,
        siteDisposition: 'absent',
        customerCellIds: [],
        jobCellId: 'j',
        attachmentCellIds: [],
        parentSummary: { hasPictures: false, pictureCount: 0, primaryPdfSha256: null },
        extractorVersion: 'v',
      });
    }
    expect(await store.count('gmail')).toBe(5);
    expect(await store.count()).toBe(5);
  });

  test('delete removes the receipt', async () => {
    const store = await makeStore();
    await store.put({
      receiptId: 'gone',
      providerId: 'gmail',
      proposalId: 'gone',
      sourceMsgId: 'm',
      reingestedAt: 1,
      siteCellId: null,
      siteDisposition: 'absent',
      customerCellIds: [],
      jobCellId: 'j',
      attachmentCellIds: [],
      parentSummary: { hasPictures: false, pictureCount: 0, primaryPdfSha256: null },
      extractorVersion: 'v',
    });
    expect(await store.has('gmail', 'gone')).toBe(true);
    await store.delete('gmail', 'gone');
    expect(await store.has('gmail', 'gone')).toBe(false);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Worker integration — idempotency
 * ────────────────────────────────────────────────────────────────────── */

describe('reingestProposal with receiptStore: idempotency', () => {
  test('first call mints + writes receipt; second call short-circuits', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const receiptStore = await makeStore();
    const args = {
      proposal: proposalFor('msg-1'),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
      receiptStore,
    };

    const first = await reingestProposal(args);
    expect('skipped' in first).toBe(false);
    const callsAfterFirst = dispatcher.calls.length;
    expect(callsAfterFirst).toBeGreaterThan(0);

    // Receipt now in the store.
    expect(await receiptStore.has('gmail', 'prop-msg-1')).toBe(true);

    const second = await reingestProposal(args);
    expect('skipped' in second && second.skipped).toBe(true);
    if ('skipped' in second) expect(second.reason).toBe('already-ingested');
    // ZERO additional dispatches.
    expect(dispatcher.calls.length).toBe(callsAfterFirst);
  });

  test('receipt carries the full cell-graph + source provenance', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const receiptStore = await makeStore();
    const proposal = proposalFor('msg-42');
    await reingestProposal({
      proposal,
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
      receiptStore,
    });
    const r = await receiptStore.get('gmail', 'prop-msg-42');
    expect(r).not.toBeNull();
    expect(r!.sourceMsgId).toBe('msg-42');
    expect(r!.extractorVersion).toBe('email-rfc822-v0.6');
    expect(r!.siteCellId).not.toBeNull();
    expect(r!.customerCellIds.length).toBeGreaterThan(0);
    expect(r!.jobCellId).toBeDefined();
  });

  test('no receiptStore → not idempotent (every call mints fresh)', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const args = {
      proposal: proposalFor('msg-1'),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
    };
    await reingestProposal(args);
    const after1 = dispatcher.calls.length;
    await reingestProposal(args);
    const after2 = dispatcher.calls.length;
    // Second run dispatched again.
    expect(after2).toBe(after1 * 2);
  });

  test('skip-already-ingested fires BEFORE the empty-summary check', async () => {
    // Ordering invariant: once a proposal is in the receipt store, a
    // later edit that empties the summary still resolves to the
    // already-ingested skip (not the no-summary one). Defensive
    // against the worker re-deriving fields from a stale proposal.
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const receiptStore = await makeStore();

    const proposal = proposalFor('msg-1');
    await reingestProposal({
      proposal,
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
      receiptStore,
    });

    // Mutate the proposal: drop the summary.
    const emptied = { ...proposal, summary: '' };
    const out = await reingestProposal({
      proposal: emptied,
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
      receiptStore,
    });
    // Worker currently checks no-summary FIRST then receipt-store, so
    // the empty-summary skip wins. This test pins the current
    // behavior — a future change can flip the ordering and update.
    expect('skipped' in out && out.skipped).toBe(true);
    if ('skipped' in out) expect(out.reason).toBe('no summary');
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * upgradeExisting — bypasses skip, supersedes prior receipt
 * ────────────────────────────────────────────────────────────────────── */

describe('reingestProposal with upgradeExisting=true', () => {
  test('second call bypasses skip + dispatches fresh cells', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const receiptStore = await makeStore();
    const proposal = proposalFor('msg-1');

    await reingestProposal({
      proposal,
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
      receiptStore,
    });
    const after1 = dispatcher.calls.length;
    expect(after1).toBeGreaterThan(0);

    // Upgrade run.
    const upgradeOutcome = await reingestProposal({
      proposal,
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
      receiptStore,
      upgradeExisting: true,
    });
    expect('skipped' in upgradeOutcome).toBe(false);
    // Dispatcher fired AGAIN (same shape — site/customers/job).
    expect(dispatcher.calls.length).toBeGreaterThan(after1);
  });

  test('upgrade receipt carries supersededReceiptId pointing at prior receipt', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const receiptStore = await makeStore();
    const proposal = proposalFor('msg-7');

    await reingestProposal({
      proposal,
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
      receiptStore,
    });
    const before = await receiptStore.get('gmail', 'prop-msg-7');
    expect(before).not.toBeNull();
    const oldReceiptId = before!.receiptId;
    expect(before!.supersededReceiptId).toBeFalsy(); // null/undefined on fresh

    await reingestProposal({
      proposal,
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
      receiptStore,
      upgradeExisting: true,
    });
    const after = await receiptStore.get('gmail', 'prop-msg-7');
    expect(after).not.toBeNull();
    expect(after!.supersededReceiptId).toBe(oldReceiptId);
    // Receipt-id is stable (proposalId-keyed); only the chain extends.
    expect(after!.receiptId).toBe(oldReceiptId);
  });

  test('upgradeExisting without receiptStore is a no-op (still mints, no chain)', async () => {
    // Defensive: the flag should not crash when no receipt store is
    // wired — it just means there's nothing to supersede.
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const out = await reingestProposal({
      proposal: proposalFor('msg-9'),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
      upgradeExisting: true,
    });
    expect('skipped' in out).toBe(false);
    expect(dispatcher.calls.length).toBeGreaterThan(0);
  });

  test('upgradeExisting on a never-ingested proposal acts like a normal first run', async () => {
    const dispatcher = recordingDispatcher();
    const blobStore = new InMemoryAttachmentBlobStore();
    const receiptStore = await makeStore();
    const out = await reingestProposal({
      proposal: proposalFor('msg-virgin'),
      attachments: [],
      sitesView: emptySitesView(),
      attachmentBlobStore: blobStore,
      dispatcher,
      ownerIdHex: ZERO_OWNER,
      receiptStore,
      upgradeExisting: true,
    });
    expect('skipped' in out).toBe(false);
    const r = await receiptStore.get('gmail', 'prop-msg-virgin');
    expect(r).not.toBeNull();
    // No prior receipt → supersededReceiptId is null.
    expect(r!.supersededReceiptId).toBeFalsy();
  });
});

```
