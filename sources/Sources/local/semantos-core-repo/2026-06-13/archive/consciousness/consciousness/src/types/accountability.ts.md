---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/consciousness/consciousness/src/types/accountability.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.722726+00:00
---

# archive/consciousness/consciousness/src/types/accountability.ts

```ts
/**
 * Accountability Layer: Daily rituals, dimension tracking, and Paskian integration.
 *
 * The accountability system creates structured interactions that feed the
 * Paskian constraint graph. Each check-in, review, and intention is an
 * interaction that propagates through the graph, revealing which dimensions
 * support each other and which habits are stabilizing for THIS person.
 *
 * @module @semantos/consciousness/accountability
 */

import {
  SemanticType,
  type LinearObject,
  type AffineObject,
  type RelevantObject,
  type ConsumptionProof,
  type RevocationProof,
} from '@semantos/core';

import { LifeDimension } from './consciousness-objects.js';

// ─── Evening Review (LINEAR — done once per day, consumed) ─────────

/**
 * DailyReview: The evening accountability ritual.
 * LINEAR — one review per day, consumed when complete.
 */
export interface DailyReview extends LinearObject<ConsumptionProof> {
  semanticType: SemanticType.LINEAR;
  date: string;
  wins: ReviewItem[];
  improvements: ReviewItem[];
  tomorrowIntention: string;
  tomorrowDimensionFocus: LifeDimension;
  tomorrowGoal: string;
  energyLevel: number;
  moodLevel: number;
  gratitude?: string;
  paskianInteractionIds: string[];
}

/** A single win or improvement item in the daily review. */
export interface ReviewItem {
  content: string;
  dimension: LifeDimension;
  significance: number;
}

// ─── Morning Intention (LINEAR — consumed when the day begins) ─────

/**
 * MorningIntention: The morning check-in ritual.
 * LINEAR — one per morning, consumed when you begin the day.
 */
export interface MorningIntention extends LinearObject<ConsumptionProof> {
  semanticType: SemanticType.LINEAR;
  date: string;
  yesterdayReview: 'fulfilled' | 'partial' | 'missed' | 'transformed';
  yesterdayReflection?: string;
  todayIntention: string;
  primaryDimension: LifeDimension;
  secondaryDimension?: LifeDimension;
  concreteAction: string;
  successCriteria: string;
  paskianInteractionIds: string[];
}

// ─── Dimension Pulse (AFFINE — acknowledge or skip) ────────────────

/**
 * DimensionPulse: A quick mid-day check-in on a single dimension.
 * AFFINE — you can acknowledge it (checked in) or discard (skipped).
 */
export interface DimensionPulse extends AffineObject<{ pulseTime: number }> {
  semanticType: SemanticType.AFFINE;
  dimension: LifeDimension;
  date: string;
  score: number;
  note?: string;
  trend: 'up' | 'down' | 'steady' | 'first';
  paskianInteractionId?: string;
}

// ─── Streak / Consistency (RELEVANT — accumulates) ─────────────────

/**
 * AccountabilityStreak: Tracks consistency across the accountability rituals.
 * RELEVANT — persists and grows.
 */
export interface AccountabilityStreak extends RelevantObject<RevocationProof> {
  semanticType: SemanticType.RELEVANT;
  streakType: 'evening-review' | 'morning-intention' | 'dimension-pulse' | 'release-writing';
  currentStreak: number;
  longestStreak: number;
  totalCompletions: number;
  streakHistory: Array<{
    startDate: string;
    endDate: string;
    length: number;
  }>;
  lastCompletedDate: string;
}

// ─── Paskian Integration Types ─────────────────────────────────────

export interface AccountabilityInteraction {
  source: 'daily-review-win' | 'daily-review-improvement' | 'morning-fulfilled'
    | 'morning-missed' | 'dimension-pulse' | 'dimension-skip'
    | 'release-completed' | 'intention-acknowledged' | 'intention-discarded';
  dimension: LifeDimension;
  strength: number;
  relatedDimensions: LifeDimension[];
  metadata: Record<string, unknown>;
}

export const ACCOUNTABILITY_STRENGTHS: Record<AccountabilityInteraction['source'], number> = {
  'daily-review-win': 1.0,
  'daily-review-improvement': -0.3,
  'morning-fulfilled': 1.2,
  'morning-missed': -0.5,
  'dimension-pulse': 0.5,
  'dimension-skip': -0.1,
  'release-completed': 0.8,
  'intention-acknowledged': 1.0,
  'intention-discarded': -0.2,
};

export function toAccountabilityInteraction(
  source: AccountabilityInteraction['source'],
  dimension: LifeDimension,
  relatedDimensions: LifeDimension[] = [],
  overrideStrength?: number,
  metadata: Record<string, unknown> = {},
): AccountabilityInteraction {
  return {
    source,
    dimension,
    strength: overrideStrength ?? ACCOUNTABILITY_STRENGTHS[source],
    relatedDimensions,
    metadata: {
      ...metadata,
      timestamp: Date.now(),
      source,
    },
  };
}

export function reviewToInteractions(review: DailyReview): AccountabilityInteraction[] {
  const interactions: AccountabilityInteraction[] = [];

  for (const win of review.wins) {
    interactions.push(toAccountabilityInteraction(
      'daily-review-win',
      win.dimension,
      review.wins.filter(w => w !== win).map(w => w.dimension),
      win.significance * 0.3,
      { content: win.content },
    ));
  }

  for (const imp of review.improvements) {
    interactions.push(toAccountabilityInteraction(
      'daily-review-improvement',
      imp.dimension,
      [],
      -0.1 * imp.significance,
      { content: imp.content },
    ));
  }

  return interactions;
}

export function morningToInteractions(morning: MorningIntention): AccountabilityInteraction[] {
  const interactions: AccountabilityInteraction[] = [];

  const yesterdayStrength =
    morning.yesterdayReview === 'fulfilled' ? 1.2
    : morning.yesterdayReview === 'partial' ? 0.4
    : morning.yesterdayReview === 'transformed' ? 0.8
    : -0.5;

  interactions.push(toAccountabilityInteraction(
    morning.yesterdayReview === 'missed' ? 'morning-missed' : 'morning-fulfilled',
    morning.primaryDimension,
    morning.secondaryDimension ? [morning.secondaryDimension] : [],
    yesterdayStrength,
    { intention: morning.todayIntention },
  ));

  return interactions;
}

export function pulseToInteraction(pulse: DimensionPulse): AccountabilityInteraction {
  const normalizedStrength = (pulse.score - 5) / 5;

  return toAccountabilityInteraction(
    pulse.acknowledged ? 'dimension-pulse' : 'dimension-skip',
    pulse.dimension,
    [],
    pulse.acknowledged ? 0.3 + normalizedStrength * 0.5 : -0.1,
    { score: pulse.score, note: pulse.note },
  );
}

export const DEFAULT_SCHEDULE = {
  morningIntention: { hour: 7, minute: 0, cron: '0 7 * * *' },
  middayPulse: { hour: 12, minute: 30, cron: '30 12 * * *' },
  afternoonPulse: { hour: 16, minute: 0, cron: '0 16 * * *' },
  eveningReview: { hour: 21, minute: 0, cron: '0 21 * * *' },
} as const;

```
