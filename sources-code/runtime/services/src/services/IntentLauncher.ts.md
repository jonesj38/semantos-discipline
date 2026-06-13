---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/IntentLauncher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.094499+00:00
---

# runtime/services/src/services/IntentLauncher.ts

```ts
/**
 * IntentLauncher — 1-3-5 control plane ranked shortlist.
 *
 * The 15 intent slots (DO×5 + FIND×5 + TALK×5) each resolve a promoted
 * shortlist of the most relevant objects + types for that context, ranked
 * by Pask-graph proximity and recency. Accessible via REPL/SSH (`launch`)
 * and from the React SlotLauncher component.
 */

import type { LoomStore } from './LoomStore';
import type { PaskGraph } from './PaskGraph';

// ── Slot types ─────────────────────────────────────────────────────────────

export type IntentContext =
  | 'do.transact' | 'do.manage' | 'do.create' | 'do.play' | 'do.offer'
  | 'talk.self' | 'talk.direct' | 'talk.squad' | 'talk.agent' | 'talk.broadcast'
  | 'find.memory' | 'find.market' | 'find.network' | 'find.value' | 'find.truth';

export const ALL_SLOTS: IntentContext[] = [
  'do.transact', 'do.manage', 'do.create', 'do.play', 'do.offer',
  'talk.self', 'talk.direct', 'talk.squad', 'talk.agent', 'talk.broadcast',
  'find.memory', 'find.market', 'find.network', 'find.value', 'find.truth',
];

export const SLOT_MODE: Record<IntentContext, 'do' | 'talk' | 'find'> = {
  'do.transact': 'do', 'do.manage': 'do', 'do.create': 'do', 'do.play': 'do', 'do.offer': 'do',
  'talk.self': 'talk', 'talk.direct': 'talk', 'talk.squad': 'talk', 'talk.agent': 'talk', 'talk.broadcast': 'talk',
  'find.memory': 'find', 'find.market': 'find', 'find.network': 'find', 'find.value': 'find', 'find.truth': 'find',
};

export const SLOT_LABEL: Record<IntentContext, string> = {
  'do.transact':      'Transact',
  'do.manage':        'Manage',
  'do.create':        'Create',
  'do.play':          'Play',
  'do.offer':         'Offer',
  'talk.self':        'Journal',
  'talk.direct':      'Direct',
  'talk.squad':       'Squad',
  'talk.agent':       'Agent',
  'talk.broadcast':   'Broadcast',
  'find.memory':      'Memory',
  'find.market':      'Market',
  'find.network':     'Network',
  'find.value':       'Value',
  'find.truth':       'Truth',
};

// Type archetypes hinted per slot — used to filter/rank the type shortlist.
// Kept as plain strings so no circular dep on the type registry.
const SLOT_TYPE_HINTS: Record<IntentContext, string[]> = {
  'do.transact':   ['Transaction', 'Invoice', 'Job', 'Contract'],
  'do.manage':     ['Task', 'Project', 'Goal'],
  'do.create':     ['Document', 'Template', 'Asset'],
  'do.play':       ['Game', 'Puzzle', 'Media'],
  'do.offer':      ['Offer', 'Proposal', 'Listing'],
  'talk.self':     ['Document', 'Journal', 'Note'],
  'talk.direct':   ['Contact', 'Message', 'Thread'],
  'talk.squad':    ['Squad', 'Channel', 'Team'],
  'talk.agent':    ['Agent', 'Bot', 'Workflow'],
  'talk.broadcast':['Channel', 'Stream', 'Page'],
  'find.memory':   ['Document', 'Note', 'Journal'],
  'find.market':   ['Listing', 'Product', 'Service'],
  'find.network':  ['Contact', 'Organization', 'Event'],
  'find.value':    ['Asset', 'Portfolio', 'Position'],
  'find.truth':    ['Reference', 'Source', 'Fact'],
};

// ── Result types ───────────────────────────────────────────────────────────

export interface LauncherItem {
  kind: 'object' | 'type';
  /** Loom object ID or type archetype name. */
  id: string;
  label: string;
  /** Composite relevance score [0, 1]. */
  score: number;
}

export interface LauncherResult {
  slot: IntentContext;
  /** Top 3 objects + 2 types, interleaved. */
  promoted: LauncherItem[];
  /** Search over full object+type lists for this slot. */
  search: (query: string) => LauncherItem[];
}

export interface LauncherDeps {
  loomStore: LoomStore;
  paskGraph?: PaskGraph;
}

// ── Resolver ───────────────────────────────────────────────────────────────

function recencyScore(updatedAt: number | undefined, now: number): number {
  if (!updatedAt) return 0;
  const ageDays = (now - updatedAt) / (1000 * 60 * 60 * 24);
  return Math.max(0, 1 - ageDays / 30);
}

function paskScoreFor(graph: PaskGraph | undefined, cellId: string): number {
  if (!graph?.ready) return 0;
  const ctx = graph.getActiveContext();
  if (!ctx) return 0;
  const dist = graph.distance(ctx, cellId);
  return isFinite(dist) ? 1 / (1 + dist) : 0;
}

function normalize(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]/g, '');
}

export class IntentLauncher {
  resolve(slot: IntentContext, deps: LauncherDeps): LauncherResult {
    const now = Date.now();
    const { loomStore, paskGraph } = deps;
    const state = loomStore.getState();
    const hints = SLOT_TYPE_HINTS[slot];

    // ── Objects ──────────────────────────────────────────────────────────
    const allObjects = [...state.objects.values()];
    const scoredObjects: LauncherItem[] = allObjects.map((obj) => {
      const cellId = `helm:item:${obj.id}`;
      const ps = paskScoreFor(paskGraph, cellId);
      const rs = recencyScore(obj.updatedAt, now);
      const typeBoost = hints.some(
        (h) => obj.typeDefinition?.name?.toLowerCase().includes(h.toLowerCase())
      ) ? 0.1 : 0;
      const score = ps * 0.6 + rs * 0.4 + typeBoost;
      const label = (obj.payload?.title as string | undefined) ?? obj.id.slice(0, 12);
      return { kind: 'object' as const, id: obj.id, label, score };
    });
    scoredObjects.sort((a, b) => b.score - a.score);

    // ── Types ────────────────────────────────────────────────────────────
    const scoredTypes: LauncherItem[] = hints.map((typeName) => {
      const cellId = `helm:type:${typeName}`;
      const ps = paskScoreFor(paskGraph, cellId);
      return { kind: 'type' as const, id: typeName, label: typeName, score: ps };
    });
    scoredTypes.sort((a, b) => b.score - a.score);

    // ── Promote: 3 objects + 2 types ─────────────────────────────────────
    const promoted: LauncherItem[] = [
      ...scoredObjects.slice(0, 3),
      ...scoredTypes.slice(0, 2),
    ];

    // ── Search fn ────────────────────────────────────────────────────────
    const search = (query: string): LauncherItem[] => {
      const q = normalize(query);
      if (!q) return promoted;
      const objs = scoredObjects.filter(
        (o) => normalize(o.label).includes(q) || normalize(o.id).includes(q)
      );
      const types = scoredTypes.filter((t) => normalize(t.label).includes(q));
      return [...objs.slice(0, 5), ...types.slice(0, 3)];
    };

    return { slot, promoted, search };
  }
}

export const intentLauncher = new IntentLauncher();

// ── Late-bound deps (avoids circular import from index.ts) ─────────────────

let _deps: LauncherDeps | null = null;
export function setLaunchDeps(deps: LauncherDeps): void {
  _deps = deps;
}
export function getLaunchDeps(): LauncherDeps | null {
  return _deps;
}

```
