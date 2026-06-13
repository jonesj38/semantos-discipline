---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/hooks/useDimensions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.961760+00:00
---

# archive/apps-loom-react/src/hooks/useDimensions.ts

```ts
export const DIMENSION_IDS = ['mind', 'body', 'spirit', 'tribe', 'home', 'craft', 'wealth'] as const;
export type DimensionId = (typeof DIMENSION_IDS)[number];

export const DIMENSION_META: Record<DimensionId, { emoji: string; label: string; color: string; group: string }> = {
  mind:   { emoji: '🧠', label: 'Mind',   color: '#818cf8', group: 'Self' },
  body:   { emoji: '💪', label: 'Body',   color: '#f472b6', group: 'Self' },
  spirit: { emoji: '✨', label: 'Spirit', color: '#c084fc', group: 'Self' },
  tribe:  { emoji: '👥', label: 'Tribe',  color: '#fb923c', group: 'Connection' },
  home:   { emoji: '🏠', label: 'Home',   color: '#4ade80', group: 'Connection' },
  craft:  { emoji: '🎨', label: 'Craft',  color: '#facc15', group: 'Creation' },
  wealth: { emoji: '💎', label: 'Wealth', color: '#38bdf8', group: 'Creation' },
};

export const DIMENSION_ENUM_MAP: Record<string, DimensionId> = {
  MENTAL: 'mind',
  PHYSICAL: 'body',
  SPIRITUAL: 'spirit',
  SOCIAL: 'tribe',
  VOCATIONAL: 'craft',
  FINANCIAL: 'wealth',
  FAMILIAL: 'home',
};

export const DIMENSION_GROUPS: Record<string, DimensionId[]> = {
  Self: ['mind', 'body', 'spirit'],
  Connection: ['tribe', 'home'],
  Creation: ['craft', 'wealth'],
};

/** Dimensions in the "old" enum format used by overlays */
export const DIMENSIONS_ENUM = [
  { id: 'mental',     emoji: '🧠', label: 'Mental' },
  { id: 'physical',   emoji: '💪', label: 'Physical' },
  { id: 'spiritual',  emoji: '🙏', label: 'Spiritual' },
  { id: 'social',     emoji: '🤝', label: 'Social' },
  { id: 'vocational', emoji: '🎯', label: 'Vocational' },
  { id: 'financial',  emoji: '💰', label: 'Financial' },
  { id: 'familial',   emoji: '❤️', label: 'Family' },
] as const;

```
