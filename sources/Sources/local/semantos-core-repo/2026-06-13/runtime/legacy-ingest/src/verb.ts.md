---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/verb.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.135381+00:00
---

# runtime/legacy-ingest/src/verb.ts

```ts
/**
 * `legacy` REPL verb.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI1 + LI2 + LI4.
 *
 * Subcommands:
 *   - legacy register-client <provider>    — store this provider's OAuth client credentials
 *   - legacy unregister-client <provider>  — remove the stored credentials
 *   - legacy clients                       — list registered providers (no secrets shown)
 *   - legacy connect <provider>            — start an OAuth grant flow
 *   - legacy resume <state> <code>         — complete the OAuth grant after callback
 *   - legacy disconnect <provider>         — revoke + delete grants
 *   - legacy status [<provider>]           — list grants, expiries, ingest progress, queue
 *   - legacy providers                     — list registered providers
 *   - legacy ingest <provider> [--since <iso>] [--max-pages <n>] [--query <q>] [--no-extract] [--reextract]   (LI2)
 *   - legacy extract <provider> [--force]                          (LI2)
 *   - legacy auto <provider> [--interval <s>]                      (LI2)
 *   - legacy stop <provider>                                       (LI2)
 *   - legacy review [--provider <id>] [--confidence <op><n>] [--limit <n>]   (LI4)
 *   - legacy ratify <provider>:<proposal-id>                       (LI4)
 *   - legacy reject <provider>:<proposal-id> --reason <text>       (LI4)
 *   - legacy correct <provider>:<proposal-id>                      (LI4)
 *   - legacy bulk-ratify [--provider <id>] --confidence <op><n> [--dry-run]  (LI4)
 *   - legacy unratify <provider>:<receipt-id>                      (LI4)
 *
 * Wired by the host via `registerVerb('legacy', routeLegacy)` once the
 * orchestrator + store + worker + ratification have been initialised.
 */

import type { LegacyGrant, ProviderId } from './types';
import { LegacyGrantStore } from './grant-store';
import { OAuthOrchestrator, ProviderRegistry } from './oauth';
import type { LegacyBlobStore } from './blob-store';
import type { CursorStore } from './cursor-store';
import type { IngestWorker } from './ingest-worker';
import type { ProposalStore } from './proposal-store';
import type { Proposal } from './extractor/types';
import type { ExtractionRunner, ExtractionRunSummary } from './extractor/runner';
import type { RatificationOrchestrator } from './ratification/orchestrator';
import type { ReceiptStore } from './ratification/store';
import type { SIRProgram } from '@semantos/semantos-sir';
import type { SitesView } from './site-dedupe';
import type { AttachmentBlobStore } from './attachment-pipeline';
import {
  reingestProposal,
  type EncodeDispatcher,
  type ReingestOutcome,
} from './reingest-worker';
import type { ReingestReceiptStore } from './reingest-receipt-store';
import { parseEmailMimeParts } from './extractor/attachment';
import { parseRfc822 } from './extractor/email';
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
} from 'node:fs';
import { dirname, join } from 'node:path';
import type {
  ClientConfigStore,
  CachedClientConfigProvider,
  StoredClientConfig,
} from './client-config-store';

export interface LegacyVerbContext {
  registry: ProviderRegistry;
  store: LegacyGrantStore;
  orchestrator: OAuthOrchestrator;
  /**
   * LI2 dependencies — optional so LI1 hosts that haven't enabled
   * ingest yet can still wire the verb.
   */
  blobStore?: LegacyBlobStore;
  cursorStore?: CursorStore;
  worker?: IngestWorker;
  /**
   * Continuous-mode handles by `${providerId}:${grantId}`. Populated
   * by `legacy auto`; consumed by `legacy stop`.
   */
  continuousHandles?: Map<string, () => void>;
  /**
   * Client-config store + sync cache — operator-supplied OAuth credentials
   * per provider. The orchestrator's `configProvider` reads from the cache;
   * `register-client` writes to the store and refreshes the cache.
   */
  clientConfigStore?: ClientConfigStore;
  clientConfigCache?: CachedClientConfigProvider;
  /**
   * Returns the active hat for audit attribution on register-client.
   * Optional; tests can omit and credentials get hatId: null.
   */
  hatIdProvider?: () => string | null;
  /**
   * LI4 dependencies — optional so LI1+LI2 hosts without ratification
   * wired can still use the verb.
   */
  proposalStore?: ProposalStore;
  receiptStore?: ReceiptStore;
  ratification?: RatificationOrchestrator;
  /**
   * D-DOG.1.0c Phase 5 G.1 — brain data root used by `legacy
   * migrate-to-graph` to read the operator's existing flat
   * `jobs.jsonl` rows from `<dataDir>/oddjobz/jobs.jsonl` and to
   * write the `legacy-unsigned.jsonl` marker for un-matchable rows.
   * Defaults are wired by the host (`apps/legacy-cli/src/bootstrap.ts`
   * resolves to `BRAIN_DATA_DIR` or `<root>/data`); tests pin a temp
   * directory so they don't touch the operator's real data tree.
   */
  brainDataDir?: string;
  /**
   * D-DOG.1.0 — extraction runner. When wired, `legacy ingest` chains
   * `ExtractionRunner.runForProvider` onto the tail of `IngestWorker.backfill`
   * so a single command yields blobs → proposals in one shot. The
   * `--no-extract` flag short-circuits the chain for the rare blob-only
   * case (e.g. operator wants to inspect raw fetches before running an
   * LLM-cost-bearing extractor pass).
   */
  extractionRunner?: ExtractionRunner;
  /**
   * Editor hook for `legacy correct`. Host opens an editor with the
   * proposal's SIRProgram serialised; operator saves; host returns
   * the parsed corrected SIRProgram (or null on cancel).
   */
  openCorrectionEditor?: (proposal: Proposal) => Promise<SIRProgram | null>;
  /**
   * D-RTC.6 / D-RTC.7 — reingest worker dependencies. All four are
   * required to run `legacy reingest`; if any is missing the verb
   * returns a clean "not wired" error so the host can surface a
   * setup hint to the operator.
   */
  sitesView?: SitesView;
  attachmentBlobStore?: AttachmentBlobStore;
  encodeDispatcher?: EncodeDispatcher;
  /**
   * D-RTC.6 follow-up — when wired, `legacy reingest` becomes
   * idempotent: re-running on the same proposals skips O(1) via
   * `receiptStore.has(providerId, proposalId)`. When absent the
   * verb keeps the previous (non-idempotent) behaviour.
   */
  reingestReceiptStore?: ReingestReceiptStore;
  /** Operator hat id (first 16 bytes as 32-hex). Used for cell ownership. */
  ownerIdHex?: string;
  /**
   * In TUI / phone flows the host opens a browser to this URL so the
   * operator can complete the OAuth dance. Test contexts pass a stub.
   */
  openBrowser?: (url: string) => void | Promise<void>;
}

interface VerbCommand {
  flags?: Record<string, unknown>;
  args?: string[];
  positional?: string[];
}

export function makeRouteLegacy(ctx: LegacyVerbContext) {
  return async function routeLegacy(cmdRaw: unknown, _execCtx: unknown): Promise<unknown> {
    const cmd = (cmdRaw ?? {}) as VerbCommand;
    const args = cmd.positional ?? cmd.args ?? [];
    const flags = cmd.flags ?? {};
    const sub = args[0];
    switch (sub) {
      case 'connect':           return doConnect(ctx, args[1]);
      case 'resume':            return doResume(ctx, args[1], args[2]);
      case 'disconnect':        return doDisconnect(ctx, args[1]);
      case 'status':            return doStatus(ctx, args[1]);
      case 'providers':         return doProviders(ctx);
      case 'register-client':   return doRegisterClient(ctx, args[1], flags);
      case 'unregister-client': return doUnregisterClient(ctx, args[1]);
      case 'clients':           return doListClients(ctx);
      case 'ingest':            return doIngest(ctx, args[1], flags);
      case 'extract':           return doExtract(ctx, args[1], flags);
      case 'auto':              return doAuto(ctx, args[1], flags);
      case 'stop':              return doStop(ctx, args[1]);
      case 'review':            return doReview(ctx, flags);
      case 'ratify':            return doRatify(ctx, args[1]);
      case 'reject':            return doReject(ctx, args[1], flags);
      case 'correct':           return doCorrect(ctx, args[1]);
      case 'bulk-ratify':       return doBulkRatify(ctx, flags);
      case 'unratify':          return doUnratify(ctx, args[1]);
      case 'migrate-to-graph':  return doMigrateToGraph(ctx, flags);
      case 'reingest':          return doReingest(ctx, args[1], flags);
      case undefined:
      case 'help':
      default:              return helpText();
    }
  };
}

async function doConnect(ctx: LegacyVerbContext, providerId: string | undefined): Promise<unknown> {
  if (!providerId) return { error: 'Usage: legacy connect <provider>' };
  if (!ctx.registry.get(providerId)) {
    return { error: `unknown provider '${providerId}'` };
  }
  let prepared;
  try {
    prepared = await ctx.orchestrator.prepareGrant(providerId);
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }
  if (ctx.openBrowser) {
    await ctx.openBrowser(prepared.authorizeUrl);
  }
  return {
    ok: true,
    providerId,
    authorizeUrl: prepared.authorizeUrl,
    stateNonce: prepared.stateNonce,
    instructions: ctx.openBrowser
      ? 'A browser window has been opened to complete the OAuth grant.'
      : `Open this URL on your phone or laptop to grant access:\n  ${prepared.authorizeUrl}`,
  };
}

/**
 * Complete an OAuth grant after the operator pastes the (state, code)
 * pair from the callback page (`/auth/callback?purpose=oauth_grant&...`
 * served by the temporary Next.js placeholder per V1.0 plan §5).
 *
 * The orchestrator verifies the state nonce against its in-memory
 * pending map (10-minute TTL), exchanges the code with the provider,
 * encrypts the resulting token under the wallet KEK, and persists it.
 */
async function doResume(
  ctx: LegacyVerbContext,
  state: string | undefined,
  code: string | undefined,
): Promise<unknown> {
  if (!state || !code) {
    return { error: 'Usage: legacy resume <state> <code>' };
  }
  try {
    const grant = await ctx.orchestrator.handleCallback({ state, code });
    return {
      ok: true,
      providerId: grant.providerId,
      grantId: grant.grantId,
      accountLabel: grant.accountLabel,
      hatId: grant.hatId,
      tokenExpiresAt: new Date(grant.token.expiresAt).toISOString(),
      hasRefreshToken: grant.token.refreshToken !== null,
      scopes: grant.token.scopes,
    };
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }
}

async function doDisconnect(ctx: LegacyVerbContext, providerId: string | undefined): Promise<unknown> {
  if (!providerId) return { error: 'Usage: legacy disconnect <provider>' };
  let grants: LegacyGrant[];
  try {
    grants = await ctx.store.listByProvider(providerId);
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }
  if (grants.length === 0) {
    return { ok: true, disconnected: 0, message: `no active grants for '${providerId}'` };
  }
  for (const grant of grants) {
    await ctx.orchestrator.disconnect(grant);
  }
  return { ok: true, disconnected: grants.length };
}

async function doStatus(ctx: LegacyVerbContext, providerId: string | undefined): Promise<unknown> {
  const targets = providerId
    ? [providerId]
    : ctx.registry.list().map(p => p.id);
  const out: Record<string, unknown> = {};
  for (const id of targets) {
    let grants: LegacyGrant[];
    try {
      grants = await ctx.store.listByProvider(id);
    } catch (err) {
      out[id] = { error: err instanceof Error ? err.message : String(err) };
      continue;
    }
    const grantBlocks = await Promise.all(grants.map(g => grantSummaryWithIngest(ctx, g)));
    const blobCount = ctx.blobStore ? await ctx.blobStore.count(id) : null;
    const queue = ctx.proposalStore ? await summariseQueue(ctx.proposalStore, id) : null;
    out[id] = {
      grants: grantBlocks,
      ...(blobCount !== null ? { rawItemsStored: blobCount } : {}),
      ...(queue ? { queue } : {}),
      continuous: listContinuous(ctx, id),
    };
  }
  return { providers: out };
}

async function doIngest(
  ctx: LegacyVerbContext,
  providerId: string | undefined,
  flags: Record<string, unknown>,
): Promise<unknown> {
  if (!providerId) {
    return {
      error:
        'Usage: legacy ingest <provider> [--since <iso>] [--max-pages <n>] [--query <gmail-query-string>] [--no-extract] [--reextract]',
    };
  }
  if (!ctx.worker) return { error: 'ingest worker not configured (LI2 deps not wired)' };
  const provider = ctx.registry.get(providerId);
  if (!provider) return { error: `unknown provider '${providerId}'` };

  const since = parseSinceFlag(flags.since);
  const maxPages = parseMaxPages(flags['max-pages']);
  const query = parseQueryFlag(flags.query);
  const noExtract = flags['no-extract'] === true || flags['no-extract'] === 'true';
  // `--reextract` re-runs extraction over already-stored blobs even if
  // they have prior proposals. Useful when the extractor prompt/schema
  // has been upgraded (e.g. PR #361 added point_of_contact) and the
  // operator wants the new fields populated for already-fetched mail
  // without burning Gmail API quota on a re-fetch.
  const reextract = flags.reextract === true || flags.reextract === 'true';
  let cp;
  try {
    cp = await ctx.worker.backfill(provider, { since, maxPages, query });
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }

  // D-DOG.1.0 — chain the extractor pass onto the tail of the ingest so
  // `legacy ingest gmail` produces proposals in one shot. The legacy CLI
  // wires `ExtractionRunner` into the ctx; older hosts that haven't done
  // so still get the LI2-only blob-fetch behaviour. `--no-extract` lets
  // the operator skip the (potentially LLM-cost-bearing) extract pass
  // when they only want to inspect raw fetches; `--reextract` forces
  // re-extraction over already-processed blobs.
  let extractSummary: ExtractionRunSummary | { skipped: string } | undefined;
  if (noExtract) {
    extractSummary = { skipped: 'no-extract flag set' };
  } else if (ctx.extractionRunner) {
    try {
      extractSummary = await ctx.extractionRunner.runForProvider(provider.id, { force: reextract });
    } catch (err) {
      // Extraction failure must not mask the (already-completed) ingest
      // result — surface both so the operator can re-run extract via
      // `legacy reextract` (or future verbs) without re-fetching blobs.
      extractSummary = {
        skipped:
          'extract error: ' + (err instanceof Error ? err.message : String(err)),
      };
    }
  } else {
    extractSummary = { skipped: 'no extraction runner wired' };
  }

  return {
    ok: true,
    providerId,
    grantId: cp.grantId,
    pagesProcessed: cp.pagesProcessed,
    itemsPersisted: cp.itemsPersisted,
    completed: cp.completed,
    cursor: cp.cursor,
    extract: extractSummary,
  };
}

/**
 * `legacy extract <provider> [--force]`
 *
 * Run the extraction pass over already-stored blobs without fetching
 * new ones from the provider. No OAuth grant required. Use this when
 * the extractor prompt/schema has been upgraded and you want to re-
 * extract without burning provider API quota on a re-fetch.
 *
 * `--force` supersedes existing proposals (same as `ingest --reextract`).
 * Without `--force`, blobs that already have a proposal are skipped.
 */
async function doExtract(
  ctx: LegacyVerbContext,
  providerId: string | undefined,
  flags: Record<string, unknown>,
): Promise<unknown> {
  if (!providerId) {
    return { error: 'Usage: legacy extract <provider> [--force]' };
  }
  if (!ctx.extractionRunner) {
    return { error: 'no extraction runner wired (LLM backend not configured — set ANTHROPIC_API_KEY, OPENROUTER_API_KEY, or OLLAMA_BASE_URL)' };
  }
  const force = flags.force === true || flags.force === 'true';
  const maxItems = typeof flags.max === 'number'
    ? flags.max
    : (typeof flags.max === 'string' && /^\d+$/.test(flags.max) ? parseInt(flags.max, 10) : undefined);
  const summary = await ctx.extractionRunner.runForProvider(providerId, { force, maxItems });
  return { ok: true, providerId, extract: summary };
}

async function doAuto(
  ctx: LegacyVerbContext,
  providerId: string | undefined,
  flags: Record<string, unknown>,
): Promise<unknown> {
  if (!providerId) return { error: 'Usage: legacy auto <provider> [--interval <seconds>]' };
  if (!ctx.worker || !ctx.continuousHandles) {
    return { error: 'continuous-mode worker not configured (LI2 deps not wired)' };
  }
  const provider = ctx.registry.get(providerId);
  if (!provider) return { error: `unknown provider '${providerId}'` };

  const intervalSec = typeof flags.interval === 'number' ? flags.interval
    : typeof flags.interval === 'string' ? Number(flags.interval)
    : 300;
  const intervalMs = Math.max(60, intervalSec * 1000);

  const grants = await ctx.store.listByProvider(providerId);
  if (grants.length === 0) return { error: `no grants for '${providerId}'; run 'legacy connect ${providerId}' first` };

  const started: string[] = [];
  for (const grant of grants) {
    const key = `${providerId}:${grant.grantId}`;
    if (ctx.continuousHandles.has(key)) continue;
    const stop = ctx.worker.startContinuous(provider, intervalMs);
    ctx.continuousHandles.set(key, stop);
    started.push(grant.grantId);
  }
  return { ok: true, providerId, intervalSec, started };
}

async function doStop(
  ctx: LegacyVerbContext,
  providerId: string | undefined,
): Promise<unknown> {
  if (!providerId) return { error: 'Usage: legacy stop <provider>' };
  if (!ctx.continuousHandles) return { error: 'no continuous handles registered' };
  let stopped = 0;
  for (const [key, stop] of ctx.continuousHandles) {
    if (key.startsWith(`${providerId}:`)) {
      stop();
      ctx.continuousHandles.delete(key);
      stopped += 1;
    }
  }
  return { ok: true, providerId, stopped };
}

async function grantSummaryWithIngest(
  ctx: LegacyVerbContext,
  grant: LegacyGrant,
): Promise<Record<string, unknown>> {
  const base = grantSummary(grant);
  if (!ctx.cursorStore) return base;
  try {
    const cp = await ctx.cursorStore.get(grant.providerId, grant.grantId);
    if (!cp) return base;
    return {
      ...base,
      ingest: {
        cursor: cp.cursor,
        since: cp.since,
        highWatermark: cp.highWatermark
          ? new Date(cp.highWatermark).toISOString()
          : null,
        pagesProcessed: cp.pagesProcessed,
        itemsPersisted: cp.itemsPersisted,
        completed: cp.completed,
        lastUpdatedAt: cp.lastUpdatedAt,
      },
    };
  } catch {
    return base;
  }
}

function listContinuous(ctx: LegacyVerbContext, providerId: ProviderId): string[] {
  if (!ctx.continuousHandles) return [];
  const out: string[] = [];
  for (const key of ctx.continuousHandles.keys()) {
    if (key.startsWith(`${providerId}:`)) out.push(key.slice(providerId.length + 1));
  }
  return out;
}

function parseSinceFlag(raw: unknown): number | undefined {
  if (typeof raw === 'number') return raw;
  if (typeof raw !== 'string' || raw.length === 0) return undefined;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? ms : undefined;
}

function parseMaxPages(raw: unknown): number | undefined {
  if (typeof raw === 'number') return raw;
  if (typeof raw === 'string' && raw.length > 0) {
    const n = Number(raw);
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

function parseQueryFlag(raw: unknown): string | undefined {
  // Strings only — anything else (including booleans from a bare `--query`
  // with no value) is silently ignored so the operator gets the
  // "no filter" behaviour rather than an error.
  if (typeof raw !== 'string' || raw.length === 0) return undefined;
  return raw;
}

function doProviders(ctx: LegacyVerbContext): unknown {
  return {
    providers: ctx.registry.list().map(p => ({
      id: p.id,
      displayName: p.displayName,
      oauthScopes: p.oauthScopes,
    })),
  };
}

function grantSummary(grant: LegacyGrant): Record<string, unknown> {
  const remainingMs = grant.token.expiresAt - Date.now();
  return {
    grantId: grant.grantId,
    accountLabel: grant.accountLabel,
    createdAt: grant.createdAt,
    lastRefreshedAt: grant.lastRefreshedAt,
    hatId: grant.hatId,
    accessTokenExpiresAt: new Date(grant.token.expiresAt).toISOString(),
    accessTokenExpiresInSeconds: Math.max(0, Math.floor(remainingMs / 1000)),
    hasRefreshToken: grant.token.refreshToken !== null,
    scopes: grant.token.scopes,
  };
}

function helpText(): unknown {
  return {
    verbs: [
      'legacy connect <provider>',
      'legacy resume <state> <code>',
      'legacy disconnect <provider>',
      'legacy status [<provider>]',
      'legacy providers',
      'legacy register-client <provider> --client-id <id> [--client-secret <secret>] --redirect-uri <url> [--pkce]',
      'legacy unregister-client <provider>',
      'legacy clients',
      'legacy ingest <provider> [--since <iso>] [--max-pages <n>] [--query <q>] [--no-extract] [--reextract]',
      'legacy auto <provider> [--interval <seconds>]',
      'legacy stop <provider>',
      'legacy review [--provider <id>] [--confidence <op><n>] [--limit <n>]',
      'legacy ratify <provider>:<proposal-id>',
      'legacy reject <provider>:<proposal-id> --reason <text>',
      'legacy correct <provider>:<proposal-id>',
      'legacy bulk-ratify [--provider <id>] --confidence <op><n> [--dry-run]',
      'legacy unratify <provider>:<receipt-id>',
      'legacy migrate-to-graph [--dry-run]',
      'legacy reingest <provider> [--dry-run] [--since <iso>] [--max <n>] [--upgrade-existing] [--min-version v0.6]',
    ],
  };
}

// ── LI4 handlers ──

async function doReview(ctx: LegacyVerbContext, flags: Record<string, unknown>): Promise<unknown> {
  if (!ctx.proposalStore) return { error: 'proposal store not configured (LI3 deps not wired)' };
  const limit = parseNumFlag(flags.limit) ?? 10;
  const cf = parseConfidenceFilter(flags.confidence);
  const proposals = await ctx.proposalStore.list({
    providerId: typeof flags.provider === 'string' ? flags.provider : undefined,
    status: 'pending',
    minConfidence: cf.min,
    maxConfidence: cf.max,
    limit,
  });
  return { pending: proposals.length, proposals: proposals.map(proposalSummary) };
}

async function doRatify(ctx: LegacyVerbContext, target: string | undefined): Promise<unknown> {
  if (!target) return { error: 'Usage: legacy ratify <provider>:<proposal-id>' };
  if (!ctx.ratification) return { error: 'ratification not configured (LI4 deps not wired)' };
  const split = parseProviderQualifiedId(target);
  if (!split) return { error: 'expected <provider>:<id>' };
  try {
    const r = await ctx.ratification.ratify(split.providerId, split.id);
    return { ok: true, receiptId: r.receiptId, cellId: r.cellId };
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }
}

async function doReject(
  ctx: LegacyVerbContext,
  target: string | undefined,
  flags: Record<string, unknown>,
): Promise<unknown> {
  if (!target) return { error: 'Usage: legacy reject <provider>:<proposal-id> --reason <text>' };
  if (!ctx.ratification) return { error: 'ratification not configured' };
  const split = parseProviderQualifiedId(target);
  if (!split) return { error: 'expected <provider>:<id>' };
  const reason = typeof flags.reason === 'string' ? flags.reason : 'unspecified';
  try {
    const r = await ctx.ratification.reject(split.providerId, split.id, reason);
    return { ok: true, ...r };
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }
}

async function doCorrect(ctx: LegacyVerbContext, target: string | undefined): Promise<unknown> {
  if (!target) return { error: 'Usage: legacy correct <provider>:<proposal-id>' };
  if (!ctx.ratification || !ctx.proposalStore) return { error: 'ratification not configured' };
  if (!ctx.openCorrectionEditor) return { error: 'no correction editor wired (host responsibility)' };
  const split = parseProviderQualifiedId(target);
  if (!split) return { error: 'expected <provider>:<id>' };
  const proposal = await ctx.proposalStore.get(split.providerId, split.id);
  if (!proposal) return { error: `proposal ${target} not found` };
  const corrected = await ctx.openCorrectionEditor(proposal);
  if (!corrected) return { ok: false, message: 'correction cancelled' };
  try {
    const r = await ctx.ratification.correct(split.providerId, split.id, corrected);
    return {
      ok: true,
      receiptId: r.receipt.receiptId,
      correctionId: r.correction.correctionId,
      cellId: r.receipt.cellId,
    };
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }
}

async function doBulkRatify(ctx: LegacyVerbContext, flags: Record<string, unknown>): Promise<unknown> {
  if (!ctx.ratification) return { error: 'ratification not configured' };
  const cf = parseConfidenceFilter(flags.confidence);
  if (cf.min === undefined) return { error: 'bulk-ratify requires --confidence ">=<n>"' };
  const dryRun = flags['dry-run'] === true || flags['dry-run'] === 'true';
  return ctx.ratification.bulkRatify({
    providerId: typeof flags.provider === 'string' ? flags.provider : undefined,
    minConfidence: cf.min,
    dryRun,
  });
}

async function doUnratify(ctx: LegacyVerbContext, target: string | undefined): Promise<unknown> {
  if (!target) return { error: 'Usage: legacy unratify <provider>:<receipt-id>' };
  if (!ctx.ratification) return { error: 'ratification not configured' };
  const split = parseProviderQualifiedId(target);
  if (!split) return { error: 'expected <provider>:<id>' };
  try {
    const r = await ctx.ratification.unratify(split.providerId, split.id);
    return { ok: true, ...r };
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }
}

// ── LI4 helpers ──

async function summariseQueue(store: ProposalStore, providerId: ProviderId): Promise<Record<string, number>> {
  const all = await store.list({ providerId });
  const counts: Record<string, number> = {};
  for (const p of all) counts[p.status] = (counts[p.status] ?? 0) + 1;
  return counts;
}

function proposalSummary(p: Proposal): Record<string, unknown> {
  // Tier 1.7 — surface the deep-PDF fields by default. Older proposals
  // (v0.4 and earlier) don't carry these; we omit them when absent so
  // operators reviewing a mixed v0.4/v0.5 queue see a clean per-row
  // shape. JSON consumers tolerate optional fields; TUI consumers can
  // keep their existing rendering and progressively add new columns.
  const out: Record<string, unknown> = {
    proposalId: p.proposalId,
    providerId: p.provenance.providerId,
    providerItemId: p.provenance.providerItemId,
    confidence: Number(p.confidence.toFixed(3)),
    status: p.status,
    // PR #361 added pointOfContact to the Proposal type. Surface it
    // here so `legacy review` shows the agency / PM / tenant /
    // landlord identity the operator actually wants to see at a
    // glance, alongside (not in place of) the LLM-emitted summary.
    pointOfContact: p.pointOfContact,
    summary: p.summary,
    threadKey: p.threadKey,
    siblingProposalIds: p.siblingProposalIds,
  };
  if (p.workOrderNumber !== undefined) out.workOrderNumber = p.workOrderNumber;
  if (p.issuanceDate !== undefined) out.issuanceDate = p.issuanceDate;
  if (p.dueDate !== undefined) out.dueDate = p.dueDate;
  if (p.propertyAddress !== undefined) out.propertyAddress = p.propertyAddress;
  if (p.propertyKey !== undefined) out.propertyKey = p.propertyKey;
  if (p.primaryContact !== undefined) out.primaryContact = p.primaryContact;
  if (p.secondaryContacts !== undefined) out.secondaryContacts = p.secondaryContacts;
  if (p.ownerName !== undefined) out.ownerName = p.ownerName;
  if (p.billingParty !== undefined) out.billingParty = p.billingParty;
  if (p.hasPhotos !== undefined) out.hasPhotos = p.hasPhotos;
  if (p.photoCount !== undefined) out.photoCount = p.photoCount;
  if (p.sourceAttachmentPath !== undefined) {
    out.sourceAttachmentPath = p.sourceAttachmentPath;
  }
  return out;
}

function parseProviderQualifiedId(s: string): { providerId: string; id: string } | null {
  const colon = s.indexOf(':');
  if (colon <= 0 || colon === s.length - 1) return null;
  return { providerId: s.slice(0, colon), id: s.slice(colon + 1) };
}

function parseNumFlag(raw: unknown): number | undefined {
  if (typeof raw === 'number') return raw;
  if (typeof raw === 'string' && raw.length > 0) {
    const n = Number(raw);
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

interface ConfidenceFilter { min?: number; max?: number; }

function parseConfidenceFilter(raw: unknown): ConfidenceFilter {
  if (typeof raw !== 'string') return {};
  const m = raw.match(/^(>=|<=|<|>|=)?\s*(-?\d*\.?\d+)$/);
  if (!m) return {};
  const op = m[1] ?? '>=';
  const n = Number(m[2]);
  if (!Number.isFinite(n)) return {};
  switch (op) {
    case '>=': return { min: n };
    case '>':  return { min: n + Number.EPSILON };
    case '<=': return { max: n };
    case '<':  return { max: n - Number.EPSILON };
    case '=':  return { min: n, max: n };
  }
  return {};
}

// ── Client config handlers ──

async function doRegisterClient(
  ctx: LegacyVerbContext,
  providerId: string | undefined,
  flags: Record<string, unknown>,
): Promise<unknown> {
  if (!providerId) {
    return { error: 'Usage: legacy register-client <provider> --client-id <id> [--client-secret <secret>] --redirect-uri <url> [--pkce]' };
  }
  if (!ctx.clientConfigStore || !ctx.clientConfigCache) {
    return { error: 'client config store not configured (host responsibility)' };
  }
  if (!ctx.registry.get(providerId)) {
    return { error: `unknown provider '${providerId}' — registered providers: ${ctx.registry.list().map(p => p.id).join(', ') || '(none)'}` };
  }
  const clientId = strFlag(flags, 'client-id');
  const redirectUri = strFlag(flags, 'redirect-uri');
  if (!clientId) return { error: '--client-id is required' };
  if (!redirectUri) return { error: '--redirect-uri is required' };
  const clientSecret = strFlag(flags, 'client-secret');
  const pkce = flags.pkce === true || flags.pkce === 'true';

  const stored: StoredClientConfig = {
    providerId,
    clientId,
    clientSecret,
    redirectUri,
    pkce: pkce || undefined,
    registeredAt: new Date().toISOString(),
    registeredBy: ctx.hatIdProvider?.() ?? null,
  };
  try {
    await ctx.clientConfigStore.put(stored);
    await ctx.clientConfigCache.reload();
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }
  return {
    ok: true,
    providerId,
    redirectUri,
    pkce: pkce || false,
    hasClientSecret: clientSecret !== undefined,
    note: clientSecret
      ? 'Client credentials stored encrypted at rest under your wallet KEK.'
      : 'Client credentials stored. No client secret supplied — provider must support PKCE-only flow.',
  };
}

async function doUnregisterClient(
  ctx: LegacyVerbContext,
  providerId: string | undefined,
): Promise<unknown> {
  if (!providerId) return { error: 'Usage: legacy unregister-client <provider>' };
  if (!ctx.clientConfigStore || !ctx.clientConfigCache) {
    return { error: 'client config store not configured (host responsibility)' };
  }
  try {
    const existing = await ctx.clientConfigStore.get(providerId);
    if (!existing) return { ok: true, providerId, note: 'no client config registered for this provider' };
    await ctx.clientConfigStore.delete(providerId);
    ctx.clientConfigCache.forget(providerId);
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }
  return { ok: true, providerId, note: 'Client credentials removed. Existing grants are not deleted; they remain usable until the provider revokes them.' };
}

async function doListClients(ctx: LegacyVerbContext): Promise<unknown> {
  if (!ctx.clientConfigStore) {
    return { error: 'client config store not configured (host responsibility)' };
  }
  let configs: StoredClientConfig[];
  try {
    configs = await ctx.clientConfigStore.list();
  } catch (err) {
    return { error: err instanceof Error ? err.message : String(err) };
  }
  // Never surface the client secret. Show clientId as a first-8…last-4
  // fingerprint so the operator can verify which client is registered
  // without echoing a credential. Google client IDs share the
  // `.apps.googleusercontent.com` suffix; the unique part is the prefix,
  // so we keep more of it.
  return {
    clients: configs.map(c => ({
      providerId: c.providerId,
      clientIdFingerprint: fingerprintClientId(c.clientId),
      redirectUri: c.redirectUri,
      pkce: c.pkce ?? false,
      hasClientSecret: c.clientSecret !== undefined && c.clientSecret !== null,
      registeredAt: c.registeredAt,
      registeredBy: c.registeredBy,
    })),
  };
}

function fingerprintClientId(id: string): string {
  if (id.length <= 12) return id;
  return `${id.slice(0, 8)}\u2026${id.slice(-4)}`;
}

function strFlag(flags: Record<string, unknown>, key: string): string | undefined {
  const v = flags[key];
  if (typeof v === 'string' && v.length > 0) return v;
  return undefined;
}

// ── D-DOG.1.0c Phase 5 G.1 — `legacy migrate-to-graph` ──────────────
//
// Walks the operator's existing flat `<brainDataDir>/oddjobz/jobs.jsonl`
// rows for v1 (pre-Phase-2A.4) cells and re-ratifies each through the
// Phase 2A.4 graph-walk handler (which also signs via Phase 4's BKDS).
//
// A v1 row is identified by the absence of the v2-only `siteRef` field
// (see `runtime/semantos-brain/src/jobs_store_fs.zig` lines 90-113 for the row-shape
// discriminator the Zig store uses on replay; this verb mirrors that).
//
// Match strategy: every v1 row carries a UUID `id` field. Each
// `RatificationReceipt` written under the v1 ratify path stamped that
// UUID into its `cellId` field. Looking up the receipt by cellId gives
// us `(providerId, proposalId)`, and the proposal-store still holds the
// original SIRProgram + payload-hint that produced the row. Re-ratifying
// the same proposal through the Phase 2A.4 graph translator mints the
// site/customer/job/attachment cell graph in place.
//
// Best-effort. Per matrix R5 the operator's first dogfood produced 72
// v1 cells and some pre-Phase-1.7 proposals may have been pruned; rows
// that don't resolve to a live proposal stay flat and gain a
// `legacy_unsigned: true` marker (written to a sidecar
// `<brainDataDir>/oddjobz/legacy-unsigned.jsonl`) so helm + mobile can
// surface them with the "legacy" pill (Phase 5 G.2).
//
// The marker file is sidecar (separate from `jobs.jsonl`) so this verb
// never has to rewrite the existing JSONL — append-only is the only
// operation. Re-ratify writes its new graph through the same RPC the
// `legacy ratify` verb uses, so the original v1 row stays in
// `jobs.jsonl` (helm + mobile renderers walk both v1 and v2 rows; the
// v1 row will visually render as "superseded by graph row" when its id
// appears in the migration index, see `legacy-ratifications.jsonl`).
//
// Idempotency: re-running the verb is safe. The proposal-store's
// `status` column flips from `pending`/`ratified` to `ratified` after a
// successful re-ratify, but the existing receipt is preserved
// (we mint a NEW receipt for the migration so audit-trail readers see
// both the original v1 ratify and the v0 → v2 graph promotion). When a
// proposal is already migrated (a previous run produced a receipt with
// the SAME proposal_id but a graph-shaped cellId object), we skip it.
async function doMigrateToGraph(
  ctx: LegacyVerbContext,
  flags: Record<string, unknown>,
): Promise<unknown> {
  if (!ctx.proposalStore) return { error: 'proposal store not configured' };
  if (!ctx.receiptStore) return { error: 'receipt store not configured' };
  if (!ctx.ratification) return { error: 'ratification not configured' };
  if (!ctx.brainDataDir) return { error: 'brain data dir not configured (set BRAIN_DATA_DIR or pass via host)' };

  const dryRun = flags['dry-run'] === true || flags['dry-run'] === 'true';
  const oddjobzDir = join(ctx.brainDataDir, 'oddjobz');
  const jobsPath = join(oddjobzDir, 'jobs.jsonl');
  const unsignedPath = join(oddjobzDir, 'legacy-unsigned.jsonl');

  const v1Rows = readV1Jobs(jobsPath);
  if (v1Rows.length === 0) {
    return {
      ok: true,
      scanned: 0,
      migrated: 0,
      flaggedLegacy: 0,
      dryRun,
      message: 'no v1 flat rows found; jobs.jsonl is either empty or already graph-shaped',
    };
  }

  // Build cellId → {providerId, proposalId} from receipts. v1 receipts
  // stamped the row UUID into the `cellId` field as a plain string;
  // v2 receipts stringify a `{site, customers, job, attachments}`
  // graph. Anything that JSON-parses as an object is v2 and skipped
  // here — those rows already migrated.
  const receipts = await ctx.receiptStore.list();
  const cellIdToReceipt = new Map<string, { providerId: string; proposalId: string }>();
  const migratedProposalIds = new Set<string>();
  for (const r of receipts) {
    const cid = r.cellId;
    if (cid === null || cid.length === 0) continue;
    if (cid.startsWith('{')) {
      // v2 graph receipt — track the proposal so we don't re-migrate.
      migratedProposalIds.add(`${r.providerId}:${r.proposalId}`);
      continue;
    }
    cellIdToReceipt.set(cid, { providerId: r.providerId, proposalId: r.proposalId });
  }

  let migrated = 0;
  let flagged = 0;
  let alreadyMigrated = 0;
  let proposalMissing = 0;
  let ratifyError = 0;
  const flaggedRows: Array<{ id: string; reason: string }> = [];
  const migratedRows: Array<{ id: string; receiptId: string; cellId: string | null }> = [];

  for (const row of v1Rows) {
    const id = typeof row.id === 'string' ? row.id : '';
    if (id.length === 0) {
      // Defensive — a v1 row without an id can't be matched to a
      // proposal. Flag and move on.
      flagged += 1;
      flaggedRows.push({ id: '(no-id)', reason: 'row has no id field' });
      if (!dryRun) {
        appendUnsignedMarker(unsignedPath, {
          v1Id: '(no-id)',
          reason: 'row has no id field',
          flaggedAt: new Date().toISOString(),
        });
      }
      continue;
    }

    const ref = cellIdToReceipt.get(id);
    if (!ref) {
      flagged += 1;
      flaggedRows.push({ id, reason: 'no receipt found for v1 cellId' });
      if (!dryRun) {
        appendUnsignedMarker(unsignedPath, {
          v1Id: id,
          reason: 'no receipt found for v1 cellId',
          flaggedAt: new Date().toISOString(),
        });
      }
      continue;
    }
    if (migratedProposalIds.has(`${ref.providerId}:${ref.proposalId}`)) {
      alreadyMigrated += 1;
      continue;
    }

    const proposal = await ctx.proposalStore.get(ref.providerId, ref.proposalId);
    if (!proposal) {
      proposalMissing += 1;
      flagged += 1;
      flaggedRows.push({ id, reason: `proposal ${ref.providerId}:${ref.proposalId} no longer in store` });
      if (!dryRun) {
        appendUnsignedMarker(unsignedPath, {
          v1Id: id,
          reason: 'source proposal no longer in store',
          providerId: ref.providerId,
          proposalId: ref.proposalId,
          flaggedAt: new Date().toISOString(),
        });
      }
      continue;
    }

    if (dryRun) {
      migrated += 1;
      migratedRows.push({ id, receiptId: '(dry-run)', cellId: null });
      continue;
    }

    // Re-ratify through the orchestrator. The proposal's status was
    // flipped to `ratified` on the original v1 ratify; the orchestrator
    // refuses to ratify a non-pending proposal, so we flip it back to
    // pending for the migration window, ratify, and let
    // `completeRatification` flip it to `ratified` again. This keeps the
    // public ratification API unchanged.
    try {
      await ctx.proposalStore.update({ ...proposal, status: 'pending' });
      const r = await ctx.ratification.ratify(ref.providerId, ref.proposalId);
      migrated += 1;
      migratedRows.push({ id, receiptId: r.receiptId, cellId: r.cellId });
      // Stamp the proposal pair as migrated so a re-run doesn't try
      // again — defensive against the receipt-list snapshot taken at
      // the top of this function being stale by the time we finish.
      migratedProposalIds.add(`${ref.providerId}:${ref.proposalId}`);
    } catch (err) {
      ratifyError += 1;
      flagged += 1;
      const reason = err instanceof Error ? err.message : String(err);
      flaggedRows.push({ id, reason: `re-ratify failed: ${reason}` });
      appendUnsignedMarker(unsignedPath, {
        v1Id: id,
        reason: `re-ratify failed: ${reason}`,
        providerId: ref.providerId,
        proposalId: ref.proposalId,
        flaggedAt: new Date().toISOString(),
      });
    }
  }

  return {
    ok: true,
    scanned: v1Rows.length,
    migrated,
    alreadyMigrated,
    flaggedLegacy: flagged,
    proposalMissing,
    ratifyError,
    dryRun,
    unsignedMarkerPath: dryRun ? null : unsignedPath,
    flaggedRows: flaggedRows.slice(0, 50),
    migratedRows: migratedRows.slice(0, 50),
  };
}

interface V1JobRow {
  id?: unknown;
  customer_name?: unknown;
  state?: unknown;
  scheduled_at?: unknown;
  created_at?: unknown;
  // v2 discriminator — when present, the row is graph-shaped and the
  // migration verb skips it (Phase 2A.4 already shipped this row).
  siteRef?: unknown;
}

/**
 * Read v1 (pre-Phase-2A.4 / flat-shape) rows from `jobs.jsonl`.
 *
 * Mirrors the discriminator `runtime/semantos-brain/src/jobs_store_fs.zig` uses on
 * replay: the absence of the v2-only `siteRef` field means v1.
 *
 * Returns the most-recent record per `id` (jobs.jsonl is append-only;
 * later records like state-transition appends overwrite earlier ones
 * for the same id). The migration verb only cares about `id`, so we
 * pass the full row through and let the caller pick the field it needs.
 */
function readV1Jobs(path: string): V1JobRow[] {
  if (!existsSync(path)) return [];
  let raw: string;
  try {
    raw = readFileSync(path, 'utf8');
  } catch {
    return [];
  }
  const byId = new Map<string, V1JobRow>();
  for (const line of raw.split('\n')) {
    if (line.length === 0) continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    if (typeof parsed !== 'object' || parsed === null) continue;
    const obj = parsed as V1JobRow;
    // v2 rows carry `siteRef` (a 64-hex string); v1 rows omit it
    // entirely. Forward-compat: a future v3 row that DOES carry siteRef
    // is also skipped — the migration verb only fires on v1.
    if (typeof obj.siteRef === 'string' && obj.siteRef.length > 0) continue;
    if (typeof obj.id !== 'string' || obj.id.length === 0) continue;
    byId.set(obj.id, obj);
  }
  return [...byId.values()];
}

/**
 * Append one un-matchable v1 row to the sidecar `legacy-unsigned.jsonl`
 * marker file. Helm + mobile read this file alongside `jobs.jsonl` to
 * paint the "legacy" pill on the matching row (Phase 5 G.2).
 *
 * Append-only is intentional: a re-run of `legacy migrate-to-graph`
 * idempotently appends the same marker line; readers de-dupe on
 * `v1Id`. We never rewrite or delete this file from this verb.
 */
function appendUnsignedMarker(path: string, entry: Record<string, unknown>): void {
  const dir = dirname(path);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  appendFileSync(path, JSON.stringify(entry) + '\n');
}

// ── D-RTC.7 — `legacy reingest <provider>` ───────────────────────────
//
// Drives the D-RTC.6 reingest worker over the existing proposal corpus
// for `<provider>`. Each proposal's raw email blob is loaded from the
// blob store, MIME-parsed for attachments, and reingested through the
// typed-cell pipeline (site → customers → job → attachments).
//
// `--dry-run` swaps the real EncodeDispatcher for a counting stub so
// the operator can preview projected ratification counts without
// minting cells brain-side. The dispatcher seam means the rest of the
// pipeline is exercised identically — site dedupe still runs, blob
// hashes are still computed, parent has_pictures still propagates.
async function doReingest(
  ctx: LegacyVerbContext,
  providerId: string | undefined,
  flags: Record<string, unknown>,
): Promise<unknown> {
  if (!providerId) {
    return {
      error:
        'Usage: legacy reingest <provider> [--dry-run] [--since <iso>] [--max <n>] [--upgrade-existing] [--min-version v0.6]',
    };
  }
  if (!ctx.proposalStore) return { error: 'proposal store not configured' };
  if (!ctx.blobStore) return { error: 'blob store not configured' };
  if (!ctx.sitesView) return { error: 'sites view not configured (D-RTC.7 dep)' };
  if (!ctx.attachmentBlobStore) {
    return { error: 'attachment blob store not configured (D-RTC.7 dep)' };
  }

  const dryRun = flags['dry-run'] === true || flags['dry-run'] === 'true';
  const upgradeExisting =
    flags['upgrade-existing'] === true || flags['upgrade-existing'] === 'true';
  // Optional extractor-version filter — `--min-version v0.6` (alias
  // for `email-rfc822-v0.6`). Proposals with an older extractor
  // version are skipped at scan time. Default unset: every proposal
  // is eligible. Use this after a `legacy extract --force` to mint
  // ONLY the freshly-re-extracted proposals and leave stale
  // pre-v0.6 ones alone.
  let minExtractorVersion: string | null = null;
  if (typeof flags['min-version'] === 'string') {
    const raw = flags['min-version'].trim();
    minExtractorVersion = raw.startsWith('email-rfc822-')
      ? raw
      : raw.startsWith('v')
        ? `email-rfc822-${raw}`
        : raw;
  }
  if (!dryRun && !ctx.encodeDispatcher) {
    return {
      error:
        'encode dispatcher not configured — non-dry-run reingest needs brain-side `entity.encode` wiring',
    };
  }

  // Dry-run dispatcher: counts requests by tag, returns synthetic ids
  // so the worker pipeline continues end-to-end without touching the
  // brain. Operators get the same shape of receipts they'd see in
  // production, just with placeholder cell ids.
  const dryCounts: Record<number, number> = {};
  let dryCounter = 0;
  const dryDispatcher: EncodeDispatcher = {
    async dispatch(req) {
      dryCounts[req.spec.tag] = (dryCounts[req.spec.tag] ?? 0) + 1;
      dryCounter += 1;
      return (
        req.spec.tag.toString(16).padStart(2, '0') +
        dryCounter.toString(16).padStart(62, '0')
      );
    },
  };
  const dispatcher: EncodeDispatcher = dryRun ? dryDispatcher : ctx.encodeDispatcher!;

  const since = parseSinceFlag(flags.since);
  const max = parseNumFlag(flags.max) ?? Infinity;
  const ownerIdHex = ctx.ownerIdHex ?? '0'.repeat(32);

  // Pull pending proposals for the provider. We don't filter on status
  // — operators may want to re-ingest already-ratified rows under the
  // new typed-cell shape. The receipts coming back from this verb can
  // be used by a follow-up upgrade-in-place pass.
  const proposals = await ctx.proposalStore.list({ providerId });

  // Job-dedupe index. Seed from prior receipts (cross-run dedupe),
  // then keep it live as jobs mint this run (within-run dedupe — the
  // bundle-fanout dupes are all in one run). A proposal whose job
  // lookup-key already mapped to a cell reuses it instead of minting
  // a second job_cell.
  const jobKeyToCell = new Map<string, string>();
  if (ctx.reingestReceiptStore) {
    try {
      for (const r of await ctx.reingestReceiptStore.list(providerId)) {
        if (r.jobLookupKey && r.jobLookupKey.length > 0 && r.jobCellId) {
          jobKeyToCell.set(r.jobLookupKey, r.jobCellId);
        }
      }
    } catch {
      // Missing/locked receipt store → start cold; dedupe still works
      // within this run.
    }
  }
  const jobsDedupeView = {
    async findJobByLookupKey(key: string): Promise<string | null> {
      return jobKeyToCell.get(key) ?? null;
    },
  };

  // Customer-dedupe index (handoff §6.2). Same posture as jobs: seed
  // from prior receipts (cross-run dedupe), keep live as customers mint
  // this run (the agency-across-many-properties fan-out is mostly within
  // one run). A contact whose natural key already mapped to a cell
  // reuses it — this is what stops the canonicalized 152 from regrowing.
  const customerKeyToCell = new Map<string, string>();
  if (ctx.reingestReceiptStore) {
    try {
      for (const r of await ctx.reingestReceiptStore.list(providerId)) {
        const keys = r.customerLookupKeys;
        const ids = r.customerCellIds;
        if (!keys) continue;
        for (let i = 0; i < keys.length && i < ids.length; i++) {
          const k = keys[i];
          if (k && k.length > 0 && k !== 'unkeyed:' && !customerKeyToCell.has(k)) {
            customerKeyToCell.set(k, ids[i]);
          }
        }
      }
    } catch {
      // Missing/locked receipt store → start cold; dedupe still works
      // within this run.
    }
  }
  const customersDedupeView = {
    async findCustomerByLookupKey(key: string): Promise<string | null> {
      return customerKeyToCell.get(key) ?? null;
    },
  };

  let scanned = 0;
  let reingested = 0;
  let skipped = 0;
  let errored = 0;
  let jobsDeduped = 0;
  let customersDeduped = 0;
  const errors: Array<{ proposalId: string; reason: string }> = [];
  const receipts: ReingestOutcome[] = [];

  let versionFiltered = 0;
  for (const p of proposals) {
    if (scanned >= max) break;
    if (since !== undefined && p.extractedAt < since) continue;
    if (
      minExtractorVersion !== null &&
      p.provenance.extractorVersion !== minExtractorVersion
    ) {
      versionFiltered += 1;
      continue;
    }
    scanned += 1;

    const item = await ctx.blobStore.get(p.provenance.providerId, p.provenance.providerItemId);
    if (!item) {
      errored += 1;
      errors.push({ proposalId: p.proposalId, reason: 'raw blob missing' });
      continue;
    }

    let attachments: ReturnType<typeof parseEmailMimeParts>['attachments'] = [];
    try {
      const parsed = parseRfc822(item.bytes);
      const headerContentType =
        (parsed.headers as Record<string, string>)['content-type'] ?? 'text/plain';
      attachments = parseEmailMimeParts(parsed.body, headerContentType).attachments;
    } catch (err) {
      errored += 1;
      errors.push({
        proposalId: p.proposalId,
        reason: 'rfc822 parse: ' + (err instanceof Error ? err.message : String(err)),
      });
      continue;
    }

    try {
      const outcome = await reingestProposal({
        proposal: p,
        attachments,
        sitesView: ctx.sitesView,
        jobsDedupeView,
        customersDedupeView,
        attachmentBlobStore: ctx.attachmentBlobStore,
        dispatcher,
        ownerIdHex,
        // Only wire the receipt store on non-dry-run paths — dry-run
        // never actually mints, so writing a receipt would falsely
        // mark the proposal as ingested.
        receiptStore: dryRun ? undefined : ctx.reingestReceiptStore,
        upgradeExisting,
      });
      receipts.push(outcome);
      if ('skipped' in outcome) {
        skipped += 1;
      } else {
        reingested += 1;
        if (outcome.jobDisposition === 'matched') {
          jobsDeduped += 1;
        } else if (
          outcome.jobLookupKey &&
          outcome.jobLookupKey.length > 0 &&
          !jobKeyToCell.has(outcome.jobLookupKey)
        ) {
          // Keep the live index current so the NEXT duplicate proposal
          // in this run collapses onto this freshly-minted job.
          jobKeyToCell.set(outcome.jobLookupKey, outcome.jobCellId);
        }
        // §6.2 — tally deduped contacts + keep the customer index live so
        // the NEXT proposal naming the same contact collapses onto the
        // freshly-minted customer_cell within this run.
        for (let i = 0; i < outcome.customerCellIds.length; i++) {
          const k = outcome.customerLookupKeys[i];
          const disp = outcome.customerDispositions[i];
          if (disp === 'matched') {
            customersDeduped += 1;
          } else if (k && k.length > 0 && k !== 'unkeyed:' && !customerKeyToCell.has(k)) {
            customerKeyToCell.set(k, outcome.customerCellIds[i]);
          }
        }
      }
    } catch (err) {
      errored += 1;
      errors.push({
        proposalId: p.proposalId,
        reason: 'reingest: ' + (err instanceof Error ? err.message : String(err)),
      });
    }
  }

  return {
    ok: true,
    providerId,
    dryRun,
    upgradeExisting,
    minExtractorVersion,
    versionFiltered,
    scanned,
    reingested,
    skipped,
    errored,
    jobsDeduped,
    customersDeduped,
    projectedCellCountsByTag: dryRun ? dryCounts : undefined,
    errors: errors.slice(0, 25),
    // Cap the receipts surface so the verb response stays bounded; full
    // receipts go to the audit log in the non-dry-run path (audit-log
    // integration is the next-level scope beyond D-RTC.7).
    receipts: receipts.slice(0, 25),
  };
}

```
