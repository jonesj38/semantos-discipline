---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/cell-writer/brain-rpc.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.137108+00:00
---

# runtime/legacy-ingest/src/cell-writer/brain-rpc.ts

```ts
/**
 * BRAIN JSON-RPC cell-writer adapter — D-DOG.1.0c Phase 2B.2.
 *
 * Implements the `RatificationOrchestrator.opts.writeCell` contract by
 * POSTing a ratification request to brain's `oddjobz.ratify_proposal`
 * JSON-RPC verb over the existing `/api/v1/wallet` WSS endpoint. The
 * brain handler walks the SIRProgram's nodes, mints a graph of cells
 * (site → customers → job → attachments) and returns the cell ids as
 * a structured `cellIds` object. Trust level matches every existing
 * oddjobz operator-driven write — K1–K10 cryptographic cell-DAG
 * promotion is captured as D-DOG.1.0d (post-dogfood).
 *
 * Wire shape (request):
 *   {"jsonrpc":"2.0","method":"oddjobz.ratify_proposal",
 *    "params":{"proposal_id":"...", "sir_program":{...},
 *              "payload_hint": {
 *                // Legacy 5 (snake_case, backward-compat):
 *                "customer_name":"...","point_of_contact":"...",
 *                "summary":"...","reference_number":"...",
 *                "source_provider_id":"...",
 *                // Tier 1.7 enriched (camelCase — matches the Zig
 *                // handler's parsePayloadHint keys exactly):
 *                "primaryContact":{"name","role","phone","email"},
 *                "secondaryContacts":[{...}, ...],
 *                "ownerName":"...","billingParty":{"type","name"},
 *                "propertyAddress":"...","propertyKey":"...",
 *                "workOrderNumber":"...","issuanceDate":"YYYY-MM-DD",
 *                "dueDate":"YYYY-MM-DD","hasPhotos":bool,
 *                "photoCount":<int>,"sourceAttachmentPath":"..."
 *              }},
 *    "id": <int>}
 *
 * The brain handler (and the FS fallback below) prefer
 * `point_of_contact` over `customer_name` when filling the JSONL
 * `customer_name` field — the field name stays for backward compat
 * but the *value* is the operator's display point of contact (agency,
 * agent, PM, etc.). The proper schema rename is Tier 1.6.
 *
 * Wire shape (response — D-DOG.1.0c Phase 2A.4 graph rewrite):
 *   {"jsonrpc":"2.0","id":<int>,
 *    "result":{"proposal_id":"<echoed>",
 *              "cellIds":{
 *                "site":"<64hex>"|null,
 *                "customers":["<64hex>", ...],
 *                "job":"<64hex>"|null,
 *                "attachments":["<64hex>", ...]
 *              },
 *              "persistedAt":<i64>}}
 *
 * Phase 1.0 transport: open a fresh WSS connection per ratify (simple,
 * slow). Phase 1.A or later can pool. Bun supports the standard
 * WebSocket global natively.
 *
 * D-DOG.1.0c Phase 2B.2 — TS-side FS fallback graph rewrite. The
 * fallback path now mirrors the Zig handler's graph-walk: it derives a
 * site (with lookupKey dedupe), customer cells (phone → email →
 * name+role+site dedupe ladder), a fresh job cell, and one attachment
 * per source PDF. The on-disk JSONL line shapes match the four typed
 * view-stores (sites/customers/jobs/attachments).jsonl byte-for-byte
 * for the fields they share. CellID generation mirrors the Zig
 * handler's deterministic separator-string SHA-256 strategy
 * (`oddjobz.<type>.v2|...`); Phase 2B.4 lands a cross-language byte-
 * parity oracle. Until then the TS-side and Zig-side graphs are
 * INTENDED to converge for byte-equal inputs but only the dogfood
 * tests assert it directly.
 */

import type { SIRProgram } from '@semantos/semantos-sir';
import type { Proposal, ProposalContact } from '../extractor/types';
import { createHash } from 'node:crypto';
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
} from 'node:fs';
import { join } from 'node:path';

export interface BrainRpcCellWriterOpts {
  /**
   * The brain WSS endpoint, e.g. `ws://localhost:8424/api/v1/wallet`.
   * The default in `apps/legacy-cli/src/bootstrap.ts` reads from
   * `process.env.BRAIN_WSS_URL`.
   */
  wsRpcUrl: string;
  /**
   * Optional WebSocket constructor override. Tests inject a stub that
   * speaks to a Bun.serve()-backed in-process server; production uses
   * `globalThis.WebSocket` (Bun ships it).
   */
  webSocketCtor?: typeof WebSocket;
  /**
   * RPC timeout in ms. Defaults to 15s — `oddjobz.ratify_proposal` is
   * expected to be fast (no LLM, no network egress beyond local
   * dispatcher), so a generous-but-finite cap protects the operator's
   * REPL from a hung brain.
   */
  timeoutMs?: number;
  /**
   * Optional FS fallback for when WSS is unreachable. When set, any
   * WSS-path failure (connection refused, 503 upgrade failure, timeout,
   * ws_construct_error) falls back to writing JSONL directly into
   * `<fsFallbackDataDir>/oddjobz/{sites,customers,jobs,attachments}.jsonl`
   * in the same shape as brain's typed view-stores. This bypasses the
   * brain process boundary but lands the same on-disk format / trust
   * level the dispatcher → JSONL view-store path produces (D-DOG.1.0c
   * Phase 2A.4).
   *
   * Set this to your Semantos Brain data root (e.g. `~/.semantos/data`). When
   * unset, WSS failures throw `BrainRpcCellWriterError` as before.
   *
   * The fallback is tonight-pragmatic — once brain's tenant manifest
   * scaffolding ships and `brain serve` exposes `/api/v1/wallet` in
   * basic mode, the WSS path becomes the default and this becomes
   * a true emergency mode. The console.warn it emits whenever it
   * fires makes the situation visible to the operator.
   */
  fsFallbackDataDir?: string | null;
  /**
   * Hat id stamped on the fallback path's ratification index (the WSS
   * path passes hat resolution through to brain; the fallback needs to
   * know it directly so the audit trail for fallback-written cells
   * still attributes them).
   */
  fsFallbackHatId?: string | null;
  /**
   * Optional clock-now override (ms since epoch). Used by tests to
   * pin the timestamp in the JSONL `ts` / `created_at` fields and the
   * CellID derivation (job + attachment cellIDs incorporate
   * `created_at`). Defaults to `Date.now()`.
   */
  fsFallbackClock?: () => number;
}

/**
 * Graph-shaped cell ids returned by the new (D-DOG.1.0c Phase 2A.4)
 * `oddjobz.ratify_proposal` handler. One ratify produces a connected
 * graph of cells: an optional site-of-work, the customers contacted
 * about it, the job itself, and any attachments. Each leaf field is a
 * 64-char hex cell id (or null/empty when the SIR didn't carry that
 * facet).
 */
export interface RatifyProposalCellIds {
  readonly site: string | null;
  readonly customers: readonly string[];
  readonly job: string | null;
  readonly attachments: readonly string[];
}

/**
 * Result returned by `BrainRpcCellWriter.invoke` and threaded into the
 * RatificationReceipt's `cellId` field as a JSON-encoded string.
 *
 * The single-string `cellId` shape predates Layer-2 ratification. For
 * Phase 2B.1 we keep the receipt schema unchanged and stringify the
 * full cellIds graph object (Option A from the rollout plan); helm SPA
 * and mobile JobList treat the value as opaque today. Phase 3 (graph-
 * aware UI) is when we promote this to a structured `RatificationReceipt
 * .cellIds` field across receipt-store + helm/mobile readers.
 *
 * TODO(D-DOG.1.0c Phase 3): replace the JSON-encoded-string carry with
 * a structured `cellIds` field on `RatificationReceipt`. Will ripple
 * into `runtime/legacy-ingest/src/ratification-store.ts` and the helm/
 * mobile readers; deferred so this PR's blast radius stays minimal.
 */
export interface RatifyProposalResult {
  readonly proposalId: string;
  readonly cellIds: RatifyProposalCellIds;
  readonly persistedAt: number;
}

export class BrainRpcCellWriterError extends Error {
  constructor(message: string, readonly code: string) {
    super(message);
    this.name = 'BrainRpcCellWriterError';
  }
}

const DEFAULT_TIMEOUT_MS = 15_000;

export class BrainRpcCellWriter {
  private readonly opts: BrainRpcCellWriterOpts;
  private rpcCounter = 0;

  constructor(opts: BrainRpcCellWriterOpts) {
    this.opts = opts;
  }

  /**
   * Implements `RatificationOrchestrator.opts.writeCell`. Returns the
   * JSON-encoded `cellIds` graph object so the existing
   * `RatificationReceipt.cellId` schema (single string) keeps working.
   * Throws `BrainRpcCellWriterError` on transport / protocol failure;
   * the orchestrator wraps that into a `RatificationError` with code
   * `cell_write_error`.
   *
   * D-DOG.1.0c Phase 2B.1 — the encoded value is now an object of the
   * shape `{site, customers, job, attachments}`, not a flat array.
   * Receipt readers that previously parsed it as a string array will
   * see an object instead; today they only surface presence/absence so
   * the change is backward-compatible at the UI level. Phase 3 will
   * promote `RatificationReceipt.cellId` to a structured field.
   *
   * Soft-skip: when the SIR carried only `noop` / `attach_reply`
   * nodes (and the handler therefore minted no cells anywhere in the
   * graph), we still return a stringified empty graph rather than
   * throwing — the proposal status flips to `ratified` either way.
   */
  async write(args: {
    program: SIRProgram;
    proposal: Proposal;
  }): Promise<string> {
    const result = await this.invoke(args.program, args.proposal);
    return JSON.stringify(result.cellIds);
  }

  /**
   * The full ratify dance: open WS, wait for open, send the request,
   * wait for the matching response, close. Single round-trip.
   *
   * If `fsFallbackDataDir` is set and the WSS path fails for ANY
   * reason (construct error, transport error, timeout, server-side
   * 503 upgrade failure surfacing as ws_closed), this method logs a
   * `[brain-rpc] WSS unavailable` warning and routes the write through
   * `fallbackFsWrite` instead of throwing. With `fsFallbackDataDir`
   * unset, the WSS error throws as before.
   */
  async invoke(program: SIRProgram, proposal: Proposal): Promise<RatifyProposalResult> {
    try {
      return await this.invokeWss(program, proposal);
    } catch (err) {
      if (this.opts.fsFallbackDataDir) {
        const reason =
          err instanceof Error ? `${err.name}: ${err.message}` : String(err);
        // eslint-disable-next-line no-console
        console.warn(
          `[brain-rpc] WSS unavailable (${reason}) — falling back to direct FS append at ${this.opts.fsFallbackDataDir}`,
        );
        return this.fallbackFsWrite(program, proposal);
      }
      throw err;
    }
  }

  /**
   * Direct WSS attempt. Separated from `invoke` so the fallback wrapper
   * is a single try/catch around it.
   */
  private async invokeWss(program: SIRProgram, proposal: Proposal): Promise<RatifyProposalResult> {
    const Ctor = this.opts.webSocketCtor ?? globalThis.WebSocket;
    if (typeof Ctor !== 'function') {
      throw new BrainRpcCellWriterError(
        'no WebSocket implementation available (set opts.webSocketCtor or run on Bun/Node ≥21)',
        'no_websocket',
      );
    }
    const id = ++this.rpcCounter;
    const payloadHint = derivePayloadHint(proposal);
    const request = JSON.stringify({
      jsonrpc: '2.0',
      // C4 PR-J5b — ratify is now the generic, namespace-routed substrate
      // primitive. `oddjobz.ratify_proposal` was retired; we send
      // `ratify.submit` with `namespace: 'oddjobz'` (same params otherwise),
      // which the brain routes to the oddjobz graph builder.
      method: 'ratify.submit',
      params: {
        namespace: 'oddjobz',
        proposal_id: proposal.proposalId,
        sir_program: program,
        payload_hint: payloadHint,
      },
      id,
    });

    return await new Promise<RatifyProposalResult>((resolve, reject) => {
      let ws: WebSocket;
      try {
        ws = new Ctor(this.opts.wsRpcUrl);
      } catch (err) {
        reject(
          new BrainRpcCellWriterError(
            `WS construct failed: ${err instanceof Error ? err.message : String(err)}`,
            'ws_construct_error',
          ),
        );
        return;
      }

      let settled = false;
      const finish = (
        outcome: { ok: true; value: RatifyProposalResult } | { ok: false; err: BrainRpcCellWriterError },
      ): void => {
        if (settled) return;
        settled = true;
        try { ws.close(); } catch { /* swallow */ }
        if (outcome.ok) resolve(outcome.value);
        else reject(outcome.err);
      };

      const timeout = setTimeout(() => {
        finish({
          ok: false,
          err: new BrainRpcCellWriterError(
            `ratify.submit timed out after ${this.opts.timeoutMs ?? DEFAULT_TIMEOUT_MS}ms`,
            'timeout',
          ),
        });
      }, this.opts.timeoutMs ?? DEFAULT_TIMEOUT_MS);
      // node/bun: timeouts can be unrefed so they don't keep the loop alive.
      if (typeof (timeout as { unref?: () => void }).unref === 'function') {
        (timeout as { unref: () => void }).unref();
      }
      const wrap = <T>(fn: () => T): T => {
        try { return fn(); } finally { /* keep ordering */ }
      };

      ws.onopen = () => wrap(() => {
        try {
          ws.send(request);
        } catch (err) {
          clearTimeout(timeout);
          finish({
            ok: false,
            err: new BrainRpcCellWriterError(
              `WS send failed: ${err instanceof Error ? err.message : String(err)}`,
              'ws_send_error',
            ),
          });
        }
      });

      ws.onmessage = (event: MessageEvent) => wrap(() => {
        // The brain server sends one response per request id. We treat
        // any frame that doesn't parse OR doesn't carry our id as a
        // protocol error rather than silently skipping — Phase 1.0
        // never multiplexes multiple in-flight requests over one
        // connection (one writer = one fresh socket per ratify).
        let frame: unknown;
        try {
          frame =
            typeof event.data === 'string'
              ? JSON.parse(event.data)
              : JSON.parse(new TextDecoder().decode(event.data as ArrayBuffer));
        } catch (err) {
          clearTimeout(timeout);
          finish({
            ok: false,
            err: new BrainRpcCellWriterError(
              `brain returned non-JSON frame: ${err instanceof Error ? err.message : String(err)}`,
              'protocol_error',
            ),
          });
          return;
        }
        const obj = frame as Record<string, unknown>;
        if (obj.id !== id) {
          // Possibly a server-initiated notification (e.g. helm.event
          // broadcast). Ignore and keep waiting for our response.
          return;
        }
        clearTimeout(timeout);
        if (typeof obj.error === 'object' && obj.error !== null) {
          const errObj = obj.error as Record<string, unknown>;
          finish({
            ok: false,
            err: new BrainRpcCellWriterError(
              `brain error ${errObj.code ?? '?'}: ${errObj.message ?? 'unknown'}`,
              'rpc_error',
            ),
          });
          return;
        }
        const result = obj.result as Record<string, unknown> | undefined;
        if (!result) {
          finish({
            ok: false,
            err: new BrainRpcCellWriterError('brain response missing result', 'protocol_error'),
          });
          return;
        }
        // D-DOG.1.0c Phase 2A.4 — the handler now returns
        // `cellIds: {site, customers, job, attachments}` (graph shape).
        // The legacy flat-array `cell_ids` shape is gone; if the Semantos Brain
        // returns it we surface a protocol error rather than silently
        // accept a stale handler.
        const cellIdsRaw = result.cellIds;
        if (typeof cellIdsRaw !== 'object' || cellIdsRaw === null || Array.isArray(cellIdsRaw)) {
          finish({
            ok: false,
            err: new BrainRpcCellWriterError(
              "brain response missing 'cellIds' graph object {site, customers, job, attachments}",
              'protocol_error',
            ),
          });
          return;
        }
        const parsedCellIds = parseCellIdsGraph(cellIdsRaw as Record<string, unknown>);
        if (!parsedCellIds.ok) {
          finish({
            ok: false,
            err: new BrainRpcCellWriterError(parsedCellIds.error, 'protocol_error'),
          });
          return;
        }
        const proposalIdEcho =
          typeof result.proposal_id === 'string' ? result.proposal_id : proposal.proposalId;
        // The Zig handler emits `persistedAt` (camelCase) per Phase
        // 2A.4; older handlers emitted `persisted_at` (snake_case).
        // Accept both for forward/backward compat — preferring the new
        // shape when both somehow appear.
        const persistedAtRaw =
          typeof result.persistedAt === 'number'
            ? result.persistedAt
            : typeof result.persisted_at === 'number'
              ? result.persisted_at
              : Date.now();
        finish({
          ok: true,
          value: {
            proposalId: proposalIdEcho,
            cellIds: parsedCellIds.value,
            persistedAt: persistedAtRaw,
          },
        });
      });

      ws.onerror = () => wrap(() => {
        clearTimeout(timeout);
        finish({
          ok: false,
          err: new BrainRpcCellWriterError(
            `WS error talking to ${this.opts.wsRpcUrl}`,
            'ws_error',
          ),
        });
      });

      ws.onclose = (event: CloseEvent) => wrap(() => {
        if (settled) return;
        clearTimeout(timeout);
        finish({
          ok: false,
          err: new BrainRpcCellWriterError(
            `WS closed before response (code=${event.code} reason=${event.reason || 'none'})`,
            'ws_closed',
          ),
        });
      });
    });
  }

  /**
   * Direct-FS fallback path. Mirrors what `oddjobz_ratify_handler.zig`
   * does in Zig — walks the proposal's payload_hint into a graph of
   * cells (site → customers → job → attachments), appends each to its
   * typed JSONL view-store at `<fsFallbackDataDir>/oddjobz/<type>.jsonl`,
   * and returns the connected graph of cellIDs.
   *
   * D-DOG.1.0c Phase 2B.2 — replaces the Phase 2B.1 single-flat-row
   * shape. The on-disk shapes match what the Zig view-stores
   * (sites_store_fs.zig / customers_store_fs.zig:appendCreatedV2Line /
   * jobs_store_fs.zig:appendCreatedV2Line / attachments_store_fs.zig:
   * appendV2Line) produce.
   *
   * Idempotency: an in-process index file at
   * `<fsFallbackDataDir>/oddjobz/legacy-ratifications.jsonl` records
   * `{proposal_id, cellIds:{site,customers,job,attachments},
   * persisted_at}` per ratify and is replayed on every fallback call so
   * a re-ratify of the same proposal id returns the previously-minted
   * cellIDs without re-walking or re-appending. Matches
   * `Handler.handleRatify`'s per-proposal idempotency contract
   * (separate file from brain's own `ratifications.jsonl` so the two
   * paths don't trample each other's headers).
   *
   * Per-cell dedupe (within one ratify):
   *   • Site by lookupKey (normalisedAddress + '|' + keyNumber-or-empty)
   *     — read `sites.jsonl`, find existing match → reuse cellID; else
   *     mint and append.
   *   • Customer by phone → email → name+role+site exact match — TS
   *     side uses STRICT byte-equal exact matching (no fuzzy / no E.164
   *     normaliser). The matrix's R2 row says fuzzy is deferred; this
   *     mirrors the Zig handler's posture.
   *   • Job: always fresh (a re-ratify with same SIR at a different
   *     wall-clock time produces a new job — Zig handler's documented
   *     semantic, and the per-proposal cache above catches the
   *     idempotent re-ratify case anyway).
   *   • Attachment: always fresh, one per source PDF.
   *
   * CellID generation (Zig parity):
   *   site:        SHA-256("oddjobz.site.v2|"        + normalised + "|" + keyNumber + "|" + fullAddress)
   *   customer:    SHA-256("oddjobz.customer.v2|"    + name + "|" + role + "|" + siteCellId(32 bytes) + "|" + phone + "|" + email)
   *   job:         SHA-256("oddjobz.job.v2|"         + siteCellId(32) + "|" + customerRefs-encoded + "|" + workOrderNumber + "|" + issuanceDate + "|" + dueDate + "|" + displayName + "|" + createdAt)
   *   attachment:  SHA-256("oddjobz.attachment.v2|"  + jobCellId(32) + "|" + sourceAttachmentPath + "|" + createdAt)
   *
   * The customer cellID's siteCellId, the job's siteCellId and
   * customerRefs[].cellId, and the attachment's jobCellId are fed in as
   * RAW 32-byte buffers (NOT hex). This mirrors `hasher.update(&site_cell_id)`
   * in `oddjobz_ratify_handler.zig:1236`.
   *
   * The customer.v2 schema's `customerId: assertUuid(...)` requirement
   * is satisfied via a deterministic UUID v4-shape derived from the
   * cellID's first 16 bytes (mirrors Zig's `uuidV5LikeFromBytes`).
   */
  private fallbackFsWrite(
    program: SIRProgram,
    proposal: Proposal,
  ): RatifyProposalResult {
    const dataDir = this.opts.fsFallbackDataDir;
    if (!dataDir) {
      // Defensive — caller checks fsFallbackDataDir before invoking.
      throw new BrainRpcCellWriterError(
        'fallbackFsWrite called with no fsFallbackDataDir',
        'fallback_misconfigured',
      );
    }
    const oddjobzDir = join(dataDir, 'oddjobz');
    mkdirSync(oddjobzDir, { recursive: true });

    const indexPath = join(oddjobzDir, 'legacy-ratifications.jsonl');
    const existing = readFallbackIndex(indexPath, proposal.proposalId);
    if (existing) {
      return {
        proposalId: proposal.proposalId,
        cellIds: existing.cellIds,
        persistedAt: existing.persistedAt,
      };
    }

    // Whether this SIR contains any ratifiable action at all. A pure
    // noop / attach_reply SIR persists an empty graph (no cells) so
    // the proposal_id stays idempotent — re-ratifying returns "no
    // cells" rather than re-walking.
    const nodes = Array.isArray((program as { nodes?: unknown }).nodes)
      ? ((program as { nodes: unknown[] }).nodes)
      : [];
    let hasRatifiable = false;
    for (const node of nodes) {
      if (typeof node !== 'object' || node === null) continue;
      const action = (node as { action?: unknown }).action;
      if (typeof action !== 'string') continue;
      if (isRatifiableAction(action)) {
        hasRatifiable = true;
        break;
      }
    }

    const clock = this.opts.fsFallbackClock ?? (() => Date.now());
    const persistedAt = clock();
    const sitesPath = join(oddjobzDir, 'sites.jsonl');
    const customersPath = join(oddjobzDir, 'customers.jsonl');
    const jobsPath = join(oddjobzDir, 'jobs.jsonl');
    const attachmentsPath = join(oddjobzDir, 'attachments.jsonl');

    let graph: RatifyProposalCellIds = { site: null, customers: [], job: null, attachments: [] };

    if (hasRatifiable) {
      graph = buildGraphAndAppend({
        proposal,
        persistedAt,
        sitesPath,
        customersPath,
        jobsPath,
        attachmentsPath,
      });
    }

    // Persist the idempotency index AFTER the per-store appends so a
    // crash mid-write doesn't leave the index claiming cells exist
    // that never landed (the operator would re-ratify and end up with
    // no cells; better than a duplicate).
    const indexLine = JSON.stringify({
      proposal_id: proposal.proposalId,
      hat_id: this.opts.fsFallbackHatId ?? null,
      cellIds: graph,
      persisted_at: persistedAt,
    });
    appendFileSync(indexPath, `${indexLine}\n`);

    return {
      proposalId: proposal.proposalId,
      cellIds: graph,
      persistedAt,
    };
  }
}

/**
 * Mirrors `oddjobz_ratify_handler.zig::isRatifiableAction`. SIR-node
 * actions the EmailExtractor emits that translate to a fresh oddjobz
 * cell today. `noop` and `attach_reply` are intentionally omitted —
 * they belong on the proposal review queue but don't mint cells.
 *
 * Phase 2B.2 extends the recognised set with the Tier 1.7 actions
 * (`create_work_order`, `create_maintenance_order`) the EmailExtractor
 * v0.5 emits — `mapJobTypeToAction` in extractor/email.ts produces
 * these for `job_type === 'work_order' / 'maintenance_order'`. The
 * Zig-side `isRatifiableAction` will pick these up in the next brain
 * release; until then the WSS path stays a no-op for these actions
 * and the FS fallback is the only path that lands them as cells.
 */
function isRatifiableAction(action: string): boolean {
  return (
    action === 'create_lead' ||
    action === 'create_quote_request' ||
    action === 'create_work_order' ||
    action === 'create_maintenance_order' ||
    action === 'create_booking' ||
    action === 'log_inquiry'
  );
}

interface FallbackIndexEntry {
  cellIds: RatifyProposalCellIds;
  persistedAt: number;
}

/**
 * Replay the legacy-ratifications.jsonl index file looking for an
 * existing record for `proposalId`. Returns the most-recent matching
 * record or null. Best-effort: malformed lines are skipped (forward-
 * compat — same posture as `oddjobz_ratify_handler.zig::replay`).
 *
 * Phase 2B.2 — the index now stores the GRAPH-shaped cellIds object
 * (`{site, customers, job, attachments}`) under the `cellIds` key.
 * Pre-Phase-2B.2 entries used a flat `cell_ids` array; we still parse
 * those for forward-compat (lifting the array onto `cellIds.job` when
 * a single id, else `cellIds.customers` as a degenerate fan-out — same
 * bridge as Phase 2B.1's `legacyJobIdsToGraph`).
 */
function readFallbackIndex(path: string, proposalId: string): FallbackIndexEntry | null {
  if (!existsSync(path)) return null;
  let raw: string;
  try {
    raw = readFileSync(path, 'utf8');
  } catch {
    return null;
  }
  let found: FallbackIndexEntry | null = null;
  for (const line of raw.split('\n')) {
    if (line.length === 0) continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    if (typeof parsed !== 'object' || parsed === null) continue;
    const obj = parsed as Record<string, unknown>;
    if (obj.proposal_id !== proposalId) continue;
    const persistedAt = typeof obj.persisted_at === 'number' ? obj.persisted_at : Date.now();

    // Graph-shaped index entry (Phase 2B.2 onwards).
    const cellIdsRaw = obj.cellIds;
    if (typeof cellIdsRaw === 'object' && cellIdsRaw !== null && !Array.isArray(cellIdsRaw)) {
      const parsedGraph = parseCellIdsGraph(cellIdsRaw as Record<string, unknown>);
      if (parsedGraph.ok) {
        found = { cellIds: parsedGraph.value, persistedAt };
        continue;
      }
    }
    // Legacy flat-array shape (pre-Phase-2B.2).
    const cellsRaw = obj.cell_ids;
    if (Array.isArray(cellsRaw)) {
      const cellIds: string[] = [];
      let ok = true;
      for (const c of cellsRaw) {
        if (typeof c !== 'string') { ok = false; break; }
        cellIds.push(c);
      }
      if (ok) {
        found = { cellIds: legacyJobIdsToGraph(cellIds), persistedAt };
      }
    }
  }
  return found;
}

/**
 * One contact in the payload_hint. Mirrors `ContactInput` in
 * `oddjobz_ratify_handler.zig` exactly — `name` is required, the
 * other three optional. The Zig parser (parseContact) reads
 * `optString(obj, "phone")` / `"email"`, so we send `null` rather than
 * omitting when absent so the wire shape is unambiguous.
 */
interface PayloadHintContact {
  name: string;
  role: string;
  phone: string | null;
  email: string | null;
}

/** Billing-party node — matches `parsePayloadHint`'s `billingParty`. */
interface PayloadHintBillingParty {
  type: string;
  name: string;
}

/**
 * The full payload_hint envelope. Field naming is split deliberately:
 * the legacy 5 are snake_case (kept for backward-compat with any brain
 * handler that hasn't pulled the Phase 2A.4 rewrite); the Tier 1.7
 * fields are camelCase to match the keys `oddjobz_ratify_handler.zig`
 * `parsePayloadHint` reads (`propertyAddress`, `primaryContact`, ...).
 */
export interface PayloadHint {
  // Legacy 5 (snake_case — preserved exactly for backward-compat).
  customer_name: string;
  point_of_contact: string;
  summary: string;
  reference_number: string;
  source_provider_id: string;
  // Tier 1.7 enriched (camelCase — must match Zig's parsePayloadHint
  // keys byte-for-byte). Each field is optional on the proposal; when
  // absent we omit it from the wire JSON so the Zig handler falls back
  // to its zero-value for the field.
  primaryContact?: PayloadHintContact;
  secondaryContacts?: PayloadHintContact[];
  ownerName?: string;
  billingParty?: PayloadHintBillingParty;
  propertyAddress?: string;
  propertyKey?: string;
  workOrderNumber?: string;
  issuanceDate?: string;
  dueDate?: string;
  hasPhotos?: boolean;
  photoCount?: number;
  sourceAttachmentPath?: string;
}

/**
 * Distil the proposal into a side-channel hint the Semantos Brain handler reads
 * to fill cell fields the SIRProgram itself doesn't currently carry.
 *
 * D-DOG.1.0c Phase 2B.1 — extended from the legacy 5-field shape
 * (customer_name / point_of_contact / summary / reference_number /
 * source_provider_id) to forward the Tier 1.7 enriched fields
 * (primaryContact / secondaryContacts / ownerName / billingParty /
 * propertyAddress / propertyKey / workOrderNumber / issuanceDate /
 * dueDate / hasPhotos / photoCount / sourceAttachmentPath).
 *
 * Field names match `oddjobz_ratify_handler.zig::parsePayloadHint`
 * keys exactly; the Zig handler is the source of truth for the wire
 * format. Tier 1.7 fields use camelCase; legacy 5 stay snake_case for
 * backward-compat.
 *
 * Older proposals (extracted before Tier 1.7 landed) lack these
 * fields entirely — the function omits them from the wire JSON in
 * that case and the Zig handler falls back gracefully (each Tier 1.7
 * branch in parsePayloadHint is gated on `obj.get("...")`).
 */
export function derivePayloadHint(proposal: Proposal): PayloadHint {
  // First line of the summary truncated to 200 chars stands in as the
  // legacy customer_name. Kept alongside the new point_of_contact so
  // the Semantos Brain handler / FS fallback can still resolve a name even when
  // the LLM didn't emit point_of_contact (older proposals; LLM miss).
  const firstLine = proposal.summary.split(/\r?\n/)[0] ?? proposal.summary;
  const customerName = firstLine.trim().slice(0, 200) || '(untitled lead)';
  // The new field — the agency / agent / PM the operator talks to.
  // The Zig handler and the FS fallback prefer this when present;
  // when absent we send '' so the Semantos Brain handler can fall through to
  // customer_name without an `undefined`-shaped JSON serialisation.
  const pointOfContact = proposal.pointOfContact?.trim().slice(0, 200) ?? '';

  const hint: PayloadHint = {
    customer_name: customerName,
    point_of_contact: pointOfContact,
    summary: proposal.summary.slice(0, 4000),
    reference_number: proposal.referenceNumber ?? '',
    source_provider_id: proposal.provenance.providerId,
  };

  // Tier 1.7 — only set fields when the proposal carries them, so
  // legacy proposals (pre-Tier-1.7 extractor versions) round-trip with
  // an envelope identical to the pre-Phase-2B.1 shape.
  const primary = normaliseHintContact(proposal.primaryContact);
  if (primary) hint.primaryContact = primary;

  if (proposal.secondaryContacts && proposal.secondaryContacts.length > 0) {
    const secondary: PayloadHintContact[] = [];
    for (const c of proposal.secondaryContacts) {
      const n = normaliseHintContact(c);
      if (n) secondary.push(n);
    }
    if (secondary.length > 0) hint.secondaryContacts = secondary;
  }

  if (typeof proposal.ownerName === 'string' && proposal.ownerName.length > 0) {
    hint.ownerName = proposal.ownerName;
  }

  if (proposal.billingParty) {
    hint.billingParty = {
      type: proposal.billingParty.type,
      name: proposal.billingParty.name,
    };
  }

  if (typeof proposal.propertyAddress === 'string' && proposal.propertyAddress.length > 0) {
    hint.propertyAddress = proposal.propertyAddress;
  }
  if (typeof proposal.propertyKey === 'string' && proposal.propertyKey.length > 0) {
    hint.propertyKey = proposal.propertyKey;
  }
  if (typeof proposal.workOrderNumber === 'string' && proposal.workOrderNumber.length > 0) {
    hint.workOrderNumber = proposal.workOrderNumber;
  }
  if (typeof proposal.issuanceDate === 'string' && proposal.issuanceDate.length > 0) {
    hint.issuanceDate = proposal.issuanceDate;
  }
  if (typeof proposal.dueDate === 'string' && proposal.dueDate.length > 0) {
    hint.dueDate = proposal.dueDate;
  }
  if (typeof proposal.hasPhotos === 'boolean') {
    hint.hasPhotos = proposal.hasPhotos;
  }
  if (typeof proposal.photoCount === 'number' && proposal.photoCount >= 0) {
    hint.photoCount = proposal.photoCount;
  }
  if (typeof proposal.sourceAttachmentPath === 'string' && proposal.sourceAttachmentPath.length > 0) {
    hint.sourceAttachmentPath = proposal.sourceAttachmentPath;
  }

  return hint;
}

/**
 * Coerce a `ProposalContact | null | undefined` into a wire-shape
 * `PayloadHintContact`. Returns null when the input is missing, has no
 * name, or is otherwise invalid — the Zig parser drops contacts with
 * empty names too (`parseContact` returns null in that branch).
 */
function normaliseHintContact(
  c: { name: string; role: string; phone: string | null; email: string | null } | null | undefined,
): PayloadHintContact | null {
  if (!c) return null;
  if (typeof c.name !== 'string' || c.name.length === 0) return null;
  return {
    name: c.name,
    role: c.role,
    phone: c.phone ?? null,
    email: c.email ?? null,
  };
}

/**
 * Validate + extract a `cellIds` graph object out of a parsed JSON-RPC
 * `result`. The Zig handler always emits all four keys (with the
 * scalars nullable and the arrays possibly empty), so anything else is
 * a protocol error.
 */
function parseCellIdsGraph(
  obj: Record<string, unknown>,
): { ok: true; value: RatifyProposalCellIds } | { ok: false; error: string } {
  const siteRaw = obj.site;
  let site: string | null;
  if (siteRaw === null || siteRaw === undefined) {
    site = null;
  } else if (typeof siteRaw === 'string') {
    site = siteRaw;
  } else {
    return { ok: false, error: "'cellIds.site' must be string or null" };
  }

  const jobRaw = obj.job;
  let job: string | null;
  if (jobRaw === null || jobRaw === undefined) {
    job = null;
  } else if (typeof jobRaw === 'string') {
    job = jobRaw;
  } else {
    return { ok: false, error: "'cellIds.job' must be string or null" };
  }

  const customers = stringArray(obj.customers);
  if (!customers.ok) return { ok: false, error: `'cellIds.customers': ${customers.error}` };
  const attachments = stringArray(obj.attachments);
  if (!attachments.ok) return { ok: false, error: `'cellIds.attachments': ${attachments.error}` };

  return {
    ok: true,
    value: {
      site,
      customers: customers.value,
      job,
      attachments: attachments.value,
    },
  };
}

function stringArray(
  v: unknown,
): { ok: true; value: string[] } | { ok: false; error: string } {
  if (!Array.isArray(v)) return { ok: false, error: 'must be an array' };
  const out: string[] = [];
  for (const item of v) {
    if (typeof item !== 'string') return { ok: false, error: 'must contain only strings' };
    out.push(item);
  }
  return { ok: true, value: out };
}

/**
 * Pre-Phase-2B.2 forward-compat bridge: lift a flat array of cellIDs
 * (the old idempotency-index shape) onto the graph (single id → job;
 * many → customers as degenerate fan-out). Only used when replaying a
 * legacy `legacy-ratifications.jsonl` file that pre-dates the
 * graph-shaped index format.
 */
function legacyJobIdsToGraph(ids: readonly string[]): RatifyProposalCellIds {
  if (ids.length === 0) {
    return { site: null, customers: [], job: null, attachments: [] };
  }
  if (ids.length === 1) {
    return { site: null, customers: [], job: ids[0]!, attachments: [] };
  }
  return { site: null, customers: [...ids], job: null, attachments: [] };
}

// ─── Graph build (Phase 2B.2) ─────────────────────────────────────────

/**
 * Mirror of site.v2.ts `normaliseAddress` — lowercase + collapse
 * whitespace + trim. Re-implemented here (rather than imported from
 * `cartridges/oddjobz/brain`) so the legacy-ingest package stays unbloated;
 * the byte-equality is asserted by Phase 2B.4's parity oracle.
 */
function normaliseAddress(input: string): string {
  return input.toLowerCase().replace(/\s+/g, ' ').trim();
}

/** Mirror of site.v2.ts `deriveLookupKey`. */
function deriveLookupKey(normalisedAddress: string, keyNumber: string | null): string {
  return `${normalisedAddress}|${keyNumber ?? ''}`;
}

/** Inputs to `buildGraphAndAppend`. */
interface BuildGraphArgs {
  proposal: Proposal;
  persistedAt: number;
  sitesPath: string;
  customersPath: string;
  jobsPath: string;
  attachmentsPath: string;
}

/**
 * Walk the proposal's payload-derived fields into a graph of cells and
 * append each to its typed JSONL view-store. Returns the connected
 * graph of cellIDs.
 */
function buildGraphAndAppend(args: BuildGraphArgs): RatifyProposalCellIds {
  const { proposal, persistedAt, sitesPath, customersPath, jobsPath, attachmentsPath } = args;

  // Re-use derivePayloadHint so the FS-fallback graph build sees the
  // same field shape the WSS handler does — the on-the-wire envelope
  // and the on-disk graph stay congruent.
  const hint = derivePayloadHint(proposal);

  // ── Site lookup-or-mint ────────────────────────────────────────────
  // Site address priority: propertyAddress → customer_name (legacy
  // fallback). Same posture as `buildGraph` in
  // oddjobz_ratify_handler.zig:530.
  const siteFullAddress =
    (typeof hint.propertyAddress === 'string' && hint.propertyAddress.length > 0)
      ? hint.propertyAddress
      : hint.customer_name;
  const siteNormalised = normaliseAddress(siteFullAddress);
  const propertyKey = (typeof hint.propertyKey === 'string' && hint.propertyKey.length > 0)
    ? hint.propertyKey
    : null;
  const siteLookupKey = deriveLookupKey(siteNormalised, propertyKey);

  let siteCellIdBytes = findSiteCellIdByLookupKey(sitesPath, siteLookupKey);
  if (!siteCellIdBytes) {
    siteCellIdBytes = computeSiteCellId(siteNormalised, propertyKey, siteFullAddress);
    appendSiteRow({
      path: sitesPath,
      ts: persistedAt,
      cellId: siteCellIdBytes,
      typeHash: ODDJOBZ_TYPE_HASH_SITE,
      normalisedAddress: siteNormalised,
      keyNumber: propertyKey,
      lookupKey: siteLookupKey,
      fullAddress: siteFullAddress,
      createdAt: persistedAt,
    });
  }
  const siteCellIdHex = bytesToHex(siteCellIdBytes);

  // ── Customer lookup-or-mint (primary + secondaries) ────────────────
  const createdAtStr = String(persistedAt);
  const providerId = (hint.source_provider_id.length > 0) ? hint.source_provider_id : 'unknown';
  const providerItemId = (hint.reference_number.length > 0) ? hint.reference_number : 'ratify';

  type CustomerRef = { cellIdBytes: Buffer; cellIdHex: string; role: string; primary: boolean };
  const customerRefs: CustomerRef[] = [];

  const synthesisedPrimary: PayloadHintContact | null =
    hint.primaryContact
      ?? (
        // Legacy fallback: synthesise a primary from
        // point_of_contact / customer_name (Phase 1.0 LLM shape).
        (hint.point_of_contact.length > 0 || hint.customer_name.length > 0)
          ? {
            name: (hint.point_of_contact.length > 0) ? hint.point_of_contact : hint.customer_name,
            role: 'agent',
            phone: null,
            email: null,
          }
          : null
      );

  if (synthesisedPrimary) {
    const ref = lookupOrMintCustomer({
      path: customersPath,
      contact: synthesisedPrimary,
      primary: true,
      siteCellIdBytes,
      ts: persistedAt,
      providerId,
      providerItemId,
      createdAtStr,
    });
    customerRefs.push(ref);
  }

  if (hint.secondaryContacts) {
    for (const sc of hint.secondaryContacts) {
      const ref = lookupOrMintCustomer({
        path: customersPath,
        contact: sc,
        primary: false,
        siteCellIdBytes,
        ts: persistedAt,
        providerId,
        providerItemId,
        createdAtStr,
      });
      customerRefs.push(ref);
    }
  }

  // ── Job mint (always fresh) ────────────────────────────────────────
  const jobDisplayName: string =
    (hint.point_of_contact.length > 0)
      ? hint.point_of_contact
      : (hint.customer_name.length > 0)
        ? hint.customer_name
        : '(untitled lead)';
  const jobCellIdBytes = computeJobCellId({
    siteCellIdBytes,
    customerRefs: customerRefs.map(r => ({
      cellIdBytes: r.cellIdBytes,
      role: r.role,
      primary: r.primary,
    })),
    workOrderNumber: hint.workOrderNumber ?? '',
    issuanceDate: hint.issuanceDate ?? '',
    dueDate: hint.dueDate ?? '',
    createdAt: createdAtStr,
    displayName: jobDisplayName,
  });
  appendJobRow({
    path: jobsPath,
    ts: persistedAt,
    cellId: jobCellIdBytes,
    typeHash: ODDJOBZ_TYPE_HASH_JOB,
    customerName: jobDisplayName,
    state: 'lead',
    scheduledAt: '',
    createdAt: createdAtStr,
    workOrderNumber: hint.workOrderNumber && hint.workOrderNumber.length > 0 ? hint.workOrderNumber : null,
    issuanceDate: hint.issuanceDate && hint.issuanceDate.length > 0 ? hint.issuanceDate : null,
    dueDate: hint.dueDate && hint.dueDate.length > 0 ? hint.dueDate : null,
    billingParty: hint.billingParty ?? null,
    hasPhotos: hint.hasPhotos === true,
    photoCount: typeof hint.photoCount === 'number' ? hint.photoCount : null,
    propertyKey,
    siteRef: siteCellIdBytes,
    customerRefs: customerRefs.map(r => ({
      cellIdBytes: r.cellIdBytes,
      role: r.role,
      primary: r.primary,
    })),
    attachmentRefs: [],
  });
  const jobCellIdHex = bytesToHex(jobCellIdBytes);

  // ── Attachment mint (one per source PDF, optional) ─────────────────
  const attachmentCellIdHexes: string[] = [];
  if (typeof hint.sourceAttachmentPath === 'string' && hint.sourceAttachmentPath.length > 0) {
    const attCellIdBytes = computeAttachmentCellId(
      jobCellIdBytes,
      hint.sourceAttachmentPath,
      createdAtStr,
    );
    const attUuid = uuidV5LikeFromBytes(attCellIdBytes);
    appendAttachmentRow({
      path: attachmentsPath,
      ts: persistedAt,
      id: attUuid,
      visit_id: '',
      kind_field: '',
      content_hash: '',
      content_size: 0,
      mime_type: 'application/pdf',
      captured_at: '',
      captured_by_cert_id: '',
      caption: '',
      created_at: createdAtStr,
      cellId: attCellIdBytes,
      typeHash: ODDJOBZ_TYPE_HASH_ATTACHMENT,
      jobRef: jobCellIdBytes,
      sourceBlobKey: hint.sourceAttachmentPath,
      pageCount: null,
      photoCount: typeof hint.photoCount === 'number' ? hint.photoCount : null,
      hasPhotos: hint.hasPhotos === true,
    });
    attachmentCellIdHexes.push(bytesToHex(attCellIdBytes));
  }

  return {
    site: siteCellIdHex,
    customers: customerRefs.map(r => r.cellIdHex),
    job: jobCellIdHex,
    attachments: attachmentCellIdHexes,
  };
}

/**
 * Look up a site by lookupKey by scanning sites.jsonl line-by-line.
 * Returns the cellId (32-byte buffer) of the matching row or null.
 *
 * O(n) for n=site rows. Acceptable in fallback mode — the operator's
 * site count is single-thousands at most. The Zig store has a hashmap
 * index; the FS fallback is intentionally simpler.
 */
function findSiteCellIdByLookupKey(path: string, lookupKey: string): Buffer | null {
  if (!existsSync(path)) return null;
  let raw: string;
  try {
    raw = readFileSync(path, 'utf8');
  } catch {
    return null;
  }
  for (const line of raw.split('\n')) {
    if (line.length === 0) continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    if (typeof parsed !== 'object' || parsed === null) continue;
    const obj = parsed as Record<string, unknown>;
    if (obj.kind !== 'created') continue;
    if (obj.lookupKey !== lookupKey) continue;
    const cellIdHex = obj.cellId;
    if (typeof cellIdHex !== 'string' || cellIdHex.length !== 64) continue;
    try {
      return Buffer.from(cellIdHex, 'hex');
    } catch {
      continue;
    }
  }
  return null;
}

interface LookupOrMintCustomerArgs {
  path: string;
  contact: PayloadHintContact;
  primary: boolean;
  siteCellIdBytes: Buffer;
  ts: number;
  providerId: string;
  providerItemId: string;
  createdAtStr: string;
}

/**
 * Lookup-or-mint one customer cell. TS-side dedupe ladder mirrors
 * Zig's: phone exact → email exact → name+role+site exact (TS keeps
 * STRICT byte-equal matching; no E.164 normaliser, no fuzzy match).
 *
 * The matrix's R2 risk note says fuzzy customer dedupe is deferred to
 * a confirm-on-first-use prompt in helm; this PR's fallback path
 * matches that posture.
 */
function lookupOrMintCustomer(
  args: LookupOrMintCustomerArgs,
): { cellIdBytes: Buffer; cellIdHex: string; role: string; primary: boolean } {
  const { path, contact, primary, siteCellIdBytes, ts, providerId, providerItemId, createdAtStr } = args;
  const role = contact.role;
  const phone = contact.phone ?? '';
  const email = contact.email ?? '';
  const siteHex = bytesToHex(siteCellIdBytes);

  const existing = findCustomerByDedupeLadder({
    path,
    phone,
    email,
    name: contact.name,
    role,
    siteHex,
  });
  if (existing) {
    return { cellIdBytes: existing, cellIdHex: bytesToHex(existing), role, primary };
  }

  const cellIdBytes = computeCustomerCellId(
    contact.name,
    role,
    siteCellIdBytes,
    phone,
    email,
  );
  // Deterministic UUID v4-shape derived from the cellId so the
  // customer.v2 schema's `customerId: assertUuid(...)` constraint is
  // met AND the value is reproducible across replays.
  const customerUuid = uuidV5LikeFromBytes(cellIdBytes);
  appendCustomerRow({
    path,
    ts,
    id: customerUuid,
    display_name: contact.name,
    phone,
    email,
    address: '',
    notes: '',
    created_at: createdAtStr,
    cellId: cellIdBytes,
    typeHash: ODDJOBZ_TYPE_HASH_CUSTOMER,
    role,
    normalisedPhone: phone.length > 0 ? phone : null,
    sourceProvenance: {
      providerId,
      providerItemId,
      extractedAt: createdAtStr,
    },
    siteRef: siteCellIdBytes,
  });
  return { cellIdBytes, cellIdHex: bytesToHex(cellIdBytes), role, primary };
}

/**
 * Walk customers.jsonl line-by-line looking for an existing customer
 * matching one of the dedupe ladder steps (phone → email → name+role+
 * site). Returns the cellId bytes of the first match, or null.
 *
 * Skips rows without `cellId` (legacy v1 rows) and rows that don't
 * carry the v2 graph-aware fields.
 */
function findCustomerByDedupeLadder(args: {
  path: string;
  phone: string;
  email: string;
  name: string;
  role: string;
  siteHex: string;
}): Buffer | null {
  if (!existsSync(args.path)) return null;
  let raw: string;
  try {
    raw = readFileSync(args.path, 'utf8');
  } catch {
    return null;
  }
  // Pre-pass 1: phone match (highest precedence).
  // Pre-pass 2: email match.
  // Pre-pass 3: name+role+site match.
  // Single forward walk records candidates per pass; we return the
  // first phone-pass hit, else first email-pass hit, else first
  // triple-pass hit. Mirrors `findByDedupeKey`'s precedence in
  // customers_store_fs.zig.
  let phoneHit: Buffer | null = null;
  let emailHit: Buffer | null = null;
  let tripleHit: Buffer | null = null;

  for (const line of raw.split('\n')) {
    if (line.length === 0) continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    if (typeof parsed !== 'object' || parsed === null) continue;
    const obj = parsed as Record<string, unknown>;
    if (obj.kind !== 'created') continue;
    const cellIdHex = obj.cellId;
    if (typeof cellIdHex !== 'string' || cellIdHex.length !== 64) continue;
    const stored = (() => {
      try { return Buffer.from(cellIdHex, 'hex'); } catch { return null; }
    })();
    if (!stored) continue;

    if (!phoneHit && args.phone.length > 0) {
      const np = obj.normalisedPhone;
      if (typeof np === 'string' && np.length > 0 && np === args.phone) {
        phoneHit = stored;
      }
    }
    if (!emailHit && args.email.length > 0) {
      const e = obj.email;
      if (typeof e === 'string' && e.length > 0 && e === args.email) {
        emailHit = stored;
      }
    }
    if (!tripleHit && args.name.length > 0) {
      const dn = obj.display_name;
      const r = obj.role;
      const sr = obj.siteRef;
      if (
        typeof dn === 'string'
        && dn === args.name
        && typeof r === 'string'
        && r === args.role
        && typeof sr === 'string'
        && sr === args.siteHex
      ) {
        tripleHit = stored;
      }
    }
  }
  return phoneHit ?? emailHit ?? tripleHit;
}

// ─── JSONL row builders ───────────────────────────────────────────────
//
// Each helper mirrors the corresponding Zig store's
// `appendCreated{,V2}Line` byte-for-byte for the fields they share,
// modulo:
//   • The `ts` field is a JS `Date.now()`-shaped millisecond integer
//     (Zig also writes ms via `self.clock()` in the `create_at`
//     stamps, which the operator's `brain serve` wires from
//     `realClock()`). Both are JSON integers; the units agree.
//   • Hex byte fields are written as 64-char lowercase hex (matching
//     Zig's `std.fmt.bytesToHex(.., .lower)`).
//   • String escaping uses JSON.stringify, which produces the same
//     escape rules Zig's `std.json.Stringify.valueAlloc` emits (both
//     escape \" \\ control chars; do NOT escape /; use \uXXXX for
//     other controls).

function appendSiteRow(args: {
  path: string;
  ts: number;
  cellId: Buffer;
  typeHash: Buffer;
  normalisedAddress: string;
  keyNumber: string | null;
  lookupKey: string;
  fullAddress: string;
  createdAt: number;
}): void {
  const obj = {
    ts: args.ts,
    kind: 'created',
    cellId: bytesToHex(args.cellId),
    typeHash: bytesToHex(args.typeHash),
    normalisedAddress: args.normalisedAddress,
    keyNumber: args.keyNumber,
    lookupKey: args.lookupKey,
    fullAddress: args.fullAddress,
    suburb: null,
    postcode: null,
    state: null,
    signedBy: null,
    signature: null,
    createdAt: args.createdAt,
  };
  appendFileSync(args.path, `${JSON.stringify(obj)}\n`);
}

function appendCustomerRow(args: {
  path: string;
  ts: number;
  id: string;
  display_name: string;
  phone: string;
  email: string;
  address: string;
  notes: string;
  created_at: string;
  cellId: Buffer;
  typeHash: Buffer;
  role: string;
  normalisedPhone: string | null;
  sourceProvenance: { providerId: string; providerItemId: string; extractedAt: string };
  siteRef: Buffer | null;
}): void {
  const obj = {
    ts: args.ts,
    kind: 'created',
    id: args.id,
    display_name: args.display_name,
    phone: args.phone,
    email: args.email,
    address: args.address,
    notes: args.notes,
    created_at: args.created_at,
    cellId: bytesToHex(args.cellId),
    typeHash: bytesToHex(args.typeHash),
    role: args.role,
    normalisedPhone: args.normalisedPhone,
    sourceProvenance: args.sourceProvenance,
    siteRef: args.siteRef ? bytesToHex(args.siteRef) : null,
  };
  appendFileSync(args.path, `${JSON.stringify(obj)}\n`);
}

function appendJobRow(args: {
  path: string;
  ts: number;
  cellId: Buffer;
  typeHash: Buffer;
  customerName: string;
  state: string;
  scheduledAt: string;
  createdAt: string;
  workOrderNumber: string | null;
  issuanceDate: string | null;
  dueDate: string | null;
  billingParty: { type: string; name: string } | null;
  hasPhotos: boolean;
  photoCount: number | null;
  propertyKey: string | null;
  siteRef: Buffer;
  customerRefs: Array<{ cellIdBytes: Buffer; role: string; primary: boolean }>;
  attachmentRefs: Buffer[];
}): void {
  const obj = {
    ts: args.ts,
    kind: 'created',
    id: bytesToHex(args.cellId),
    typeHash: bytesToHex(args.typeHash),
    customer_name: args.customerName,
    state: args.state,
    scheduled_at: args.scheduledAt,
    created_at: args.createdAt,
    workOrderNumber: args.workOrderNumber,
    issuanceDate: args.issuanceDate,
    dueDate: args.dueDate,
    billingParty: args.billingParty,
    hasPhotos: args.hasPhotos,
    photoCount: args.photoCount,
    propertyKey: args.propertyKey,
    siteRef: bytesToHex(args.siteRef),
    customerRefs: args.customerRefs.map(r => ({
      cellId: bytesToHex(r.cellIdBytes),
      role: r.role,
      primary: r.primary,
    })),
    attachmentRefs: args.attachmentRefs.map(b => bytesToHex(b)),
    signedBy: null,
    signature: null,
  };
  appendFileSync(args.path, `${JSON.stringify(obj)}\n`);
}

function appendAttachmentRow(args: {
  path: string;
  ts: number;
  id: string;
  visit_id: string;
  kind_field: string;
  content_hash: string;
  content_size: number;
  mime_type: string;
  captured_at: string;
  captured_by_cert_id: string;
  caption: string;
  created_at: string;
  cellId: Buffer;
  typeHash: Buffer;
  jobRef: Buffer | null;
  sourceBlobKey: string | null;
  pageCount: number | null;
  photoCount: number | null;
  hasPhotos: boolean;
}): void {
  const obj = {
    ts: args.ts,
    kind: 'created',
    id: args.id,
    visit_id: args.visit_id,
    kind_field: args.kind_field,
    content_hash: args.content_hash,
    content_size: args.content_size,
    mime_type: args.mime_type,
    captured_at: args.captured_at,
    captured_by_cert_id: args.captured_by_cert_id,
    caption: args.caption,
    created_at: args.created_at,
    cellId: bytesToHex(args.cellId),
    typeHash: bytesToHex(args.typeHash),
    jobRef: args.jobRef ? bytesToHex(args.jobRef) : null,
    sourceBlobKey: args.sourceBlobKey,
    pageCount: args.pageCount,
    photoCount: args.photoCount,
    hasPhotos: args.hasPhotos,
  };
  appendFileSync(args.path, `${JSON.stringify(obj)}\n`);
}

// ─── CellID + UUID derivation ─────────────────────────────────────────
//
// Zig parity (oddjobz_ratify_handler.zig:1199-1321):
//   site:        SHA-256("oddjobz.site.v2|"        + normalised + "|" + keyNumber + "|" + fullAddress)
//   customer:    SHA-256("oddjobz.customer.v2|"    + name + "|" + role + "|" + siteCellId(32 raw bytes) + "|" + phone + "|" + email)
//   job:         SHA-256("oddjobz.job.v2|"         + siteCellId(32) + "|" + each(cref.cellId(32) + ":" + cref.role + (cref.primary ? "*" : " ") + "|") + workOrderNumber + "|" + issuanceDate + "|" + dueDate + "|" + displayName + "|" + createdAt)
//   attachment:  SHA-256("oddjobz.attachment.v2|"  + jobCellId(32) + "|" + sourceAttachmentPath + "|" + createdAt)
//
// The 32-byte siteCellId / customer cellId / jobCellId fed into
// downstream hashes are RAW bytes, not hex. This mirrors the Zig
// `hasher.update(&site_cell_id)` calls.
//
// The TS-side and Zig-side outputs are INTENDED to be byte-equal for
// byte-equal inputs; Phase 2B.4 lands a parity oracle that asserts
// this directly across both implementations.

function sha256(buffers: ReadonlyArray<Buffer | string>): Buffer {
  const h = createHash('sha256');
  for (const b of buffers) {
    h.update(b);
  }
  return h.digest();
}

function utf8(s: string): Buffer {
  return Buffer.from(s, 'utf8');
}

function computeSiteCellId(
  normalisedAddress: string,
  keyNumber: string | null,
  fullAddress: string,
): Buffer {
  return sha256([
    utf8('oddjobz.site.v2|'),
    utf8(normalisedAddress),
    utf8('|'),
    utf8(keyNumber ?? ''),
    utf8('|'),
    utf8(fullAddress),
  ]);
}

function computeCustomerCellId(
  name: string,
  role: string,
  siteCellIdBytes: Buffer,
  phone: string,
  email: string,
): Buffer {
  return sha256([
    utf8('oddjobz.customer.v2|'),
    utf8(name),
    utf8('|'),
    utf8(role),
    utf8('|'),
    siteCellIdBytes,
    utf8('|'),
    utf8(phone),
    utf8('|'),
    utf8(email),
  ]);
}

function computeJobCellId(args: {
  siteCellIdBytes: Buffer;
  customerRefs: ReadonlyArray<{ cellIdBytes: Buffer; role: string; primary: boolean }>;
  workOrderNumber: string;
  issuanceDate: string;
  dueDate: string;
  createdAt: string;
  displayName: string;
}): Buffer {
  const parts: Array<Buffer | string> = [
    utf8('oddjobz.job.v2|'),
    args.siteCellIdBytes,
    utf8('|'),
  ];
  for (const cref of args.customerRefs) {
    parts.push(cref.cellIdBytes);
    parts.push(utf8(':'));
    parts.push(utf8(cref.role));
    parts.push(utf8(cref.primary ? '*' : ' '));
    parts.push(utf8('|'));
  }
  parts.push(utf8(args.workOrderNumber));
  parts.push(utf8('|'));
  parts.push(utf8(args.issuanceDate));
  parts.push(utf8('|'));
  parts.push(utf8(args.dueDate));
  parts.push(utf8('|'));
  parts.push(utf8(args.displayName));
  parts.push(utf8('|'));
  parts.push(utf8(args.createdAt));
  return sha256(parts);
}

function computeAttachmentCellId(
  jobCellIdBytes: Buffer,
  sourceAttachmentPath: string,
  createdAt: string,
): Buffer {
  return sha256([
    utf8('oddjobz.attachment.v2|'),
    jobCellIdBytes,
    utf8('|'),
    utf8(sourceAttachmentPath),
    utf8('|'),
    utf8(createdAt),
  ]);
}

/**
 * Build a UUID v4-shape hex string (32 chars, no dashes) from a 32-byte
 * source. Mirrors `oddjobz_ratify_handler.zig::uuidV5LikeFromBytes`:
 * take the first 16 bytes, force the version (high nibble of byte 6 = 4)
 * and variant (high two bits of byte 8 = 10) bits per RFC 4122 §4.4,
 * emit lowercase hex without dashes.
 */
function uuidV5LikeFromBytes(source: Buffer): string {
  const bytes = Buffer.alloc(16);
  source.copy(bytes, 0, 0, 16);
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  return bytes.toString('hex');
}

function bytesToHex(b: Buffer): string {
  return b.toString('hex');
}

// ─── Type-hash constants ──────────────────────────────────────────────
//
// SHA-256("<whatPath>:<howSlug>:<instPath>") per
// `core/cell-ops/src/typeHashRegistry.ts::computeTypeHash` and the
// `ODDJOBZ_CELL_TYPE_IDENTITIES` table. Pre-computed at module-load
// (the inputs are all string literals).

const ODDJOBZ_TYPE_HASH_SITE = sha256([utf8('oddjobz.site:locate:inst.location.work-site.v2')]);
const ODDJOBZ_TYPE_HASH_CUSTOMER = sha256([utf8('oddjobz.customer:identify:inst.identity.customer-record.v2')]);
const ODDJOBZ_TYPE_HASH_JOB = sha256([utf8('oddjobz.job:worktrack:inst.work.job-record.v2')]);
const ODDJOBZ_TYPE_HASH_ATTACHMENT = sha256([utf8('oddjobz.attachment:capture:inst.evidence.site-artifact.v2')]);

// Re-export for tests / parity-oracle use. These aren't part of the
// production surface; flag-day deletion is fine if a downstream picks
// them up unintentionally.
export const __FS_FALLBACK_INTERNALS__ = {
  computeSiteCellId,
  computeCustomerCellId,
  computeJobCellId,
  computeAttachmentCellId,
  uuidV5LikeFromBytes,
  normaliseAddress,
  deriveLookupKey,
  ODDJOBZ_TYPE_HASH_SITE,
  ODDJOBZ_TYPE_HASH_CUSTOMER,
  ODDJOBZ_TYPE_HASH_JOB,
  ODDJOBZ_TYPE_HASH_ATTACHMENT,
};

// Suppress unused-export warnings on `ProposalContact` import (kept so
// the type narrows cleanly when Phase 2B.4's parity oracle reaches in).
export type _PhaseTwoBTwoContactRef = ProposalContact;

```
