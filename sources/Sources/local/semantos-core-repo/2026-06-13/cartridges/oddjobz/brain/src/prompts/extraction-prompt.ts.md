---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/prompts/extraction-prompt.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.528683+00:00
---

# cartridges/oddjobz/brain/src/prompts/extraction-prompt.ts

```ts
/**
 * D-O7 — extraction prompt.
 *
 * Origin: `oddjobtodd/src/lib/ai/prompts/extractionPrompt.ts` —
 *         operator-tuned across Sprints 1–3 of OJT (the "be aggressive
 *         about inferring likely meaning" pass).
 * Last tuned: 2026-04 (the OJT-P6 TAGGED FACTS section + jobPivot HARD
 *             RULES).
 *
 * The OJT version depended on `@/lib/lexicons` for the TAGGED FACTS
 * section (jural / property-management / trades-job-types / building-
 * job-dimensions registries). semantos-core's substrate
 * `TradesLexicon` is a DIFFERENT thing (it carries the §O4 transition
 * categories: lead | estimate | quote | dispatch | visit | invoice |
 * settle | message). The OJT job-type taxonomy (carpentry | plumbing
 * | electrical | …) is a complementary classification that the prompt
 * uses to bucket inbound work; we declare it locally as
 * `JOB_TYPE_VALUES`. The other lexicons (jural, pm, building-job-
 * dimensions) are out of scope for D-O7 and surface via the
 * parameterised `taggedFactsSection`.
 *
 * The prompt is a frozen string export: callers pass current job state
 * + latest message + a conversation summary and get the prompt body
 * back. Pure function. Tests assert the prompt's invariants (it
 * mentions the JSON shape verbatim, the EXTRACTION RULES preserve the
 * tuned thresholds, etc.).
 */

/** Schema version of this prompt. Bump (and APPEND a new version
 *  entry in conversation/prompt-store.ts) on any intentional change to
 *  the prompt text, so the old version stays in the audit chain. */
export const EXTRACTION_PROMPT_VERSION = '1.0.0' as const;

/** A subset of the OJT `AccumulatedJobState` — the fields the prompt
 *  CITES verbatim in its CURRENT KNOWN STATE block. The accumulated
 *  state itself lives in `cartridges/oddjobz/brain/src/conversation/
 *  accumulated-job-state.ts`; this interface is the import-only shape
 *  the prompt needs. */
export interface ExtractionPromptState {
  readonly customerName?: string | null;
  readonly customerPhone?: string | null;
  readonly customerEmail?: string | null;
  readonly suburb?: string | null;
  readonly jobType?: string | null;
  readonly scopeDescription?: string | null;
  readonly conversationPhase?: string | null;
  readonly estimatePresented?: boolean;
  /** Anything else the caller wants in the JSON-stringified state block;
   *  the prompt renders the FULL state, not just the fields above. */
  readonly [k: string]: unknown;
}

/** Input to `buildExtractionPrompt`. */
export interface ExtractionPromptInput {
  /** The accumulated job state at this turn (rendered as JSON). */
  readonly currentState: ExtractionPromptState;
  /** The latest customer message (verbatim). */
  readonly latestMessage: string;
  /** A short text summary of the conversation so far. */
  readonly conversationSummary: string;
  /** Optional override for the TAGGED FACTS section. Defaults to the
   *  trades-only section derived from `TradesLexicon`. */
  readonly taggedFactsSection?: string;
}

/** The list of canonical job-type enum values — the OJT taxonomy of
 *  inbound handyman work. Distinct from the semantos-core
 *  `TradesLexicon` (which is the §O4 transition vocabulary). Mirrors
 *  OJT's old `JOB_TYPE_VALUES` verbatim. */
export const JOB_TYPE_VALUES = [
  'carpentry',
  'plumbing',
  'electrical',
  'painting',
  'general',
  'fencing',
  'tiling',
  'roofing',
  'doors_windows',
  'gardening',
  'cleaning',
  'other',
] as const;
export type JobTypeValue = (typeof JOB_TYPE_VALUES)[number];

/** One-line definitions for the job-type categories. Verbatim from
 *  OJT origin. */
const JOB_TYPE_DEFINITIONS: Readonly<Record<JobTypeValue, string>> = Object.freeze({
  carpentry: 'framing, cabinetry, decks, shelves, built-ins, timber work',
  plumbing: 'taps, drains, hot water, basin, pipes, toilets',
  electrical: 'power points, switches, light fittings, circuits, rewires',
  painting: 'interior/exterior coats, patching, feature walls, stain',
  general:
    'assembly, flatpack, wardrobes, bracket work, hang picture / TV mount (catch-all for non-trade-specific handy jobs)',
  fencing: 'panels, posts, gates, palings, boundary fences',
  tiling: 'floor/wall tile repair, grout, splashbacks, bathroom tiling',
  roofing: 'leaks, gutters, ridge caps, tile replacement, whirlybirds',
  doors_windows:
    'door hanging, adjusting, frames, locks, window sashes, sliding units',
  gardening: 'mow, hedge, mulch, retaining walls, landscaping',
  cleaning: 'pressure wash, house wash, gutter clean, end-of-lease',
  other: "doesn't fit any of the above — use rarely",
});

/** The trades-only TAGGED FACTS section. Replaces the fuller OJT
 *  version that included jural / pm / building-job-dimensions
 *  lexicons. Callers that have those lexicons available can pass
 *  `taggedFactsSection` to override.
 *
 *  L-1: Now includes both the trades-job-types lexicon (job classification)
 *  AND the jural lexicon (speech-act category) so the intent reducer's
 *  rhetoric-pass can select the correct action. Each message turn should
 *  emit exactly one jural fact and at most one trades-job-types fact. */
export function buildTradesTaggedFactsSection(): string {
  const tradesList = JOB_TYPE_VALUES.map(
    (c) => `  - ${c}: ${JOB_TYPE_DEFINITIONS[c]}`,
  ).join('\n');

  return `
TAGGED FACTS:

Alongside the extraction fields above, emit a \`taggedFacts\` array. Each element tags a single fact against ONE (lexicon, category) pair. Emit NULL facts only when genuinely no category applies.

Shape:
  "taggedFacts": [
    {
      "lexicon": "jural" | "trades-job-types" | null,
      "category": <one of the categories for that lexicon> | null,
      "confidence": <number 0..1>,
      "fact": <one-sentence canonicalised statement of the fact>,
      "source": <verbatim slice of the customer's utterance that supports this tag>
    }
  ]

── Lexicon 1: jural (REQUIRED — emit exactly ONE per turn) ──────────────────
Tag the customer's PRIMARY speech act. Choose the category that best describes
what the customer is DOING with their words — their normative move:

  - declaration  : Asserting a fact or reporting a situation.
                   Examples: "My tap is dripping", "There's a crack in the wall",
                   "The hot water system stopped working".

  - obligation   : Expressing a duty, requirement, or constraint on the work.
                   Examples: "You'll need to use copper pipe", "The work must be done
                   before Friday", "You have to match the existing paint colour".

  - power        : Authorising, approving, or granting permission to act.
                   Examples: "Go ahead with the quote", "I approve that",
                   "Yes, book it in", "Confirmed, please proceed".

  - condition    : Scheduling, proposing timing, or stating a conditional.
                   Examples: "Can you come next Tuesday?", "I need it done next week",
                   "I'm available Wednesday morning".

  - transfer     : Requesting financial movement — invoicing or payment.
                   Examples: "Please send me the invoice", "I'll pay by bank transfer",
                   "How do I pay?", "Can you send through what I owe?".

Rules for jural:
- Emit EXACTLY ONE jural fact per turn. If the message contains multiple speech
  acts, tag the DOMINANT one (the one most likely to advance the job state).
- "power" requires an explicit approval signal — tentative or questioning is NOT power.
- "transfer" requires explicit mention of payment, invoice, or cost settlement.
- When unsure between declaration and condition, prefer declaration.

── Lexicon 2: trades-job-types (emit at most ONE per turn) ──────────────────
Classify the physical trade the job belongs to. Only emit when the trade is
clear from this message. Match the \`jobType\` field above.

${tradesList}

── Rules (both lexicons) ────────────────────────────────────────────────────
- Confidence below 0.6 will be discarded. Only emit facts you are confident about.
- NEVER set lexicon non-null and category null, or vice versa — partial tags are rejected.
- If no trades-job-types category applies clearly, emit lexicon=null, category=null for that slot.
- The jural fact's "fact" field should be a clean one-sentence restatement, not a verbatim quote.
- The trades fact's "fact" field should name the trade explicitly (e.g. "Customer reports a plumbing issue").
`;
}

/** The full enum list rendered as a quoted union for the JSON schema
 *  block in the prompt. */
function renderJobTypeUnion(): string {
  return JOB_TYPE_VALUES.map((v) => `"${v}"`).join(' | ');
}

/**
 * Build the extraction prompt for a chat turn. Verbatim port of the
 * OJT `buildExtractionPrompt` body — every EXTRACTION RULE, every
 * jobPivot HARD RULE, every conversation-phase mapping is preserved.
 */
export function buildExtractionPrompt(input: ExtractionPromptInput): string {
  const taggedFactsSection =
    input.taggedFactsSection ?? buildTradesTaggedFactsSection();
  const jobTypeUnion = renderJobTypeUnion();

  return `You are a data extraction agent for a Sunshine Coast handyman business. Extract structured JSON from a customer's message in context.

CRITICAL RULES:
- Be aggressive about extraction. Extract LIKELY meanings, not just explicit statements.
- A customer saying "3 doors need doing" means jobType is "doors_windows", quantity is "3 doors", repairReplaceSignal is "replace".
- Output ONLY raw JSON. No markdown fences, no backticks, no explanation. Just the { } object.
- Use ONLY the exact enum values listed below. Do NOT invent new values.

CURRENT KNOWN STATE:
${JSON.stringify(input.currentState, null, 2)}

CONVERSATION SO FAR:
${input.conversationSummary}

LATEST CUSTOMER MESSAGE:
"${input.latestMessage}"

Return this JSON structure. Use null for genuinely unknown fields:

{
  "customerName": string | null,
  "customerPhone": string | null,
  "customerEmail": string | null,
  "suburb": string | null,
  "locationClue": string | null,
  "address": string | null,
  "postcode": string | null,
  "accessNotes": string | null,
  "jobType": ${jobTypeUnion} | null,
  "jobTypeConfidence": "certain" | "likely" | "guess" | null,
  "jobSubcategory": string | null,
  "repairReplaceSignal": "repair" | "replace" | "install" | "inspect" | "unclear" | null,
  "scopeDescription": string | null,
  "quantity": string | null,
  "materials": string | null,
  "materialCondition": string | null,
  "accessDifficulty": "ground_level" | "ladder_required" | "scaffolding_required" | "difficult_access" | null,
  "photosReferenced": boolean | null,
  "urgency": "emergency" | "urgent" | "next_week" | "next_2_weeks" | "flexible" | "when_convenient" | "unspecified" | null,
  "estimateReaction": "accepted" | "tentative" | "uncertain" | "pushback" | "rejected" | "wants_exact_price" | "rate_shopping" | "unclear" | null,
  "budgetReaction": "accepted" | "ok" | "unsure" | "expensive" | "cheap" | "wants_hourly" | "wants_guarantee" | null,
  "customerToneSignal": "friendly" | "practical" | "demanding" | "suspicious" | "price_focused" | "vague" | "impatient" | null,
  "micromanagerSignals": boolean | null,
  "cheapestMindset": boolean | null,
  "clarityScore": "very_clear" | "clear" | "vague" | "confused" | null,
  "contactReadiness": "offered" | "willing" | "reluctant" | "refused" | null,
  "jobPivot": "same_job" | "additional_scope" | "different_job" | null,
  "isComplete": boolean,
  "missingInfo": string[],
  "conversationPhase": "greeting" | "describing_job" | "providing_details" | "providing_location" | "providing_contact" | "reviewing_estimate" | "confirmed" | "disengaged"
}

EXTRACTION RULES:

1. JOB TYPE — use the EXACT values above:
   "doors" / "door" → "doors_windows"
   "fence" / "fencing" / "paling" → "fencing"
   "tap" / "pipe" / "drain" / "leak" → "plumbing"
   "deck" / "timber framing" / "shelf" / "cabinet" / "pergola" → "carpentry"
   "paint" / "repaint" → "painting"
   "tile" / "grout" → "tiling"
   "roof" / "gutter" → "roofing"
   "light" / "power point" / "switch" → "electrical"
   "curtain rod" / "blind" / "hook" / "hang picture" / "towel rail" / "misc fix" → "general"
   "garden" / "lawn" / "hedge" / "tree" → "gardening"
   If ambiguous, use "general" and set jobTypeConfidence to "guess"

2. URGENCY — use the EXACT values above:
   "ASAP" / "today" / "emergency" / "flooding" → "emergency"
   "urgent" / "this week" / "broken" (safety risk) → "urgent"
   "next week" / "soon" → "next_week"
   "couple of weeks" / "fortnight" → "next_2_weeks"
   "no rush" / "whenever" / "flexible" → "flexible"
   "when you can" / "when convenient" → "when_convenient"

3. ESTIMATE REACTION — only if estimate was previously presented:
   "yeah that's fine" / "sounds good" / "about what I expected" → "accepted"
   "ok" / "I guess" / "maybe" → "tentative"
   "hmm" / "that much?" / "I was thinking less" → "pushback"
   "that seems cheap" / "how can you do it for that?" / "seems low" / "that's not enough time" → "pushback"
   Questions about method/feasibility ("how do you mortise in that time?", "two coats?") → "pushback"
   "no way" / "too expensive" / "forget it" → "rejected"
   "what's your hourly rate?" / "can you do it cheaper?" → "wants_exact_price"
   "I'm getting a few quotes" / "what do others charge?" → "rate_shopping"
   IMPORTANT: "cheap" is pushback (skepticism), not acceptance!

4. CUSTOMER TONE — read between the lines:
   Helpful, detail naturally → "friendly" or "practical"
   Short reluctant answers → "vague"
   Demanding exact times/methods/prices → "demanding"
   Questioning everything / comparing → "suspicious"
   Every message mentions cost → "price_focused"
   Wants it done NOW, annoyance at timeline → "impatient"

5. CHEAPEST MINDSET — set true if ANY of these:
   - Asks for cheapest option, cheapest fix, cheapest way
   - Only wants a patch/bandaid, not proper repair
   - Pushes back on materials cost, wants to supply own cheap materials
   - Asks "can you just..." to minimise scope
   - Compares to DIY cost or YouTube estimates
   - Multiple mentions of budget/cost being the top priority
   - Tone suggests they see the job as trivial and overpriced

6. CONVERSATION PHASE:
   First message or just said hi → "greeting"
   Describing what they need → "describing_job"
   Answering follow-up questions → "providing_details"
   Talking about location → "providing_location"
   Giving name/phone/email → "providing_contact"
   Responding to an estimate → "reviewing_estimate"
   Agreed to proceed → "confirmed"
   Gone quiet / said no thanks → "disengaged"

7. MISSING INFO — list what would help most right now.

8. SUBURB — extract any Sunshine Coast suburb mentioned. Common ones: Noosa Heads, Noosaville, Sunshine Beach, Tewantin, Cooroy, Peregian Beach, Maroochydore, Mooloolaba, Buderim, Caloundra, Nambour, Coolum Beach, Eumundi, Doonan. Also extract from context like "I'm in Noosa" → "Noosa Heads".

9. JOB PIVOT — detect when the customer changes topic mid-conversation:
   - Same work, more details about the current job → "same_job"
   - Adding related scope ("also need...", "while you're here...", "and the kitchen too") that's the SAME TRADE → "additional_scope"
   - Completely DIFFERENT trade or unrelated work (fencing → painting, plumbing → carpentry) → "different_job"
   - First message or no prior job context → null
   - If unsure, use "same_job" — only use "different_job" when it's clearly a separate job

   HARD RULES — these override anything else:
   - If CURRENT KNOWN STATE shows estimatePresented=true OR conversationPhase="reviewing_estimate", jobPivot MUST be "same_job" UNLESS the customer literally names a different property/trade ("also at my mum's house", "different job — paint the bedrooms"). Pushback on the estimate ("seems cheap", "5 hrs?", "how do you do two coats in that time", "bit steep", "what's your rate") is ALWAYS "same_job".
   - Questions about method, materials, time, or price are NEVER different_job — they're the customer probing the current scope. Use "same_job".
   - Single-sentence challenges (under 15 words) referencing time/cost/method are "same_job", not pivots.

${taggedFactsSection}
Output ONLY the raw JSON object. No \`\`\`json fences. No markdown. No explanation.`;
}

```
