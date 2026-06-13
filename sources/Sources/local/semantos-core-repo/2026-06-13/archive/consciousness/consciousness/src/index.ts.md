---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/consciousness/consciousness/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.721120+00:00
---

# archive/consciousness/consciousness/src/index.ts

```ts
/**
 * @semantos/consciousness — Consciousness Process Extension
 *
 * Models the self as a semantic object undergoing release/receive cycles.
 * Consumption semantics map directly to personal development:
 *
 *   LINEAR  → things you release (consumed once, gone, the kernel enforces it)
 *   AFFINE  → intentions you set (acknowledge or discard, both valid)
 *   RELEVANT → wisdom you receive (persists, accumulates, revocable when outgrown)
 *
 * @module @semantos/consciousness
 */

// ─── Core Types ─────────────────────────────────────────────────────
export type {
  Release,
  Session,
  SessionPractice,
  Intention,
  IntentionMeta,
  Insight,
  Pattern,
  Connection,
  VacuumSession,
  GoldSeal,
  ReleaseConsumptionProof,
  SessionConsumptionProof,
  ReleaseExtractionResult,
  JournalPhotoExtractionResult,
} from './types/consciousness-objects.js';

export {
  ElevationLevel,
  LifeDimension,
  SELF_INQUIRY,
  RELEASE_WRITING,
  ATTENTION_TRAINING,
  ENERGETIC_PRACTICE,
  CONNECTION_RECEIVING,
} from './types/consciousness-objects.js';

export type {
  ReleaseSource,
  ReleasePrompt,
  ConnectionTarget,
  PatternCategory,
} from './types/consciousness-objects.js';

// ─── Accountability Types ───────────────────────────────────────────
export type {
  DailyReview,
  ReviewItem,
  MorningIntention,
  DimensionPulse,
  AccountabilityStreak,
  AccountabilityInteraction,
} from './types/accountability.js';

export {
  ACCOUNTABILITY_STRENGTHS,
  DEFAULT_SCHEDULE,
  toAccountabilityInteraction,
  reviewToInteractions,
  morningToInteractions,
  pulseToInteraction,
} from './types/accountability.js';

// ─── Tower Data ────────────────────────────────────────────────────
export type { TowerLayer } from './tower-data.js';

export {
  CONSCIOUSNESS_TOWER,
  ELEVATION_TO_LAYERS,
} from './tower-data.js';

// ─── LLM Extraction ────────────────────────────────────────────────
export {
  RELEASE_EXTRACTION_SYSTEM_PROMPT,
  JOURNAL_PHOTO_SYSTEM_PROMPT,
  buildReleaseExtractionPrompt,
  buildJournalPhotoPrompt,
  parseExtractionResult,
  parseJournalPhotoResult,
} from './extraction.js';

// ─── Paskian Bridge ────────────────────────────────────────────────
export type {
  PaskianInteractionSink,
  PaskianGraphQuery,
  DimensionInsight,
} from './paskian-bridge.js';

export {
  ConsciousnessPaskianBridge,
  dimensionCellId,
  dimensionTypePath,
  generateDimensionInsights,
} from './paskian-bridge.js';

```
