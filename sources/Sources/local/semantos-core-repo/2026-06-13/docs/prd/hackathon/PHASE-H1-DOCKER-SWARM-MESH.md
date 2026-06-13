---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/hackathon/PHASE-H1-DOCKER-SWARM-MESH.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.762086+00:00
---

# Phase H1 — Docker Swarm Poker Mesh (Transport Layer)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 3–4 days
**Prerequisites**: Phase 26D, 26E, 26G complete (all on `hackathon/semantos-swarm` branch)
**Master document**: `HACKATHON-PRD.md`
**Branch**: `hackathon/h1-docker-swarm-mesh`

---

## Context

Phase H1 is the transport infrastructure for the Semantos Swarm hackathon demo. It extends the existing Phase 26G Docker node packaging to support a 25-node poker swarm where each container is an isolated Semantos node running a poker bot with a deterministic persona (nit, maniac, calculator, apex). Containers discover each other and form poker tables via IPv6 UDP multicast on the Docker bridge network.

This is the **virtualised version of Phase 33's 6LoWPAN mesh**. When ESP32-C6 boards arrive post-hackathon, the transport layer swaps from DockerMulticastAdapter to OpenThreadAdapter with zero kernel changes. The NetworkAdapter abstraction ensures this swap is transparent to the game logic.

### Deployment Topology

```
Docker Host (Swarm Orchestrator)
  │
  ├─ bot-0 (poker-agent, nit persona)
  ├─ bot-1 (poker-agent, maniac persona)
  ├─ bot-2 (poker-agent, calculator persona)
  ├─ ...
  ├─ bot-24 (poker-agent, apex persona)
  │
  └─ block-headers (existing from Phase 26G)

All 25 bots on shared Docker bridge network (172.20.0.0/16)
IPv6 multicast group: ff02::1 (link-local, compressed)
Table discovery: multicast announcement + UDP heartbeat
```

### Transport Design Decisions

1. **Multicast, not overlay mesh** — simplify transport for hackathon; Docker's bridge network provides IP connectivity
2. **CoAP-like framing** — cell serialization as CBOR over UDP (256-byte MTU), matching Phase 33 design
3. **Deterministic bot identity** — BOT_INDEX env var (0-24) derives crypto keys, ensuring reproducible games
4. **Table formation via agent-discovery** — nodes announce, negotiate stakes, form locked tables (reuses Phase 27 logic)
5. **Heartbeat health monitoring** — nodes announce every 5 seconds; absent nodes are excluded from tables
6. **Memory-only storage** — bots don't persist state (live game demos), simplifying orchestration

### Why Docker Multicast Works

Docker's bridge network supports IPv6 multicast on the default bridge. Multicast frames stay within the bridge; no VXLAN complexity. Each container sees all multicast traffic from other containers on the bridge, enabling table discovery without a broker.

---

## Source Files / References

| Alias | Path | What to reference |
|-------|------|------------------|
| `MASTER:HACK` | `docs/prd/hackathon/HACKATHON-PRD.md` | Swarm architecture, game topology, agent taxonomy |
| `PHASE:26D` | `docs/prd/PHASE-26D-NETWORK-ADAPTER.md` | NetworkAdapter interface, publish/subscribe/resolve |
| `PHASE:26E` | `docs/prd/PHASE-26E-NODE-BOOTSTRAP.md` | NodeConfig, SemantosNode lifecycle |
| `PHASE:26G` | `docs/prd/PHASE-26G-NODE-PACKAGING.md` | Dockerfile, docker-compose, semantos CLI |
| `PHASE:27` | `docs/prd/PHASE-27-SIMPLE-GAMES.md` | GameCellEngine, poker transport, agent-discovery |
| `TYPES:NETWORK` | `packages/protocol-types/src/network.ts` | NetworkAdapter interface, PublishableObject, NetworkQuery |
| `SDK:GAME` | `packages/game-sdk/src/engine.ts` | GameCellEngine, table lifecycle |
| `AGENT:DISCO` | `packages/poker-agent/src/agent-discovery.ts` | Stake matching, persona negotiation, table lock |
| `ADAPTER:STUB` | `packages/protocol-types/src/stubs/` | StubNetworkAdapter reference implementation |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming convention, branch rules |

---

## Deliverables

### DH1.1 — DockerMulticastAdapter (NetworkAdapter Implementation)

**New file**: `packages/protocol-types/src/docker-multicast-adapter.ts`

A concrete NetworkAdapter implementation using IPv6 UDP multicast on Docker's bridge network. Implements all five methods from the NetworkAdapter interface: `publish()`, `subscribe()`, `resolve()`, `resolveBCA()`, `sendToNode()`.

#### Constructor & Initialization

```typescript
export class DockerMulticastAdapter implements NetworkAdapter {
  private multicastGroup: string;      // ff02::1 (link-local)
  private multicastPort: number;       // 9000 (CoAP)
  private botIndex: number;            // 0-24, from BOT_INDEX env
  private botBCA: string;              // Derived from botIndex
  private socket: dgram.Socket;
  private subscriptions: Map<string, Set<Callback>>;
  private peers: Map<string, PeerInfo>;
  private lastHeartbeat: Map<string, number>;

  constructor(config: {
    multicastGroup?: string;           // default ff02::1
    multicastPort?: number;            // default 9000
    botIndex: number;                  // 0-24
    botPersona: 'nit' | 'maniac' | 'calculator' | 'apex';
  }) {
    this.multicastGroup = config.multicastGroup ?? 'ff02::1';
    this.multicastPort = config.multicastPort ?? 9000;
    this.botIndex = config.botIndex;
    this.botBCA = this.deriveBCA(config.botIndex);
    this.subscriptions = new Map();
    this.peers = new Map();
    this.lastHeartbeat = new Map();
  }

  private deriveBCA(index: number): string {
    // Deterministic: 2602:f9f8::N where N = 0x0000 + index
    // Ensures reproducible addressing across restarts
    return `2602:f9f8:0000:0000:0000:0000:0000:${index.toString(16).padStart(4, '0')}`;
  }

  async start(): Promise<void> {
    // Create UDP6 socket, bind to multicast group
    // Enable IPv6, multicast loopback (for same-container testing)
    // Join multicast group
    // Start heartbeat interval (5 seconds)
  }
}
```

#### Method: `publish()`

```typescript
async publish(
  object: PublishableObject,
  options?: PublishOptions,
): Promise<PublishResult> {
  // 1. Serialize object as CBOR (256-byte cell format)
  // 2. Prepend CoAP-like header (msgType, msgId, botIndex)
  // 3. Send via UDP multicast on ff02::1:9000
  // 4. Return PublishResult { txid: msgId, timestamp }
  //
  // CoAP-like header (12 bytes):
  //   u8 version (1)
  //   u8 type (PUBLISH = 0x01)
  //   u16 msgId (incrementing per-bot)
  //   u32 botIndex (sender's 0-24)
  //   u32 timestamp (unix ms)
  //
  // Example: poker.shuffle published by bot-3
  //   → msgId = 1743
  //   → multicast frame: [01 01 06CF 00000003 1712345678] + CBOR(cell)
}
```

#### Method: `subscribe()`

```typescript
subscribe(
  topic: string,
  callback: (event: NetworkEvent) => void,
): () => void {
  // 1. Register callback for topic (e.g. 'tm_poker_table', 'tm_agent_discovery')
  // 2. Return unsubscribe function
  //
  // When UDP multicast frame arrives:
  //   a. Decode CoAP header
  //   b. Deserialize CBOR cell
  //   c. Emit NetworkEvent { source: botBCA, data: cell, timestamp }
  //   d. Fire all callbacks registered for matching topics
  //
  // Topics are derived from cell type:
  //   'poker.shuffle' → 'tm_poker_table'
  //   'agent.announcement' → 'tm_agent_discovery'
}
```

#### Method: `resolve()`

```typescript
async resolve(query: NetworkQuery): Promise<NetworkResult[]> {
  // 1. Query local in-memory cache of recently-received cells
  // 2. Optionally multicast a CoAP SEARCH request (for remote queries)
  // 3. Wait 100ms for responses
  // 4. Return array of matching cells
  //
  // Supported queries:
  //   - path: 'poker/table/t1' → cells for table t1
  //   - ownerCert: cert-id → all cells signed by that cert
  //   - contentHash: SHA256(cell) → exact match
  //
  // Local cache strategy:
  //   - Ring buffer, 1000 most-recent cells
  //   - TTL = 30 seconds (discard older)
  //   - Index by path, hash, owner cert
}
```

#### Method: `resolveBCA()`

```typescript
async resolveBCA(address: string): Promise<NodeInfo | null> {
  // 1. Extract botIndex from BCA address
  // 2. Lookup peer table: has this bot announced recently? (< 5s heartbeat)
  // 3. Return NodeInfo { nodeId, bca, persona, adapters, uptime }
  //    or null if peer not found / stale
}
```

#### Method: `sendToNode()`

```typescript
async sendToNode(
  targetBCA: string,
  message: Uint8Array,
): Promise<{ delivered: boolean }> {
  // Direct unicast UDP to target peer (not multicast)
  // Extract peer's IP from peer table
  // Send frame: [type=DIRECT] + message
  // Return confirmation when ACK received (or timeout)
}
```

#### Method: `isConnected()`

```typescript
isConnected(): boolean {
  // Return true if socket is bound and multicast group is joined
  // Return false if socket error or group join failed
}
```

#### Method: `getNodeBCA()`

```typescript
getNodeBCA(): string | null {
  // Return this node's BCA (derived from botIndex)
  // e.g. '2602:f9f8::0003' for bot-3
}
```

#### Heartbeat Mechanism

Every 5 seconds, each node publishes an `agent.heartbeat` cell:

```typescript
private startHeartbeat(): void {
  setInterval(async () => {
    const heartbeat = {
      type: 'agent.heartbeat',
      botIndex: this.botIndex,
      botPersona: this.botPersona,
      timestamp: Date.now(),
      uptime: process.uptime(),
      peers: Array.from(this.peers.keys()), // list of known peers
    };
    await this.publish({ data: heartbeat, topic: 'tm_agent_discovery' });

    // Prune stale peers (no heartbeat > 15 seconds)
    const now = Date.now();
    for (const [peerId, lastTime] of this.lastHeartbeat) {
      if (now - lastTime > 15000) {
        this.peers.delete(peerId);
        this.lastHeartbeat.delete(peerId);
      }
    }
  }, 5000);
}
```

#### CBOR Cell Framing

CoAP-like 256-byte MTU. Cell serialized as CBOR:

```
Frame layout:
  [Bytes 0–1]     CoAP header (version + flags)
  [Bytes 2–3]     Message ID (u16)
  [Bytes 4–7]     Bot Index (u32)
  [Bytes 8–11]    Timestamp (u32, unix seconds)
  [Bytes 12–255]  CBOR-encoded cell (244 bytes max)

Example poker.shuffle frame (80 bytes total):
  01 01              (CoAP header: version=0, type=PUBLISH)
  06CF              (msgId = 1743)
  00000003          (bot-3)
  66A7B4F2          (timestamp)
  A3 61 74...       (CBOR: { "type": "poker.shuffle", "data": ... })
```

### DH1.2 — docker-compose.hackathon.yml (Swarm Orchestration)

**New file**: `docker-compose.hackathon.yml`

Extends the Phase 26G docker-compose.yml to scale the bot service to 25 replicas. Uses service discovery and environment variable templating.

#### File Structure

```yaml
version: '3.9'

services:
  # Existing block-headers service from Phase 26G
  block-headers:
    image: bitcoinops/block-headers:latest
    ports:
      - "8080:8080"
    volumes:
      - block-headers-cache:/var/cache/block-headers
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # Poker bot service — scales to 25 replicas
  bot:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        - NODE_ENV=production
        - SEMANTOS_MODE=docker-swarm
    image: semantos-bot:latest
    depends_on:
      - block-headers
    ports:
      - "9000/udp"    # Multicast, not port-mapped (only exposed within network)
    volumes:
      - /var/semantos/cache:/app/cache     # Shared runtime cache
    environment:
      # Injected per-replica by Docker Compose
      BOT_INDEX: "${BOT_INDEX}"
      BOT_PERSONA: "${BOT_PERSONA}"
      
      # Shared configuration
      MULTICAST_GROUP: "ff02::1"
      MULTICAST_PORT: "9000"
      BLOCK_HEADERS_URL: "http://block-headers:8080"
      
      # Node configuration
      SEMANTOS_MODE: docker-swarm
      SEMANTOS_STORAGE: memory
      SEMANTOS_IDENTITY: stub
      SEMANTOS_ANCHOR: stub
      SEMANTOS_NETWORK: docker-multicast
      
      # Game configuration
      GAME_TYPES: "poker"
      POKER_MIN_STAKES: "1000"     # sats
      POKER_MAX_STAKES: "100000"
      TABLE_TIMEOUT: "300000"       # 5 minutes
      
      # Logging
      LOG_LEVEL: "info"
      DEBUG_MULTICAST: "false"
    
    networks:
      - semantos-swarm
    
    restart: unless-stopped
    
    healthcheck:
      # Check if bot is responsive to multicast heartbeat
      test: ["CMD", "sh", "-c", "kill -0 $$"]
      interval: 10s
      timeout: 2s
      retries: 3

networks:
  semantos-swarm:
    driver: bridge
    ipam:
      config:
        - subnet: "172.20.0.0/16"
    driver_opts:
      # Enable IPv6 multicast on bridge (Docker 20.10+)
      "com.docker.network.ipv6": "true"

volumes:
  block-headers-cache:
```

#### Deployment Strategy

Two ways to deploy:

**Option 1: Explicit service definition** (shown above)
```bash
docker-compose -f docker-compose.hackathon.yml up -d
# Then manually scale:
docker-compose -f docker-compose.hackathon.yml up -d --scale bot=25
```

**Option 2: Programmatic bot scaling** (via shell script)
```bash
#!/bin/bash
# scripts/scale-swarm.sh 25

NUM_BOTS=${1:-25}
PERSONAS=("nit" "maniac" "calculator" "apex")

for i in $(seq 0 $((NUM_BOTS - 1))); do
  PERSONA_IDX=$((i % 4))
  PERSONA=${PERSONAS[$PERSONA_IDX]}
  
  docker run -d \
    --name "bot-$i" \
    --network semantos-swarm \
    -e BOT_INDEX=$i \
    -e BOT_PERSONA=$PERSONA \
    semantos-bot:latest
done

echo "Started $NUM_BOTS bots"
```

#### Network Configuration

All 25 bots share the `semantos-swarm` bridge. Docker assigns each container an IP on 172.20.x.x. IPv6 multicast group `ff02::1:9000` is shared across all containers on the bridge.

### DH1.3 — Bot Container Entrypoint Script

**New file**: `packages/node/src/entrypoint.docker-swarm.ts`

Boots a SemantosNode with persona-specific configuration derived from environment variables. This is the main process inside each bot container.

#### Initialization Flow

```typescript
async function bootPokerBot() {
  // 1. Validate environment
  const botIndex = parseInt(process.env.BOT_INDEX || '0');
  const botPersona = (process.env.BOT_PERSONA || 'nit') as BotPersona;
  const multicastGroup = process.env.MULTICAST_GROUP || 'ff02::1';
  const multicastPort = parseInt(process.env.MULTICAST_PORT || '9000');

  if (botIndex < 0 || botIndex > 24) {
    throw new Error(`Invalid BOT_INDEX: ${botIndex} (must be 0-24)`);
  }

  // 2. Create adapters
  const storageAdapter = new MemoryStorageAdapter();
  const identityAdapter = new StubIdentityAdapter({
    cert: deriveStubCert(botIndex), // Deterministic per bot
  });
  const anchorAdapter = new StubAnchorAdapter();
  const networkAdapter = new DockerMulticastAdapter({
    botIndex,
    botPersona,
    multicastGroup,
    multicastPort,
  });

  // 3. Create NodeConfig
  const nodeConfig: NodeConfig = {
    nodeId: `bot-${botIndex}`,
    mode: 'docker-swarm',
    adapters: {
      storage: storageAdapter,
      identity: identityAdapter,
      anchor: anchorAdapter,
      network: networkAdapter,
    },
    verticals: ['poker'],
  };

  // 4. Bootstrap SemantosNode
  const node = await createNode(nodeConfig);
  console.log(`✓ Bot ${botIndex} (${botPersona}) booted`);
  console.log(`  Node ID: ${node.nodeId}`);
  console.log(`  BCA: ${networkAdapter.getNodeBCA()}`);

  // 5. Start poker game loop
  const pokerAgent = new PokerAgent({
    node,
    botIndex,
    botPersona,
    minStakes: parseInt(process.env.POKER_MIN_STAKES || '1000'),
    maxStakes: parseInt(process.env.POKER_MAX_STAKES || '100000'),
    tableTimeout: parseInt(process.env.TABLE_TIMEOUT || '300000'),
  });

  await pokerAgent.start();
  console.log(`✓ Poker agent started, listening for tables...`);

  // 6. Graceful shutdown
  process.on('SIGTERM', async () => {
    console.log(`Bot ${botIndex} shutting down...`);
    await pokerAgent.stop();
    await node.shutdown();
    process.exit(0);
  });
}

if (require.main === module) {
  bootPokerBot().catch(err => {
    console.error('Fatal:', err);
    process.exit(1);
  });
}
```

#### Persona Configuration

Each persona has distinct play characteristics, wired into the PokerAgent decision-making:

```typescript
export interface BotPersona {
  name: 'nit' | 'maniac' | 'calculator' | 'apex';
  description: string;
  
  // Strategy parameters
  aggression: number;        // 0.0–1.0: how often to raise
  volatility: number;        // 0.0–1.0: randomness in hand selection
  bankrollRisk: number;      // 0.0–1.0: willingness to go all-in
  
  // Play style
  foldThreshold: number;     // win% below which to fold pre-flop
  raiseFrequency: number;    // % of hands to raise with
  bluffFrequency: number;    // % of hands to bluff (if calculator/apex)
}

export const PERSONAS = {
  nit: {
    name: 'nit',
    description: 'Tight, conservative. Plays only premium hands.',
    aggression: 0.1,
    volatility: 0.05,
    bankrollRisk: 0.1,
    foldThreshold: 0.65,
    raiseFrequency: 0.15,
    bluffFrequency: 0.0,
  },
  maniac: {
    name: 'maniac',
    description: 'Loose, aggressive. Plays many hands, raises often.',
    aggression: 0.9,
    volatility: 0.8,
    bankrollRisk: 0.7,
    foldThreshold: 0.2,
    raiseFrequency: 0.6,
    bluffFrequency: 0.4,
  },
  calculator: {
    name: 'calculator',
    description: 'Math-focused. Plays odds-based, seldom bluffs.',
    aggression: 0.5,
    volatility: 0.1,
    bankrollRisk: 0.3,
    foldThreshold: 0.55,
    raiseFrequency: 0.35,
    bluffFrequency: 0.05,
  },
  apex: {
    name: 'apex',
    description: 'Skilled, adaptive. Plays tight but aggressive.',
    aggression: 0.7,
    volatility: 0.2,
    bankrollRisk: 0.5,
    foldThreshold: 0.60,
    raiseFrequency: 0.45,
    bluffFrequency: 0.25,
  },
};
```

### DH1.4 — Table Formation Protocol

**New file**: `packages/poker-agent/src/table-formation.ts`

Implements the table discovery and formation handshake. Nodes listen on multicast for `agent.announcement` messages, match compatible stakes, negotiate, and lock a table.

#### Discovery Phase

```typescript
export class TableFormation {
  private activeAnnouncements: Map<string, AgentAnnouncement> = new Map();
  private lockingTableId: string | null = null;

  async announceAvailability() {
    // 1. Every 3 seconds, publish availability to multicast
    // 2. Format: agent.announcement { botIndex, persona, minStakes, maxStakes, uptime }
    // 3. Expires after 10 seconds of no re-announcement
    
    const announcement: AgentAnnouncement = {
      type: 'agent.announcement',
      botIndex: this.botIndex,
      botPersona: this.botPersona,
      minStakes: this.minStakes,
      maxStakes: this.maxStakes,
      bankroll: this.currentBankroll,
      timestamp: Date.now(),
      version: 1,
    };

    await this.networkAdapter.publish({
      data: announcement,
      topic: 'tm_agent_discovery',
    });
  }

  async listenForAnnouncements() {
    // Listen for agent.announcement on multicast
    this.networkAdapter.subscribe('tm_agent_discovery', (event) => {
      const msg = event.data;
      if (msg.type !== 'agent.announcement') return;

      // Record this peer's availability
      this.activeAnnouncements.set(msg.botIndex, msg);

      // Check if we can form a table with this peer
      this.tryFormTable(msg.botIndex);
    });
  }

  private tryFormTable(peerId: number) {
    // Don't form if already locking a table
    if (this.lockingTableId) return;

    const peer = this.activeAnnouncements.get(peerId);
    if (!peer) return;

    // Check stake compatibility
    const stakes = this.findCompatibleStakes(this.minStakes, this.maxStakes, peer);
    if (!stakes) {
      console.log(`No stake overlap with bot-${peerId}`);
      return;
    }

    // Both bots have overlapping stake ranges
    // Proceed to negotiation
    this.negotiateTable(peerId, stakes);
  }

  private findCompatibleStakes(
    myMin: number,
    myMax: number,
    peer: AgentAnnouncement,
  ): { stakes: number; smallBlind: number } | null {
    // Find overlap in stake ranges
    const overlapMin = Math.max(myMin, peer.minStakes);
    const overlapMax = Math.min(myMax, peer.maxStakes);

    if (overlapMin > overlapMax) return null; // No overlap

    // Choose stakes at midpoint of overlap
    const stakes = Math.floor((overlapMin + overlapMax) / 2);
    const smallBlind = Math.floor(stakes / 10);

    return { stakes, smallBlind };
  }
}
```

#### Negotiation & Locking Phase

```typescript
async negotiateTable(peerId: number, stakes: { stakes: number; smallBlind: number }) {
  const tableId = this.generateTableId(Math.min(this.botIndex, peerId), peerId);
  this.lockingTableId = tableId;

  // 1. Publish table.proposal
  const proposal: TableProposal = {
    type: 'table.proposal',
    tableId,
    initiator: this.botIndex,
    participants: [this.botIndex, peerId],
    stakes: stakes.stakes,
    smallBlind: stakes.smallBlind,
    maxPlayers: 2,
    gameType: 'texas-holdem',
    timestamp: Date.now(),
  };

  await this.networkAdapter.publish({
    data: proposal,
    topic: 'tm_poker_table',
  });

  // 2. Wait for table.accept from peer (within 5 seconds)
  const accepted = await this.waitForTableAccept(tableId, 5000);
  if (!accepted) {
    console.log(`Table ${tableId} proposal rejected or timed out`);
    this.lockingTableId = null;
    return;
  }

  // 3. Publish table.locked to declare the table is now in play
  await this.networkAdapter.publish({
    data: {
      type: 'table.locked',
      tableId,
      participants: [this.botIndex, peerId],
      timestamp: Date.now(),
    },
    topic: 'tm_poker_table',
  });

  console.log(`✓ Table ${tableId} locked: bot-${this.botIndex} vs bot-${peerId}`);

  // 4. Start poker game on this table
  const table = new PokerTable({
    tableId,
    participants: [this.botIndex, peerId],
    stakes: stakes.stakes,
    smallBlind: stakes.smallBlind,
  });

  await table.playRounds();
}

private generateTableId(a: number, b: number): string {
  // Deterministic table ID from participant indices
  // Example: bot-2 vs bot-7 → 't2_7_1712345678'
  return `t${Math.min(a, b)}_${Math.max(a, b)}_${Date.now()}`;
}
```

### DH1.5 — Heartbeat & Health Monitoring

**New file**: `packages/protocol-types/src/docker-multicast-adapter.heartbeat.ts`

Integrated into DockerMulticastAdapter (see DH1.1 above). Nodes emit heartbeats every 5 seconds, and exclude peers that haven't heartbeated in 15 seconds from table formation.

#### Heartbeat Schema

```typescript
export interface AgentHeartbeat {
  type: 'agent.heartbeat';
  botIndex: number;
  botPersona: BotPersona;
  timestamp: number;
  uptime: number;           // seconds since bot started
  version: 1;
  
  // Optional: current game state
  activeTableId?: string;
  bankroll?: number;
}
```

#### Health Checks

Docker health check (in docker-compose.hackathon.yml):

```bash
# Simple: kill -0 keeps the container alive
# Advanced: read heartbeat from local cache, check < 10s old
healthcheck:
  test: [
    "CMD",
    "sh",
    "-c",
    "stat /app/heartbeat.txt && [ $(date +%s) -le $(($(cat /app/heartbeat.txt) + 10)) ]"
  ]
  interval: 10s
  timeout: 2s
  retries: 3
```

#### Stale Peer Eviction

DockerMulticastAdapter prunes peers with no heartbeat > 15 seconds:

```typescript
private startHeartbeatMonitor(): void {
  setInterval(() => {
    const now = Date.now();
    const staleThreshold = 15000; // 15 seconds

    for (const [peerId, lastHeartbeat] of this.lastHeartbeat) {
      if (now - lastHeartbeat > staleThreshold) {
        console.warn(`Peer bot-${peerId} stale (no heartbeat for ${(now - lastHeartbeat) / 1000}s)`);
        this.peers.delete(peerId);
        this.lastHeartbeat.delete(peerId);

        // Notify table formation: if this peer was waiting for a lock,
        // abort the negotiation
        this.emit('peer-offline', { peerId });
      }
    }
  }, 5000); // Check every 5 seconds
}
```

### DH1.6 — Gate Tests (T1–T10)

**Test file**: `packages/protocol-types/test/docker-multicast-adapter.test.ts`

Comprehensive integration tests for the DockerMulticastAdapter and table formation protocol.

#### Test Structure

```typescript
describe('Phase H1: Docker Swarm Mesh', () => {
  // ── T1: Docker Multicast Adapter Initialization ──
  test('T1: DockerMulticastAdapter binds to multicast group', async () => {
    const adapter = new DockerMulticastAdapter({
      botIndex: 1,
      botPersona: 'nit',
      multicastGroup: 'ff02::1',
      multicastPort: 9000,
    });

    await adapter.start();
    expect(adapter.isConnected()).toBe(true);
    expect(adapter.getNodeBCA()).toBe('2602:f9f8::0001');

    await adapter.stop();
  });

  // ── T2: Multicast Publish / Subscribe ──
  test('T2: Multiple adapters can publish and subscribe', async () => {
    const adapter1 = new DockerMulticastAdapter({
      botIndex: 1,
      botPersona: 'nit',
    });
    const adapter2 = new DockerMulticastAdapter({
      botIndex: 2,
      botPersona: 'maniac',
    });

    await adapter1.start();
    await adapter2.start();

    const receivedEvents: any[] = [];
    adapter2.subscribe('tm_poker_table', (event) => {
      receivedEvents.push(event);
    });

    // Publisher sends a message
    const testCell = { type: 'poker.shuffle', data: 'test' };
    const result = await adapter1.publish({
      data: testCell,
      topic: 'tm_poker_table',
    });

    expect(result.txid).toBeDefined();

    // Wait for subscriber to receive
    await sleep(100);
    expect(receivedEvents.length).toBeGreaterThan(0);
    expect(receivedEvents[0].data.type).toBe('poker.shuffle');

    await adapter1.stop();
    await adapter2.stop();
  });

  // ── T3: Heartbeat Publication ──
  test('T3: Bots emit heartbeats every 5 seconds', async () => {
    const adapter = new DockerMulticastAdapter({
      botIndex: 3,
      botPersona: 'calculator',
    });

    await adapter.start();

    const heartbeats: any[] = [];
    adapter.subscribe('tm_agent_discovery', (event) => {
      if (event.data?.type === 'agent.heartbeat') {
        heartbeats.push(event);
      }
    });

    // Wait for two heartbeat cycles
    await sleep(12000);

    expect(heartbeats.length).toBeGreaterThanOrEqual(2);
    expect(heartbeats[0].data.botIndex).toBe(3);
    expect(heartbeats[0].data.botPersona).toBe('calculator');

    await adapter.stop();
  });

  // ── T4: Peer Discovery ──
  test('T4: Peer discovery via heartbeat', async () => {
    const adapter1 = new DockerMulticastAdapter({
      botIndex: 1,
      botPersona: 'nit',
    });
    const adapter2 = new DockerMulticastAdapter({
      botIndex: 2,
      botPersona: 'maniac',
    });

    await adapter1.start();
    await adapter2.start();

    // Wait for heartbeats
    await sleep(6000);

    // adapter1 should know about adapter2
    const peer = await adapter1.resolveBCA('2602:f9f8::0002');
    expect(peer).not.toBeNull();
    expect(peer?.nodeId).toBe('bot-2');
    expect(peer?.persona).toBe('maniac');

    await adapter1.stop();
    await adapter2.stop();
  });

  // ── T5: Stale Peer Eviction ──
  test('T5: Stale peers are evicted after 15 seconds', async () => {
    const adapter1 = new DockerMulticastAdapter({
      botIndex: 1,
      botPersona: 'nit',
    });
    const adapter2 = new DockerMulticastAdapter({
      botIndex: 2,
      botPersona: 'maniac',
    });

    await adapter1.start();
    await adapter2.start();

    // Wait for heartbeats
    await sleep(6000);

    let peer = await adapter1.resolveBCA('2602:f9f8::0002');
    expect(peer).not.toBeNull();

    // Stop adapter2 (no more heartbeats)
    await adapter2.stop();

    // Wait > 15 seconds for eviction
    await sleep(20000);

    peer = await adapter1.resolveBCA('2602:f9f8::0002');
    expect(peer).toBeNull(); // Should be evicted

    await adapter1.stop();
  });

  // ── T6: CBOR Cell Serialization ──
  test('T6: Cells are serialized as CBOR with CoAP header', async () => {
    const adapter = new DockerMulticastAdapter({
      botIndex: 5,
      botPersona: 'apex',
    });

    await adapter.start();

    const cell = {
      type: 'poker.shuffle',
      players: [0, 1],
      deck: 'encrypted-deck-bytes',
    };

    const result = await adapter.publish({
      data: cell,
      topic: 'tm_poker_table',
    });

    // Verify CoAP header structure
    expect(result.txid).toMatch(/^\d+$/); // msgId is numeric
    expect(result.timestamp).toBeLessThanOrEqual(Date.now());

    await adapter.stop();
  });

  // ── T7: Table Proposal Handshake ──
  test('T7: Two bots negotiate and lock a table', async () => {
    const formation1 = new TableFormation({
      botIndex: 0,
      botPersona: 'nit',
      minStakes: 1000,
      maxStakes: 50000,
      networkAdapter: adapter1,
    });

    const formation2 = new TableFormation({
      botIndex: 1,
      botPersona: 'maniac',
      minStakes: 2000,
      maxStakes: 80000,
      networkAdapter: adapter2,
    });

    await formation1.start();
    await formation2.start();

    // Wait for negotiation
    await sleep(10000);

    const table1 = formation1.activeTable();
    const table2 = formation2.activeTable();

    expect(table1).not.toBeNull();
    expect(table1?.tableId).toBe(table2?.tableId);
    expect(table1?.stakes).toBeGreaterThanOrEqual(1000);
    expect(table1?.stakes).toBeLessThanOrEqual(50000);

    await formation1.stop();
    await formation2.stop();
  });

  // ── T8: Multi-Bot Swarm (N=25) ──
  test('T8: Swarm of 25 bots can be instantiated', async () => {
    const adapters: DockerMulticastAdapter[] = [];

    for (let i = 0; i < 25; i++) {
      const persona = ['nit', 'maniac', 'calculator', 'apex'][i % 4];
      const adapter = new DockerMulticastAdapter({
        botIndex: i,
        botPersona: persona as any,
      });
      adapters.push(adapter);
    }

    // Start all adapters
    await Promise.all(adapters.map(a => a.start()));

    // Wait for heartbeats
    await sleep(6000);

    // Each adapter should see 24 peers
    for (let i = 0; i < 25; i++) {
      const peers = await adapters[i].discoverPeers();
      expect(peers.length).toBe(24); // All except self
    }

    // Cleanup
    await Promise.all(adapters.map(a => a.stop()));
  });

  // ── T9: Poker Game on Locked Table ──
  test('T9: Bots play a poker hand on a locked table', async () => {
    // Requires full integration with GameCellEngine and PokerEngine
    // Simplified test: verify table transitions to PLAYING state
    
    const table = new PokerTable({
      tableId: 't0_1_123456',
      participants: [0, 1],
      stakes: 10000,
      smallBlind: 1000,
    });

    const state = table.getState();
    expect(state.phase).toBe('WAITING_FOR_PLAYERS');

    await table.addPlayer(0, 50000); // bot-0, 50k bankroll
    await table.addPlayer(1, 50000); // bot-1, 50k bankroll

    expect(table.getState().phase).toBe('PLAYING');

    // Play one hand
    await table.dealHand();
    const hand = table.getCurrentHand();
    expect(hand.phase).toBe('PREFLOP');

    await table.stop();
  });

  // ── T10: Docker Compose Health Check ──
  test('T10: docker-compose.yml swarm brings all bots up', async () => {
    // Integration test: spawn docker-compose, verify all 25 services
    // This test runs in CI/Docker environment
    
    const result = await exec('docker-compose -f docker-compose.hackathon.yml up -d --scale bot=25');
    expect(result.exitCode).toBe(0);

    // Wait for services to start
    await sleep(10000);

    // Check all services are running
    const psResult = await exec('docker-compose -f docker-compose.hackathon.yml ps');
    expect(psResult.stdout).toContain('bot_1');
    expect(psResult.stdout).toContain('bot_25');

    // Cleanup
    await exec('docker-compose -f docker-compose.hackathon.yml down');
  });
});
```

---

## What NOT to Do

- **Don't hardcode bot indices in config files.** Use BOT_INDEX environment variable for deterministic derivation.
- **Don't use IPv4-only networking.** Multicast group must be IPv6 (`ff02::1`); use proper IPv6 socket options.
- **Don't publish game state as plaintext on multicast.** Encrypt hand details with poker.shuffle SRA keys.
- **Don't block on table formation.** Async negotiation with 5-second timeout; retry if proposal times out.
- **Don't mix persistent storage with docker-swarm mode.** Use MemoryStorageAdapter for bots; BSV anchor handles durability.
- **Don't emit heartbeats on every network event.** Fixed 5-second interval prevents multicast spam.
- **Don't skip BCA derivation.** Each bot must have a stable BCA for peer resolution; deterministic from botIndex.
- **Don't assume all peers are always present.** Implement stale peer eviction (15 second timeout).
- **Don't break Phase 26D–G tests.** NetworkAdapter is an interface; DockerMulticastAdapter is one implementation. Stub tests must still pass.
- **Don't commit Docker image builds to git.** Build images in CI; use Dockerfile as source of truth.

---

## Completion Criteria

- [ ] `DockerMulticastAdapter` implements all five NetworkAdapter methods (publish, subscribe, resolve, resolveBCA, sendToNode)
- [ ] `DockerMulticastAdapter` emits heartbeats every 5 seconds with peer tracking
- [ ] `DockerMulticastAdapter` evicts stale peers (no heartbeat > 15 seconds)
- [ ] CBOR cell serialization with CoAP-like header (12-byte prefix + 244-byte payload max)
- [ ] `docker-compose.hackathon.yml` scales bot service to 25 replicas with environment variable injection
- [ ] `packages/node/src/entrypoint.docker-swarm.ts` boots SemantosNode with persona config
- [ ] `TableFormation` implements discovery, negotiation, and table locking phases
- [ ] `TableFormation` finds compatible stake ranges between peers
- [ ] Tests T1–T10 all pass:
  - T1: Adapter initialization and BCA derivation
  - T2: Multicast publish/subscribe between two adapters
  - T3: Heartbeat emission at 5-second intervals
  - T4: Peer discovery via heartbeat
  - T5: Stale peer eviction after 15 seconds
  - T6: CBOR serialization with CoAP header
  - T7: Table proposal and locking handshake
  - T8: 25-node swarm instantiation
  - T9: Poker hand play on locked table
  - T10: docker-compose health checks
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All Phase 26D–G tests still pass (no regressions)
- [ ] All commits follow `hackathon/h1/DH1.N:` naming convention
- [ ] Branch is `hackathon/h1-docker-swarm-mesh`
- [ ] Pull request against `hackathon/semantos-swarm` with summary of transport layer

---

## Next Phase

Phase H2 extends the swarm with cross-table governance: bots negotiate over multi-table poker tournaments, introducing ranked ladder play and leaderboard state anchoring to BSV. Phase H3 integrates the Double Mate chess engine so bots can stake poker winnings on stakes chess games.

---

## Architecture Diagram: Full H1 Stack

```
┌──────────────────────────────────────────────────────────────────┐
│                    Docker Host / Swarm                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  bot-0        bot-1        bot-2    ...    bot-24              │
│  (nit)       (maniac)   (calculator)      (apex)               │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐     ┌─────────┐          │
│  │ Docker  │ │ Docker  │ │ Docker  │     │ Docker  │          │
│  │ Node.js │ │ Node.js │ │ Node.js │     │ Node.js │          │
│  ├─────────┤ ├─────────┤ ├─────────┤     ├─────────┤          │
│  │Semantos │ │Semantos │ │Semantos │     │Semantos │          │
│  │  Node   │ │  Node   │ │  Node   │     │  Node   │          │
│  ├─────────┤ ├─────────┤ ├─────────┤     ├─────────┤          │
│  │Poker    │ │Poker    │ │Poker    │     │Poker    │          │
│  │Agent    │ │Agent    │ │Agent    │     │Agent    │          │
│  ├─────────┤ ├─────────┤ ├─────────┤     ├─────────┤          │
│  │Docker   │ │Docker   │ │Docker   │     │Docker   │          │
│  │Multicast│ │Multicast│ │Multicast│     │Multicast│          │
│  │Adapter  │ │Adapter  │ │Adapter  │     │Adapter  │          │
│  └────┬────┘ └────┬────┘ └────┬────┘     └────┬────┘          │
│       │           │           │                 │              │
│       └───────────┴───────────┴─────────────────┘              │
│                   │                                            │
│              IPv6 Multicast Bridge                            │
│              ff02::1:9000 (UDP)                               │
│                   │                                            │
│       ┌───────────┴───────────┬─────────────────┐             │
│       │                       │                 │             │
│   ┌───┴───┐               ┌───┴───┐         ┌───┴───┐        │
│   │ block-│               │ (BSV  │         │(future)│       │
│   │headers│               │mainnet)         │H2 mgmt │       │
│   └───────┘               └───────┘         └───────┘        │
│                                                                │
└──────────────────────────────────────────────────────────────────┘

Poker Game Flow:
  1. Bots announce on multicast (tm_agent_discovery)
  2. Bot-i and Bot-j discover compatible stakes
  3. Exchange table.proposal / table.accept (tm_poker_table)
  4. Lock table, play poker.shuffle / betting / showdown
  5. Winner's bankroll increases; loser's decreases
  6. Return to step 1, repeat
```

---

## Reference: Prerequisites Checklist

Before starting Phase H1, verify:

- [ ] Phase 26D (NetworkAdapter interface) merged to `hackathon/semantos-swarm`
- [ ] Phase 26E (NodeConfig, createNode) merged to `hackathon/semantos-swarm`
- [ ] Phase 26G (Dockerfile, docker-compose.yml, CLI) merged to `hackathon/semantos-swarm`
- [ ] Phase 27 (GameCellEngine, PokerEngine, agent-discovery) merged to `hackathon/semantos-swarm`
- [ ] `packages/poker-agent/src/agent-discovery.ts` implements `findCompatibleStakes()`
- [ ] `packages/game-sdk/src/engine.ts` has `PokerTable` class with play methods
- [ ] Docker 20.10+ with IPv6 support available
- [ ] Bun 1.0+ installed (`bun --version`)
- [ ] All Phase 26A–G tests passing: `bun run test:phase-26`

