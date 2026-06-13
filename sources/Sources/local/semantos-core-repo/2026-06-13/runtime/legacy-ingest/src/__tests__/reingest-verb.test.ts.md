---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/reingest-verb.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.145444+00:00
---

# runtime/legacy-ingest/src/__tests__/reingest-verb.test.ts

```ts
/**
 * D-RTC.7 — `legacy reingest <provider>` CLI conformance tests.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.7.
 *
 * Acceptance gate: `legacy reingest <provider> --dry-run --since
 * <date>` reports projected ratification counts without writing.
 * Also: missing deps surface clean error messages; non-dry-run paths
 * are gated until the encoder dispatcher is wired.
 */

import { describe, test, expect } from 'bun:test';
import { makeRouteLegacy } from '../verb';
import { ProposalStore } from '../proposal-store';
import { LegacyBlobStore } from '../blob-store';
import { ProviderRegistry, OAuthOrchestrator } from '../oauth';
import { LegacyGrantStore, type GrantPersistence } from '../grant-store';
import { InMemoryAttachmentBlobStore } from '../attachment-pipeline';
import type { SitesView } from '../site-dedupe';
import type { EncodeDispatcher } from '../reingest-worker';
import type { Proposal } from '../extractor/types';
import type { LegacyProvider, ListPageResult, RawItem, AccessToken } from '../types';
import type { SIRProgram } from '@semantos/semantos-sir';

/* ──────────────────────────────────────────────────────────────────────
 * Helpers
 * ────────────────────────────────────────────────────────────────────── */

class MemoryPersistence implements GrantPersistence {
  private store = new Map<string, Uint8Array>();
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

const STUB_PROVIDER: LegacyProvider = {
  id: 'gmail',
  displayName: 'Gmail',
  oauthScopes: [],
  oauthAuthorizeUrl: 'https://x/auth',
  oauthTokenUrl: 'https://x/tok',
  oauthRevokeUrl: 'https://x/rev',
  async listPage(): Promise<ListPageResult> {
    return { items: [], nextCursor: null };
  },
  async fetchFull(_t: AccessToken, item: RawItem) { return item; },
  fingerprint(item: RawItem) { return item.providerItemId; },
};

const NOOP_SIR: SIRProgram = {} as unknown as SIRProgram;

function proposalFor(providerItemId: string, overrides: Partial<Proposal> = {}): Proposal {
  return {
    proposalId: `p-${providerItemId}`,
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

const PLAIN_EMAIL_BYTES = new TextEncoder().encode(
  [
    'From: pm@cleverproperty.com.au',
    'To: ops@example.com',
    'Subject: tap',
    'Content-Type: text/plain',
    '',
    'leaking tap',
  ].join('\r\n'),
);

async function buildCtx(overrides: {
  withDispatcher?: boolean;
  withSitesView?: boolean;
  withAttachmentStore?: boolean;
  withBlobStore?: boolean;
  withProposalStore?: boolean;
} = {}) {
  const persistence = new MemoryPersistence();
  const kek = await makeKek();
  const registry = new ProviderRegistry();
  registry.register(STUB_PROVIDER);
  const grantStore = new LegacyGrantStore({
    persistence,
    kekProvider: async () => kek,
  });
  const orchestrator = new OAuthOrchestrator({
    registry,
    store: grantStore,
    configProvider: () => null,
    fetch: async () => new Response('', { status: 200 }),
  });

  const proposalStore =
    overrides.withProposalStore === false
      ? undefined
      : new ProposalStore({ persistence, kekProvider: async () => kek });
  const blobStore =
    overrides.withBlobStore === false
      ? undefined
      : new LegacyBlobStore({ persistence, kekProvider: async () => kek });

  const sitesView: SitesView | undefined =
    overrides.withSitesView === false
      ? undefined
      : { async findByLookupKey() { return null; } };
  const attachmentBlobStore =
    overrides.withAttachmentStore === false
      ? undefined
      : new InMemoryAttachmentBlobStore();

  const dispatcherCalls: Array<{ tag: number }> = [];
  const encodeDispatcher: EncodeDispatcher | undefined =
    overrides.withDispatcher === false
      ? undefined
      : {
          async dispatch(req) {
            dispatcherCalls.push({ tag: req.spec.tag });
            return req.spec.tag.toString(16).padStart(64, '0');
          },
        };

  const ctx = {
    registry,
    store: grantStore,
    orchestrator,
    proposalStore,
    blobStore,
    sitesView,
    attachmentBlobStore,
    encodeDispatcher,
  };
  return { ctx, proposalStore, blobStore, dispatcherCalls };
}

/* ──────────────────────────────────────────────────────────────────────
 * Dependency-missing error surfaces
 * ────────────────────────────────────────────────────────────────────── */

describe('legacy reingest: missing deps return clean errors', () => {
  test('missing provider arg → usage error', async () => {
    const { ctx } = await buildCtx();
    const route = makeRouteLegacy(ctx);
    const r = await route({ positional: ['reingest'] }, null) as { error?: string };
    expect(r.error).toMatch(/Usage: legacy reingest/);
  });

  test('proposalStore not configured', async () => {
    const { ctx } = await buildCtx({ withProposalStore: false });
    const route = makeRouteLegacy(ctx);
    const r = await route({ positional: ['reingest', 'gmail'] }, null) as { error?: string };
    expect(r.error).toBe('proposal store not configured');
  });

  test('sitesView not configured', async () => {
    const { ctx } = await buildCtx({ withSitesView: false });
    const route = makeRouteLegacy(ctx);
    const r = await route({ positional: ['reingest', 'gmail'] }, null) as { error?: string };
    expect(r.error).toMatch(/sites view not configured/);
  });

  test('attachmentBlobStore not configured', async () => {
    const { ctx } = await buildCtx({ withAttachmentStore: false });
    const route = makeRouteLegacy(ctx);
    const r = await route({ positional: ['reingest', 'gmail'] }, null) as { error?: string };
    expect(r.error).toMatch(/attachment blob store not configured/);
  });

  test('non-dry-run without encoder dispatcher rejects', async () => {
    const { ctx } = await buildCtx({ withDispatcher: false });
    const route = makeRouteLegacy(ctx);
    const r = await route(
      { positional: ['reingest', 'gmail'] },
      null,
    ) as { error?: string };
    expect(r.error).toMatch(/encode dispatcher not configured/);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Dry-run path — keystone PRD acceptance
 * ────────────────────────────────────────────────────────────────────── */

describe('legacy reingest: --dry-run reports projected counts without writing', () => {
  test('reports scanned / reingested / projected counts for one proposal', async () => {
    const { ctx, proposalStore, blobStore, dispatcherCalls } = await buildCtx();
    // Seed: one proposal with a corresponding raw blob.
    await proposalStore!.put(proposalFor('msg-1'));
    await blobStore!.put({
      providerId: 'gmail',
      providerItemId: 'msg-1',
      fetchedAt: 1700000000000,
      contentType: 'email/rfc822',
      bytes: PLAIN_EMAIL_BYTES,
      metadata: {},
    });

    const route = makeRouteLegacy(ctx);
    const r = await route(
      { positional: ['reingest', 'gmail'], flags: { 'dry-run': true } },
      null,
    ) as {
      ok: boolean;
      dryRun: boolean;
      scanned: number;
      reingested: number;
      skipped: number;
      errored: number;
      projectedCellCountsByTag: Record<number, number>;
    };

    expect(r.ok).toBe(true);
    expect(r.dryRun).toBe(true);
    expect(r.scanned).toBe(1);
    expect(r.reingested).toBe(1);
    expect(r.skipped).toBe(0);
    expect(r.errored).toBe(0);

    // 1 site + 1 customer + 1 job = 3 projected cells (no attachments
    // in PLAIN_EMAIL_BYTES).
    expect(r.projectedCellCountsByTag[0x07]).toBe(1); // TAG_SITE
    expect(r.projectedCellCountsByTag[0x01]).toBe(1); // TAG_CUSTOMER
    expect(r.projectedCellCountsByTag[0x06]).toBe(1); // TAG_JOB

    // Real dispatcher must NOT have fired in dry-run.
    expect(dispatcherCalls).toHaveLength(0);
  });

  test('--max caps the scan', async () => {
    const { ctx, proposalStore, blobStore } = await buildCtx();
    for (let i = 0; i < 5; i++) {
      await proposalStore!.put(proposalFor(`msg-${i}`));
      await blobStore!.put({
        providerId: 'gmail',
        providerItemId: `msg-${i}`,
        fetchedAt: 1700000000000,
        contentType: 'email/rfc822',
        bytes: PLAIN_EMAIL_BYTES,
        metadata: {},
      });
    }
    const route = makeRouteLegacy(ctx);
    const r = await route(
      { positional: ['reingest', 'gmail'], flags: { 'dry-run': true, max: 2 } },
      null,
    ) as { scanned: number; reingested: number };
    expect(r.scanned).toBe(2);
    expect(r.reingested).toBe(2);
  });

  test('proposal with empty summary is skipped, not errored', async () => {
    const { ctx, proposalStore, blobStore } = await buildCtx();
    await proposalStore!.put(proposalFor('msg-empty', { summary: '' }));
    await blobStore!.put({
      providerId: 'gmail',
      providerItemId: 'msg-empty',
      fetchedAt: 1700000000000,
      contentType: 'email/rfc822',
      bytes: PLAIN_EMAIL_BYTES,
      metadata: {},
    });
    const route = makeRouteLegacy(ctx);
    const r = await route(
      { positional: ['reingest', 'gmail'], flags: { 'dry-run': true } },
      null,
    ) as { scanned: number; skipped: number; reingested: number; errored: number };
    expect(r.scanned).toBe(1);
    expect(r.skipped).toBe(1);
    expect(r.reingested).toBe(0);
    expect(r.errored).toBe(0);
  });

  test('proposal whose raw blob is missing is errored, not crashed', async () => {
    const { ctx, proposalStore } = await buildCtx();
    // Put a proposal but NO corresponding raw blob.
    await proposalStore!.put(proposalFor('msg-orphan'));
    const route = makeRouteLegacy(ctx);
    const r = await route(
      { positional: ['reingest', 'gmail'], flags: { 'dry-run': true } },
      null,
    ) as {
      scanned: number;
      errored: number;
      errors: Array<{ proposalId: string; reason: string }>;
    };
    expect(r.scanned).toBe(1);
    expect(r.errored).toBe(1);
    expect(r.errors[0]!.reason).toBe('raw blob missing');
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Non-dry-run path → real dispatcher fires
 * ────────────────────────────────────────────────────────────────────── */

describe('legacy reingest: real run dispatches through encoder', () => {
  test('non-dry-run with wired dispatcher mints cells through the seam', async () => {
    const { ctx, proposalStore, blobStore, dispatcherCalls } = await buildCtx();
    await proposalStore!.put(proposalFor('msg-1'));
    await blobStore!.put({
      providerId: 'gmail',
      providerItemId: 'msg-1',
      fetchedAt: 1700000000000,
      contentType: 'email/rfc822',
      bytes: PLAIN_EMAIL_BYTES,
      metadata: {},
    });

    const route = makeRouteLegacy(ctx);
    const r = await route(
      { positional: ['reingest', 'gmail'] },
      null,
    ) as { ok: boolean; dryRun: boolean; reingested: number };

    expect(r.ok).toBe(true);
    expect(r.dryRun).toBe(false);
    expect(r.reingested).toBe(1);
    expect(dispatcherCalls.length).toBeGreaterThanOrEqual(3); // site + customer + job
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * --upgrade-existing flag (PRD §D-RTC.7)
 * ────────────────────────────────────────────────────────────────────── */

describe('legacy reingest: --upgrade-existing flag', () => {
  test('response surfaces upgradeExisting=true when flag is set', async () => {
    const { ctx, proposalStore, blobStore } = await buildCtx();
    await proposalStore!.put(proposalFor('msg-1'));
    await blobStore!.put({
      providerId: 'gmail',
      providerItemId: 'msg-1',
      fetchedAt: 1700000000000,
      contentType: 'email/rfc822',
      bytes: PLAIN_EMAIL_BYTES,
      metadata: {},
    });
    const route = makeRouteLegacy(ctx);
    const r = await route(
      {
        positional: ['reingest', 'gmail'],
        flags: { 'upgrade-existing': true },
      },
      null,
    ) as { ok: boolean; upgradeExisting: boolean; reingested: number };
    expect(r.ok).toBe(true);
    expect(r.upgradeExisting).toBe(true);
    expect(r.reingested).toBe(1);
  });

  test('without flag: response reports upgradeExisting=false', async () => {
    const { ctx, proposalStore, blobStore } = await buildCtx();
    await proposalStore!.put(proposalFor('msg-1'));
    await blobStore!.put({
      providerId: 'gmail',
      providerItemId: 'msg-1',
      fetchedAt: 1700000000000,
      contentType: 'email/rfc822',
      bytes: PLAIN_EMAIL_BYTES,
      metadata: {},
    });
    const route = makeRouteLegacy(ctx);
    const r = await route(
      { positional: ['reingest', 'gmail'] },
      null,
    ) as { upgradeExisting: boolean };
    expect(r.upgradeExisting).toBe(false);
  });

  test('flag string form ("true") is also accepted', async () => {
    const { ctx, proposalStore, blobStore } = await buildCtx();
    await proposalStore!.put(proposalFor('msg-x'));
    await blobStore!.put({
      providerId: 'gmail',
      providerItemId: 'msg-x',
      fetchedAt: 1700000000000,
      contentType: 'email/rfc822',
      bytes: PLAIN_EMAIL_BYTES,
      metadata: {},
    });
    const route = makeRouteLegacy(ctx);
    const r = await route(
      {
        positional: ['reingest', 'gmail'],
        flags: { 'upgrade-existing': 'true' },
      },
      null,
    ) as { upgradeExisting: boolean };
    expect(r.upgradeExisting).toBe(true);
  });
});

```
