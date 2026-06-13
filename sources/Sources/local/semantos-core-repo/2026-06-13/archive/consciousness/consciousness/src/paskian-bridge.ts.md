---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/consciousness/consciousness/src/paskian-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.721417+00:00
---

# archive/consciousness/consciousness/src/paskian-bridge.ts

```ts
/**
 * Paskian Bridge: Connects accountability events to the constraint graph.
 *
 * Each dimension becomes a PaskianNode. Accountability events become
 * interactions. The Paskian adapter handles constraint propagation,
 * stability detection, and pruning automatically.
 *
 * @module @semantos/consciousness/paskian-bridge
 */

import { LifeDimension } from './types/consciousness-objects.js';
import type {
  AccountabilityInteraction,
  DailyReview,
  MorningIntention,
  DimensionPulse,
} from './types/accountability.js';
import {
  reviewToInteractions,
  morningToInteractions,
  pulseToInteraction,
} from './types/accountability.js';

// ─── Node ID Convention ─────────────────────────────────────────────

const TYPE_PREFIX = 'consciousness.dimension';

/**
 * Generate the Paskian cell ID for a dimension.
 * Convention: `con-dim-{DIMENSION}` (e.g., `con-dim-PHYSICAL`)
 */
export function dimensionCellId(dim: LifeDimension): string {
  return `con-dim-${dim}`;
}

/**
 * Generate the type path for a dimension node.
 */
export function dimensionTypePath(dim: LifeDimension): string {
  return `${TYPE_PREFIX}.${dim.toLowerCase()}`;
}

// ─── Paskian Interaction Adapter ────────────────────────────────────

export interface PaskianInteractionSink {
  interact(interaction: {
    cellId: string;
    kind: string;
    strength: number;
    relatedCells?: string[];
    metadata?: Record<string, unknown>;
  }): Promise<void>;
}

/**
 * ConsciousnessPaskianBridge: Translates accountability events into
 * Paskian graph interactions.
 */
export class ConsciousnessPaskianBridge {
  private sink: PaskianInteractionSink;

  constructor(sink: PaskianInteractionSink) {
    this.sink = sink;
  }

  async processReview(review: DailyReview): Promise<string[]> {
    const interactions = reviewToInteractions(review);
    const ids: string[] = [];
    for (const interaction of interactions) {
      const id = await this.pushInteraction(interaction);
      ids.push(id);
    }
    return ids;
  }

  async processMorning(morning: MorningIntention): Promise<string[]> {
    const interactions = morningToInteractions(morning);
    const ids: string[] = [];
    for (const interaction of interactions) {
      const id = await this.pushInteraction(interaction);
      ids.push(id);
    }
    return ids;
  }

  async processPulse(pulse: DimensionPulse): Promise<string> {
    const interaction = pulseToInteraction(pulse);
    return this.pushInteraction(interaction);
  }

  private async pushInteraction(interaction: AccountabilityInteraction): Promise<string> {
    const cellId = dimensionCellId(interaction.dimension);
    const relatedCells = interaction.relatedDimensions.map(dimensionCellId);

    await this.sink.interact({
      cellId,
      kind: interaction.source,
      strength: interaction.strength,
      relatedCells: relatedCells.length > 0 ? relatedCells : undefined,
      metadata: interaction.metadata,
    });

    return `${cellId}-${interaction.source}-${Date.now()}`;
  }
}

// ─── Insight Generation from Graph State ────────────────────────────

export interface PaskianGraphQuery {
  stableThreads(): Promise<Array<{ cellId: string; hState: number; totalConstraintStrength: number }>>;
  emergingThreads(window: number): Promise<Array<{ cellId: string; hState: number; momentum: number }>>;
  pruningCandidates(threshold: number): Promise<Array<{ cellId: string; hState: number }>>;
  edgesFor(cellId: string): Promise<Array<{ fromCell: string; toCell: string; constraintWeight: number }>>;
}

export interface DimensionInsight {
  dimension: LifeDimension;
  status: 'stabilized' | 'emerging' | 'declining' | 'pruning-candidate' | 'dormant';
  narrative: string;
  reinforcedBy: LifeDimension[];
  competingWith: LifeDimension[];
}

export async function generateDimensionInsights(
  query: PaskianGraphQuery,
): Promise<DimensionInsight[]> {
  const ALL_DIMENSIONS = Object.values(LifeDimension);

  const stable = await query.stableThreads();
  const emerging = await query.emergingThreads(7 * 24 * 60 * 60 * 1000);
  const pruning = await query.pruningCandidates(-0.3);

  const stableIds = new Set(stable.map(s => s.cellId));
  const emergingIds = new Set(emerging.map(e => e.cellId));
  const pruningIds = new Set(pruning.map(p => p.cellId));

  const insights: DimensionInsight[] = [];

  for (const dim of ALL_DIMENSIONS) {
    const cellId = dimensionCellId(dim);
    const edges = await query.edgesFor(cellId);

    const reinforcedBy: LifeDimension[] = [];
    const competingWith: LifeDimension[] = [];

    for (const edge of edges) {
      const otherCellId = edge.fromCell === cellId ? edge.toCell : edge.fromCell;
      const otherDim = cellIdToDimension(otherCellId);
      if (!otherDim) continue;

      if (edge.constraintWeight > 0.1) {
        reinforcedBy.push(otherDim);
      } else if (edge.constraintWeight < -0.1) {
        competingWith.push(otherDim);
      }
    }

    let status: DimensionInsight['status'];
    let narrative: string;

    if (stableIds.has(cellId)) {
      status = 'stabilized';
      const reinforceText = reinforcedBy.length > 0
        ? ` Reinforced by ${reinforcedBy.map(formatDimension).join(' and ')}.`
        : '';
      narrative = `${formatDimension(dim)} has stabilized — this is becoming natural for you.${reinforceText}`;
    } else if (emergingIds.has(cellId)) {
      status = 'emerging';
      narrative = `${formatDimension(dim)} is gaining momentum. Keep the attention here.`;
    } else if (pruningIds.has(cellId)) {
      status = 'pruning-candidate';
      const competeText = competingWith.length > 0
        ? ` It may be competing with ${competingWith.map(formatDimension).join(' and ')}.`
        : '';
      narrative = `${formatDimension(dim)} has been declining. Consider deprioritizing or recommitting.${competeText}`;
    } else if (edges.length === 0) {
      status = 'dormant';
      narrative = `${formatDimension(dim)} hasn't been active yet. Start with a pulse check-in.`;
    } else {
      status = 'declining';
      narrative = `${formatDimension(dim)} is present but not building momentum.`;
    }

    insights.push({ dimension: dim, status, narrative, reinforcedBy, competingWith });
  }

  return insights;
}

function cellIdToDimension(cellId: string): LifeDimension | null {
  const match = cellId.match(/^con-dim-(\w+)$/);
  if (!match) return null;
  const dim = match[1] as LifeDimension;
  return Object.values(LifeDimension).includes(dim) ? dim : null;
}

function formatDimension(dim: LifeDimension): string {
  return dim.charAt(0) + dim.slice(1).toLowerCase();
}

```
