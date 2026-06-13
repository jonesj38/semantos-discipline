---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/cell-types/envelope.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.516649+00:00
---

# packages/dispatch/dispatch/src/cell-types/envelope.ts

```ts
/**
 * `dispatch.envelope.v1` — LINEAR cell.
 *
 * D-O11 phase O11b — the bridge primitive. A dispatch envelope is the
 * single semantic object that bridges two independent vertical
 * extensions across a federation seam.
 *
 * The envelope is LINEAR: per chapter 29 it must be consumed at
 * least once on the receiving side (K1 enforcement; an envelope that
 * is created but never accepted is a kernel-invariant violation, not
 * just a missed delivery). The receiving brain's accept-handler
 * consumes the envelope cell-id when it materialises the payload
 * into a vertical-B cell.
 *
 * Field shape per chapter 29 + ODDJOBZ-EXTENSION-PLAN.md §3 phase O11:
 *
 *   envelopeId       — stable envelope identifier (UUID v4)
 *   fromTenant       — originating tenant domain (e.g. `acme-pm.com`)
 *   fromHat          — originating hat-id (e.g. `pm-alice`)
 *   toTenant         — receiving tenant domain (e.g. `oddjobtodd.info`)
 *   toHat            — receiving hat-id (e.g. `tradie-todd`)
 *   payloadType      — canonical name of the inner cell type
 *                      (e.g. `re-desk.maintenance-request.v1`)
 *   payload          — canonical-encoded inner cell bytes (hex)
 *   signedBy         — cert id chain (lower-case hex; semicolon-
 *                      separated for chain depth > 1)
 *   createdAt        — ISO-8601 envelope creation timestamp
 */

import {
  defineCellType,
  type CellTypeDef,
} from '@semantos/oddjobz/cell-types';
import {
  assertEnum,
  assertHex,
  assertIsoDateString,
  assertNonEmptyString,
  assertTenantHatRef,
  assertUuid,
} from './validators.js';

export const ENVELOPE_TENANT_RE = /^[a-z0-9.-]+$/;
export const ENVELOPE_HAT_RE = /^[a-z0-9-]+$/;

export interface DispatchEnvelope {
  /** Stable envelope identifier (UUID v4). */
  readonly envelopeId: string;
  /** Originating tenant domain. */
  readonly fromTenant: string;
  /** Originating hat-id. */
  readonly fromHat: string;
  /** Receiving tenant domain. */
  readonly toTenant: string;
  /** Receiving hat-id. */
  readonly toHat: string;
  /** Canonical name of the inner cell (e.g. `re-desk.maintenance-request.v1`). */
  readonly payloadType: string;
  /** Lower-case hex encoding of the canonical inner cell bytes. */
  readonly payload: string;
  /** Signing cert chain (hex; semicolon-separated for chain depth > 1). */
  readonly signedBy: string;
  /** ISO-8601 envelope creation timestamp. */
  readonly createdAt: string;
}

function validate(v: DispatchEnvelope): void {
  assertUuid('envelopeId', v.envelopeId);
  assertNonEmptyString('fromTenant', v.fromTenant);
  if (!ENVELOPE_TENANT_RE.test(v.fromTenant)) {
    throw new Error(`field fromTenant: must match ${ENVELOPE_TENANT_RE.source}`);
  }
  assertNonEmptyString('fromHat', v.fromHat);
  if (!ENVELOPE_HAT_RE.test(v.fromHat)) {
    throw new Error(`field fromHat: must match ${ENVELOPE_HAT_RE.source}`);
  }
  assertNonEmptyString('toTenant', v.toTenant);
  if (!ENVELOPE_TENANT_RE.test(v.toTenant)) {
    throw new Error(`field toTenant: must match ${ENVELOPE_TENANT_RE.source}`);
  }
  assertNonEmptyString('toHat', v.toHat);
  if (!ENVELOPE_HAT_RE.test(v.toHat)) {
    throw new Error(`field toHat: must match ${ENVELOPE_HAT_RE.source}`);
  }
  assertNonEmptyString('payloadType', v.payloadType);
  assertHex('payload', v.payload);
  assertNonEmptyString('signedBy', v.signedBy);
  assertIsoDateString('createdAt', v.createdAt);

  // Cross-tenant invariant: an envelope MUST cross a tenant boundary.
  // A same-tenant dispatch is an architectural mistake — chapter 29
  // §"Do not anchor when the exchange is within a single governance
  // domain" explicitly forbids it. The kernel-gate equivalent of this
  // check is at the dispatch-handler altitude (the receiving brain
  // only accepts envelopes addressed to a different operator); we
  // surface it here at validate-time so an attempt to construct one
  // is structurally rejected.
  if (v.fromTenant === v.toTenant && v.fromHat === v.toHat) {
    throw new Error(
      `dispatch.envelope.v1: from and to are identical (${v.fromTenant}#${v.fromHat}) — same-hat dispatch is forbidden`,
    );
  }

  // Avoid unused-imports.
  void assertEnum;
}

function toCanonical(v: DispatchEnvelope): Record<string, unknown> {
  return {
    envelopeId: v.envelopeId,
    fromTenant: v.fromTenant,
    fromHat: v.fromHat,
    toTenant: v.toTenant,
    toHat: v.toHat,
    payloadType: v.payloadType,
    payload: v.payload,
    signedBy: v.signedBy,
    createdAt: v.createdAt,
  };
}

function fromCanonical(c: unknown): DispatchEnvelope {
  if (typeof c !== 'object' || c === null) {
    throw new Error('dispatch.envelope.v1: payload not an object');
  }
  const r = c as Record<string, unknown>;
  return {
    envelopeId: r.envelopeId as string,
    fromTenant: r.fromTenant as string,
    fromHat: r.fromHat as string,
    toTenant: r.toTenant as string,
    toHat: r.toHat as string,
    payloadType: r.payloadType as string,
    payload: r.payload as string,
    signedBy: r.signedBy as string,
    createdAt: r.createdAt as string,
  };
}

export const dispatchEnvelopeCellType: CellTypeDef<DispatchEnvelope> =
  defineCellType({
    name: 'dispatch.envelope.v1',
    identity: {
      whatPath: 'dispatch.envelope',
      howSlug: 'federation-bridge',
      instPath: 'inst.signal.dispatch-envelope',
    },
    linearity: 'LINEAR',
    toCanonical,
    fromCanonical,
    validate,
  });

```
