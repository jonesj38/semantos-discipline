---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/pricing-policy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.505359+00:00
---

# cartridges/oddjobz/brain/src/cell-types/pricing-policy.ts

```ts
/**
 * `oddjobz.pricing_policy.v1` — Ricardian-style operator pricing-policy
 * cell. (DECISION-A5, design doc §7.)
 *
 * The ROM calculator (`../rom.ts` `calculateROM`) needs a
 * `PricingPolicy`. The operator wants it configurable, each aspect a
 * field "like a Ricardian contract", edited from the field-app helm
 * under the operator hat, mutated as a config-intent, observable by
 * Pask. This cell is the substrate that holds it.
 *
 * ── Linearity: PERSISTENT (wire RELEVANT) ──
 * Operator clarification: they know this class as RELEVANT and did
 * not recognise the §O2 high-level label "PERSISTENT" — they are the
 * same thing (`linearity.ts`: PERSISTENT → wire RELEVANT). They were
 * NOT rejecting the accumulate-never-destructively-consumed
 * semantic. A pricing policy IS that: long-lived operator config,
 * never kernel-consumed, read CONCURRENTLY by the ROM calculator,
 * the Pask observer, and the dashboard — which `LINEAR` (consumed
 * exactly once, no DUP) would forbid, and `AFFINE` (discardable
 * draft) misrepresents. So this cell ships `PERSISTENT` (wire
 * RELEVANT), the exact class customer/site/message use for
 * long-lived reference data — the correct precedent.
 *
 * The "append-only signed-versioned" amendment chain the operator
 * wants is preserved at the APPLICATION layer via the envelope
 * fields `version` (monotonic) + `prevPolicyHash` (→ predecessor) +
 * `signedByOperatorId` (mint-time hat-signature). Kernel linearity
 * (RELEVANT) governs consumption; the Ricardian amendment history is
 * the version/prevPolicyHash chain over accumulated cells. (Stated
 * explicitly so the linearity choice is reviewable, not buried.)
 *
 * Signing depth (A5 #2, recommended default): mint-time hat-signing +
 * a `signedByOperatorId` provenance field — the `lead.ratifiedBy`
 * precedent — NOT an in-cell detached-signature-per-field. Sufficient
 * Ricardian-ness for v1; true per-clause detached sigs are a future
 * `.v2` if ever needed.
 *
 * The embedded `policy` is the EXACT `PricingPolicy` interface
 * `calculateROM` consumes (imported, single source of truth — the
 * cell wraps it, never redefines it). A thin projector
 * (`policyCell.policy`) feeds `calculateROM` in A5.P1.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertNonEmptyString,
  assertNonNegativeInt,
  assertOptionalString,
  assertIsoDateString,
} from './validators.js';
import type { PricingPolicy } from '../rom.js';

export interface OddjobzPricingPolicy {
  /** Stable policy identity (UUID v4) — constant across the
   *  amendment chain; `version` distinguishes revisions. */
  readonly policyId: string;
  /** Tenant/hat this policy governs. The substrate filters by hat;
   *  pricing is per operator context. */
  readonly hatId: string;
  /** Monotonic revision, ≥ 1. v1 is the genesis; each amendment
   *  increments it and chains via `prevPolicyHash`. */
  readonly version: number;
  /** Type-hash of the immediately-preceding policy cell (the
   *  amendment-chain link). Absent on the genesis (version 1). */
  readonly prevPolicyHash?: string;
  /** Operator root-cert id (hex) that signed this revision at mint,
   *  under the operator hat. Provenance, not an in-cell signature
   *  primitive (the `lead.ratifiedBy` precedent). */
  readonly signedByOperatorId?: string;

  /** The machine-readable pricing contract — the EXACT shape
   *  `calculateROM` consumes. Each field (baseRates, travel/
   *  category/complexity/serviceType modifiers, sizingQuestions,
   *  orgMarkup, presentation) is operator-configurable. */
  readonly policy: PricingPolicy;

  readonly createdAt: string;
  readonly updatedAt: string;
}

function validatePolicyPayload(p: PricingPolicy): void {
  if (typeof p !== 'object' || p === null) {
    throw new Error('pricing_policy: policy must be an object');
  }
  const recOk = (
    rec: unknown,
    name: string,
    each: (k: string, v: Record<string, unknown>) => void,
  ): void => {
    if (typeof rec !== 'object' || rec === null) {
      throw new Error(`pricing_policy: ${name} must be a record`);
    }
    for (const [k, v] of Object.entries(rec as Record<string, unknown>)) {
      if (typeof v !== 'object' || v === null) {
        throw new Error(`pricing_policy: ${name}.${k} must be an object`);
      }
      each(k, v as Record<string, unknown>);
    }
  };

  recOk(p.baseRates, 'baseRates', (k, v) => {
    if (typeof v.min !== 'number' || typeof v.max !== 'number') {
      throw new Error(`pricing_policy: baseRates.${k} needs numeric min/max`);
    }
    if (v.max < v.min) {
      throw new Error(`pricing_policy: baseRates.${k} max < min`);
    }
  });
  recOk(p.travelModifiers, 'travelModifiers', (k, v) => {
    if (typeof v.surcharge !== 'number' || typeof v.label !== 'string') {
      throw new Error(`pricing_policy: travelModifiers.${k} needs surcharge:number,label:string`);
    }
  });
  recOk(p.categoryModifiers, 'categoryModifiers', (k, v) => {
    if (typeof v.factor !== 'number') {
      throw new Error(`pricing_policy: categoryModifiers.${k} needs factor:number`);
    }
  });
  recOk(p.complexityModifiers, 'complexityModifiers', (k, v) => {
    if (typeof v.factor !== 'number' || typeof v.label !== 'string') {
      throw new Error(`pricing_policy: complexityModifiers.${k} needs factor:number,label:string`);
    }
  });
  if (p.orgMarkup !== undefined) {
    const { percent } = p.orgMarkup;
    if (typeof percent !== 'number' || percent < 0 || percent > 50) {
      throw new Error('pricing_policy: orgMarkup.percent must be 0..50');
    }
  }
  const pr = p.presentation;
  if (
    typeof pr !== 'object' || pr === null ||
    typeof pr.roundTo !== 'number' ||
    typeof pr.rangeLabel !== 'string' ||
    typeof pr.disclaimer !== 'string'
  ) {
    throw new Error('pricing_policy: presentation needs roundTo:number,rangeLabel:string,disclaimer:string');
  }
}

function validate(v: OddjobzPricingPolicy): void {
  assertUuid('policyId', v.policyId);
  assertNonEmptyString('hatId', v.hatId);
  assertNonNegativeInt('version', v.version);
  if (v.version < 1) throw new Error('pricing_policy: version must be ≥ 1');
  assertOptionalString('prevPolicyHash', v.prevPolicyHash);
  assertOptionalString('signedByOperatorId', v.signedByOperatorId);
  if (v.version === 1 && v.prevPolicyHash !== undefined) {
    throw new Error('pricing_policy: genesis (version 1) must not carry prevPolicyHash');
  }
  if (v.version > 1 && (v.prevPolicyHash === undefined || v.prevPolicyHash.length === 0)) {
    throw new Error('pricing_policy: amendment (version > 1) must carry prevPolicyHash');
  }
  assertIsoDateString('createdAt', v.createdAt);
  assertIsoDateString('updatedAt', v.updatedAt);
  validatePolicyPayload(v.policy);
}

function toCanonical(v: OddjobzPricingPolicy): Record<string, unknown> {
  const out: Record<string, unknown> = {
    policyId: v.policyId,
    hatId: v.hatId,
    version: v.version,
    policy: v.policy,
    createdAt: v.createdAt,
    updatedAt: v.updatedAt,
  };
  if (v.prevPolicyHash !== undefined) out.prevPolicyHash = v.prevPolicyHash;
  if (v.signedByOperatorId !== undefined) out.signedByOperatorId = v.signedByOperatorId;
  return out;
}

function fromCanonical(c: unknown): OddjobzPricingPolicy {
  if (typeof c !== 'object' || c === null) {
    throw new Error('pricing_policy: payload not an object');
  }
  const r = c as Record<string, unknown>;
  return {
    policyId: r.policyId as string,
    hatId: r.hatId as string,
    version: r.version as number,
    prevPolicyHash: r.prevPolicyHash as string | undefined,
    signedByOperatorId: r.signedByOperatorId as string | undefined,
    policy: r.policy as PricingPolicy,
    createdAt: r.createdAt as string,
    updatedAt: r.updatedAt as string,
  };
}

export const pricingPolicyCellType: CellTypeDef<OddjobzPricingPolicy> =
  defineCellType({
    name: 'oddjobz.pricing_policy.v1',
    identity: {
      whatPath: 'oddjobz.pricing_policy',
      howSlug: 'pricing-policy',
      instPath: 'inst.config.pricing-policy',
    },
    linearity: 'PERSISTENT', // → wire RELEVANT; see linearity rationale above
    toCanonical,
    fromCanonical,
    validate,
  });

```
