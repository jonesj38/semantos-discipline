---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/legacy-host.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.474803+00:00
---

# cartridges/oddjobz/brain/src/legacy-host.ts

```ts
/**
 * LI-3 — legacy OAuth onboarding host (bun).
 *
 * Composes the legacy-ingest OAuth context with DURABLE filesystem persistence +
 * a persistent AES-GCM KEK, and routes a subcommand via makeRouteLegacy. Lets the
 * operator register a provider's OAuth client, start a grant (get the consent URL),
 * and complete it (resume <state> <code>) across separate process invocations
 * (pending state is disk-backed). Onboarding subcommands: register-client, connect,
 * resume, disconnect, status, providers, clients, unregister-client.
 * The ingest/extract/ratify pipeline is wired in a follow-up (needs the LLM +
 * cell-writer); those subcommands return "not configured" here.
 *
 *   stdin:  { "args": ["<subcommand>", ...], "flags": { ... } }
 *   stdout: the routeLegacy result as JSON
 */
import { mkdirSync, readFileSync, writeFileSync, readdirSync, existsSync, unlinkSync, statSync } from 'node:fs';
import { join } from 'node:path';
import {
  LegacyGrantStore, ClientConfigStore, CachedClientConfigProvider,
  ProviderRegistry, GmailProvider, OAuthOrchestrator, PendingStateStore,
  LegacyBlobStore, CursorStore, IngestWorker, ProposalStore,
  ExtractionRunner, ExtractorRegistry, EmailExtractor, OpenRouterAdapter, AnthropicAdapter,
  OJT_SENDER_ALLOWLIST, OJT_SELF_FORWARD_ADDRESSES,
  makeRouteLegacy,
} from '@semantos/legacy-ingest';

const DEFAULT_REDIRECT_URI = 'http://localhost:3001/auth/callback';
const DATA_DIR = process.env.ODDJOBZ_LEGACY_DATA_DIR ?? '/var/lib/semantos/legacy';
const STORE_DIR = join(DATA_DIR, 'store');
const KEK_PATH = join(DATA_DIR, 'kek.bin');

const encName = (k: string) => Buffer.from(k, 'utf8').toString('base64url');
const decName = (f: string) => Buffer.from(f, 'base64url').toString('utf8');

// Durable GrantPersistence + PendingPersistence (read/write/delete/list/mtimeMs).
const persistence: any = {
  async read(k: string) { const p = join(STORE_DIR, encName(k)); return existsSync(p) ? new Uint8Array(readFileSync(p)) : null; },
  async write(k: string, v: Uint8Array) { mkdirSync(STORE_DIR, { recursive: true }); writeFileSync(join(STORE_DIR, encName(k)), Buffer.from(v)); },
  async delete(k: string) { const p = join(STORE_DIR, encName(k)); if (existsSync(p)) unlinkSync(p); },
  async list(prefix?: string) { mkdirSync(STORE_DIR, { recursive: true }); const all = readdirSync(STORE_DIR).map(decName); return prefix ? all.filter((k) => k.startsWith(prefix)) : all; },
  async mtimeMs(k: string) { const p = join(STORE_DIR, encName(k)); return existsSync(p) ? statSync(p).mtimeMs : null; },
};

async function loadOrCreateKek(): Promise<CryptoKey> {
  mkdirSync(DATA_DIR, { recursive: true });
  let raw: Uint8Array;
  if (existsSync(KEK_PATH)) raw = new Uint8Array(readFileSync(KEK_PATH));
  else { raw = crypto.getRandomValues(new Uint8Array(32)); writeFileSync(KEK_PATH, Buffer.from(raw), { mode: 0o600 }); }
  return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
}

async function main() {
  let input: { args?: string[]; flags?: Record<string, unknown> };
  try { input = JSON.parse(readFileSync('/dev/stdin', 'utf8')); }
  catch { process.stdout.write(JSON.stringify({ error: 'bad_stdin_json' })); return; }

  const kek = await loadOrCreateKek();
  const kekProvider = async () => kek;

  const grantStore = new LegacyGrantStore({ persistence, kekProvider });
  const clientConfigStore = new ClientConfigStore({ persistence, kekProvider });
  const cache = new CachedClientConfigProvider(clientConfigStore);
  await cache.reload();
  const pendingStore = new PendingStateStore({ persistence, kekProvider });

  const registry = new ProviderRegistry();
  registry.register(new GmailProvider());

  const orchestrator = new OAuthOrchestrator({
    store: grantStore, registry, configProvider: cache.get,
    defaultRedirectUri: DEFAULT_REDIRECT_URI, pendingStore,
  });

  // ── ingest pipeline (read side) ──
  // blob store = raw fetched messages; cursor store = per-provider checkpoint
  // (incremental dedup); worker = the backfill/continuous fetcher. The grant
  // resolver re-resolves before every page and refreshes an (almost-)expired
  // access token via the refresh token, persisting the renewed grant.
  const blobStore = new LegacyBlobStore({ persistence, kekProvider });
  const cursorStore = new CursorStore({ persistence });
  const proposalStore = new ProposalStore({ persistence, kekProvider });
  const worker = new IngestWorker({
    blobStore, cursorStore,
    grantResolver: async (providerId: string) => {
      const grants = await grantStore.listByProvider(providerId);
      let g = grants[0] ?? null;
      if (!g) return null;
      const exp = g.token?.expiresAt ?? 0;
      if (exp && exp < Date.now() + 60_000) {
        try { g = await orchestrator.refresh(g); await grantStore.put(g); } catch { /* fall through with stale token */ }
      }
      return g;
    },
  });

  // ── extraction (LLM side) ──
  // OpenRouter adapter keyed from env (OPENROUTER_API_KEY / OPENROUTER_MODEL).
  // EmailExtractor pre-filters cheaply before the LLM, so non-lead mail costs no
  // call. Extraction only writes PROPOSALS to the proposal store — minting cells
  // is the separate ratify step, so extraction never touches the substrate.
  // Pick the LLM backend from whichever key is in the env — Anthropic BYOK direct
  // (ANTHROPIC_API_KEY) preferred, else OpenRouter. Both constrain JSON output.
  // Bound every LLM/vision HTTP call — a single hung request (observed: a vision
  // call stuck in poll() forever, no timeout) otherwise stalls the whole
  // sequential backfill. AbortSignal.timeout makes it fail → the runner counts an
  // error and moves to the next item instead of hanging.
  const LLM_TIMEOUT_MS = Number(process.env.LEGACY_LLM_TIMEOUT_MS ?? 90_000);
  const fetchWithTimeout = ((input: any, init?: any) =>
    fetch(input, { ...(init ?? {}), signal: init?.signal ?? AbortSignal.timeout(LLM_TIMEOUT_MS) })) as typeof fetch;
  const llm = process.env.ANTHROPIC_API_KEY
    ? new AnthropicAdapter({
        apiKey: () => process.env.ANTHROPIC_API_KEY ?? null,
        extractionModel: process.env.ANTHROPIC_MODEL || undefined,
        // Vision-OCR of PDF work orders. Default to haiku for backfill throughput
        // (sonnet is minutes/call; bundles fan out per page). Override via env.
        visionModel: process.env.ANTHROPIC_VISION_MODEL || 'claude-haiku-4-5-20251001',
        fetch: fetchWithTimeout,
      })
    : new OpenRouterAdapter({ apiKey: () => process.env.OPENROUTER_API_KEY ?? null, extractionModel: process.env.OPENROUTER_MODEL || undefined, fetch: fetchWithTimeout });
  const extractorRegistry = new ExtractorRegistry();
  extractorRegistry.register(new EmailExtractor({
    acceptThreshold: 0.5,
    vision: llm,                                       // Anthropic does OCR of the PDF attachments
    senderAllowlist: OJT_SENDER_ALLOWLIST,             // Clever Property + Robert James Realty + self
    selfForwardAddresses: OJT_SELF_FORWARD_ADDRESSES,  // self-forwarded PDF bundles → bundle fan-out
  }));
  const extractionRunner = new ExtractionRunner({
    blobStore, proposalStore, registry: extractorRegistry, llm,
  });

  // export-proposals — dump pending Proposals as individual JSON files into the
  // BRAIN data dir's imports/ (where the LI-2 `ingest import_lead` resource reads
  // them), so the proven reingestProposal → entity.encode mint path can ratify
  // them into canonical owner-bound cells. Read-only on the legacy store; needs
  // no bearer (the minting bearer is the brain-spawned import_lead handler's).
  if (input.args?.[0] === 'export-proposals') {
    const ps = await proposalStore.list({ providerId: 'gmail', status: 'pending', limit: 10000 });
    const brainDataDir = process.env.BRAIN_DATA_DIR ?? '/var/lib/semantos';
    const dir = join(brainDataDir, 'imports');
    mkdirSync(dir, { recursive: true });
    const files: string[] = [];
    for (const p of ps) {
      const fname = `proposal-${(p as any).proposalId}.json`;
      writeFileSync(join(dir, fname), JSON.stringify(p));
      files.push(fname);
    }
    process.stdout.write(JSON.stringify({ ok: true, exported: files.length, dir, files }));
    return;
  }

  const routeLegacy = makeRouteLegacy({
    registry, store: grantStore, orchestrator,
    clientConfigStore, clientConfigCache: cache,
    blobStore, cursorStore, proposalStore, worker, extractionRunner,
    hatIdProvider: () => null, continuousHandles: new Map(),
  } as any);

  const result = await routeLegacy({ args: input.args ?? [], flags: input.flags ?? {} }, {});
  process.stdout.write(JSON.stringify(result));
}
main().then(() => process.exit(0), (e) => { process.stdout.write(JSON.stringify({ error: String(e) })); process.exit(0); });

```
