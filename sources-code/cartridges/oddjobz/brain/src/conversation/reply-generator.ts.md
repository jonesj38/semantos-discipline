---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/reply-generator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.520174+00:00
---

# cartridges/oddjobz/brain/src/conversation/reply-generator.ts

```ts
/**
 * R-1 — Reply generator.
 *
 * Produces the bot's conversational response to a customer message.
 * Two steps:
 *
 *   1. evaluateConversationState(state) → ConversationAction
 *      Decides what the bot should DO next (ask for location, present
 *      estimate, summarise + close, etc.) using the operator-tuned cascade.
 *
 *   2. LLM chat-completion with generateSystemInjection(action) injected
 *      as a system directive alongside the conversation history.
 *      The model writes the actual reply text.
 *
 * Parameterised over ReplyLlmFn so callers inject the LLM backend and
 * tests inject a deterministic stub — same pattern as LlmCompleteFn in
 * lead-extract.ts.
 *
 * The present_estimate branch requires an estimatorFn callback — the
 * caller resolves the ROM wording from their effort-band service and
 * passes it back as a string. The reply generator injects it into the
 * system prompt so the model can relay it to the customer without
 * inventing numbers.
 */

import {
  evaluateConversationState,
  generateSystemInjection,
  type ConversationAction,
  type EstimatorRequest,
} from './state-manager.js';
import type { AccumulatedJobState } from './accumulated-job-state.js';
import type { BusinessContext } from './business-context.js';

// ── Types ─────────────────────────────────────────────────────────────────────

/** A single turn in the conversation history shown to the reply LLM. */
export interface ConversationTurn {
  role: 'user' | 'assistant';
  content: string;
}

/**
 * LLM callback for generating the reply text.
 * Parameterised so production wires Anthropic and tests inject a stub.
 *
 * `systemPrompt` is the operator-tuned injection from generateSystemInjection
 * plus any estimator wording. `history` is the prior turns. `latestMessage`
 * is the current customer message.
 */
export type ReplyLlmFn = (args: {
  systemPrompt: string;
  history: ReadonlyArray<ConversationTurn>;
  latestMessage: string;
}) => Promise<string>;

/**
 * Callback that produces ROM wording for a present_estimate action.
 *
 * Consumes the canonical {@link EstimatorRequest} that the
 * state-manager actually constructs (`action.request`) — previously a
 * divergent inline shape (had `suburb` but not `subcategory`/
 * `materials`, the reverse of EstimatorRequest), a latent mismatch
 * masked only because `DEFAULT_ESTIMATOR_FN` destructures just
 * `{jobType, allowWidenedBand}`. Unifying on EstimatorRequest is the
 * single source of truth and lets the A5.P1b `calculateROM`-backed
 * estimator read `suburb`/`postcode`/`urgency` without re-touching
 * call sites.
 */
export type EstimatorFn = (request: EstimatorRequest) => string;

export interface ReplyGeneratorInput {
  readonly state: AccumulatedJobState;
  readonly history: ReadonlyArray<ConversationTurn>;
  readonly latestMessage: string;
  readonly operatorName?: string;
  /** Required when action.type === 'present_estimate'. */
  readonly estimatorFn?: EstimatorFn;
  readonly llm: ReplyLlmFn;
  /** WP-6 — operator profile facts; build the default persona (any trade). */
  readonly businessContext?: BusinessContext;
  /** WP-6 — operator's active WP-5 prompt text; overrides the default persona. */
  readonly activePrompt?: string | null;
}

export interface ReplyGeneratorResult {
  readonly replyText: string;
  readonly action: ConversationAction;
  /** The system injection string passed to the LLM (null for 'continue'). */
  readonly systemInjection: string | null;
  /** The EXACT assembled system prompt the LLM saw this turn
   *  (BASE_SYSTEM + systemInjection [+ ROM line]). Surfaced so the
   *  conversation-turn patch can hash it for versioned provenance —
   *  the bot becomes auditable against its prompt, not a black box. */
  readonly assembledPrompt: string;
}

// ── Default estimator ─────────────────────────────────────────────────────────

/**
 * ROM band table — operator-tuned effort-band brackets by job type.
 * Verbatim from OJT's effortBandService (the simplified ROM-only path).
 * Replace with a real service call in production.
 */
const ROM_BANDS: Record<string, [number, number]> = {
  plumbing:       [150, 350],
  electrical:     [180, 380],
  carpentry:      [200, 600],
  painting:       [250, 800],
  tiling:         [300, 700],
  roofing:        [400, 1200],
  fencing:        [300, 900],
  doors_windows:  [150, 400],
  gardening:      [150, 450],
  cleaning:       [120, 300],
  general:        [120, 280],
};

export const DEFAULT_ESTIMATOR_FN: EstimatorFn = ({ jobType, allowWidenedBand }) => {
  const band = (jobType && ROM_BANDS[jobType]) ?? ROM_BANDS.general;
  const [low, high] = allowWidenedBand
    ? [Math.round(band[0] * 0.8), Math.round(band[1] * 1.2)]
    : band;
  return `$${low}–$${high}`;
};

/**
 * P3.5a — the SAME band `DEFAULT_ESTIMATOR_FN` shows the customer,
 * in integer cents, for the accept_rom money channel. Additive (the
 * estimator wording is unchanged); single source of truth so the
 * minted cell's `{costMin,costMax}` is exactly the range the customer
 * was shown (NOT a re-guess). Slice-3b later swaps ROM_BANDS for the
 * real calculateROM — this helper's signature is the stable seam.
 */
export function romBandCents(
  jobType: string | null,
  allowWidenedBand = false,
): { costMin: number; costMax: number } {
  const band = (jobType && ROM_BANDS[jobType]) ?? ROM_BANDS.general;
  const [low, high] = allowWidenedBand
    ? [Math.round(band[0] * 0.8), Math.round(band[1] * 1.2)]
    : band;
  return { costMin: low * 100, costMax: high * 100 };
}

// ── Base system prompt ────────────────────────────────────────────────────────

// WP-6 — guardrails apply to every persona (the generic default AND an operator's
// custom WP-5 prompt), so the conversation stays short + honest regardless of trade.
const GUARDRAILS = `Keep replies SHORT — two to four sentences max. Ask ONE question at a time. Never invent prices or commit to dates. Always sound like a human, not a bot.`;

/**
 * WP-6 — build the default persona from the operator's profile so any in-person
 * site-visit service business is framed correctly (no handyman hardcoding). Used
 * when the operator hasn't set a custom prompt (WP-5).
 */
function buildPersona(ctx?: BusinessContext): string {
  const trade = ctx?.tradeLabel?.trim();
  const name = ctx?.businessName?.trim();
  const who = name || (trade ? `a local ${trade.toLowerCase()} business` : 'a local service business');
  const lines: string[] = [
    `You are a friendly, professional intake assistant for ${who}. Your job is to collect just enough information to give a rough price range and decide whether a site visit is warranted.`,
  ];
  if (ctx?.services && ctx.services.length > 0) lines.push(`Services offered: ${ctx.services.join(', ')}.`);
  if (ctx?.geography?.trim()) {
    const radius = ctx.travelDistanceKm && ctx.travelDistanceKm > 0 ? ` (within ~${ctx.travelDistanceKm}km)` : '';
    lines.push(`Service area: ${ctx.geography.trim()}${radius}.`);
  }
  if (ctx?.hourlyRate && ctx.hourlyRate > 0) {
    lines.push(`Indicative rate: about ${ctx.currency ?? 'AUD'} ${ctx.hourlyRate}/hour — only ever give rough ranges, never a firm total.`);
  }
  if (ctx?.tone?.trim()) lines.push(`Tone: ${ctx.tone.trim()}.`);
  return lines.join('\n');
}

// ── Implementation ────────────────────────────────────────────────────────────

export async function generateReply(
  input: ReplyGeneratorInput,
): Promise<ReplyGeneratorResult> {
  const action = evaluateConversationState(input.state);
  const operatorName = input.operatorName ?? 'Todd';

  let systemInjection = generateSystemInjection(action, operatorName);

  // For present_estimate, resolve the ROM and embed it in the injection.
  if (action.type === 'present_estimate') {
    const estimator = input.estimatorFn ?? DEFAULT_ESTIMATOR_FN;
    const rom = estimator(action.request);
    systemInjection = systemInjection
      ? `${systemInjection}\n\n[ROM from estimator: ${rom}]`
      : `[ROM from estimator: ${rom}]`;
  }

  // WP-6 — persona = the operator's active WP-5 prompt if set, else the
  // profile-built default; guardrails always apply.
  const persona = input.activePrompt && input.activePrompt.trim().length > 0
    ? input.activePrompt.trim()
    : buildPersona(input.businessContext);
  const base = `${persona}\n\n${GUARDRAILS}`;
  const systemPrompt = systemInjection
    ? `${base}\n\n${systemInjection}`
    : base;

  const replyText = await input.llm({
    systemPrompt,
    history: input.history,
    latestMessage: input.latestMessage,
  });

  return { replyText, action, systemInjection, assembledPrompt: systemPrompt };
}

```
