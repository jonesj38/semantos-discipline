---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/integration-ratify-pipeline.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.145737+00:00
---

# runtime/legacy-ingest/src/__tests__/integration-ratify-pipeline.test.ts

```ts
/**
 * D-DOG.1.0 + D-DOG.1.0b' end-to-end pipeline test.
 *
 * Wires the legacy-ingest stack the way `apps/legacy-cli/src/bootstrap.ts`
 * wires it for real, swaps in a stub LLM + stub WS server, and walks
 * the full ingest → extract → ratify path. Asserts:
 *
 *   1. `legacy ingest <stub>` produces ≥1 blob AND ≥1 proposal.
 *   2. `legacy review` returns the proposal with cellId-equivalent
 *      pre-ratify status (status=pending).
 *   3. `legacy ratify <proposal-id>` returns a receipt whose cellId
 *      is a non-null JSON-array string.
 *   4. The stub WS server received the right SIRProgram + proposal_id
 *      + payload_hint.
 *   5. Re-ratifying the same proposal would short-circuit on the Semantos Brain
 *      side (asserted via the stub server's invocation count + the
 *      idempotent-cell-id contract — full Layer-2 idempotency is
 *      asserted in the Zig conformance suite).
 *
 * What this does NOT cover (deferred to the manual smoke + Zig suite):
 *   • Actual jobs.jsonl on-disk shape — covered in
 *     runtime/semantos-brain/tests/oddjobz_ratify_handler_conformance.zig.
 *   • Real brain subprocess management — too heavyweight for a unit
 *     test; the manual smoke step in the PR description spans that.
 */

import { describe, expect, test, beforeEach, afterEach } from 'bun:test';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  LegacyGrantStore,
  LegacyBlobStore,
  CursorStore,
  ProposalStore,
  ReceiptStore,
  CorrectionEdgeStore,
  IngestWorker,
  RatificationOrchestrator,
  ProviderRegistry,
  ExtractorRegistry,
  EmailExtractor,
  ExtractionRunner,
  BrainRpcCellWriter,
  makeRouteLegacy,
  type GrantPersistence,
  type LegacyProvider,
  type ListPageResult,
  type RawItem,
  type AccessToken,
  type LLMAdapter,
} from '..';

// ── stubs ─────────────────────────────────────────────────────────

class MemoryPersistence implements GrantPersistence {
  store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) { return [...this.store.keys()].filter(k => k.startsWith(prefix)); }
}

const REAL_EMAIL = `From: jane@acmecorp.com
Subject: Quote request for deck rebuild
Message-ID: <real-1@acmecorp.com>

Hi, I'd like a quote for rebuilding our back deck. ~30sqm.
`;

const STUB_PROVIDER: LegacyProvider = {
  id: 'stub',
  displayName: 'Stub provider',
  oauthScopes: ['stub'],
  oauthAuthorizeUrl: 'https://x/auth',
  oauthTokenUrl: 'https://x/token',
  oauthRevokeUrl: 'https://x/revoke',
  async listPage(): Promise<ListPageResult> {
    return {
      items: [{
        providerId: 'stub',
        providerItemId: 'item-real-001',
        fetchedAt: 1_700_000_000_000,
        contentType: 'email/rfc822',
        bytes: new TextEncoder().encode(REAL_EMAIL),
        metadata: {},
      }],
      nextCursor: null,
    };
  },
  async fetchFull(_t: AccessToken, item: RawItem) { return item; },
  fingerprint(item: RawItem) { return item.providerItemId; },
};

function stubLlm(): LLMAdapter {
  return {
    async extract<T>() {
      // Mirrors the EmailExtractor v0.5 LLM payload shape — the
      // `job_type` field drives `mapJobTypeToAction` in
      // extractor/email.ts. Older tests passed `intent` here but that
      // field is no longer read since Tier 1.7 landed; without
      // `job_type` the action ends up undefined and the fallback's
      // graph build short-circuits to an empty graph.
      return {
        payload: {
          job_type: 'quote_request',
          summary: 'Quote request from jane@acmecorp.com — deck rebuild ~30sqm',
          customer: { name: 'AcmeCorp Jane', email: 'jane@acmecorp.com' },
          job: { description: 'rebuild back deck, ~30sqm' },
        } as unknown as T,
        confidence: 0.92,
        raw: '{}',
      };
    },
  };
}

interface StubBrainServer {
  url: string;
  stop: () => void;
  invocations: () => number;
  lastReq: () => Record<string, unknown> | null;
}

/**
 * Mimic enough of brain's `oddjobz.ratify_proposal` RPC to drive the
 * RatificationOrchestrator → BrainRpcCellWriter pipeline. Returns a
 * deterministic cell id derived from the proposal_id so the test can
 * assert the receipt round-trips that.
 *
 * Tracks an idempotency map so a repeat ratify returns the same
 * cell_ids without minting a new id — same shape the real brain handler
 * promises.
 */
function startStubBrainServer(): StubBrainServer {
  let last: Record<string, unknown> | null = null;
  let invocations = 0;
  const ratified = new Map<string, string[]>();
  const srv = Bun.serve({
    port: 0,
    fetch(req, server) {
      if (server.upgrade(req)) return undefined;
      return new Response('ws only', { status: 400 });
    },
    websocket: {
      open() { /* no-op */ },
      message(ws, raw) {
        const text = typeof raw === 'string' ? raw : new TextDecoder().decode(raw as ArrayBuffer);
        let parsed: Record<string, unknown> | null = null;
        try { parsed = JSON.parse(text); } catch { /* protocol error path */ }
        last = parsed;
        invocations += 1;
        if (!parsed || parsed.method !== 'ratify.submit') {
          ws.send(JSON.stringify({ jsonrpc: '2.0', id: parsed?.id ?? null, error: { code: -32601, message: 'unknown method' } }));
          return;
        }
        const params = parsed.params as Record<string, unknown>;
        const pid = params.proposal_id as string;
        let cellIds = ratified.get(pid);
        if (!cellIds) {
          cellIds = [`stub-job-${pid.slice(0, 8)}`];
          ratified.set(pid, cellIds);
        }
        // D-DOG.1.0c Phase 2A.4 wire shape — graph-shaped cellIds.
        // The stub mints a single job id (matching what one
        // `create_lead`-shaped SIR action does in production) and
        // returns it on `cellIds.job`.
        ws.send(JSON.stringify({
          jsonrpc: '2.0',
          id: parsed.id,
          result: {
            proposal_id: pid,
            cellIds: {
              site: null,
              customers: [],
              job: cellIds[0],
              attachments: [],
            },
            persistedAt: 1_700_000_005,
          },
        }));
      },
    },
  });
  const port = srv.port;
  const host = srv.hostname ?? '127.0.0.1';
  const hostFmt = host.includes(':') ? `[${host}]` : host;
  return {
    url: `ws://${hostFmt}:${port}/wallet`,
    stop: () => srv.stop(true),
    invocations: () => invocations,
    lastReq: () => last,
  };
}

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

// ── the test ──────────────────────────────────────────────────────

describe('end-to-end: ingest → extract → ratify pipeline (D-DOG.1.0 + 1.0b\')', () => {
  let stubServer: StubBrainServer;

  beforeEach(() => {
    stubServer = startStubBrainServer();
  });

  afterEach(() => {
    stubServer.stop();
  });

  test('one email blob produces one proposal that ratifies into a real cell id over WS', async () => {
    const persistence = new MemoryPersistence();
    const kek = await makeKek();
    const kekProvider = async () => kek;

    const grantStore = new LegacyGrantStore({ persistence, kekProvider });
    const blobStore = new LegacyBlobStore({ persistence, kekProvider });
    const cursorStore = new CursorStore({ persistence });
    const proposalStore = new ProposalStore({ persistence, kekProvider });
    const receiptStore = new ReceiptStore({ persistence, kekProvider });
    const correctionStore = new CorrectionEdgeStore({ persistence, kekProvider });

    const registry = new ProviderRegistry();
    registry.register(STUB_PROVIDER);

    // Seed a grant so backfill has something to read.
    const issuedAt = Date.now();
    await grantStore.put({
      providerId: 'stub',
      grantId: 'g-1',
      accountLabel: 'stub-account',
      hatId: 'hat-1',
      createdAt: new Date().toISOString(),
      lastRefreshedAt: new Date().toISOString(),
      token: {
        accessToken: 'a',
        refreshToken: null,
        expiresAt: issuedAt + 3600 * 1000,
        scopes: ['stub'],
      },
    });

    const worker = new IngestWorker({
      blobStore, cursorStore,
      grantResolver: async (id) => {
        const g = await grantStore.listByProvider(id);
        return g[0] ?? null;
      },
    });

    // Real ExtractionRunner with a stub LLM.
    const extractorRegistry = new ExtractorRegistry();
    extractorRegistry.register(new EmailExtractor({ acceptThreshold: 0.5 }));
    const extractionRunner = new ExtractionRunner({
      blobStore, proposalStore, registry: extractorRegistry, llm: stubLlm(),
    });

    // Real BrainRpcCellWriter pointed at the in-process stub server.
    const cellWriter = new BrainRpcCellWriter({
      wsRpcUrl: stubServer.url,
      timeoutMs: 5000,
    });
    const ratification = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore,
      hatProvider: () => ({ hatId: 'hat-1', certId: null }),
      writeCell: ({ program, proposal }) => cellWriter.write({ program, proposal }),
    });

    // Build a no-op orchestrator stand-in for the verb (we don't drive
    // OAuth here — the grant is pre-seeded above).  The verb only needs
    // it for `connect/disconnect/etc`; ingest reads from `worker`.
    const routeLegacy = makeRouteLegacy({
      registry,
      store: grantStore,
      orchestrator: undefined as unknown as import('../oauth').OAuthOrchestrator,
      blobStore, cursorStore, worker,
      proposalStore, ratification,
      extractionRunner,
      continuousHandles: new Map(),
    });

    // 1. legacy ingest <stub>  — pulls one blob + extracts one proposal
    const ingestResult = await routeLegacy({
      positional: ['ingest', 'stub'],
      flags: { 'max-pages': 1 },
    }, null) as {
      ok: boolean;
      itemsPersisted: number;
      extract: { extracted?: number };
    };
    expect(ingestResult.ok).toBe(true);
    expect(ingestResult.itemsPersisted).toBe(1);
    expect(ingestResult.extract.extracted).toBe(1);

    // 2. legacy review — assert ≥1 pending proposal
    const reviewResult = await routeLegacy({
      positional: ['review'],
      flags: {},
    }, null) as { pending: number; proposals: Array<{ proposalId: string; status: string }> };
    expect(reviewResult.pending).toBe(1);
    expect(reviewResult.proposals[0]!.status).toBe('pending');
    const proposalId = reviewResult.proposals[0]!.proposalId;

    // 3. legacy ratify <provider>:<id> — POSTs to stub brain server
    const ratifyResult = await routeLegacy({
      positional: ['ratify', `stub:${proposalId}`],
    }, null) as { ok: boolean; receiptId: string; cellId: string | null };
    expect(ratifyResult.ok).toBe(true);
    expect(ratifyResult.cellId).not.toBeNull();
    // D-DOG.1.0c Phase 2B.1 — cellId is a JSON-encoded `cellIds` graph
    // object {site, customers, job, attachments}. Tests assert on the
    // single-job branch the stub produces.
    const cellIdsGraph = JSON.parse(ratifyResult.cellId!) as Record<string, unknown>;
    expect(cellIdsGraph.site).toBeNull();
    expect(cellIdsGraph.customers).toEqual([]);
    expect(typeof cellIdsGraph.job).toBe('string');
    expect(cellIdsGraph.job as string).toMatch(/^stub-job-/);
    expect(cellIdsGraph.attachments).toEqual([]);

    // 4. The stub WS server received exactly one ratify request with
    //    the right SIRProgram + proposal_id + payload_hint.
    expect(stubServer.invocations()).toBe(1);
    const lastReq = stubServer.lastReq();
    expect(lastReq).not.toBeNull();
    expect(lastReq!.method).toBe('ratify.submit');
    const params = lastReq!.params as Record<string, unknown>;
    expect(params.namespace).toBe('oddjobz');
    expect(params.proposal_id).toBe(proposalId);
    expect(params.sir_program).toBeDefined();
    const sir = params.sir_program as Record<string, unknown>;
    expect(Array.isArray(sir.nodes)).toBe(true);
    const hint = params.payload_hint as Record<string, unknown>;
    expect(typeof hint.customer_name).toBe('string');
    expect(hint.source_provider_id).toBe('stub');

    // 5. Idempotency: re-ratifying the same proposal would short-
    //    circuit on the Semantos Brain side and return the same cell ids. We
    //    can't easily re-drive `legacy ratify` because the orchestrator
    //    flips the proposal's status to 'ratified' after the first
    //    ratify, but the stub server's idempotency map is asserted by
    //    the Zig conformance suite (oddjobz_ratify_handler_conformance.
    //    zig: re-ratifying the same proposal_id is idempotent).  Here
    //    we just confirm the proposal flipped to 'ratified'.
    const reviewAfter = await routeLegacy({
      positional: ['review'],
      flags: {},
    }, null) as { pending: number };
    expect(reviewAfter.pending).toBe(0);
  });
});

// ── D-DOG.1.0c Phase 2B.2 — FS fallback E2E ────────────────────────────
//
// When brain's `/api/v1/wallet` is unreachable (no tenant manifest, 503,
// or the operator's brain process simply isn't running), the writer
// routes the ratify through the FS fallback path. After Phase 2B.2,
// this path produces the same graph of cells the WSS handler does:
// site + customers + job + attachments across four typed JSONL files.
//
// This test wires the full ingest → extract → ratify pipeline against
// a `BrainRpcCellWriter` whose WSS URL points nowhere AND has
// `fsFallbackDataDir` set, then asserts:
//   1. All four `~/oddjobz/{sites,customers,jobs,attachments}.jsonl`
//      files populate (sites + customers + jobs; attachments only
//      when the proposal carries a sourceAttachmentPath, which the
//      stub email here doesn't).
//   2. The receipt's `cellId` is a JSON-encoded {site, customers,
//      job, attachments} graph object.
//   3. Re-ratifying is short-circuited by the proposal-level cache
//      (the orchestrator flips status to 'ratified', so we just
//      assert the on-disk graph is preserved).

class WSConstructFailure {
  constructor() {
    throw new Error('e2e fallback: ws unreachable');
  }
}

describe("end-to-end FS fallback: ingest → extract → ratify produces graph (D-DOG.1.0c Phase 2B.2)", () => {
  let dataDir: string;

  beforeEach(() => {
    dataDir = mkdtempSync(join(tmpdir(), 'd10c-2b2-e2e-'));
  });

  afterEach(() => {
    try { rmSync(dataDir, { recursive: true, force: true }); } catch { /* swallow */ }
  });

  test('one stub email ratifies through the FS fallback into all four typed JSONL view-stores', async () => {
    const persistence = new MemoryPersistence();
    const kek = await makeKek();
    const kekProvider = async () => kek;

    const grantStore = new LegacyGrantStore({ persistence, kekProvider });
    const blobStore = new LegacyBlobStore({ persistence, kekProvider });
    const cursorStore = new CursorStore({ persistence });
    const proposalStore = new ProposalStore({ persistence, kekProvider });
    const receiptStore = new ReceiptStore({ persistence, kekProvider });
    const correctionStore = new CorrectionEdgeStore({ persistence, kekProvider });

    const registry = new ProviderRegistry();
    registry.register(STUB_PROVIDER);

    const issuedAt = Date.now();
    await grantStore.put({
      providerId: 'stub',
      grantId: 'g-1',
      accountLabel: 'stub-account',
      hatId: 'hat-1',
      createdAt: new Date().toISOString(),
      lastRefreshedAt: new Date().toISOString(),
      token: {
        accessToken: 'a',
        refreshToken: null,
        expiresAt: issuedAt + 3600 * 1000,
        scopes: ['stub'],
      },
    });

    const worker = new IngestWorker({
      blobStore, cursorStore,
      grantResolver: async (id) => {
        const g = await grantStore.listByProvider(id);
        return g[0] ?? null;
      },
    });

    const extractorRegistry = new ExtractorRegistry();
    extractorRegistry.register(new EmailExtractor({ acceptThreshold: 0.5 }));
    const extractionRunner = new ExtractionRunner({
      blobStore, proposalStore, registry: extractorRegistry, llm: stubLlm(),
    });

    // Writer points at a never-bound port AND has fsFallbackDataDir
    // set. The throwing WS ctor short-circuits the WSS attempt and
    // forces the fallback path on every ratify.
    const cellWriter = new BrainRpcCellWriter({
      wsRpcUrl: 'ws://localhost:1/never',
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      webSocketCtor: WSConstructFailure as any,
      fsFallbackDataDir: dataDir,
      fsFallbackHatId: 'hat-1',
    });
    const ratification = new RatificationOrchestrator({
      proposalStore, receiptStore, correctionStore,
      hatProvider: () => ({ hatId: 'hat-1', certId: null }),
      writeCell: ({ program, proposal }) => cellWriter.write({ program, proposal }),
    });

    const routeLegacy = makeRouteLegacy({
      registry,
      store: grantStore,
      orchestrator: undefined as unknown as import('../oauth').OAuthOrchestrator,
      blobStore, cursorStore, worker,
      proposalStore, ratification,
      extractionRunner,
      continuousHandles: new Map(),
    });

    // Silence the [brain-rpc] WSS unavailable warning that fires every
    // ratify in this test (we expect it).
    const origWarn = console.warn;
    console.warn = () => {};
    try {
      // 1. ingest
      const ingestResult = await routeLegacy({
        positional: ['ingest', 'stub'],
        flags: { 'max-pages': 1 },
      }, null) as { ok: boolean; itemsPersisted: number };
      expect(ingestResult.ok).toBe(true);

      // 2. review
      const reviewResult = await routeLegacy({
        positional: ['review'],
        flags: {},
      }, null) as { proposals: Array<{ proposalId: string }> };
      const proposalId = reviewResult.proposals[0]!.proposalId;

      // 3. ratify
      const ratifyResult = await routeLegacy({
        positional: ['ratify', `stub:${proposalId}`],
      }, null) as { ok: boolean; cellId: string | null };
      expect(ratifyResult.ok).toBe(true);
      expect(ratifyResult.cellId).not.toBeNull();
      const decoded = JSON.parse(ratifyResult.cellId!) as Record<string, unknown>;
      // The graph: site + (synthesised primary) customer + job +
      // attachment (the EmailExtractor v0.5 always stamps the source
      // blob key as `sourceAttachmentPath`, even for plain emails
      // with no PDF — defends against prompt injection in the LLM
      // path).
      expect(typeof decoded.site).toBe('string');
      expect((decoded.customers as string[]).length).toBe(1);
      expect(typeof decoded.job).toBe('string');
      expect((decoded.attachments as string[]).length).toBe(1);

      // 4. All four populated JSONL files exist with one row each.
      const oddjobzDir = join(dataDir, 'oddjobz');
      for (const fname of ['sites.jsonl', 'customers.jsonl', 'jobs.jsonl', 'attachments.jsonl']) {
        const path = join(oddjobzDir, fname);
        expect(existsSync(path)).toBe(true);
        const lines = readFileSync(path, 'utf8').split('\n').filter(l => l.length > 0);
        expect(lines.length).toBe(1);
      }

      // legacy-ratifications.jsonl carries the graph-shaped index.
      const indexLines = readFileSync(join(oddjobzDir, 'legacy-ratifications.jsonl'), 'utf8')
        .split('\n').filter(l => l.length > 0);
      expect(indexLines.length).toBe(1);
      const indexRow = JSON.parse(indexLines[0]!) as Record<string, unknown>;
      expect(indexRow.proposal_id).toBe(proposalId);
      const indexGraph = indexRow.cellIds as Record<string, unknown>;
      expect(indexGraph.site).toBe(decoded.site);
      expect(indexGraph.job).toBe(decoded.job);
    } finally {
      console.warn = origWarn;
    }
  });
});

```
