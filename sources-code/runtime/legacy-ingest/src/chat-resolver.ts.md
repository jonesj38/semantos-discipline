---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/chat-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.130457+00:00
---

# runtime/legacy-ingest/src/chat-resolver.ts

```ts
/**
 * T9 — Chat resolver (the user-acceptance gate for the reingest PRD).
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §TDD Gate / T9:
 *   "Chat resolver integration: 'quote 500 for the pergola job'
 *    disambiguates to single job_cell."
 *
 * Given an operator utterance (PWA chat, REPL command, voice
 * transcription) plus a JobsView query seam over the typed job_cells
 * minted by the reingest pipeline (D-RTC.6), produce one of:
 *
 *   • a single matched job_cell_id with confidence + reasons
 *   • an ambiguous-candidates list when ≥2 jobs match the same hint
 *   • a no-match result so the operator can pick from the open queue
 *
 * The matcher is intentionally vocabulary-driven: a curated dictionary
 * of service tags (mirroring the v0.6 extractor prompt's lexicon) plus
 * an intent classifier. No LLM in the resolver path — keeps it fast,
 * deterministic, debuggable.
 */

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

export type ChatIntent =
  | 'quote'
  | 'schedule'
  | 'complete'
  | 'invoice'
  | 'status'
  | 'note'
  | 'unknown';

/** Subset of the JobCellPayload fields the resolver needs to match against. */
export interface JobSummary {
  readonly cellId: string;
  readonly services: readonly string[];
  /** "lead" | "quoted" | "scheduled" | "in_progress" | ... */
  readonly state: string;
  /** Optional display name — helps the resolver report ambiguities. */
  readonly displayName?: string;
  /** Optional site id — supports "the leak at 10 list lane" reference. */
  readonly siteId?: string | null;
  /** Optional issuance date — supports "the recent" tie-breaker. */
  readonly issuanceDate?: string | null;
}

/** Caller-provided query seam against the brain's view of jobs. */
export interface JobsView {
  /**
   * Returns active jobs whose `services` overlap with the input set
   * (set-intersection semantics). Brain-side wires this to a typeHash
   * query on TAG_JOB rows filtered by services[] ⊇ input.
   *
   * When `services` is empty, returns ALL open jobs — the resolver
   * uses this for fallback ambiguity reporting.
   */
  findActiveByServices(services: readonly string[]): Promise<readonly JobSummary[]>;
}

export interface ResolverArgs {
  readonly utterance: string;
  readonly jobsView: JobsView;
  /** Optional explicit caller-supplied hints (e.g. from PWA chat context). */
  readonly siteHint?: string | null;
}

export type ResolverResult =
  | { kind: 'match'; cellId: string; confidence: number; intent: ChatIntent; reasons: readonly string[] }
  | { kind: 'ambiguous'; candidates: readonly JobSummary[]; intent: ChatIntent; reasons: readonly string[] }
  | { kind: 'none'; intent: ChatIntent; reasons: readonly string[] };

/* ──────────────────────────────────────────────────────────────────────
 * Service-tag lexicon (mirrors v0.6 extractor prompt vocabulary)
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Map utterance keywords → canonical service tags. Multiple keywords
 * may map to the same tag ("leak"/"leaky"/"dripping" → "leak-investig-
 * ation"); a single utterance may yield several tags.
 */
const SERVICE_KEYWORDS: ReadonlyMap<RegExp, string> = new Map([
  [/\bpergola\b/i, 'pergola'],
  [/\bdeck(?:ing)?\b/i, 'decking'],
  [/\bfenc(?:e|ing)\b/i, 'fence-replacement'],
  [/\bgate\b/i, 'gate-repair'],
  [/\broof(?:ing)?\b/i, 'roof-repair'],
  [/\bgutter(?:s)?\b/i, 'gutter-repair'],
  [/\btap(?:s)?\b/i, 'tap-replacement'],
  [/\b(?:leak|leaky|leaking|dripping)\b/i, 'leak-investigation'],
  [/\bhot[\s-]?water\b/i, 'hot-water-system'],
  [/\boven\b/i, 'oven-repair'],
  [/\bdishwasher\b/i, 'dishwasher-repair'],
  [/\bplumb(?:er|ing)\b/i, 'plumbing'],
  [/\belectric(?:al|ian)\b/i, 'electrical'],
  [/\b(?:carpenter|carpentry)\b/i, 'carpentry'],
  [/\b(?:builder|building)\b/i, 'building'],
  [/\blandscap(?:e|ing)\b/i, 'landscaping'],
  [/\b(?:lawn|mow|mowing)\b/i, 'lawn-care'],
  [/\bpaint(?:er|ing)\b/i, 'painting'],
  [/\btil(?:e[rs]?|ing)\b/i, 'tiling'],
  [/\bwindow(?:s)?\b/i, 'window-repair'],
  [/\bdoor(?:s)?\b/i, 'door-repair'],
]);

const INTENT_PATTERNS: ReadonlyArray<{ rx: RegExp; intent: ChatIntent }> = [
  { rx: /\b(?:quote|quoting|estimate|price|cost)\b/i, intent: 'quote' },
  { rx: /\b(?:schedule|book|arrange|attend|attendance)\b/i, intent: 'schedule' },
  { rx: /\b(?:complete[d]?|finish(?:ed)?|done|wrap(?:ped)?|close[d]?)\b/i, intent: 'complete' },
  { rx: /\b(?:invoice|bill|send\s+invoice|payment)\b/i, intent: 'invoice' },
  { rx: /\b(?:status|update|where(?:'?s)?\s+(?:we|the)|when\s+(?:will|can))\b/i, intent: 'status' },
  { rx: /\b(?:note|remember|fyi|note\s+to)\b/i, intent: 'note' },
];

/* ──────────────────────────────────────────────────────────────────────
 * Public API
 * ────────────────────────────────────────────────────────────────────── */

export async function resolveJobReference(
  args: ResolverArgs,
): Promise<ResolverResult> {
  const reasons: string[] = [];
  const intent = detectIntent(args.utterance);
  if (intent !== 'unknown') reasons.push(`intent: ${intent}`);

  const services = extractServiceTags(args.utterance);
  if (services.length > 0) {
    reasons.push(`service tags: [${services.join(', ')}]`);
  } else {
    reasons.push('no service tags in utterance');
  }

  const candidates = await args.jobsView.findActiveByServices(services);

  if (candidates.length === 0) {
    return { kind: 'none', intent, reasons };
  }
  if (candidates.length === 1) {
    // Confidence = 1.0 when we matched on a service tag, 0.6 when
    // there was only one open job globally (no tag match).
    const confidence = services.length > 0 ? 1.0 : 0.6;
    reasons.push(`single candidate matched`);
    return {
      kind: 'match',
      cellId: candidates[0]!.cellId,
      confidence,
      intent,
      reasons,
    };
  }

  // Multiple candidates — try the site hint to disambiguate.
  if (args.siteHint) {
    const sited = candidates.filter(c => c.siteId === args.siteHint);
    if (sited.length === 1) {
      reasons.push(`site hint narrowed ${candidates.length} → 1`);
      return {
        kind: 'match',
        cellId: sited[0]!.cellId,
        confidence: 0.9,
        intent,
        reasons,
      };
    }
    if (sited.length > 1) {
      reasons.push(`site hint narrowed ${candidates.length} → ${sited.length}`);
      return { kind: 'ambiguous', candidates: sited, intent, reasons };
    }
  }

  // Tie-breaker on issuance date — most recent wins for `complete` /
  // `invoice` intents (the operator typically refers to the most
  // recent job). For `quote` / `schedule`, leave ambiguous since
  // they're job-creation-adjacent and disambiguation must be
  // explicit.
  if (intent === 'complete' || intent === 'invoice') {
    const sorted = [...candidates].sort(
      (a, b) => (b.issuanceDate ?? '').localeCompare(a.issuanceDate ?? ''),
    );
    const top = sorted[0]!;
    const next = sorted[1]!;
    if (top.issuanceDate && top.issuanceDate !== next.issuanceDate) {
      reasons.push(
        `most-recent tie-break on issuance_date (${top.issuanceDate} vs ${next.issuanceDate})`,
      );
      return {
        kind: 'match',
        cellId: top.cellId,
        confidence: 0.75,
        intent,
        reasons,
      };
    }
  }

  reasons.push(`${candidates.length} candidates`);
  return { kind: 'ambiguous', candidates, intent, reasons };
}

/* ──────────────────────────────────────────────────────────────────────
 * Exposed helpers (for tests + the brain-side resolver wiring)
 * ────────────────────────────────────────────────────────────────────── */

export function extractServiceTags(utterance: string): string[] {
  const seen = new Set<string>();
  for (const [rx, tag] of SERVICE_KEYWORDS) {
    if (rx.test(utterance)) seen.add(tag);
  }
  return [...seen];
}

export function detectIntent(utterance: string): ChatIntent {
  for (const p of INTENT_PATTERNS) {
    if (p.rx.test(utterance)) return p.intent;
  }
  return 'unknown';
}

/**
 * Pull dollar amounts out of the utterance — used by the PWA chat to
 * pre-fill a quote / invoice cell once the resolver locked onto the
 * target job. Returns an array because operators sometimes mention
 * multiple amounts ("quote 500 to 700 for the pergola").
 */
export function extractMoneyAmounts(utterance: string): number[] {
  const out: number[] = [];
  // $500 | 500 dollars | 500.50 | $1,200
  const rx = /(?:\$\s?(\d{1,3}(?:,\d{3})*(?:\.\d+)?))|(?:\b(\d{2,6})(?:\.\d+)?\s*(?:dollars|d|aud)?\b)/gi;
  let m: RegExpExecArray | null;
  while ((m = rx.exec(utterance)) !== null) {
    const raw = (m[1] ?? m[2] ?? '').replace(/,/g, '');
    const n = parseFloat(raw);
    if (Number.isFinite(n) && n > 0) out.push(n);
    if (out.length >= 8) break;
  }
  return out;
}

```
