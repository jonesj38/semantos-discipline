---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/invoice.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.505825+00:00
---

# cartridges/oddjobz/brain/src/cell-types/invoice.ts

```ts
/**
 * `oddjobz.invoice.v1` — LINEAR cell.
 *
 * An invoice. Per §O2: an Invoice is consumed when paid (the §O4 FSM
 * spends the invoice cell on the `invoiced → paid` transition; the
 * payment-confirmed successor cell carries `paidAt`/`paidAmount`).
 *
 * Field shape derived from the legacy `invoices` table. Amounts are in
 * cents (smallest currency unit) — same convention as the Quote cell.
 * `externalInvoiceId` carries through to Xero/Stripe/etc. integrations
 * via §O4 push transitions.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertOptionalUuid,
  assertOptionalString,
  assertNonNegativeInt,
  assertEnum,
  assertIsoDateString,
  assertOptionalIsoDateString,
  assertOptionalNonNegativeInt,
} from './validators.js';

export const INVOICE_STATUSES = [
  'draft',
  'sent',
  'viewed',
  'partial',
  'paid',
  'overdue',
  'cancelled',
] as const;
export type InvoiceStatus = (typeof INVOICE_STATUSES)[number];

export interface OddjobzInvoice {
  /** Stable invoice identifier (UUID v4). */
  readonly invoiceId: string;
  /** Job the invoice bills (UUID v4). */
  readonly jobId: string;
  /** Customer being billed (UUID v4). */
  readonly customerId?: string;

  /** Current invoice state. */
  readonly status: InvoiceStatus;

  /** Invoice number / external system ID (Xero ref, Stripe id, etc.). */
  readonly externalInvoiceId?: string;
  /** Currency code, ISO-4217 (defaults to operator's currency). */
  readonly currency?: string;

  /** Total amount due in cents. */
  readonly amount: number;
  /** Amount already paid in cents (0 unless partial/paid). */
  readonly amountPaid?: number;

  /** ISO-8601 date the invoice was sent to the customer. */
  readonly sentAt?: string;
  /** ISO-8601 date the customer first viewed it. */
  readonly viewedAt?: string;
  /** ISO-8601 date marked paid (matches `paid` status). */
  readonly paidAt?: string;
  /** ISO-8601 date by which payment is due. */
  readonly dueAt?: string;

  /** Free-form line-item summary (the canonical lines may live in a sibling cell type later). */
  readonly summary?: string;

  /** ISO-8601 cell creation timestamp. */
  readonly createdAt: string;
  /** ISO-8601 last-update timestamp. */
  readonly updatedAt: string;
}

function validate(v: OddjobzInvoice): void {
  assertUuid('invoiceId', v.invoiceId);
  assertUuid('jobId', v.jobId);
  assertOptionalUuid('customerId', v.customerId);
  assertEnum('status', v.status, INVOICE_STATUSES);
  assertOptionalString('externalInvoiceId', v.externalInvoiceId);
  if (v.currency !== undefined) {
    if (typeof v.currency !== 'string' || !/^[A-Z]{3}$/.test(v.currency)) {
      throw new Error('invoice: currency must be ISO-4217 alpha-3 uppercase');
    }
  }
  assertNonNegativeInt('amount', v.amount);
  assertOptionalNonNegativeInt('amountPaid', v.amountPaid);
  if (v.amountPaid !== undefined && v.amountPaid > v.amount) {
    throw new Error('invoice: amountPaid exceeds amount');
  }
  assertOptionalIsoDateString('sentAt', v.sentAt);
  assertOptionalIsoDateString('viewedAt', v.viewedAt);
  assertOptionalIsoDateString('paidAt', v.paidAt);
  assertOptionalIsoDateString('dueAt', v.dueAt);
  assertOptionalString('summary', v.summary);
  assertIsoDateString('createdAt', v.createdAt);
  assertIsoDateString('updatedAt', v.updatedAt);

  if (v.status === 'paid' && v.paidAt === undefined) {
    throw new Error('invoice: status=paid requires paidAt');
  }
  if (v.status === 'paid') {
    const paid = v.amountPaid ?? v.amount;
    if (paid !== v.amount) {
      throw new Error('invoice: status=paid requires amountPaid === amount');
    }
  }
  if (v.status === 'sent' && v.sentAt === undefined) {
    throw new Error('invoice: status=sent requires sentAt');
  }
}

function toCanonical(v: OddjobzInvoice): Record<string, unknown> {
  const out: Record<string, unknown> = {
    invoiceId: v.invoiceId,
    jobId: v.jobId,
    status: v.status,
    amount: v.amount,
    createdAt: v.createdAt,
    updatedAt: v.updatedAt,
  };
  if (v.customerId !== undefined) out.customerId = v.customerId;
  if (v.externalInvoiceId !== undefined) out.externalInvoiceId = v.externalInvoiceId;
  if (v.currency !== undefined) out.currency = v.currency;
  if (v.amountPaid !== undefined) out.amountPaid = v.amountPaid;
  if (v.sentAt !== undefined) out.sentAt = v.sentAt;
  if (v.viewedAt !== undefined) out.viewedAt = v.viewedAt;
  if (v.paidAt !== undefined) out.paidAt = v.paidAt;
  if (v.dueAt !== undefined) out.dueAt = v.dueAt;
  if (v.summary !== undefined) out.summary = v.summary;
  return out;
}

function fromCanonical(c: unknown): OddjobzInvoice {
  if (typeof c !== 'object' || c === null) throw new Error('invoice: payload not an object');
  const r = c as Record<string, unknown>;
  return {
    invoiceId: r.invoiceId as string,
    jobId: r.jobId as string,
    customerId: r.customerId as string | undefined,
    status: r.status as InvoiceStatus,
    externalInvoiceId: r.externalInvoiceId as string | undefined,
    currency: r.currency as string | undefined,
    amount: r.amount as number,
    amountPaid: r.amountPaid as number | undefined,
    sentAt: r.sentAt as string | undefined,
    viewedAt: r.viewedAt as string | undefined,
    paidAt: r.paidAt as string | undefined,
    dueAt: r.dueAt as string | undefined,
    summary: r.summary as string | undefined,
    createdAt: r.createdAt as string,
    updatedAt: r.updatedAt as string,
  };
}

export const invoiceCellType: CellTypeDef<OddjobzInvoice> = defineCellType({
  name: 'oddjobz.invoice.v1',
  identity: {
    whatPath: 'oddjobz.invoice',
    howSlug: 'bill',
    instPath: 'inst.contract.invoice',
  },
  linearity: 'LINEAR',
  toCanonical,
  fromCanonical,
  validate,
});

```
