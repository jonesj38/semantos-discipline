---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26D-NETWORK-ADAPTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.659211+00:00
---

# Phase 26D — NetworkAdapter Interface & Overlay Composition

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 26A complete (IdentityAdapter extraction)
**Master document**: `PHASE-26-KERNEL-ISOLATION-MASTER.md`
**Branch**: `phase-26d-network-adapter`

---

## Context

The NetworkAdapter unifies object movement between nodes. Currently, three separate clients handle networking:

- **TopicManagerClient** (BRC-22 SHIP) — submits cell-token transactions to overlay topics
- **LookupServiceClient** (BRC-24 SLAP) — queries objects by path, content, owner, type, parent
- **ShardProxyClient** (UDP multicast) — publishes transactions through shard proxy

These clients exist at different abstraction levels and are composed ad-hoc in BsvOverlayAdapter. Phase 26D unifies them behind a clean `NetworkAdapter` interface, decouples network operations from storage, and enables swappable network implementations (stub for dev, BSV overlay for production, direct LAN for enterprise nodes).

### The Three Concerns (Do Not Conflate)

| Concern | Adapter | What it does | Example impl |
|---------|---------|-------------|--------------|
| **Where bytes live** | StorageAdapter | Persistence + local state | MemoryAdapter, NodeFsAdapter, BsvOverlayAdapter |
| **Who you are** | IdentityAdapter | Identity, derivation, capabilities | StubIdentityAdapter, LocalIdentityAdapter, CloudIdentityAdapter |
| **Proving things existed** | AnchorAdapter | Timestamp proofs on blockchain | StubAnchorAdapter, BsvAnchorAdapter |
| **How objects move** | NetworkAdapter | Publish, subscribe, resolve | StubNetworkAdapter, BsvOverlayNetworkAdapter, DirectNetworkAdapter |

A node composes all four. Storage and network are independent — you can store locally AND publish via overlay.

### Architecture Diagram

```
┌─────────────────────────────────────────┐
│       Kernel Node Instance              │
│  (cell engine, validation, evidence)    │
└──────┬──────┬──────────┬────────────────┘
       │      │          │
       v      v          v
  Storage   Identity   Anchor      Network
  Adapter   Adapter    Adapter     Adapter
  ─────────────────────────────────────────
  | Memory  | Stub    | Stub    | Stub
  | NodeFs  | Local   | Bsv     | Bsv
  | OPFS    | Cloud   | -       | Direct
  | Overlay | -       | -       | -
```

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `CLIENTS:TOPIC` | `packages/protocol-types/src/overlay/topic-manager-client.ts` | TopicManagerClient.submit(), SEMANTOS_TOPICS |
| `CLIENTS:LOOKUP` | `packages/protocol-types/src/overlay/lookup-service-client.ts` | LookupServiceClient query methods, DecodedLookupOutput |
| `CLIENTS:SHARD` | `packages/protocol-types/src/overlay/shard-proxy-client.ts` | ShardProxyClient.publish(), PublishResult |
| `STORAGE:ADAPTER` | `packages/protocol-types/src/storage.ts` | StorageAdapter pattern, StorageEvent structure |
| `BSV:OVERLAY` | `packages/protocol-types/src/adapters/bsv-overlay-adapter.ts` | How clients currently compose, CellToken usage |
| `PATTERN:MASTER` | `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` | Four adapter architecture, node deployment profiles |

---

## Deliverables

### D26D.1 — NetworkAdapter Interface

**New file**: `packages/protocol-types/src/network.ts`

The `NetworkAdapter` interface as the unified contract for all network operations. All methods. All JSDoc. Only primitive and basic types in signature.

```typescript
/**
 * NetworkAdapter — unified interface for object movement between nodes.
 *
 * Abstracts all publish, subscribe, and resolve operations.
 * Decoupled from StorageAdapter (where objects live locally)
 * and AnchorAdapter (how objects are proved).
 *
 * Implementations:
 * - StubNetworkAdapter: in-memory pub/sub
 * - BsvOverlayNetworkAdapter: BRC-22 SHIP + BRC-24 SLAP
 * - DirectNetworkAdapter: campus LAN, IPv6 multicast
 */
export interface NetworkAdapter {
  /**
   * Publish an object to the network.
   *
   * @param object - object to publish (cell bytes + metadata)
   * @param options - optional topic override, batch flag
   * @returns txid, multicast group, publish timestamp
   */
  publish(object: PublishableObject, options?: PublishOptions): Promise<PublishResult>;

  /**
   * Subscribe to objects matching a topic or query.
   *
   * Fires callback immediately on new publications that match the query.
   * The callback fires AFTER the publish() call completes on the publisher.
   *
   * @param topic - subscription topic (e.g. 'tm_semantos_objects')
   * @param callback - fires on matching PublishableObject
   * @returns unsubscribe function
   */
  subscribe(topic: string, callback: (event: NetworkEvent) => void): () => void;

  /**
   * Resolve objects matching a query on the network.
   *
   * Query by path, content hash, owner cert, type, or parent.
   * Returns results from local index + overlay queries.
   *
   * @param query - resolve query (path, owner, type, etc)
   * @returns array of matching objects with metadata
   */
  resolve(query: NetworkQuery): Promise<NetworkResult[]>;

  /**
   * Resolve a Bitcoin Coin Address (BCA) to node metadata.
   *
   * BCAs are IPv6 addresses that encode node identity.
   * Used in enterprise nodes for sovereign addressing.
   *
   * @param address - BCA in IPv6 notation (e.g. '2602:f9f8::a3f8:b2c1')
   * @returns NodeInfo with node identity, capabilities, adapters
   */
  resolveBCA(address: string): Promise<NodeInfo | null>;

  /**
   * Send an authenticated message to a specific node.
   *
   * Uses IdentityAdapter capability tokens to prove authorization.
   *
   * @param targetBCA - recipient's BCA address
   * @param message - binary message payload
   * @returns delivery confirmation
   */
  sendToNode(targetBCA: string, message: Uint8Array): Promise<{ delivered: boolean }>;

  /**
   * Check if this adapter is currently connected to the network.
   *
   * For stub: always true.
   * For BSV overlay: true if SLAP resolvers are responding.
   * For direct: true if multicast socket is bound.
   */
  isConnected(): boolean;

  /**
   * Get the BCA (Bitcoin Coin Address) of this node.
   *
   * Used in node self-object (sovereignty.node).
   * Returns null if not configured.
   */
  getNodeBCA(): string | null;
}
```

### D26D.2 — NetworkQuery and NetworkEvent Types

**Add to**: `packages/protocol-types/src/network.ts`

```typescript
/**
 * Query to resolve objects on the network.
 */
export interface NetworkQuery {
  /** Semantic path (e.g. 'trades/job/plumbing-1774') */
  path?: string;
  /** Content SHA-256 hash as hex string */
  contentHash?: string;
  /** Owner cert ID */
  ownerCert?: string;
  /** Type hash (e.g. 'sha256(trades.job)') */
  typeHash?: string;
  /** Parent object path */
  parentPath?: string;
  /** Max results. Default: 10. */
  limit?: number;
  /** Depth for hierarchy queries. Default: 1. */
  depth?: number;
}

/**
 * Result from a network resolve query.
 */
export interface NetworkResult {
  /** Transaction ID containing this object. */
  txid: string;
  /** Output index within the transaction. */
  vout: number;
  /** Cell bytes (1024 bytes). */
  cellBytes: Uint8Array;
  /** Semantic path from the PushDrop script. */
  semanticPath: string;
  /** Content hash (32 bytes). */
  contentHash: string;
  /** Owner cert ID. */
  ownerCert: string;
  /** Type hash. */
  typeHash: string;
  /** Parent path (if applicable). */
  parentPath?: string;
  /** Network publication timestamp (epoch ms). */
  publishedAt: number;
  /** Which multicast group carried this. */
  multicastGroup?: string;
}

/**
 * Event fired on subscription callback.
 */
export interface NetworkEvent {
  type: 'object_published' | 'object_updated' | 'object_consumed';
  result: NetworkResult;
  timestamp: number;
}

/**
 * Object ready for network publication.
 */
export interface PublishableObject {
  /** Cell bytes (1024 bytes). */
  cellBytes: Uint8Array;
  /** Semantic path. */
  semanticPath: string;
  /** Content hash (32 bytes). */
  contentHash: string;
  /** Owner cert ID. */
  ownerCert: string;
  /** Type hash. */
  typeHash: string;
  /** Parent path (optional). */
  parentPath?: string;
  /** Metadata for serialization (used by overlay to pack PushDrop). */
  metadata?: Record<string, string>;
}

/**
 * Options for publish().
 */
export interface PublishOptions {
  /** Override topic. Default derived from path. */
  topic?: string;
  /** Include in batch. Default: false (immediate). */
  batch?: boolean;
  /** Batch timeout if batch=true. Default: 1000ms. */
  batchTimeoutMs?: number;
  /** Skip local index. Default: false. */
  skipLocalIndex?: boolean;
}

/**
 * Result of a publish operation.
 */
export interface PublishResult {
  /** Transaction ID on the network. */
  txid: string;
  /** Multicast group (if applicable). */
  multicastGroup?: string;
  /** Shard index (if using ShardProxyClient). */
  shardIndex?: number;
  /** Publication timestamp (epoch ms). */
  publishedAt: number;
}

/**
 * Metadata about a node on the network.
 */
export interface NodeInfo {
  /** BCA address. */
  bca: string;
  /** Node cert ID. */
  nodeCert: string;
  /** Node name / description. */
  name?: string;
  /** List of active verticals (e.g. ['trades', 'sovereignty']). */
  verticals: string[];
  /** Node adapters configuration. */
  adapters: {
    storage: string;
    identity: string;
    anchor: string;
    network: string;
  };
  /** Node version. */
  version: string;
  /** Uptime in ms. */
  uptime: number;
  /** Last anchor proof (if available). */
  lastAnchorProof?: {
    stateHash: string;
    blockHeight: number;
    timestamp: number;
  };
}
```

### D26D.3 — BsvOverlayNetworkAdapter Implementation

**New file**: `packages/protocol-types/src/adapters/bsv-overlay-network-adapter.ts`

Implements `NetworkAdapter` by composing the three existing clients (TopicManagerClient, LookupServiceClient, ShardProxyClient). This is the production network implementation for overlay-based nodes.

```typescript
/**
 * BsvOverlayNetworkAdapter — NetworkAdapter backed by BRC-22 SHIP + BRC-24 SLAP.
 *
 * Composes:
 * - TopicManagerClient for publish (BRC-22 SHIP)
 * - LookupServiceClient for resolve queries (BRC-24 SLAP)
 * - ShardProxyClient for UDP multicast (optional, for throughput)
 *
 * Decoupled from storage — this is pure network, not persistence.
 */
export class BsvOverlayNetworkAdapter implements NetworkAdapter {
  private readonly topicManager: TopicManagerClient;
  private readonly lookupService: LookupServiceClient;
  private readonly shardProxy?: ShardProxyClient;
  private readonly subscribers = new Map<string, Set<(event: NetworkEvent) => void>>();
  private nodeBCA: string | null = null;
  private connected = true;

  constructor(config: BsvOverlayNetworkAdapterConfig) {
    this.topicManager = new TopicManagerClient(config.topicManagerConfig);
    this.lookupService = new LookupServiceClient(config.lookupServiceConfig);
    this.shardProxy = config.shardProxy;
    this.nodeBCA = config.nodeBCA ?? null;
  }

  async publish(object: PublishableObject, options?: PublishOptions): Promise<PublishResult> {
    // Determine topic from path or options
    const topic = options?.topic ?? topicForKey(object.semanticPath);

    // Build transaction from PublishableObject
    const tx = this.buildCellTokenTransaction(object);

    // Publish via topic manager or shard proxy
    const txid = tx.id('hex');
    let shardIndex: number | undefined;
    let multicastGroup: string | undefined;

    if (this.shardProxy) {
      const result = await this.shardProxy.publish(tx);
      shardIndex = result.shardIndex;
      multicastGroup = result.multicastGroup;
    } else {
      await this.topicManager.submit(tx, [topic]);
    }

    // Fire subscribers
    this.fireSubscribers(topic, {
      type: 'object_published',
      result: {
        txid,
        vout: 0,
        cellBytes: object.cellBytes,
        semanticPath: object.semanticPath,
        contentHash: object.contentHash,
        ownerCert: object.ownerCert,
        typeHash: object.typeHash,
        parentPath: object.parentPath,
        publishedAt: Date.now(),
        multicastGroup,
      },
      timestamp: Date.now(),
    });

    return {
      txid,
      shardIndex,
      multicastGroup,
      publishedAt: Date.now(),
    };
  }

  subscribe(topic: string, callback: (event: NetworkEvent) => void): () => void {
    if (!this.subscribers.has(topic)) {
      this.subscribers.set(topic, new Set());
    }
    this.subscribers.get(topic)!.add(callback);

    return () => {
      this.subscribers.get(topic)?.delete(callback);
    };
  }

  async resolve(query: NetworkQuery): Promise<NetworkResult[]> {
    const results: NetworkResult[] = [];

    if (query.path) {
      const answer = await this.lookupService.queryByPath(query.path, {
        prefix: false,
        depth: query.depth,
      });
      results.push(...this.decodeAnswerToResults(answer));
    }

    if (query.contentHash) {
      const answer = await this.lookupService.queryByContent(query.contentHash);
      results.push(...this.decodeAnswerToResults(answer));
    }

    if (query.ownerCert) {
      const answer = await this.lookupService.queryByOwner(query.ownerCert);
      results.push(...this.decodeAnswerToResults(answer));
    }

    if (query.typeHash) {
      const answer = await this.lookupService.queryByType(query.typeHash);
      results.push(...this.decodeAnswerToResults(answer));
    }

    if (query.parentPath) {
      const answer = await this.lookupService.queryByParent(query.parentPath);
      results.push(...this.decodeAnswerToResults(answer));
    }

    return results.slice(0, query.limit ?? 10);
  }

  async resolveBCA(address: string): Promise<NodeInfo | null> {
    // In overlay model, BCA is encoded but not directly queryable.
    // This is a placeholder for enterprise sovereign nodes.
    return null;
  }

  async sendToNode(targetBCA: string, message: Uint8Array): Promise<{ delivered: boolean }> {
    // Would require authenticated message wrapping + routing.
    // Stub for Phase 26E (node bootstrap).
    return { delivered: false };
  }

  isConnected(): boolean {
    return this.connected;
  }

  getNodeBCA(): string | null {
    return this.nodeBCA;
  }

  private buildCellTokenTransaction(object: PublishableObject): Transaction {
    // Wrap PublishableObject in CellToken PushDrop script.
    // Implementation: pack cell, create PushDrop output, build tx.
    throw new Error('buildCellTokenTransaction: implementation pending, uses CellToken + @bsv/sdk');
  }

  private decodeAnswerToResults(answer: LookupAnswer): NetworkResult[] {
    // Convert LookupResolver answer to NetworkResult array.
    // Extract from answer.outputs, map DecodedLookupOutput → NetworkResult.
    throw new Error('decodeAnswerToResults: implementation pending, uses answer.outputs');
  }

  private fireSubscribers(topic: string, event: NetworkEvent): void {
    const callbacks = this.subscribers.get(topic);
    if (callbacks) {
      callbacks.forEach(cb => cb(event));
    }
  }
}

export interface BsvOverlayNetworkAdapterConfig {
  topicManagerConfig?: ConstructorParameters<typeof TopicManagerClient>[0];
  lookupServiceConfig?: ConstructorParameters<typeof LookupServiceClient>[0];
  shardProxy?: ShardProxyClient;
  nodeBCA?: string;
}
```

### D26D.4 — StubNetworkAdapter (Development)

**New file**: `packages/protocol-types/src/adapters/stub-network-adapter.ts`

In-memory pub/sub implementation for local development and testing. No network, no async delays.

```typescript
/**
 * StubNetworkAdapter — in-memory pub/sub for development.
 *
 * - publish() stores in local map, fires subscriber callbacks immediately
 * - resolve() queries local map by path/content/owner/type/parent
 * - subscribe() registers callback that fires on publish
 * - No network calls, fully deterministic, synchronous-like behavior
 */
export class StubNetworkAdapter implements NetworkAdapter {
  private readonly objects = new Map<string, NetworkResult>();
  private readonly subscribers = new Map<string, Set<(event: NetworkEvent) => void>>();
  private nodeBCA: string | null = null;
  private txidCounter = 1;

  constructor(config?: { nodeBCA?: string }) {
    this.nodeBCA = config?.nodeBCA ?? null;
  }

  async publish(object: PublishableObject, options?: PublishOptions): Promise<PublishResult> {
    const txid = this.generateTxid();
    const result: NetworkResult = {
      txid,
      vout: 0,
      cellBytes: object.cellBytes,
      semanticPath: object.semanticPath,
      contentHash: object.contentHash,
      ownerCert: object.ownerCert,
      typeHash: object.typeHash,
      parentPath: object.parentPath,
      publishedAt: Date.now(),
      multicastGroup: options?.topic,
    };

    // Store in local map
    this.objects.set(object.semanticPath, result);

    // Fire subscribers
    const topic = options?.topic ?? 'tm_semantos_objects';
    const event: NetworkEvent = {
      type: 'object_published',
      result,
      timestamp: Date.now(),
    };
    this.fireSubscribers(topic, event);

    return {
      txid,
      publishedAt: Date.now(),
      multicastGroup: topic,
    };
  }

  subscribe(topic: string, callback: (event: NetworkEvent) => void): () => void {
    if (!this.subscribers.has(topic)) {
      this.subscribers.set(topic, new Set());
    }
    this.subscribers.get(topic)!.add(callback);

    return () => {
      this.subscribers.get(topic)?.delete(callback);
    };
  }

  async resolve(query: NetworkQuery): Promise<NetworkResult[]> {
    const results: NetworkResult[] = [];

    for (const [, result] of this.objects) {
      let matches = true;

      if (query.path && !result.semanticPath.includes(query.path)) matches = false;
      if (query.contentHash && result.contentHash !== query.contentHash) matches = false;
      if (query.ownerCert && result.ownerCert !== query.ownerCert) matches = false;
      if (query.typeHash && result.typeHash !== query.typeHash) matches = false;
      if (query.parentPath && result.parentPath !== query.parentPath) matches = false;

      if (matches) results.push(result);
    }

    return results.slice(0, query.limit ?? 10);
  }

  async resolveBCA(address: string): Promise<NodeInfo | null> {
    return null;
  }

  async sendToNode(targetBCA: string, message: Uint8Array): Promise<{ delivered: boolean }> {
    return { delivered: true };
  }

  isConnected(): boolean {
    return true;
  }

  getNodeBCA(): string | null {
    return this.nodeBCA;
  }

  private fireSubscribers(topic: string, event: NetworkEvent): void {
    const callbacks = this.subscribers.get(topic);
    if (callbacks) {
      callbacks.forEach(cb => cb(event));
    }
  }

  private generateTxid(): string {
    const id = this.txidCounter++;
    return 'stub' + id.toString(16).padStart(63, '0');
  }
}
```

### D26D.5 — Decouple BsvOverlayAdapter Storage from Network

**Modify**: `packages/protocol-types/src/adapters/bsv-overlay-adapter.ts`

Currently, BsvOverlayAdapter conflates storage (persistence via overlay) with networking (publishing to remote nodes). Phase 26D separates these concerns:

1. BsvOverlayAdapter remains a **StorageAdapter** — it reads/writes to the overlay network as persistent storage
2. Create BsvOverlayNetworkAdapter as a separate **NetworkAdapter** — it publishes/resolves via the same overlay, but as a networking layer
3. In a node, you can:
   - Store locally (NodeFsAdapter) + publish via overlay (BsvOverlayNetworkAdapter)
   - Store via overlay (BsvOverlayAdapter) + publish via overlay (BsvOverlayNetworkAdapter)
   - Store locally + publish via direct LAN (DirectNetworkAdapter)

**Changes**:

- Extract network-only logic from BsvOverlayAdapter into BsvOverlayNetworkAdapter
- BsvOverlayAdapter.write() → stores cell in overlay (existing behavior)
- BsvOverlayAdapter.read() → queries overlay for stored objects (existing behavior)
- BsvOverlayNetworkAdapter.publish() → publishes PublishableObject to overlay topics
- BsvOverlayNetworkAdapter.resolve() → queries lookup services

No breaking changes to BsvOverlayAdapter API. It continues to implement StorageAdapter. The network concern is now a sibling, not entangled.

### D26D.6 — Relationship Diagram

Add to the module documentation of `network.ts`:

```
Three Independent Concerns in a Semantos Node:

┌─────────────────────────────────────────────────────────┐
│                Kernel Core                              │
│  (cell engine, linearity, capability validation)        │
└──────┬──────────┬──────────┬──────────┬─────────────────┘
       │          │          │          │
       v          v          v          v

 STORAGE       IDENTITY      ANCHOR      NETWORK
 (where        (who you      (proving    (how
  bytes         are,          things     objects
  live)         what you      existed)   move)
               can do)

 Memory        Stub          Stub        Stub
 NodeFs        Local         BSV         BSV
 OPFS          Cloud         –           Direct
 Overlay       –             –           –

 None conflict. Each can be swapped independently.
 A node's deployment profile is the sum of four choices.
```

---

## TDD Gate

Create `packages/__tests__/phase26d-gate.test.ts`.

### Unit Tests (T1–T6)

```typescript
describe("StubNetworkAdapter", () => {
  // T1: publish stores object, returns txid + publishedAt
  // T2: subscribe fires on publish
  // T3: resolve queries by path, returns matching objects
  // T4: resolve queries by contentHash
  // T5: resolve queries by ownerCert
  // T6: resolve queries by typeHash + respects limit
});
```

### Integration Tests (T7–T12)

```typescript
describe("NetworkAdapter composition", () => {
  // T7: BsvOverlayNetworkAdapter.publish uses TopicManagerClient.submit
  // T8: BsvOverlayNetworkAdapter.resolve calls LookupServiceClient.queryByPath
  // T9: BsvOverlayNetworkAdapter.resolve calls queryByOwner for ownerCert query
  // T10: BsvOverlayNetworkAdapter.subscribe fires on remote publish
  // T11: publish + subscribe round-trip: published object reaches subscriber
  // T12: resolve + publish round-trip: published object is resolvable by path
});
```

### Decoupling Tests (T13–T15)

```typescript
describe("Storage and Network Decoupling", () => {
  // T13: StorageAdapter and NetworkAdapter can be different implementations
  //   → StubStorageAdapter + BsvOverlayNetworkAdapter work together
  // T14: BsvOverlayAdapter (storage) and BsvOverlayNetworkAdapter (network) are independent
  //   → Each has its own Clients, config, state
  // T15: Node can use NodeFsAdapter (storage) + BsvOverlayNetworkAdapter (network)
  //   → Objects stored locally, published to overlay
});
```

---

## Completion Criteria

- [ ] `packages/protocol-types/src/network.ts` exists with full `NetworkAdapter` interface
- [ ] `NetworkQuery`, `NetworkEvent`, `NetworkResult`, `PublishableObject`, `NodeInfo` types defined
- [ ] `packages/protocol-types/src/adapters/bsv-overlay-network-adapter.ts` exists and composes clients
- [ ] `packages/protocol-types/src/adapters/stub-network-adapter.ts` exists with in-memory impl
- [ ] BsvOverlayAdapter refactored to decouple storage from network
- [ ] Relationship diagram documented in `network.ts` module comments
- [ ] Tests T1–T15 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No @bsv/sdk imports outside `packages/protocol-types/src/adapters/`
- [ ] All commits follow `phase-26d/D26D.N:` naming convention
- [ ] Branch is `phase-26d-network-adapter`

---

## Next Phase

Phase 26E (Node Bootstrap) composes all four adapters into a NodeConfig, creates the node self-object (sovereignty.node), and brings up the conversational shell.
