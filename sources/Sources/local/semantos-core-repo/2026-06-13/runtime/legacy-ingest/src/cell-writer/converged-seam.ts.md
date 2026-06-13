---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/cell-writer/converged-seam.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.136743+00:00
---

# runtime/legacy-ingest/src/cell-writer/converged-seam.ts

```ts
/**
 * U2 — converged-seam CellWriter (operator decision 2026-05-18: RETIRE
 * the `oddjobz.ratify_proposal`/WSS/JSONL-island path; gmail/meta
 * leads converge on the SAME standardised seam as chat).
 *
 * Drop-in `RatificationOrchestrator.opts.writeCell` replacement for
 * `brain-rpc.ts`'s `BrainRpcCellWriter`. Instead of minting the
 * D-RTC.4 substrate_entity cell graph into the JSONL view-store
 * island, it creates the job in `lead` via the proven cap-gated REPL
 * `add job "<name>" lead` — the SAME genesis the chat seam (SD2
 * incr.1, `cartridges/oddjobz/brain/src/conversation/ensure-lead-job.ts`)
 * uses, so an ingested lead lands in the SAME `IntentCellLmdbStore` +
 * jobs FSM and (if/when it gets a ROM) the `intent_action_router`
 * flips it `lead→qualified` exactly like a chat lead.
 *
 * PACKAGE DECOUPLING (load-bearing): `@semantos/legacy-ingest` does
 * NOT depend on `@semantos/oddjobz` (see brain-rpc.ts ~919 — oddjobz
 * specifics are deliberately kept out so legacy-ingest stays
 * unbloated). So this does NOT import `ensure-lead-job.ts`; it
 * MIRRORS its stable wire contract (`add job "<sanitised name>"
 * lead` over the cap-gated REPL, `.in_process_root` ⇒ the bearer
 * satisfies `cap.oddjobz.write_customer`). Keep the two in sync if
 * the `add job` REPL verb / sanitisation rule ever changes.
 *
 * NOT a brain-spawned child (legacy-ingest is standalone tooling), so
 * the self-call deadlock that forced the chat seam's detached
 * submitter does NOT apply here — this calls the LOOPBACK REPL
 * synchronously and returns the receipt id inline.
 *
 * Deps-injected (env-supplied REPL url/bearer + a mockable fetch) ⇒
 * unit-tested with ZERO live. Gmail/meta ingest is dormant tooling,
 * so wiring this changes nothing until the operator next runs ingest.
 */

import type { SIRProgram } from '@semantos/semantos-sir';
import type { Proposal } from '../extractor/types';
import type { CellWriterFn } from '../ratification/orchestrator';

/** Injected transport — the global `fetch` shape, mockable in tests. */
export type ConvergedFetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string },
) => Promise<{ status: number; text: () => Promise<string> }>;

export interface ConvergedSeamDeps {
  /** Brain REPL endpoint — LOOPBACK, e.g. http://127.0.0.1:8080/api/v1/repl */
  readonly brainReplUrl: string;
  /** Bearer token (hex64) issued into the live brain TokenStore. */
  readonly brainBearer: string;
  /** Injected transport; defaults to global fetch. */
  readonly fetchFn?: ConvergedFetchLike;
}

/**
 * Mirror of `ensure-lead-job.ts::sanitizeCustomerName`. The brain
 * `splitArgs` `"…"` tokeniser breaks on embedded `"`/newlines; collapse
 * whitespace; cap length so `customer_name` stays well under the
 * store bound and the router substring-match is stable.
 */
export function sanitizeName(raw: string): string {
  return raw
    .replace(/["\r\n\t]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 120);
}

/**
 * Derive the lead's correlation/display identity from the Proposal.
 * `pointOfContact` is the extractor's curated "who's in the loop about
 * THIS job" (v0.5 "<name> (<role>)"); fall back to the primary tenant
 * contact name. Null ⇒ no correlation key (the router could never
 * match a flip) ⇒ the writer no-ops (returns null, no receipt cell).
 */
export function proposalLeadName(p: Proposal): string | null {
  const raw =
    (p.pointOfContact && p.pointOfContact.trim()) ||
    (p.primaryContact && p.primaryContact.name && p.primaryContact.name.trim()) ||
    '';
  if (!raw) return null;
  const n = sanitizeName(raw);
  return n.length > 0 ? n : null;
}

/**
 * Build the converged `CellWriterFn`. On a ratified Proposal it
 * creates the job in `lead` (genesis) via the cap-gated REPL and
 * returns a receipt id (the proposalId — stable, dedup-friendly) so
 * the `RatificationReceipt.cellId` stays populated. Returns null when
 * there is no usable name (nothing minted). THROWS on a genuine REPL
 * failure so the orchestrator surfaces it as `cell_write_error`
 * (same contract as BrainRpcCellWriter — never a silent success).
 *
 * No ROM is available from an inbound email/form, so — exactly like
 * a chat-no-estimate contact — only the `lead` job is created (no
 * `accept_rom`); a later quote/ROM advances it through the FSM.
 */
/**
 * SD2 incr.2 — the WO classifier signal. The `Proposal` carries NO
 * `job_type` field; the extractor encodes the Phase-1 classification
 * as the SIRProgram node `action` (`email.ts:mapJobTypeToAction`):
 * `create_quote_request` | `create_work_order` |
 * `create_maintenance_order`. Read it the proven way
 * (`brain-rpc.ts` L528-535: first `program.nodes[].action` string).
 */
export function proposalJobAction(program: SIRProgram): string | null {
  const nodes = Array.isArray((program as { nodes?: unknown }).nodes)
    ? (program as { nodes: unknown[] }).nodes
    : [];
  for (const node of nodes) {
    const a = (node as { action?: unknown }).action;
    if (typeof a === 'string' && a.length > 0) return a;
  }
  return null;
}

/**
 * Work-order / maintenance-order ⇒ the WO IS the authorisation (no
 * customer quote owed) ⇒ skip the converged-ingest lead straight to
 * `authorized` via the new `lead→authorized` FSM edge.
 * `create_quote_request` ⇒ stay `lead` (qualify/quote as today).
 */
const WORK_ORDER_ACTIONS = new Set([
  'create_work_order',
  'create_maintenance_order',
]);

/** Extract the created job id from the REPL `add job` response. The
 *  REPL envelope is `{"result":"{\"id\":\"…\",\"status\":\"…\"}\n",
 *  "exit":"continue"}`; be tolerant of either the enveloped or a raw
 *  inner form. Returns null if no id (⇒ skip the WO transition). */
export function parseCreatedJobId(text: string): string | null {
  try {
    const outer = JSON.parse(text) as { result?: unknown };
    const inner =
      typeof outer.result === 'string' ? outer.result : text;
    const j = JSON.parse(inner) as { id?: unknown };
    if (typeof j.id === 'string' && j.id.length > 0) return j.id;
  } catch {
    /* fall through to regex */
  }
  const m = text.match(/"id\\?":\\?"([^"\\]{4,})\\?"/);
  return m ? m[1]! : null;
}

export function makeConvergedSeamCellWriter(
  deps: ConvergedSeamDeps,
): CellWriterFn {
  const fetchFn: ConvergedFetchLike =
    deps.fetchFn ??
    ((url, init) =>
      (globalThis.fetch as unknown as ConvergedFetchLike)(url, init));

  return async (opts: {
    program: SIRProgram;
    proposal: Proposal;
  }): Promise<string | null> => {
    const name = proposalLeadName(opts.proposal);
    if (!name) return null;

    const body = JSON.stringify({ cmd: `add job "${name}" lead` });
    const res = await fetchFn(deps.brainReplUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${deps.brainBearer}`,
      },
      body,
    });
    if (res.status < 200 || res.status >= 300) {
      const errBody = await res.text().catch(() => '');
      throw new Error(
        `converged-seam jobs.create HTTP ${res.status}: ${errBody.slice(0, 300)}`,
      );
    }
    const text = (await res.text()).trim();
    if (/dispatch failed|"error"|error_kind|cap_/i.test(text)) {
      throw new Error(
        `converged-seam jobs.create rejected: ${text.slice(0, 300)}`,
      );
    }
    // SD2 incr.2 — WO classifier. A work-order/maintenance-order IS
    // the authorisation (REA/PM-issued, no customer quote owed) ⇒
    // drive the genesis lead straight to `authorized` via the new
    // lead→authorized FSM edge. quote_request ⇒ leave in `lead`
    // (qualify/quote as today). Best-effort/surfaced like the create:
    // a transition failure throws ⇒ the orchestrator records
    // `cell_write_error` (never a silent half-done).
    const action = proposalJobAction(opts.program);
    if (action && WORK_ORDER_ACTIONS.has(action)) {
      const jobId = parseCreatedJobId(text);
      if (jobId) {
        const tRes = await fetchFn(deps.brainReplUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${deps.brainBearer}`,
          },
          body: JSON.stringify({
            cmd: `transition job ${jobId} authorized`,
          }),
        });
        if (tRes.status < 200 || tRes.status >= 300) {
          const eb = await tRes.text().catch(() => '');
          throw new Error(
            `converged-seam jobs.transition HTTP ${tRes.status}: ${eb.slice(0, 300)}`,
          );
        }
        const tText = (await tRes.text()).trim();
        if (/dispatch failed|"error"|error_kind|cap_|invalid.*transition/i.test(tText)) {
          throw new Error(
            `converged-seam jobs.transition rejected: ${tText.slice(0, 300)}`,
          );
        }
      }
      // No parseable job id ⇒ the create response was unexpected;
      // the lead still exists, just not auto-authorised. Surfaced via
      // the returned receipt; not fatal (best-effort, like the create).
    }

    // Receipt id = the stable proposalId (ingest's correlation key),
    // mirroring how BrainRpcCellWriter echoes a proposal-scoped id.
    return opts.proposal.proposalId;
  };
}

```
