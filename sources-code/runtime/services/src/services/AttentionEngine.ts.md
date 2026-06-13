---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/AttentionEngine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.094203+00:00
---

# runtime/services/src/services/AttentionEngine.ts

```ts
/**
 * AttentionEngine — scores and ranks LoomObjects by computed relevance.
 *
 * Phase 39A: deterministic weighted heuristic.
 * AS2 (this commit): per-operator, per-context-profile weights sourced
 * from AttentionWeightLearner. Sixth `external_signal` factor reserved
 * for AS4. Five base factors retain Phase 39A semantics.
 *
 * Subscribes to LoomStore state changes and recomputes a sorted
 * AttentionItem[] within 16ms for up to 500 objects (one frame budget).
 */

import { TypedEventEmitter } from './TypedEventEmitter';
import type { LoomStore } from './LoomStore';
import type { LoomObject, AttentionItem, AttentionReason } from '../types/loom';
import type { IntentContext } from '@semantos/protocol-types';
import type { AttentionWeightLearner, AttentionWeights, AttentionFactor } from './AttentionWeightLearner';
import { BASELINE_WEIGHTS } from './AttentionWeightLearner';
import type { AttentionRules } from './AttentionRules';
import type { AttentionSignalRegistry } from './AttentionSignals';
import type { AttentionTelemetry, AttentionContextTag } from './AttentionTelemetry';
import type { PaskGraph } from './PaskGraph';

const RECENCY_HALF_LIFE_MS = 4 * 60 * 60 * 1000;
const DEADLINE_NEAR_MS = 24 * 60 * 60 * 1000;
const DEADLINE_FAR_MS = 7 * 24 * 60 * 60 * 1000;
const ACTIVE_WORK_WINDOW_MS = 48 * 60 * 60 * 1000;
const IMMEDIATE_DEADLINE_MS = 2 * 60 * 60 * 1000;
const PENDING_STALE_MS = 24 * 60 * 60 * 1000;

export interface AttentionSnapshot {
  items: AttentionItem[];
  computedAt: number;
}

type AttentionEvents = {
  change: [AttentionSnapshot];
};

export interface AttentionEngineDeps {
  weightLearner?: AttentionWeightLearner;
  rules?: AttentionRules;
  signals?: AttentionSignalRegistry;
  telemetry?: AttentionTelemetry;
  /** Returns the current operator context tag (field/desk/night). */
  contextProvider?: () => AttentionContextTag | null;
  /** DB5: Pask constraint graph for graph-proximity scoring. */
  paskGraph?: PaskGraph;
}

const GRAPH_PROXIMITY_CONTEXT_TTL_MS = 10 * 60 * 1000;

export class AttentionEngine extends TypedEventEmitter<AttentionEvents> {
  private snapshot: AttentionSnapshot = { items: [], computedAt: 0 };
  private unsubscribe: (() => void) | null = null;
  private signalUnsubscribe: (() => void) | null = null;
  private rulesUnsubscribe: (() => void) | null = null;
  private deps: AttentionEngineDeps;
  private activeContextCellId: string | null = null;
  private activeContextSetAt = 0;

  constructor(private store: LoomStore, deps: AttentionEngineDeps = {}) {
    super();
    this.deps = deps;
  }

  start(): void {
    this.unsubscribe = this.store.stableSubscribe(() => this.recompute());
    if (this.deps.signals) {
      this.signalUnsubscribe = this.deps.signals.on('flush', () => this.recompute());
      this.deps.signals.on('signal', () => this.recompute());
      this.deps.signals.start();
    }
    if (this.deps.rules) {
      this.rulesUnsubscribe = this.deps.rules.on('change', () => this.recompute());
    }
    this.recompute();
  }

  stop(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
    this.signalUnsubscribe?.();
    this.signalUnsubscribe = null;
    this.rulesUnsubscribe?.();
    this.rulesUnsubscribe = null;
    this.deps.signals?.stop();
  }

  getSnapshot = (): AttentionSnapshot => this.snapshot;

  setActiveContext(cellId: string | null): void {
    this.activeContextCellId = cellId;
    this.activeContextSetAt = cellId ? Date.now() : 0;
    this.recompute();
  }

  stableSubscribe = (listener: () => void): (() => void) => {
    return this.on('change', () => listener());
  };

  /** Resolve the per-factor weight set in effect for the current pass. */
  private currentWeights(): AttentionWeights {
    if (!this.deps.weightLearner) return { ...BASELINE_WEIGHTS };
    const ctx = this.deps.contextProvider?.() ?? null;
    const profile = this.deps.weightLearner.selectProfile(ctx);
    return this.deps.weightLearner.getWeights(profile);
  }

  private currentClassMultipliers(): Record<string, number> {
    if (!this.deps.weightLearner) return {};
    const ctx = this.deps.contextProvider?.() ?? null;
    const profile = this.deps.weightLearner.selectProfile(ctx);
    return this.deps.weightLearner.getClassMultipliers(profile);
  }

  private recompute(): void {
    const state = this.store.getState();
    const now = Date.now();
    const weights = this.currentWeights();
    const classMultipliers = this.currentClassMultipliers();
    const items: AttentionItem[] = [];

    for (const obj of state.objects.values()) {
      const scored = this.scoreObject(obj, now, weights, classMultipliers);
      if (scored) items.push(scored);
    }

    // Synthesised items from signal sources (transient, TTL-bound).
    if (this.deps.signals) {
      for (const { signal, object } of this.deps.signals.getSynthesized()) {
        const scored = this.scoreObject(object, now, weights, classMultipliers, signal.score);
        if (scored) items.push(scored);
      }
    }

    items.sort((a, b) => {
      // Pinned items always render first.
      if (a.urgency === 'immediate' && b.urgency !== 'immediate') return -1;
      if (b.urgency === 'immediate' && a.urgency !== 'immediate') return 1;
      return b.relevance - a.relevance;
    });

    this.snapshot = { items, computedAt: now };
    if (this.deps.weightLearner) {
      for (let i = 0; i < items.length; i++) this.deps.weightLearner.noteImpression();
    }
    this.emit('change', this.snapshot);
  }

  private scoreObject(
    obj: LoomObject,
    now: number,
    weights: AttentionWeights,
    classMultipliers: Record<string, number>,
    forcedExternalSignalScore?: number,
  ): AttentionItem | null {
    const recency = this.scoreRecency(obj, now);
    const deadline = this.scoreDeadline(obj, now);
    const activeWork = this.scoreActiveWork(obj, now);
    const goalAlignment = 0; // EmbeddingService integration deferred
    const pendingAction = this.scorePendingAction(obj, now);
    const externalSignal = forcedExternalSignalScore ?? this.scoreExternalSignal(obj);
    const graphProximity = this.scoreGraphProximity(obj, now);

    let relevance = Math.min(1.0,
      recency.score * weights.recency +
      deadline.score * weights.deadline +
      activeWork.score * weights.active_work +
      goalAlignment * weights.goal_alignment +
      pendingAction.score * weights.pending_action +
      externalSignal * weights.external_signal +
      graphProximity.score * weights.graph_proximity,
    );

    const learnerMultiplier = this.matchClassMultiplier(obj, classMultipliers);
    relevance = Math.min(1.0, relevance * learnerMultiplier);

    // AS3: rule-driven overrides — pin / suppress / must-show / class-boost.
    const ruleEval = this.deps.rules?.evaluate(obj, now);
    if (ruleEval) {
      if (ruleEval.suppressed) return null;
      relevance = Math.min(1.0, relevance * ruleEval.multiplier + ruleEval.boost);
    }

    if (!ruleEval?.pinned && relevance <= 0.05) return null;

    const reason = this.pickPrimaryReason(recency, deadline, activeWork, pendingAction, externalSignal, graphProximity, obj, weights);
    const urgency = this.computeUrgency(deadline, pendingAction, activeWork, ruleEval?.pinned ?? false, now);
    const primaryMode = this.inferPrimaryMode(obj);
    const context = this.inferContext(obj, primaryMode);

    return {
      object: obj,
      relevance: ruleEval?.pinned ? Math.max(relevance, 0.99) : relevance,
      reason,
      primaryMode,
      context,
      urgency,
      scoredAt: now,
    };
  }

  private scoreRecency(obj: LoomObject, now: number): { score: number; lastTouchedAgo: number } {
    const age = now - obj.updatedAt;
    const score = Math.exp(-age * Math.LN2 / RECENCY_HALF_LIFE_MS);
    return { score, lastTouchedAgo: age };
  }

  private scoreDeadline(obj: LoomObject, now: number): { score: number; field: string | null; deadline: number; remainingMs: number } {
    let bestScore = 0;
    let bestField: string | null = null;
    let bestDeadline = 0;
    let bestRemaining = Infinity;

    if (obj.typeDefinition?.fields) {
      for (const field of obj.typeDefinition.fields) {
        if (field.type === 'datetime') {
          const value = obj.payload[field.name];
          if (typeof value === 'string' || typeof value === 'number') {
            const deadline = typeof value === 'string' ? new Date(value).getTime() : value;
            if (!isNaN(deadline) && deadline > now) {
              const remaining = deadline - now;
              let score = 0;
              if (remaining <= DEADLINE_NEAR_MS) {
                score = 1.0;
              } else if (remaining <= DEADLINE_FAR_MS) {
                score = 1.0 - (remaining - DEADLINE_NEAR_MS) / (DEADLINE_FAR_MS - DEADLINE_NEAR_MS);
              }
              if (score > bestScore) {
                bestScore = score;
                bestField = field.name;
                bestDeadline = deadline;
                bestRemaining = remaining;
              }
            }
          }
        }
      }
    }

    return { score: bestScore, field: bestField, deadline: bestDeadline, remainingMs: bestRemaining };
  }

  private scoreActiveWork(obj: LoomObject, now: number): { score: number; recentPatchCount: number } {
    const cutoff = now - ACTIVE_WORK_WINDOW_MS;
    const recentPatches = obj.patches.filter(p => p.timestamp > cutoff);
    const score = Math.min(recentPatches.length / 5, 1.0);
    return { score, recentPatchCount: recentPatches.length };
  }

  private scorePendingAction(obj: LoomObject, now: number): { score: number; action: string | null; awaitingSince: number } {
    const status = obj.payload.status;
    if (typeof status === 'string') {
      const pendingStatuses = ['pending', 'awaiting', 'open', 'in_progress'];
      if (pendingStatuses.some(s => status.toLowerCase().includes(s))) {
        return { score: 1.0, action: `Status: ${status}`, awaitingSince: obj.updatedAt };
      }
    }
    if (obj.visibility === 'draft' && obj.typeDefinition?.visibility?.publishTransition) {
      return { score: 0.7, action: 'Ready to publish', awaitingSince: obj.updatedAt };
    }
    return { score: 0, action: null, awaitingSince: 0 };
  }

  private scoreExternalSignal(obj: LoomObject): number {
    if (!this.deps.signals) return 0;
    const signals = this.deps.signals.getForObject(obj.id);
    if (signals.length === 0) return 0;
    return Math.min(1.0, signals.reduce((m, s) => Math.max(m, s.score), 0));
  }

  private matchClassMultiplier(obj: LoomObject, multipliers: Record<string, number>): number {
    let result = 1.0;
    const path = obj.typeDefinition?.name ?? '';
    const what = obj.typeCoordinate?.what ?? '';
    for (const [pattern, mult] of Object.entries(multipliers)) {
      const re = new RegExp('^' + pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$');
      if (re.test(path) || re.test(what)) result *= mult;
    }
    return result;
  }

  private pickPrimaryReason(
    recency: { score: number; lastTouchedAgo: number },
    deadline: { score: number; field: string | null; deadline: number; remainingMs: number },
    activeWork: { score: number; recentPatchCount: number },
    pendingAction: { score: number; action: string | null; awaitingSince: number },
    externalSignal: number,
    graphProximity: { score: number },
    obj: LoomObject,
    weights: AttentionWeights,
  ): AttentionReason {
    const candidates: { weight: number; reason: AttentionReason }[] = [];

    if (deadline.score > 0 && deadline.field) {
      candidates.push({
        weight: deadline.score * weights.deadline,
        reason: { type: 'deadline_approaching', field: deadline.field, deadline: deadline.deadline, remainingMs: deadline.remainingMs },
      });
    }
    if (pendingAction.score > 0 && pendingAction.action) {
      candidates.push({
        weight: pendingAction.score * weights.pending_action,
        reason: { type: 'pending_action', action: pendingAction.action, awaitingSince: pendingAction.awaitingSince },
      });
    }
    if (activeWork.recentPatchCount >= 3) {
      candidates.push({
        weight: activeWork.score * weights.active_work,
        reason: { type: 'active_work', lastTouchedAgo: recency.lastTouchedAgo },
      });
    }
    if (externalSignal > 0 && this.deps.signals) {
      const top = this.deps.signals.getForObject(obj.id)
        .sort((a, b) => b.score - a.score)[0];
      if (top && top.factor.type === 'extension_signal') {
        candidates.push({
          weight: externalSignal * weights.external_signal,
          reason: top.factor,
        });
      }
    }
    if (graphProximity.score > 0 && this.activeContextCellId) {
      candidates.push({
        weight: graphProximity.score * weights.graph_proximity,
        reason: { type: 'graph_proximity', activeContext: this.activeContextCellId, distance: Math.round(1 / graphProximity.score - 1) },
      });
    }

    if (candidates.length === 0) {
      return { type: 'active_work', lastTouchedAgo: recency.lastTouchedAgo };
    }

    candidates.sort((a, b) => b.weight - a.weight);
    return candidates[0].reason;
  }

  /** Map a reason to its underlying factor — exposed for AS2 telemetry. */
  static dominantFactor(reason: AttentionReason): AttentionFactor {
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

  private scoreGraphProximity(obj: LoomObject, now: number): { score: number } {
    if (!this.deps.paskGraph?.ready) return { score: 0 };
    if (!this.activeContextCellId) return { score: 0 };
    if (now - this.activeContextSetAt > GRAPH_PROXIMITY_CONTEXT_TTL_MS) return { score: 0 };
    const cellId = `helm:item:${obj.id}`;
    const dist = this.deps.paskGraph.distance(this.activeContextCellId, cellId);
    return { score: isFinite(dist) ? 1 / (1 + dist) : 0 };
  }

  private computeUrgency(
    deadline: { score: number; remainingMs: number },
    pendingAction: { score: number; awaitingSince: number },
    activeWork: { score: number; recentPatchCount: number },
    pinned: boolean,
    now: number,
  ): 'immediate' | 'soon' | 'background' {
    if (pinned) return 'immediate';
    if (deadline.score > 0 && deadline.remainingMs < IMMEDIATE_DEADLINE_MS) return 'immediate';
    if (pendingAction.score > 0 && pendingAction.awaitingSince > 0 && (now - pendingAction.awaitingSince) > PENDING_STALE_MS) return 'immediate';

    if (deadline.score > 0 && deadline.remainingMs < DEADLINE_NEAR_MS) return 'soon';
    if (activeWork.recentPatchCount >= 5) return 'soon';

    return 'background';
  }

  private inferPrimaryMode(obj: LoomObject): 'do' | 'talk' | 'find' {
    const archetype = obj.typeDefinition?.archetype;
    if (archetype === 'action' || archetype === 'instrument') return 'do';
    if (obj.typeDefinition?.conversationEnabled) return 'talk';
    if (obj.visibility === 'published') return 'find';
    return 'do';
  }

  private inferContext(obj: LoomObject, mode: 'do' | 'talk' | 'find'): IntentContext {
    const name = obj.typeDefinition?.name?.toLowerCase() ?? '';
    const category = obj.typeDefinition?.category?.toLowerCase() ?? '';
    const status = (obj.payload.status as string)?.toLowerCase() ?? '';
    const archetype = obj.typeDefinition?.archetype;

    if (mode === 'do') {
      if (name.includes('payment') || name.includes('invoice') || name.includes('settlement') ||
          category === 'commerce' && (status.includes('pay') || status.includes('settle'))) {
        return 'transact';
      }
      if (category === 'game' || name.includes('game') || name.includes('chess') ||
          name.includes('poker') || name.includes('dungeon')) {
        return 'play';
      }
      if (obj.visibility === 'published' && (name.includes('service') || name.includes('product') ||
          name.includes('listing') || name.includes('review') || name.includes('rating'))) {
        return 'offer';
      }
      if (status.includes('pending') || status.includes('in_progress') || status.includes('quoted') ||
          status.includes('accepted') || archetype === 'action') {
        return 'manage';
      }
      return 'create';
    }

    if (mode === 'talk') {
      if (name.includes('dispute') || name.includes('ballot') || name.includes('resolution') ||
          name.includes('governance') || category === 'governance') {
        return 'broadcast';
      }
      if (name.includes('agent') || name.includes('session') && category === 'meta') {
        return 'agent';
      }
      if (name.includes('identity') || name.includes('hat') || name.includes('goal') ||
          name.includes('intention') || category === 'identity') {
        return 'self';
      }
      if (name.includes('group') || name.includes('team') || name.includes('squad')) {
        return 'squad';
      }
      return 'direct';
    }

    if (name.includes('evidence') || name.includes('stake') || name.includes('proof') ||
        name.includes('audit') || category === 'evidence') {
      return 'truth';
    }
    if (name.includes('payment') || name.includes('invoice') || name.includes('stake') ||
        category === 'commerce') {
      return 'value';
    }
    if (name.includes('identity') || name.includes('hat') || name.includes('consumer') ||
        category === 'identity') {
      return 'network';
    }
    if (obj.visibility === 'published' || name.includes('taxonomy') || name.includes('service') ||
        name.includes('product')) {
      return 'market';
    }
    return 'memory';
  }
}

```
