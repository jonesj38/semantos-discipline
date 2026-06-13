---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/hackathon/PHASE-H5-SWARM-DASHBOARD.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.761759+00:00
---

# Phase H5 — Swarm God View Dashboard (Presentation Layer)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 2–3 days
**Prerequisites**: Phase H3 (Border Router Overlay API) complete, Phase H4 (Apex Agent PolicyEvolutionChain) complete, Phase 26 (React loom) available
**Master document**: `HACKATHON-PRD.md`
**Branch**: `hackathon/h5-swarm-dashboard`

---

## Context

The Semantos Swarm hackathon demo runs 25 autonomous poker bots on a Docker multicast mesh (Phase H1), each with a distinct persona (Nit, Maniac, Calculator, Apex). The bots negotiate poker tables, play hands, and anchor game state to BSV every 30 seconds. Today, judges see text logs. Phase H5 makes the invisible math visceral.

This phase builds a dark-mode React dashboard that connects to the Border Router's Overlay API via WebSocket. Five interactive panels show swarm topology, live transaction rates, persona leaderboard, hand feed, and anchor chain — all updating in real-time as the 25 nodes play.

### The Problem (What This Solves)

Raw transaction logs are unreadable. Judges watching the demo see:

```
[2026-04-11T14:23:45.123Z] poker.shuffle CELL_PUBLISHED source=bot-3
[2026-04-11T14:23:45.128Z] poker.action CELL_PUBLISHED source=bot-8
[2026-04-11T14:23:45.134Z] poker.shuffle CELL_PUBLISHED source=bot-15
...7000 more lines...
```

They have no way to:
- See which agents are winning (Apex Agent dominance moment)
- Understand transaction volume (aiming for 1.5M cells in 24 hours)
- Track multi-bot poker tables (which nodes are playing together)
- Verify anchoring to BSV (did the hand settle on-chain?)
- Witness the Apex Agent's policy evolving in real-time

Phase H5 answers all four with a unified visualization dashboard that runs in a browser, connects to a live WebSocket feed, and renders the swarm as a force-directed graph with overlaid metrics.

### Why This Matters for the Hackathon

The Semantos platform's core value is **trustless, multi-agent coordination under resource constraints**. The dashboard makes this visible:

1. **Topology visibility** — Judges can see 25 autonomous nodes self-organizing into poker tables via multicast discovery (Phase H1 NetworkAdapter)
2. **Policy evolution** — Judges watch the Apex Agent's policy version increment every ~2 minutes as PolicyEvolutionChain (Phase H4) hot-swaps winning strategies
3. **Economic flow** — Persona leaderboard shows which strategy wins; gold bars animate as each agent's bankroll changes
4. **Proof of work** — Anchor chain proves every hand settles to BSV with Merkle roots and txids (no trusted intermediary)
5. **Competitive narrative** — Hand feed shows which persona won which hand, making the swarm feel like a real tournament, not a simulation

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│         Swarm God View Dashboard (React, Vite)              │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │               SWARM TOPOLOGY                         │  │
│  │        (Force-directed D3 graph / canvas)            │  │
│  │   25 nodes as circles, edges flash on multicast      │  │
│  │   Colored by persona: blue=Nit, red=Maniac, etc      │  │
│  │   Central hub = Border Router with BSV anchor link   │  │
│  │                                                      │  │
│  │  ┌──────────┐   ┌──────────┐   ┌──────────┐        │  │
│  │  │  bot-0   │   │  bot-1   │   │  bot-24  │        │  │
│  │  │  (Nit)   │───│(Maniac)  │───│ (Apex)   │        │  │
│  │  └──────────┘   └──────────┘   └──────────┘        │  │
│  │       ↓               ↓               ↓             │  │
│  │  [Active table t1: 2 players, hand 47]            │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────┐  ┌─────────────────────────┐  │
│  │    LIVE TPS COUNTER    │  │  PERSONA LEADERBOARD    │  │
│  │                        │  │                         │  │
│  │   1,247 TPS ▲          │  │ 1. Maniac   847 sats    │  │
│  │   [█████░░░░░░] 1.5M   │  │ 2. Apex     821 sats    │  │
│  │   ETA: 4h 23m          │  │ 3. Nit      634 sats    │  │
│  │   23 batches → BSV     │  │ 4. Calc     501 sats    │  │
│  │                        │  │                         │  │
│  │   Sparkline:           │  │ Apex policy v17, dom +3% │  │
│  │   ▁▂▃▃▂▄▆█▇▆▅▄▃▂▁▀     │  │                         │  │
│  └────────────────────────┘  └─────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           HAND FEED                                 │  │
│  │                                                      │  │
│  │  ✓ Hand #2847: t1 Maniac→Nit    pot:120 [↗]       │  │
│  │    winner: Maniac | turn 1 / 1.4x wtd     [...]    │  │
│  │                                                      │  │
│  │  ✓ Hand #2846: t3 Calc→Calc→Apex pot:82  [↗]       │  │
│  │    winner: Apex  | flop 2 / best hand      [...]    │  │
│  │                                                      │  │
│  │  ✗ Hand #2845: t2 Nit→Calc       pot:64  [↗]       │  │
│  │    winner: Calc  | river 2 / opponent shove [...]  │  │
│  │                                                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           ANCHOR CHAIN                              │  │
│  │                                                      │  │
│  │  [Batch 23]──[Batch 24]──[Batch 25] (New)          │  │
│  │   847 cells    901 cells    445 cells               │  │
│  │   Root:5a3e... Root:7b2c...  Root:9d1f...          │  │
│  │   BSV:tx1... BSV:tx2... BSV:tx3...                 │  │
│  │   2h ago     1h ago     <1s ago                     │  │
│  │                                                      │  │
│  │   [→ View on WhatsOnChain]                          │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
        ↓ WebSocket (ws://localhost:9001/ws/live) ← Border Router
```

---

## Source Files / References

| Alias | Path | What to reference |
|-------|------|------------------|
| `MASTER:HACK` | `docs/prd/hackathon/HACKATHON-PRD.md` | Swarm architecture, agent taxonomy, game topology |
| `PHASE:H1` | `docs/prd/hackathon/PHASE-H1-DOCKER-SWARM-MESH.md` | Docker multicast transport, table discovery, heartbeats |
| `PHASE:H2` | `docs/prd/hackathon/PHASE-H2-POKER-GRAMMAR-LISP-PROFILES.md` | Persona definitions, poker extension grammar, policy bytecode |
| `PHASE:H3` | `docs/prd/hackathon/PHASE-H3-BORDER-ROUTER-OVERLAY.md` | Overlay API endpoints, WebSocket schema, DAG provenance, live stats |
| `PHASE:H4` | `docs/prd/hackathon/PHASE-H4-APEX-AGENT-POLICY-EVOLUTION.md` | PolicyEvolutionChain, policy versioning, hot-swap mechanism |
| `PHASE:26` | `docs/prd/PHASE-26A-WORKBENCH.md` | React three-panel loom, Zustand state, Vite bundling |
| `SDK:WORKBENCH` | `packages/loom/src/` | React layout, component patterns, dark theme |
| `TYPES:NETWORK` | `packages/protocol-types/src/network.ts` | NetworkEvent, PublishableObject, persona definitions |
| `POKER:AGENT` | `packages/poker-agent/src/` | BotPersona enum, hand evaluation, decision pipeline |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules, deliverable sign-off |

---

## Deliverables

### DH5.1 — SwarmTopology Component (Force-Directed Graph)

**New file**: `packages/loom/src/components/SwarmTopology.tsx`

Renders all 25 nodes as a force-directed graph (D3.js or canvas-based). Each node is a circle colored by persona; edges flash white when a cell is multicast between nodes.

#### Node Styling

```typescript
export const PERSONA_COLORS = {
  nit:        '#3366ff',       // Blue
  maniac:     '#ff3333',       // Red
  calculator: '#33cc33',       // Green
  apex:       '#ffcc00',       // Gold
} as const;

export interface NodeData {
  id: string;                  // 'bot-0', 'bot-1', ..., 'bot-24', 'border-router'
  persona: BotPersona | 'router';
  heartbeat: number;           // Last heartbeat timestamp
  uptime: number;              // Seconds online
  activeTable?: string;        // 't1_3_...' if seated
  bankroll?: number;           // Current sats
}
```

#### Edge Animation

When the Border Router emits a cell publish event on the WS stream:

```typescript
// WS event: { type: 'cell.published', source: 'bot-3', timestamp: ... }

// Edge from source to any node (animated)
// → Flash white for 200ms
// → Fade back to default color
// → Increment edge label: "42 cells" → "43 cells"
```

#### Table Clustering

Nodes with an `activeTable` are visually grouped:

```typescript
// If bot-1, bot-7, bot-12 all have activeTable = 't1_7_123456789'
// → Render them in a sub-cluster with a dashed border
// → Label: "Table t1: Hand 47 (Nit vs Maniac vs Calculator)"
```

#### Central Hub

A special "border-router" node sits at the center, connected to all 25 bots and to a "BSV" node off to the right:

```
                 ┌──────────┐
              ┌──│  bot-1   │──┐
         ┌────┤  │  (Nit)   │  ├────┐
         │    └──│          │──┘    │
    [BSV]        └──────────┘   [bot-24]
         │        ┌──────────┐    (Apex)
         └────┤  │border-rtr │  ├────┘
              ├──│ (hub)     │──┤
              └──│          │──┘
                 └──────────┘
```

The border-router-to-BSV edge animates every 30 seconds (batch anchor interval) with a gold glow.

#### Implementation Notes

- **D3 force simulation** or **canvas + Pixi.js** for 25-node performance
- **Responsive**: adapts to viewport size; default 1920x1080 optimized
- **Dark theme**: node circles: `#2a2a3a`, edges: `#555577`, text: `#e0e0e0`
- **Real-time updates**: subscribe to WS `cell.published` events; use Zustand to update graph state
- **Click interaction**: clicking a node opens its detail view (bankroll, persona, policy version if Apex)

---

### DH5.2 — TPSCounter Component (Live Counter + Sparkline + Progress)

**New file**: `packages/loom/src/components/TPSCounter.tsx`

Displays current transactions per second, historical sparkline (last 5 minutes), and progress toward 1.5M cell target.

#### Layout

```
┌─────────────────────────────────┐
│     LIVE TPS                    │
│     1,247 TPS ▲                 │
│                                 │
│     Progress:                   │
│     [████████░░░░░░░░]          │
│     847,231 / 1,500,000 (56%)   │
│                                 │
│     ETA to target: 4h 23m       │
│                                 │
│     Sparkline (5 min history):  │
│     ▁▂▃▃▂▄▆█▇▆▅▄▃▂▁▀            │
│     (60 samples, 1 per 5 sec)   │
│                                 │
│     Batch anchors: 23            │
│     Avg cells/batch: 36.8        │
└─────────────────────────────────┘
```

#### Data Source

Subscribe to WS `/ws/live` stream:

```typescript
// Event type: 'stats.updated'
interface StatsUpdate {
  type: 'stats.updated';
  timestamp: number;
  tps: number;                    // Cells/second (current 5-sec window)
  totalCellsPublished: number;    // Cumulative
  totalBatchesAnchored: number;   // Cumulative
  avgCellsPerBatch: number;       // rolling average
}
```

#### Calculation

```typescript
// TPS = count of cells in current 5-second window / 5
// Target = 1,500,000
// Progress = totalCellsPublished / Target
// ETA = (Target - totalCellsPublished) / (tps * 3600) hours
// Sparkline = ring buffer of tps values, sampled every 5 seconds
```

#### Visual Indicators

- **TPS trend arrow**:
  - `▲` if tps increased in last sample
  - `▼` if tps decreased
  - `→` if flat
- **Progress bar color**:
  - Green if tps > 1000
  - Yellow if tps 500–1000
  - Red if tps < 500
- **Sparkline colors**:
  - Green bars if tps > avg
  - Gray bars if tps ≤ avg

---

### DH5.3 — PersonaLeaderboard Component (Table + Sparklines + Dominance Indicator)

**New file**: `packages/loom/src/components/PersonaLeaderboard.tsx`

Ranked table of all four personas with win statistics and policy versioning. Highlights the Apex Agent's "dominance moment" when its win rate exceeds swarm average.

#### Layout

```
┌────────────────────────────────────────────────────────────────┐
│ PERSONA LEADERBOARD                                            │
├────────────────────────────────────────────────────────────────┤
│ Rank │ Persona    │ Balance │ Hands │ Won │ Win% │ Policy │   │
├──────┼────────────┼─────────┼───────┼─────┼──────┼────────┤   │
│  1   │ Maniac     │ 847 sats│  432  │ 218 │ 50.5%│   –   │ ▁▂  │
│  2   │ Apex ★     │ 821 sats│  421  │ 223 │ 53.0%│  v17  │ ▂▃▃ │
│  3   │ Nit        │ 634 sats│  398  │ 189 │ 47.5%│   –   │ ▀▂▁ │
│  4   │ Calculator │ 501 sats│  415  │ 189 │ 45.5%│   –   │ ▁▀▀ │
│      │ SWARM AVG  │         │       │     │ 49.1%│       │     │
│      │ DOMINANCE  │         │       │     │ +3.9%│       │     │
├──────┼────────────┼─────────┼───────┼─────┼──────┼────────┤   │
│      │  Sparklines show balance over time (20 data points)     │
└────────────────────────────────────────────────────────────────┘
```

#### Data Source

Subscribe to WS `/ws/live` stream:

```typescript
// Event type: 'persona.stats'
interface PersonaStatsUpdate {
  type: 'persona.stats';
  timestamp: number;
  personas: {
    [persona in BotPersona]: {
      balance: number;           // sats
      handsPlayed: number;
      handsWon: number;
      winRate: number;           // 0.0 to 1.0
      policyVersion: number;     // Apex Agent only; increments on hot-swap
      recentBalances: number[];  // Last 20 balance snapshots for sparkline
    };
  };
}
```

#### Dominance Indicator

Calculate swarm-average win rate across all four personas:

```typescript
const avgWinRate = (
  (nit.winRate + maniac.winRate + calculator.winRate + apex.winRate) / 4
);

const apexDominance = apex.winRate - avgWinRate;

// Render below table:
if (apexDominance > 0) {
  // Gold highlight, animated pulse
  <div class="dominance-indicator">
    APEX DOMINANCE: +{(apexDominance * 100).toFixed(1)}%
  </div>
}
```

#### Sparkline Per Persona

Render a mini sparkline (22px high) for each persona's balance over time:

```typescript
// Sparkline data = persona.recentBalances (last 20 snapshots)
// Chart type = area chart, colored by persona
// Min/max auto-scale; labels show current + 1h ago
```

#### Policy Version (Apex Only)

The Apex row displays `policyVersion` (e.g., `v17`). Every ~2 minutes when Phase H4's PolicyEvolutionChain hot-swaps a winning policy:

```typescript
// Change policyVersion: "v16" → "v17"
// Pulse the cell with gold glow for 2 seconds
// Log to console: "Apex Agent policy evolved: v16 → v17"
```

---

### DH5.4 — HandFeed Component (Scrolling Feed with BSV Links)

**New file**: `packages/loom/src/components/HandFeed.tsx`

Real-time feed of completed poker hands, most recent at the top. Each hand shows table ID, players, summary, winner, pot, and clickable BSV txid.

#### Layout

```
┌────────────────────────────────────────────────────────────────┐
│ HAND FEED (realtime)                                           │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│ ✓ Hand #2847 | t1_7  | Maniac ← Nit          | pot:120 sats   │
│   Players: bot-2 (Nit), bot-5 (Maniac)  |  Actions: 3 bet rnd│
│   Winner: Maniac | Reason: High card king-queen              │
│   BSV anchor: 7b2c... [Click for WhatsOnChain]               │
│   2 seconds ago                                               │
│                                                                │
│ ✓ Hand #2846 | t3_24 | Apex ← Calc ← Calc   | pot:82 sats    │
│   Players: bot-0, bot-4, bot-24  |  Actions: 4 bet rnd      │
│   Winner: Apex | Reason: Full house aces over kings          │
│   BSV anchor: 5a9e... [Click for WhatsOnChain]               │
│   8 seconds ago                                               │
│                                                                │
│ ✗ Hand #2845 | t2_18 | Calculator ← Nit    | pot:64 sats     │
│   Players: bot-1, bot-12  |  Actions: 2 bet rnd            │
│   Winner: Calculator | Reason: Opponent shove all-in        │
│   VIOLATION: [Tampering detected in shuffle proof]          │
│   BSV anchor: 9d1f... [Click for WhatsOnChain]               │
│   45 seconds ago                                              │
│                                                                │
│ ✓ Hand #2844 | t1_7  | Nit → Maniac        | pot:105 sats    │
│   Players: bot-2, bot-5  |  Actions: 3 bet rnd             │
│   Winner: Nit | Reason: Three of a kind sevens              │
│   BSV anchor: 3c7e... [Click for WhatsOnChain]               │
│   58 seconds ago                                              │
│                                                                │
│ [scroll for more hands ↓]                                     │
└────────────────────────────────────────────────────────────────┘
```

#### Data Source

Subscribe to WS `/ws/live` stream:

```typescript
// Event type: 'hand.completed'
interface HandCompletedEvent {
  type: 'hand.completed';
  timestamp: number;
  handId: string;                // e.g., 'h2847'
  tableId: string;               // e.g., 't1_7_123456789'
  players: Array<{
    botIndex: number;
    persona: BotPersona;
  }>;
  winner: {
    botIndex: number;
    persona: BotPersona;
  };
  potSize: number;               // sats
  reason: string;                // "high card", "full house", "opponent shove"
  actions: number;               // Betting rounds count
  bsvTxid: string;               // Anchor transaction ID
  violation?: {
    type: string;                // "tampering", "invalid_action"
    details: string;
  };
}
```

#### Hand Row Styling

```typescript
// Row background color based on Apex involvement:
// - Green (#1a3a2a) if Apex won
// - Red (#3a1a1a) if Apex lost  
// - Gray (#2a2a2a) if Apex not at table
//
// Violation rows:
// - Red border + warning icon
// - "VIOLATION:" prefix in red
// - Tamper label overlaid
```

#### BSV Link

Clicking the txid opens WhatsOnChain in a new tab:

```typescript
const whatsOnChainUrl = `https://whatsonchain.com/tx/${bsvTxid}`;
```

#### Scrolling Behavior

- Max-height with scrollbar (flex grow)
- Newest hands at top (prepend to list)
- Keep last 100 hands in state (discard older to prevent memory leak)
- Smooth auto-scroll: when a new hand arrives, scroll to top if already near top

---

### DH5.5 — AnchorChain Component (Visual Block Chain)

**New file**: `packages/loom/src/components/AnchorChain.tsx`

Horizontal chain of Merkle-rooted batches, visualizing the anchor history from the Border Router.

#### Layout

```
┌────────────────────────────────────────────────────────────────┐
│ ANCHOR CHAIN (BSV Settlement)                                  │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│   [Batch 21]    [Batch 22]    [Batch 23]    [Batch 24] NEW   │
│   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐      │
│   │ 802 cells   │ 847 cells   │ 756 cells   │ 923 cells  │     │
│   │ Root:     │ Root:     │ Root:     │ Root:     │     │
│   │ 5a3e...  │ 7b2c...  │ 9d1f...  │ 2e4b... │     │
│   │ TxID:    │ TxID:    │ TxID:    │ TxID:   │     │
│   │ 7ab1... │ 3f8c... │ 6e2d... │ 9c4a... │     │
│   │ [Link]  │ [Link]  │ [Link]  │ [Link] │     │
│   │ 3h ago  │ 2h ago  │ 1h ago  │ <1s ago │     │
│   └─────────┘   └─────────┘   └─────────┘   └─────────┘      │
│        ↑               ↑               ↑               ↑       │
│        └───────────────┴───────────────┴───────────────┘       │
│                  Merkle chain of roots                         │
│                                                                │
│   Click any txid to view on WhatsOnChain                      │
└────────────────────────────────────────────────────────────────┘
```

#### Data Source

Subscribe to WS `/ws/live` stream:

```typescript
// Event type: 'batch.anchored'
interface BatchAnchoredEvent {
  type: 'batch.anchored';
  timestamp: number;
  batchNumber: number;           // Incremental batch ID
  cellCount: number;
  merkleRoot: string;            // Hex, 256-bit
  bsvTxid: string;               // Mainnet txid
  merkleParent?: string;         // Parent batch root (for chain visualization)
}
```

#### Animation

When a new batch is anchored:

```typescript
// 1. New block slides in from the right
// 2. Gold glow animates for 2 seconds
// 3. Arrow points from previous root to new root
// 4. ETA indicator updates: "4h 23m to 1.5M"
```

#### Chain Display

- Show last 10 batches horizontally (scrollable if > 10)
- Truncate txid/root: first 6 chars + "..."
- Root hex: truncate to 6 chars
- Cell count: display as "847 cells"
- Timestamp: relative ("2h ago", "<1s ago")

#### Click Behavior

Clicking a txid link:

```typescript
const url = `https://whatsonchain.com/tx/${bsvTxid}`;
window.open(url, '_blank');
```

---

### DH5.6 — Dashboard Shell (Layout, WebSocket, Dark Theme)

**New file**: `packages/loom/src/pages/SwarmDashboard.tsx`

Top-level React component that orchestrates the five panels, manages WebSocket connection, and applies dark theme.

#### Layout Grid

```typescript
// CSS Grid: 2 columns, 3 rows, responsive
// ┌─────────────────────────────┬─────────────────────────┐
// │ SwarmTopology (span 1, row 1)│ TPSCounter (row 1)      │
// │                             ├─────────────────────────┤
// │                             │ PersonaLeaderboard (r2) │
// ├─────────────────────────────┼─────────────────────────┤
// │ HandFeed (row 3)            │ AnchorChain (row 3)     │
// └─────────────────────────────┴─────────────────────────┘
```

#### WebSocket Management

```typescript
export interface SwarmDashboardState {
  // Connection
  wsUrl: string;                 // configurable, default ws://localhost:9001/ws/live
  connected: boolean;
  lastHeartbeat: number;         // timestamp

  // Graph data
  nodes: NodeData[];             // 25 bots + 1 router
  edges: EdgeData[];

  // Stats
  stats: StatsUpdate;
  personaStats: PersonaStatsUpdate;

  // Hand history
  hands: HandCompletedEvent[];

  // Anchor chain
  batches: BatchAnchoredEvent[];
}

// Zustand store
export const useSwarmDashboardStore = create<SwarmDashboardState>((set) => ({
  // ... getters/setters for all fields
}));
```

#### WebSocket Connection Lifecycle

```typescript
// 1. useEffect on mount: establish WS connection
// 2. Subscribe to all event types: cell.published, stats.updated, 
//    persona.stats, hand.completed, batch.anchored, peer.announced
// 3. On event: update Zustand store (triggers re-render)
// 4. On disconnect: gray out UI, show "DISCONNECTED" banner, retry every 3 seconds
// 5. On reconnect: re-subscribe, restore full state
```

#### Dark Theme

```typescript
// Tailwind config (if using Tailwind) or CSS variables
export const darkThemeColors = {
  bg:         '#0a0a0a',       // Darkest black
  bgSecondary: '#1a1a2e',       // Dark slate
  border:      '#333355',       // Dark purple-gray
  text:        '#e0e0e0',       // Light gray
  textDim:     '#a0a0a0',       // Dimmer gray
  accentGold:  '#ffcc00',       // Apex color
  accentBlue:  '#3366ff',       // Nit color
  accentRed:   '#ff3333',       // Maniac color
  accentGreen: '#33cc33',       // Calculator color
  success:     '#22dd22',       // Green for positive
  warning:     '#dd9922',       // Orange for caution
  error:       '#dd2222',       // Red for violation
} as const;
```

#### Configuration

Allow runtime configuration via environment or URL params:

```typescript
// Default:
const defaultConfig = {
  wsUrl: process.env.REACT_APP_WS_URL ?? 'ws://localhost:9001/ws/live',
  maxHandsInFeed: 100,
  maxBatchesInChain: 10,
  tpsSparklineLength: 60,       // 5 minutes at 5-sec intervals
};

// URL param override:
// ?wsUrl=ws://192.168.1.10:9001/ws/live
```

#### Responsive Design

- Optimized for 1920x1080 (demo screen)
- Mobile breakpoints: reduce panel sizes, stack vertically
- Font sizes: scale with viewport (clamp)
- Touch-friendly: increase tap targets to 48px

---

### DH5.7 — Gate Tests (T1–T8)

**Test file**: `packages/loom/test/SwarmDashboard.test.tsx`

Integration tests for WebSocket connection, data parsing, and component rendering.

#### Test Structure

```typescript
describe('Phase H5: Swarm God View Dashboard', () => {
  // ── T1: WebSocket Connection ──
  test('T1: Dashboard connects to Border Router WS endpoint', async () => {
    const mockWs = new MockWebSocket('ws://localhost:9001/ws/live');
    render(<SwarmDashboard wsUrl="ws://localhost:9001/ws/live" />);

    await waitFor(() => {
      expect(mockWs.readyState).toBe(WebSocket.OPEN);
    });
  });

  // ── T2: Stats Update Handling ──
  test('T2: TPSCounter updates when stats.updated event arrives', async () => {
    const mockWs = new MockWebSocket('ws://localhost:9001/ws/live');
    render(<SwarmDashboard wsUrl="ws://localhost:9001/ws/live" />);

    mockWs.send(JSON.stringify({
      type: 'stats.updated',
      timestamp: Date.now(),
      tps: 1247,
      totalCellsPublished: 847231,
      totalBatchesAnchored: 23,
      avgCellsPerBatch: 36.8,
    }));

    await waitFor(() => {
      expect(screen.getByText(/1247 TPS/)).toBeInTheDocument();
    });
  });

  // ── T3: Persona Stats Leaderboard ──
  test('T3: PersonaLeaderboard renders all four personas ranked by balance', async () => {
    const mockWs = new MockWebSocket('ws://localhost:9001/ws/live');
    render(<SwarmDashboard wsUrl="ws://localhost:9001/ws/live" />);

    mockWs.send(JSON.stringify({
      type: 'persona.stats',
      timestamp: Date.now(),
      personas: {
        nit: {
          balance: 634,
          handsPlayed: 398,
          handsWon: 189,
          winRate: 0.475,
          policyVersion: 1,
          recentBalances: [600, 610, 634],
        },
        maniac: {
          balance: 847,
          handsPlayed: 432,
          handsWon: 218,
          winRate: 0.505,
          policyVersion: 1,
          recentBalances: [800, 820, 847],
        },
        calculator: {
          balance: 501,
          handsPlayed: 415,
          handsWon: 189,
          winRate: 0.455,
          policyVersion: 1,
          recentBalances: [500, 501, 501],
        },
        apex: {
          balance: 821,
          handsPlayed: 421,
          handsWon: 223,
          winRate: 0.530,
          policyVersion: 17,
          recentBalances: [750, 800, 821],
        },
      },
    }));

    await waitFor(() => {
      expect(screen.getByText(/Maniac/)).toBeInTheDocument();
      expect(screen.getByText(/847 sats/)).toBeInTheDocument();
      expect(screen.getByText(/v17/)).toBeInTheDocument(); // Apex policy
    });
  });

  // ── T4: Hand Completed Event ──
  test('T4: HandFeed renders new completed hand with correct styling', async () => {
    const mockWs = new MockWebSocket('ws://localhost:9001/ws/live');
    render(<SwarmDashboard wsUrl="ws://localhost:9001/ws/live" />);

    mockWs.send(JSON.stringify({
      type: 'hand.completed',
      timestamp: Date.now(),
      handId: 'h2847',
      tableId: 't1_7_123456789',
      players: [
        { botIndex: 1, persona: 'nit' },
        { botIndex: 5, persona: 'maniac' },
      ],
      winner: { botIndex: 5, persona: 'maniac' },
      potSize: 120,
      reason: 'high card',
      actions: 3,
      bsvTxid: '7ab1c2d3e4f5...',
    }));

    await waitFor(() => {
      expect(screen.getByText(/Hand #2847/)).toBeInTheDocument();
      expect(screen.getByText(/Maniac/)).toBeInTheDocument();
      expect(screen.getByText(/pot:120/)).toBeInTheDocument();
    });
  });

  // ── T5: Violation Detection ──
  test('T5: Violations are highlighted in red in HandFeed', async () => {
    const mockWs = new MockWebSocket('ws://localhost:9001/ws/live');
    render(<SwarmDashboard wsUrl="ws://localhost:9001/ws/live" />);

    mockWs.send(JSON.stringify({
      type: 'hand.completed',
      timestamp: Date.now(),
      handId: 'h2845',
      tableId: 't2_18_123456789',
      players: [
        { botIndex: 1, persona: 'nit' },
        { botIndex: 12, persona: 'calculator' },
      ],
      winner: { botIndex: 12, persona: 'calculator' },
      potSize: 64,
      reason: 'opponent shove',
      actions: 2,
      bsvTxid: '9d1f2e3c4b5a...',
      violation: {
        type: 'tampering',
        details: 'Shuffle proof validation failed',
      },
    }));

    await waitFor(() => {
      const row = screen.getByText(/VIOLATION/).closest('div');
      expect(row).toHaveClass('violation');
    });
  });

  // ── T6: Batch Anchoring Animation ──
  test('T6: AnchorChain animates when new batch arrives', async () => {
    const mockWs = new MockWebSocket('ws://localhost:9001/ws/live');
    const { rerender } = render(<SwarmDashboard wsUrl="ws://localhost:9001/ws/live" />);

    mockWs.send(JSON.stringify({
      type: 'batch.anchored',
      timestamp: Date.now(),
      batchNumber: 24,
      cellCount: 923,
      merkleRoot: '2e4b5f6a7c8d9e0f1a2b3c4d5e6f7a8b',
      bsvTxid: '9c4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c',
    }));

    await waitFor(() => {
      const newBatch = screen.getByText(/Batch 24/);
      expect(newBatch).toHaveClass('new-batch'); // CSS class for gold glow
    });
  });

  // ── T7: Apex Dominance Indicator ──
  test('T7: Dominance indicator displays when Apex win rate exceeds average', async () => {
    const mockWs = new MockWebSocket('ws://localhost:9001/ws/live');
    render(<SwarmDashboard wsUrl="ws://localhost:9001/ws/live" />);

    mockWs.send(JSON.stringify({
      type: 'persona.stats',
      timestamp: Date.now(),
      personas: {
        nit: { balance: 634, handsPlayed: 398, handsWon: 189, winRate: 0.475, policyVersion: 1, recentBalances: [634] },
        maniac: { balance: 847, handsPlayed: 432, handsWon: 218, winRate: 0.505, policyVersion: 1, recentBalances: [847] },
        calculator: { balance: 501, handsPlayed: 415, handsWon: 189, winRate: 0.455, policyVersion: 1, recentBalances: [501] },
        apex: { balance: 821, handsPlayed: 421, handsWon: 223, winRate: 0.530, policyVersion: 17, recentBalances: [821] }, // 53% > avg 49.1%
      },
    }));

    await waitFor(() => {
      expect(screen.getByText(/APEX DOMINANCE/)).toBeInTheDocument();
    });
  });

  // ── T8: WebSocket Reconnection ──
  test('T8: Dashboard reconnects on WS disconnect', async () => {
    const mockWs = new MockWebSocket('ws://localhost:9001/ws/live');
    render(<SwarmDashboard wsUrl="ws://localhost:9001/ws/live" />);

    // Simulate disconnect
    mockWs.close();

    await waitFor(() => {
      expect(screen.getByText(/DISCONNECTED/)).toBeInTheDocument();
    });

    // Simulate reconnection
    mockWs.open();

    await waitFor(() => {
      expect(screen.queryByText(/DISCONNECTED/)).not.toBeInTheDocument();
    });
  });
});
```

---

## Design Requirements

### Color Palette

| Color | RGB | Usage |
|-------|-----|-------|
| Background | `#0a0a0a` | Page background |
| Secondary BG | `#1a1a2e` | Panel backgrounds, cards |
| Border | `#333355` | Dividers, edges |
| Text Primary | `#e0e0e0` | Main text |
| Text Dim | `#a0a0a0` | Secondary text, timestamps |
| Nit (blue) | `#3366ff` | Node color, link |
| Maniac (red) | `#ff3333` | Node color, loss indicator |
| Calculator (green) | `#33cc33` | Node color, item indicator |
| Apex (gold) | `#ffcc00` | Node color, dominance glow |
| Success | `#22dd22` | Win indicator |
| Warning | `#dd9922` | Caution state |
| Error | `#dd2222` | Violation, loss |

### Typography

- **Headings**: Courier New, monospace, 16px bold
- **Body text**: Courier New, monospace, 14px regular
- **Timestamps**: Courier New, monospace, 11px dim
- **Numbers (TPS, balances)**: Courier New, monospace, 18px bold

### Spacing

- **Panel padding**: 16px
- **Component gaps**: 8px
- **Border radius**: 4px (minimal, prefer sharp angles for technical feel)

### Animations

- **Edge flash**: 200ms, white glow
- **New batch slide**: 300ms ease-out from right
- **Dominance pulse**: 2 seconds, gold glow
- **Policy version change**: 2 seconds, gold glow + pulse
- **All transitions**: prefer `transform` + `opacity` for performance

---

## What NOT to Do

### Anti-Patterns

1. **DO NOT fetch all historical data on connect** — Stream only new events. The WS provides real-time deltas; the dashboard is about NOW, not the past.

2. **DO NOT render every node with a separate SVG/DOM element** — Use canvas (Pixi.js) or batched D3 for 25 nodes. Avoid 25 React components for the graph.

3. **DO NOT display raw cell hashes or Merkle roots in full length** — Truncate to 6 characters max. Full 256-bit hashes are illegible.

4. **DO NOT block the UI on WS events** — Use Zustand or Redux for async state updates. Never await on event handlers.

5. **DO NOT create a localStorage cache** — Use React state only. Judges want to see live data; cached data from a previous run is misleading.

6. **DO NOT hardcode the WS URL** — Make it configurable via env var or URL param. Demo environments vary.

7. **DO NOT render the entire hand history** — Keep max 100 hands in state. Discard old ones to prevent memory leaks.

8. **DO NOT use client-side timestamps for hand ordering** — Use Border Router's server timestamps. Client clocks may drift.

9. **DO NOT animate EVERY cell published** — The graph would flash constantly (120+ cells/sec). Animate only multicast edges between specific nodes; aggregate per-node publish rates.

10. **DO NOT forget the disconnection case** — Show a clear "DISCONNECTED" banner, disable interactivity, auto-retry with backoff. Tests must cover this (T8).

11. **DO NOT use localStorage to persist UI state** — On refresh, the dashboard should be blank until WS events arrive. This ensures judges see live data, not cached state.

12. **DO NOT attempt to render the full DAG visualization** — Leave DAG queries to the Border Router API. The dashboard focuses on topology (who's connected) and outcomes (hands, anchors). If judges want provenance, they query `/api/dag` directly.

---

## Prerequisites

### Hard Prerequisites

- **Phase H3** (Border Router Overlay API) must be complete:
  - `GET /api/stats` returning live TPS, batch counts
  - `GET /api/personas` returning per-persona stats + policy versions
  - `WS /ws/live` stream emitting `cell.published`, `stats.updated`, `persona.stats`, `hand.completed`, `batch.anchored` events

- **Phase H4** (Apex Agent PolicyEvolutionChain) must be running:
  - Apex Agent traces policy version increments
  - Border Router's `persona.stats` includes `apex.policyVersion` field

- **Phase 26** (React loom) available:
  - Zustand store patterns
  - Vite build setup
  - Dark theme CSS

### Soft Prerequisites

- **Phase H1** (Docker mesh) running: provides the 25 nodes and multicast transport
- **Phase H2** (Lisp profiles) running: provides the persona implementations that drive bot decisions

---

## Completion Criteria

1. **DH5.1 (SwarmTopology)**
   - [ ] Force-directed graph renders 25 nodes + 1 router node
   - [ ] Nodes colored by persona (blue/red/green/gold)
   - [ ] Edges flash white when cell published between nodes
   - [ ] Tables cluster nodes visually with dashed border + label
   - [ ] Border router connects to all bots and to BSV anchor node
   - [ ] Click node to see details panel (persona, uptime, policy version if Apex)

2. **DH5.2 (TPSCounter)**
   - [ ] Displays current TPS as large number with trend arrow
   - [ ] Shows 5-minute sparkline (60 samples)
   - [ ] Progress bar toward 1.5M target with percentage
   - [ ] ETA calculation (hours to target) updates in real-time
   - [ ] Batch counter increments on `batch.anchored` event
   - [ ] Colors change based on TPS thresholds (green > 1000, yellow 500–1000, red < 500)

3. **DH5.3 (PersonaLeaderboard)**
   - [ ] Table with 4 rows (one per persona) + average row
   - [ ] Columns: rank, persona name, balance (sats), hands played, hands won, win %, policy version
   - [ ] Rows sorted by balance descending
   - [ ] Sparkline per persona showing balance history (20 samples, 1/minute)
   - [ ] Apex row highlighted in gold
   - [ ] Dominance indicator displays when Apex win rate > average
   - [ ] Policy version updates (v1 → v2 → ... v17) with gold glow on change

4. **DH5.4 (HandFeed)**
   - [ ] Scrolling list of completed hands, newest at top
   - [ ] Each hand shows: ID, table, players, winner, pot, reason, actions count
   - [ ] Rows colored by outcome: green if Apex won, red if Apex lost, gray if not at table
   - [ ] Violations highlighted with red border + "VIOLATION:" label
   - [ ] BSV txid clickable, opens WhatsOnChain in new tab
   - [ ] Max 100 hands retained in state
   - [ ] Auto-scroll to top when new hand arrives (if already near top)

5. **DH5.5 (AnchorChain)**
   - [ ] Horizontal chain of last 10 batches displayed
   - [ ] Each block shows: batch number, cell count, truncated root, truncated txid, timestamp
   - [ ] New blocks slide in from right with gold glow
   - [ ] Merkle parent → child arrows (visual chain)
   - [ ] Txids clickable, open WhatsOnChain
   - [ ] Relative timestamps ("2h ago", "<1s ago") auto-update

6. **DH5.6 (Dashboard Shell)**
   - [ ] All five panels laid out in 2-column grid
   - [ ] Dark theme applied: `#0a0a0a` background, `#e0e0e0` text
   - [ ] WebSocket connects to configurable `WS_URL` (default `ws://localhost:9001/ws/live`)
   - [ ] Auto-reconnect on disconnect (exponential backoff, max 30s)
   - [ ] "DISCONNECTED" banner shown when not connected
   - [ ] Responsive: works on 1920x1080 and mobile (stacked layout)
   - [ ] No localStorage; state is React-only
   - [ ] All components wrapped in Zustand store provider

7. **DH5.7 (Gate Tests T1–T8)**
   - [ ] T1: WebSocket connects to endpoint
   - [ ] T2: TPSCounter updates on `stats.updated` event
   - [ ] T3: PersonaLeaderboard renders all four personas, sorted by balance
   - [ ] T4: HandFeed renders completed hands with correct styling
   - [ ] T5: Violations highlighted in red
   - [ ] T6: New batch animates with gold glow
   - [ ] T7: Dominance indicator displays when Apex exceeds average
   - [ ] T8: Dashboard reconnects on WS disconnect

---

## Success Metrics

### Hackathon Demo (Live)

- **Topology visibility**: Judges can see 25 nodes forming 2–3 concurrent poker tables in real-time
- **Dominance moment**: Judges witness Apex Agent's win rate cross above swarm average, gold indicator lights up
- **Policy evolution**: Judges see Apex policy version increment as hot-swaps occur (v16 → v17 → ...)
- **Anchor proof**: Judges click a hand's BSV txid and verify the anchor on WhatsOnChain
- **Economic narrative**: Judges follow persona balances; see who's winning, who's bust

### Performance Targets

- **Render frame rate**: 60 FPS during graph animation (edge flashes, new batch slides)
- **WebSocket latency**: hand.completed event → HandFeed rendered in < 100ms
- **Memory**: Dashboard < 50MB RAM (no memory leaks from event stream)
- **Connection stability**: Automatic reconnect within 3 seconds of disconnect

---

## Next Phases (Post-Hackathon)

### Phase H6 — Replication & Failover

Add multi-region support: run swarm on two continents, replicate anchor chain across both. Monitor latency, measure consensus time.

### Phase H7 — Playback & Postmortem

Record the entire 24-hour swarm run. Playback dashboard in time-lapse. Judges see full game evolution in 5 minutes.

### Phase H8 — Advanced Analytics

Heatmaps of poker hand outcomes per table. Win rate trends by persona over time. Prediction model: can we predict policy evolution?

---

## Files to Create / Modify

### New Files

- `packages/loom/src/components/SwarmTopology.tsx` (DH5.1)
- `packages/loom/src/components/TPSCounter.tsx` (DH5.2)
- `packages/loom/src/components/PersonaLeaderboard.tsx` (DH5.3)
- `packages/loom/src/components/HandFeed.tsx` (DH5.4)
- `packages/loom/src/components/AnchorChain.tsx` (DH5.5)
- `packages/loom/src/pages/SwarmDashboard.tsx` (DH5.6)
- `packages/loom/test/SwarmDashboard.test.tsx` (DH5.7)
- `packages/loom/src/store/swarmDashboardStore.ts` (Zustand store)
- `packages/loom/src/styles/darkTheme.css` (Dark theme colors)

### Files to Modify

- `packages/loom/vite.config.ts`: Add `/swarm` route
- `packages/loom/src/index.tsx`: Register SwarmDashboard route
- `packages/protocol-types/src/network.ts`: Export BotPersona, NodeData, EdgeData types for dashboard
- `docs/prd/hackathon/HACKATHON-PRD.md`: Link to Phase H5 in architecture section

---

## Deliverable Sign-Off

**Implemented by**: [Engineer name/date]
**Reviewed by**: [Reviewer name/date]
**Status**: [ ] In Progress [ ] Complete [ ] Blocked

---

## Git Workflow

```bash
# Create feature branch from main
git checkout main
git pull origin main
git checkout -b hackathon/h5-swarm-dashboard

# Implement deliverables DH5.1–DH5.7
# Commit messages follow convention:
git commit -m "DH5.1: SwarmTopology force-directed graph with persona coloring"
git commit -m "DH5.2: TPSCounter with 5-min sparkline and progress bar"
git commit -m "DH5.3: PersonaLeaderboard with dominance indicator"
git commit -m "DH5.4: HandFeed with BSV txid links and violation detection"
git commit -m "DH5.5: AnchorChain block visualization with WhatsOnChain links"
git commit -m "DH5.6: Dashboard shell with WebSocket reconnection"
git commit -m "DH5.7: Gate tests T1–T8 for dashboard integration"

# Push and create PR
git push -u origin hackathon/h5-swarm-dashboard
gh pr create --title "Phase H5: Swarm God View Dashboard" \
  --body "Implements real-time visualization of 25-node poker swarm..."
```

---

## References

- Semantos Extension Grammar (Phase 36A)
- Cell Packing & Type Hashing (Phase 1)
- Lisp Compiler (Phase 21)
- NetworkAdapter Design (Phase 26D)
- Trustless Poker Engine (Phase 27)
- React Loom (Phase 26)
- Hackathon Master PRD (HACKATHON-PRD.md)
- Phase H1: Docker Swarm Mesh (PHASE-H1-DOCKER-SWARM-MESH.md)
- Phase H2: Poker Grammar (PHASE-H2-POKER-GRAMMAR-LISP-PROFILES.md)
- Phase H3: Border Router Overlay API (PHASE-H3-BORDER-ROUTER-OVERLAY.md)
- Phase H4: Apex Agent PolicyEvolutionChain (PHASE-H4-APEX-AGENT-POLICY-EVOLUTION.md)
