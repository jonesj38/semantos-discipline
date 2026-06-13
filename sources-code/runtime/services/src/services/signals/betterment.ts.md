---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/signals/betterment.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.112143+00:00
---

# runtime/services/src/services/signals/betterment.ts

```ts
/**
 * Self signal source — T7.c.
 *
 * Emits AttentionSignals for betterment.* cell-shapes that don't surface
 * naturally from LoomObject properties alone (the AttentionEngine's
 * built-in factors).  Four shapes:
 *
 *   1. Morning intention not set today by 9am  → `pending_action`
 *   2. Daily review not done today by 9pm      → `pending_action`
 *   3. Accountability streak about to break    → `streak_continuation`
 *   4. Pattern strength threshold crossed      → `extension_signal`
 *
 * Reuses existing `AttentionReason` discriminated-union variants — no
 * new enum entries needed (per T7.c scoping; the existing reasons cover
 * all four shapes once Provider state is wired).
 *
 * Pattern mirrors `signals/capability.ts` — defines a Provider interface
 * the runtime supplies (brain queries / in-app state cache) plus a
 * factory that polls + subscribes.
 */

import type { AttentionSignalSource, AttentionSignal } from '../AttentionSignals';
import type { LoomObject } from '../../types/loom';

// ── Provider interfaces ─────────────────────────────────────────────────

export interface MorningIntentionState {
  /** UTC midnight of the day this intention covers (number — Date.UTC(y,m,d)). */
  readonly day: number;
  /** True when MorningIntention cell has been minted for this day. */
  readonly set: boolean;
  /** Object id to attach the signal to (the user's primary self-page). */
  readonly attachToObjectId?: string;
  readonly synthesizesObject?: LoomObject;
}

export interface DailyReviewState {
  readonly day: number;
  readonly done: boolean;
  readonly attachToObjectId?: string;
  readonly synthesizesObject?: LoomObject;
}

export interface AccountabilityStreakState {
  readonly streakType: string;
  readonly currentStreak: number;
  /** UTC timestamp of last completion. */
  readonly lastCompletedAt: number;
  /** UTC timestamp by which next completion is needed to preserve the streak. */
  readonly breaksAtMs: number;
  readonly attachToObjectId?: string;
  readonly synthesizesObject?: LoomObject;
}

export interface PatternThresholdState {
  readonly patternId: string;
  readonly patternDescription: string;
  readonly strength: number;
  /** Threshold the strength just crossed (e.g. 0.5, 0.75). */
  readonly thresholdCrossed: number;
  readonly attachToObjectId?: string;
  readonly synthesizesObject?: LoomObject;
}

export interface SelfProvider {
  /** Current morning-intention state per tracked day (typically just today). */
  listMorningIntentions(): MorningIntentionState[];
  /** Current daily-review state per tracked day. */
  listDailyReviews(): DailyReviewState[];
  /** Current accountability streaks (multiple — one per streakType). */
  listStreaks(): AccountabilityStreakState[];
  /** Recently-crossed pattern thresholds (transient — typically TTL'd). */
  listPatternThresholds(): PatternThresholdState[];
  /** Optional push subscription for state changes. */
  subscribe?(emit: (kind: SelfSignalKind) => void): () => void;
}

export type SelfSignalKind =
  | { type: 'morning-intention'; state: MorningIntentionState }
  | { type: 'daily-review'; state: DailyReviewState }
  | { type: 'streak'; state: AccountabilityStreakState }
  | { type: 'pattern-threshold'; state: PatternThresholdState };

// ── Source factory ──────────────────────────────────────────────────────

export interface SelfSourceOptions {
  provider: SelfProvider;
  /** Hour-of-day (local) when morning intention should be set by.
   *  Default 9 — signal fires after 09:00 local if not set. */
  morningIntentionByHour?: number;
  /** Hour-of-day (local) when daily review should be done by.
   *  Default 21 — signal fires after 21:00 local if not done. */
  dailyReviewByHour?: number;
  /** Streak fires at urgency `soon` when within this lead time of breaking. */
  streakLeadTimeMs?: number;
}

export function createSelfSource(opts: SelfSourceOptions): AttentionSignalSource {
  const morningHour = opts.morningIntentionByHour ?? 9;
  const reviewHour = opts.dailyReviewByHour ?? 21;
  const streakLeadMs = opts.streakLeadTimeMs ?? 6 * 60 * 60 * 1000; // 6h

  return {
    id: 'betterment',
    displayName: 'Self practice',

    async poll(now: number): Promise<AttentionSignal[]> {
      const out: AttentionSignal[] = [];
      for (const s of opts.provider.listMorningIntentions()) {
        const sig = morningIntentionSignal(s, now, morningHour);
        if (sig) out.push(sig);
      }
      for (const s of opts.provider.listDailyReviews()) {
        const sig = dailyReviewSignal(s, now, reviewHour);
        if (sig) out.push(sig);
      }
      for (const s of opts.provider.listStreaks()) {
        const sig = streakSignal(s, now, streakLeadMs);
        if (sig) out.push(sig);
      }
      for (const s of opts.provider.listPatternThresholds()) {
        out.push(patternThresholdSignal(s, now));
      }
      return out;
    },

    subscribe(emit) {
      if (!opts.provider.subscribe) return () => {};
      return opts.provider.subscribe((kind) => {
        const now = Date.now();
        let sig: AttentionSignal | null = null;
        switch (kind.type) {
          case 'morning-intention':
            sig = morningIntentionSignal(kind.state, now, morningHour);
            break;
          case 'daily-review':
            sig = dailyReviewSignal(kind.state, now, reviewHour);
            break;
          case 'streak':
            sig = streakSignal(kind.state, now, streakLeadMs);
            break;
          case 'pattern-threshold':
            sig = patternThresholdSignal(kind.state, now);
            break;
        }
        if (sig) emit(sig);
      });
    },
  };
}

// ── Per-shape mappers ──────────────────────────────────────────────────

function morningIntentionSignal(
  state: MorningIntentionState,
  now: number,
  byHour: number,
): AttentionSignal | null {
  if (state.set) return null;
  // Only fire after the by-hour cutoff in local time.
  const dayStart = new Date(state.day);
  const cutoff = new Date(dayStart.getFullYear(), dayStart.getMonth(), dayStart.getDate(), byHour);
  if (now < cutoff.getTime()) return null;
  return {
    sourceId: 'betterment',
    attachToObjectId: state.attachToObjectId,
    synthesizesObject: state.synthesizesObject,
    factor: {
      type: 'pending_action',
      action: 'betterment.accountability.morning',
      awaitingSince: cutoff.getTime(),
    },
    score: scoreFromAge(now - cutoff.getTime(), 2 * 60 * 60 * 1000), // saturate after 2h
    expiresAt: cutoff.getTime() + 24 * 60 * 60 * 1000,
  };
}

function dailyReviewSignal(
  state: DailyReviewState,
  now: number,
  byHour: number,
): AttentionSignal | null {
  if (state.done) return null;
  const dayStart = new Date(state.day);
  const cutoff = new Date(dayStart.getFullYear(), dayStart.getMonth(), dayStart.getDate(), byHour);
  if (now < cutoff.getTime()) return null;
  return {
    sourceId: 'betterment',
    attachToObjectId: state.attachToObjectId,
    synthesizesObject: state.synthesizesObject,
    factor: {
      type: 'pending_action',
      action: 'betterment.accountability.review',
      awaitingSince: cutoff.getTime(),
    },
    score: scoreFromAge(now - cutoff.getTime(), 2 * 60 * 60 * 1000),
    expiresAt: cutoff.getTime() + 6 * 60 * 60 * 1000, // expires at 3am next day
  };
}

function streakSignal(
  state: AccountabilityStreakState,
  now: number,
  leadMs: number,
): AttentionSignal | null {
  const remaining = state.breaksAtMs - now;
  if (remaining <= 0) return null;          // already broken — different signal kind
  if (remaining > leadMs) return null;       // not yet in lead window
  return {
    sourceId: 'betterment',
    attachToObjectId: state.attachToObjectId,
    synthesizesObject: state.synthesizesObject,
    factor: {
      type: 'streak_continuation',
      streakDays: state.currentStreak,
    },
    // Closer to break → higher urgency
    score: 1 - (remaining / leadMs),
    expiresAt: state.breaksAtMs,
  };
}

function patternThresholdSignal(
  state: PatternThresholdState,
  now: number,
): AttentionSignal {
  return {
    sourceId: 'betterment',
    attachToObjectId: state.attachToObjectId,
    synthesizesObject: state.synthesizesObject,
    factor: {
      type: 'extension_signal',
      extensionId: 'betterment',
      signal: `Pattern '${state.patternDescription}' crossed strength ${state.thresholdCrossed.toFixed(2)} (now ${state.strength.toFixed(2)})`,
    },
    score: Math.min(1, state.strength),
    expiresAt: now + 24 * 60 * 60 * 1000,
  };
}

/** Map an "age past deadline" duration to a 0..1 urgency score. */
function scoreFromAge(ageMs: number, saturationMs: number): number {
  if (ageMs <= 0) return 0;
  return Math.min(1, ageMs / saturationMs);
}

```
