---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/rom.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.474511+00:00
---

# cartridges/oddjobz/brain/src/rom.ts

```ts
/**
 * ROM Calculator — CANONICAL copy (oddjobz Estimate / quote-seed path).
 *
 * Cherry-picked verbatim from runtime/shell/src/rom.ts during the
 * REPL-canonicalisation pass (graft-before-cut): the ROM math was
 * unique to the shell chat relic + legacy-ingest, with NO canonical
 * equivalent on the Estimate/quote path. This is now the canonical
 * home; the shell copy is a relic to be repointed/deprecated when
 * the @semantos/intent turn-pipeline binding lands. Keep logic in
 * lock-step with runtime/shell/src/rom.ts until that deprecation.
 *
 * Pure function. No I/O. Deterministic: same inputs → same output.
 * Produces the cost range + breakdown that an oddjobz.estimate.v1
 * (auto_rom) cell is minted from.
 */

// ── Types ───────────────────────────────────────────────────

export interface PricingPolicy {
  baseRates: Record<string, { min: number; max: number; note?: string }>;
  travelModifiers: Record<string, { surcharge: number; decline?: boolean; label: string }>;
  categoryModifiers: Record<string, { factor: number; note?: string }>;
  complexityModifiers: Record<string, { factor: number; label: string }>;
  sizingQuestions?: Record<string, SizingConfig>;
  /** Phase 3: Organization markup (founder-configurable, 0-50%).
   *  NOTE (handyman-estimating research, docs/design/research/): the
   *  operator target is conceptually a *gross margin*
   *  (sell = loaded / (1 − margin)), not a markup. v1 keeps this a
   *  markup (no behaviour change); the distinction is recorded so the
   *  A5.P3 console copy + the agent-tuner don't silently conflate. */
  orgMarkup?: { percent: number; label: string };
  /** Phase 3: Service-type specific modifiers. */
  serviceTypeModifiers?: Record<string, { factor: number; note?: string }>;

  // ── A5.P1b additive-optional fields ──────────────────────────────
  // Grounded in docs/design/research/handyman-estimating-research.md
  // (operator-supplied). Additive-optional on oddjobz.pricing_policy.v1
  // (operator ruling 2026-05-17); absent ⇒ calculateROM is byte-
  // identical to the pre-P1b behaviour. AU-calibrated starting
  // defaults ship as editable policy (A5.P3 console), never inlined.

  /** Operator-home-postcode + radius bands → the input to the
   *  `suburbGroup` classifier (pricing-policy-projector.ts, A5.P1b
   *  Slice 2). NOT consumed by calculateROM directly — calculateROM
   *  takes the already-classified `ROMInput.suburbGroup`. */
  serviceArea?: {
    homePostcode: string;
    /** Ordered nearest→farthest; first band whose maxKm ≥ distance
     *  wins. A band may name a `suburbGroup` that maps to a
     *  `travelModifiers` entry with `decline:true` for out-of-area. */
    radiusBands: Array<{ maxKm: number; suburbGroup: string }>;
    /** When true, beyond the last band ⇒ decline (vs. clamp to the
     *  farthest band). */
    outsideDeclines?: boolean;
  };

  /** Structured rubric → the input to the `effortBand` classifier
   *  (A5.P1b Slice 2). The operator's axes: technical difficulty,
   *  displacement-over-time, mass/density, access, risk, and crucially
   *  **hrCapacity** (one-man-team) — any job needing a second person
   *  or >1 day routes to the existing `requiresQuote` branch (the
   *  baseRates `note:'requires_formal_quote'` path; no new mechanism).
   *  NOT consumed by calculateROM directly. */
  effortRubric?: {
    /** Number of operators the business can field (one-man-team = 1).
     *  The classifier escalates to a formal-quote band when the job
     *  exceeds this. */
    hrCapacity: number;
    /** Optional per-axis → band-key hints the classifier consults. */
    bands?: Record<string, { maxScore: number; band: string }>;
    notes?: string;
  };

  /** Price effect of `ROMInput.urgency` (now plumbed via P1b part-1).
   *  Research starting points: after-hours ≈ +25%, true emergency ≈
   *  +50%. When this field is PRESENT it supersedes the legacy
   *  `complexityModifiers['emergency']` path (so emergency is never
   *  double-counted); when ABSENT the legacy path is unchanged. */
  urgencyModifiers?: Record<string, { premiumPct: number; label: string }>;

  /** Minimum service-call floor (research: standard on short jobs).
   *  Applied after all modifiers + rounding: the final `min` (and
   *  `max` if needed) is raised to `amount`. Absent ⇒ no floor. */
  minimumCallout?: { amount: number; label: string };

  /** Certainty→contingency ladder (research). The BAND is selected by
   *  the decision-tree / classifier (A5.P1b Slice 4), not by
   *  calculateROM here — recorded now so the schema is stable. The
   *  `highUncertainty` band is the sentinel `'formal_quote'`: route to
   *  a formal quote (reuse the safe default) rather than fabricate a
   *  fixed number. Pct values are uplift percentages. */
  contingencyBands?: {
    repeatVisible: number;
    firstTimeVisible: number;
    moderateHidden: number;
    highUncertainty: number | 'formal_quote';
  };

  /** Materials markup (research: ~10–20% stock / ~20–35% special-
   *  order) + subcontractor-coordination margin (~10–20%). RECORDED
   *  for the agent/Pask + a future itemised path; v1 `calculateROM`
   *  is band-based (materials live inside the band) and does NOT
   *  silently apply these — flagged, not wired. */
  materialsMarkup?: { standardPct: number; specialOrderPct: number };
  subcontractorCoordinationPct?: number;

  presentation: {
    roundTo: number;
    rangeLabel: string;
    disclaimer: string;
  };
}

export interface SizingConfig {
  required: string[];
  optional?: string[];
  effortMap: Record<string, string>;
  prompts: Record<string, string>;
}

export interface ROMInput {
  effortBand: string;
  suburbGroup: string;
  categoryPath: string;
  urgency: string;
  complexityHints: string[];  // e.g. ['2_story', 'tricky_access']
}

export interface ROMResult {
  /** The range the homeowner sees */
  min: number;
  max: number;
  /** Human-readable presentation */
  label: string;
  disclaimer: string;
  /** True if outside service area — don't present ROM, decline */
  declined: boolean;
  declineReason?: string;
  /** True if multi_day — needs formal quote, not auto ROM */
  requiresQuote: boolean;
  /** Breakdown for audit/evidence chain */
  breakdown: BreakdownItem[];
}

export interface BreakdownItem {
  component: string;
  effect: string;
  minDelta: number;
  maxDelta: number;
}

// ── Calculator ──────────────────────────────────────────────

export function calculateROM(input: ROMInput, policy: PricingPolicy): ROMResult {
  const breakdown: BreakdownItem[] = [];

  // 1. Base rate from effort band
  const band = input.effortBand || 'short';
  const base = policy.baseRates[band] || policy.baseRates['short'];

  if (base.note === 'requires_formal_quote' || base.max === 0) {
    return {
      min: 0,
      max: 0,
      label: 'This job needs a formal quote — too complex for an auto estimate.',
      disclaimer: policy.presentation.disclaimer,
      declined: false,
      requiresQuote: true,
      breakdown: [{ component: 'effortBand', effect: `${band} → requires formal quote`, minDelta: 0, maxDelta: 0 }],
    };
  }

  let min = base.min;
  let max = base.max;
  breakdown.push({
    component: 'baseRate',
    effect: `${band} band → $${base.min}-$${base.max}`,
    minDelta: base.min,
    maxDelta: base.max,
  });

  // 2. Travel modifier from suburb group
  const travel = policy.travelModifiers[input.suburbGroup] || policy.travelModifiers['core'];
  if (travel.decline) {
    return {
      min: 0,
      max: 0,
      label: `Sorry, that area is outside the service area.`,
      disclaimer: '',
      declined: true,
      declineReason: `suburbGroup=${input.suburbGroup}: outside service area`,
      requiresQuote: false,
      breakdown: [
        ...breakdown,
        { component: 'travel', effect: `${input.suburbGroup} → declined`, minDelta: 0, maxDelta: 0 },
      ],
    };
  }
  if (travel.surcharge > 0) {
    min += travel.surcharge;
    max += travel.surcharge;
    breakdown.push({
      component: 'travel',
      effect: `${input.suburbGroup} → +$${travel.surcharge}`,
      minDelta: travel.surcharge,
      maxDelta: travel.surcharge,
    });
  }

  // 3. Category modifier
  const catMod = policy.categoryModifiers[input.categoryPath];
  if (catMod && catMod.factor !== 1.0) {
    const prevMin = min;
    const prevMax = max;
    min = Math.round(min * catMod.factor);
    max = Math.round(max * catMod.factor);
    breakdown.push({
      component: 'category',
      effect: `${input.categoryPath} → ×${catMod.factor}${catMod.note ? ` (${catMod.note})` : ''}`,
      minDelta: min - prevMin,
      maxDelta: max - prevMax,
    });
  }

  // 4. Complexity modifiers (cumulative)
  for (const hint of input.complexityHints) {
    const mod = policy.complexityModifiers[hint];
    if (mod) {
      const prevMin = min;
      const prevMax = max;
      min = Math.round(min * mod.factor);
      max = Math.round(max * mod.factor);
      breakdown.push({
        component: 'complexity',
        effect: `${hint} → ×${mod.factor} (${mod.label})`,
        minDelta: min - prevMin,
        maxDelta: max - prevMax,
      });
    }
  }

  // 5. Service-type modifier (Phase 3: consumer service pricing)
  if (policy.serviceTypeModifiers) {
    const serviceTypeMod = policy.serviceTypeModifiers[input.categoryPath];
    if (serviceTypeMod && serviceTypeMod.factor !== 1.0) {
      const prevMin = min;
      const prevMax = max;
      min = Math.round(min * serviceTypeMod.factor);
      max = Math.round(max * serviceTypeMod.factor);
      breakdown.push({
        component: 'serviceType',
        effect: `${input.categoryPath} → ×${serviceTypeMod.factor}${serviceTypeMod.note ? ` (${serviceTypeMod.note})` : ''}`,
        minDelta: min - prevMin,
        maxDelta: max - prevMax,
      });
    }
  }

  // 5.5 Organization markup (Phase 3: founder-configurable premium)
  if (policy.orgMarkup && policy.orgMarkup.percent > 0) {
    const prevMin = min;
    const prevMax = max;
    const factor = 1 + (policy.orgMarkup.percent / 100);
    min = Math.round(min * factor);
    max = Math.round(max * factor);
    breakdown.push({
      component: 'orgMarkup',
      effect: `+${policy.orgMarkup.percent}% (${policy.orgMarkup.label})`,
      minDelta: min - prevMin,
      maxDelta: max - prevMax,
    });
  }

  // 6. Urgency modifier.
  //   - A5.P1b: if the policy carries structured `urgencyModifiers`
  //     (research: after-hours ≈ +25%, emergency ≈ +50%), it
  //     SUPERSEDES the legacy emergency path and covers the full
  //     urgency enum. Premium applied after orgMarkup, before
  //     rounding — same position as the legacy block.
  //   - Otherwise the legacy `complexityModifiers['emergency']` path
  //     is preserved BYTE-IDENTICAL (pre-P1b behaviour when no
  //     urgencyModifiers field is configured).
  if (policy.urgencyModifiers) {
    const um = policy.urgencyModifiers[input.urgency];
    if (um && um.premiumPct !== 0) {
      const prevMin = min;
      const prevMax = max;
      const factor = 1 + um.premiumPct / 100;
      min = Math.round(min * factor);
      max = Math.round(max * factor);
      breakdown.push({
        component: 'urgency',
        effect: `${input.urgency} → +${um.premiumPct}% (${um.label})`,
        minDelta: min - prevMin,
        maxDelta: max - prevMax,
      });
    }
  } else if (
    input.urgency === 'emergency' &&
    !input.complexityHints.includes('emergency')
  ) {
    const emergencyMod = policy.complexityModifiers['emergency'];
    if (emergencyMod) {
      const prevMin = min;
      const prevMax = max;
      min = Math.round(min * emergencyMod.factor);
      max = Math.round(max * emergencyMod.factor);
      breakdown.push({
        component: 'urgency',
        effect: `emergency → ×${emergencyMod.factor} (${emergencyMod.label})`,
        minDelta: min - prevMin,
        maxDelta: max - prevMax,
      });
    }
  }

  // 6. Round to presentation granularity
  const roundTo = policy.presentation.roundTo || 10;
  min = Math.round(min / roundTo) * roundTo;
  max = Math.round(max / roundTo) * roundTo;

  // Ensure min < max
  if (min >= max) max = min + roundTo;

  // 7. Minimum service-call floor (A5.P1b; research: standard on
  //    short jobs). Absent ⇒ no floor (byte-identical to pre-P1b).
  if (policy.minimumCallout && min < policy.minimumCallout.amount) {
    const prevMin = min;
    const prevMax = max;
    min = policy.minimumCallout.amount;
    if (max <= min) max = min + roundTo;
    breakdown.push({
      component: 'minimumCallout',
      effect: `floor → $${min} (${policy.minimumCallout.label})`,
      minDelta: min - prevMin,
      maxDelta: max - prevMax,
    });
  }

  const label = `${policy.presentation.rangeLabel} $${min}–$${max}`;

  return {
    min,
    max,
    label,
    disclaimer: policy.presentation.disclaimer,
    declined: false,
    requiresQuote: false,
    breakdown,
  };
}

// ── Complexity Hint Extraction ──────────────────────────────

/**
 * Extract complexity hints from Job/Property/Site fields.
 * These are signals that affect pricing but aren't explicit schema fields.
 */
export function extractComplexityHints(fields: {
  propertyType?: string;
  accessNotes?: string;
  description?: string;
}): string[] {
  const hints: string[] = [];
  const text = [fields.accessNotes || '', fields.description || ''].join(' ').toLowerCase();

  if (text.includes('2 stor') || text.includes('two stor') || text.includes('2-stor') || text.includes('double stor')) {
    hints.push('2_story');
  }
  if (text.includes('tricky') || text.includes('difficult access') || text.includes('hard to reach') || text.includes('tight space')) {
    hints.push('tricky_access');
  }

  return hints;
}

```
