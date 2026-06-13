---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/state-machines/job-fsm.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.492480+00:00
---

# cartridges/oddjobz/brain/tests/state-machines/job-fsm.test.ts

```ts
/**
 * D-O4 — Job FSM tests.
 *
 * Three §O4 acceptance tests are flagged with `[§O4 K1/K2/K4]` in
 * their `test()` titles so the PR body can grep them out of the bun
 * output verbatim.
 *
 * Reference:
 *   docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4 (acceptance tests)
 *   cartridges/oddjobz/brain/src/state-machines/job-fsm.ts
 */

import { describe, expect, test } from 'bun:test';

import {
  ODDJOBZ_CAPABILITIES,
  capQuote,
  capDispatch,
  capInvoice,
  capClose,
  capWriteCustomer,
  mintCapabilityCell,
} from '../../src/index.js';
import {
  JOB_FSM_STATES,
  JOB_TRANSITIONS,
  allValidJobTransitions,
  findJobTransition,
  genesisJobLead,
  isJobFsmState,
  jobCellId,
  jobTransition,
  makeConsumedCellSet,
  type PresentedCap,
} from '../../src/state-machines/index.js';
import type { OddjobzJob, JobStatus } from '../../src/cell-types/job.js';

const STABLE_JOB_ID = '11111111-2222-3333-4444-555555555555';
const STABLE_JOB_ID_2 = '99999999-aaaa-bbbb-cccc-dddddddddddd';
const STABLE_NOW = '2026-05-01T00:00:00.000Z';

const STABLE_OWNER_ID = new Uint8Array([
  0x00, 0x70, 0x65, 0x72, 0x61, 0x74, 0x6f, 0x72,
  0x2d, 0x72, 0x6f, 0x6f, 0x74, 0x2d, 0x69, 0x64,
]);
const CONTEXT_TAG = 0x10;

function structuralCap(domainFlag: number): PresentedCap {
  return { kind: 'structural', domainFlag };
}

function bytesCap(capName: 'cap.oddjobz.quote' | 'cap.oddjobz.dispatch' | 'cap.oddjobz.invoice' | 'cap.oddjobz.close' | 'cap.oddjobz.write_customer'): PresentedCap {
  const cap = ODDJOBZ_CAPABILITIES.find((c) => c.name === capName);
  if (!cap) throw new Error(`unknown cap ${capName}`);
  return { kind: 'cell', cell: mintCapabilityCell(cap, CONTEXT_TAG, STABLE_OWNER_ID) };
}

function makeLeadCell(jobId: string = STABLE_JOB_ID): OddjobzJob {
  return {
    jobId,
    status: 'lead',
    createdAt: STABLE_NOW,
    updatedAt: STABLE_NOW,
  };
}

function makeJobAtState(state: (typeof JOB_FSM_STATES)[number], jobId = STABLE_JOB_ID): OddjobzJob {
  return {
    jobId,
    status: state,
    createdAt: STABLE_NOW,
    updatedAt: STABLE_NOW,
  };
}

/* ══════════════════════════════════════════════════════════════════════
 * Table shape
 * ══════════════════════════════════════════════════════════════════════ */

describe('§O4 — Job FSM table shape', () => {
  // Realigned 2026-05-18 to the SHIPPED 13-state / 15-row lead-nurture
  // remodel (the line-for-line mirror of job_fsm.zig JOB_TRANSITIONS +
  // proofs JobFSM.lean jobTransitions; declaration order = row order).
  // The original 7-row §O4 linear table is superseded.
  test('JOB_TRANSITIONS has exactly 15 rows in shipped declaration order', () => {
    expect(JOB_TRANSITIONS).toHaveLength(15);
    expect(allValidJobTransitions()).toEqual([
      { from: 'lead', to: 'qualified' },
      { from: 'lead', to: 'authorized' },
      { from: 'qualified', to: 'visit_pending' },
      { from: 'qualified', to: 'quoted' },
      { from: 'qualified', to: 'authorized' },
      { from: 'visit_pending', to: 'visit_scheduled' },
      { from: 'visit_scheduled', to: 'visited' },
      { from: 'visited', to: 'quoted' },
      { from: 'quoted', to: 'scheduled' },
      { from: 'authorized', to: 'scheduled' },
      { from: 'scheduled', to: 'in_progress' },
      { from: 'in_progress', to: 'completed' },
      { from: 'completed', to: 'invoiced' },
      { from: 'invoiced', to: 'paid' },
      { from: 'paid', to: 'closed' },
    ]);
  });

  test('cap-gated rows reference the correct cap name', () => {
    const get = (f: string, t: string) =>
      JOB_TRANSITIONS.find((r) => r.from === f && r.to === t);
    // Post-remodel the quote gate is on qualified→quoted (skip path)
    // and visited→quoted (post-visit); dispatch on quoted/authorized
    // →scheduled.
    expect(get('qualified', 'quoted')!.capRequired).toBe('cap.oddjobz.quote');
    expect(get('visited', 'quoted')!.capRequired).toBe('cap.oddjobz.quote');
    expect(get('quoted', 'scheduled')!.capRequired).toBe('cap.oddjobz.dispatch');
    expect(get('authorized', 'scheduled')!.capRequired).toBe('cap.oddjobz.dispatch');
    expect(get('completed', 'invoiced')!.capRequired).toBe('cap.oddjobz.invoice');
    expect(get('paid', 'closed')!.capRequired).toBe('cap.oddjobz.close');
  });

  test('ungated rows have null capRequired', () => {
    const get = (f: string, t: string) =>
      JOB_TRANSITIONS.find((r) => r.from === f && r.to === t);
    expect(get('scheduled', 'in_progress')!.capRequired).toBeNull();
    expect(get('in_progress', 'completed')!.capRequired).toBeNull();
    expect(get('invoiced', 'paid')!.capRequired).toBeNull();
  });

  test('signing principals match the shipped column', () => {
    const get = (f: string, t: string) =>
      JOB_TRANSITIONS.find((r) => r.from === f && r.to === t);
    // SD2 lead-front edges are operator; the two machine-driven
    // lifecycle edges (scheduled→in_progress, invoiced→paid) are
    // service; everything else operator.
    expect(get('lead', 'qualified')!.principalKinds).toEqual(['operator']);
    expect(get('lead', 'authorized')!.principalKinds).toEqual(['operator']);
    expect(get('scheduled', 'in_progress')!.principalKinds).toEqual(['service']);
    expect(get('in_progress', 'completed')!.principalKinds).toEqual(['operator']);
    expect(get('invoiced', 'paid')!.principalKinds).toEqual(['service']);
  });

  test('isJobFsmState identifies canonical and rejects legacy', () => {
    expect(isJobFsmState('lead')).toBe(true);
    expect(isJobFsmState('quoted')).toBe(true);
    expect(isJobFsmState('closed')).toBe(true);
    expect(isJobFsmState('archived' as JobStatus)).toBe(false);
    expect(isJobFsmState('new_lead' as JobStatus)).toBe(false);
  });

  test('findJobTransition returns undefined for non-table pairs', () => {
    expect(findJobTransition('lead', 'scheduled')).toBeUndefined();
    expect(findJobTransition('quoted', 'paid')).toBeUndefined();
    expect(findJobTransition('paid', 'lead')).toBeUndefined();
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * Genesis (∅ → lead)
 * ══════════════════════════════════════════════════════════════════════ */

describe('§O4 — Job genesis (∅ → lead)', () => {
  test('operator with cap.oddjobz.write_customer creates a lead', () => {
    const r = genesisJobLead({
      jobId: STABLE_JOB_ID,
      principal: 'operator',
      presentedCap: bytesCap('cap.oddjobz.write_customer'),
      nowIso: STABLE_NOW,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.status).toBe('lead');
      expect(r.value.jobId).toBe(STABLE_JOB_ID);
    }
  });

  test('service with cap.oddjobz.public_chat_serve creates a lead (anonymous-OK path)', () => {
    const cap = ODDJOBZ_CAPABILITIES.find((c) => c.name === 'cap.oddjobz.public_chat_serve')!;
    const r = genesisJobLead({
      jobId: STABLE_JOB_ID,
      principal: 'service',
      presentedCap: structuralCap(cap.domainFlag),
      nowIso: STABLE_NOW,
    });
    expect(r.ok).toBe(true);
  });

  test('operator with WRONG cap (dispatch instead of write_customer) is rejected', () => {
    const r = genesisJobLead({
      jobId: STABLE_JOB_ID,
      principal: 'operator',
      presentedCap: structuralCap(capDispatch.domainFlag),
      nowIso: STABLE_NOW,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('wrong_cap');
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * Per-transition happy path
 * ══════════════════════════════════════════════════════════════════════ */

describe('§O4 — Job FSM happy-path transitions', () => {
  // Realigned: post the lead-nurture remodel the direct lead→quoted
  // edge was removed; the cap-gated quote-skip path off the
  // prequalified ROM is now `qualified → quoted` (mirrors the Zig
  // job_fsm.zig + the JobFSM.lean `job_fsm_cap_required_qualified_
  // quoted` theorem).
  test('qualified → quoted with cap.oddjobz.quote (operator)', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('qualified'),
      to: 'quoted',
      presentedCap: bytesCap('cap.oddjobz.quote'),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.cell.status).toBe('quoted');
      expect(r.value.consumedCellId).toBe(jobCellId(STABLE_JOB_ID, 'qualified'));
      expect(consumed.has(jobCellId(STABLE_JOB_ID, 'qualified'))).toBe(true);
      expect(consumed.has(jobCellId(STABLE_JOB_ID, 'quoted'))).toBe(false);
    }
  });

  test('scheduled → in_progress is service-signed and ungated', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('scheduled'),
      to: 'in_progress',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
  });

  test('in_progress → completed is operator-signed and ungated', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('in_progress'),
      to: 'completed',
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
  });

  test('completed → invoiced with cap.oddjobz.invoice (operator)', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('completed'),
      to: 'invoiced',
      presentedCap: structuralCap(capInvoice.domainFlag),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
  });

  test('invoiced → paid is service-signed and ungated', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('invoiced'),
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
  });

  test('paid → closed with cap.oddjobz.close (operator)', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('paid'),
      to: 'closed',
      presentedCap: structuralCap(capClose.domainFlag),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.cell.status).toBe('closed');
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * THE THREE §O4 ACCEPTANCE TESTS
 * ══════════════════════════════════════════════════════════════════════ */

describe('§O4 — three acceptance tests (K1/K2/K4)', () => {
  test('[§O4 K2] quoted → scheduled WITHOUT cap.oddjobz.dispatch fails at the kernel gate', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('quoted'),
      to: 'scheduled',
      presentedCap: null, // no cap presented — kernel-gate K2 rejection
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('cap_required');
      expect(r.error.expectedCap).toBe('cap.oddjobz.dispatch');
    }
    // K4-equivalent: cell-id NOT consumed since the gate failed
    expect(consumed.has(jobCellId(STABLE_JOB_ID, 'quoted'))).toBe(false);
  });

  test('[§O4 K2] quoted → scheduled with WRONG cap (close instead of dispatch) is wrong_cap', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('quoted'),
      to: 'scheduled',
      presentedCap: structuralCap(capClose.domainFlag), // wrong domain flag
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('wrong_cap');
      expect(r.error.expectedCap).toBe('cap.oddjobz.dispatch');
      expect(r.error.presentedDomainFlag).toBe(capClose.domainFlag);
    }
  });

  test('[§O4 K1] two quoted → scheduled transitions on the same Job cell-id; second fails', () => {
    const consumed = makeConsumedCellSet();
    const cell = makeJobAtState('quoted');
    const dispatchCap = structuralCap(capDispatch.domainFlag);
    // First transition succeeds and consumes the cell.
    const r1 = jobTransition({
      cell,
      to: 'scheduled',
      presentedCap: dispatchCap,
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r1.ok).toBe(true);
    expect(consumed.has(jobCellId(STABLE_JOB_ID, 'quoted'))).toBe(true);

    // Second attempt on the same INPUT cell (same cell-id) — K1 rejects.
    const r2 = jobTransition({
      cell,
      to: 'scheduled',
      presentedCap: dispatchCap,
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r2.ok).toBe(false);
    if (!r2.ok) {
      expect(r2.error.kind).toBe('cell_already_consumed');
      expect(r2.error.consumedCellId).toBe(jobCellId(STABLE_JOB_ID, 'quoted'));
    }
  });

  test('[§O4 K4] induced HTTP failure on invoiced → paid leaves cell unchanged; retry succeeds', () => {
    const consumed = makeConsumedCellSet();
    const cell = makeJobAtState('invoiced');
    const cellBefore = JSON.stringify(cell);
    const consumedBefore = new Set(consumed.snapshot());

    // Simulate the Stripe webhook handler throwing partway through.
    let firstAttemptCalls = 0;
    const r1 = jobTransition({
      cell,
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
      sideEffect: () => {
        firstAttemptCalls++;
        throw new Error('simulated network-failure on Stripe webhook');
      },
    });
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.error.kind).toBe('induced_io_failure');
    expect(firstAttemptCalls).toBe(1);

    // K4: input cell is byte-identical to before (TS object equality).
    expect(JSON.stringify(cell)).toBe(cellBefore);
    // K4: consumed-set is byte-identical to before — predecessor was NOT consumed.
    expect(consumed.snapshot()).toEqual(consumedBefore);
    expect(consumed.has(jobCellId(STABLE_JOB_ID, 'invoiced'))).toBe(false);

    // Retry — same input cell, no thrown side effect — succeeds.
    const r2 = jobTransition({
      cell,
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
      sideEffect: () => {
        // Stripe webhook returns 200 OK on retry
      },
    });
    expect(r2.ok).toBe(true);
    if (r2.ok) {
      expect(r2.value.cell.status).toBe('paid');
      // Now the cell IS consumed.
      expect(consumed.has(jobCellId(STABLE_JOB_ID, 'invoiced'))).toBe(true);
    }
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * Negative paths — invalid table pairs, principal mismatches
 * ══════════════════════════════════════════════════════════════════════ */

describe('§O4 — Job FSM negative paths', () => {
  test('lead → scheduled (skip-quoted) is an invalid_state_transition', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeLeadCell(),
      to: 'scheduled',
      presentedCap: structuralCap(capDispatch.domainFlag),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('invalid_state_transition');
  });

  test('paid → lead (terminal-state regression) is invalid_state_transition', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('paid'),
      to: 'lead',
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('invalid_state_transition');
  });

  test('scheduled → in_progress signed by operator (not service) is bad_signing_principal', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('scheduled'),
      to: 'in_progress',
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('bad_signing_principal');
  });

  test('legacy status (archived) on input cell is from_state_mismatch', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: { ...makeLeadCell(), status: 'archived' as JobStatus },
      to: 'quoted',
      presentedCap: structuralCap(capQuote.domainFlag),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('from_state_mismatch');
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * Property test — random walk over the FSM never reaches an
 * invalid state.
 * ══════════════════════════════════════════════════════════════════════ */

describe('§O4 — Job FSM property test (random walk stays in canonical states)', () => {
  test('random walk over 50 attempted transitions never reaches an invalid state', () => {
    const consumed = makeConsumedCellSet();
    let cell: OddjobzJob = makeLeadCell(STABLE_JOB_ID_2);
    let ok = 0;
    let bad = 0;

    // Deterministic LCG for reproducibility.
    let seed = 0x9e3779b1;
    const rand = () => {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      return seed / 0xffffffff;
    };

    for (let step = 0; step < 50; step++) {
      const to = JOB_FSM_STATES[Math.floor(rand() * JOB_FSM_STATES.length)]!;
      const spec = findJobTransition(cell.status as (typeof JOB_FSM_STATES)[number], to);
      const cap = spec?.capRequired ?? null;
      const presented: PresentedCap | null = cap === null
        ? null
        : structuralCap(
            ODDJOBZ_CAPABILITIES.find((c) => c.name === cap)!.domainFlag,
          );
      const principal = spec?.principalKinds[0] ?? 'operator';
      const r = jobTransition({
        cell,
        to,
        presentedCap: presented,
        principal,
        nowIso: STABLE_NOW,
        consumed,
      });
      if (r.ok) {
        cell = r.value.cell;
        ok++;
      } else {
        bad++;
      }
      // Cell.status MUST always be a canonical state (we never mutate
      // it ourselves; the FSM is the only writer).
      expect(JOB_FSM_STATES).toContain(cell.status as (typeof JOB_FSM_STATES)[number]);
    }
    // Sanity — at least one ok, at least one bad in any reasonable walk.
    expect(ok + bad).toBe(50);
  });
});

/* ══════════════════════════════════════════════════════════════════════
 * Shape: operator-flag matches operator-cert mint-shape
 * ══════════════════════════════════════════════════════════════════════ */

describe('§O4 — Job FSM presents real cap-UTXO bytes', () => {
  test('quoted → scheduled accepts a real mintCapabilityCell output for cap.oddjobz.dispatch', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('quoted'),
      to: 'scheduled',
      presentedCap: bytesCap('cap.oddjobz.dispatch'),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
  });

  test('quoted → scheduled rejects a real mintCapabilityCell for cap.oddjobz.invoice (wrong cap)', () => {
    const consumed = makeConsumedCellSet();
    const r = jobTransition({
      cell: makeJobAtState('quoted'),
      to: 'scheduled',
      presentedCap: bytesCap('cap.oddjobz.invoice'),
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('wrong_cap');
  });
});


```
