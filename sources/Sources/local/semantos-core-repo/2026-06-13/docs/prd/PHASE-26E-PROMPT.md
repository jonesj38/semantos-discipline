---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26E-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.719538+00:00
---

# Phase 26E Execution Prompt — Node Bootstrap & Self-Object

> Paste this prompt into a fresh session to execute Phase 26E.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer for Bitcoin-native semantic objects. The kernel (cell engine, 2-PDA, linearity enforcement) is Zig/WASM in the sibling `semantos` repo. Phase 25A–D implemented four adapter interfaces for storage, identity (identity.ts), anchoring (anchor.ts), and networking (network.ts). Each adapter has a stub implementation for development and at least one production implementation.

Your task is Phase 26E: assemble the four adapters into a deployable Semantos node. Define `NodeConfig`, implement `createNode()`, and wire the node to self-describe as a RELEVANT semantic object. After this phase, a Semantos node is a runnable, administrable unit that knows about itself.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are building on top of. If you haven't read them, you will produce code that doesn't integrate.

**Read first** (the Phase 26E PRD — your requirements):
- `docs/prd/PHASE-26E-NODE-BOOTSTRAP.md` — Complete Phase 26E spec with deliverables D26E.1–D26E.4, gate tests T1–T15, completion criteria

**Read second** (the Phase 26 master and prerequisites):
- `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` — Context on the four adapters, deployment profiles, node object design
- `docs/prd/PLATFORM-ARCHITECTURE.md` — **Product context.** The node bootstrap creates the foundation for multi-vertical deployment. A PM agency node loads property + trades verticals. A tradie node loads trades only. The dispatch envelope works because both nodes run the same kernel with the same semantic object format — NodeConfig just has different vertical paths.
- `docs/prd/PHASE-26A-IDENTITY-EXTRACTION.md` — IdentityAdapter interface and implementations
- `docs/prd/PHASE-26B-LOCAL-IDENTITY.md` — LocalIdentityAdapter implementation
- `docs/prd/PHASE-26C-ANCHOR-ADAPTER.md` — AnchorAdapter interface and BsvAnchorAdapter
- `docs/prd/PHASE-26D-NETWORK-ADAPTER.md` — NetworkAdapter interface and implementations

**Read third** (the Phase 25 storage and semantic layers):
- `docs/prd/PHASE-25A-STORAGE-ADAPTER.md` — StorageAdapter interface (complete reference)
- `docs/prd/PHASE-25B-CELL-STORE.md` — CellStore interface
- `docs/prd/PHASE-25C-SEMANTIC-FS.md` — SemanticFS interface
- `docs/prd/PHASE-25D-BSV-OVERLAY.md` — BsvOverlayAdapter as reference implementation

**Read fourth** (the types you are integrating with):
- `packages/protocol-types/src/storage.ts` — StorageAdapter interface
- `packages/protocol-types/src/identity.ts` — IdentityAdapter interface
- `packages/protocol-types/src/anchor.ts` — AnchorAdapter interface
- `packages/protocol-types/src/network.ts` — NetworkAdapter interface
- `packages/protocol-types/src/cell-store.ts` — CellStore interface
- `packages/protocol-types/src/semantic-fs.ts` — SemanticFS interface
- `packages/protocol-types/src/taxonomy-resolver.ts` — TaxonomyResolver interface
- `packages/protocol-types/src/constants.ts` — Linearity enum (RELEVANT = 3)
- `packages/protocol-types/src/adapters/create-adapter.ts` — Adapter factory pattern

**Read fifth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-26e-node-bootstrap`. Commits as `phase-26e/D26E.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO STUBS IN PHASE 26E

Every function must do real work. `NodeConfig` is a real configuration object with four pluggable adapter slots. `createNode()` is a real bootstrap sequence. `SemantosNode` is a real handle with real lifecycle methods. If a function body is `throw new Error("not implemented")` or returns `undefined`, you have failed.

### 2. ALL FOUR ADAPTERS MUST BE PLUGGABLE

`NodeConfig` takes four adapters as properties (not factory names). This means you can instantiate a node with:
```typescript
const node = await createNode({
  nodeCert: "0x...",
  storage: new NodeFsAdapter('/data'),
  identity: new LocalIdentityAdapter('/certs'),
  anchor: new BsvAnchorAdapter({ ... }),
  network: new BsvOverlayNetworkAdapter({ ... }),
  verticals: ['trades', 'sovereignty'],
});
```

The `loadNodeConfig()` function WRAPS this by reading a JSON file and calling the adapter factories. The config object itself is adapter-agnostic.

### 3. NODE SELF-OBJECT IS RELEVANT

The node creates a `sovereignty.node.{cert_id}` RELEVANT semantic object. This is not DEBUG or AFFINE. This means:
- It persists across writes
- It cannot be deleted
- It is the admin interface to the node
- Commands scoped to it require governance consent

### 4. SEMANTIC FS, NOT RAW STORAGE

`createNode()` must use `SemanticFS` to write the node self-object, not raw storage. The path must be `"objects/sovereignty/node/{cert_id}"`. The taxonomy resolver must be initialized from the vertical configs.

### 5. ANCHOR SCHEDULER IS OPTIONAL

`config.anchorIntervalMs` can be 0. If so, anchoring is disabled. The node still runs; it just doesn't anchor. Set a reasonable default (600000ms = 10 min) if not specified.

### 6. TESTS MUST USE REAL ADAPTERS (STUBS OK)

Tests can use stub adapters (StubStorageAdapter, StubIdentityAdapter, etc), but they must be REAL stubs that actually work, not mocks that hardcode responses. When you create a node and call `node.start()`, something real must happen.

### 7. TAXONOMY LOADING IS PHASE 26F

You do NOT implement vertical config loading from disk in 26E. You do NOT implement directory scanning. The `loadTaxonomy()` helper is a PLACEHOLDER. Phase 26F will implement it.

For now, your `createNode()` test fixtures must pass pre-built TaxonomyResolver instances or use an empty taxonomy for testing.

### 8. NO HARDCODED PATHS

Do not hardcode `/var/semantos/data` or `~/.semantos/` in the code. These go in `NodeConfig.dataDir` (optional, with sensible defaults in the loader). The node itself is path-agnostic.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify prerequisites are complete

Phases 26A, 26B, 26C, 26D must be complete. Check:

```bash
# Adapter interfaces exist
ls packages/protocol-types/src/identity.ts
ls packages/protocol-types/src/anchor.ts
ls packages/protocol-types/src/network.ts

# At least stub implementations exist
ls packages/protocol-types/src/adapters/stub-identity-adapter.ts
ls packages/protocol-types/src/adapters/stub-anchor-adapter.ts
ls packages/protocol-types/src/adapters/stub-network-adapter.ts

# Phase 25 (storage, cell store, semantic fs) is complete
ls packages/protocol-types/src/storage.ts
ls packages/protocol-types/src/cell-store.ts
ls packages/protocol-types/src/semantic-fs.ts
```

All files must exist and be complete (not stubbed). If anything is missing, STOP and escalate.

### 0.4 Create Phase 26E branch

```bash
git checkout -b phase-26e-node-bootstrap
```

---

## Step 1: NodeConfig Type Definition (D26E.1)

Create `packages/protocol-types/src/node-config.ts`.

This defines the configuration object that a Semantos node needs. Key points:

- `NodeConfig` is the runtime config object with four adapters as properties (StorageAdapter, IdentityAdapter, AnchorAdapter, NetworkAdapter)
- `NodeConfigFile` is the JSON schema for filesystem-based loading (has `type: string` instead of adapter instances)
- Document both well in JSDoc

The storage, identity, anchor, network properties are the actual adapter instances (not strings). The loader will instantiate these from names.

Commit: `phase-26e/D26E.1: NodeConfig type — four adapter slots plus deployment metadata`

---

## Step 2: createNode Bootstrap Function (D26E.2)

Create `packages/protocol-types/src/node.ts`.

Implement:

- `createNode(config: NodeConfig)` — validates config, initializes adapters, creates node self-object, returns SemantosNode
- `loadTaxonomy(verticalPaths: string[])` — PLACEHOLDER. Returns an empty TaxonomyResolver for now. Phase 26F will implement.
- `createNodeSelfObject(config, nodeCertId, semanticFs)` — creates the sovereignty.node.{cert_id} RELEVANT object with current state
- Helper to compute storage adapter name from instance (for diagnostics)

Key behavior:

- Validate that all four adapters are present before proceeding
- Initialize CellStore and SemanticFS from the storage adapter
- Resolve or register the node's identity cert
- Create the node self-object as RELEVANT (linearity: Linearity.RELEVANT)
- Return a SemantosNode handle (not started yet)

Commit: `phase-26e/D26E.2: createNode() bootstrap function — init adapters, create node self-object`

---

## Step 3: SemantosNode Interface and Implementation (D26E.3)

Create `packages/protocol-types/src/types/semantos-node.ts`.

Implement:

- `SemantosNode` interface with all properties and methods
- `NodeStatus` interface for status snapshots
- `SemantosNodeImpl` class implementing SemantosNode

Key methods:

- `start()` — Set running = true, start timestamp, start anchor scheduler (if enabled), update node self-object
- `stop()` — Set running = false, clear scheduler, update node self-object
- `getStatus()` — Return current uptime, last anchor time, adapter names, diagnostics
- `updateNodeObject()` — Refresh the node self-object at `objects/sovereignty/node/{cert_id}` with current status

The class is private; callers use `createNode()`.

Commit: `phase-26e/D26E.3: SemantosNode interface and implementation — lifecycle and status`

---

## Step 4: NodeConfig Loader (D26E.4)

Create `packages/protocol-types/src/node-config-loader.ts`.

Implement:

- `loadNodeConfig(configPath, cliOverrides)` — reads JSON file, resolves adapter factories, applies CLI overrides, returns NodeConfig
- `createStorageAdapter(spec)` — factory for storage adapters (node-fs, memory, opfs, indexed-db, bsv-overlay)
- `createIdentityAdapter(spec)` — factory for identity adapters (local, cloud)
- `createAnchorAdapter(spec)` — factory for anchor adapters (bsv, stub)
- `createNetworkAdapter(spec)` — factory for network adapters (bsv-overlay, direct, stub)

Each factory takes a spec object with `{ type: string, ...options }` and returns an adapter instance.

CLI overrides can override `nodeCert`, `bcaAddress`, `subnetPrefix`, `openRouterKey`, `openRouterModel`, `anchorIntervalMs`, `dataDir`.

Commit: `phase-26e/D26E.4: NodeConfig loader — JSON parsing, adapter factories, CLI overrides`

---

## Step 5: Gate Tests

Create `packages/__tests__/phase26e-gate.test.ts`.

### Unit Tests (T1–T7)

```typescript
describe("NodeConfig and createNode", () => {
  // T1: NodeConfig validates with all four adapters present
  test("NodeConfig accepts all four adapters", () => {
    const config: NodeConfig = {
      nodeCert: "0xabc123",
      storage: new StubStorageAdapter(),
      identity: new StubIdentityAdapter(),
      anchor: new StubAnchorAdapter(),
      network: new StubNetworkAdapter(),
      verticals: ['trades'],
    };
    expect(config).toBeDefined();
    expect(config.storage).toBeDefined();
  });

  // T2: createNode rejects missing nodeCert
  test("createNode rejects missing nodeCert", async () => {
    const config = { /* missing nodeCert */ } as any;
    await expect(createNode(config)).rejects.toThrow('nodeCert is required');
  });

  // T3: createNode rejects missing verticals
  test("createNode rejects missing verticals", async () => {
    const config = {
      nodeCert: "0xabc",
      storage: new StubStorageAdapter(),
      identity: new StubIdentityAdapter(),
      anchor: new StubAnchorAdapter(),
      network: new StubNetworkAdapter(),
      // missing verticals
    } as any;
    await expect(createNode(config)).rejects.toThrow('verticals');
  });

  // T4: createNode initializes CellStore and SemanticFS
  test("createNode initializes CellStore and SemanticFS", async () => {
    const config = {
      nodeCert: "0xabc123",
      storage: new StubStorageAdapter(),
      identity: new StubIdentityAdapter(),
      anchor: new StubAnchorAdapter(),
      network: new StubNetworkAdapter(),
      verticals: ['trades'],
    };
    const node = await createNode(config);
    expect(node.cellStore).toBeDefined();
    expect(node.semanticFs).toBeDefined();
  });

  // T5: createNode creates node self-object as RELEVANT
  test("createNode creates node self-object with RELEVANT linearity", async () => {
    const config = { /* valid config */ };
    const node = await createNode(config);
    expect(node.nodeObject).toBeDefined();
    expect(node.nodeObject.key).toContain('sovereignty/node');
  });

  // T6: node.start() sets running=true, starts scheduler
  test("node.start() sets running=true and starts anchor scheduler", async () => {
    const config = { anchorIntervalMs: 1000 /* ... */ };
    const node = await createNode(config);
    await node.start();
    const status = node.getStatus();
    expect(status.running).toBe(true);
    expect(status.uptime).toBeGreaterThan(0);
  });

  // T7: node.stop() sets running=false, clears scheduler
  test("node.stop() sets running=false and clears scheduler", async () => {
    const node = await createNode({ /* valid config */ });
    await node.start();
    await node.stop();
    const status = node.getStatus();
    expect(status.running).toBe(false);
  });
});
```

### Integration Tests (T8–T12)

```typescript
describe("SemantosNode lifecycle", () => {
  // T8: createNode with stub adapters → node is ready
  test("createNode with stubs returns ready node", async () => {
    const node = await createNode(buildStubConfig());
    expect(node.config).toBeDefined();
    expect(node.nodeObject).toBeDefined();
    expect(node.storage).toBeInstanceOf(StubStorageAdapter);
  });

  // T9: node.start() then node.getStatus() shows uptime > 0
  test("node.getStatus() shows uptime after start", async () => {
    const node = await createNode(buildStubConfig());
    await node.start();
    await new Promise(r => setTimeout(r, 10));
    const status = node.getStatus();
    expect(status.uptime).toBeGreaterThan(0);
  });

  // T10: node.stop() clears uptime
  test("node.getStatus() shows uptime=0 after stop", async () => {
    const node = await createNode(buildStubConfig());
    await node.start();
    await node.stop();
    const status = node.getStatus();
    expect(status.uptime).toBe(0);
    expect(status.running).toBe(false);
  });

  // T11: node.updateNodeObject() refreshes the self-object
  test("node.updateNodeObject() refreshes self-object", async () => {
    const node = await createNode(buildStubConfig());
    await node.start();
    const before = node.nodeObject;
    await new Promise(r => setTimeout(r, 50));
    await node.updateNodeObject();
    const after = node.nodeObject;
    // New version should have updated timestamp
    expect(after.timestamp).toBeGreaterThanOrEqual(before.timestamp);
  });

  // T12: node.nodeObject is RELEVANT
  test("node.nodeObject has RELEVANT linearity", async () => {
    const node = await createNode(buildStubConfig());
    const cellValue = await node.semanticFs.get(`objects/sovereignty/node/${node.config.nodeCert}`);
    expect(cellValue.header.linearity).toBe(Linearity.RELEVANT);
  });
});
```

### Config Loading Tests (T13–T15)

```typescript
describe("loadNodeConfig and adapter factories", () => {
  // T13: loadNodeConfig reads JSON file and resolves adapters
  test("loadNodeConfig loads and resolves adapters from JSON", async () => {
    const configPath = '/tmp/test-node-config.json';
    await fs.promises.writeFile(configPath, JSON.stringify({
      nodeCert: "0xtest123",
      storage: { type: "memory" },
      identity: { type: "local", localDir: "/tmp/certs" },
      anchor: { type: "stub" },
      network: { type: "stub" },
      verticals: ["trades"],
    }));
    const config = await loadNodeConfig(configPath);
    expect(config.nodeCert).toBe("0xtest123");
    expect(config.storage).toBeDefined();
    expect(config.identity).toBeDefined();
  });

  // T14: CLI overrides work
  test("loadNodeConfig applies CLI overrides", async () => {
    const config = await loadNodeConfig('/tmp/config.json', {
      cert: "0xcli123",
      anchorIntervalMs: 120000,
    });
    expect(config.nodeCert).toBe("0xcli123");
    expect(config.anchorIntervalMs).toBe(120000);
  });

  // T15: Invalid adapter type throws
  test("loadNodeConfig throws on invalid adapter type", async () => {
    const configPath = '/tmp/invalid-config.json';
    await fs.promises.writeFile(configPath, JSON.stringify({
      nodeCert: "0xtest",
      storage: { type: "invalid-storage-type" },
      identity: { type: "local" },
      anchor: { type: "stub" },
      network: { type: "stub" },
      verticals: ["trades"],
    }));
    await expect(loadNodeConfig(configPath)).rejects.toThrow(/Unknown storage adapter type/);
  });
});
```

Helper:
```typescript
function buildStubConfig(): NodeConfig {
  return {
    nodeCert: "0xtest123",
    storage: new StubStorageAdapter(),
    identity: new StubIdentityAdapter(),
    anchor: new StubAnchorAdapter(),
    network: new StubNetworkAdapter(),
    verticals: ['trades'],
    anchorIntervalMs: 600000,
  };
}
```

Commit: `phase-26e/T1-T15: full gate test suite — unit, integration, config loading`

---

## Step 6: CI Gate Extension

Verify the existing `.github/workflows/gate.yml` will pick up `packages/__tests__/phase26e-gate.test.ts` automatically.

No new lint checks needed for this phase (the four adapters are already defined in Phase 26A–D).

---

## Step 7: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review of every new file
2. Check that node.nodeObject.key resolves correctly to the sovereignty.node path
3. Check that node.getStatus() reflects accurate uptime (not off by a few ms)
4. Check that node.stop() properly clears the anchor scheduler (no dangling timers)
5. Check that createNode() rejects adapters that are null/undefined
6. Check that node self-object payload is valid JSON
7. Write errata doc as `docs/prd/PHASE-26E-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/protocol-types/src/node-config.ts` exists with NodeConfig and NodeConfigFile types
- [ ] `packages/protocol-types/src/node.ts` exists with createNode(), loadTaxonomy(), and createNodeSelfObject()
- [ ] `packages/protocol-types/src/types/semantos-node.ts` exists with SemantosNode, NodeStatus, and SemantosNodeImpl
- [ ] `packages/protocol-types/src/node-config-loader.ts` exists with loadNodeConfig() and adapter factories
- [ ] node.start() initializes anchor scheduler based on config.anchorIntervalMs
- [ ] node.stop() clears scheduler and updates node self-object
- [ ] node.getStatus() returns accurate uptime, lastAnchor, activeIdentities, storageUsage
- [ ] node self-object is written via SemanticFS (not raw storage)
- [ ] node self-object has RELEVANT linearity
- [ ] Tests T1–T15 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No `@plexus/*` imports (Phase 26 is adapter-clean)
- [ ] All commits follow `phase-26e/D26E.N:` naming convention
- [ ] Branch is `phase-26e-node-bootstrap`

---

## Next Phase

Phase 26F implements vertical config loading from filesystem directories. Phase 26G packages the node as Docker and provides a single-command install script.
