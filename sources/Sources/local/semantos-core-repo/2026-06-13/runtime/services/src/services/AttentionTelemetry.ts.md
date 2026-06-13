---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/AttentionTelemetry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.096451+00:00
---

# runtime/services/src/services/AttentionTelemetry.ts

```ts
/**
 * AttentionTelemetry — AS1 of the AS workstream.
 *
 * Captures every operator interaction with the attention surface as a typed
 * event. The events are the input the AS2 weight learner consumes; without
 * telemetry there is nothing to learn from.
 *
 * Per the design doc:
 *   - Events are signed cells (LINEARITY = RELEVANT) batched into the
 *     storage adapter (AS1 §6).
 *   - Each event carries an optional `context` tag (`field` / `desk` /
 *     `night`) used by the per-context profile selector in AS2.
 *   - `acted-on` events link a voice / REPL command back to a surfaced
 *     attention item, so the learner can attribute a successful action
 *     to the surfacing.
 *
 * This service is renderer-agnostic. The React surface in
 * `AttentionSurface.tsx` instruments tap / open / ignore / dismiss; the
 * REPL telemetry verb queries the stream.
 */
import { TypedEventEmitter } from './TypedEventEmitter';
import type { AttentionReason } from '../types/loom';

export type AttentionContextTag = 'field' | 'desk' | 'night';

export type AttentionInteraction =
  | { kind: 'tapped'; itemId: string; rank: number; relevance: number; primaryReason: AttentionReason['type'] }
  | { kind: 'opened'; itemId: string; secondsViewed: number }
  | { kind: 'dismissed'; itemId: string; explicit: boolean }
  | { kind: 'acted-on'; itemId: string; verb: 'do' | 'find' | 'talk'; targetVerb: string }
  | { kind: 'ignored'; itemId: string; surfaceForMs: number }
  | { kind: 'pinned'; itemId: string }
  | { kind: 'suppressed'; itemId: string; pattern: string }
  | { kind: 'unsuppressed'; itemId: string }
  // AS5 cross-surface delivery — push / SMS / voice outcomes feed the same loop.
  | { kind: 'push-delivered'; itemId: string; channel: 'push' | 'sms' | 'voice' }
  | { kind: 'push-opened'; itemId: string; channel: 'push' | 'sms' | 'voice' }
  | { kind: 'push-dismissed'; itemId: string; channel: 'push' | 'sms' | 'voice' };

export interface AttentionInteractionRecord {
  /** Stable monotonic id, hash-friendly. */
  readonly id: string;
  readonly timestamp: number;
  readonly hatId: string | null;
  readonly context: AttentionContextTag | null;
  readonly interaction: AttentionInteraction;
}

export interface AttentionTelemetryQueryOpts {
  /** Lower-bound timestamp (inclusive). */
  since?: number;
  /** Upper-bound timestamp (inclusive). */
  until?: number;
  /** Filter by interaction kind(s). */
  kinds?: AttentionInteraction['kind'][];
  /** Filter by item id. */
  itemId?: string;
  /** Maximum records returned. */
  limit?: number;
}

type TelemetryEvents = {
  record: [AttentionInteractionRecord];
};

/** Source of the active hat id (provided by IdentityStore at runtime). */
export type HatIdProvider = () => string | null;

/** Source of the current context tag (provided by host or platform). */
export type ContextTagProvider = () => AttentionContextTag | null;

/**
 * In-memory telemetry store with optional persistence hook. The persistence
 * hook is called after every record() so the host can flush to its substrate
 * cell store (lmdb in BRAIN, IndexedDB in the browser). Retention defaults to
 * 90 days raw + lifetime aggregated; the persistence layer is responsible
 * for trimming.
 */
export class AttentionTelemetry extends TypedEventEmitter<TelemetryEvents> {
  private records: AttentionInteractionRecord[] = [];
  private hatIdProvider: HatIdProvider = () => null;
  private contextProvider: ContextTagProvider = () => null;
  private persistFn: ((rec: AttentionInteractionRecord) => Promise<void>) | null = null;
  private seq = 0;

  constructor() {
    super();
  }

  setHatIdProvider(provider: HatIdProvider): void {
    this.hatIdProvider = provider;
  }

  setContextProvider(provider: ContextTagProvider): void {
    this.contextProvider = provider;
  }

  setPersistFn(fn: (rec: AttentionInteractionRecord) => Promise<void>): void {
    this.persistFn = fn;
  }

  async record(interaction: AttentionInteraction): Promise<AttentionInteractionRecord> {
    const ts = Date.now();
    const rec: AttentionInteractionRecord = {
      id: `att-${ts.toString(36)}-${(this.seq++).toString(36)}`,
      timestamp: ts,
      hatId: this.hatIdProvider(),
      context: this.contextProvider(),
      interaction,
    };
    this.records.push(rec);
    this.emit('record', rec);
    if (this.persistFn) {
      try {
        await this.persistFn(rec);
      } catch {
        // Persistence failures are non-fatal — telemetry remains in-memory.
      }
    }
    return rec;
  }

  /**
   * Synchronous query over in-memory records. For substrate-backed history
   * beyond the in-memory window, the host wires a separate adapter that
   * reads the cell store.
   */
  query(opts: AttentionTelemetryQueryOpts = {}): AttentionInteractionRecord[] {
    const since = opts.since ?? 0;
    const until = opts.until ?? Number.MAX_SAFE_INTEGER;
    const kinds = opts.kinds ? new Set(opts.kinds) : null;
    const out: AttentionInteractionRecord[] = [];
    for (const rec of this.records) {
      if (rec.timestamp < since) continue;
      if (rec.timestamp > until) continue;
      if (kinds && !kinds.has(rec.interaction.kind)) continue;
      if (opts.itemId) {
        const itemId = (rec.interaction as { itemId?: string }).itemId;
        if (itemId !== opts.itemId) continue;
      }
      out.push(rec);
      if (opts.limit && out.length >= opts.limit) break;
    }
    return out;
  }

  /** Total in-memory record count. */
  size(): number {
    return this.records.length;
  }

  /** Aggregate: count interactions per item, per kind. Used by AS2 learner. */
  aggregateByItem(): Map<string, Record<AttentionInteraction['kind'], number>> {
    const map = new Map<string, Record<string, number>>();
    for (const rec of this.records) {
      const itemId = (rec.interaction as { itemId?: string }).itemId;
      if (!itemId) continue;
      let bucket = map.get(itemId);
      if (!bucket) {
        bucket = {};
        map.set(itemId, bucket);
      }
      bucket[rec.interaction.kind] = (bucket[rec.interaction.kind] ?? 0) + 1;
    }
    return map as Map<string, Record<AttentionInteraction['kind'], number>>;
  }

  /** Drop in-memory records older than `cutoff`. The persistence layer holds the historical record. */
  trim(cutoff: number): number {
    const before = this.records.length;
    this.records = this.records.filter(r => r.timestamp >= cutoff);
    return before - this.records.length;
  }
}

/** Singleton, parallel to other services in this package. */
export const attentionTelemetry = new AttentionTelemetry();

```
