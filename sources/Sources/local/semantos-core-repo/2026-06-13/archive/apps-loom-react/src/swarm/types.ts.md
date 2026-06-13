---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.958319+00:00
---

# archive/apps-loom-react/src/swarm/types.ts

```ts
/**
 * Phase H5 — Swarm God View Dashboard types.
 *
 * Defines all interfaces consumed by dashboard components.
 * The h3EventAdapter maps Border Router wire events into these types.
 */

// ── Persona ──

export type PersonaId = 'nit' | 'maniac' | 'calculator' | 'apex';

export const PERSONA_COLORS: Record<PersonaId, string> = {
  nit:        '#3366ff',   // Blue
  maniac:     '#ff3333',   // Red
  calculator: '#33cc33',   // Green
  apex:       '#ffcc00',   // Gold
} as const;

export const PERSONA_LABELS: Record<PersonaId, string> = {
  nit:        'Nit',
  maniac:     'Maniac',
  calculator: 'Calculator',
  apex:       'Apex',
} as const;

// ── Node / Edge (Topology) ──

export interface NodeData {
  id: string;                    // 'bot-0' .. 'bot-24', 'border-router'
  persona: PersonaId | 'router';
  heartbeat: number;             // last heartbeat timestamp (ms)
  uptime: number;                // seconds online
  activeTable?: string;          // table id if seated
  bankroll?: number;             // current sats
  cellCount: number;             // cells published by this node
}

export interface EdgeData {
  source: string;
  target: string;
  cellCount: number;
  lastFlash: number;             // timestamp of last flash animation trigger
}

// ── Stats ──

export interface StatsUpdate {
  timestamp: number;
  tps: number;                   // cells/second
  totalCellsPublished: number;
  totalBatchesAnchored: number;
  avgCellsPerBatch: number;
}

// ── Persona Stats ──

export interface PersonaStats {
  balance: number;
  handsPlayed: number;
  handsWon: number;
  winRate: number;               // 0.0 to 1.0
  policyVersion: number;         // Apex only; increments on hot-swap
  recentBalances: number[];      // last 20 balance snapshots
}

export interface PersonaStatsUpdate {
  timestamp: number;
  personas: Record<PersonaId, PersonaStats>;
}

// ── Hand ──

export interface HandCompletedEvent {
  type: 'hand.completed';
  timestamp: number;
  handId: string;
  tableId: string;
  players: Array<{ botIndex: number; persona: PersonaId }>;
  winner: { botIndex: number; persona: PersonaId };
  potSize: number;
  reason: string;
  actions: number;
  bsvTxid: string;
  violation?: { type: string; details: string };
}

// ── Batch / Anchor ──

export interface BatchAnchoredEvent {
  type: 'batch.anchored';
  timestamp: number;
  batchNumber: number;
  cellCount: number;
  merkleRoot: string;
  bsvTxid: string;
  merkleParent?: string;
}

// ── H3 Wire Protocol ──

export type H3EventType = 'welcome' | 'cell' | 'batch' | 'anchor' | 'anchor_failed' | 'stats';

export interface H3WsMessage {
  type: H3EventType;
  data: unknown;
  timestamp: number;
}

export interface H3CellData {
  cellId: string;
  semanticPath: string;
  sourceAddr: string;
  receivedAt: number;
  linearity: number;
  contentHash: string;
}

export interface H3BatchData {
  batchId: string;
  cellCount: number;
  openedAt: number;
  closedAt: number;
  merkleRoot: string;
}

export interface H3AnchorData {
  batchId: string;
  merkleRoot: string;
  txid: string | null;
  leafCount: number;
  status: 'pending' | 'submitted' | 'confirmed' | 'failed';
}

export interface H3StatsData {
  cellsPerSecond: number;
  totalCellsCollected: number;
  totalCellsAnchored: number;
  totalBatches: number;
  totalAnchors: number;
  currentBatchSize: number;
  currentBatchAgeMs: number;
  uniquePlayers: number;
  uptimeMs: number;
}

// ── Connection ──

export type SwarmConnectionStatus = 'connecting' | 'connected' | 'disconnected' | 'error';

// ── Dashboard State ──

export interface SwarmDashboardState {
  connection: SwarmConnectionStatus;
  wsUrl: string;
  lastHeartbeat: number;

  // Topology
  nodes: NodeData[];
  edges: EdgeData[];

  // Stats
  stats: StatsUpdate;
  tpsHistory: number[];          // ring buffer of tps samples (max 60)

  // Persona stats
  personaStats: PersonaStatsUpdate;

  // Hands
  hands: HandCompletedEvent[];   // ring buffer (max 100)

  // Anchor chain
  batches: BatchAnchoredEvent[]; // ring buffer (max 10)

  // Selection
  selectedNodeId: string | null;
}

export function createInitialState(): SwarmDashboardState {
  const defaultPersonaStats: PersonaStats = {
    balance: 1000,
    handsPlayed: 0,
    handsWon: 0,
    winRate: 0,
    policyVersion: 1,
    recentBalances: [1000],
  };

  return {
    connection: 'disconnected',
    wsUrl: import.meta.env.VITE_SWARM_WS_URL ?? 'ws://localhost:8081',
    lastHeartbeat: 0,

    nodes: [],
    edges: [],

    stats: {
      timestamp: 0,
      tps: 0,
      totalCellsPublished: 0,
      totalBatchesAnchored: 0,
      avgCellsPerBatch: 0,
    },
    tpsHistory: [],

    personaStats: {
      timestamp: 0,
      personas: {
        nit: { ...defaultPersonaStats },
        maniac: { ...defaultPersonaStats },
        calculator: { ...defaultPersonaStats },
        apex: { ...defaultPersonaStats },
      },
    },

    hands: [],
    batches: [],
    selectedNodeId: null,
  };
}

```
