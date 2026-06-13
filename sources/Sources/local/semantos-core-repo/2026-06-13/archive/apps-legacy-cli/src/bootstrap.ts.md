---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/bootstrap.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.699405+00:00
---

# archive/apps-legacy-cli/src/bootstrap.ts

```ts
/**
 * Bootstrap — constructs every legacy-ingest singleton the verb
 * dispatcher needs and returns a fully-wired LegacyVerbContext.
 *
 * Reference: V1.0 plan §5; docs/design/WALLET-LEGACY-INGEST.md §3.
 *
 * What's wired:
 *   - FsPersistence  — disk under <root>
 *   - KekProvider    — passphrase-derived (Phase 2 swaps for brain broker)
 *   - Audit sink     — JSON-line append to <root>/audit.log
 *   - Stores         — grant / blob / cursor / proposal / receipt /
 *                      correction / client-config
 *   - Cache          — CachedClientConfigProvider for sync configProvider
 *   - Registry       — GmailProvider registered (Meta / WhatsApp / G-Cal /
 *                      Xero deferred to LI6)
 *   - OAuthOrchestrator + RefreshWorker
 *   - IngestWorker
 *   - RatificationOrchestrator
 *   - LegacyVerbContext   — what `routeLegacy` consumes
 */

import {
  LegacyGrantStore,
  LegacyBlobStore,
  CursorStore,
  ProposalStore,
  ClientConfigStore,
  CachedClientConfigProvider,
  ReceiptStore,
  CorrectionEdgeStore,
  OAuthOrchestrator,
  PendingStateStore,
  ProviderRegistry,
  IngestWorker,
  RefreshWorker,
  RatificationOrchestrator,
  GmailProvider,
  MetaProvider,
  EmailExtractor,
  OJT_SENDER_ALLOWLIST,
  OJT_SELF_FORWARD_ADDRESSES,
  ExtractionRunner,
  ExtractorRegistry,
  ReingestReceiptStore,
  FsAttachmentBlobStore,
  WssEncodeDispatcher,
  OpenRouterAdapter,
  OllamaAdapter,
  AnthropicAdapter,
  LlmRouter,
  BrainRpcCellWriter,
  JsonlConversationTurnPatchSink,
  JsonlConversationDispatchDecisionSink,
  ConversationDispatchRouter,
  OddjobzConversationGraphResolver,
  setAuditSink,
  type LegacyVerbContext,
  type LegacyGrant,
  type LLMAdapter,
  type PendingPersistence,
  type ProviderId,
} from '@semantos/legacy-ingest';
import { rawItemToOddjobzMessagePatch } from '@semantos/legacy-ingest';
import { FsPersistence } from './fs-persistence';
import { unlockedKek, unlockWithPassphrase } from './kek-from-passphrase';
import { defaultAuditSink } from './audit-sink';
import { makeMetaFanOutSink } from './meta-fanout-sink';
import { getDatabaseOrNull, makeOddjobzSinks } from '@semantos/oddjobz/conversation/db';
import { mapMessagePatchToCanonical } from '@semantos/oddjobz/conversation/legacy-ingest-bridge';
import type { ConversationTurnSink } from '@semantos/legacy-ingest';
import type { RawItem } from '@semantos/legacy-ingest';
import {
  existsSync,
  readFileSync,
  writeFileSync,
  unlinkSync,
  mkdirSync,
  readdirSync,
  statSync,
  chmodSync,
} from 'node:fs';
import { join } from 'node:path';

export interface BootstrapOpts {
  /** Root directory for all legacy-ingest state. Defaults to ~/.semantos. */
  root?: string;
  /**
   * Pre-resolved passphrase for non-interactive bootstrap (tests +
   * SEMANTOS_LEGACY_PASSPHRASE env-var path). When unset, the CLI
   * prompts on the TTY at first KEK access.
   */
  passphrase?: string;
  /**
   * Hat id getter — populates audit attribution on register-client +
   * ratification + grant. Phase 2 sources this from the Semantos Brain broker.
   */
  hatIdProvider?: () => string | null;
  /**
   * Optional editor hook for `legacy correct`. Phase 1 default opens
   * $EDITOR with the proposal serialised; tests inject a stub.
   */
  openCorrectionEditor?: LegacyVerbContext['openCorrectionEditor'];
  /**
   * Optional browser opener for `legacy connect`. Phase 1 default
   * prints the URL and lets the operator open it. Bun-on-VPS scenario
   * has no browser; the operator copies the URL to a phone or laptop.
   */
  openBrowser?: LegacyVerbContext['openBrowser'];
}

export interface BootstrappedCli {
  ctx: LegacyVerbContext;
  /**
   * D-OJ-conv-meta-inbox-bridge — fan-out `ConversationTurnSink` for the
   * meta webhook server.
   *
   * Calls the legacy `JsonlConversationTurnPatchSink.append` for ALL events
   * (every provider) PLUS the canonical `makeCanonicalTurnSink` for META
   * events only (`event.providerId === 'meta'`).
   *
   * Widget events (`providerId === 'widget'`) are excluded from the canonical
   * side: the cartridge `intake-handler.ts` already owns canonical widget turns
   * (#555), so wiring widget here too would DOUBLE-WRITE.
   *
   * When `DATABASE_URL` is unset (`getDatabaseOrNull()` returns null), the
   * canonical side is a no-op — legacy path is unaffected. This makes the
   * wiring safe to deploy before the DB is provisioned.
   *
   * Pass this as `onConversationTurn` when constructing `MetaWebhookServer`.
   */
  readonly metaFanOutSink: ConversationTurnSink;
  /** Call once before the CLI exits to flush any deferred state. */
  shutdown(): Promise<void>;
}

export async function bootstrap(opts: BootstrapOpts = {}): Promise<BootstrappedCli> {
  const root = opts.root ?? defaultRoot();

  // Audit sink — wire before any other component so the bootstrap
  // events themselves get logged.
  setAuditSink(defaultAuditSink(root));

  // Persistence + KEK provider.
  const persistence = new FsPersistence({ root });
  const kekProvider = async () => {
    if (opts.passphrase !== undefined) {
      return unlockWithPassphrase(opts.passphrase);
    }
    return unlockedKek();
  };

  // Stores.
  const store = new LegacyGrantStore({ persistence, kekProvider });
  const blobStore = new LegacyBlobStore({ persistence, kekProvider });
  const cursorStore = new CursorStore({ persistence });
  const proposalStore = new ProposalStore({ persistence, kekProvider });
  const receiptStore = new ReceiptStore({ persistence, kekProvider });
  const correctionStore = new CorrectionEdgeStore({ persistence, kekProvider });
  // D-RTC.6 follow-up — reingest receipts (separate prefix from
  // the legacy ratification receipts; both encrypted under the same
  // KEK). The reingest verb writes here when minting fresh typed
  // cells; re-runs check this store first for O(1) skip.
  const reingestReceiptStore = new ReingestReceiptStore({
    persistence,
    kekProvider,
  });
  const clientConfigStore = new ClientConfigStore({ persistence, kekProvider });
  const clientConfigCache = new CachedClientConfigProvider(clientConfigStore);
  const graphResolver = new OddjobzConversationGraphResolver({ root });
  const dispatchRouter = new ConversationDispatchRouter({
    resolveCandidates: graphResolver.resolve,
  });
  const dispatchDecisionSink = new JsonlConversationDispatchDecisionSink({
    root,
    router: dispatchRouter,
  });
  const messagePatchSink = new JsonlConversationTurnPatchSink({
    root,
    onPatch: dispatchDecisionSink.append,
  });
  // Pre-warm the cache so the orchestrator's sync configProvider sees
  // any previously-registered credentials on the first verb call.
  await clientConfigCache.reload();

  // Provider registry — Gmail + Meta Business Suite. Meta supports both
  // webhook tail and historical conversation backfill when an asset id is
  // supplied via grant extras or `legacy ingest meta --query`.
  const registry = new ProviderRegistry();
  registry.register(new GmailProvider());
  registry.register(new MetaProvider({
    verifyToken: process.env.META_WEBHOOK_VERIFY_TOKEN ?? '',
  }));

  // Disk-backed pending-state store. Without this the legacy-cli's
  // one-shot verb invocations lose pending state between `legacy
  // connect` and `legacy resume` (each invocation is a fresh bun
  // process). Encrypted under the same KEK as LegacyGrantStore — the
  // pending state contains the PKCE verifier + redirect URI, which
  // both deserve at-rest protection. Files live at
  // `<root>/legacy-pending/<nonce>.json` and are TTL-swept on every
  // prepare / exchange.
  const pendingStore = new PendingStateStore({
    persistence: new FsPendingPersistence({
      dir: join(root, 'legacy-pending'),
    }),
    kekProvider,
  });

  // OAuth orchestrator — uses the cache's sync get as configProvider.
  const orchestrator = new OAuthOrchestrator({
    registry,
    store,
    configProvider: clientConfigCache.get,
    hatIdProvider: opts.hatIdProvider,
    pendingStore,
  });

  // Ingest worker — re-resolves the grant before every page so a
  // background refresh takes effect transparently. The legacy-cli is
  // a one-shot process per verb, so the RefreshWorker timer doesn't
  // get a chance to run on short commands. We auto-refresh on-demand
  // here when the access token has expired (or is within 60s of
  // expiry) so `legacy ingest` doesn't 401 the operator just because
  // they ran their last verb >1h ago. If the refresh itself fails,
  // we surface the original grant and let the provider call return
  // its 401 — same behaviour as before.
  const TOKEN_REFRESH_LEAD_MS = 60_000;
  const grantResolver = async (providerId: ProviderId): Promise<LegacyGrant | null> => {
    const grants = await store.listByProvider(providerId);
    const grant = grants[0];
    if (!grant) return null;
    const now = Date.now();
    const expiresInMs = grant.token.expiresAt - now;
    if (expiresInMs > TOKEN_REFRESH_LEAD_MS) return grant;
    if (!grant.token.refreshToken) {
      // No refresh token — operator must re-do `legacy connect`.
      // Return the (probably-expired) grant; the provider call will
      // 401 with a useful message.
      return grant;
    }
    try {
      return await orchestrator.refresh(grant);
    } catch {
      // Refresh failed — propagate the stale grant; the 401 from the
      // provider is more actionable than masking the real failure.
      return grant;
    }
  };
  // D-OJ-conv-gmail-canonical-bridge — email canonical fan-out.
  //
  // `getDatabaseOrNull()` reads `DATABASE_URL` at construction time.  When
  // unset (dev / pre-provisioning), `emailCanonicalDb === null` and the
  // canonical side is a no-op — the legacy JSONL path (`appendRawItem`) is
  // fully unaffected.
  //
  // For every Gmail item that `appendRawItem` persists we ALSO attempt to
  // write a canonical `oddjobz.conversation.turn` sem_objects row, but ONLY
  // when:
  //   1. DATABASE_URL is set (emailCanonicalDb is non-null)
  //   2. The patch has an email channel ('email' or 'gmail')
  //   3. `mapMessagePatchToCanonical` returns non-null (text is non-blank)
  //
  // The canonical path is BEST-EFFORT + ISOLATED: failures are swallowed so
  // they NEVER block the legacy JSONL write.  The JSONL is the authoritative
  // durable log; sem_objects rows are additive.
  //
  // No self-call deadlock: `makeOddjobzSinks(db).semObjectSink` writes to
  // Postgres directly — it does NOT call back into the brain's HTTP/REPL.
  const emailCanonicalDb = getDatabaseOrNull();
  const emailCanonicalSinks = emailCanonicalDb ? makeOddjobzSinks(emailCanonicalDb) : null;

  const onItemPersisted = async (item: RawItem): Promise<void> => {
    // 1. Legacy JSONL path — always fires.
    messagePatchSink.appendRawItem(item);

    // 2. Canonical email path — best-effort, isolated.
    if (!emailCanonicalSinks) return;

    try {
      const patch = rawItemToOddjobzMessagePatch(item);
      if (!patch) return;

      // Only handle email channels in this fan-out; Meta has its own
      // `metaFanOutSink` driven by the webhook path.
      if (patch.channel !== 'email' && patch.channel !== 'gmail') return;

      const turn = mapMessagePatchToCanonical(patch);
      if (!turn) return;

      await emailCanonicalSinks.semObjectSink(turn);
    } catch {
      // Best-effort: swallow all failures. Legacy JSONL already landed.
    }
  };

  const worker = new IngestWorker({
    blobStore,
    cursorStore,
    grantResolver,
    onItemPersisted,
  });

  // Refresh worker — scans every minute, refreshes within 5 min of expiry.
  const refresh = new RefreshWorker({
    store,
    orchestrator,
    providers: registry.list().map(p => p.id),
  });
  refresh.start();

  // D-DOG.1.0 + D-DOG.1d — extractor stack.
  //
  // The legacy CLI is the canonical bootstrap host that drives Gmail
  // backfill end-to-end. Without an LLM adapter wired here, `legacy
  // ingest` only fetches raw blobs and `runtime/legacy-ingest`'s
  // extractor framework is dead code from the operator's perspective.
  //
  // D-DOG.1d swaps the single OpenRouterAdapter for an LlmRouter that
  // composes the three concrete adapters and dispatches per-call:
  //   • Local Ollama (free, sovereign) for the bulk of shell ops.
  //   • BYOK Anthropic (Claude direct) for vision + high-stakes calls.
  //   • OpenRouter as a fallback / legacy path.
  //
  // Each adapter is wired only if its env var is present:
  //   • OLLAMA_BASE_URL or OLLAMA_ENABLE=1 → OllamaAdapter
  //   • ANTHROPIC_API_KEY                  → AnthropicAdapter
  //   • OPENROUTER_API_KEY                 → OpenRouterAdapter
  //
  // The router's default preference list is ["ollama","anthropic",
  // "openrouter"] for extraction and ["anthropic","openrouter"] for
  // vision; missing adapters in the default list are silently skipped.
  //
  // If NO backend is configured we log a clear warning and leave the
  // extractor stack disabled — `legacy ingest` will still fetch blobs
  // (so credentials + cursor state stay current) and the verb's
  // `extract.skipped` field tells the operator why. Existing tests
  // depend on this null-llm behaviour to bootstrap cleanly without
  // any env vars set.
  const llm: LLMAdapter | null = (() => {
    const ollamaConfigured =
      (process.env.OLLAMA_BASE_URL && process.env.OLLAMA_BASE_URL.length > 0) ||
      process.env.OLLAMA_ENABLE === '1';
    const anthropicKey = process.env.ANTHROPIC_API_KEY;
    const anthropicConfigured = !!anthropicKey && anthropicKey.length > 0;
    const openrouterKey = process.env.OPENROUTER_API_KEY;
    const openrouterConfigured = !!openrouterKey && openrouterKey.length > 0;

    if (!ollamaConfigured && !anthropicConfigured && !openrouterConfigured) {
      // eslint-disable-next-line no-console
      console.warn(
        'legacy-cli: No LLM backend configured. Set OLLAMA_BASE_URL (or OLLAMA_ENABLE=1) for local Llama, ' +
          'ANTHROPIC_API_KEY for BYOK Claude, or OPENROUTER_API_KEY for hosted fallback. ' +
          '`legacy ingest` will fetch blobs but skip extraction until at least one is set.',
      );
      return null;
    }

    return new LlmRouter({
      adapters: {
        ollama: ollamaConfigured
          ? new OllamaAdapter({
              baseUrl: process.env.OLLAMA_BASE_URL || undefined,
              model: process.env.OLLAMA_MODEL || undefined,
            })
          : null,
        anthropic: anthropicConfigured
          ? new AnthropicAdapter({
              apiKey: () => process.env.ANTHROPIC_API_KEY ?? null,
            })
          : null,
        openrouter: openrouterConfigured
          ? new OpenRouterAdapter({
              apiKey: () => process.env.OPENROUTER_API_KEY ?? null,
            })
          : null,
      },
      // Defaults are correct for the operator's preferences:
      //   extraction: ollama → anthropic → openrouter
      //   vision:     anthropic → openrouter (ollama can't do vision)
    });
  })();

  let extractionRunner: ExtractionRunner | undefined;
  if (llm) {
    const extractorRegistry = new ExtractorRegistry();
    // The router implements both LLMAdapter and VisionAdapter, so the
    // EmailExtractor's vision OCR pass is automatically routed to
    // Anthropic (or OpenRouter as fallback) when an attachment is
    // encountered. Ollama is intentionally skipped for vision — local
    // 3B models can't reliably transcribe documents.
    const visionAdapter = llm instanceof LlmRouter ? llm : undefined;
    // D-RTC.7-followup — opt-in OJT sender allowlist. Set
    // `LEGACY_INGEST_SENDER_ALLOWLIST=ojt` to filter the gmail corpus
    // down to Clever Property / Robert James Realty / Todd's gmail
    // (operator-self-forward bundles). Anything else gets dropped at
    // the pre-classifier with reason "sender not in allowlist". Off by
    // default to preserve generic-operator behaviour.
    const allowlistMode = process.env.LEGACY_INGEST_SENDER_ALLOWLIST;
    const emailExtractorOpts: ConstructorParameters<typeof EmailExtractor>[0] = {
      vision: visionAdapter,
    };
    if (allowlistMode === 'ojt') {
      emailExtractorOpts.senderAllowlist = OJT_SENDER_ALLOWLIST;
      emailExtractorOpts.selfForwardAddresses = OJT_SELF_FORWARD_ADDRESSES;
    }
    extractorRegistry.register(new EmailExtractor(emailExtractorOpts));
    extractionRunner = new ExtractionRunner({
      blobStore,
      proposalStore,
      registry: extractorRegistry,
      llm,
    });
  }

  // D-DOG.1.0b' — Layer-2 ratify seam.
  //
  // The brain-side `oddjobz.ratify_proposal` JSON-RPC verb takes a
  // SIRProgram + proposal_id, walks the SIR nodes, and routes each one
  // through the existing typed dispatcher commands (jobs.create /
  // customers.create / quotes.create / etc.) — the same commands the
  // helm + REPL drive operator-driven writes through. Trust level
  // matches every existing oddjobz operator-driven write; K1–K10
  // cryptographic cell-DAG promotion is captured as D-DOG.1.0c
  // (post-dogfood — needs a Semantos Brain-side hat key vault that doesn't exist
  // yet). See docs/prd/DOGFOOD-READINESS-MATRIX.md Phase 1.0 for the
  // full re-scope rationale.
  //
  // For Phase 1.0 transport we open a fresh WSS connection per ratify
  // (simple, slow). Phase 1.A or later can pool connections.
  //
  // Default WSS URL: `/api/v1/wallet` matches what `brain serve` exposes
  // (see runtime/semantos-brain/src/cli.zig — `WSS wallet: GET /api/v1/wallet`).
  // The earlier `/wallet` default was wrong and 404'd the upgrade
  // handshake.
  //
  // FS fallback: `brain serve <domain>` (basic mode) returns 503 for
  // `/api/v1/wallet` when no tenant manifest is wired — that's a
  // multi-hour scaffolding effort we're deferring past tonight's
  // dogfood. The fallback writes JSONL directly into the same on-disk
  // shape brain's dispatcher → JobsStore path produces, so the helm /
  // mobile views see ratified cells either way. Once tenant-manifest
  // scaffolding ships the WSS path becomes the default and the
  // fallback's `console.warn` makes any silent regression visible.
  const wsRpcUrl = process.env.BRAIN_WSS_URL ?? 'ws://localhost:8424/api/v1/wallet';
  const fsFallbackDataDir = process.env.BRAIN_DATA_DIR ?? join(root, 'data');
  const fsFallbackHatId = process.env.SEMANTOS_HAT_ID ?? opts.hatIdProvider?.() ?? null;
  const cellWriter = new BrainRpcCellWriter({
    wsRpcUrl,
    fsFallbackDataDir,
    fsFallbackHatId,
  });

  // Ratification orchestrator — `writeCell` POSTs the SIRProgram to
  // the Semantos Brain-side `oddjobz.ratify_proposal` RPC; the inserted record
  // ids come back as `cell_ids` and we plumb them through the
  // RatificationReceipt's `cellId` field as a JSON-encoded array (the
  // existing receipt schema carries a single string; encoding the
  // array preserves multi-cell ratifications without a schema bump).
  const ratification = new RatificationOrchestrator({
    proposalStore,
    receiptStore,
    correctionStore,
    hatProvider: () => {
      const hatId = opts.hatIdProvider?.() ?? null;
      return hatId ? { hatId, certId: null } : null;
    },
    writeCell: ({ program, proposal }) =>
      cellWriter.write({ program, proposal }),
  });

  const continuousHandles = new Map<string, () => void>();

  // D-Reingest-Typed-Cells dry-run deps. The dry-run path doesn't
  // mint cells brain-side — it only counts what WOULD be minted —
  // so we wire stub dependencies sufficient for the dry-run shape:
  //   • sitesView: returns null for every key → every site appears
  //     as "minted" in the projected counts (an upper-bound proxy).
  //   • attachmentBlobStore: in-memory map; bytes are persisted only
  //     for the lifetime of the verb call, then dropped on shutdown.
  //   • encodeDispatcher: omitted — the verb's --dry-run path uses
  //     its own counting stub regardless of what's wired here.
  // Real-run wiring (real SitesView + persistent blob store + real
  // encodeDispatcher into brain `entity.encode` verb) lands when
  // the brain serve flow + tenant-manifest scaffolding ship.
  const reingestSitesView = {
    async findByLookupKey(_k: string): Promise<string | null> {
      return null;
    },
  };
  // Persistent, content-addressed: writes `<dir>/<sha>.bin` (the brain
  // attachment_blobs_fs layout). After a re-mint this dir rsyncs into
  // rbs `/var/lib/semantos/oddjobz/blobs/` and the job-sheet PDFs +
  // photos become reachable via GET /api/v1/attachments/<id>/blob.
  // Absolute path under the legacy-ingest root (never a stale
  // .semantos/data path); ATTACHMENT_BLOB_DIR overrides.
  const reingestAttachmentBlobStore = new FsAttachmentBlobStore(
    process.env.ATTACHMENT_BLOB_DIR ?? join(root, 'attachment-blobs'),
  );

  const ctx: LegacyVerbContext = {
    registry,
    store,
    orchestrator,
    blobStore,
    cursorStore,
    worker,
    continuousHandles,
    clientConfigStore,
    clientConfigCache,
    hatIdProvider: opts.hatIdProvider,
    proposalStore,
    receiptStore,
    ratification,
    extractionRunner,
    // D-Reingest-Typed-Cells deps.
    reingestReceiptStore,
    sitesView: reingestSitesView,
    attachmentBlobStore: reingestAttachmentBlobStore,
    // D-RTC.4-followup — WSS dispatcher into brain's `verb.dispatch
    // substrate entity.encode` walker. Uses the same WSS URL the
    // legacy ratify path uses (BRAIN_WSS_URL env override; default
    // ws://localhost:8424/api/v1/wallet but operator typically points
    // it at ws://<host>:8080/api/v1/wallet — see README runbook).
    encodeDispatcher: new WssEncodeDispatcher({
      wsRpcUrl: wsRpcUrl,
      // The prod brain's /api/v1/wallet WSS upgrade is bearer-gated
      // (single-operator mode). Pass the operator bearer so the
      // upgrade returns 101 instead of being refused — without this
      // `legacy reingest` can never reach a live brain. Use the same
      // boot-snapshot token the brain recognises (systemd
      // ODDJOBZ_BRAIN_BEARER). Falls back to BRAIN_BEARER for parity
      // with other tools.
      bearerToken:
        process.env.BRAIN_WSS_BEARER ??
        process.env.ODDJOBZ_BRAIN_BEARER ??
        process.env.BRAIN_BEARER ??
        undefined,
    }),
    // D-DOG.1.0c Phase 5 G.1 — `legacy migrate-to-graph` reads
    // `<brainDataDir>/oddjobz/jobs.jsonl` and writes the sidecar
    // `legacy-unsigned.jsonl` marker. Use the same dir the cell-writer
    // FS-fallback path resolves so a host that drives both verbs
    // through this CLI sees one consistent on-disk view.
    brainDataDir: fsFallbackDataDir,
    openCorrectionEditor: opts.openCorrectionEditor,
    openBrowser: opts.openBrowser,
  };

  // D-OJ-conv-meta-inbox-bridge — canonical meta fan-out sink.
  //
  // `getDatabaseOrNull()` reads `DATABASE_URL` at construction time. When
  // unset (dev / pre-provisioning), `db === null` and the canonical side is
  // a no-op — the legacy JSONL path is fully unaffected.
  //
  // The fan-out fires meta canonical turns ONLY for `event.providerId === 'meta'`
  // (channels: meta_messenger / meta_instagram). Widget events are excluded —
  // the cartridge intake-handler.ts already owns canonical widget turns (#555).
  //
  // Pass `metaFanOutSink` as `onConversationTurn` when constructing
  // `MetaWebhookServer` in a `legacy serve` or standalone webhook process.
  const metaCanonicalDb = getDatabaseOrNull();
  const metaFanOutSink = makeMetaFanOutSink({
    legacySink: (event) => messagePatchSink.append(event),
    db: metaCanonicalDb,
  });

  return {
    ctx,
    metaFanOutSink,
    async shutdown() {
      refresh.stop();
      for (const stop of continuousHandles.values()) stop();
      continuousHandles.clear();
    },
  };
}

function defaultRoot(): string {
  const home = process.env.HOME ?? process.env.USERPROFILE;
  if (!home) throw new Error('legacy-cli: cannot determine HOME; pass --root explicitly');
  return `${home}/.semantos`;
}

/**
 * Filesystem `PendingPersistence` for the disk-backed PendingStateStore.
 *
 * Layout: a single flat directory of `<nonce>.json` files (the `.json`
 * suffix is purely conventional — bytes on disk are AES-GCM-encrypted
 * via the store's envelope). Files are written 0600 to match the
 * grant-store's at-rest posture.
 *
 * Kept inline rather than in its own file because (a) it's small and
 * mirrors the one-off responsibilities of FsPersistence, and (b) the
 * pending-state file layout is intentionally distinct from the
 * `legacy-grants/<provider>/<grant-id>.enc` layout (no provider
 * subdirectories — pending entries are short-lived and provider-id is
 * encoded inside the encrypted body).
 */
class FsPendingPersistence implements PendingPersistence {
  private readonly dir: string;

  constructor(opts: { dir: string }) {
    this.dir = opts.dir;
    ensurePendingDir(this.dir);
  }

  async read(key: string): Promise<Uint8Array | null> {
    const path = join(this.dir, key);
    if (!existsSync(path)) return null;
    return new Uint8Array(readFileSync(path));
  }

  async write(key: string, data: Uint8Array): Promise<void> {
    ensurePendingDir(this.dir);
    const path = join(this.dir, key);
    writeFileSync(path, data, { mode: 0o600 });
    chmodSync(path, 0o600);
  }

  async delete(key: string): Promise<void> {
    const path = join(this.dir, key);
    if (existsSync(path)) unlinkSync(path);
  }

  async list(): Promise<string[]> {
    if (!existsSync(this.dir)) return [];
    return readdirSync(this.dir, { withFileTypes: true })
      .filter((e) => e.isFile())
      .map((e) => e.name);
  }

  async mtimeMs(key: string): Promise<number | null> {
    const path = join(this.dir, key);
    if (!existsSync(path)) return null;
    return statSync(path).mtimeMs;
  }
}

function ensurePendingDir(dir: string): void {
  if (existsSync(dir)) return;
  mkdirSync(dir, { recursive: true, mode: 0o700 });
}

```
