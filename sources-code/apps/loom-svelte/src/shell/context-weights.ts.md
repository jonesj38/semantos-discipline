---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/context-weights.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.086466+00:00
---

# apps/loom-svelte/src/shell/context-weights.ts

```ts
/**
 * Context weights — which types are "favourites" for each of the 15 contexts.
 *
 * Types ↔ contexts is many-to-many (see docs/EXTENSIONS-VS-TYPES.md and
 * docs/BRAINSTORM-DOCK-SHELL-SILOS.md). This file declares the BASE weights
 * for the 14 kernel types. Extensions layer on top via their manifest's
 * `tier_3_weights` field — composed by `resolveFavourites()`.
 *
 * Weight scale: 0 (not shown) → 100 (top favourite). Values are coarse —
 * we just need ordering, not precision.
 *
 * ── Document-leak policy ──
 * Document is INTENTIONALLY confined to a narrow set of contexts:
 *   - do.create   (primary — "draft a thing")
 *   - talk.self   (journal / notes-to-self)
 *   - find.memory (search your own notes)
 * It must NOT appear in talk.direct/squad/broadcast or do.manage — those
 * slots get types that properly model the context (Contact, Squad, Channel…).
 *
 * ── Stub types ──
 * Contact and Squad aren't in the kernel yet — they model the
 * *contacts book* which is a Plexus SDK concern (identity lookup, group
 * routing). They stay stubbed here and the tier-3 popover renders the
 * who-picker variant for `talk.direct` / `talk.squad` instead of
 * `new Contact` / `new Squad` buttons.
 *
 * Channel, Stream, and Page were promoted to kernel types in this PR —
 * they are local "publish envelopes" (broadcast lane) and don't need
 * Plexus to be meaningful. `new Channel` etc. now dispatch normally.
 */

export type IntentId = 'do' | 'talk' | 'find';
export type DoContextId = 'transact' | 'manage' | 'create' | 'play' | 'offer';
export type TalkContextId = 'self' | 'direct' | 'squad' | 'agent' | 'broadcast';
export type FindContextId = 'memory' | 'market' | 'network' | 'value' | 'truth';
export type ContextId = DoContextId | TalkContextId | FindContextId;

/**
 * Full context path, e.g. "do.create". Only the 15 valid pairings exist —
 * we explicitly enumerate instead of using `${IntentId}.${ContextId}` so
 * the Cartesian product (e.g. "find.create") is rejected by the compiler.
 */
export type ContextPath =
  | `do.${DoContextId}`
  | `talk.${TalkContextId}`
  | `find.${FindContextId}`;

/** A weight entry: type name → weight (0–100). */
export type WeightMap = Partial<Record<string, number>>;

/**
 * Types that aren't in the kernel yet — their favourites render as
 * "coming with Plexus" stubs rather than dispatching `new <Type>`.
 *
 * Note: for talk.direct / talk.squad the Tier3Popover renders a
 * *who-picker* variant entirely instead of favourite buttons, so these
 * Contact/Squad entries are mostly belt-and-suspenders — if some future
 * surface resolves favourites for those paths it still won't attempt a
 * `new Contact` dispatch.
 */
export const STUB_TYPES = new Set<string>([
  'Contact',
  'Squad',
]);

/** Short note shown on hover / in the stub toast. */
export const STUB_NOTES: Record<string, string> = {
  Contact: 'Lands with the Plexus SDK — contacts book integration.',
  Squad: 'Lands with the Plexus SDK — named groups of contacts/agents.',
};

/** Base kernel weights, keyed by context path. */
export const KERNEL_CONTEXT_WEIGHTS: Record<ContextPath, WeightMap> = {
  // ── Do ─────────────────────────────────────────────
  'do.transact': {
    PaymentChannel: 90,
    ChannelPolicy: 70,
    Stake: 60,
  },
  'do.manage': {
    Action: 90,
    ConsumerBinding: 60,
    GovernancePolicy: 20,
  },
  'do.create': {
    Document: 95,
    Event: 80,
    TaxonomyNode: 50,
  },
  'do.play': {},
  'do.offer': {
    Instrument: 90,
  },

  // ── Talk ───────────────────────────────────────────
  // Self is the only Talk context where Document belongs — it's the
  // private journal surface (notes to self, intentions).
  'talk.self': {
    Document: 70,
    Event: 30,
  },
  // Direct = "who" (individual). Primary type is Contact (stubbed).
  'talk.direct': {
    Contact: 95,
  },
  // Squad = "who" (a named group). Primary type is Squad (stubbed).
  // Event and Action stay as secondaries — coordinating work with a squad
  // naturally produces events/actions bound to that squad.
  'talk.squad': {
    Squad: 95,
    Event: 40,
    Action: 20,
  },
  'talk.agent': {},
  // Broadcast = the town square. Primary publish types (Channel/Stream/Page)
  // are stubbed until Plexus ships them; governance types populate secondaries.
  'talk.broadcast': {
    Channel: 90,
    Stream: 80,
    Page: 70,
    Dispute: 50,
    Ballot: 45,
    GovernancePolicy: 40,
    TaxonomyNode: 20,
  },

  // ── Find ───────────────────────────────────────────
  'find.memory': {
    Document: 70,
    Event: 60,
    Action: 20,
  },
  'find.market': {
    Instrument: 50,
    TaxonomyNode: 40,
  },
  'find.network': {
    ConsumerBinding: 30,
  },
  'find.value': {
    PaymentChannel: 80,
    Stake: 70,
    ChannelPolicy: 40,
  },
  'find.truth': {
    Resolution: 90,
    Dispute: 60,
    Ballot: 40,
  },
};

/** Extension tier-3 weight hints. Composed on top of kernel base weights. */
export type ExtensionWeights = Record<ContextPath, WeightMap>;

/**
 * Compose kernel + active extension weights.
 * Extension entries win ties; otherwise the higher weight wins.
 */
export function composeWeights(
  base: Record<ContextPath, WeightMap>,
  ...extensionWeights: ExtensionWeights[]
): Record<ContextPath, WeightMap> {
  const out: Record<ContextPath, WeightMap> = JSON.parse(JSON.stringify(base));
  for (const ext of extensionWeights) {
    for (const path of Object.keys(ext) as ContextPath[]) {
      const entries = ext[path];
      if (!entries) continue;
      out[path] ??= {};
      for (const [type, weight] of Object.entries(entries)) {
        const existing = out[path][type] ?? 0;
        out[path][type] = Math.max(existing, weight ?? 0);
      }
    }
  }
  return out;
}

/**
 * Favourite item — a tier-3 popover entry.
 * `command` is the shell command string to run when invoked.
 * `stubbed` flags types that aren't in the kernel yet — the popover
 * surfaces a hint instead of dispatching.
 */
export interface Favourite {
  typeName: string;
  label: string;
  icon?: string;
  command: string;
  weight: number;
  stubbed?: boolean;
  stubNote?: string;
}

/**
 * Resolve favourites for a given context path, sorted by weight desc.
 * `max` caps the result (default 5 — the "tier-3 favourites" slot count).
 */
export function resolveFavourites(
  path: ContextPath,
  weights: Record<ContextPath, WeightMap> = KERNEL_CONTEXT_WEIGHTS,
  max: number = 5,
): Favourite[] {
  const entries = weights[path] ?? {};
  return Object.entries(entries)
    .filter(([, w]) => (w ?? 0) > 0)
    .sort(([, a], [, b]) => (b ?? 0) - (a ?? 0))
    .slice(0, max)
    .map(([typeName, weight]) => {
      const stubbed = STUB_TYPES.has(typeName);
      return {
        typeName,
        label: `New ${typeName}`,
        command: `new ${typeName}`,
        weight: weight ?? 0,
        stubbed,
        stubNote: stubbed ? STUB_NOTES[typeName] : undefined,
      };
    });
}

// ── Context metadata ─────────────────────────────────────────
//
// The 5 contexts under each intent. Used by Dock.svelte to render tier-2.
// Kept next to the weight maps so the 1-3-5 pyramid is a single
// source of truth.

export interface ContextDef<T extends string> {
  id: T;
  label: string;
  icon: string;
  description: string;
}

export const DO_CONTEXTS: ContextDef<DoContextId>[] = [
  { id: 'transact', label: 'Transact', icon: '⚡', description: 'Exchange value — settlements, invoices, payments' },
  { id: 'manage', label: 'Manage', icon: '⚙', description: 'Life and business ops — status transitions, approvals' },
  { id: 'create', label: 'Create', icon: '✎', description: 'Deep work — drafting, writing, building' },
  { id: 'play', label: 'Play', icon: '♟', description: 'Entertainment — games, challenges' },
  { id: 'offer', label: 'Offer', icon: '⚒', description: 'Publish listings — services, products, offerings' },
];

export const TALK_CONTEXTS: ContextDef<TalkContextId>[] = [
  { id: 'self', label: 'Self', icon: '◎', description: 'Reflection — goals, intentions, your Paskian graph' },
  { id: 'direct', label: 'Direct', icon: '↔', description: '1:1 encrypted connection with another identity' },
  { id: 'squad', label: 'Squad', icon: '⌂', description: 'Private group coordination — teams, study groups' },
  { id: 'agent', label: 'Agent', icon: '⌖', description: 'LLM interaction — ask the system to execute tasks' },
  { id: 'broadcast', label: 'Broadcast', icon: '◉', description: 'The town square — governance, public taxonomy' },
];

export const FIND_CONTEXTS: ContextDef<FindContextId>[] = [
  { id: 'memory', label: 'Memory', icon: '⦾', description: 'Your internal graph — past notes, sessions, insights' },
  { id: 'market', label: 'Market', icon: '☷', description: 'Public taxonomy — services, products, offerings' },
  { id: 'network', label: 'Network', icon: '⨁', description: 'Social graph — identities, hats, connections' },
  { id: 'value', label: 'Value', icon: '$', description: 'Economic graph — UTXOs, invoices, stakes' },
  { id: 'truth', label: 'Truth', icon: '✓', description: 'Provenance — evidence chains, proofs, audit trails' },
];

```
