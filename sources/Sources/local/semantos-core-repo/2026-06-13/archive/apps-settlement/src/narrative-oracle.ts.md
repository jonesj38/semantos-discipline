---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/narrative-oracle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.708350+00:00
---

# archive/apps-settlement/src/narrative-oracle.ts

```ts
/**
 * NarrativeOracle — Claude prompt-caching bridge (interface stub).
 *
 * This defines the contract for the Claude API integration that
 * translates Paskian constraint state into narrative decisions.
 * The implementation is deferred — this file is the typed interface
 * that the game layer codes against.
 *
 * Architecture:
 *
 *   Cached context (paid once, persists across interactions):
 *     — world lore (RELEVANT cells)
 *     — constraint graph structure
 *     — relationship DAGs
 *     — Paskian stability state
 *
 *   Per-interaction delta (tiny, fast):
 *     — what just happened
 *     — which constraints were affected
 *     — what the player is doing
 *
 *   Response:
 *     — which narrative threads strengthen/weaken
 *     — which entities to create or consume
 *     — what the world says back to the player
 *
 * The prompt caching angle (from the associate's requirements):
 *   Claude's prompt caching keeps the entire world state in cached
 *   context. Each interaction only sends the delta. The model has
 *   full world memory without re-sending everything.
 *
 * Cross-references:
 *   adapter.ts   — PaskianAdapter (feeds constraint state)
 *   store.ts     — PaskianStore (provides graph snapshots)
 *   grammar.ts   — type paths for cell creation
 */

import type { PaskianNode, PaskianEdge, StableThread, EmergingThread } from './types';

// ── World context (cached portion) ─────────────────────────────────────

/**
 * The static world context that gets cached in the Claude prompt.
 * This is rebuilt when the world structure changes significantly
 * (new stable thread, major pruning event) but NOT on every interaction.
 */
export interface WorldContext {
  /** All stable threads — the world's persistent memory. */
  stableThreads: StableThread[];
  /** All active (non-pruned) nodes in the constraint graph. */
  activeNodes: PaskianNode[];
  /** All edges in the constraint graph. */
  edges: PaskianEdge[];
  /** World lore and background (free-form text, from RELEVANT cells). */
  lore: string;
  /** Named relationships between entities. */
  relationships: Array<{
    from: string;
    to: string;
    kind: string;
    strength: number;
  }>;
}

// ── Interaction delta (per-request portion) ────────────────────────────

/**
 * The per-interaction delta sent to Claude alongside the cached context.
 * This is small — typically < 500 tokens.
 */
export interface InteractionDelta {
  /** What the player just did. */
  playerAction: string;
  /** Which cells were directly affected. */
  affectedCells: string[];
  /** Constraint changes from this interaction. */
  constraintDeltas: Array<{
    edgeId: string;
    delta: number;
    fromNode: string;
    toNode: string;
  }>;
  /** Emerging threads that are gaining momentum. */
  emergingThreads: EmergingThread[];
  /** Recently pruned nodes (world forgetting). */
  recentPrunings: string[];
}

// ── Oracle response ────────────────────────────────────────────────────

/**
 * What the oracle returns: narrative decisions that feed back
 * into the Paskian graph as new interactions.
 */
export interface NarrativeResponse {
  /** The world's narrative response to the player (displayed text). */
  narrative: string;
  /** Threads to strengthen (positive interaction events). */
  strengthen: Array<{
    cellId: string;
    amount: number;
    reason: string;
  }>;
  /** Threads to weaken (negative interaction events). */
  weaken: Array<{
    cellId: string;
    amount: number;
    reason: string;
  }>;
  /** New entities to create (returned as creation specs). */
  create: Array<{
    typePath: string;
    name: string;
    metadata: Record<string, unknown>;
    relatedTo: string[];
  }>;
  /** Entities to consume (AFFINE destruction or LINEAR spend). */
  consume: Array<{
    cellId: string;
    reason: string;
  }>;
}

// ── Oracle interface ───────────────────────────────────────────────────

/**
 * The NarrativeOracle interface.
 *
 * Implementations will:
 *   1. Maintain a prompt cache with WorldContext
 *   2. Send InteractionDelta on each player action
 *   3. Parse the response into NarrativeResponse
 *   4. Feed strengthen/weaken back into PaskianAdapter.interact()
 *
 * The stub implementation (below) returns no-op responses so the
 * system can run without Claude connected.
 */
export interface NarrativeOracle {
  /**
   * Update the cached world context.
   * Called when the graph structure changes significantly.
   */
  updateContext(context: WorldContext): Promise<void>;

  /**
   * Generate a narrative response for a player interaction.
   * Uses prompt caching — the context is already loaded.
   */
  narrate(delta: InteractionDelta): Promise<NarrativeResponse>;

  /**
   * Check whether the oracle is connected and ready.
   */
  isReady(): boolean;
}

// ── Stub implementation ────────────────────────────────────────────────

/**
 * No-op oracle that returns empty responses.
 * Used when Claude is not connected — the Paskian graph still
 * operates purely from player interaction, just without
 * AI-generated narrative.
 */
export class StubNarrativeOracle implements NarrativeOracle {
  async updateContext(_context: WorldContext): Promise<void> {
    // no-op
  }

  async narrate(_delta: InteractionDelta): Promise<NarrativeResponse> {
    return {
      narrative: '',
      strengthen: [],
      weaken: [],
      create: [],
      consume: [],
    };
  }

  isReady(): boolean {
    return false;
  }
}

```
