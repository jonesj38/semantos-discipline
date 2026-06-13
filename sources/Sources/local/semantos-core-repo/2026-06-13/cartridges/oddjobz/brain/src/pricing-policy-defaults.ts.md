---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/pricing-policy-defaults.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.474227+00:00
---

# cartridges/oddjobz/brain/src/pricing-policy-defaults.ts

```ts
/**
 * AU-calibrated *starting* pricing policy (DECISION-A5 / A5.P2).
 *
 * Operator ruling 2026-05-17: "AU-calibrated from the report,
 * editable". This module is that — a single, named, research-cited
 * `PricingPolicy` VALUE the `set_pricing_policy` genesis can seed and
 * the operator then amends via the console (A5.P3). It is deliberately
 * NOT inlined into `calculateROM` (memory: "no hardcoded workarounds"
 * — fabricated calculator constants age into silent regressions). The
 * calculator stays pure and policy-agnostic; THIS is editable data.
 *
 * Provenance + caveats:
 *  - Structure adopted from docs/design/research/handyman-estimating-
 *    research.md (operator-supplied). The report is US-centric
 *    (BLS/SBA/IRS/OSHA/EPA/FTC, US$); these numbers are AU-localised
 *    starting defaults to BACK-TEST, not US figures copied in. AU
 *    anchor: hipages A$55–A$85/hr (+ holiday/weekend/rush premiums);
 *    QBCC written-contract > A$3,300; licensed plumbing/electrical
 *    regardless of price.
 *  - `serviceArea.homePostcode` is intentionally EMPTY: the operator
 *    sets their real home postcode via the console. The classifier
 *    (`classifySuburbGroup`) already degrades to `'core'` when the
 *    postcode is unresolvable, so an unconfigured service area never
 *    wrongly declines a customer.
 *  - Per-trade `categoryModifiers` is intentionally EMPTY: the
 *    operator owns the trade taxonomy (no taxonomy hardcoded here;
 *    `calculateROM` no-ops unknown category keys).
 *  - These are "decide-before-you-quote" defaults (the report's
 *    sharpest operational rule); the operator tunes them, Pask
 *    observes their stability, an edge agent proposes amendments.
 */

import type { PricingPolicy } from './rom.js';
import type { OddjobzPricingPolicy } from './cell-types/pricing-policy.js';
import type { SetPricingPolicyInput } from './set-pricing-policy.js';

/**
 * The AU starting policy. Every field is operator-editable; the
 * comments cite the research band each default sits within.
 */
export const AU_DEFAULT_PRICING_POLICY: PricingPolicy = Object.freeze({
  // Loaded sell-rate bands (AU$, incl. non-billable overhead — the
  // report's "what it costs to hire ≠ what it costs to sell a billable
  // hour"). `multi_day` is the one-man-team / over-capacity escalation
  // → formal quote (note:'requires_formal_quote'), reused by
  // classifyEffortBand rather than fabricating an over-capacity price.
  baseRates: {
    short: { min: 150, max: 450 }, // ~1–3 hrs at hipages A$55–85/hr + overhead
    half_day: { min: 350, max: 750 },
    full_day: { min: 650, max: 1200 },
    multi_day: { min: 0, max: 0, note: 'requires_formal_quote' },
  },
  // Travel tiers keyed by the suburbGroup classifier output. `outside`
  // declines (the genuine out-of-area decline lives here, not in the
  // classifier — which never declines on geo-uncertainty).
  travelModifiers: {
    core: { surcharge: 0, label: 'Local / core service area' },
    extended: { surcharge: 40, label: 'Extended area travel' },
    outside: { surcharge: 0, decline: true, label: 'Outside service area' },
  },
  // Operator owns the per-trade taxonomy — empty by design.
  categoryModifiers: {},
  complexityModifiers: {
    '2_story': { factor: 1.15, label: 'Two-storey access' },
    tricky_access: { factor: 1.2, label: 'Difficult / restricted access' },
  },
  // Research: after-hours ≈ +25%, true emergency ≈ +50%. Supersedes
  // the legacy complexityModifiers['emergency'] path (Slice 1).
  urgencyModifiers: {
    emergency: { premiumPct: 50, label: 'Emergency response' },
    urgent: { premiumPct: 25, label: 'Urgent / after-hours' },
    next_week: { premiumPct: 0, label: 'Next week' },
    next_2_weeks: { premiumPct: 0, label: 'Next fortnight' },
    flexible: { premiumPct: 0, label: 'Flexible timing' },
    when_convenient: { premiumPct: 0, label: 'When convenient' },
    unspecified: { premiumPct: 0, label: 'Unspecified' },
  },
  // Research: minimum service call is standard on short jobs (AU$).
  minimumCallout: { amount: 120, label: 'Minimum call-out' },
  // Research certainty→contingency ladder; high-uncertainty routes to
  // a formal quote (the safe default) rather than a fabricated number.
  contingencyBands: {
    repeatVisible: 5,
    firstTimeVisible: 10,
    moderateHidden: 20,
    highUncertainty: 'formal_quote',
  },
  // Materials/sub margins RECORDED for the agent/Pask + a future
  // itemised path; v1 calculateROM is band-based and does NOT apply
  // these (flagged in rom.ts, not silently wired).
  materialsMarkup: { standardPct: 15, specialOrderPct: 27 },
  subcontractorCoordinationPct: 15,
  // Operator MUST set homePostcode via the console; '' degrades to
  // 'core' in classifySuburbGroup (never a wrong decline).
  serviceArea: {
    homePostcode: '',
    radiusBands: [
      { maxKm: 15, suburbGroup: 'core' },
      { maxKm: 40, suburbGroup: 'extended' },
      { maxKm: 99_999, suburbGroup: 'outside' },
    ],
    outsideDeclines: true,
  },
  // One-man team: scaffolding / multi-person / multi-day ⇒ formal
  // quote (classifyEffortBand → 'multi_day').
  effortRubric: {
    hrCapacity: 1,
    notes:
      'One-man team. Work requiring a second person, rigging/scaffolding, ' +
      'or more than a day routes to a formal quote rather than an auto ROM.',
  },
  presentation: {
    roundTo: 10,
    rangeLabel: 'Typically',
    disclaimer:
      'Ballpark estimate only — not a formal quote. Final price is ' +
      'confirmed on site once access and scope are verified.',
  },
} satisfies PricingPolicy);

/**
 * Build the `set_pricing_policy` genesis input that seeds
 * {@link AU_DEFAULT_PRICING_POLICY} for a hat. The caller supplies the
 * presented `cap.oddjobz.write_policy` UTXO + operator cert id + clock;
 * the operator then amends via the console (A5.P3) — this is a
 * starting point, never a frozen price book.
 */
export function auDefaultGenesisInput(args: {
  hatId: string;
  operatorCertId: string;
  presentedCap: SetPricingPolicyInput['presentedCap'];
  nowIso: string;
  newPolicyId?: string;
}): SetPricingPolicyInput {
  return {
    hatId: args.hatId,
    operatorCertId: args.operatorCertId,
    policy: AU_DEFAULT_PRICING_POLICY,
    presentedCap: args.presentedCap,
    nowIso: args.nowIso,
    ...(args.newPolicyId !== undefined ? { newPolicyId: args.newPolicyId } : {}),
  };
}

/** Narrowing helper for tests/consumers that hold a minted cell. */
export type AuDefaultPolicyCell = OddjobzPricingPolicy;

```
