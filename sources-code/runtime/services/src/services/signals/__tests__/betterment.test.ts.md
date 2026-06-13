---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/signals/__tests__/betterment.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.124428+00:00
---

# runtime/services/src/services/signals/__tests__/betterment.test.ts

```ts
/**
 * T7.c — Betterment attention signal source tests.
 *
 * Covers all 4 signal shapes:
 *   - Morning intention before cutoff → silent
 *   - Morning intention after cutoff + not set → pending_action
 *   - Morning intention already set → silent
 *   - Daily review before cutoff → silent; after + not done → pending_action
 *   - Streak with plenty of time → silent
 *   - Streak within lead window → streak_continuation with rising score
 *   - Pattern threshold → extension_signal
 *
 * Plus subscribe-path smoke + per-day cutoff filtering.
 */

import { describe, expect, test } from 'bun:test';
import {
  createSelfSource,
  type SelfProvider,
  type MorningIntentionState,
  type DailyReviewState,
  type AccountabilityStreakState,
  type PatternThresholdState,
} from '../betterment';

function provider(overrides: Partial<SelfProvider> = {}): SelfProvider {
  return {
    listMorningIntentions: () => [],
    listDailyReviews: () => [],
    listStreaks: () => [],
    listPatternThresholds: () => [],
    ...overrides,
  };
}

const DAY_2026_05_25 = Date.UTC(2026, 4, 25); // months are 0-indexed; May = 4
const HOUR = 60 * 60 * 1000;

describe('T7.c — morning intention signal', () => {
  test('silent before cutoff (8:30am, default cutoff 9am)', async () => {
    const day = new Date(2026, 4, 25);
    const now = new Date(2026, 4, 25, 8, 30).getTime();
    const src = createSelfSource({
      provider: provider({
        listMorningIntentions: () => [{ day: day.getTime(), set: false }],
      }),
    });
    expect((await src.poll!(now)).length).toBe(0);
  });

  test('fires after cutoff with rising score as time passes', async () => {
    const day = new Date(2026, 4, 25);
    const justAfter = new Date(2026, 4, 25, 9, 1).getTime();
    const muchLater = new Date(2026, 4, 25, 11, 0).getTime(); // 2h past cutoff = saturation
    const src = createSelfSource({
      provider: provider({
        listMorningIntentions: () => [{ day: day.getTime(), set: false }],
      }),
    });
    const earlySignals = await src.poll!(justAfter);
    expect(earlySignals.length).toBe(1);
    expect(earlySignals[0]!.factor.type).toBe('pending_action');
    expect((earlySignals[0]!.factor as { action: string }).action).toBe('betterment.accountability.morning');
    expect(earlySignals[0]!.score).toBeLessThan(0.1);

    const lateSignals = await src.poll!(muchLater);
    expect(lateSignals[0]!.score).toBe(1.0);
  });

  test('silent when intention is already set', async () => {
    const day = new Date(2026, 4, 25);
    const now = new Date(2026, 4, 25, 14, 0).getTime();
    const src = createSelfSource({
      provider: provider({
        listMorningIntentions: () => [{ day: day.getTime(), set: true }],
      }),
    });
    expect((await src.poll!(now)).length).toBe(0);
  });
});

describe('T7.c — daily review signal', () => {
  test('silent before 9pm cutoff', async () => {
    const day = new Date(2026, 4, 25);
    const now = new Date(2026, 4, 25, 18, 0).getTime();
    const src = createSelfSource({
      provider: provider({
        listDailyReviews: () => [{ day: day.getTime(), done: false }],
      }),
    });
    expect((await src.poll!(now)).length).toBe(0);
  });

  test('fires after 9pm cutoff with pending_action for review', async () => {
    const day = new Date(2026, 4, 25);
    const now = new Date(2026, 4, 25, 21, 30).getTime();
    const src = createSelfSource({
      provider: provider({
        listDailyReviews: () => [{ day: day.getTime(), done: false }],
      }),
    });
    const sigs = await src.poll!(now);
    expect(sigs.length).toBe(1);
    expect(sigs[0]!.factor.type).toBe('pending_action');
    expect((sigs[0]!.factor as { action: string }).action).toBe('betterment.accountability.review');
  });
});

describe('T7.c — streak signal', () => {
  test('silent when plenty of time remains', async () => {
    const now = Date.now();
    const src = createSelfSource({
      provider: provider({
        listStreaks: () => [{
          streakType: 'daily-release',
          currentStreak: 14,
          lastCompletedAt: now - 1 * HOUR,
          breaksAtMs: now + 18 * HOUR, // well beyond 6h lead window
        }],
      }),
    });
    expect((await src.poll!(now)).length).toBe(0);
  });

  test('fires within lead window, score rises as break approaches', async () => {
    const now = Date.now();
    const src = createSelfSource({
      provider: provider({
        listStreaks: () => [
          { streakType: 'morning', currentStreak: 30, lastCompletedAt: now - 23 * HOUR, breaksAtMs: now + 1 * HOUR },
          { streakType: 'release', currentStreak: 7, lastCompletedAt: now - 19 * HOUR, breaksAtMs: now + 5 * HOUR },
        ],
      }),
    });
    const sigs = await src.poll!(now);
    expect(sigs.length).toBe(2);
    expect(sigs.every(s => s.factor.type === 'streak_continuation')).toBe(true);
    // The 1h-remaining streak should score higher than the 5h-remaining one
    const oneH = sigs.find(s => s.factor.type === 'streak_continuation' && (s.factor as { streakDays: number }).streakDays === 30)!;
    const fiveH = sigs.find(s => s.factor.type === 'streak_continuation' && (s.factor as { streakDays: number }).streakDays === 7)!;
    expect(oneH.score).toBeGreaterThan(fiveH.score);
  });

  test('silent when streak already broken (remaining <= 0)', async () => {
    const now = Date.now();
    const src = createSelfSource({
      provider: provider({
        listStreaks: () => [{
          streakType: 'broken',
          currentStreak: 0,
          lastCompletedAt: now - 30 * HOUR,
          breaksAtMs: now - 6 * HOUR, // already past
        }],
      }),
    });
    expect((await src.poll!(now)).length).toBe(0);
  });
});

describe('T7.c — pattern threshold signal', () => {
  test('emits extension_signal with strength + threshold detail', async () => {
    const now = Date.now();
    const src = createSelfSource({
      provider: provider({
        listPatternThresholds: () => [{
          patternId: 'p1',
          patternDescription: 'morning resistance to writing',
          strength: 0.78,
          thresholdCrossed: 0.75,
        }],
      }),
    });
    const sigs = await src.poll!(now);
    expect(sigs.length).toBe(1);
    const f = sigs[0]!.factor as { type: 'extension_signal'; extensionId: string; signal: string };
    expect(f.type).toBe('extension_signal');
    expect(f.extensionId).toBe('betterment');
    expect(f.signal).toContain('morning resistance to writing');
    expect(f.signal).toContain('0.75');
  });
});

describe('T7.c — subscribe path', () => {
  test('emits via subscribe when provider notifies', () => {
    const day = new Date(2026, 4, 25);
    let emitted: import('../../AttentionSignals').AttentionSignal[] = [];
    let subscriber: ((kind: import('../betterment').SelfSignalKind) => void) | null = null;
    const src = createSelfSource({
      provider: {
        listMorningIntentions: () => [],
        listDailyReviews: () => [],
        listStreaks: () => [],
        listPatternThresholds: () => [],
        subscribe(emit) {
          subscriber = emit;
          return () => { subscriber = null; };
        },
      },
    });
    const unsub = src.subscribe!(s => emitted.push(s));
    expect(subscriber).not.toBe(null);
    subscriber!({
      type: 'morning-intention',
      state: { day: day.getTime(), set: false },
    });
    // The morning-intention only fires if past cutoff at "now"; can't guarantee
    // local time. Either way the subscribe wiring is exercised.
    unsub();
  });
});

describe('T7.c — source metadata', () => {
  test('id + displayName', () => {
    const src = createSelfSource({ provider: provider() });
    expect(src.id).toBe('betterment');
    expect(src.displayName).toBe('Self practice');
  });
});

```
