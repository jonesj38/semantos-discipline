---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/site.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.507161+00:00
---

# cartridges/oddjobz/brain/src/cell-types/site.ts

```ts
/**
 * `oddjobz.site.v1` — PERSISTENT cell.
 *
 * A physical work location belonging to a customer. Per §O2: a Site
 * accumulates Visit cells over time and is never consumed
 * (PERSISTENT → wire RELEVANT). Site mutability (e.g. updated access
 * notes) flows via prevStateHash-chained state cells of the same type.
 *
 * Field shape derived from `sites` (legacy) and `sem_trades_sites`
 * (`schema.trades.ts`). Lat/lng kept as finite numbers (degrees);
 * legacy schema stores them as numeric/real, both round-trip cleanly
 * through canonical-JSON.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertNonEmptyString,
  assertOptionalString,
  assertOptionalFiniteNumber,
  assertIsoDateString,
} from './validators.js';

export interface OddjobzSite {
  /** Stable site identifier (UUID v4). */
  readonly siteId: string;
  /** Customer the site belongs to (UUID v4 of `oddjobz.customer.v1`). */
  readonly customerId: string;
  /** Address line 1 (street + number). */
  readonly addressLine1?: string;
  /** Address line 2 (unit / floor). */
  readonly addressLine2?: string;
  /** Suburb / locality. */
  readonly suburb?: string;
  /** Postcode. */
  readonly postcode?: string;
  /** State / province / region (defaults to operator's region). */
  readonly state?: string;
  /** Latitude in decimal degrees. */
  readonly lat?: number;
  /** Longitude in decimal degrees. */
  readonly lng?: number;
  /** Operator-only access notes (gate codes, dog warning, etc.). */
  readonly accessNotes?: string;
  /** General site notes (history, recurring issues). */
  readonly siteNotes?: string;
  /** Legacy site ID from the OJT prototype (UUID), for migration. */
  readonly legacySiteId?: string;
  /** Cell creation timestamp (ISO-8601). */
  readonly createdAt: string;
  /** Last-update timestamp (ISO-8601). */
  readonly updatedAt: string;
}

function validate(v: OddjobzSite): void {
  assertUuid('siteId', v.siteId);
  assertUuid('customerId', v.customerId);
  assertOptionalString('addressLine1', v.addressLine1);
  assertOptionalString('addressLine2', v.addressLine2);
  assertOptionalString('suburb', v.suburb);
  assertOptionalString('postcode', v.postcode);
  assertOptionalString('state', v.state);
  assertOptionalFiniteNumber('lat', v.lat);
  assertOptionalFiniteNumber('lng', v.lng);
  assertOptionalString('accessNotes', v.accessNotes);
  assertOptionalString('siteNotes', v.siteNotes);
  if (v.legacySiteId !== undefined) assertUuid('legacySiteId', v.legacySiteId);
  assertIsoDateString('createdAt', v.createdAt);
  assertIsoDateString('updatedAt', v.updatedAt);
  if (v.lat !== undefined) {
    if (v.lat < -90 || v.lat > 90) throw new Error('field lat: outside [-90, 90]');
  }
  if (v.lng !== undefined) {
    if (v.lng < -180 || v.lng > 180) throw new Error('field lng: outside [-180, 180]');
  }
  // Cheap consistency: name field non-empty if at all present
  if (v.addressLine1 !== undefined) assertNonEmptyString('addressLine1', v.addressLine1);
}

function toCanonical(v: OddjobzSite): Record<string, unknown> {
  const out: Record<string, unknown> = {
    siteId: v.siteId,
    customerId: v.customerId,
    createdAt: v.createdAt,
    updatedAt: v.updatedAt,
  };
  if (v.addressLine1 !== undefined) out.addressLine1 = v.addressLine1;
  if (v.addressLine2 !== undefined) out.addressLine2 = v.addressLine2;
  if (v.suburb !== undefined) out.suburb = v.suburb;
  if (v.postcode !== undefined) out.postcode = v.postcode;
  if (v.state !== undefined) out.state = v.state;
  if (v.lat !== undefined) out.lat = v.lat;
  if (v.lng !== undefined) out.lng = v.lng;
  if (v.accessNotes !== undefined) out.accessNotes = v.accessNotes;
  if (v.siteNotes !== undefined) out.siteNotes = v.siteNotes;
  if (v.legacySiteId !== undefined) out.legacySiteId = v.legacySiteId;
  return out;
}

function fromCanonical(c: unknown): OddjobzSite {
  if (typeof c !== 'object' || c === null) throw new Error('site: payload not an object');
  const r = c as Record<string, unknown>;
  return {
    siteId: r.siteId as string,
    customerId: r.customerId as string,
    addressLine1: r.addressLine1 as string | undefined,
    addressLine2: r.addressLine2 as string | undefined,
    suburb: r.suburb as string | undefined,
    postcode: r.postcode as string | undefined,
    state: r.state as string | undefined,
    lat: r.lat as number | undefined,
    lng: r.lng as number | undefined,
    accessNotes: r.accessNotes as string | undefined,
    siteNotes: r.siteNotes as string | undefined,
    legacySiteId: r.legacySiteId as string | undefined,
    createdAt: r.createdAt as string,
    updatedAt: r.updatedAt as string,
  };
}

export const siteCellType: CellTypeDef<OddjobzSite> = defineCellType({
  name: 'oddjobz.site.v1',
  identity: {
    whatPath: 'oddjobz.site',
    howSlug: 'locate',
    instPath: 'inst.location.work-site',
  },
  linearity: 'PERSISTENT',
  toCanonical,
  fromCanonical,
  validate,
});

```
