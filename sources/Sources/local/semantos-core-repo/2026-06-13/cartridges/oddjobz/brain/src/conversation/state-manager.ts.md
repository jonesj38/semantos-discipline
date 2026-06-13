---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/state-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.523606+00:00
---

# cartridges/oddjobz/brain/src/conversation/state-manager.ts

```ts
/**
 * D-O7 — conversation state manager.
 *
 * Origin: `oddjobtodd/src/lib/domain/workflow/conversationStateManager.ts`
 *         (Sprint 3 — sub-score smarter stop conditions).
 * Last tuned: 2026-04 (the offer_free_quote_visit branch + worthiness
 *             guard).
 *
 * THE most load-bearing OJT artefact for D-O7. The 230-line cascade
 * encodes ~6 months of operator-tuned thresholds: 70 for decision-
 * readiness, 50 for estimate-readiness, 35 for second-chance scope-
 * clarity, the worthiness ≥ 35 + fit ≥ 25 thresholds for the free-
 * quote-visit branch. These numbers ARE the operator-tuned product;
 * do not change without operator review.
 *
 * Refactor from OJT origin:
 *
 *   1. Decoupled from `effortBandService` / `estimateService` /
 *      `estimateWordingService`. The OJT version inlined ROM
 *      generation as a side effect of the cascade. The D-O7 port
 *      separates the DECISION (this module) from the EXECUTION
 *      (the caller, who plugs in their own estimator). The action
 *      type now has `present_estimate` carrying a `EstimatorRequest`
 *      shape — the caller resolves that against their estimator
 *      service and renders the actual ROM wording.
 *   2. Documented as hint-only relative to the substrate. The Job FSM
 *      (D-O4) is the source of truth for "what's the next valid
 *      transition"; this cascade is the heuristic that picks a hint
 *      to inject into the LLM. See D-O7-OJT-SALVAGE-REPORT.md
 *      Finding 3.
 *
 * Apart from those refactor points, the cascade is verbatim. The
 * tone strings in `generateSystemInjection` are the operator-approved
 * text — preserve them exactly.
 */

import type { AccumulatedJobState } from './accumulated-job-state.js';

/* ══════════════════════════════════════════════════════════════════════
 * Action type
 * ══════════════════════════════════════════════════════════════════════ */

/** Shape of a request to the caller's estimator service. The
 *  conversation manager doesn't itself emit ROM dollar figures; it
 *  emits a request, the caller (which holds the estimator + ROM
 *  policy) resolves it and renders the wording. The OJT version
 *  inlined this; D-O7 separates the decision from the execution. */
export interface EstimatorRequest {
  readonly jobType: string | null;
  readonly subcategory: string | null;
  readonly quantity: string | null;
  readonly scopeDescription: string | null;
  readonly materials: string | null;
  readonly accessDifficulty: string | null;
  /** Location/timing already collected by the intake conversation
   *  (LLM-extracted → AccumulatedJobState). Forwarded here so a
   *  `calculateROM`-backed estimator (A5.P1b) can derive `suburbGroup`
   *  (postcode/suburb → operator-radius band) and pass `urgency`
   *  through to the ROM. Behaviour-neutral for `DEFAULT_ESTIMATOR_FN`
   *  (which reads only jobType/allowWidenedBand). */
  readonly suburb: string | null;
  readonly postcode: string | null;
  readonly urgency: string | null;
  /** When true, the caller may fall back to a wider first-pass
   *  bracket if the typed effort band can't be inferred. */
  readonly allowWidenedBand: boolean;
}

/** Discriminated union of conversation actions. */
export type ConversationAction =
  | { readonly type: 'continue' }
  | { readonly type: 'present_estimate'; readonly request: EstimatorRequest }
  | { readonly type: 'ask_contact' }
  | {
      /** Post-ROM: customer's ballpark-accepted; get contact + frame
       *  the next step as "operator comes out for a free quote", not
       *  "we've booked the work". Gated by quote-worthiness so we
       *  don't offer a site visit for jobs that shouldn't get one. */
      readonly type: 'offer_free_quote_visit';
      readonly reason: string;
    }
  | {
      readonly type: 'summarise_and_close';
      readonly summary: string;
    }
  | { readonly type: 'needs_more_info'; readonly hint: string }
  | { readonly type: 'not_worth_pursuing'; readonly reason: string }
  | { readonly type: 'needs_site_visit'; readonly reason: string };

/* ══════════════════════════════════════════════════════════════════════
 * Operator-tuned thresholds (frozen — verbatim from OJT)
 *
 * Exposed as named constants so tests and downstream tuning can read
 * them; semantically they ARE the cascade's behaviour.
 * ══════════════════════════════════════════════════════════════════════ */

export const THRESHOLDS = Object.freeze({
  /** Customer-fit score below which we early-exit if estimate already presented. */
  earlyExitFit: 15,
  /** Decision-readiness needed to summarise + close. */
  closeReadiness: 70,
  /** Estimate-readiness needed for the first-pass present_estimate path. */
  presentEstimateReadiness: 50,
  /** Scope clarity below which we stay in needs_more_info. */
  needsMoreInfoScope: 30,
  /** Scope clarity above which we force a present_estimate even at borderline readiness. */
  forcePresentEstimateScope: 35,
  /** Scope clarity below which "scope still unclear after estimate" triggers a site visit. */
  scopeUnclearAfterEstimate: 25,
  /** Worthiness needed to pivot to free-quote-visit. */
  freeQuoteWorthiness: 35,
  /** Customer-fit needed to pivot to free-quote-visit. */
  freeQuoteFit: 25,
  /** Default scoring values when null at the worthiness branch. */
  worthinessDefault: 50,
  fitDefault: 50,
});

/* ══════════════════════════════════════════════════════════════════════
 * The cascade
 *
 * Verbatim port from OJT, with the present_estimate branch refactored
 * to emit an EstimatorRequest rather than inlining the estimator
 * call. The branch order, the threshold numbers, the early-exit, the
 * worthiness guard — all unchanged.
 * ══════════════════════════════════════════════════════════════════════ */

/**
 * Evaluate the current state and decide the next conversation action.
 * Pure function. Verbatim cascade from OJT origin.
 */
export function evaluateConversationState(
  state: AccumulatedJobState,
): ConversationAction {
  // Disengaged → stop.
  if (state.conversationPhase === 'disengaged') {
    return { type: 'continue' };
  }
  // 'confirmed' means the customer is ready but we may not have sent the
  // summary yet — fall through to the normal cascade so summarise_and_close
  // fires if the contact + estimate conditions are met.

  // Early exit: not worth pursuing.
  if (
    state.customerFitScore !== null &&
    state.customerFitScore <= THRESHOLDS.earlyExitFit &&
    state.estimatePresented
  ) {
    return {
      type: 'not_worth_pursuing',
      reason: 'Customer fit score very low and estimate already presented.',
    };
  }
  if (state.estimateAckStatus === 'rejected') {
    return {
      type: 'not_worth_pursuing',
      reason: 'Customer rejected the ROM estimate.',
    };
  }

  // Site visit needed — check BEFORE presenting estimate.
  const siteVisitReason = detectNeedsSiteVisit(state);
  if (siteVisitReason !== null) {
    return { type: 'needs_site_visit', reason: siteVisitReason };
  }

  // Ready to close.
  if (
    state.decisionReadiness >= THRESHOLDS.closeReadiness &&
    state.estimatePresented &&
    state.estimateAcknowledged &&
    (state.customerName || state.customerPhone || state.customerEmail)
  ) {
    return {
      type: 'summarise_and_close',
      summary: buildSummary(state),
    };
  }

  // Estimate pushback — address concern before moving on.
  if (
    state.estimatePresented &&
    (state.estimateAckStatus === 'pushback' ||
      state.estimateAckStatus === 'wants_exact_price' ||
      state.estimateAckStatus === 'uncertain')
  ) {
    return { type: 'continue' };
  }

  // Post-ROM: offer a free site quote visit (worthiness-guarded).
  if (
    state.estimatePresented &&
    state.estimateAcknowledged &&
    (state.estimateAckStatus === 'accepted' ||
      state.estimateAckStatus === 'tentative') &&
    !state.customerPhone &&
    !state.customerEmail
  ) {
    const worthy =
      (state.quoteWorthinessScore ?? THRESHOLDS.worthinessDefault) >=
        THRESHOLDS.freeQuoteWorthiness &&
      (state.customerFitScore ?? THRESHOLDS.fitDefault) >=
        THRESHOLDS.freeQuoteFit;
    if (worthy) {
      return {
        type: 'offer_free_quote_visit',
        reason:
          'ROM accepted/tentative + job passes worthiness threshold — invite operator for a free quote',
      };
    }
    return {
      type: 'not_worth_pursuing',
      reason:
        'ROM accepted but worthiness/fit scores too low to justify a site visit.',
    };
  }

  // Need contact details (fallback path for non-accepted states).
  if (
    state.estimatePresented &&
    state.estimateAcknowledged &&
    !state.customerPhone &&
    !state.customerEmail
  ) {
    return { type: 'ask_contact' };
  }

  // Present estimate — but suppress for vague hourly seekers.
  const hasNoRealScope =
    !state.scopeDescription || state.scopeDescription.length < 40;
  const isPriceFocused =
    state.customerToneSignal === 'price_focused' ||
    state.budgetReaction === 'wants_hourly' ||
    state.estimateReaction === 'wants_exact_price' ||
    state.estimateReaction === 'rate_shopping';
  const isVagueHourlySeeker =
    isPriceFocused && (hasNoRealScope || state.clarityScore === 'vague');

  if (
    !state.estimatePresented &&
    !isVagueHourlySeeker &&
    state.estimateReadiness >= THRESHOLDS.presentEstimateReadiness &&
    state.scopeDescription &&
    state.suburb &&
    state.locationClarity >= 40
  ) {
    return {
      type: 'present_estimate',
      request: buildEstimatorRequest(state, /* allowWidenedBand */ true),
    };
  }

  // Force present_estimate at borderline readiness if scope is reasonable.
  if (
    !state.estimatePresented &&
    !isVagueHourlySeeker &&
    state.scopeClarity >= THRESHOLDS.forcePresentEstimateScope &&
    state.scopeDescription &&
    state.suburb
  ) {
    return {
      type: 'present_estimate',
      request: buildEstimatorRequest(state, /* allowWidenedBand */ false),
    };
  }

  // Need more info — but only if scope is genuinely vague.
  if (
    !state.estimatePresented &&
    state.scopeClarity < THRESHOLDS.needsMoreInfoScope &&
    !state.jobType
  ) {
    return {
      type: 'needs_more_info',
      hint: "I've got a rough idea of the job but need a bit more detail on the scope to give you a ballpark — can you tell me more about what's involved?",
    };
  }

  return { type: 'continue' };
}

/**
 * Detect if a site visit is needed based on hazardous keywords +
 * concerning material conditions. Verbatim port of OJT's
 * `detectNeedsSiteVisit`.
 */
export function detectNeedsSiteVisit(state: AccumulatedJobState): string | null {
  const desc = (state.scopeDescription || '').toLowerCase();
  const condition = (state.materialCondition || '').toLowerCase();

  // Tier 1: definitely hazardous — always flag.
  const hazardousKeywords =
    /asbestos|termit|subsid|structur(?:al|e)\s+(?:damage|issue|problem|fail)/;
  if (hazardousKeywords.test(desc) || hazardousKeywords.test(condition)) {
    return 'Possible hazardous or structural issue — need to inspect before pricing.';
  }

  // Tier 2: concerning but only if multiple signals present.
  const concerningWords = [
    'rotten',
    'sagg',
    'lean',
    'mould',
    'collaps',
    'buckl',
    'cave',
  ];
  const matchCount = concerningWords.filter(
    (w) => desc.includes(w) || condition.includes(w),
  ).length;
  if (matchCount >= 2) {
    return 'Multiple concerning indicators — should inspect before committing to a price.';
  }
  if (
    matchCount === 1 &&
    condition.length > 0 &&
    /rot|decay|water.?damage|soft.*through|crumbl/.test(condition)
  ) {
    return 'Material condition suggests possible hidden damage — worth inspecting.';
  }

  // Scope still very unclear after estimate presented.
  if (
    state.scopeClarity < THRESHOLDS.scopeUnclearAfterEstimate &&
    state.estimatePresented
  ) {
    return 'Scope still unclear after estimate presented — might need a look in person.';
  }

  return null;
}

/** Build a closing summary for the customer. Verbatim port of OJT's
 *  `buildSummary`. */
export function buildSummary(state: AccumulatedJobState): string {
  const parts: string[] = [];

  if (state.scopeDescription) parts.push(`Job: ${state.scopeDescription}`);
  if (state.suburb) parts.push(`Location: ${state.suburb}`);
  if (state.urgency && state.urgency !== 'unspecified') {
    const urgencyLabels: Record<string, string> = {
      emergency: 'ASAP',
      urgent: 'Urgent — next few days',
      next_week: 'Next week',
      next_2_weeks: 'Within a couple of weeks',
      flexible: 'Flexible timing',
      when_convenient: 'Whenever suits',
    };
    parts.push(`Timing: ${urgencyLabels[state.urgency] ?? state.urgency}`);
  }
  if (state.customerName) parts.push(`Name: ${state.customerName}`);
  if (state.customerPhone) parts.push(`Phone: ${state.customerPhone}`);
  if (state.customerEmail) parts.push(`Email: ${state.customerEmail}`);

  return parts.join('\n');
}

/** Build an EstimatorRequest from the current job state. */
function buildEstimatorRequest(
  state: AccumulatedJobState,
  allowWidenedBand: boolean,
): EstimatorRequest {
  return {
    jobType: state.jobType,
    subcategory: state.jobSubcategory,
    quantity: state.quantity,
    scopeDescription: state.scopeDescription,
    materials: state.materials,
    accessDifficulty: state.accessDifficulty,
    suburb: state.suburb,
    postcode: state.postcode,
    urgency: state.urgency,
    allowWidenedBand,
  };
}

/* ══════════════════════════════════════════════════════════════════════
 * System injection — operator-approved tone strings
 *
 * Verbatim from OJT origin. Each branch's text is the operator's
 * approved framing; do not edit lightly. The strings reference
 * "operator" as a placeholder; callers can post-process to substitute
 * the actual operator name (e.g. "Todd") if desired, but the structural
 * framing — ROM-not-quote, free on-site quote, expectation-check —
 * MUST be preserved.
 *
 * The OJT version interpolated `${name}` into the strings; the D-O7
 * port leaves a literal {OPERATOR} placeholder so callers do their own
 * name substitution post-hoc — keeps this function pure of persona
 * lookups.
 * ══════════════════════════════════════════════════════════════════════ */

/** Optional substitution for the {OPERATOR} placeholder. Default
 *  resolves to "Todd" for backwards-compatibility with the OJT origin. */
export function generateSystemInjection(
  action: ConversationAction,
  operatorName: string = 'Todd',
): string | null {
  const sub = (s: string): string => s.replace(/\{OPERATOR\}/g, operatorName);

  switch (action.type) {
    case 'present_estimate':
      // The caller renders the actual ROM wording; this injection just
      // tells the LLM to expect a ROM and to ask the expectation check.
      // The full ROM-relay is in the caller's prompt-injection step.
      return sub(
        '[SYSTEM: Present the ROUGH ORDER OF MAGNITUDE the estimator emits to the customer. The estimator wording is already framed as ROM-not-quote — use it. Do NOT invent any number. After the range, ask the expectation-check question so the customer self-qualifies on the ballpark.]',
      );

    case 'ask_contact':
      return sub(
        '[SYSTEM: The customer has acknowledged the ROM. The next step is a free on-site quote — not the job itself. Ask for contact details naturally, framed as "so {OPERATOR} can get in touch to arrange a free on-site quote". Don\'t make it sound like we\'ve booked the work.]',
      );

    case 'offer_free_quote_visit':
      return sub(
        `[SYSTEM: The customer's accepted the ROM as a workable ballpark. {OPERATOR}'s prepared to come out for a free on-site quote to turn that ballpark into a real number. Ask naturally for their name + phone/email so he can line up a time. Make clear the on-site quote is free and doesn't commit them to anything. IMPORTANT: do NOT confirm or commit to any specific date, time, or time window — you cannot access {OPERATOR}'s calendar. Just collect their availability preference and contact details, and tell them {OPERATOR} will be in touch to confirm. Reason logged: ${action.reason}]`,
      );

    case 'summarise_and_close':
      return sub(
        `[SYSTEM: Intake is complete. Summarise what's been logged and let the customer know {OPERATOR} will review and be in touch to confirm a time. Keep it brief and warm. CRITICAL: do NOT confirm a booking, do NOT commit to a specific date or time — you have no access to {OPERATOR}'s calendar. Say that {OPERATOR} will contact them to arrange a time.]\n\nSummary:\n${action.summary}`,
      );

    case 'needs_more_info':
      return sub(`[SYSTEM: ${action.hint}]`);

    case 'not_worth_pursuing':
      return sub(
        "[SYSTEM: This lead isn't a strong fit for a free on-site quote visit. Wrap up politely — thank them for reaching out, say the job might not be the best fit for {OPERATOR}'s schedule right now, and wish them well finding someone. Do NOT offer a site visit. Do NOT ask for contact details.]",
      );

    case 'needs_site_visit':
      return sub(
        '[SYSTEM: This job needs a site visit before any ballpark — too many unknowns to quote even a ROM honestly. Let the customer know that given what\'s described, {OPERATOR} would want to take a quick look before giving even a rough range. Ask if they\'d be happy for him to pop round (this visit is free).]',
      );

    case 'continue':
      return null;
  }
}

```
