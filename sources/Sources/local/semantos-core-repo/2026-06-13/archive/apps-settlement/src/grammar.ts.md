---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/grammar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.706272+00:00
---

# archive/apps-settlement/src/grammar.ts

```ts
/**
 * Paskian Story Grammar
 *
 * Defines the vertical grammar for Paskian learning over the cell model.
 * Each node type maps to a linearity class; each constraint edge maps to
 * a RELEVANT cell; every stability event and pruning action corresponds
 * to a cell state transition.
 *
 * The grammar is domain-agnostic at the base level — `paskian.graph.*`
 * types describe the constraint graph itself. The `paskian.story.*`
 * extension adds narrative semantics for MUD/interactive fiction use.
 *
 * Cross-references:
 *   configs/extensions/core.json  — core object types
 *   cell-ops/typeHashRegistry.ts — LINEARITY constants
 *   cell-engine/linearity.zig    — runtime enforcement
 */

import { LINEARITY, type Linearity } from '../../cell-ops/src/typeHashRegistry';

// ── Paskian tuning parameters ──────────────────────────────────────────

export interface PaskianConfig {
  /** Constraint weakening rate below which a node is pruned. */
  pruneThreshold: number;
  /** ΔH threshold below which a node is considered stable. */
  stabilityEpsilon: number;
  /** Minimum interaction count before stability can be declared. */
  minInteractions: number;
  /** Number of propagation iterations per interaction (k in the paper). */
  propagationDepth: number;
  /** Learning rate for constraint effect calculation. */
  learningRate: number;
  /** Time window (ms) for stability calculation. */
  stabilityWindow: number;
}

export const DEFAULT_PASKIAN_CONFIG: PaskianConfig = {
  pruneThreshold: -0.3,
  stabilityEpsilon: 0.01,
  minInteractions: 5,
  propagationDepth: 3,
  learningRate: 0.1,
  stabilityWindow: 60_000,
};

// ── Type path definitions ──────────────────────────────────────────────

/**
 * Base graph types — domain-agnostic Paskian graph primitives.
 * These correspond to the paper's G = (V, E) formulation.
 */
export const PASKIAN_GRAPH_TYPES = {
  /** A node in the constraint graph. h_i state. */
  'paskian.graph.node':        LINEARITY.RELEVANT,
  /** An edge / constraint relation C_ij. */
  'paskian.graph.edge':        LINEARITY.RELEVANT,
  /** A stability event — node declared stable (ΔH ≈ 0). */
  'paskian.graph.stable':      LINEARITY.RELEVANT,
  /** A pruning event — node/edge removed for weakness. */
  'paskian.graph.pruned':      LINEARITY.LINEAR,
} as const satisfies Record<string, Linearity>;

/**
 * Story extension — narrative semantics layered on the constraint graph.
 * These are the game-facing types that a MUD / interactive fiction system
 * would use.
 */
export const PASKIAN_STORY_TYPES = {
  /** Narrative thread — persists as long as it's engaged. */
  'paskian.story.thread':      LINEARITY.RELEVANT,
  /** Unique story artifact — can only be found/used once. */
  'paskian.story.artifact':    LINEARITY.LINEAR,
  /** Character, scene, or transient story element. */
  'paskian.story.entity':      LINEARITY.AFFINE,
  /** Constraint edge between story elements. */
  'paskian.story.relation':    LINEARITY.RELEVANT,
  /** One-time story event (plot point, revelation). */
  'paskian.story.moment':      LINEARITY.LINEAR,
} as const satisfies Record<string, Linearity>;

// ── Anchor policy ──────────────────────────────────────────────────────

export interface AnchorPolicy {
  /** Cell operations that require BSV anchoring. */
  requireAnchorOn: string[];
  /** Compliance events that trigger BSV write. */
  complianceEvents: string[];
  /** Batch interval (ms) for non-urgent anchors. */
  batchInterval: number;
}

export const DEFAULT_ANCHOR_POLICY: AnchorPolicy = {
  requireAnchorOn: ['linear_consume', 'ownership_transfer'],
  complianceEvents: ['thread_stabilised', 'entity_pruned', 'artifact_found'],
  batchInterval: 30_000,
};

// ── Combined grammar export ────────────────────────────────────────────

export interface PaskianGrammar {
  verticalId: string;
  types: Record<string, Linearity>;
  anchorPolicy: AnchorPolicy;
  paskian: PaskianConfig;
}

/**
 * The complete Paskian story grammar.
 *
 * Usage:
 *   import { PaskianStoryGrammar } from '@semantos/settlement';
 *   const linearity = PaskianStoryGrammar.types['paskian.story.artifact'];
 *   // → 1 (LINEAR)
 */
export const PaskianStoryGrammar: PaskianGrammar = {
  verticalId: 'paskian.story',
  types: {
    ...PASKIAN_GRAPH_TYPES,
    ...PASKIAN_STORY_TYPES,
  },
  anchorPolicy: DEFAULT_ANCHOR_POLICY,
  paskian: DEFAULT_PASKIAN_CONFIG,
};

```
