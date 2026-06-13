---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/AttentionWeightLearner.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.097342+00:00
---

# runtime/services/src/services/AttentionWeightLearner.ts

```ts
/**
 * AttentionWeightLearner — AS2 of the AS workstream.
 *
 * Per-operator (and per-context) weights drift toward the operator's
 * demonstrated preferences. The five base weights from Phase 39A stop
 * being constants; they become live cells.
 *
 * Update rule (AS2 §2):
 *   - acted-on / pinned:              dominant factor +1.0% (completion signal; 2× base)
 *   - tapped / opened / push-opened:  dominant factor +0.3% (engagement signal; 0.6× base)
 *   - dismiss / ignore / suppressed:  dominant factor -0.5% (capped at -20% under base)
 *   - re-normalise so factors sum to 1.0; floor at 0.05
 *   - per-class multipliers tracked separately (AS2 §3)
 *   - profile-aware: field / desk / night, selected at scoring time
 *   - cold start: first 100 interactions accumulate before any drift
 */
import { TypedEventEmitter } from './TypedEventEmitter';
import type { AttentionInteraction, AttentionInteractionRecord, AttentionContextTag } from './AttentionTelemetry';
import type { AttentionReason } from '../types/loom';

export type AttentionFactor =
  | 'recency'
  | 'deadline'
  | 'active_work'
  | 'goal_alignment'
  | 'pending_action'
  | 'external_signal'
  | 'graph_proximity';

export interface AttentionWeights {
  recency: number;
  deadline: number;
  active_work: number;
  goal_alignment: number;
  pending_action: number;
  external_signal: number;
  /** DB5: proximity in the Pask constraint graph to the active context cell. */
  graph_proximity: number;
}

export interface AttentionWeightProfile {
  /** field / desk / night — or `default` for cold-start. */
  readonly profile: AttentionContextTag | 'default';
  weights: AttentionWeights;
  /** Per-class multipliers, keyed by type-path glob. */
  classMultipliers: Record<string, number>;
  /** Counter — required before drift kicks in. */
  warmupInteractions: number;
}

export const BASELINE_WEIGHTS: AttentionWeights = {
  recency: 0.30,
  deadline: 0.25,
  active_work: 0.20,
  goal_alignment: 0.05, // stub (EmbeddingService deferred); freed 0.10 for graph_proximity
  pending_action: 0.10,
  external_signal: 0.00,
  graph_proximity: 0.10,
};

const DRIFT_STEP_COMPLETION = 0.010; // acted-on, pinned — completed something
const DRIFT_STEP_ENGAGEMENT = 0.003; // tapped, opened — glanced at it
const DRIFT_STEP_NEGATIVE   = 0.005;
const DRIFT_CAP = 0.20;
const WEIGHT_FLOOR = 0.05;
const COLD_START_INTERACTIONS = 100;
const COMPLETION_KINDS: AttentionInteraction['kind'][] = ['acted-on', 'pinned'];
const ENGAGEMENT_KINDS: AttentionInteraction['kind'][] = ['tapped', 'opened', 'push-opened'];
const NEGATIVE_KINDS: AttentionInteraction['kind'][] = ['dismissed', 'ignored', 'suppressed', 'push-dismissed'];

type LearnerEvents = {
  weights: [{ profile: AttentionContextTag | 'default'; weights: AttentionWeights }];
};

export interface AttentionWeightSnapshot {
  takenAt: number;
  profiles: Record<AttentionContextTag | 'default', AttentionWeightProfile>;
}

export class AttentionWeightLearner extends TypedEventEmitter<LearnerEvents> {
  private profiles: Record<AttentionContextTag | 'default', AttentionWeightProfile>;
  private history: AttentionWeightSnapshot[] = [];
  private persistFn: ((snap: AttentionWeightSnapshot) => Promise<void>) | null = null;
  private interactionCount = 0;
  /** 30-day surface impression count by profile, for `attention status`. */
  private impressionStats = {
    impressions: 0,
    interactions: 0,
  };

  constructor() {
    super();
    this.profiles = {
      default: this.makeProfile('default'),
      field: this.makeProfile('field'),
      desk: this.makeProfile('desk'),
      night: this.makeProfile('night'),
    };
    this.applyContextPriors();
  }

  setPersistFn(fn: (snap: AttentionWeightSnapshot) => Promise<void>): void {
    this.persistFn = fn;
  }

  /**
   * Pick the profile to score against. The host calls this with the
   * inferred current context (mobile + GPS = field, desktop = desk,
   * out-of-hours = night).
   */
  selectProfile(context: AttentionContextTag | null): AttentionContextTag | 'default' {
    if (context && this.profiles[context]) return context;
    return 'default';
  }

  /** Get the active weights for a profile. */
  getWeights(profile: AttentionContextTag | 'default' = 'default'): AttentionWeights {
    return { ...this.profiles[profile].weights };
  }

  /** Get the active class multipliers for a profile. */
  getClassMultipliers(profile: AttentionContextTag | 'default' = 'default'): Record<string, number> {
    return { ...this.profiles[profile].classMultipliers };
  }

  /** Note an impression — used for the `attention status` denominator. */
  noteImpression(): void {
    this.impressionStats.impressions += 1;
  }

  /** Note an interaction — used for the `attention status` numerator. */
  noteInteractionForStats(): void {
    this.impressionStats.interactions += 1;
  }

  getImpressionStats(): { impressions: number; interactions: number; rate: number } {
    const { impressions, interactions } = this.impressionStats;
    return {
      impressions,
      interactions,
      rate: impressions > 0 ? interactions / impressions : 0,
    };
  }

  /**
   * Consume one telemetry record and update the matching profile's weights.
   * The dominant factor (the highest-weighted reason on the surfaced item)
   * gets the drift; the rest re-normalise.
   */
  observe(record: AttentionInteractionRecord, dominantFactor: AttentionFactor | null): void {
    this.interactionCount += 1;
    if (this.interactionCount < COLD_START_INTERACTIONS) {
      return; // accumulate, don't drift
    }
    const profile = this.profiles[record.context ?? 'default'];
    if (!profile || !dominantFactor) return;
    profile.warmupInteractions += 1;

    let sign: number;
    let driftStep: number;
    if (COMPLETION_KINDS.includes(record.interaction.kind)) {
      sign = +1; driftStep = DRIFT_STEP_COMPLETION;
    } else if (ENGAGEMENT_KINDS.includes(record.interaction.kind)) {
      sign = +1; driftStep = DRIFT_STEP_ENGAGEMENT;
    } else if (NEGATIVE_KINDS.includes(record.interaction.kind)) {
      sign = -1; driftStep = DRIFT_STEP_NEGATIVE;
    } else {
      return;
    }

    const baseline = BASELINE_WEIGHTS[dominantFactor];
    const current = profile.weights[dominantFactor];
    const proposed = current + sign * driftStep;
    // Clamp to ±20% of baseline.
    const clamped = Math.max(
      Math.max(WEIGHT_FLOOR, baseline * (1 - DRIFT_CAP)),
      Math.min(baseline * (1 + DRIFT_CAP), proposed),
    );
    if (clamped === current) return;

    profile.weights[dominantFactor] = clamped;
    this.renormalise(profile.weights);
    this.emit('weights', { profile: profile.profile, weights: profile.weights });
  }

  /** Daily batch: scan recent telemetry, update class multipliers. */
  batchUpdate(records: AttentionInteractionRecord[], itemTypePathOf: (itemId: string) => string | null): void {
    if (records.length === 0) return;

    // Per-class interaction-rate. Class is the typeDefinition.name (or any
    // hierarchical path). Auto-boost when interaction-rate > mean * 1.2;
    // auto-suppress when < mean * 0.8.
    const perClass = new Map<string, { positive: number; negative: number }>();
    for (const rec of records) {
      const itemId = (rec.interaction as { itemId?: string }).itemId;
      if (!itemId) continue;
      const path = itemTypePathOf(itemId);
      if (!path) continue;
      let bucket = perClass.get(path);
      if (!bucket) {
        bucket = { positive: 0, negative: 0 };
        perClass.set(path, bucket);
      }
      if (COMPLETION_KINDS.includes(rec.interaction.kind) || ENGAGEMENT_KINDS.includes(rec.interaction.kind)) bucket.positive += 1;
      else if (NEGATIVE_KINDS.includes(rec.interaction.kind)) bucket.negative += 1;
    }

    const rates: number[] = [];
    for (const [, b] of perClass) {
      const total = b.positive + b.negative;
      if (total > 0) rates.push(b.positive / total);
    }
    if (rates.length === 0) return;
    const mean = rates.reduce((a, b) => a + b, 0) / rates.length;

    const profile = this.profiles.default;
    for (const [path, b] of perClass) {
      const total = b.positive + b.negative;
      if (total < 5) continue; // not enough signal
      const rate = b.positive / total;
      if (rate > mean * 1.2) {
        profile.classMultipliers[path] = Math.min(2.0, (profile.classMultipliers[path] ?? 1.0) * 1.05);
      } else if (rate < mean * 0.8) {
        profile.classMultipliers[path] = Math.max(0.1, (profile.classMultipliers[path] ?? 1.0) * 0.95);
      }
    }

    void this.snapshotAndPersist();
  }

  /** Roll back to a snapshot taken at-or-before the given iso date. */
  rollbackTo(isoDate: string): boolean {
    const target = new Date(isoDate).getTime();
    const candidate = [...this.history].reverse().find(h => h.takenAt <= target);
    if (!candidate) return false;
    this.profiles = JSON.parse(JSON.stringify(candidate.profiles));
    return true;
  }

  /**
   * Map an attention reason to its underlying factor — used by callers
   * before invoking `observe()`.
   */
  static reasonToFactor(reason: AttentionReason): AttentionFactor | null {
    switch (reason.type) {
      case 'active_work': return 'active_work';
      case 'deadline_approaching': return 'deadline';
      case 'goal_misalignment': return 'goal_alignment';
      case 'pending_action': return 'pending_action';
      case 'new_update': return 'recency';
      case 'streak_continuation': return 'recency';
      case 'scheduled': return 'deadline';
      case 'extension_signal': return 'external_signal';
      case 'graph_proximity': return 'graph_proximity';
    }
  }

  private async snapshotAndPersist(): Promise<void> {
    const snap: AttentionWeightSnapshot = {
      takenAt: Date.now(),
      profiles: JSON.parse(JSON.stringify(this.profiles)),
    };
    this.history.push(snap);
    if (this.persistFn) {
      try { await this.persistFn(snap); } catch {/* non-fatal */ }
    }
  }

  private makeProfile(profile: AttentionContextTag | 'default'): AttentionWeightProfile {
    return {
      profile,
      weights: { ...BASELINE_WEIGHTS },
      classMultipliers: {},
      warmupInteractions: 0,
    };
  }

  /**
   * Apply per-context priors so the profiles aren't identical out of the
   * box. Field up-weights deadline + active_work; night down-weights
   * everything but pending-action critical alerts.
   */
  private applyContextPriors(): void {
    const field = this.profiles.field.weights;
    field.deadline = 0.30;
    field.active_work = 0.25;
    field.goal_alignment = 0.10;
    field.recency = 0.25;
    field.pending_action = 0.10;
    this.renormalise(field);

    const night = this.profiles.night.weights;
    night.recency = 0.10;
    night.deadline = 0.20;
    night.active_work = 0.10;
    night.goal_alignment = 0.10;
    night.pending_action = 0.50;
    this.renormalise(night);
  }

  private renormalise(weights: AttentionWeights): void {
    // Floor first.
    for (const k of Object.keys(weights) as AttentionFactor[]) {
      if (weights[k] < WEIGHT_FLOOR) weights[k] = WEIGHT_FLOOR;
    }
    const sum = Object.values(weights).reduce((a, b) => a + b, 0);
    if (sum === 0) return;
    for (const k of Object.keys(weights) as AttentionFactor[]) {
      weights[k] = weights[k] / sum;
    }
  }
}

export const attentionWeightLearner = new AttentionWeightLearner();

```
