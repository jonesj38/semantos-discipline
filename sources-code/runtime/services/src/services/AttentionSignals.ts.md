---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/AttentionSignals.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.092969+00:00
---

# runtime/services/src/services/AttentionSignals.ts

```ts
/**
 * AttentionSignals — AS4 of the AS workstream.
 *
 * Pluggable adapter registry for inputs the AttentionEngine cannot derive
 * from LoomObject properties alone: weather changing, surf forecast,
 * legacy-ingest proposals, capability-token expiries, federated peer
 * dispatches.
 *
 * Each adapter either polls or pushes. Signals attach to existing
 * LoomObjects (augmenting their score) or synthesize transient surface
 * items with a TTL.
 */
import { TypedEventEmitter } from './TypedEventEmitter';
import type { LoomObject, AttentionReason } from '../types/loom';

export interface AttentionSignal {
  readonly sourceId: string;
  readonly attachToObjectId?: string;
  readonly synthesizesObject?: LoomObject;
  readonly factor: AttentionReason;
  /** Contribution to the synthetic external_signal factor, 0..1. */
  readonly score: number;
  readonly expiresAt?: number;
}

export interface AttentionSignalSource {
  readonly id: string;
  readonly displayName: string;
  poll?(now: number): Promise<AttentionSignal[]>;
  subscribe?(emit: (signal: AttentionSignal) => void): () => void;
}

type SignalEvents = {
  signal: [AttentionSignal];
  flush: [{ sourceId: string; signals: AttentionSignal[] }];
};

export interface AttentionSignalRegistryConfig {
  /** ms between polls; default 30 minutes. */
  pollIntervalMs?: number;
  /** Cap on the number of active signals retained per source. */
  perSourceLimit?: number;
}

export class AttentionSignalRegistry extends TypedEventEmitter<SignalEvents> {
  private sources = new Map<string, AttentionSignalSource>();
  private subscriptions = new Map<string, () => void>();
  private active = new Map<string, AttentionSignal[]>();
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private config: Required<AttentionSignalRegistryConfig>;
  private enabled = new Map<string, boolean>();

  constructor(config: AttentionSignalRegistryConfig = {}) {
    super();
    this.config = {
      pollIntervalMs: config.pollIntervalMs ?? 30 * 60 * 1000,
      perSourceLimit: config.perSourceLimit ?? 50,
    };
  }

  register(source: AttentionSignalSource, opts: { enabled?: boolean } = {}): void {
    this.sources.set(source.id, source);
    this.enabled.set(source.id, opts.enabled ?? true);
    if (source.subscribe && this.enabled.get(source.id)) {
      const unsub = source.subscribe(s => this.ingest(s));
      this.subscriptions.set(source.id, unsub);
    }
  }

  unregister(id: string): void {
    this.subscriptions.get(id)?.();
    this.subscriptions.delete(id);
    this.sources.delete(id);
    this.active.delete(id);
    this.enabled.delete(id);
  }

  setEnabled(id: string, enabled: boolean): void {
    this.enabled.set(id, enabled);
    if (!enabled) {
      this.subscriptions.get(id)?.();
      this.subscriptions.delete(id);
      this.active.delete(id);
    } else {
      const src = this.sources.get(id);
      if (src?.subscribe) {
        const unsub = src.subscribe(s => this.ingest(s));
        this.subscriptions.set(id, unsub);
      }
    }
  }

  isEnabled(id: string): boolean {
    return this.enabled.get(id) ?? false;
  }

  start(): void {
    if (this.pollTimer) return;
    this.pollTimer = setInterval(() => void this.pollAll(), this.config.pollIntervalMs);
    void this.pollAll();
  }

  stop(): void {
    if (this.pollTimer) clearInterval(this.pollTimer);
    this.pollTimer = null;
    for (const unsub of this.subscriptions.values()) unsub();
    this.subscriptions.clear();
  }

  /** All currently-active signals across all enabled sources. */
  getActive(): AttentionSignal[] {
    const out: AttentionSignal[] = [];
    const now = Date.now();
    for (const [, signals] of this.active) {
      for (const s of signals) {
        if (s.expiresAt && s.expiresAt < now) continue;
        out.push(s);
      }
    }
    return out;
  }

  /** Signals attached to a specific object — used by the engine's per-object scorer. */
  getForObject(objectId: string): AttentionSignal[] {
    const out: AttentionSignal[] = [];
    const now = Date.now();
    for (const [, signals] of this.active) {
      for (const s of signals) {
        if (s.expiresAt && s.expiresAt < now) continue;
        if (s.attachToObjectId === objectId) out.push(s);
      }
    }
    return out;
  }

  /** Synthesised LoomObjects that should appear as transient surface items. */
  getSynthesized(): { signal: AttentionSignal; object: LoomObject }[] {
    const out: { signal: AttentionSignal; object: LoomObject }[] = [];
    const now = Date.now();
    for (const [, signals] of this.active) {
      for (const s of signals) {
        if (s.expiresAt && s.expiresAt < now) continue;
        if (s.synthesizesObject) out.push({ signal: s, object: s.synthesizesObject });
      }
    }
    return out;
  }

  private async pollAll(): Promise<void> {
    const now = Date.now();
    for (const [id, src] of this.sources) {
      if (!this.enabled.get(id)) continue;
      if (!src.poll) continue;
      try {
        const signals = await src.poll(now);
        const fresh = signals.slice(0, this.config.perSourceLimit);
        this.active.set(id, fresh);
        this.emit('flush', { sourceId: id, signals: fresh });
      } catch {
        // adapter errors are non-fatal
      }
    }
  }

  private ingest(signal: AttentionSignal): void {
    if (!this.enabled.get(signal.sourceId)) return;
    const list = this.active.get(signal.sourceId) ?? [];
    list.push(signal);
    if (list.length > this.config.perSourceLimit) {
      list.splice(0, list.length - this.config.perSourceLimit);
    }
    this.active.set(signal.sourceId, list);
    this.emit('signal', signal);
  }
}

export const attentionSignals = new AttentionSignalRegistry();

```
