---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/pask_sweep.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.563509+00:00
---

# cartridges/betterment/brain/src/pask_sweep.ts

```ts
/**
 * Pask sweep — derive primed themes from recent practice history.
 *
 * The SCAN state needs to tell the practitioner what is still live in
 * their field — rather than asking them to manually score 7 dimensions,
 * we compute it from history.  This is the pask insight applied to the
 * personal data layer: themes that keep reappearing have high constraint
 * weight; themes that have been sealed have higher stability.
 *
 * Design: pure function over recent cell payloads.  No I/O.  The caller
 * (brain endpoint or Flutter app) is responsible for fetching the cells
 * and passing them in.
 *
 * Pask connection:
 *   - Constraint weight ≈ occurrence frequency (theme keeps entering conversation)
 *   - Stability ≈ sealed_occurrences / total_occurrences (topic reaching closure)
 *   - Pruning ≈ stability > 0.85 for 3+ consecutive sessions (not implemented here;
 *     left for the kernel-side paskian.graph.pruned emitter)
 *
 * Trajectory (day-over-day trend):
 *   When the caller supplies `windowSplitMs`, each primed theme also carries a
 *   `trend` comparing the theme's charge in the PRIOR window (cells minted
 *   before the split) against the CURRENT window (cells minted at/after it).
 *   This surfaces whether a recurring point is *escalating* (more charge, no
 *   closure) or *settling* (reaching resolution) over time — the analytical
 *   payoff of "a conversation with myself across days".  Omitting the split
 *   reproduces the original behavior exactly (no `trend` emitted).
 *
 * v0.1.0 limitations:
 *   - Theme extraction from rawText uses simple stopword-filtered frequency;
 *     semantic clustering is a future improvement.
 *   - sealedReleaseIds is a comma-separated string (v0.1.0 schema);
 *     array shape deferred to v0.2.0.
 *   - No cross-session persistence of stability history — each sweep is
 *     stateless over the provided window.  Persistence is a TODO when
 *     the brain-side pask snapshot store is wired for betterment cells.
 */

// ─── Input types (mirror cell payload shapes from cell-types/) ─────────────

export interface ReleaseCellInput {
  readonly cellId: string
  readonly mintedAt?: number // epoch ms — for recency scoring
  readonly payload: {
    readonly themes?: string          // comma-separated tags (optional)
    readonly rawText: string
    readonly day?: string             // local ISO day key (YYYY-MM-DD)
    readonly valence?: number         // -1..1
    readonly elevation?: number       // 1..10
  }
}

export interface InsightCellInput {
  readonly cellId: string
  readonly mintedAt?: number
  readonly payload: {
    readonly content: string
    readonly dimensions?: string      // comma-separated
    readonly source?: string
    readonly tags?: string
  }
}

export interface PatternCellInput {
  readonly cellId: string
  readonly mintedAt?: number
  readonly payload: {
    readonly description: string
    readonly category: string
    readonly polarity: string
    readonly strength?: number
    readonly occurrenceCount?: number
  }
}

export interface SealCellInput {
  readonly cellId: string
  readonly mintedAt?: number
  readonly payload: {
    readonly sealedReleaseIds: string // comma-separated cellIds (v0.1.0)
    readonly elevation?: number
  }
}

export interface SessionCellInput {
  readonly cellId: string
  readonly mintedAt?: number
  readonly payload: {
    readonly date: string
    readonly elevation: number
  }
}

export interface PaskSweepInput {
  readonly recentReleaseCells: readonly ReleaseCellInput[]
  readonly recentInsightCells: readonly InsightCellInput[]
  readonly recentPatternCells: readonly PatternCellInput[]
  readonly recentSealCells: readonly SealCellInput[]
  readonly recentSessionCells: readonly SessionCellInput[]
  /**
   * Optional trajectory split (epoch ms).  Cells with `mintedAt < windowSplitMs`
   * form the PRIOR window; cells at/after it form the CURRENT window.  When set,
   * each primed theme carries a `trend`.  When omitted, no `trend` is emitted.
   */
  readonly windowSplitMs?: number
}

// ─── Output types ─────────────────────────────────────────────────────────────

export type SuggestedNextState = 'RELEASE' | 'CONNECTION' | 'VACUUM' | 'INSIGHT_CAPTURE'

/** Direction of a theme's charge over the trajectory window. */
export type TrendDirection = 'escalating' | 'settling' | 'steady' | 'new'

export interface ThemeTrend {
  /** Normalized occurrence weight in the prior window (0 if absent). */
  readonly priorWeight: number
  /** Stability (sealed/total) in the prior window (0 if absent). */
  readonly priorStability: number
  /** currentWeight − priorWeight (positive = more charge recently). */
  readonly weightDelta: number
  /** currentStability − priorStability (positive = moving toward closure). */
  readonly stabilityDelta: number
  /**
   * - `new`        — first appeared in the current window (no prior charge)
   * - `settling`   — stability rising (the point is reaching resolution)
   * - `escalating` — more charge recently with no rise in closure
   * - `steady`     — present in both windows, little change
   */
  readonly direction: TrendDirection
}

export interface PrimedTheme {
  /** The concept label (extracted or explicit). */
  readonly concept: string
  /** Normalized occurrence weight 0–1 (1 = most frequent in window). */
  readonly weight: number
  /**
   * Paskian stability estimate 0–1.
   * 0 = fully live, high charge.  1 = closed / resolved.
   * Only themes with stability < 0.85 are included in the output.
   */
  readonly stability: number
  /** ISO date string of most recent cell referencing this theme. */
  readonly lastSeen: string
  /** Source cell IDs contributing to this theme. */
  readonly cellIds: readonly string[]
  /** Suggested entry state based on theme characteristics. */
  readonly suggestedState: SuggestedNextState
  /** Day-over-day trajectory — present only when `windowSplitMs` was supplied. */
  readonly trend?: ThemeTrend
}

export interface PaskSweepResult {
  /** Themes ordered by stability ascending (least stable = most needing attention first). */
  readonly primedThemes: readonly PrimedTheme[]
  /** Rolling elevation estimate from recent sessions (1–10). */
  readonly overallElevationEstimate: number
  /** Whether the field appears clear (all themes stable or no history). */
  readonly fieldIsClear: boolean
  readonly sweepTimestamp: number
}

// ─── Stopword list ────────────────────────────────────────────────────────────

// Common English words that carry no thematic weight.
const STOPWORDS = new Set([
  'that', 'this', 'with', 'have', 'from', 'they', 'been', 'were', 'said',
  'each', 'which', 'their', 'there', 'will', 'what', 'when', 'make', 'like',
  'time', 'just', 'know', 'take', 'into', 'year', 'your', 'good', 'some',
  'could', 'them', 'other', 'than', 'then', 'look', 'only', 'come', 'over',
  'also', 'back', 'after', 'most', 'about', 'feel', 'want', 'need', 'more',
  'very', 'really', 'think', 'much', 'right', 'still', 'well', 'around',
  'even', 'here', 'going', 'down', 'does', 'always', 'through', 'being',
])

// Trend sensitivity — deltas below this are treated as no meaningful change.
const TREND_EPSILON = 0.05

// ─── Implementation ───────────────────────────────────────────────────────────

/**
 * Extract candidate themes from a raw text string.
 * Returns lowercase words of 4+ chars, stopword-filtered.
 */
function extractKeywords(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[\s,.'";:!?()\-—\n]+/)
    .filter((w) => w.length >= 4 && !STOPWORDS.has(w) && /^[a-z]+$/.test(w))
}

/**
 * Parse a comma-separated tags string into an array of trimmed,
 * lowercase tokens.  Returns [] for undefined/empty.
 */
function parseTags(tags: string | undefined): string[] {
  if (!tags || tags.trim().length === 0) return []
  return tags
    .split(',')
    .map((t) => t.trim().toLowerCase())
    .filter((t) => t.length >= 2)
}

/**
 * Parse sealedReleaseIds comma-separated string into array of cellId strings.
 */
function parseSealedIds(raw: string): string[] {
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0)
}

/** Compute ISO date string from epoch ms, or today if undefined. */
function toIsoDate(epochMs: number | undefined): string {
  const ts = epochMs ?? Date.now()
  return new Date(ts).toISOString().slice(0, 10)
}

/**
 * Determine the suggested next state for a theme based on its
 * pattern cells and polarity.
 */
function suggestedStateForTheme(
  concept: string,
  patternCells: readonly PatternCellInput[],
): SuggestedNextState {
  // Check if any pattern cell mentions this concept
  const relatedPattern = patternCells.find(
    (p) => p.payload.description.toLowerCase().includes(concept),
  )
  if (!relatedPattern) return 'RELEASE'

  switch (relatedPattern.payload.polarity) {
    case 'limiting':
      // Limiting patterns with high occurrence benefit from vacuum clearing
      return (relatedPattern.payload.occurrenceCount ?? 1) >= 3 ? 'VACUUM' : 'RELEASE'
    case 'supportive':
      return 'INSIGHT_CAPTURE'
    default:
      return 'RELEASE'
  }
}

// ─── Concept accumulation ──────────────────────────────────────────────────────

interface ConceptAccum {
  totalCount: number
  sealedCount: number
  lastSeenMs: number
  cellIds: string[]
  // Trajectory buckets (only populated when windowSplitMs is supplied).
  priorCount: number
  priorSealed: number
  currentCount: number
  currentSealed: number
}

/**
 * Compute the day-over-day trend for one concept given its accumulated
 * prior/current buckets and the full-window max count (for normalization).
 */
function computeTrend(accum: ConceptAccum, maxCount: number): ThemeTrend {
  const priorWeight = maxCount > 0 ? accum.priorCount / maxCount : 0
  const currentWeight = maxCount > 0 ? accum.currentCount / maxCount : 0
  const priorStability = accum.priorCount > 0 ? accum.priorSealed / accum.priorCount : 0
  const currentStability = accum.currentCount > 0 ? accum.currentSealed / accum.currentCount : 0
  const weightDelta = currentWeight - priorWeight
  const stabilityDelta = currentStability - priorStability

  let direction: TrendDirection
  if (accum.priorCount === 0) {
    direction = 'new'
  } else if (stabilityDelta > TREND_EPSILON) {
    direction = 'settling'
  } else if (weightDelta > TREND_EPSILON) {
    direction = 'escalating'
  } else {
    direction = 'steady'
  }

  return { priorWeight, priorStability, weightDelta, stabilityDelta, direction }
}

// ─── Main sweep function ──────────────────────────────────────────────────────

/**
 * Sweep recent practice history to produce a ranked list of primed
 * themes for the SCAN state.
 *
 * Algorithm:
 *  1. Collect all sealed release cell IDs (they are resolved).
 *  2. For each release cell, extract themes from explicit tags (preferred)
 *     or rawText keywords (fallback).
 *  3. Accumulate occurrence counts per concept.  Track whether each
 *     contributing release has been sealed.  When a window split is given,
 *     also bucket each occurrence into prior vs current.
 *  4. Compute stability = sealed_occurrences / total.
 *  5. Filter out stable themes (≥ 0.85) — they are no longer load-bearing.
 *  6. Normalize weight, attach trend (if split given), order by stability
 *     ascending, return top 7.
 */
export function sweepPracticeHistory(input: PaskSweepInput): PaskSweepResult {
  const {
    recentReleaseCells,
    recentInsightCells,
    recentPatternCells,
    recentSealCells,
    recentSessionCells,
    windowSplitMs,
  } = input

  // ── Build set of sealed release cell IDs ──────────────────────────
  const sealedReleaseIds = new Set<string>()
  for (const seal of recentSealCells) {
    for (const id of parseSealedIds(seal.payload.sealedReleaseIds)) {
      sealedReleaseIds.add(id)
    }
  }

  // ── Accumulate per-concept data ───────────────────────────────────
  const concepts = new Map<string, ConceptAccum>()

  function touch(concept: string, cellId: string, mintedAt: number | undefined, sealed: boolean) {
    const ts = mintedAt ?? Date.now()
    // Bucket into prior/current only when a split is supplied.
    const isCurrent = windowSplitMs !== undefined ? ts >= windowSplitMs : false
    let existing = concepts.get(concept)
    if (!existing) {
      existing = {
        totalCount: 0,
        sealedCount: 0,
        lastSeenMs: ts,
        cellIds: [],
        priorCount: 0,
        priorSealed: 0,
        currentCount: 0,
        currentSealed: 0,
      }
      concepts.set(concept, existing)
    }
    existing.totalCount += 1
    if (sealed) existing.sealedCount += 1
    if (ts > existing.lastSeenMs) existing.lastSeenMs = ts
    existing.cellIds.push(cellId)
    if (windowSplitMs !== undefined) {
      if (isCurrent) {
        existing.currentCount += 1
        if (sealed) existing.currentSealed += 1
      } else {
        existing.priorCount += 1
        if (sealed) existing.priorSealed += 1
      }
    }
  }

  // Process release cells
  for (const release of recentReleaseCells) {
    const isSealed = sealedReleaseIds.has(release.cellId)

    // Prefer explicit tags; fall back to keyword extraction
    const tags = parseTags(release.payload.themes)
    const terms = tags.length > 0 ? tags : extractKeywords(release.payload.rawText).slice(0, 5)

    for (const term of terms) {
      touch(term, release.cellId, release.mintedAt, isSealed)
    }
  }

  // Process insight cells (not sealed, add weight as unresolved signal)
  for (const insight of recentInsightCells) {
    const terms = [
      ...parseTags(insight.payload.dimensions),
      ...parseTags(insight.payload.tags),
      ...extractKeywords(insight.payload.content).slice(0, 3),
    ]
    for (const term of terms) {
      touch(term, insight.cellId, insight.mintedAt, false)
    }
  }

  // Process pattern cells (recurring patterns are most load-bearing)
  for (const pattern of recentPatternCells) {
    const terms = extractKeywords(pattern.payload.description).slice(0, 4)
    const isResolved = (pattern.payload.strength ?? 0) <= 0.1
    for (const term of terms) {
      touch(term, pattern.cellId, pattern.mintedAt, isResolved)
    }
  }

  if (concepts.size === 0) {
    return {
      primedThemes: [],
      overallElevationEstimate: _rollingElevation(recentSessionCells),
      fieldIsClear: true,
      sweepTimestamp: Date.now(),
    }
  }

  // ── Compute stability + weight, filter resolved ──────────────────
  const maxCount = Math.max(...Array.from(concepts.values()).map((c) => c.totalCount))

  const themes: PrimedTheme[] = []
  for (const [concept, accum] of concepts.entries()) {
    const stability = accum.totalCount > 0 ? accum.sealedCount / accum.totalCount : 0
    if (stability >= 0.85) continue // fully resolved — prunable by pask kernel

    const weight = maxCount > 0 ? accum.totalCount / maxCount : 0
    themes.push({
      concept,
      weight,
      stability,
      lastSeen: toIsoDate(accum.lastSeenMs),
      cellIds: accum.cellIds,
      suggestedState: suggestedStateForTheme(concept, recentPatternCells),
      ...(windowSplitMs !== undefined ? { trend: computeTrend(accum, maxCount) } : {}),
    })
  }

  // Order by stability ascending (least stable = most needing attention)
  themes.sort((a, b) => a.stability - b.stability || b.weight - a.weight)

  const top7 = themes.slice(0, 7)

  return {
    primedThemes: top7,
    overallElevationEstimate: _rollingElevation(recentSessionCells),
    fieldIsClear: top7.length === 0,
    sweepTimestamp: Date.now(),
  }
}

/** Rolling 7-day elevation average from session cells. */
function _rollingElevation(sessions: readonly SessionCellInput[]): number {
  if (sessions.length === 0) return 5

  const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000
  const recent = sessions.filter((s) => (s.mintedAt ?? 0) >= cutoff)
  if (recent.length === 0) return sessions.at(-1)?.payload.elevation ?? 5

  const avg = recent.reduce((sum, s) => sum + s.payload.elevation, 0) / recent.length
  return Math.round(avg * 10) / 10
}

```
