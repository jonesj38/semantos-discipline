---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/state-machines/job-fsm.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.529953+00:00
---

# cartridges/oddjobz/brain/src/state-machines/job-fsm.ts

```ts
/**
 * D-O4 — Job FSM.
 *
 * The canonical Job state machine. Lead-nurture front (the
 * "don't let it fall through the gap" remodel) + the §O4 execution
 * chain:
 *
 *   ∅ → lead → qualified ┬→ visit_pending → visit_scheduled →
 *                        │      visited ──┐
 *                        ├→ quoted ◀──────┘  (skip: quote off ROM)
 *                        └→ authorized        (REA WO: no quote owed)
 *   quoted ─────┐
 *   authorized ─┴→ scheduled → in_progress → completed → invoiced →
 *       paid → closed
 *
 * `authorized` is a discrete branch parallel to `quoted`: a directly-
 * authorised work order (e.g. an REA-issued WO that is itself the
 * authorisation — no customer quote round-trip) skips quoting and
 * feeds `scheduled` the same way `quoted` does. Keeping it a distinct
 * state (rather than a quote with auto-accepted status) gives Pask +
 * the operator pricing-schedule analytics a clean signal to fine-tune
 * how direct-authorised work performs against quoted work.
 *
 * Each transition consumes the current Job cell at the kernel gate and
 * mints a successor cell with the same `jobId` but a fresh cell-id.
 * This module:
 *
 *   1. enumerates the thirteen states + fourteen transitions (two
 *      branches at `qualified` — visit / quote-skip / authorise — and
 *      two in-edges each to `quoted` and `scheduled`) verbatim;
 *   2. exposes a single `jobTransition()` function that runs the
 *      kernel-gate checks (K1 / K2 / K3a — via the
 *      `kernel-gate.ts` substrate stub) and emits the successor cell;
 *   3. surfaces failure-atomicity (K4) by **never** marking the input
 *      cell consumed unless every check has passed.
 *
 * Cell-id semantics on transition (per the cell-engine canon and per
 * the K1 invariant in `proofs/lean/Semantos/Theorems/LinearityK1.lean`):
 * a LINEAR cell is **consumed once**. A successful transition mints a
 * structurally new successor cell (new cell-id, same logical jobId,
 * `prevStateHash` chain to the predecessor — the prevStateHash is
 * tracked by the cell-engine substrate, not by the FSM module). The TS
 * stub mirrors this: the input cell-id goes into the `ConsumedCellSet`,
 * the output cell carries a fresh derived cell-id.
 *
 * Reference:
 *  - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4 (the full transition table)
 *  - cartridges/oddjobz/brain/src/cell-types/job.ts (the cell-type the FSM
 *    operates over — `OddjobzJob`, `JOB_STATUSES`)
 *  - cartridges/oddjobz/brain/src/capabilities.ts (the caps the gates check)
 *  - proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/JobFSM.lean
 *    (the per-transition-table-pair enumeration + totality theorem)
 */

import type { OddjobzJob, JobStatus } from '../cell-types/job.js';
import {
  ok,
  err,
  assertLinear,
  checkDomainFlag,
  describeFailure,
  type ConsumedCellSet,
  type KernelGateFailure,
  type OddjobzCapName,
  type PresentedCap,
  type Result,
  type SigningPrincipal,
} from './kernel-gate.js';

/* ══════════════════════════════════════════════════════════════════════
 * Canonical FSM states + transition table
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * The thirteen canonical Job FSM states. These are a strict subset of
 * `JOB_STATUSES` (which carries legacy values for OJT-migration round-
 * trips); the FSM only permits transitions over the canonical
 * thirteen. `authorized` sits parallel to `quoted` (both feed
 * `scheduled`) — the directly-authorised, no-quote branch.
 */
export const JOB_FSM_STATES = [
  'lead',
  'qualified',
  'visit_pending',
  'visit_scheduled',
  'visited',
  'quoted',
  'authorized',
  'scheduled',
  'in_progress',
  'completed',
  'invoiced',
  'paid',
  'closed',
] as const;
export type JobFsmState = (typeof JOB_FSM_STATES)[number];

/** Type-guard: is `s` one of the thirteen canonical states? */
export function isJobFsmState(s: JobStatus): s is JobFsmState {
  return (JOB_FSM_STATES as readonly string[]).includes(s);
}

/**
 * The shape of one row in the §O4 Job FSM transition table.
 *   - `from`            current state (must equal the input cell's `status`)
 *   - `to`              successor state
 *   - `capRequired`     the cap that must be presented; null for an
 *                       ungated transition (the §O4 "none" entries)
 *   - `principalKinds`  acceptable signing principals (order-insensitive
 *                       set; multi-element for the ∅→lead row that
 *                       accepts either operator OR service)
 */
export interface JobTransitionSpec {
  readonly from: JobFsmState;
  readonly to: JobFsmState;
  readonly capRequired: OddjobzCapName | null;
  readonly principalKinds: readonly SigningPrincipal[];
}

/**
 * The §O4 critical-path Job FSM transition table — verbatim from the
 * spec, declaration order = spec row order. The `∅ → lead` row is
 * handled separately by `genesisJobLead()` (no input cell) so it does
 * not appear in this table; this table covers the fourteen LINEAR-
 * consumption transitions (each consumes a Job cell).
 */
export const JOB_TRANSITIONS: readonly JobTransitionSpec[] = Object.freeze([
  // ── Lead-nurture front of the pipeline (the "don't let it fall
  //    through the gap" states). Each is a discrete, schedulable,
  //    queryable step so the Sunday week-optimiser agent can surface
  //    "qualified leads with no visit booked" / "visits done, quote
  //    owed". The ∅→lead genesis is handled by genesisJobLead().
  Object.freeze({
    // Customer accepted the ROM (rough order of magnitude) in the
    // chat widget — the lead is now worth pursuing.
    from: 'lead',
    to: 'qualified',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    // SD2 incr.2: an ingested work-order / maintenance-order (the WO
    // IS the authorisation — REA/PM-issued, no customer quote owed)
    // skips a converged-ingest lead straight to authorized. Ungated/
    // operator, a verbatim mirror of qualified→authorized — the
    // authorisation lives in the WO, not a presented cap. Declaration
    // order tracks the Zig job_fsm.zig canon (row 1).
    from: 'lead',
    to: 'authorized',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    // This one needs eyes on site before a firm quote.
    from: 'qualified',
    to: 'visit_pending',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    // Skip path: confident enough to quote straight off the
    // prequalified ROM acceptance — no site visit.
    from: 'qualified',
    to: 'quoted',
    capRequired: 'cap.oddjobz.quote',
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    // Directly-authorised branch: a pre-authorised work order (e.g.
    // an REA-issued WO that IS the authorisation) needs no customer
    // quote. The operator marks the qualified job authorised and it
    // proceeds straight to scheduling. Ungated/operator like the
    // other lead-nurture front edges — the authorisation lives in
    // the WO, not a presented cap.
    from: 'qualified',
    to: 'authorized',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    // A visit time was locked with the customer (the negotiation
    // rounds happen as events while in visit_pending; this edge
    // fires only when the slot is agreed). Mirrors a linked Visit
    // cell entering Visit-FSM `scheduled`.
    from: 'visit_pending',
    to: 'visit_scheduled',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    // Been on site; the linked Visit cell is completed and its
    // photos are attached. Quote is now owed — this is the second
    // gap the agent watches ("visited but not quoted").
    from: 'visit_scheduled',
    to: 'visited',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    // Quote issued off the completed site visit.
    from: 'visited',
    to: 'quoted',
    capRequired: 'cap.oddjobz.quote',
    principalKinds: ['operator'] as const,
  }),
  // ── Post-quote execution chain (unchanged from §O4).
  Object.freeze({
    from: 'quoted',
    to: 'scheduled',
    capRequired: 'cap.oddjobz.dispatch',
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    // Authorised-branch dispatch — exact mirror of quoted→scheduled
    // (same dispatch act, parallel branch). The two in-edges to
    // `scheduled` are the only place quoted/authorised re-converge.
    from: 'authorized',
    to: 'scheduled',
    capRequired: 'cap.oddjobz.dispatch',
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'scheduled',
    to: 'in_progress',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'in_progress',
    to: 'completed',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'completed',
    to: 'invoiced',
    capRequired: 'cap.oddjobz.invoice',
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'invoiced',
    to: 'paid',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'paid',
    to: 'closed',
    capRequired: 'cap.oddjobz.close',
    principalKinds: ['operator'] as const,
  }),
]);

/** Lookup the (from, to) row, or `undefined` if the pair isn't in the table. */
export function findJobTransition(
  from: JobFsmState,
  to: JobFsmState,
): JobTransitionSpec | undefined {
  return JOB_TRANSITIONS.find((t) => t.from === from && t.to === to);
}

/** All (from, to) pairs in the table — handy for property tests. */
export function allValidJobTransitions(): ReadonlyArray<{
  readonly from: JobFsmState;
  readonly to: JobFsmState;
}> {
  return JOB_TRANSITIONS.map((t) => ({ from: t.from, to: t.to }));
}

/* ══════════════════════════════════════════════════════════════════════
 * Cell-id derivation — the LINEAR successor cell-id
 *
 * The TS-FSM stub treats `cellId` as a structural string keyed off
 * `(jobId, status)` so two different Job cells under the same jobId
 * have distinct cell-ids. In production the cell-id is a SHA-256 of
 * the cell bytes; here we keep the test-double readable.
 *
 * The contract this satisfies (matched in the Lean spec):
 *   distinct (jobId, status) ⇒ distinct cellId
 * which the K1-equivalent `job_fsm_consumed_cell_rejected` proof needs.
 * ══════════════════════════════════════════════════════════════════════ */

/** Deterministic cell-id for a Job cell at `(jobId, status)`. */
export function jobCellId(jobId: string, status: JobFsmState): string {
  return `oddjobz.job:${jobId}:${status}`;
}

/* ══════════════════════════════════════════════════════════════════════
 * The transition function
 * ══════════════════════════════════════════════════════════════════════ */

export interface JobTransitionInput {
  /** The current Job cell to be consumed. Its `status` must equal `to.from`. */
  readonly cell: OddjobzJob;
  /** The transition target. */
  readonly to: JobFsmState;
  /** The presented cap UTXO, if the transition requires one. */
  readonly presentedCap?: PresentedCap | null;
  /** The signing principal kind. */
  readonly principal: SigningPrincipal;
  /** ISO-8601 wall-clock timestamp to stamp on the successor cell. */
  readonly nowIso: string;
  /** The K1 substrate stub — tracks consumed cell-ids. */
  readonly consumed: ConsumedCellSet;
  /** Optional side effect that runs AFTER all kernel-gate checks pass.
   *  If it throws, the input cell is left untouched (K4) and the failure
   *  bubbles up as `induced_io_failure`. Use this to model the Stripe /
   *  Xero / SMS push that the §O4 spec uses for the K4 acceptance test. */
  readonly sideEffect?: () => void;
}

export interface JobTransitionOutput {
  /** The successor Job cell (new cell-id, new status, refreshed updatedAt). */
  readonly cell: OddjobzJob;
  /** The cell-id of the predecessor that was consumed (now in `consumed`). */
  readonly consumedCellId: string;
  /** The cell-id of the successor (NOT yet in `consumed`). */
  readonly successorCellId: string;
  /** The transition that fired. */
  readonly transition: JobTransitionSpec;
}

/**
 * Run a Job FSM transition. See module head for the K1/K2/K3a/K4
 * contract this honours.
 *
 * Order of checks (matches the kernel-gate's evaluation order):
 *
 *   1. Lookup the (from, to) row in the table; reject `invalid_state_transition`
 *      if absent.
 *   2. Verify the cell's `status` equals the row's `from`; reject
 *      `from_state_mismatch` otherwise.
 *   3. Verify the input cell-id is not already in `consumed` (K1 /
 *      OP_ASSERTLINEAR); reject `cell_already_consumed` otherwise.
 *   4. Verify the signing principal kind is in the row's `principalKinds`;
 *      reject `bad_signing_principal` otherwise.
 *   5. If the row requires a cap, verify the presented cap's domain flag
 *      matches (K2 / K3a / OP_CHECKDOMAINFLAG); reject `cap_required`
 *      or `wrong_cap` otherwise. Step 5 is skipped for ungated rows.
 *   6. Run the optional side effect inside `runFailureAtomic`; if it
 *      throws, the cell stays unchanged and `induced_io_failure` is
 *      returned (K4).
 *   7. Mint the successor cell, mark the predecessor cell-id consumed,
 *      and return.
 *
 * The "consume only on success" ordering is what gives K4: a step-6
 * failure leaves `consumed` untouched, so a retry on the same cell
 * succeeds. The Lean `job_fsm_failure_atomic` theorem proves this.
 */
export function jobTransition(
  input: JobTransitionInput,
): Result<JobTransitionOutput, KernelGateFailure> {
  const { cell, to, presentedCap, principal, nowIso, consumed } = input;

  // Step 0: input validation — the cell must already be on a canonical
  // FSM state. Legacy statuses (the OJT-migration entries in
  // `JOB_STATUSES`) do not participate in §O4 transitions; they raise
  // `from_state_mismatch` so the caller migrates them to canonical
  // first.
  if (!isJobFsmState(cell.status)) {
    return err({
      kind: 'from_state_mismatch',
      message: `cell.status=${cell.status} is not a canonical FSM state`,
      attempted: { from: cell.status, to },
    });
  }

  // Step 1: lookup
  const spec = findJobTransition(cell.status, to);
  if (spec === undefined) {
    return err({
      kind: 'invalid_state_transition',
      message: `no §O4 row for ${cell.status} → ${to}`,
      attempted: { from: cell.status, to },
    });
  }

  // Step 2: from-state already enforced by the lookup-from-cell.status,
  // but we double-check for defence in depth (a future caller might
  // route through findJobTransition directly).
  if (cell.status !== spec.from) {
    return err({
      kind: 'from_state_mismatch',
      message: `cell.status=${cell.status} ≠ spec.from=${spec.from}`,
      attempted: { from: cell.status, to },
    });
  }

  // Step 3: K1 — OP_ASSERTLINEAR
  const inputCellId = jobCellId(cell.jobId, spec.from);
  const linChk = assertLinear(consumed, inputCellId);
  if (!linChk.ok) return linChk;

  // Step 4: signing principal
  if (!spec.principalKinds.includes(principal)) {
    return err({
      kind: 'bad_signing_principal',
      message: `principal=${principal} not in [${spec.principalKinds.join(',')}] for ${spec.from} → ${spec.to}`,
      expectedPrincipal: spec.principalKinds[0],
      attempted: { from: spec.from, to: spec.to },
    });
  }

  // Step 5: K2 / K3a — OP_CHECKDOMAINFLAG (only when the row requires a cap)
  if (spec.capRequired !== null) {
    const capChk = checkDomainFlag(spec.capRequired, presentedCap ?? null);
    if (!capChk.ok) return capChk;
  }

  // Step 6: K4 — optional side effect; on throw the cell is unchanged
  if (input.sideEffect !== undefined) {
    try {
      input.sideEffect();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return err({
        kind: 'induced_io_failure',
        message: `side effect for ${spec.from} → ${spec.to} failed: ${msg}`,
        attempted: { from: spec.from, to: spec.to },
      });
    }
  }

  // Step 7: mint successor + mark predecessor consumed
  const successor: OddjobzJob = {
    ...cell,
    status: spec.to,
    updatedAt: nowIso,
  };
  consumed.add(inputCellId);

  return ok({
    cell: successor,
    consumedCellId: inputCellId,
    successorCellId: jobCellId(cell.jobId, spec.to),
    transition: spec,
  });
}

/* ══════════════════════════════════════════════════════════════════════
 * Genesis — the ∅ → lead row
 *
 * §O4 calls out that the genesis path may be either operator-held
 * (`cap.oddjobz.write_customer`) or service-held
 * (`cap.oddjobz.public_chat_serve`). There is no input cell to
 * consume; this is the only "create-from-nothing" row in the Job FSM.
 *
 * The cell-id of the freshly-minted lead is NOT added to `consumed`
 * here — it is consumed by the next transition (`lead → quoted`).
 * ══════════════════════════════════════════════════════════════════════ */

export interface JobGenesisInput {
  readonly jobId: string;
  readonly principal: SigningPrincipal;
  readonly presentedCap: PresentedCap;
  readonly nowIso: string;
  /** Optional fields the lead is materialised with — minimal shape;
   *  callers can layer on more after. */
  readonly customerId?: string;
  readonly siteId?: string;
}

/**
 * Build a fresh Job in `lead` state, gated by `cap.oddjobz.write_customer`
 * (operator) or `cap.oddjobz.public_chat_serve` (service) per §O4.
 */
export function genesisJobLead(
  input: JobGenesisInput,
): Result<OddjobzJob, KernelGateFailure> {
  const expectedCap: OddjobzCapName =
    input.principal === 'operator'
      ? 'cap.oddjobz.write_customer'
      : 'cap.oddjobz.public_chat_serve';
  const capChk = checkDomainFlag(expectedCap, input.presentedCap);
  if (!capChk.ok) return capChk;
  const lead: OddjobzJob = {
    jobId: input.jobId,
    customerId: input.customerId,
    siteId: input.siteId,
    status: 'lead',
    createdAt: input.nowIso,
    updatedAt: input.nowIso,
  };
  return ok(lead);
}

/* ══════════════════════════════════════════════════════════════════════
 * Pretty-printer for tests + audit logs
 * ══════════════════════════════════════════════════════════════════════ */

export function describeJobFailure(f: KernelGateFailure): string {
  return `[Job FSM] ${describeFailure(f)}`;
}

```
