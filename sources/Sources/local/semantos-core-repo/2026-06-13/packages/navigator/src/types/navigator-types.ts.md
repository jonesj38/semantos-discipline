---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/navigator/src/types/navigator-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.441806+00:00
---

# packages/navigator/src/types/navigator-types.ts

```ts
/**
 * Navigator Core Types: Lenses, object presentation, and consumer binding.
 *
 * The navigator is like Finder/Explorer — it renders any extension's
 * semantic objects. Lenses are the primitive for attention allocation:
 * they filter, group, and prioritize objects for the presentation layer.
 *
 * The 7 default lenses (Mind, Body, Spirit, Tribe, Home, Craft, Wealth)
 * represent fundamental dimensions of attention. Extensions register
 * their object types against lenses so the navigator knows how to
 * organize them. The navigator doesn't track state per lens — extensions
 * do that. The navigator just knows how to filter and present.
 *
 * @module @semantos/navigator/types
 */

// ─── Lenses ─────────────────────────────────────────────────────────

/**
 * A navigation lens — a dimension of attention that objects can be viewed through.
 *
 * Lenses are the organizing primitive of the navigator. Every semantic object
 * can be tagged with one or more lens IDs. The UI groups, filters, and
 * prioritizes based on which lens is active.
 *
 * The default lens set covers the 7 life dimensions, but extensions can
 * register additional lenses for their domain.
 */
export interface Lens {
  /** Unique identifier (e.g. 'mind', 'body', 'craft'). */
  id: string;

  /** Display label. */
  label: string;

  /** Emoji icon for compact display. */
  emoji: string;

  /** Theme color (hex). */
  color: string;

  /** Group this lens belongs to (for visual clustering). */
  group: string;
}

/**
 * A group of related lenses.
 * The navigator presents lenses in groups (e.g. Self, Connection, Creation).
 */
export interface LensGroup {
  /** Group identifier. */
  id: string;

  /** Display label. */
  label: string;

  /** Ordered lens IDs in this group. */
  lensIds: string[];
}

// ─── Default Lens Set ───────────────────────────────────────────────

/**
 * The 7 default navigation lenses — fundamental dimensions of attention.
 *
 * These aren't consciousness-specific. They're how any human organizes
 * their life: what they think about (mind), what they do physically (body),
 * what gives meaning (spirit), who they're connected to (tribe),
 * where they live (home), what they build (craft), what they earn (wealth).
 *
 * Extensions map their object types to these lenses so the navigator
 * can organize objects across any domain.
 */
export const DEFAULT_LENSES: Lens[] = [
  { id: 'mind',   label: 'Mind',   emoji: '🧠', color: '#818cf8', group: 'self' },
  { id: 'body',   label: 'Body',   emoji: '💪', color: '#f472b6', group: 'self' },
  { id: 'spirit', label: 'Spirit', emoji: '✨', color: '#c084fc', group: 'self' },
  { id: 'tribe',  label: 'Tribe',  emoji: '👥', color: '#fb923c', group: 'connection' },
  { id: 'home',   label: 'Home',   emoji: '🏠', color: '#4ade80', group: 'connection' },
  { id: 'craft',  label: 'Craft',  emoji: '🎨', color: '#facc15', group: 'creation' },
  { id: 'wealth', label: 'Wealth', emoji: '💎', color: '#38bdf8', group: 'creation' },
];

/**
 * Default lens groups — how the 7 lenses cluster visually.
 */
export const DEFAULT_LENS_GROUPS: LensGroup[] = [
  { id: 'self',       label: 'Self',       lensIds: ['mind', 'body', 'spirit'] },
  { id: 'connection', label: 'Connection', lensIds: ['tribe', 'home'] },
  { id: 'creation',   label: 'Creation',   lensIds: ['craft', 'wealth'] },
];

/**
 * Mapping from extension dimension enum values to navigator lens IDs.
 * Extensions use uppercase enum names (MENTAL, PHYSICAL, etc.);
 * the navigator uses lowercase lens IDs (mind, body, etc.).
 */
export const DIMENSION_TO_LENS: Record<string, string> = {
  'MENTAL':     'mind',
  'PHYSICAL':   'body',
  'SPIRITUAL':  'spirit',
  'SOCIAL':     'tribe',
  'VOCATIONAL': 'craft',
  'FINANCIAL':  'wealth',
  'FAMILIAL':   'home',
};

// ─── Object Presentation ────────────────────────────────────────────

/**
 * How a semantic object should be presented in the navigator.
 * Extensions can register presentation hints for their types.
 */
export interface ObjectPresentation {
  /** The object's primary text (title or summary). */
  title: string;

  /** Secondary text (description, preview). */
  subtitle?: string;

  /** Which lens IDs this object is relevant to. */
  lensIds: string[];

  /** Object type name (for icon/badge rendering). */
  typeName: string;

  /** Timestamp for sorting. */
  timestamp: number;

  /** The underlying object ID. */
  objectId: string;
}

```
