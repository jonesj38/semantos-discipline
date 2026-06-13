---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/ensure-lead-job.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.525856+00:00
---

# cartridges/oddjobz/brain/src/conversation/ensure-lead-job.ts

```ts
/**
 * SD2 incr.1 — lead-on-contact (operator decision 2026-05-18:
 * "anyone touching our system is a lead").
 *
 * The Job FSM genesis `∅→lead` is `jobs.create`; the
 * `intent_action_router` only ever *transitions* an existing job (it
 * never creates one). So before the proven P3.5 `accept_rom` seam can
 * flip a job `lead→qualified`, the job must EXIST in `lead`. This
 * module mints that job on every completed contact — ROM or not — via
 * the standard cap-gated REPL `jobs.create` verb, keeping the brain
 * generic (DECISION-P4C: the cartridge mints through the standard
 * API; no brain/Zig change).
 *
 * Wire: `POST /api/v1/repl` `{"cmd":"add job \"<name>\" lead"}` with
 * the pinned brain bearer → `oddjobz_cmds.cmdJobsCreate` →
 * `jobs.create {customer_name,state:"lead"}` (dispatched
 * `.in_process_root`, so the bearer satisfies `cap.oddjobz.
 * write_customer` structurally — same as `intent_cells.submit`).
 *
 * Exactly-once: `jobs.create` is NOT idempotent (`add job` has no id
 * arg; the store generates one), and a conversation can emit
 * `done:true` on multiple turns. The caller (intake-handler) guards
 * on the persisted `AccumulatedJobState.leadJobCreated` flag and only
 * calls this once per contact; this module also refuses when the flag
 * is already set or no customer name is known, so it is safe even if
 * the caller's guard regresses.
 *
 * Best-effort/additive by construction: the intake-handler wraps this
 * in the same try/catch as `submitLeadCell` — a throw is logged and
 * swallowed; the customer reply and the `leads.jsonl` shadow are
 * unaffected. `read`/idempotency live with the caller; this is a
 * pure submit with deps injected so it is worktree-unit-tested
 * (ZERO live) exactly like `submit-lead-cell.ts`.
 */

import type { AccumulatedJobState } from './accumulated-job-state.js';
import type { FetchLike } from './brain-submit-storage.js';

export interface EnsureLeadJobDeps {
  /** Brain REPL endpoint, e.g. https://oddjobtodd.info/api/v1/repl */
  readonly brainReplUrl: string;
  /** Bearer token (hex64) issued into the live brain TokenStore. */
  readonly brainBearer: string;
  /** Injected transport (tests mock; default global fetch). */
  readonly fetchFn?: FetchLike;
}

export interface EnsureLeadJobResult {
  readonly created: boolean;
  /** Why a job was NOT created (guard), for the best-effort log. */
  readonly skipped?: 'already_created' | 'no_customer_name';
  /** Raw REPL result text (trimmed) on a create attempt. */
  readonly replResult?: string;
}

/**
 * `add job` is whitespace+quote tokenised by the brain's `splitArgs`
 * (`"…"` groups, quotes stripped). An embedded `"` would split the
 * name (and a newline would break the single-line REPL command), so
 * strip both; collapse internal whitespace; cap length so the
 * `customer_name` stays well under the store's bound and the router's
 * substring match is stable.
 */
export function sanitizeCustomerName(raw: string): string {
  return raw
    .replace(/["\r\n\t]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 120);
}

/**
 * Mint the contact's job in `lead` (genesis) so the proven
 * `accept_rom` seam has something to flip to `qualified`, and so a
 * no-ROM contact is still a lead. Returns a result; THROWS only on a
 * genuine REPL failure (the intake-handler logs + swallows it, like
 * `submitLeadCell`).
 */
export async function ensureLeadJob(
  state: AccumulatedJobState,
  deps: EnsureLeadJobDeps,
): Promise<EnsureLeadJobResult> {
  return ensureLeadJobForName(
    state.customerName ?? null,
    state.leadJobCreated === true,
    deps,
  );
}

/**
 * U2 — the source-agnostic core. The proven genesis-lead POST, factored
 * out so BOTH chat (`ensureLeadJob`, from `AccumulatedJobState`) and
 * the converged gmail/meta ingest writer (from a `Proposal`) mint the
 * SAME `oddjobz.lead.v1` lead through the SAME cap-gated REPL seam.
 * `rawName` is the source's customer/point-of-contact identity (null ⇒
 * no correlation key); `alreadyCreated` is the source's exactly-once
 * guard. Behaviourally identical to the pre-U2 `ensureLeadJob` (the
 * chat tests are unchanged) — this is a pure additive extraction.
 */
export async function ensureLeadJobForName(
  rawName: string | null,
  alreadyCreated: boolean,
  deps: EnsureLeadJobDeps,
): Promise<EnsureLeadJobResult> {
  if (alreadyCreated) {
    return { created: false, skipped: 'already_created' };
  }
  const name = rawName ? sanitizeCustomerName(rawName) : '';
  if (name.length === 0) {
    // No correlation key ⇒ the router could never match a flip to
    // this job anyway; the jsonl shadow still captures the contact.
    return { created: false, skipped: 'no_customer_name' };
  }

  const fetchFn =
    deps.fetchFn ??
    ((url, init) => (globalThis.fetch as unknown as FetchLike)(url, init));

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
    throw new Error(`jobs.create HTTP ${res.status}: ${errBody.slice(0, 300)}`);
  }
  const text = (await res.text()).trim();
  // The handler returns the created Job JSON (status "created" or
  // "already_exists"). A dispatch failure / cap rejection surfaces a
  // typed error body — treat that as a genuine failure so the caller
  // logs it (and does NOT set the leadJobCreated flag, so a later
  // contact turn can retry).
  if (/dispatch failed|"error"|error_kind|cap_/i.test(text)) {
    throw new Error(`jobs.create rejected: ${text.slice(0, 300)}`);
  }
  return { created: true, replResult: text.slice(0, 300) };
}

```
