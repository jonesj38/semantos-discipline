---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/customer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.502968+00:00
---

# cartridges/oddjobz/brain/src/cell-types/customer.ts

```ts
/**
 * `oddjobz.customer.v1` — PERSISTENT cell.
 *
 * Identity record for a trades customer. Per §O2: a Customer accumulates
 * Job/Visit/Invoice references over time and is never consumed
 * (PERSISTENT → wire RELEVANT). The customer's mutable contact details
 * are tracked via `prevStateHash`-chained state cells of the same type;
 * the cell payload below is the latest snapshot.
 *
 * Field shape derived from oddjobtodd's `customers` table and the
 * `sem_trades_customers` projection (`schema.trades.ts`). Operator-only
 * fields like notes are kept; org affiliation is an outer-context concern
 * (the operator's tenant) and not encoded in the cell.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertNonEmptyString,
  assertOptionalString,
  assertEnum,
  assertIsoDateString,
} from './validators.js';

export const CONTACT_CHANNELS = ['phone', 'sms', 'email', 'webchat', 'in_person'] as const;
export type ContactChannel = (typeof CONTACT_CHANNELS)[number];

export interface OddjobzCustomer {
  /** Stable customer identifier (UUID v4). */
  readonly customerId: string;
  /** Display name. */
  readonly name: string;
  /** Optional E.164 mobile/phone. */
  readonly phone?: string;
  /** Optional email address (unverified by default). */
  readonly email?: string;
  /** Operator-set preferred contact channel. */
  readonly preferredChannel?: ContactChannel;
  /** ISO-8601 timestamp at which mobile was verified, if ever. */
  readonly mobileVerifiedAt?: string;
  /** ISO-8601 timestamp at which email was verified, if ever. */
  readonly emailVerifiedAt?: string;
  /** Free-form operator notes about the customer. */
  readonly notes?: string;
  /** Legacy customer ID from the OJT prototype (UUID), for migration. */
  readonly legacyCustomerId?: string;
  /** Cell creation timestamp (ISO-8601). */
  readonly createdAt: string;
  /** Last-update timestamp (ISO-8601); equals createdAt for the genesis cell. */
  readonly updatedAt: string;
}

function validate(v: OddjobzCustomer): void {
  assertUuid('customerId', v.customerId);
  assertNonEmptyString('name', v.name);
  assertOptionalString('phone', v.phone);
  assertOptionalString('email', v.email);
  if (v.preferredChannel !== undefined) {
    assertEnum('preferredChannel', v.preferredChannel, CONTACT_CHANNELS);
  }
  if (v.mobileVerifiedAt !== undefined) assertIsoDateString('mobileVerifiedAt', v.mobileVerifiedAt);
  if (v.emailVerifiedAt !== undefined) assertIsoDateString('emailVerifiedAt', v.emailVerifiedAt);
  assertOptionalString('notes', v.notes);
  if (v.legacyCustomerId !== undefined) assertUuid('legacyCustomerId', v.legacyCustomerId);
  assertIsoDateString('createdAt', v.createdAt);
  assertIsoDateString('updatedAt', v.updatedAt);
}

function toCanonical(v: OddjobzCustomer): Record<string, unknown> {
  const out: Record<string, unknown> = {
    customerId: v.customerId,
    name: v.name,
    createdAt: v.createdAt,
    updatedAt: v.updatedAt,
  };
  if (v.phone !== undefined) out.phone = v.phone;
  if (v.email !== undefined) out.email = v.email;
  if (v.preferredChannel !== undefined) out.preferredChannel = v.preferredChannel;
  if (v.mobileVerifiedAt !== undefined) out.mobileVerifiedAt = v.mobileVerifiedAt;
  if (v.emailVerifiedAt !== undefined) out.emailVerifiedAt = v.emailVerifiedAt;
  if (v.notes !== undefined) out.notes = v.notes;
  if (v.legacyCustomerId !== undefined) out.legacyCustomerId = v.legacyCustomerId;
  return out;
}

function fromCanonical(c: unknown): OddjobzCustomer {
  if (typeof c !== 'object' || c === null) throw new Error('customer: payload not an object');
  const r = c as Record<string, unknown>;
  return {
    customerId: r.customerId as string,
    name: r.name as string,
    phone: r.phone as string | undefined,
    email: r.email as string | undefined,
    preferredChannel: r.preferredChannel as ContactChannel | undefined,
    mobileVerifiedAt: r.mobileVerifiedAt as string | undefined,
    emailVerifiedAt: r.emailVerifiedAt as string | undefined,
    notes: r.notes as string | undefined,
    legacyCustomerId: r.legacyCustomerId as string | undefined,
    createdAt: r.createdAt as string,
    updatedAt: r.updatedAt as string,
  };
}

export const customerCellType: CellTypeDef<OddjobzCustomer> = defineCellType({
  name: 'oddjobz.customer.v1',
  identity: {
    whatPath: 'oddjobz.customer',
    howSlug: 'identify',
    instPath: 'inst.identity.customer-record',
  },
  linearity: 'PERSISTENT',
  toCanonical,
  fromCanonical,
  validate,
});

```
