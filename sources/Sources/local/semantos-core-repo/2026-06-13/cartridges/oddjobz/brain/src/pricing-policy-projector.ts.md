---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/pricing-policy-projector.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.477253+00:00
---

# cartridges/oddjobz/brain/src/pricing-policy-projector.ts

```ts
/**
 * Pricing-policy projector (A5.P1a) — the seam between the
 * `oddjobz.pricing_policy.v1` cell and the ROM calculator.
 *
 * `calculateROM` (./rom.ts) takes a flat `PricingPolicy`. The policy
 * lives in a PERSISTENT (wire RELEVANT) operator-config cell
 * (./cell-types/pricing-policy.ts) whose `policy` field IS that
 * exact interface (wrapped, never redefined). This module is the
 * single, named projection point + the **safe-default contract**:
 *
 *   NO active pricing-policy cell under the operator hat
 *     ⇒ resolve to `null`
 *     ⇒ the caller MUST NOT call `calculateROM`; it routes the job
 *       to a formal quote (the A5 "don't fabricate prices" default).
 *
 * Keeping the null-decision here (not scattered at call sites) means
 * the "no policy ⇒ formal quote" rule is one auditable seam. The
 * projector stays thin now; the A5.P1b schema extension
 * (operator-home-postcode + radius → suburbGroup geo-classify,
 * job-type urgency priors, the effort rubric incl. operator HR
 * capacity) layers its EstimatorRequest→ROMInput mapping here too,
 * behind the same seam.
 */

import { calculateROM, type PricingPolicy, type ROMInput, type ROMResult } from './rom.js';
import type { OddjobzPricingPolicy } from './cell-types/index.js';
import type { EstimatorRequest } from './conversation/state-manager.js';

/** Outcome of resolving the active pricing policy for a hat. */
export type ResolvedPricingPolicy =
  | { readonly configured: true; readonly policy: PricingPolicy }
  | { readonly configured: false; readonly reason: 'no_policy_cell' };

/**
 * Project the active pricing-policy cell (or its absence) into the
 * ROM calculator's input. `null`/absent ⇒ `{configured:false}` —
 * the caller routes to a formal quote and MUST NOT invoke
 * `calculateROM`. A present cell yields its embedded `policy`
 * verbatim (single source of truth).
 */
export function resolvePricingPolicy(
  cell: OddjobzPricingPolicy | null | undefined,
): ResolvedPricingPolicy {
  if (cell == null) {
    return { configured: false, reason: 'no_policy_cell' };
  }
  return { configured: true, policy: cell.policy };
}

/**
 * Convenience guard for the caller's branch:
 *   const r = resolvePricingPolicy(cell);
 *   if (!shouldAutoRom(r)) { routeToFormalQuote(); return; }
 *   const rom = calculateROM(input, r.policy);
 */
export function shouldAutoRom(
  r: ResolvedPricingPolicy,
): r is { configured: true; policy: PricingPolicy } {
  return r.configured;
}

// ─────────────────────────────────────────────────────────────────────
// A5.P1b Slice 2 — the EstimatorRequest → ROMInput classifier shim.
//
// `calculateROM` takes a fully-classified `ROMInput`
// ({effortBand, suburbGroup, categoryPath, urgency, complexityHints}).
// The intake conversation produces an `EstimatorRequest` (raw
// LLM-extracted fields + the suburb/postcode/urgency P1b part-1
// plumbed through). These pure functions are the single, named
// projection between the two — co-located with the policy seam so the
// "no policy ⇒ formal quote" rule and the classification rules are one
// auditable place (this module's header contract).
//
// HONESTY CONTRACT (memory: "no hardcoded workarounds"):
//   - There is NO postcode→coordinates dataset in this package. The
//     km-radius path therefore takes an INJECTED `geoDistanceKm`
//     dependency. When it is absent OR returns null (unresolvable),
//     the classifier returns `'core'` — it NEVER fabricates a
//     distance and NEVER auto-declines a real customer on a guess
//     (declining wrongly is worse than a slightly-off travel tier;
//     the genuine out-of-area decline still lives in the operator's
//     `travelModifiers[...].decline`). Wiring a real AU postcode-
//     centroid/geocoder source is a separate data-source decision.
//   - `categoryPath` is the raw jobType passed through verbatim;
//     `calculateROM` already no-ops unknown `categoryModifiers` keys,
//     so the operator's policy decides the taxonomy — no taxonomy is
//     hardcoded here.
// ─────────────────────────────────────────────────────────────────────

/** Injected postcode→postcode great-circle distance in km, or null
 *  when it cannot be resolved (unknown postcode, no dataset). Kept a
 *  dependency so the shim stays pure + this package needs no geo
 *  dataset; a real AU source is wired by the caller (Slice 3+). */
export type GeoDistanceKmFn = (
  homePostcode: string,
  targetPostcode: string,
) => number | null;

/**
 * Classify the customer location into a `travelModifiers` key.
 *
 * - No `serviceArea` configured ⇒ `'core'` (operator hasn't set up
 *   travel discrimination; matches the pre-P1b `travelModifiers.core`
 *   default — behaviour-neutral).
 * - `serviceArea` set + a resolvable distance ⇒ the first radius band
 *   (ordered nearest→farthest) whose `maxKm ≥ distance`; beyond every
 *   band ⇒ the farthest band's `suburbGroup` (the operator models
 *   out-of-area as a final band whose group maps to a declining
 *   `travelModifiers` entry — `outsideDeclines` documents that intent).
 * - Distance unresolvable (no geo fn / returns null / no postcode)
 *   ⇒ `'core'` (never decline on uncertainty — see honesty contract).
 */
export function classifySuburbGroup(
  req: Pick<EstimatorRequest, 'postcode' | 'suburb'>,
  serviceArea?: PricingPolicy['serviceArea'],
  geoDistanceKm?: GeoDistanceKmFn,
): string {
  if (!serviceArea || serviceArea.radiusBands.length === 0) return 'core';
  const target = (req.postcode ?? '').trim();
  if (target === '' || !geoDistanceKm) return 'core';
  const d = geoDistanceKm(serviceArea.homePostcode, target);
  if (d == null || !Number.isFinite(d) || d < 0) return 'core';
  const bands = [...serviceArea.radiusBands].sort((a, b) => a.maxKm - b.maxKm);
  for (const band of bands) {
    if (d <= band.maxKm) return band.suburbGroup;
  }
  // Beyond every band: the farthest band carries the out-of-area
  // group (its `travelModifiers` entry is where `decline` lives).
  return bands[bands.length - 1].suburbGroup;
}

/**
 * Classify the job effort into a `baseRates` band key.
 *
 * First-pass rubric over the fields the conversation actually
 * collects, honouring the operator's **one-man-team HR capacity**
 * (the load-bearing axis the operator called out): work that a solo
 * operator cannot safely/efficiently self-perform escalates to
 * `'multi_day'` — the established key whose `baseRates` entry carries
 * `note:'requires_formal_quote'`, so `calculateROM` routes it to a
 * formal quote (no new mechanism; reuses the safe default rather than
 * fabricating a price for an over-capacity job).
 *
 * `effortRubric.bands` (operator-tuned, optional) overrides the
 * built-in heuristic when an explicit access→band mapping is given.
 * Absent rubric ⇒ `'short'` for ordinary work (pre-P1b default band).
 */
export function classifyEffortBand(
  req: Pick<EstimatorRequest, 'accessDifficulty' | 'scopeDescription'>,
  effortRubric?: PricingPolicy['effortRubric'],
): string {
  const access = req.accessDifficulty ?? 'ground_level';

  // Operator-tuned explicit mapping wins (keyed by access tier).
  const explicit = effortRubric?.bands?.[access];
  if (explicit) return explicit.band;

  const hrCapacity = effortRubric?.hrCapacity ?? 1;
  // Scaffolding is a ≥2-person / rigging job — a one-man team cannot
  // safely self-perform it ⇒ escalate to a formal quote.
  if (access === 'scaffolding_required' && hrCapacity <= 1) {
    return 'multi_day';
  }
  return 'short';
}

/** accessDifficulty → the `complexityModifiers` hint keys rom.ts
 *  already understands (`tricky_access`, `2_story` come from
 *  `extractComplexityHints`; access tiers map to `tricky_access`). */
function complexityHintsFromAccess(
  accessDifficulty: string | null,
): string[] {
  switch (accessDifficulty) {
    case 'ladder_required':
    case 'scaffolding_required':
    case 'difficult_access':
      return ['tricky_access'];
    default:
      return [];
  }
}

/**
 * The full `EstimatorRequest → ROMInput` projection (pure). Combines
 * the two classifiers + a verbatim category/urgency pass-through.
 * Wiring this into the estimate path (replacing the toy
 * `DEFAULT_ESTIMATOR_FN`) is Slice 3, behind the UNCHANGED
 * state-manager `present_estimate` gate.
 */
export function mapEstimatorRequestToRomInput(
  req: EstimatorRequest,
  policy: PricingPolicy,
  deps?: { geoDistanceKm?: GeoDistanceKmFn },
): ROMInput {
  return {
    effortBand: classifyEffortBand(req, policy.effortRubric),
    suburbGroup: classifySuburbGroup(
      req,
      policy.serviceArea,
      deps?.geoDistanceKm,
    ),
    categoryPath: req.jobType ?? '',
    urgency: req.urgency ?? 'unspecified',
    complexityHints: complexityHintsFromAccess(req.accessDifficulty),
  };
}

// ─────────────────────────────────────────────────────────────────────
// A5.P1b Slice 3a — the ROM EstimatorFn factory (pure).
//
// `reply-generator.ts` wants an `EstimatorFn = (EstimatorRequest) =>
// string` it can drop into the present_estimate branch. This factory
// closes over the resolved policy cell + the (injected) geo dep and
// produces exactly that, routing every outcome through the A5
// safe-default contract:
//
//   no policy cell        ⇒ formal-quote wording (NEVER a fabricated
//                            number — the whole point of A5)
//   requiresQuote / band  ⇒ formal-quote wording
//   declined (out-of-area)⇒ decline wording
//   normal                ⇒ the ROMResult range label
//
// The returned string is embedded verbatim into the LLM system
// injection (`[ROM from estimator: …]`); it is guidance the model
// phrases, so it is written as a directive, not a customer sentence.
//
// Slice 3a only BUILDS + tests this factory. Flipping the live
// intake-handler off the toy DEFAULT_ESTIMATOR_FN onto this is Slice
// 3b — a prototype-bot behaviour change (every job ⇒ "formal quote"
// until a pricing_policy cell exists, which needs A5.P2's cell-read)
// and is surfaced for an operator call, not bulldozed here.
// ─────────────────────────────────────────────────────────────────────

/** Render a ROMResult (or the not-configured safe default) into the
 *  estimator-wording string the present_estimate injection expects. */
export function formatRomWording(
  r: ResolvedPricingPolicy,
  rom: ROMResult | null,
): string {
  if (!r.configured || rom === null) {
    return 'no_auto_price: route to a formal quote — do NOT state a price; explain a proper quote will follow.';
  }
  if (rom.declined) {
    return `decline: ${rom.declineReason ?? 'outside service area'} — politely explain this is outside the service area.`;
  }
  if (rom.requiresQuote) {
    return 'requires_formal_quote: too complex for an auto estimate — explain a formal quote will follow, do NOT state a price.';
  }
  return `${rom.label}${rom.disclaimer ? ` — ${rom.disclaimer}` : ''}`;
}

/**
 * Build the present_estimate `EstimatorFn` for a (possibly absent)
 * pricing-policy cell. Pure: same cell + same request ⇒ same wording.
 */
export function makeRomEstimatorFn(
  cell: OddjobzPricingPolicy | null | undefined,
  deps?: { geoDistanceKm?: GeoDistanceKmFn },
): (req: EstimatorRequest) => string {
  const resolved = resolvePricingPolicy(cell);
  return (req: EstimatorRequest): string => {
    if (!shouldAutoRom(resolved)) return formatRomWording(resolved, null);
    const input = mapEstimatorRequestToRomInput(req, resolved.policy, deps);
    const rom = calculateROM(input, resolved.policy);
    return formatRomWording(resolved, rom);
  };
}

```
