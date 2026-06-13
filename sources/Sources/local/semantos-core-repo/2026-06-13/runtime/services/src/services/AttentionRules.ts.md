---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/AttentionRules.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.091387+00:00
---

# runtime/services/src/services/AttentionRules.ts

```ts
/**
 * AttentionRules — AS3 of the AS workstream.
 *
 * Operator-declared knobs over the attention surface:
 *   - pin: always-show, regardless of score, while a condition holds
 *   - must-show: surface even when score is below the 0.05 floor
 *   - suppress: remove from surface entirely
 *   - class-boost: multiplier on the learned per-class weight
 *
 * Rules live in `~/.semantos/attention-rules.toml`. This module is
 * renderer-agnostic and toml-agnostic — the host wires the loader.
 *
 * Patterns support glob (`trades.job.*.henderson`) and structured
 * filters (`from:<email>`, `to:<phone>`, `region:<area>`). Compiled to
 * a small predicate evaluator that runs at scoring time.
 */
import { TypedEventEmitter } from './TypedEventEmitter';
import type { LoomObject } from '../types/loom';

export interface AttentionPinRule {
  /** Object id or pattern that matches one or more objects. */
  readonly target: string;
  readonly reason?: string;
  /** ISO date string; if absent, pin is open-ended. */
  readonly until?: string;
  readonly createdAt: number;
}

export interface AttentionMustShowRule {
  readonly pattern: string;
  /** Additive boost to the relevance score, 0..1. */
  readonly boost: number;
  readonly createdAt: number;
}

export interface AttentionSuppressRule {
  readonly pattern: string;
  readonly since: string;
  /** ISO date string; if absent, suppression is open-ended. */
  readonly until?: string;
}

export interface AttentionClassBoostRule {
  readonly pattern: string;
  /** Multiplier on the learned per-class weight (1.0 = neutral). */
  readonly multiplier: number;
}

export interface AttentionRuleSet {
  pins: AttentionPinRule[];
  mustShow: AttentionMustShowRule[];
  suppress: AttentionSuppressRule[];
  classBoost: AttentionClassBoostRule[];
}

export interface AttentionRuleHistoryEntry {
  readonly timestamp: number;
  readonly action: 'pin' | 'unpin' | 'must-show' | 'suppress' | 'unsuppress' | 'class-boost' | 'rules-edit';
  readonly target: string;
  readonly hatId: string | null;
  readonly snapshot: AttentionRuleSet;
}

type RulesEvents = {
  change: [AttentionRuleSet];
};

/**
 * Compile a pattern to a predicate. The pattern grammar:
 *   - `*` matches any sequence of dot-segments
 *   - `?` matches a single dot-segment
 *   - `from:<value>` matches `obj.payload.from === value` (loose)
 *   - `to:<value>` matches `obj.payload.to === value` (loose)
 *   - `region:<value>` matches `obj.payload.region === value`
 *   - bare strings match against the type name + payload type-path
 */
export function compilePattern(pattern: string): (obj: LoomObject) => boolean {
  if (pattern.includes(':')) {
    const [field, value] = pattern.split(':', 2);
    if (field === 'from' || field === 'to' || field === 'region') {
      return (obj) => {
        const v = obj.payload[field];
        if (typeof v !== 'string') return false;
        if (value.includes('*')) {
          const re = globToRegExp(value);
          return re.test(v);
        }
        return v === value;
      };
    }
  }
  // Glob over typeDefinition.name + typeCoordinate.what.
  const re = globToRegExp(pattern);
  return (obj) => {
    const name = obj.typeDefinition?.name ?? '';
    const what = obj.typeCoordinate?.what ?? '';
    const id = obj.id;
    return re.test(name) || re.test(what) || re.test(id);
  };
}

function globToRegExp(glob: string): RegExp {
  // Escape regex special chars except * and ?
  const escaped = glob.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  // ? = single non-dot char-segment, * = any chars
  const re = '^' + escaped.replace(/\*/g, '.*').replace(/\?/g, '[^.]+') + '$';
  return new RegExp(re);
}

function emptyRules(): AttentionRuleSet {
  return { pins: [], mustShow: [], suppress: [], classBoost: [] };
}

export class AttentionRules extends TypedEventEmitter<RulesEvents> {
  private rules: AttentionRuleSet = emptyRules();
  private history: AttentionRuleHistoryEntry[] = [];
  private hatIdProvider: () => string | null = () => null;
  private persistFn: ((set: AttentionRuleSet) => Promise<void>) | null = null;

  setHatIdProvider(fn: () => string | null): void {
    this.hatIdProvider = fn;
  }

  setPersistFn(fn: (set: AttentionRuleSet) => Promise<void>): void {
    this.persistFn = fn;
  }

  load(set: AttentionRuleSet): void {
    this.rules = {
      pins: [...set.pins],
      mustShow: [...set.mustShow],
      suppress: [...set.suppress],
      classBoost: [...set.classBoost],
    };
    this.emit('change', this.snapshot());
  }

  snapshot(): AttentionRuleSet {
    return {
      pins: [...this.rules.pins],
      mustShow: [...this.rules.mustShow],
      suppress: [...this.rules.suppress],
      classBoost: [...this.rules.classBoost],
    };
  }

  getHistory(): AttentionRuleHistoryEntry[] {
    return [...this.history];
  }

  // ── Mutations ──

  async pin(target: string, opts: { reason?: string; until?: string } = {}): Promise<void> {
    this.rules.pins.push({
      target,
      reason: opts.reason,
      until: opts.until,
      createdAt: Date.now(),
    });
    await this.commit('pin', target);
  }

  async unpin(target: string): Promise<void> {
    this.rules.pins = this.rules.pins.filter(p => p.target !== target);
    await this.commit('unpin', target);
  }

  async mustShow(pattern: string, boost: number = 0.20): Promise<void> {
    this.rules.mustShow.push({ pattern, boost, createdAt: Date.now() });
    await this.commit('must-show', pattern);
  }

  async suppress(pattern: string, opts: { until?: string } = {}): Promise<void> {
    this.rules.suppress.push({
      pattern,
      since: new Date().toISOString(),
      until: opts.until,
    });
    await this.commit('suppress', pattern);
  }

  async unsuppress(pattern: string): Promise<void> {
    this.rules.suppress = this.rules.suppress.filter(s => s.pattern !== pattern);
    await this.commit('unsuppress', pattern);
  }

  async classBoost(pattern: string, multiplier: number): Promise<void> {
    const existing = this.rules.classBoost.findIndex(c => c.pattern === pattern);
    if (existing >= 0) {
      this.rules.classBoost[existing] = { pattern, multiplier };
    } else {
      this.rules.classBoost.push({ pattern, multiplier });
    }
    await this.commit('class-boost', pattern);
  }

  // ── Evaluators ──

  /**
   * Decide how a rule set should affect an object's surfacing. Returns:
   *  - `pinned`: bypass the score floor, render at the top
   *  - `suppressed`: remove from the surface entirely
   *  - `boost`: additive must-show boost (0 if none)
   *  - `multiplier`: per-class multiplier (1.0 if none)
   *
   * Pin overrides class-suppression for that one object; the suppression
   * rule continues to apply to siblings (per AS3 §5).
   */
  evaluate(obj: LoomObject, now: number = Date.now()): {
    pinned: boolean;
    suppressed: boolean;
    boost: number;
    multiplier: number;
  } {
    let pinned = false;
    for (const p of this.rules.pins) {
      if (p.until && new Date(p.until).getTime() < now) continue;
      if (p.target === obj.id) { pinned = true; break; }
      try {
        if (compilePattern(p.target)(obj)) { pinned = true; break; }
      } catch {
        // bad pattern — skip
      }
    }

    let suppressed = false;
    if (!pinned) {
      for (const s of this.rules.suppress) {
        if (s.until && new Date(s.until).getTime() < now) continue;
        try {
          if (compilePattern(s.pattern)(obj)) { suppressed = true; break; }
        } catch {
          // bad pattern — skip
        }
      }
    }

    let boost = 0;
    for (const m of this.rules.mustShow) {
      try {
        if (compilePattern(m.pattern)(obj)) { boost = Math.max(boost, m.boost); }
      } catch {
        // skip
      }
    }

    let multiplier = 1.0;
    for (const c of this.rules.classBoost) {
      try {
        if (compilePattern(c.pattern)(obj)) { multiplier *= c.multiplier; }
      } catch {
        // skip
      }
    }

    return { pinned, suppressed, boost, multiplier };
  }

  private async commit(
    action: AttentionRuleHistoryEntry['action'],
    target: string,
  ): Promise<void> {
    const snap = this.snapshot();
    this.history.push({
      timestamp: Date.now(),
      action,
      target,
      hatId: this.hatIdProvider(),
      snapshot: snap,
    });
    this.emit('change', snap);
    if (this.persistFn) {
      try {
        await this.persistFn(snap);
      } catch {
        // persistence failure non-fatal
      }
    }
  }
}

export const attentionRules = new AttentionRules();

```
