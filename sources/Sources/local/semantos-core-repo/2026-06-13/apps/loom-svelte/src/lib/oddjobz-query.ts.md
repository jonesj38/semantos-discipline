---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/oddjobz-query.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.080755+00:00
---

# apps/loom-svelte/src/lib/oddjobz-query.ts

```ts
// Helm-side client for canonical owner-bound oddjobz cell reads.
//
// Re-wired (SH core read-path migration) off the retired oddjobz-specific
// graph-walk verbs (`oddjobz.list_sites` / `get_job` / `find_jobs_at_site` …)
// onto the brain's GENERIC cell-DAG read primitive: `cell.query` / `cell.get`,
// keyed by the owner-bound `oddjobz.{site,customer,job,attachment}.v2` typeHash
// aliases. The brain no longer names oddjobz on its read surface — the oddjobz
// cartridge registers per-typeHash decoders (registerInto) that supply the same
// element JSON + `{collection}`/`{singular}` envelope this client already
// unwraps, so types + call sites below are unchanged from the old wiring.
//
// Reference (brain-side):
//   `runtime/semantos-brain/src/cell_query_handler.zig` — the generic
//     typeHash-keyed projection (query/get + the filter/ref contract).
//   `cartridges/.../wss_wallet/handlers.zig::handleCellQuery|handleCellGet` —
//     JSON-RPC method routing + param validation (`typeHash`, `filter`, `cellRef`).
//   `cartridges/oddjobz/brain/zig/registration.zig` — the oddjobz decoders
//     (aliases, collection/singular keys, allow_unfiltered_list, matches_filter)
//     + the `*ToJson` element encoders the row types below mirror byte-for-byte.
//
// Why a dedicated client (and not a method on ReplClient):
//
// The existing `ReplClient` (lib/repl-client.ts) wraps the bearer-gated
// HTTP REPL — it speaks the line-oriented `find jobs` / `add job ...`
// dialect over POST /api/v1/repl (the FSM ACTION verbs). The READ surface
// is JSON-RPC 2.0 over WSS at /api/v1/wallet — the reads ride alongside
// helm.event subscriptions on the same socket the SPA already opens for
// live ticks. Mixing the two protocols on one client object would confuse
// callers; this module is a focused JSON-RPC request/response surface for
// the cell reads only.
//
// The transport is parameterised: production passes `WssJsonRpcTransport`
// (opens a single WebSocket per request and resolves it with the matching
// id), tests inject a fake transport that returns a canned response.
//
// Wire shape (recap of the Semantos Brain-side):
//
//   request  → {"jsonrpc":"2.0","id":<n>,"method":"cell.query",
//                "params":{"typeHash":"oddjobz.site.v2"}}
//   response → {"jsonrpc":"2.0","id":<n>,"result":{"sites":[...]}}
//   error    → {"jsonrpc":"2.0","id":<n>,"error":{"code":-32602,"message":"..."}}
//
// `cell.query` enumerates cells via the cells_by_type index, so it returns
// the canonical OWNER-BOUND v2 cells ONLY (the prior verbs returned mixed
// v1+v2). This is the intended clean break: the helm now surfaces the v2
// store uniformly — including legacy Gmail leads minted as v2 cells. The
// `cellId`/v2 fields below are therefore always populated in practice; the
// `| null` arms remain only as defensive types.

// ─── Wire-typed cell shapes ─────────────────────────────────────────────
//
// These match the oddjobz cartridge's `oddjobz_query_handler.{site,customer,
// job,attachment}ToJson` element encoders byte-for-byte — the SAME encoders the
// brain's generic `cell.query`/`cell.get` decoders call (registration.zig).
// Field nullability matches the encoders' `null` emission for absent v2 fields.

/// Site row from a `cell.query`/`cell.get` on `oddjobz.site.v2`.
/// All sites in the v2 store carry the v2 fields (the typed view-store
/// is v2-only); the helm renders `fullAddress` for the operator.
export interface OddjobzSiteRow {
  /// 64-hex cellID — the graph node identity.
  readonly cellId: string;
  /// 64-hex type-hash of `oddjobz.site.v2`.
  readonly typeHash: string;
  /// Canonical lowercase + whitespace-collapsed address (dedupe key).
  readonly normalisedAddress: string;
  /// Optional `key #NNN` suffix (disambiguates units in one building).
  readonly keyNumber: string | null;
  /// `<normalisedAddress>|<keyNumber-or-empty>` — the lookup-or-mint key.
  readonly lookupKey: string;
  /// Operator-supplied display address ("13 Orealla Cr, Surfers Paradise").
  readonly fullAddress: string;
  readonly suburb: string | null;
  readonly postcode: string | null;
  readonly state: string | null;
  /// Unix-seconds creation timestamp.
  readonly createdAt: number;
}

/// Customer row from a `cell.query`/`cell.get` on `oddjobz.customer.v2`.
/// The encoder still tolerates the historic v1 shape (`cellId === null`,
/// `role === null`); `cell.query` enumerates v2 cells, so in practice
/// `role` is always populated.
export interface OddjobzCustomerRow {
  /// UUID — the v1 carry-over id; both v1 and v2 rows have this.
  readonly id: string;
  readonly display_name: string;
  readonly phone: string;
  readonly email: string;
  readonly address: string;
  readonly notes: string;
  readonly created_at: string;
  /// 64-hex cellID of the v2 customer cell, or null for v1 rows.
  readonly cellId: string | null;
  readonly typeHash: string | null;
  /// Role this customer plays.  v2-only (null on v1 rows).
  readonly role:
    | "tenant"
    | "agent"
    | "owner"
    | "pm"
    | "sub-tradie"
    | "other"
    | null;
  /// E.164 form when unambiguous, else null.
  readonly normalisedPhone: string | null;
  readonly sourceProvenance: {
    readonly providerId: string;
    readonly providerItemId: string;
    readonly extractedAt: string;
  } | null;
  /// 64-hex cellID of the customer's primary site (v2 only).
  readonly siteRef: string | null;
}

/// Customer-ref payload inside a v2 Job row.
export interface OddjobzJobCustomerRef {
  readonly cellId: string;
  readonly role: string;
  readonly primary: boolean;
}

/// Billing-party payload inside a v2 Job row.
export interface OddjobzJobBillingPartyWire {
  readonly type: string;
  readonly name: string;
}

/// Attachment row from a `cell.query` on `oddjobz.attachment.v2` (filter
/// `{jobRef}`).  Mixed v1/v2 shape — the v1 fields (id, visit_id, kind,
/// content_hash, content_size, mime_type, captured_at, captured_by_cert_id,
/// caption, created_at) always populate; the v2 graph-aware fields (cellId,
/// typeHash, jobRef, sourceBlobKey, pageCount, photoCount, hasPhotos) only
/// on v2 rows (else null/false).  Mirrors the cartridge's
/// `oddjobz_query_handler.attachmentToJson` byte-for-byte.
///
/// D-DOG.1.0c Phase 3 E.4 — the helm job-detail view binds to this row
/// (rendered as "Attachment: <sourceBlobKey> (<mimeType>, N pages, M
/// photos)" — PDF inline rendering is deferred to the `legacy attachment
/// <id>` verb's surface).
export interface OddjobzAttachmentRow {
  /// UUID — both v1 and v2.
  readonly id: string;
  readonly visit_id: string;
  readonly kind: string;
  readonly content_hash: string;
  readonly content_size: number;
  readonly mime_type: string;
  readonly captured_at: string;
  readonly captured_by_cert_id: string;
  readonly caption: string;
  readonly created_at: string;
  /// 64-hex cellID — null for v1 rows.
  readonly cellId: string | null;
  readonly typeHash: string | null;
  /// 64-hex cellID of the v2 job this attachment belongs to — null on v1.
  readonly jobRef: string | null;
  /// Blob-store key the source PDF / image was ingested under.  Null on
  /// v1 rows (no graph-aware blob link).
  readonly sourceBlobKey: string | null;
  readonly pageCount: number | null;
  readonly photoCount: number | null;
  readonly hasPhotos: boolean;
}

/// Job row from a `cell.query` on `oddjobz.job.v2` (filter `{siteRef}` or
/// `{customerRef}`) / a `cell.get` on `oddjobz.job.v2`.  Mixed v1/v2 shape —
/// the flat fields (id, customer_name, state, scheduled_at) always populate;
/// the v2 graph-aware fields are populated on the v2 cells `cell.query`
/// enumerates.
export interface OddjobzJobRow {
  readonly version: number;
  /// UUID — both v1 and v2.
  readonly id: string;
  readonly customer_name: string;
  readonly state: string;
  readonly scheduled_at: string;
  readonly created_at: string;
  /// 64-hex cellID — null for v1 rows.
  readonly cellId: string | null;
  readonly typeHash: string | null;
  readonly workOrderNumber: string | null;
  /// ISO calendar date (YYYY-MM-DD) the work order was issued.
  readonly issuanceDate: string | null;
  /// ISO calendar date (YYYY-MM-DD) the work order is due.
  readonly dueDate: string | null;
  readonly billingParty: OddjobzJobBillingPartyWire | null;
  /// Convenience flag — null on v1 rows, boolean on v2.
  readonly hasPhotos: boolean | null;
  readonly photoCount: number | null;
  readonly propertyKey: string | null;
  /// 64-hex cellID of the linked v2 site — null on v1 rows.
  readonly siteRef: string | null;
  /// Linked customer cells with role + primary flag — null on v1 rows.
  readonly customerRefs: readonly OddjobzJobCustomerRef[] | null;
  /// Linked attachment cellIDs — null on v1 rows.
  readonly attachmentRefs: readonly string[] | null;
}

// ─── Transport seam ─────────────────────────────────────────────────────

/// One round-trip JSON-RPC call.  The transport returns the parsed
/// `result` object; on JSON-RPC errors it rejects with [OddjobzQueryError].
export interface OddjobzQueryTransport {
  request(method: string, params: Record<string, unknown>): Promise<unknown>;
}

export class OddjobzQueryError extends Error {
  readonly code: number;
  constructor(code: number, message: string) {
    super(`oddjobz query error ${code}: ${message}`);
    this.name = "OddjobzQueryError";
    this.code = code;
  }
}

// ─── WebSocket transport ────────────────────────────────────────────────

/// Minimal WebSocket-shaped seam — same posture as
/// `lib/helm-event-stream.ts::HelmSocket`.  Production passes the global
/// `WebSocket`; tests inject a fake.
export interface OddjobzQuerySocket {
  send: (data: string) => void;
  close: () => void;
  addEventListener: (
    event: "open" | "message" | "close" | "error",
    handler: (ev: any) => void,
  ) => void;
}

export type OddjobzQuerySocketFactory = (url: string) => OddjobzQuerySocket;

export interface WssJsonRpcTransportOptions {
  /// `wss://<host>/api/v1/wallet`-shaped URL.  Same endpoint the event
  /// stream uses; bearer rides as `?bearer=<hex>` query param per
  /// `runtime/semantos-brain/src/wss_wallet.zig::parseBearerQuery`.
  wssUrl: string;
  /// 64-hex bearer from the active hat session.
  bearer: string;
  /// Test seam — production passes `(url) => new WebSocket(url)`.
  socketFactory?: OddjobzQuerySocketFactory;
  /// Per-request timeout in ms.  Default 10s — long enough for a cold
  /// FS read on the brain side, short enough that a wedged socket
  /// surfaces as a typed error in the SPA rather than a hung view.
  timeoutMs?: number;
  /// Wire framing. `'jsonrpc'` (default) → `{jsonrpc,id,method,params}` on
  /// /api/v1/wallet (legacy methods like `attention.poll`). `'rpc'` → the
  /// unified /api/v1/rpc channel: `{t:"req",id,method,params}` →
  /// `{t:"res"|"err",…}` (the read path — immune to the wallet if-chain
  /// codegen anomaly that breaks `cell.query` on /api/v1/wallet).
  framing?: "jsonrpc" | "rpc";
}

/// One-shot WSS JSON-RPC transport: opens a fresh WebSocket per request
/// and closes it on response.  This is intentionally simple — the helm
/// SPA's JobList does a small fixed number of these calls on each render
/// (one list_sites + one list_customers + N find_jobs_at_site), well
/// under the cost where a long-lived multiplexed socket would matter.
///
/// Multiplexing onto the existing event-stream socket is a future
/// optimisation; the design here keeps the transport seam stable so it
/// can be swapped without changing callers.
export class WssJsonRpcTransport implements OddjobzQueryTransport {
  private readonly opts: WssJsonRpcTransportOptions;
  private readonly socketFactory: OddjobzQuerySocketFactory;
  private readonly timeoutMs: number;
  private readonly framing: "jsonrpc" | "rpc";
  private nextId = 1;

  constructor(opts: WssJsonRpcTransportOptions) {
    this.opts = opts;
    this.socketFactory =
      opts.socketFactory ??
      ((url) => new WebSocket(url) as unknown as OddjobzQuerySocket);
    this.timeoutMs = opts.timeoutMs ?? 10_000;
    // Auto-derive framing from the endpoint: /api/v1/rpc uses the unified
    // rpc frames, anything else (e.g. /api/v1/wallet) the legacy JSON-RPC.
    this.framing =
      opts.framing ??
      (opts.wssUrl.includes("/api/v1/rpc") ? "rpc" : "jsonrpc");
  }

  request(method: string, params: Record<string, unknown>): Promise<unknown> {
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      const url = `${this.opts.wssUrl}${this.opts.wssUrl.includes("?") ? "&" : "?"}bearer=${encodeURIComponent(this.opts.bearer)}`;
      let socket: OddjobzQuerySocket;
      try {
        socket = this.socketFactory(url);
      } catch (e) {
        reject(e);
        return;
      }

      let settled = false;
      const settle = (
        action: { kind: "ok"; value: unknown } | { kind: "err"; err: Error },
      ) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        try {
          socket.close();
        } catch {
          // Already closed — ignore.
        }
        if (action.kind === "ok") resolve(action.value);
        else reject(action.err);
      };

      const timer = setTimeout(() => {
        settle({
          kind: "err",
          err: new Error(`oddjobz query timeout: ${method}`),
        });
      }, this.timeoutMs);

      socket.addEventListener("open", () => {
        try {
          socket.send(
            JSON.stringify(
              this.framing === "rpc"
                ? { t: "req", id: String(id), method, params }
                : { jsonrpc: "2.0", id, method, params },
            ),
          );
        } catch (e) {
          settle({
            kind: "err",
            err: e instanceof Error ? e : new Error(String(e)),
          });
        }
      });

      socket.addEventListener("message", (ev: MessageEvent | { data: unknown }) => {
        const raw = (ev as { data: unknown }).data;
        let text: string | null = null;
        if (typeof raw === "string") {
          text = raw;
        } else if (raw instanceof ArrayBuffer) {
          text = new TextDecoder().decode(raw);
        } else if (typeof Blob !== "undefined" && raw instanceof Blob) {
          // Browser-only path — async decode + recurse.
          raw
            .text()
            .then((t) => {
              this.handleFrame(t, id, method, settle);
            })
            .catch(() => {});
          return;
        } else {
          return;
        }
        this.handleFrame(text, id, method, settle);
      });

      socket.addEventListener("close", () => {
        settle({
          kind: "err",
          err: new Error(`oddjobz query: socket closed before response (${method})`),
        });
      });

      socket.addEventListener("error", () => {
        settle({
          kind: "err",
          err: new Error(`oddjobz query: socket error (${method})`),
        });
      });
    });
  }

  private handleFrame(
    text: string | null,
    expectedId: number,
    method: string,
    settle: (
      action: { kind: "ok"; value: unknown } | { kind: "err"; err: Error },
    ) => void,
  ): void {
    if (text === null) return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      return;
    }
    if (parsed === null || typeof parsed !== "object") return;
    const obj = parsed as Record<string, unknown>;
    // ── /api/v1/rpc framing: {t:"res"|"err",id,result|code/message} ──
    if (this.framing === "rpc") {
      if (obj["id"] !== String(expectedId)) return;
      if (obj["t"] === "err") {
        const message =
          typeof obj["message"] === "string"
            ? (obj["message"] as string)
            : `${method} failed`;
        settle({ kind: "err", err: new OddjobzQueryError(-32603, message) });
        return;
      }
      if (obj["t"] !== "res") return; // ignore push/ack frames
      settle({ kind: "ok", value: obj["result"] });
      return;
    }
    // ── legacy JSON-RPC framing (/api/v1/wallet) ──
    // Ignore notifications + frames that aren't our response.
    if (obj["id"] !== expectedId) return;
    const err = obj["error"];
    if (err !== undefined && err !== null && typeof err === "object") {
      const e = err as Record<string, unknown>;
      const code = typeof e["code"] === "number" ? (e["code"] as number) : -32603;
      const message =
        typeof e["message"] === "string"
          ? (e["message"] as string)
          : `oddjobz.${method} failed`;
      settle({ kind: "err", err: new OddjobzQueryError(code, message) });
      return;
    }
    settle({ kind: "ok", value: obj["result"] });
  }
}

// ─── Canonical cell typeHash aliases ────────────────────────────────────
//
// The owner-bound v2 cell typeHashes, as friendly aliases registered in
// `cartridges/oddjobz/brain/zig/registration.zig`. The brain's generic
// `cell.query`/`cell.get` accept either the 64-hex typeHash or one of these
// aliases. We use the aliases: they're self-documenting AND ≠ 64 hex chars,
// so `cell.get`'s ref-extraction (which picks the first 64-hex param value)
// never mistakes the typeHash for the cellRef.
export const ODDJOBZ_TYPE = {
  site: "oddjobz.site.v2",
  customer: "oddjobz.customer.v2",
  job: "oddjobz.job.v2",
  attachment: "oddjobz.attachment.v2",
} as const;

// ─── High-level typed surface ───────────────────────────────────────────

/// Strongly-typed wrappers around the generic `cell.query`/`cell.get`
/// primitive.  Each method returns the inner array / record (callers don't
/// unwrap `{sites: ...}` envelopes — the brain's per-typeHash decoder supplies
/// the same collection/singular keys the old verbs did).  Errors propagate as
/// [OddjobzQueryError] for typed JSON-RPC error bodies, plain `Error` for
/// transport-level failures.
///
/// `cell.query` params: `{typeHash, filter?}` → `{<collection>:[…]}`.
/// `cell.get`   params: `{typeHash, cellRef}` → `{<singular>: {…}|null}`.
/// sites/customers list unfiltered; jobs/attachments require a ref filter
/// (`{siteRef}`/`{customerRef}` for jobs, `{jobRef}` for attachments).
export class OddjobzQueryClient {
  constructor(private readonly transport: OddjobzQueryTransport) {}

  async listSites(): Promise<OddjobzSiteRow[]> {
    const r = (await this.transport.request("cell.query", {
      typeHash: ODDJOBZ_TYPE.site,
    })) as { sites?: unknown } | undefined;
    const sites = r?.sites;
    if (!Array.isArray(sites)) return [];
    return sites as OddjobzSiteRow[];
  }

  async listCustomers(): Promise<OddjobzCustomerRow[]> {
    const r = (await this.transport.request("cell.query", {
      typeHash: ODDJOBZ_TYPE.customer,
    })) as { customers?: unknown } | undefined;
    const customers = r?.customers;
    if (!Array.isArray(customers)) return [];
    return customers as OddjobzCustomerRow[];
  }

  async findJobsAtSite(siteRef: string): Promise<OddjobzJobRow[]> {
    const r = (await this.transport.request("cell.query", {
      typeHash: ODDJOBZ_TYPE.job,
      filter: { siteRef },
    })) as { jobs?: unknown } | undefined;
    const jobs = r?.jobs;
    if (!Array.isArray(jobs)) return [];
    return jobs as OddjobzJobRow[];
  }

  /// `cell.get` on `oddjobz.site.v2` → single site row or null when the
  /// siteRef doesn't resolve.  Used by the site-pivot route to render the
  /// property header before the per-site job fan-out.
  async getSite(siteRef: string): Promise<OddjobzSiteRow | null> {
    const r = (await this.transport.request("cell.get", {
      typeHash: ODDJOBZ_TYPE.site,
      cellRef: siteRef,
    })) as { site?: unknown } | undefined;
    const site = r?.site;
    if (site === null || site === undefined) return null;
    return site as OddjobzSiteRow;
  }

  async findJobsForCustomer(customerRef: string): Promise<OddjobzJobRow[]> {
    const r = (await this.transport.request("cell.query", {
      typeHash: ODDJOBZ_TYPE.job,
      filter: { customerRef },
    })) as { jobs?: unknown } | undefined;
    const jobs = r?.jobs;
    if (!Array.isArray(jobs)) return [];
    return jobs as OddjobzJobRow[];
  }

  /// `cell.get` on `oddjobz.customer.v2` → single Customer row or null.
  /// The lookup is by 64-hex cellId.  The customer-pivot route uses this to
  /// render the header card; the inner "all jobs they're contact for" list is
  /// fetched via [findJobsForCustomer].
  async getCustomer(customerRef: string): Promise<OddjobzCustomerRow | null> {
    const r = (await this.transport.request("cell.get", {
      typeHash: ODDJOBZ_TYPE.customer,
      cellRef: customerRef,
    })) as { customer?: unknown } | undefined;
    const customer = r?.customer;
    if (customer === null || customer === undefined) return null;
    return customer as OddjobzCustomerRow;
  }

  async getJob(jobRef: string): Promise<OddjobzJobRow | null> {
    const r = (await this.transport.request("cell.get", {
      typeHash: ODDJOBZ_TYPE.job,
      cellRef: jobRef,
    })) as { job?: unknown } | undefined;
    const job = r?.job;
    if (job === null || job === undefined) return null;
    return job as OddjobzJobRow;
  }

  /// `cell.query` on `oddjobz.attachment.v2` (filter `{jobRef}`) — returns
  /// the attachments linked to the given v2 job cell.  The decoder's view-store
  /// excludes v1 visit-side rows, so callers render every row uniformly without
  /// a v1/v2 branch.
  async findAttachmentsForJob(jobRef: string): Promise<OddjobzAttachmentRow[]> {
    const r = (await this.transport.request("cell.query", {
      typeHash: ODDJOBZ_TYPE.attachment,
      filter: { jobRef },
    })) as { attachments?: unknown } | undefined;
    const attachments = r?.attachments;
    if (!Array.isArray(attachments)) return [];
    return attachments as OddjobzAttachmentRow[];
  }
}

```
