---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/PaskGraph.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.090888+00:00
---

# runtime/services/src/services/PaskGraph.ts

```ts
/**
 * PaskGraph — DB1 of the Dimensional Second Brain workstream.
 *
 * Wraps the Pask WASM kernel as a lazy-init service. Before the kernel
 * loads, interactions queue (up to 500); once init() resolves they drain
 * in order. After init, interactions are fire-and-forget.
 *
 * Cell-ID namespace convention (frozen; see DIMENSIONAL-SECOND-BRAIN.md §DB1):
 *   helm:item:<loom-object-id>
 *   helm:type:<type-path>
 *   helm:hat:<hat-id>
 *   helm:ctx:<field|desk|night>
 *   obs:note:<vault-id>/<rel-path>   (DB3)
 *   obs:tag:#<tag>                   (DB3)
 *   nx:page:<workspace-id>/<page-id> (DB4)
 *   nx:db:<workspace-id>/<db-id>     (DB4)
 *   q:<query-hash>                   (voice/REPL terms)
 */

import type { PaskAdapter } from '@semantos/pask';
import type { AttentionInteractionRecord, AttentionInteraction } from './AttentionTelemetry';

export interface PaskStableThread {
  cellId: string;
  /** Source prefix: 'helm' | 'obs' | 'nx' | other */
  source: string;
  hState: number;
  trafficCount: number;
}

export interface PaskInteractArgs {
  cellId: string;
  kind: string;
  strength: number;
  relatedCells?: string[];
  nowMs?: number;
}

// Kernel cap is 64 bytes per cell ID including null terminator.
const CELL_ID_MAX = 63;
const QUEUE_CAP = 500;
const FINALIZE_INTERVAL_MS = 60_000;

function trimCellId(id: string): string {
  if (id.length <= CELL_ID_MAX) return id;
  // Truncate to 48 chars + 8-char hash suffix so the ID is still recognisable.
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (Math.imul(31, h) + id.charCodeAt(i)) | 0;
  return `${id.slice(0, 48)}#${Math.abs(h).toString(16).padStart(8, '0').slice(0, 8)}`;
}

function strengthForKind(kind: AttentionInteraction['kind']): number {
  switch (kind) {
    // Completion signals — you finished something
    case 'acted-on':     return 3.0;
    case 'pinned':       return 2.0;
    // Engagement signals — you noticed it
    case 'tapped':       return 0.5;
    case 'opened':       return 0.3;
    case 'unsuppressed': return 0.3;
    // Cross-channel delivery (TALK two-tier)
    case 'push-opened':    return 0.4;
    case 'push-delivered': return 0.1;
    // Negative signals
    case 'dismissed':      return -0.5;
    case 'push-dismissed': return -0.3;
    case 'suppressed':     return -1.0;
    case 'ignored':        return -0.1;
    default:               return 0.0;
  }
}

export class PaskGraph {
  private adapter: PaskAdapter | null = null;
  private queue: PaskInteractArgs[] = [];
  private activeContextCellId: string | null = null;
  private finalizeTimer: ReturnType<typeof setInterval> | null = null;
  /** Edge map cache — rebuilt lazily when needed for distance queries. */
  private edgeMapCache: Map<string, Set<string>> | null = null;
  private edgeMapStamp = 0;

  /** Load and instantiate the WASM kernel.
   *  source: a URL string ('/wasm/pask.wasm') or raw bytes. */
  async init(source: BufferSource | string): Promise<void> {
    const { loadPask, PaskAdapter: Adapter } = await import('@semantos/pask');
    let bytes: BufferSource;
    if (typeof source === 'string') {
      const resp = await fetch(source);
      if (!resp.ok) throw new Error(`pask WASM fetch failed: ${resp.status} ${source}`);
      bytes = await resp.arrayBuffer();
    } else {
      bytes = source;
    }
    const pask = await loadPask(bytes);
    this.adapter = new Adapter(pask);

    for (const item of this.queue) {
      this.adapter.interact(item).catch(() => {});
    }
    this.queue = [];

    this.finalizeTimer = setInterval(() => {
      this.adapter?.finalize(Date.now());
      this.edgeMapCache = null; // invalidate after finalize may prune nodes
    }, FINALIZE_INTERVAL_MS);
  }

  dispose(): void {
    if (this.finalizeTimer) clearInterval(this.finalizeTimer);
    this.finalizeTimer = null;
    this.adapter = null;
    this.edgeMapCache = null;
  }

  get ready(): boolean {
    return this.adapter !== null;
  }

  // ── Ingestion ────────────────────────────────────────────────────────

  /** Translate an AttentionTelemetry record into a Pask interaction. */
  observeTelemetry(rec: AttentionInteractionRecord): void {
    const { interaction } = rec;
    const strength = strengthForKind(interaction.kind);
    if (strength === 0) return;

    const itemId = 'itemId' in interaction ? interaction.itemId : null;
    if (!itemId) return;

    const cellId = trimCellId(`helm:item:${itemId}`);
    const related: string[] = [];
    if (rec.hatId) related.push(trimCellId(`helm:hat:${rec.hatId}`));
    if (rec.context) related.push(`helm:ctx:${rec.context}`);

    this.interact({ cellId, kind: interaction.kind, strength, relatedCells: related, nowMs: rec.timestamp });
  }

  /** Feed an interaction directly — used by vault/Notion adapters (DB3/DB4). */
  interact(args: PaskInteractArgs): void {
    const item: PaskInteractArgs = {
      cellId: trimCellId(args.cellId),
      kind: args.kind,
      strength: args.strength,
      relatedCells: (args.relatedCells ?? []).map(trimCellId),
      nowMs: args.nowMs ?? Date.now(),
    };

    if (!this.adapter) {
      if (this.queue.length < QUEUE_CAP) this.queue.push(item);
      return;
    }

    this.edgeMapCache = null; // graph changed
    this.adapter.interact(item).catch(() => {});
  }

  // ── Query ────────────────────────────────────────────────────────────

  stableThreads(opts: { limit?: number; sourcePrefix?: string } = {}): PaskStableThread[] {
    if (!this.adapter) return [];
    const { limit = 20, sourcePrefix } = opts;
    const raw = this.adapter.stableThreads(limit * 4); // over-fetch, then filter
    const out: PaskStableThread[] = [];
    for (const t of raw) {
      if (sourcePrefix && !t.cellId.startsWith(sourcePrefix)) continue;
      out.push({
        cellId: t.cellId,
        source: t.cellId.split(':')[0] ?? 'helm',
        hState: t.hState,
        trafficCount: t.interactionCount,
      });
      if (out.length >= limit) break;
    }
    return out;
  }

  neighbours(cellId: string, hops: 1 | 2 | 3 = 1): string[] {
    const em = this.edgeMap();
    const visited = new Set<string>([cellId]);
    let frontier = new Set<string>([cellId]);
    for (let h = 0; h < hops; h++) {
      const next = new Set<string>();
      for (const c of frontier) {
        for (const n of em.get(c) ?? []) {
          if (!visited.has(n)) { visited.add(n); next.add(n); }
        }
      }
      frontier = next;
    }
    visited.delete(cellId);
    return [...visited];
  }

  /** Returns min-hop distance from cellId to targetCellId, capped at maxHops.
   *  Returns Infinity when unreachable within the cap. */
  distance(cellId: string, targetCellId: string, maxHops = 3): number {
    if (cellId === targetCellId) return 0;
    const em = this.edgeMap();
    const visited = new Set<string>([cellId]);
    let frontier = new Set<string>([cellId]);
    for (let h = 1; h <= maxHops; h++) {
      const next = new Set<string>();
      for (const c of frontier) {
        for (const n of em.get(c) ?? []) {
          if (n === targetCellId) return h;
          if (!visited.has(n)) { visited.add(n); next.add(n); }
        }
      }
      if (next.size === 0) break;
      frontier = next;
    }
    return Infinity;
  }

  // ── Active context (for graph-proximity scoring in AttentionEngine) ──

  setActiveContext(cellId: string | null): void {
    this.activeContextCellId = cellId;
  }

  getActiveContext(): string | null {
    return this.activeContextCellId;
  }

  // ── Snapshot ─────────────────────────────────────────────────────────

  snapshot(): Uint8Array | null {
    if (!this.adapter) return null;
    this.adapter.finalize(Date.now());
    return this.adapter.exportSnapshotBlob();
  }

  restore(blob: Uint8Array): void {
    this.adapter?.importSnapshotBlob(blob);
    this.edgeMapCache = null;
  }

  // ── Internals ────────────────────────────────────────────────────────

  private edgeMap(): Map<string, Set<string>> {
    // Rebuilding from snapshot is O(edges). Cache until next interact/finalize.
    if (this.edgeMapCache) return this.edgeMapCache;
    const em = new Map<string, Set<string>>();
    if (this.adapter) {
      const { edges } = this.adapter.snapshot();
      for (const e of edges) {
        if (!em.has(e.fromCell)) em.set(e.fromCell, new Set());
        if (!em.has(e.toCell)) em.set(e.toCell, new Set());
        em.get(e.fromCell)!.add(e.toCell);
        em.get(e.toCell)!.add(e.fromCell);
      }
    }
    this.edgeMapCache = em;
    return em;
  }
}

export const paskGraph = new PaskGraph();

```
