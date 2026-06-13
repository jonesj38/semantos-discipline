---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/data/objectTypes.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.973343+00:00
---

# archive/apps-loom-react/src/navigator/data/objectTypes.ts

```ts
/** Object type definitions for the LLM system prompt (hidden from user) */
export const OBJECT_TYPES = `Release (LINEAR): rawText, themes[], emotionalValence(-1..1), processStepId, durationSeconds
Insight (RELEVANT): content, source(writing|connection|vacuum|meditation|llm), tags[], dimension?
Pattern (RELEVANT): description, occurrences, strength(0..1), sourceReleaseIds[]
Intention (AFFINE): statement, dimension?, deadline?
DailyReview (LINEAR): wins[], improvements[], tomorrowIntention, energyLevel(1-10), moodLevel(1-10), dimensionScores{}
MorningIntention (LINEAR): focusDimension, intention, concreteAction
DimensionPulse (AFFINE): dimension, score(1-10), note?
Session (LINEAR): sessionType, durationSeconds, processStepId?`;

export const OBJECT_ICONS: Record<string, string> = {
  Release: '↗',
  Insight: '✦',
  Pattern: '🔄',
  Intention: '🎯',
  DailyReview: '🌙',
  MorningIntention: '🌅',
  DimensionPulse: '📊',
  Session: '⏱',
};

export const FRIENDLY_TAGS: Record<string, { cls: string; icon: string; label: string }> = {
  Release:          { cls: 'released', icon: '↗', label: 'Released' },
  Insight:          { cls: 'kept',     icon: '✦', label: 'Insight saved' },
  Pattern:          { cls: 'kept',     icon: '🔄', label: 'Pattern noted' },
  Intention:        { cls: 'set',      icon: '🎯', label: 'Intention set' },
  DailyReview:      { cls: 'released', icon: '🌙', label: 'Review captured' },
  MorningIntention: { cls: 'set',      icon: '🌅', label: 'Intention set' },
  DimensionPulse:   { cls: 'set',      icon: '📊', label: 'Pulse recorded' },
  Session:          { cls: 'released', icon: '⏱', label: 'Session logged' },
};

```
