---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/state-machines/invoice-fsm.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.490664+00:00
---

# cartridges/oddjobz/brain/tests/state-machines/invoice-fsm.test.ts

```ts
/**
 * D-O4 — Invoice FSM tests.
 *
 * The §O4 K4 acceptance test grounds in this FSM's `sent → paid`
 * (and `viewed → paid`, `partial → paid`, `overdue → paid`) — an
 * induced HTTP failure on the Stripe webhook leaves the Invoice
 * cell byte-for-byte unchanged and a retry succeeds.
 */

import { describe, expect, test } from 'bun:test';

import {
  INVOICE_FSM_STATES,
  INVOICE_TRANSITIONS,
  allValidInvoiceTransitions,
  findInvoiceTransition,
  invoiceCellId,
  invoiceTransition,
  isInvoiceFsmState,
  makeConsumedCellSet,
} from '../../src/state-machines/index.js';
import type { OddjobzInvoice, InvoiceStatus } from '../../src/cell-types/invoice.js';

const STABLE_INVOICE_ID = 'a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5';
const STABLE_JOB_ID = '11111111-2222-3333-4444-555555555555';
const STABLE_NOW = '2026-05-01T00:00:00.000Z';
const AMOUNT_CENTS = 250_00;

function makeInvoiceCell(state: (typeof INVOICE_FSM_STATES)[number]): OddjobzInvoice {
  const base: OddjobzInvoice = {
    invoiceId: STABLE_INVOICE_ID,
    jobId: STABLE_JOB_ID,
    status: state,
    amount: AMOUNT_CENTS,
    createdAt: STABLE_NOW,
    updatedAt: STABLE_NOW,
  };
  // The cell-type validator requires sentAt for `sent`, paidAt for `paid`.
  if (state === 'sent') return { ...base, sentAt: STABLE_NOW };
  if (state === 'paid') return { ...base, sentAt: STABLE_NOW, paidAt: STABLE_NOW, amountPaid: AMOUNT_CENTS };
  return base;
}

describe('§O4 — Invoice FSM table shape', () => {
  test('INVOICE_TRANSITIONS contains the §O4-inferred shape', () => {
    const pairs = allValidInvoiceTransitions();
    expect(pairs).toContainEqual({ from: 'draft', to: 'sent' });
    expect(pairs).toContainEqual({ from: 'sent', to: 'paid' });
    expect(pairs).toContainEqual({ from: 'sent', to: 'viewed' });
    expect(pairs).toContainEqual({ from: 'viewed', to: 'paid' });
    expect(pairs).toContainEqual({ from: 'partial', to: 'paid' });
    expect(pairs).toContainEqual({ from: 'overdue', to: 'paid' });
  });

  test('every Invoice transition is gateless at the cell layer', () => {
    for (const t of INVOICE_TRANSITIONS) {
      expect(t.capRequired).toBeNull();
    }
  });

  test('isInvoiceFsmState identifies canonical', () => {
    expect(isInvoiceFsmState('draft')).toBe(true);
    expect(isInvoiceFsmState('sent')).toBe(true);
    expect(isInvoiceFsmState('paid')).toBe(true);
    expect(isInvoiceFsmState('garbled' as InvoiceStatus)).toBe(false);
  });
});

describe('§O4 — Invoice FSM happy-path', () => {
  test('draft → sent (operator-signed, ungated)', () => {
    const consumed = makeConsumedCellSet();
    const r = invoiceTransition({
      cell: makeInvoiceCell('draft'),
      to: 'sent',
      principal: 'operator',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.cell.status).toBe('sent');
      expect(r.value.cell.sentAt).toBe(STABLE_NOW);
    }
  });

  test('sent → paid (service-signed, full payment)', () => {
    const consumed = makeConsumedCellSet();
    const r = invoiceTransition({
      cell: makeInvoiceCell('sent'),
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      amountPaid: AMOUNT_CENTS,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.cell.status).toBe('paid');
      expect(r.value.cell.amountPaid).toBe(AMOUNT_CENTS);
      expect(r.value.cell.paidAt).toBe(STABLE_NOW);
    }
  });

  test('sent → partial with partial payment', () => {
    const consumed = makeConsumedCellSet();
    const r = invoiceTransition({
      cell: makeInvoiceCell('sent'),
      to: 'partial',
      principal: 'service',
      nowIso: STABLE_NOW,
      amountPaid: 100_00,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.cell.status).toBe('partial');
      expect(r.value.cell.amountPaid).toBe(100_00);
    }
  });

  test('partial → paid completes the payment', () => {
    const consumed = makeConsumedCellSet();
    const r = invoiceTransition({
      cell: { ...makeInvoiceCell('partial'), sentAt: STABLE_NOW, amountPaid: 100_00 },
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.cell.amountPaid).toBe(AMOUNT_CENTS);
  });
});

describe('§O4 — Invoice FSM acceptance tests (K1/K2/K4)', () => {
  test('[§O4 K1] two sent → paid on the same cell; second fails', () => {
    const consumed = makeConsumedCellSet();
    const cell = makeInvoiceCell('sent');
    const r1 = invoiceTransition({
      cell,
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      amountPaid: AMOUNT_CENTS,
      consumed,
    });
    expect(r1.ok).toBe(true);
    const r2 = invoiceTransition({
      cell,
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      amountPaid: AMOUNT_CENTS,
      consumed,
    });
    expect(r2.ok).toBe(false);
    if (!r2.ok) {
      expect(r2.error.kind).toBe('cell_already_consumed');
      expect(r2.error.consumedCellId).toBe(invoiceCellId(STABLE_INVOICE_ID, 'sent'));
    }
  });

  test('[§O4 K2] sent → paid signed by operator (not service) is bad_signing_principal', () => {
    const consumed = makeConsumedCellSet();
    const r = invoiceTransition({
      cell: makeInvoiceCell('sent'),
      to: 'paid',
      principal: 'operator', // wrong — should be service
      nowIso: STABLE_NOW,
      amountPaid: AMOUNT_CENTS,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('bad_signing_principal');
  });

  test('[§O4 K4] induced HTTP failure on sent → paid leaves cell unchanged; retry succeeds', () => {
    const consumed = makeConsumedCellSet();
    const cell = makeInvoiceCell('sent');
    const before = JSON.stringify(cell);
    const consumedBefore = new Set(consumed.snapshot());

    let attempts = 0;
    const r1 = invoiceTransition({
      cell,
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      amountPaid: AMOUNT_CENTS,
      consumed,
      sideEffect: () => {
        attempts++;
        throw new Error('simulated Stripe webhook 500');
      },
    });
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.error.kind).toBe('induced_io_failure');
    expect(attempts).toBe(1);
    expect(JSON.stringify(cell)).toBe(before);
    expect(consumed.snapshot()).toEqual(consumedBefore);
    expect(consumed.has(invoiceCellId(STABLE_INVOICE_ID, 'sent'))).toBe(false);

    const r2 = invoiceTransition({
      cell,
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      amountPaid: AMOUNT_CENTS,
      consumed,
    });
    expect(r2.ok).toBe(true);
    if (r2.ok) {
      expect(r2.value.cell.status).toBe('paid');
      expect(consumed.has(invoiceCellId(STABLE_INVOICE_ID, 'sent'))).toBe(true);
    }
  });
});

describe('§O4 — Invoice FSM negative paths', () => {
  test('draft → paid (skip-sent) is invalid_state_transition', () => {
    const consumed = makeConsumedCellSet();
    const r = invoiceTransition({
      cell: makeInvoiceCell('draft'),
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('invalid_state_transition');
  });

  test('cancelled → paid (terminal regression) is invalid_state_transition', () => {
    const consumed = makeConsumedCellSet();
    const r = invoiceTransition({
      cell: makeInvoiceCell('cancelled'),
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('invalid_state_transition');
  });

  test('partial → paid with amountPaid != amount is invalid_state_transition', () => {
    const consumed = makeConsumedCellSet();
    const r = invoiceTransition({
      cell: { ...makeInvoiceCell('partial'), sentAt: STABLE_NOW, amountPaid: 100_00 },
      to: 'paid',
      principal: 'service',
      nowIso: STABLE_NOW,
      amountPaid: 100_00, // less than amount — invalid for `paid` status
      consumed,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('invalid_state_transition');
  });
});

describe('§O4 — Invoice FSM property test', () => {
  test('random walk: status always canonical', () => {
    const consumed = makeConsumedCellSet();
    let cell: OddjobzInvoice = makeInvoiceCell('draft');
    let seed = 0xb0a710ad;
    const rand = () => {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      return seed / 0xffffffff;
    };
    for (let i = 0; i < 30; i++) {
      const to = INVOICE_FSM_STATES[Math.floor(rand() * INVOICE_FSM_STATES.length)]!;
      const spec = findInvoiceTransition(
        cell.status as (typeof INVOICE_FSM_STATES)[number],
        to,
      );
      const principal = spec?.principalKinds[0] ?? 'operator';
      const r = invoiceTransition({
        cell,
        to,
        principal,
        nowIso: STABLE_NOW,
        amountPaid: cell.amount,
        consumed,
      });
      if (r.ok) cell = r.value.cell;
      expect(INVOICE_FSM_STATES).toContain(
        cell.status as (typeof INVOICE_FSM_STATES)[number],
      );
    }
  });
});

```
