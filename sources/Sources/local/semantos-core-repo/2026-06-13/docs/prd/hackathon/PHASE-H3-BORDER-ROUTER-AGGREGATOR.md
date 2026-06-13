---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/hackathon/PHASE-H3-BORDER-ROUTER-AGGREGATOR.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.762396+00:00
---

# Phase H3 — Border Router Aggregator (Settlement Layer)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 3–4 days
**Prerequisites**: Phase H1 complete (Docker swarm mesh), Phase 26C (AnchorAdapter), Phase 26D (NetworkAdapter)
**Branch**: `hackathon/h3-border-router`

---

## Context

Phase H1 establishes a Docker swarm mesh where 25 poker bot containers play trustless games continuously, generating `depin.poker.action` cells at ~20–50 cells per second. These cells are multicast via UDP IPv6 to the group `ff02::semantos:poker`.

Phase H3 builds a **Border Router container** that listens to this multicast traffic, aggregates valid cells, batches them, computes Merkle roots, anchors to BSV mainnet/testnet, and serves the verified provenance DAG via REST/WebSocket API (the "Paskian Overlay").

This phase virtualizes Phase 33's D33.8 gateway concept for the Docker environment: the border router is the settlement layer between game logic and blockchain.

### Why This Matters for the Hackathon

1. **Validates the DePIN settlement architecture.** Phase 33 designs ESP32 devices paying via MFP channels. H3 proves the gateway pattern works in Docker — portable to real hardware.
2. **Demonstrates Merkle batching at scale.** Batches cells every 30 seconds, producing 2,880 anchor transactions per day on BSV. Proves throughput without centralization.
3. **Exposes the provenance DAG.** REST + WebSocket API lets external tools query the complete verified history of game states, enabling audits and analytics.

---

## Architecture

```
25 poker bot containers (UDP multicast ff02::semantos:poker)
        │ CBOR cells: depin.poker.action
        │ Magic bytes: 0xDEAD (valid), linearity validated
        ▼
┌─────────────────────────────────────────────────┐
│   Border Router Container                       │
│   (Paskian Overlay Service)                     │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │ 1. Cell Collector                       │   │
│  │    - Multicast listener (ff02::...)     │   │
│  │    - CBOR deserialisation               │   │
│  │    - Magic byte + linearity validation  │   │
│  │    - Content-hash deduplication         │   │
│  └─────────────────────────────────────────┘   │
│                      │                         │
│  ┌───────────────────▼─────────────────────┐   │
│  │ 2. Batch Aggregator                     │   │
│  │    - 30-second time windows              │   │
│  │    - Accumulates valid cells             │   │
│  │    - Emits batch event when window ends │   │
│  └─────────────────────────────────────────┘   │
│                      │                         │
│  ┌───────────────────▼─────────────────────┐   │
│  │ 3. Merkle Batcher                       │   │
│  │    - Computes Merkle root of batch      │   │
│  │    - Uses merkleEnvelope.ts pattern     │   │
│  │    - Tags batch with timestamp + ID     │   │
│  └─────────────────────────────────────────┘   │
│                      │                         │
│  ┌───────────────────▼─────────────────────┐   │
│  │ 4. BSV Anchor Pipeline                  │   │
│  │    - Wraps DirectBroadcastEngine        │   │
│  │    - OP_RETURN with Merkle root         │   │
│  │    - UTXO fan-out + fire-and-forget     │   │
│  │    - Target: 2,880 tx/day               │   │
│  └─────────────────────────────────────────┘   │
│                      │                         │
│  ┌───────────────────▼─────────────────────┐   │
│  │ 5. Provenance SQLite Store              │   │
│  │    - Cells (content, linearity, owner)  │   │
│  │    - Batches (timestamp, Merkle root)   │   │
│  │    - Anchors (txid, block, proof)       │   │
│  │    - Hands (players, cards, result)     │   │
│  │    - Personas (address, stats)          │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │ 6. REST API (Paskian Overlay)           │   │
│  │    - GET /api/dag (paginated DAG)       │   │
│  │    - GET /api/dag/:txid (cell + chain)  │   │
│  │    - GET /api/hands (completed hands)   │   │
│  │    - GET /api/stats (live TPS)          │   │
│  │    - GET /api/personas (per-persona)    │   │
│  │    - GET /api/batches (Merkle batches)  │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │ 7. WebSocket Live Stream                │   │
│  │    - WS /ws/live (new cells)             │   │
│  │    - WS events: cell, batch, anchor      │   │
│  │    - WS events: hand-complete, violation │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
                      │
                      ▼ POST OP_RETURN
                  BSV Mainnet / Testnet
                  (anchor proof of Merkle root)
```

---

## Data Model

### Cell

A cell published by a poker bot. Format:

```typescript
interface PokerCell {
  // Metadata
  magic: number;           // 0xDEAD for valid cells
  version: number;         // Current protocol version
  timestamp: number;       // Epoch ms when cell created
  contentHash: string;     // SHA256(cellBytes) as hex

  // Game state
  hand_id: string;         // Global hand UUID
  action_type: string;     // 'shuffle', 'deal', 'bet', 'fold', 'reveal', etc.
  player_address: string;  // BSV address of acting player
  poker_round: number;     // 0=pre-flop, 1=flop, 2=turn, 3=river
  action_data: object;     // Type-specific data (bet amount, cards, etc.)

  // Linearity
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT';
  // LINEAR: consumed exactly once (bets, card reveals)
  // AFFINE: may be read many times (game state snapshots)
  // RELEVANT: provenance record (hand results, violations)

  // Proof of work (if applicable)
  signature?: string;      // Signature of (hand_id + action + player_address)
  proof_data?: object;     // SRA proofs (shuffle, decryption, etc.)

  // Provenance
  provenance_refs?: string[]; // Content hashes of ancestor cells
}
```

### Batch

A window of aggregated cells. Format:

```typescript
interface Batch {
  batch_id: string;        // UUID
  window_start: number;    // Epoch ms
  window_end: number;      // Epoch ms (start + 30000)
  cell_count: number;      // Number of valid cells in this batch
  merkle_root: string;     // SHA256-tree root of all cell hashes
  cells: PokerCell[];      // Array of cells in this batch

  // Anchor metadata
  anchor_txid?: string;    // BSV txid if anchored
  anchor_block_height?: number;
  anchor_confirmed_at?: number; // Epoch ms
}
```

### Anchor

Proof that a Merkle root was committed to BSV. Format:

```typescript
interface Anchor {
  anchor_id: string;       // UUID
  batch_id: string;        // Which batch this anchors
  merkle_root: string;     // The root being anchored
  txid: string;            // BSV transaction ID
  vout: number;            // Output index (OP_RETURN is usually vout=0)
  block_height: number;    // Block height of confirmation
  confirmed_at: number;    // Epoch ms of confirmation
  proof_json: object;      // Full tx details for verification
}
```

### Hand

A completed poker hand. Extracted from cells for analytics. Format:

```typescript
interface Hand {
  hand_id: string;         // Global UUID
  timestamp: number;       // When hand started
  players: Array<{
    address: string;       // BSV address
    starting_chips: number;
    final_chips: number;
    actions: string[];     // ['fold', 'call', 'raise', 'reveal']
  }>;
  winner_address?: string; // null if all folded
  pot_size: number;        // Total chips in play
  duration_ms: number;     // Time from first action to resolution
}
```

### Persona

Per-player statistics. Format:

```typescript
interface Persona {
  address: string;         // BSV address (primary key)
  first_seen: number;      // Epoch ms
  last_seen: number;       // Epoch ms
  total_hands: number;
  hands_won: number;
  hands_lost: number;
  total_chips_wagered: number;
  total_chips_earned: number;
  winrate: number;         // % of hands won
  violations: number;      // Count of detected rule violations
}
```

---

## Deliverables

### DH3.1 — CellCollector Service

**New file**: `packages/paskian/src/services/cell-collector.ts`

Implements a multicast listener that:

1. Binds to IPv6 group `ff02::semantos:poker` on UDP port 6969 (configurable)
2. Receives CBOR-serialised PokerCell messages
3. Deserialises and validates:
   - Magic byte is 0xDEAD
   - Timestamp is within ±5 seconds of now (clock skew tolerance)
   - Content hash matches cell bytes
   - Linearity rule is one of: LINEAR, AFFINE, RELEVANT
4. Deduplicates by content hash (rejects if already seen in last 60 seconds)
5. Emits `CellCollectorEvent` on successful validation

**Source references**:
- `packages/paskian/src/store.ts` — pattern for event emission
- `packages/protocol-types/src/cell-ops.ts` — cell validation helpers
- `packages/metering/src/channel-fsm.ts` — linearity rule enforcement

**Interface**:

```typescript
interface CellCollectorEvent {
  type: 'cell_collected';
  cell: PokerCell;
  timestamp: number;
}

export class CellCollector {
  constructor(groupAddr?: string, port?: number);
  start(): Promise<void>;
  stop(): Promise<void>;
  on(eventType: 'cell_collected', handler: (event: CellCollectorEvent) => void): void;
  getStats(): { collected: number; deduplicated: number; invalid: number };
}
```

**Gate tests T1–T3** (see Gate Tests section below)

---

### DH3.2 — BatchAggregator Service

**New file**: `packages/paskian/src/services/batch-aggregator.ts`

Implements time-window batching:

1. Receives cells from CellCollector
2. Maintains a current batch (accumulates cells)
3. Every 30 seconds (configurable window):
   - Closes the current batch
   - Emits `BatchReadyEvent`
   - Starts a new batch
4. Tracks batch statistics: cell count, deduplication count, etc.
5. On stop/shutdown: flushes any partial batch

**Source references**:
- `packages/protocol-types/src/anchor-scheduler.ts` — batch timing logic
- Node.js `setInterval` for deterministic 30-second windows

**Interface**:

```typescript
interface BatchReadyEvent {
  type: 'batch_ready';
  batch: Batch;  // cells populated, but no merkle_root yet
  timestamp: number;
}

export class BatchAggregator {
  constructor(windowSizeMs?: number);  // default 30000
  addCell(cell: PokerCell): void;
  start(): void;
  stop(): void;
  on(eventType: 'batch_ready', handler: (event: BatchReadyEvent) => void): void;
  getCurrentBatchSize(): number;
}
```

**Gate tests T4–T5**

---

### DH3.3 — MerkleBatcher Service

**New file**: `packages/paskian/src/services/merkle-batcher.ts`

Implements Merkle root computation:

1. Receives `BatchReadyEvent` from BatchAggregator
2. Extracts all cell contentHashes from the batch
3. Builds a Merkle tree (binary tree, left-padded with empty hashes if odd count)
4. Computes root using SHA256
5. Uses the pattern from `cell-ops/src/merkle-envelope.ts`
6. Tags batch with merkle_root
7. Emits `MerkleRootReadyEvent`

**Source references**:
- `packages/protocol-types/src/cell-ops.ts` — merkleEnvelope.ts pattern (likely)
- Node.js `crypto.createHash('sha256')`

**Interface**:

```typescript
interface MerkleRootReadyEvent {
  type: 'merkle_root_ready';
  batch: Batch;  // with merkle_root populated
  timestamp: number;
}

export class MerkleBatcher {
  addBatch(batch: Batch): void;
  on(eventType: 'merkle_root_ready', handler: (event: MerkleRootReadyEvent) => void): void;
  static computeMerkleRoot(contentHashes: string[]): string;
}
```

**Gate tests T6**

---

### DH3.4 — BSV Anchor Pipeline

**New file**: `packages/paskian/src/services/bsv-anchor-pipeline.ts`

Implements OP_RETURN anchoring:

1. Receives `MerkleRootReadyEvent` from MerkleBatcher
2. Wraps `DirectBroadcastEngine` (from `packages/poker-agent/src/direct-broadcast-engine.ts`)
3. Builds a BSV transaction with:
   - Input: UTXO from the configured hot wallet
   - Output 0: OP_RETURN with: `OP_RETURN + "SEMANTOS" (8 bytes) + merkle_root (32 bytes)`
   - Output 1+: UTXO fan-out change (optional, for throughput scaling)
4. Signs transaction using the configured private key
5. Broadcasts via ARC (Bitcoin ARC protocol, ~20 tx/sec rate limit)
6. Returns immediately (fire-and-forget, not waiting for confirmation)
7. Polls BSV mempool API every 5 seconds to detect confirmation
8. Emits `AnchorConfirmedEvent` when block height is obtained

**Configuration**:

```typescript
interface AnchorPipelineConfig {
  broadcastEngine: DirectBroadcastEngine;
  hotWalletPrivateKey: string;  // WIF format
  network: 'testnet' | 'mainnet';
  batchIntervalMs?: number;  // default 30000 (anchor every batch)
  confirmationPollingMs?: number;  // default 5000
}
```

**Source references**:
- `packages/poker-agent/src/direct-broadcast-engine.ts` — DirectBroadcastEngine interface
- `packages/poker-agent/src/payment-channel.ts` — UTXO structure
- BSV transaction signing (likely `bsv` npm package or similar)

**Interface**:

```typescript
interface AnchorConfirmedEvent {
  type: 'anchor_confirmed';
  anchor: Anchor;
  timestamp: number;
}

export class BsvAnchorPipeline {
  constructor(config: AnchorPipelineConfig);
  addBatch(batch: Batch): Promise<void>;
  on(eventType: 'anchor_confirmed', handler: (event: AnchorConfirmedEvent) => void): void;
  getAnchorStats(): { submitted: number; confirmed: number; failed: number };
}
```

**Gate tests T7–T8**

---

### DH3.5 — Provenance SQLite Store

**New file**: `packages/paskian/src/store/provenance-store.ts`

Implements SQLite persistence following the pattern of `packages/paskian/src/store.ts`:

**Schema**:

```sql
-- Cells
CREATE TABLE cells (
  content_hash TEXT PRIMARY KEY,
  hand_id TEXT NOT NULL,
  action_type TEXT NOT NULL,
  player_address TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  linearity TEXT NOT NULL,
  cell_data JSON NOT NULL,
  batch_id TEXT,
  created_at INTEGER DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_cells_hand ON cells(hand_id);
CREATE INDEX idx_cells_player ON cells(player_address);
CREATE INDEX idx_cells_timestamp ON cells(timestamp);
CREATE INDEX idx_cells_batch ON cells(batch_id);

-- Batches
CREATE TABLE batches (
  batch_id TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  window_end INTEGER NOT NULL,
  cell_count INTEGER NOT NULL,
  merkle_root TEXT NOT NULL,
  anchor_txid TEXT,
  anchor_block_height INTEGER,
  anchor_confirmed_at INTEGER,
  created_at INTEGER DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_batches_merkle ON batches(merkle_root);
CREATE INDEX idx_batches_anchor_txid ON batches(anchor_txid);

-- Anchors
CREATE TABLE anchors (
  anchor_id TEXT PRIMARY KEY,
  batch_id TEXT NOT NULL,
  merkle_root TEXT NOT NULL,
  txid TEXT NOT NULL,
  vout INTEGER NOT NULL,
  block_height INTEGER,
  confirmed_at INTEGER,
  proof_json JSON,
  created_at INTEGER DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (batch_id) REFERENCES batches(batch_id)
);
CREATE INDEX idx_anchors_txid ON anchors(txid);
CREATE INDEX idx_anchors_block ON anchors(block_height);

-- Hands
CREATE TABLE hands (
  hand_id TEXT PRIMARY KEY,
  timestamp INTEGER NOT NULL,
  winner_address TEXT,
  pot_size INTEGER,
  duration_ms INTEGER,
  player_count INTEGER,
  created_at INTEGER DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_hands_timestamp ON hands(timestamp);
CREATE INDEX idx_hands_winner ON hands(winner_address);

-- Hand players
CREATE TABLE hand_players (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  hand_id TEXT NOT NULL,
  player_address TEXT NOT NULL,
  starting_chips INTEGER,
  final_chips INTEGER,
  created_at INTEGER DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (hand_id) REFERENCES hands(hand_id)
);
CREATE INDEX idx_hand_players_hand ON hand_players(hand_id);
CREATE INDEX idx_hand_players_address ON hand_players(player_address);

-- Personas (aggregated per-player stats)
CREATE TABLE personas (
  address TEXT PRIMARY KEY,
  first_seen INTEGER,
  last_seen INTEGER,
  total_hands INTEGER DEFAULT 0,
  hands_won INTEGER DEFAULT 0,
  hands_lost INTEGER DEFAULT 0,
  total_chips_wagered INTEGER DEFAULT 0,
  total_chips_earned INTEGER DEFAULT 0,
  violations INTEGER DEFAULT 0,
  updated_at INTEGER DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_personas_first_seen ON personas(first_seen);
```

**Interface**:

```typescript
export class ProvenanceStore {
  constructor(dbPath: string);
  
  // Cells
  addCell(cell: PokerCell, batchId?: string): Promise<void>;
  getCell(contentHash: string): Promise<PokerCell | null>;
  getCellsByHand(handId: string): Promise<PokerCell[]>;
  
  // Batches
  addBatch(batch: Batch): Promise<void>;
  getBatch(batchId: string): Promise<Batch | null>;
  getBatchesByMerkleRoot(merkleRoot: string): Promise<Batch[]>;
  
  // Anchors
  addAnchor(anchor: Anchor): Promise<void>;
  getAnchor(anchorId: string): Promise<Anchor | null>;
  getAnchorByTxid(txid: string): Promise<Anchor | null>;
  
  // Hands
  addHand(hand: Hand): Promise<void>;
  getHand(handId: string): Promise<Hand | null>;
  getHandsByPlayer(address: string, limit?: number): Promise<Hand[]>;
  
  // Personas
  updatePersona(persona: Persona): Promise<void>;
  getPersona(address: string): Promise<Persona | null>;
  getAllPersonas(): Promise<Persona[]>;
  
  // Stats
  getStats(): Promise<{
    totalCells: number;
    totalBatches: number;
    totalAnchors: number;
    totalHands: number;
    uniquePlayers: number;
  }>;
  
  close(): Promise<void>;
}
```

**Source references**:
- `packages/paskian/src/store.ts` — SQLite initialization pattern
- Node.js `sqlite3` or `better-sqlite3` package

**Gate tests T9**

---

### DH3.6 — REST API (Paskian Overlay)

**New file**: `packages/paskian/src/api/rest-server.ts`

Implements Express.js REST API:

**Endpoints**:

| Endpoint | Method | Description | Returns |
|----------|--------|-------------|---------|
| `/api/dag` | GET | Paginated provenance DAG | `{ cells: PokerCell[], total: number, page: number }` |
| `/api/dag/:contentHash` | GET | Cell + provenance chain | `{ cell: PokerCell, ancestors: PokerCell[], descendants: PokerCell[] }` |
| `/api/hands` | GET | Last N completed hands (default 10) | `{ hands: Hand[], total: number }` |
| `/api/hands/:handId` | GET | Specific hand + player breakdown | `{ hand: Hand, cells: PokerCell[] }` |
| `/api/batches` | GET | Merkle batches (paginated) | `{ batches: Batch[], total: number, page: number }` |
| `/api/batches/:batchId` | GET | Specific batch + anchor | `{ batch: Batch, anchor?: Anchor }` |
| `/api/anchors` | GET | Recent anchor confirmations | `{ anchors: Anchor[], total: number }` |
| `/api/anchors/:txid` | GET | Specific anchor proof | `{ anchor: Anchor }` |
| `/api/stats` | GET | Live statistics | `{ totalCells: number, totalAnchored: number, tps: number, batches: number, personas: number, uptime_ms: number }` |
| `/api/personas` | GET | All player personas (paginated) | `{ personas: Persona[], total: number }` |
| `/api/personas/:address` | GET | Specific player stats | `{ persona: Persona, recentHands: Hand[] }` |

**Query parameters**:

- `page` (default 1): for paginated endpoints
- `limit` (default 10, max 100): items per page
- `address`: filter by player address (where applicable)
- `before`: timestamp filter (epoch ms)
- `after`: timestamp filter (epoch ms)

**Response format**:

```typescript
interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  timestamp: number;
}
```

**Implementation**:

```typescript
export class RestServer {
  constructor(port: number, store: ProvenanceStore);
  start(): Promise<void>;
  stop(): Promise<void>;
  getBaseUrl(): string;
}
```

**Source references**:
- `packages/paskian/src/api/rest-server.ts` (if exists)
- Express.js documentation
- CORS headers for cross-origin requests

**Gate tests T10**

---

### DH3.7 — WebSocket Live Stream API

**New file**: `packages/paskian/src/api/websocket-server.ts`

Implements WebSocket server serving live events:

**Connection**: `WS <border-router-host>:8080/ws/live`

**Message format** (JSON):

```typescript
interface WsMessage {
  type: 'cell' | 'batch' | 'anchor' | 'hand_complete' | 'violation' | 'stats_update';
  data: PokerCell | Batch | Anchor | Hand | Violation | LiveStats;
  timestamp: number;
}
```

**Event types**:

- `cell`: New cell collected and validated
- `batch`: Batch completed and Merkle root computed
- `anchor`: Batch anchored to BSV (fire-and-forget, not waiting for confirmation)
- `anchor_confirmed`: Batch anchor confirmed in a block
- `hand_complete`: Hand completed (all players folded or showdown resolved)
- `violation`: Rule violation detected (e.g., illegal bet, timeout)
- `stats_update`: Periodic stats (TPS, total cells, personas, etc.) — every 10 seconds

**Violation type**:

```typescript
interface Violation {
  violation_id: string;
  hand_id: string;
  player_address: string;
  violation_type: string;  // 'illegal_bet', 'timeout', 'signature_invalid', etc.
  details: string;
  timestamp: number;
}
```

**LiveStats type**:

```typescript
interface LiveStats {
  cells_per_second: number;  // computed from last 10 cells
  total_cells_collected: number;
  total_cells_anchored: number;
  current_batch_size: number;
  current_batch_age_ms: number;
  unique_players: number;
  uptime_ms: number;
}
```

**Implementation**:

```typescript
export class WebSocketServer {
  constructor(port: number, store: ProvenanceStore);
  start(): Promise<void>;
  stop(): Promise<void>;
  broadcastCell(cell: PokerCell): void;
  broadcastBatch(batch: Batch): void;
  broadcastAnchor(anchor: Anchor): void;
  broadcastHandComplete(hand: Hand): void;
  broadcastViolation(violation: Violation): void;
  broadcastStatsUpdate(stats: LiveStats): void;
  getConnectionCount(): number;
}
```

**Source references**:
- Node.js `ws` package or similar

**Gate tests T11**

---

### DH3.8 — Docker Compose Service Entry

**Edit file**: `docker-compose.yml` (root of repository)

Add service entry:

```yaml
services:
  border-router:
    image: semantos/border-router:latest
    build:
      context: .
      dockerfile: packages/paskian/Dockerfile.border-router
    networks:
      - poker-mesh
    ports:
      - "8080:8080"       # REST API
      - "8081:8081"       # WebSocket
      - "6969/udp"        # Multicast listener
    environment:
      NODE_ENV: production
      LOG_LEVEL: info
      BSV_NETWORK: testnet           # or mainnet
      HOT_WALLET_PRIVKEY: ${HOT_WALLET_PRIVKEY}
      ANCHOR_BATCH_INTERVAL_MS: 30000
      CELL_DEDUP_WINDOW_MS: 60000
      MULTICAST_GROUP: ff02::semantos:poker
      MULTICAST_PORT: 6969
      SQLITE_DB_PATH: /data/provenance.db
    volumes:
      - border-router-data:/data
    depends_on:
      - poker-table-1
      - poker-table-2
      # ... all 25 poker tables

volumes:
  border-router-data:
    driver: local
```

**Dockerfile**: `packages/paskian/Dockerfile.border-router`

```dockerfile
FROM node:20-alpine

WORKDIR /app

# Copy monorepo root
COPY . .

# Install dependencies
RUN npm ci

# Build border-router service
RUN npm run build:paskian

# Expose ports
EXPOSE 8080 8081 6969/udp

# Start border router
CMD ["npm", "run", "start:border-router"]
```

**npm scripts** in `packages/paskian/package.json`:

```json
{
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "test": "jest"
  }
}
```

**Gate tests**: Docker build + container startup verification

---

### DH3.9 — Gate Tests T1–T12

**Location**: `packages/paskian/src/__tests__/border-router.test.ts`

Comprehensive test suite with 12 gates:

#### T1 — CellCollector validates magic byte

```typescript
test('T1: CellCollector rejects cells without 0xDEAD magic', async () => {
  const collector = new CellCollector();
  const badCell = { ...mockCell, magic: 0xBADF };
  expect(() => collector.validate(badCell)).toThrow('Invalid magic byte');
});
```

#### T2 — CellCollector deduplicates by content hash

```typescript
test('T2: CellCollector deduplicates within 60s window', async () => {
  const collector = new CellCollector();
  const cell = { ...mockCell, contentHash: 'abc123' };
  
  const event1 = await collector.collectCell(cell);
  expect(event1.type).toBe('cell_collected');
  
  const event2 = await collector.collectCell(cell);
  expect(event2).toBeUndefined();  // deduplicated
});
```

#### T3 — CellCollector validates linearity rules

```typescript
test('T3: CellCollector rejects unknown linearity', async () => {
  const collector = new CellCollector();
  const badCell = { ...mockCell, linearity: 'UNKNOWN' };
  expect(() => collector.validate(badCell)).toThrow('Invalid linearity');
});
```

#### T4 — BatchAggregator closes batch after 30 seconds

```typescript
test('T4: BatchAggregator emits batch_ready after 30s window', async () => {
  const agg = new BatchAggregator(1000);  // 1s for testing
  const batchReady = new Promise(resolve => {
    agg.on('batch_ready', resolve);
  });
  
  agg.addCell(mockCell);
  const batch = await batchReady;
  expect(batch.cell_count).toBe(1);
});
```

#### T5 — BatchAggregator accumulates cells

```typescript
test('T5: BatchAggregator accumulates multiple cells in window', async () => {
  const agg = new BatchAggregator(1000);
  
  for (let i = 0; i < 10; i++) {
    agg.addCell(mockCell);
  }
  
  const batch = await new Promise(resolve => {
    agg.on('batch_ready', resolve);
  });
  
  expect(batch.cell_count).toBe(10);
});
```

#### T6 — MerkleBatcher computes correct root

```typescript
test('T6: MerkleBatcher computes Merkle root', async () => {
  const batcher = new MerkleBatcher();
  
  const batch = {
    cells: [mockCell1, mockCell2, mockCell3],
    cell_count: 3,
  };
  
  const root = MerkleBatcher.computeMerkleRoot(batch.cells.map(c => c.contentHash));
  
  // Verify root is 64 hex characters (SHA256)
  expect(root).toMatch(/^[a-f0-9]{64}$/);
});
```

#### T7 — BSV Anchor Pipeline builds valid OP_RETURN transaction

```typescript
test('T7: BsvAnchorPipeline builds valid OP_RETURN tx', async () => {
  const pipeline = new BsvAnchorPipeline(mockConfig);
  
  const batch = {
    batch_id: 'batch-123',
    merkle_root: 'abc123def456...',
    cells: [mockCell],
  };
  
  const tx = pipeline.buildTransaction(batch);
  
  // Check output 0 is OP_RETURN
  expect(tx.outputs[0].script.toString()).toContain('OP_RETURN');
  // Check payload contains merkle root
  expect(tx.outputs[0].script.toString()).toContain('SEMANTOS');
});
```

#### T8 — BSV Anchor Pipeline emits anchor_confirmed on block detection

```typescript
test('T8: BsvAnchorPipeline emits anchor_confirmed when block found', async () => {
  const pipeline = new BsvAnchorPipeline(mockConfig);
  
  const anchorConfirmed = new Promise(resolve => {
    pipeline.on('anchor_confirmed', resolve);
  });
  
  await pipeline.addBatch(mockBatch);
  // Simulate block detection
  pipeline.confirmationPoller.mockBlockHeight(100);
  
  const anchor = await anchorConfirmed;
  expect(anchor.block_height).toBe(100);
});
```

#### T9 — ProvenanceStore persists and retrieves cells, batches, hands

```typescript
test('T9: ProvenanceStore persists and retrieves data', async () => {
  const store = new ProvenanceStore(':memory:');
  
  await store.addCell(mockCell, 'batch-1');
  const retrieved = await store.getCell(mockCell.contentHash);
  
  expect(retrieved.hand_id).toBe(mockCell.hand_id);
  expect(retrieved.action_type).toBe(mockCell.action_type);
});
```

#### T10 — REST API returns correct responses

```typescript
test('T10: REST API /api/stats returns live statistics', async () => {
  const server = new RestServer(3000, mockStore);
  await server.start();
  
  const response = await fetch('http://localhost:3000/api/stats');
  const data = await response.json();
  
  expect(data.data).toHaveProperty('totalCells');
  expect(data.data).toHaveProperty('tps');
  expect(data.data).toHaveProperty('uptime_ms');
  
  await server.stop();
});
```

#### T11 — WebSocket server broadcasts events

```typescript
test('T11: WebSocket server broadcasts new cell events', async () => {
  const server = new WebSocketServer(8081, mockStore);
  await server.start();
  
  const wsClient = new WebSocket('ws://localhost:8081/ws/live');
  
  const messageReceived = new Promise(resolve => {
    wsClient.onmessage = resolve;
  });
  
  server.broadcastCell(mockCell);
  const msg = await messageReceived;
  const data = JSON.parse(msg.data);
  
  expect(data.type).toBe('cell');
  expect(data.data.hand_id).toBe(mockCell.hand_id);
  
  wsClient.close();
  await server.stop();
});
```

#### T12 — Border Router end-to-end: cell → batch → anchor → API

```typescript
test('T12: End-to-end flow from cell to anchored batch in REST API', async () => {
  const router = new BorderRouter(mockConfig);
  await router.start();
  
  // Inject cell via multicast mock
  const cell = mockCell;
  router.collector.injectCell(cell);
  
  // Wait for batch + anchor
  await new Promise(resolve => setTimeout(resolve, 31000));  // 30s batch + 1s grace
  
  // Query API
  const batches = await fetch('http://localhost:8080/api/batches').then(r => r.json());
  expect(batches.data.batches.length).toBeGreaterThan(0);
  
  const firstBatch = batches.data.batches[0];
  expect(firstBatch.merkle_root).toBeDefined();
  
  // Check store
  const cells = await router.store.getCellsByHand(cell.hand_id);
  expect(cells.length).toBeGreaterThan(0);
  
  await router.stop();
});
```

**Source files**:
- Test utilities: `packages/paskian/src/__tests__/mocks.ts`
- Mock providers: `packages/paskian/src/__tests__/fixtures.ts`

---

## What NOT to Do

### ❌ Don't Build a Game Validator

The Border Router does **not** validate poker hand outcomes. It doesn't check:
- Whether the shuffle proof is mathematically correct
- Whether the community cards match the deal
- Whether the final bet amounts follow poker rules
- Who actually won the pot

**Why**: Validation is enforced by the poker engine in each bot container. The Border Router is purely a **settlement aggregator** — it trusts that valid cells reached it from the game logic.

### ❌ Don't Implement Chain-of-Custody Signing

The Border Router does **not** sign every batch or anchor. It doesn't create:
- A Border Router identity certificate
- Signatures on batch metadata
- A "gateway cert" that authenticates the router to players

**Why**: For the hackathon, we don't need a multi-node federation. A single trusted border router is fine. If this moves to Phase 33 (multi-gateway ESP32 mesh), then add gateway signing.

### ❌ Don't Attempt to Resolve Conflicts

If two cells with the same hand_id but conflicting actions arrive, the Border Router does **not** arbitrate. It stores both.

**Why**: Conflict resolution is a game-logic concern, not a settlement concern. The game engine rejects the invalid one.

### ❌ Don't Poll External BSV APIs in a Loop

The Border Router should **not** continuously poll the BSV mempool or block explorer.

**Why**: Instead, use websocket subscriptions (if available via bsv-mcp) or batch-poll once per minute to detect block confirmations. Aggressive polling is wasteful and unreliable.

### ❌ Don't Serve Unverified Transactions

The REST API endpoints should **only** return data from the local SQLite store, **not** raw blockchain queries. Cells and batches in the store have been validated locally.

**Why**: Consistency. The store is the source of truth. BSV serves as the immutable audit log.

### ❌ Don't Implement Payment Channel Settlement

The Border Router does **not** settle MFP payment channels in Phase H3.

**Why**: H3 is about cell aggregation and batching. Payment channel settlement is Phase H4 or later. For H3, the assumption is that all cells are valid (no contested channels).

---

## Completion Criteria

A Phase H3 implementation is complete when:

1. **CellCollector** listens to multicast IPv6 group, validates 100+ cells/sec, deduplicates correctly
2. **BatchAggregator** closes batches every 30 ± 1 seconds, never loses cells
3. **MerkleBatcher** computes reproducible Merkle roots, verified in tests
4. **BsvAnchorPipeline** submits OP_RETURNs to BSV, detects block confirmations within 5 minutes
5. **ProvenanceStore** persists 10,000+ cells without data loss
6. **REST API** responds to all 11 endpoints with correct schema, <100ms latency
7. **WebSocket API** broadcasts events to ≥10 simultaneous clients without lag
8. **Docker Compose** entry builds image, starts container, passes health check
9. **All 12 gate tests** pass with ≥95% coverage of critical paths
10. **Performance**: Border Router sustains ≥500 cells/sec input rate with CPU <50%, memory <500 MB

---

## Prerequisites Satisfied

| Prerequisite | Satisfied By | Status |
|---|---|---|
| Phase H1 (Docker swarm mesh) | 25 poker containers, multicast working | Must be in place |
| Phase 26C (AnchorAdapter) | BsvAnchorAdapter reference | Used in DH3.4 |
| Phase 26D (NetworkAdapter) | NetworkAdapter pattern | Informational, not directly used |

---

## Branch & Merge

**Branch name**: `hackathon/h3-border-router`

**Merge to**: `main` (via PR after T1–T12 all green)

**Commit message style** (follow project conventions):

```
feat: Phase H3 Border Router Aggregator — settlement layer

- DH3.1: CellCollector service (multicast + validation)
- DH3.2: BatchAggregator (30s time windows)
- DH3.3: MerkleBatcher (Merkle root computation)
- DH3.4: BsvAnchorPipeline (OP_RETURN to BSV)
- DH3.5: ProvenanceStore (SQLite persistence)
- DH3.6: REST API (6 endpoints + pagination)
- DH3.7: WebSocket live stream (real-time events)
- DH3.8: docker-compose service entry
- DH3.9: Gate tests T1–T12

Sustains 500+ cells/sec, anchors every 30s (~2,880 tx/day).
```

---

## References

| Document | Section | Relevance |
|----------|---------|-----------|
| PHASE-33-DEPIN-6LOWPAN-MASTER.md | D33.8 Border Router Gateway | Inspiration for this phase |
| PHASE-26-KERNEL-ISOLATION-MASTER.md | Four Adapter Architecture | AnchorAdapter + NetworkAdapter patterns |
| PHASE-26C-ANCHOR-ADAPTER.md | BSV Anchor Adapter | BsvAnchorAdapter impl |
| PHASE-26D-NETWORK-ADAPTER.md | NetworkAdapter interface | Network abstraction pattern |
| HACKATHON-PRD.md | Challenge Requirements | Contextual fit |

---

## Risk Mitigations

| Risk | Mitigation |
|---|---|
| Multicast IPv6 not working in Docker | Fallback: TCP unicast from each poker container to border-router |
| Memory leak in long-running aggregator | Unit tests with 10,000+ cell load; memory profiling |
| Batch window timing drift | Deterministic timer reset on each batch emission |
| OP_RETURN transaction rejection | Validate script format in unit tests; use known-good UTXO |
| WebSocket connection storms | Rate-limit at 100 clients/minute; idle disconnect after 1 hour |

---

## Timeline

| Day | Task | Deliverables |
|-----|------|---------------|
| 1   | CellCollector + BatchAggregator | DH3.1, DH3.2, T1–T5 |
| 2   | MerkleBatcher + ProvenanceStore | DH3.3, DH3.5, T6, T9 |
| 2   | BSV Anchor Pipeline + Tests | DH3.4, T7–T8 |
| 3   | REST API + WebSocket | DH3.6, DH3.7, T10–T11 |
| 3   | Docker Compose + E2E Test | DH3.8, T12 |
| 3   | Code review + docs | All 12 gates passing |

---

**Author**: Semantos Hackathon Team  
**Date**: April 2026  
**Status**: Ready for Implementation
