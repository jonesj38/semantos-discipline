---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26E-NODE-BOOTSTRAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.701203+00:00
---

# Phase 26E — Node Bootstrap & Self-Object

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 3–4 days
**Prerequisites**: Phase 26B, 26C, 26D ALL complete
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md`
**Branch**: `phase-26e-node-bootstrap`

---

## Context

Phase 26B (IdentityAdapter), 26C (AnchorAdapter), and 26D (NetworkAdapter) have delivered clean interfaces with working implementations. The kernel now has four pluggable adapters for storage, identity, anchoring, and networking.

Phase 26E assembles these four adapters into a deployable Semantos node. The task is to:

1. Define `NodeConfig` — a single configuration object that describes a node by its four adapter choices plus deployment metadata
2. Implement `createNode(config)` — the bootstrap sequence that loads config, initializes all four adapters, creates the node self-object
3. Wire the conversational shell so it can be scoped to the node self-object (admin managing the node via chat)

This is where everything comes together. After 26E, a Semantos node is a runnable, self-describing semantic object.

---

## Architecture: Node as Semantic Object

A Semantos node is defined by:

```
┌──────────────────────────────────────────────────────┐
│                   SemantosNode                        │
│  config: NodeConfig                                  │
│  nodeObject: CellRef (sovereignty.node.{cert_id})    │
│  storage: StorageAdapter                             │
│  identity: IdentityAdapter                           │
│  anchor: AnchorAdapter                               │
│  network: NetworkAdapter                             │
│  cellStore: CellStore                                │
│  semanticFs: SemanticFS                              │
│  start(): Promise<void>                              │
│  stop(): Promise<void>                               │
│  getStatus(): NodeStatus                             │
│  updateNodeObject(): Promise<void>                   │
└──────────────────────────────────────────────────────┘
```

On startup, the node:

1. Loads the NodeConfig (from JSON file or object)
2. Validates config (all four adapters present, required metadata present)
3. Initializes all four adapters
4. Creates or loads the node's identity cert via the IdentityAdapter
5. Starts the anchor scheduler (if `anchorIntervalMs > 0`)
6. Creates a `sovereignty.node.{cert_id}` RELEVANT semantic object describing itself
7. Listens for incoming network messages and shell commands scoped to that object

The node object is the admin interface. "Update the configuration" → intent classifies to `govern.node.update-config` → flow runner guides through the process → node self-object is updated with new state.

---

## Source Files / References

| Alias | Path | What to reference |
|-------|------|-------------------|
| `TYPE:STORAGE` | `packages/protocol-types/src/storage.ts` | StorageAdapter interface (Phase 25A) |
| `TYPE:IDENTITY` | `packages/protocol-types/src/identity.ts` | IdentityAdapter interface (Phase 26A) |
| `TYPE:ANCHOR` | `packages/protocol-types/src/anchor.ts` | AnchorAdapter interface (Phase 26C) |
| `TYPE:NETWORK` | `packages/protocol-types/src/network.ts` | NetworkAdapter interface (Phase 26D) |
| `TYPE:CELLSTORE` | `packages/protocol-types/src/cell-store.ts` | CellStore interface (Phase 25B) |
| `TYPE:SEMANTICFS` | `packages/protocol-types/src/semantic-fs.ts` | SemanticFS interface (Phase 25C) |
| `TYPE:TAXONOMYRESOLVER` | `packages/protocol-types/src/taxonomy-resolver.ts` | TaxonomyResolver interface (Phase 10) |
| `CONST:LINEARITY` | `packages/protocol-types/src/constants.ts` | Linearity enum (RELEVANT = 3) |
| `UTIL:CREATEADAPTER` | `packages/protocol-types/src/adapters/create-adapter.ts` | Adapter factory pattern |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming convention, branch rules |

---

## Deliverables

### D26E.1 — NodeConfig Type Definition

**New file**: `packages/protocol-types/src/node-config.ts`

The single configuration object that fully describes a node by its four adapter choices plus metadata.

```typescript
/**
 * NodeConfig — complete description of a Semantos node.
 *
 * A node is uniquely identified by its four adapter choices plus metadata.
 * This object is serialized to node-config.json for filesystem-based deployment.
 */
export interface NodeConfig {
  // === Four Adapter Choices ===

  /** StorageAdapter implementation. Loaded from adapter name or factory. */
  storage: StorageAdapter;

  /** IdentityAdapter implementation. Loaded from adapter name or factory. */
  identity: IdentityAdapter;

  /** AnchorAdapter implementation. Loaded from adapter name or factory. */
  anchor: AnchorAdapter;

  /** NetworkAdapter implementation. Loaded from adapter name or factory. */
  network: NetworkAdapter;

  // === Node Identity ===

  /** Organization's Plexus cert ID. The node presents this cert when bootstrapping. */
  nodeCert: string;

  // === Optional Deployment Metadata ===

  /** BCA (Blockchain Certified Address) for this node. Not set on developer laptops. */
  bcaAddress?: string;

  /** Subnet prefix for local network discovery (IPv6 or IPv4 CIDR). */
  subnetPrefix?: string;

  /** Paths to vertical config directories. Relative or absolute. */
  verticals: string[];

  /** Optional: BYOK (bring-your-own-key) for OpenRouter LLM inference. */
  openRouterKey?: string;

  /** Optional: OpenRouter model to use (e.g. "openrouter/auto"). */
  openRouterModel?: string;

  /** Anchor interval in milliseconds (0 = no anchoring). Default 10min (600000ms). */
  anchorIntervalMs?: number;

  /** Optional: Root path for NodeFsAdapter (if used). Defaults to ~/.semantos/ */
  dataDir?: string;
}

/**
 * NodeConfigSchema — JSON schema for filesystem-based node config loading.
 *
 * node-config.json layout:
 * {
 *   "nodeCert": "0xabc123...",
 *   "storage": { "type": "node-fs", "root": "/var/semantos/data" },
 *   "identity": { "type": "local", "localDir": "/var/semantos/certs" },
 *   "anchor": { "type": "bsv", "interval": 600000 },
 *   "network": { "type": "bsv-overlay", "endpoint": "..." },
 *   "bcaAddress": "2602:f9f8:...",
 *   "verticals": ["./configs/extensions/trades", "./configs/extensions/sovereignty"],
 *   "openRouterKey": "sk-or-...",
 *   "anchorIntervalMs": 600000
 * }
 */
export interface NodeConfigFile {
  nodeCert: string;
  storage: {
    type: string; // 'node-fs' | 'memory' | 'opfs' | 'indexed-db' | 'bsv-overlay'
    [key: string]: any; // adapter-specific config
  };
  identity: {
    type: string; // 'local' | 'cloud'
    [key: string]: any;
  };
  anchor: {
    type: string; // 'bsv' | 'stub'
    [key: string]: any;
  };
  network: {
    type: string; // 'bsv-overlay' | 'direct' | 'stub'
    [key: string]: any;
  };
  bcaAddress?: string;
  subnetPrefix?: string;
  verticals: string[];
  openRouterKey?: string;
  openRouterModel?: string;
  anchorIntervalMs?: number;
  dataDir?: string;
}
```

### D26E.2 — createNode(config) Bootstrap Function

**New file**: `packages/protocol-types/src/node.ts`

```typescript
/**
 * createNode — instantiate and bootstrap a Semantos node.
 *
 * Flow:
 * 1. Validate NodeConfig (all four adapters present, required fields set)
 * 2. Initialize CellStore and SemanticFS from storage adapter
 * 3. Create or load node cert via identity adapter
 * 4. Create the node self-object (sovereignty.node.{cert_id}) as RELEVANT
 * 5. Start anchor scheduler if interval > 0
 * 6. Start network listener
 * 7. Return SemantosNode handle
 *
 * @param config - NodeConfig with four adapter choices + metadata
 * @returns SemantosNode handle (ready to call start())
 * @throws Error if config is invalid or adapters fail to initialize
 */
export async function createNode(config: NodeConfig): Promise<SemantosNode> {
  // Validate config
  if (!config.nodeCert) throw new Error('NodeConfig.nodeCert is required');
  if (!config.storage) throw new Error('NodeConfig.storage adapter is required');
  if (!config.identity) throw new Error('NodeConfig.identity adapter is required');
  if (!config.anchor) throw new Error('NodeConfig.anchor adapter is required');
  if (!config.network) throw new Error('NodeConfig.network adapter is required');
  if (!config.verticals || config.verticals.length === 0) {
    throw new Error('NodeConfig.verticals must include at least one vertical');
  }

  // Initialize storage and semantic fs
  const cellStore = new CellStore(config.storage);
  const taxonomyResolver = await loadTaxonomy(config.verticals);
  const semanticFs = new SemanticFS({
    cellStore,
    adapter: config.storage,
    taxonomy: taxonomyResolver,
  });

  // Load or create node identity
  let nodeIdentity = await config.identity.resolveIdentity(config.nodeCert);
  if (!nodeIdentity) {
    // First boot: register the node cert
    nodeIdentity = await config.identity.registerIdentity(`node-${config.nodeCert}`);
  }

  // Create node self-object as RELEVANT semantic object
  const nodeObject = await createNodeSelfObject(
    config,
    nodeIdentity.certId,
    semanticFs,
  );

  // Instantiate the node
  const node = new SemantosNode(
    config,
    nodeObject,
    config.storage,
    config.identity,
    config.anchor,
    config.network,
    cellStore,
    semanticFs,
  );

  return node;
}

/**
 * Helper: Load all vertical taxonomies from filesystem paths.
 * Returns merged TaxonomyResolver.
 */
async function loadTaxonomy(verticalPaths: string[]): Promise<TaxonomyResolver> {
  // Implementation: read vertical config JSONs, merge into single taxonomy
  // See Phase 26F for details
}

/**
 * Helper: Create the node self-object (sovereignty.node.{cert_id}).
 * This is a RELEVANT object describing the node's current state.
 */
async function createNodeSelfObject(
  config: NodeConfig,
  nodeCertId: string,
  semanticFs: SemanticFS,
): Promise<CellRef> {
  const payload = {
    bcaAddress: config.bcaAddress || null,
    verticals: config.verticals,
    capabilities: [], // TODO: query active capabilities from identity adapter
    version: '1.0.0',
    uptime: 0, // Will be updated on node start
    lastAnchor: null,
    adapters: {
      storage: config.storage.constructor.name,
      identity: config.identity.constructor.name,
      anchor: config.anchor.constructor.name,
      network: config.network.constructor.name,
    },
  };

  const semanticPath = `objects/sovereignty/node/${nodeCertId}`;
  const ref = await semanticFs.put(
    semanticPath,
    new TextEncoder().encode(JSON.stringify(payload)),
    {
      linearity: Linearity.RELEVANT,
      ownerId: hexToBytes(nodeCertId),
    },
  );

  return ref;
}
```

### D26E.3 — SemantosNode Interface and Implementation

**New file**: `packages/protocol-types/src/types/semantos-node.ts`

```typescript
/**
 * SemantosNode — handle to a running Semantos node.
 *
 * Represents all four adapters, the node configuration, and the node self-object.
 * The node is the unit of deployment and administration.
 */
export interface SemantosNode {
  // === Configuration ===

  /** The NodeConfig used to instantiate this node. Read-only. */
  readonly config: NodeConfig;

  /** The node self-object (sovereignty.node.{cert_id}). Read-only. */
  readonly nodeObject: CellRef;

  // === Adapters ===

  /** Storage adapter — where bytes live. */
  readonly storage: StorageAdapter;

  /** Identity adapter — who you are, what you can do. */
  readonly identity: IdentityAdapter;

  /** Anchor adapter — proving things existed. */
  readonly anchor: AnchorAdapter;

  /** Network adapter — how objects move. */
  readonly network: NetworkAdapter;

  // === Core Services ===

  /** Cell store wrapping the storage adapter. */
  readonly cellStore: CellStore;

  /** Semantic filesystem — taxonomy-aware object layer. */
  readonly semanticFs: SemanticFS;

  // === Lifecycle ===

  /**
   * Start the node.
   *
   * - Begin listening for network messages
   * - Start anchor scheduler
   * - Update node self-object with startup timestamp
   * - Begin accepting shell commands scoped to nodeObject
   */
  start(): Promise<void>;

  /**
   * Graceful shutdown.
   *
   * - Stop anchor scheduler
   * - Close network listeners
   * - Flush pending writes
   * - Update node self-object with shutdown reason
   */
  stop(): Promise<void>;

  // === Status and Control ===

  /**
   * Get current node status.
   *
   * @returns NodeStatus with uptime, last anchor time, installed verticals, etc.
   */
  getStatus(): NodeStatus;

  /**
   * Refresh the node self-object with current state.
   *
   * Called on start, and periodically (e.g. every anchor cycle) to keep the
   * node self-object's uptime, adapter states, and capability list current.
   */
  updateNodeObject(): Promise<void>;
}

/**
 * NodeStatus — snapshot of node state.
 *
 * Returned by getStatus(). Used by admin shell and monitoring.
 */
export interface NodeStatus {
  /** Node cert ID. */
  nodeCert: string;

  /** BCA address if deployed. */
  bcaAddress: string | null;

  /** Whether the node is running. */
  running: boolean;

  /** Milliseconds since node.start() was called. */
  uptime: number;

  /** Timestamp of last anchor. Null if no anchor has succeeded yet. */
  lastAnchor: number | null;

  /** List of installed vertical names. */
  installedVerticals: string[];

  /** List of active identity certs. */
  activeIdentities: string[];

  /** Storage usage in bytes. */
  storageUsage: number;

  /** Adapter implementations currently in use. */
  adapters: {
    storage: string;
    identity: string;
    anchor: string;
    network: string;
  };

  /** Any errors or warnings from the last cycle. */
  diagnostics: string[];
}

/**
 * Implementation of SemantosNode.
 *
 * Private: use createNode() to instantiate.
 */
export class SemantosNodeImpl implements SemantosNode {
  readonly config: NodeConfig;
  readonly nodeObject: CellRef;
  readonly storage: StorageAdapter;
  readonly identity: IdentityAdapter;
  readonly anchor: AnchorAdapter;
  readonly network: NetworkAdapter;
  readonly cellStore: CellStore;
  readonly semanticFs: SemanticFS;

  private running = false;
  private startTime: number | null = null;
  private anchorScheduler: NodeJS.Timer | null = null;
  private lastAnchor: number | null = null;
  private diagnostics: string[] = [];

  constructor(
    config: NodeConfig,
    nodeObject: CellRef,
    storage: StorageAdapter,
    identity: IdentityAdapter,
    anchor: AnchorAdapter,
    network: NetworkAdapter,
    cellStore: CellStore,
    semanticFs: SemanticFS,
  ) {
    this.config = config;
    this.nodeObject = nodeObject;
    this.storage = storage;
    this.identity = identity;
    this.anchor = anchor;
    this.network = network;
    this.cellStore = cellStore;
    this.semanticFs = semanticFs;
  }

  async start(): Promise<void> {
    if (this.running) return;

    this.running = true;
    this.startTime = Date.now();
    this.diagnostics = [];

    // Start anchor scheduler if enabled
    if (this.config.anchorIntervalMs && this.config.anchorIntervalMs > 0) {
      this.anchorScheduler = setInterval(async () => {
        try {
          // TODO: Run an anchor cycle
          this.lastAnchor = Date.now();
        } catch (err) {
          this.diagnostics.push(`Anchor failed: ${err}`);
        }
      }, this.config.anchorIntervalMs);
    }

    // Update node self-object
    await this.updateNodeObject();
  }

  async stop(): Promise<void> {
    if (!this.running) return;

    this.running = false;

    // Stop anchor scheduler
    if (this.anchorScheduler) {
      clearInterval(this.anchorScheduler);
      this.anchorScheduler = null;
    }

    // Update node self-object with shutdown reason
    await this.updateNodeObject();
  }

  getStatus(): NodeStatus {
    return {
      nodeCert: this.config.nodeCert,
      bcaAddress: this.config.bcaAddress || null,
      running: this.running,
      uptime: this.running && this.startTime ? Date.now() - this.startTime : 0,
      lastAnchor: this.lastAnchor,
      installedVerticals: this.config.verticals,
      activeIdentities: [], // TODO: query from identity adapter
      storageUsage: 0, // TODO: compute from storage adapter
      adapters: {
        storage: this.storage.constructor.name,
        identity: this.identity.constructor.name,
        anchor: this.anchor.constructor.name,
        network: this.network.constructor.name,
      },
      diagnostics: this.diagnostics,
    };
  }

  async updateNodeObject(): Promise<void> {
    const status = this.getStatus();
    const payload = {
      ...status,
      timestamp: Date.now(),
    };

    await this.semanticFs.put(
      `objects/sovereignty/node/${this.config.nodeCert}`,
      new TextEncoder().encode(JSON.stringify(payload)),
      {
        linearity: Linearity.RELEVANT,
        ownerId: hexToBytes(this.config.nodeCert),
        reason: 'status update',
      },
    );
  }
}
```

### D26E.4 — NodeConfig Loader

**New file**: `packages/protocol-types/src/node-config-loader.ts`

```typescript
/**
 * loadNodeConfig — load and validate a NodeConfig from a JSON file.
 *
 * Resolves adapter names to implementations:
 * - 'node-fs' → NodeFsAdapter
 * - 'memory' → MemoryAdapter
 * - 'local' → LocalIdentityAdapter
 * - 'bsv' → BsvAnchorAdapter
 * - etc.
 *
 * Supports CLI flag overrides (--cert, --subnet, --port, etc).
 *
 * @param configPath - path to node-config.json
 * @param cliOverrides - optional command-line flag overrides
 * @returns resolved NodeConfig
 * @throws Error if config is invalid or adapter factory fails
 */
export async function loadNodeConfig(
  configPath: string,
  cliOverrides?: Record<string, any>,
): Promise<NodeConfig> {
  // 1. Read JSON file
  const configFile = await readJsonFile(configPath) as NodeConfigFile;

  // 2. Resolve adapter factories
  const storage = await createStorageAdapter(configFile.storage);
  const identity = await createIdentityAdapter(configFile.identity);
  const anchor = await createAnchorAdapter(configFile.anchor);
  const network = await createNetworkAdapter(configFile.network);

  // 3. Build NodeConfig
  const config: NodeConfig = {
    nodeCert: cliOverrides?.cert || configFile.nodeCert,
    storage,
    identity,
    anchor,
    network,
    bcaAddress: cliOverrides?.bcaAddress || configFile.bcaAddress,
    subnetPrefix: cliOverrides?.subnetPrefix || configFile.subnetPrefix,
    verticals: configFile.verticals,
    openRouterKey: cliOverrides?.openRouterKey || configFile.openRouterKey,
    openRouterModel: cliOverrides?.openRouterModel || configFile.openRouterModel,
    anchorIntervalMs: cliOverrides?.anchorIntervalMs || configFile.anchorIntervalMs || 600000,
    dataDir: cliOverrides?.dataDir || configFile.dataDir,
  };

  return config;
}

/**
 * Adapter factory functions (delegating to existing create-adapter utilities).
 */
async function createStorageAdapter(spec: any): Promise<StorageAdapter> {
  const { type, ...options } = spec;
  if (type === 'node-fs') {
    const { NodeFsAdapter } = await import('./adapters/node-fs-adapter');
    return new NodeFsAdapter(options.root);
  }
  if (type === 'memory') {
    const { MemoryAdapter } = await import('./adapters/memory-adapter');
    return new MemoryAdapter();
  }
  // ... more storage adapters
  throw new Error(`Unknown storage adapter type: ${type}`);
}

async function createIdentityAdapter(spec: any): Promise<IdentityAdapter> {
  const { type, ...options } = spec;
  if (type === 'local') {
    const { LocalIdentityAdapter } = await import('./adapters/local-identity-adapter');
    return new LocalIdentityAdapter(options.localDir);
  }
  if (type === 'cloud') {
    const { CloudIdentityAdapter } = await import('./adapters/cloud-identity-adapter');
    return new CloudIdentityAdapter(options.endpoint);
  }
  // ... more identity adapters
  throw new Error(`Unknown identity adapter type: ${type}`);
}

async function createAnchorAdapter(spec: any): Promise<AnchorAdapter> {
  const { type, ...options } = spec;
  if (type === 'bsv') {
    const { BsvAnchorAdapter } = await import('./adapters/bsv-anchor-adapter');
    return new BsvAnchorAdapter(options);
  }
  if (type === 'stub') {
    const { StubAnchorAdapter } = await import('./adapters/stub-anchor-adapter');
    return new StubAnchorAdapter();
  }
  // ... more anchor adapters
  throw new Error(`Unknown anchor adapter type: ${type}`);
}

async function createNetworkAdapter(spec: any): Promise<NetworkAdapter> {
  const { type, ...options } = spec;
  if (type === 'bsv-overlay') {
    const { BsvOverlayNetworkAdapter } = await import('./adapters/bsv-overlay-network-adapter');
    return new BsvOverlayNetworkAdapter(options);
  }
  if (type === 'direct') {
    const { DirectNetworkAdapter } = await import('./adapters/direct-network-adapter');
    return new DirectNetworkAdapter(options);
  }
  // ... more network adapters
  throw new Error(`Unknown network adapter type: ${type}`);
}
```

---

## Gate Tests (T1–T15)

Create `packages/__tests__/phase26e-gate.test.ts`.

### Unit Tests (T1–T7)

```typescript
describe("NodeConfig and createNode", () => {
  // T1: NodeConfig validates with all four adapters present
  // T2: createNode rejects missing nodeCert
  // T3: createNode rejects missing verticals
  // T4: createNode initializes CellStore and SemanticFS
  // T5: createNode creates node self-object as RELEVANT
  // T6: node.start() sets running=true, starts anchor scheduler
  // T7: node.stop() sets running=false, clears anchor scheduler
});
```

### Integration Tests (T8–T12)

```typescript
describe("SemantosNode lifecycle", () => {
  // T8: createNode with stub adapters → node is ready
  // T9: node.start() then node.getStatus() shows uptime > 0
  // T10: node.stop() clears uptime
  // T11: node.updateNodeObject() refreshes the self-object with current status
  // T12: node.nodeObject is a RELEVANT CellRef with correct linearity
});
```

### Config Loading Tests (T13–T15)

```typescript
describe("loadNodeConfig and adapter factories", () => {
  // T13: loadNodeConfig reads JSON file and resolves adapters
  // T14: CLI overrides (--cert, --subnet) override JSON values
  // T15: Invalid adapter type throws Error with clear message
});
```

---

## Completion Criteria

- [ ] `packages/protocol-types/src/node-config.ts` exists with NodeConfig type and NodeConfigFile schema
- [ ] `packages/protocol-types/src/node.ts` exists with createNode() function and helper functions
- [ ] `packages/protocol-types/src/types/semantos-node.ts` exists with SemantosNode interface and SemantosNodeImpl class
- [ ] `packages/protocol-types/src/node-config-loader.ts` exists with loadNodeConfig() and adapter factories
- [ ] All four adapters (Phase 26A, 26B, 26C, 26D) are properly imported and used
- [ ] Node self-object is created as RELEVANT during bootstrap
- [ ] Anchor scheduler can be disabled via config.anchorIntervalMs = 0
- [ ] Tests T1–T15 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All commits follow `phase-26e/D26E.N:` naming convention
- [ ] Branch is `phase-26e-node-bootstrap`

---

## Next Phase

Phase 26F implements vertical loading from filesystem-based config directories. Phase 26G packages the node as Docker and provides install scripts for VPS deployment.
