---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-37-KERNEL-BRIDGE-ADAPTER-WIRING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.667197+00:00
---

# Phase 37 — Kernel Bridge Adapter Wiring

> Wire the Navigator PWA kernel bridge to the real adapter stack (Storage, Identity, Anchor, Network) so extensions are discovered at runtime via ConsumerBindings, objects persist across sessions, and the BSV overlay network is reachable from the browser.

## Metadata

| Field | Value |
|-------|-------|
| Version | 1.0 |
| Date | April 2026 |
| Status | Ready for implementation |
| Duration | 3 weeks (4-day buffer) |
| Prerequisites | Phase 36E complete (Extension Manager UI), Phase 26B operational (LocalIdentityAdapter), Phase 30E (WASM target), configs split (navigator.json + consciousness.json) |
| Master Document | PLATFORM-ARCHITECTURE.md |
| Branch | `phase-37-kernel-bridge-adapter-wiring` |

---

## Context

The Navigator PWA currently runs a fake kernel. Two extension configs (navigator.json, consciousness.json) are statically imported at build time and baked into a JS bundle. Objects live in an in-memory `Map` that vanishes on page reload. There is no identity, no storage persistence, no BSV anchoring, and no network discovery. The "kernel" is a shim.

Meanwhile, the real adapter stack exists and is tested:

```
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

 MemoryAdapter  StubIdentity  StubAnchor  StubNetwork
 NodeFsAdapter  LocalIdentity BsvAnchor   BsvOverlayNetwork
 OpfsAdapter    (Cloud TBD)               DockerMulticast
 IndexedDb
 BsvOverlay
```

Each adapter is independently swappable. A node's deployment profile is the cartesian product of four choices. The browser PWA should use:

- **Storage**: OpfsAdapter (primary) or IndexedDbAdapter (fallback) — via `createAdapter()`
- **Identity**: LocalIdentityAdapter — offline cert chains, key derivation, capability tokens, Shamir recovery — backed by the storage adapter
- **Anchor**: StubAnchorAdapter initially, BsvAnchorAdapter when wallet connected
- **Network**: StubNetworkAdapter initially, BsvOverlayNetworkAdapter when online

The kernel bridge must also wire up the **ExtensionLoader** and **ExtensionRegistry** so extensions are discovered at runtime from storage, not embedded at build time.

### What Changes

```
Before:
  kernel-bridge.ts → import navigatorConfig from 'navigator.json'   (build-time)
                   → import consciousnessConfig from 'consciousness.json' (build-time)
                   → new Map() as object store                      (ephemeral)
                   → no identity, no anchoring, no network

After:
  kernel-bridge.ts → createAdapter()                    → OpfsAdapter / IndexedDb
                   → createIdentityAdapter('local')     → LocalIdentityAdapter
                   → createAnchorAdapter({ mode })      → Stub or BsvAnchorAdapter
                   → new StubNetworkAdapter()           → upgrades to BsvOverlay
                   → ExtensionLoader(storage)           → loads from storage
                   → ExtensionRegistry(nodeConfig)      → runtime activate/deactivate
                   → ConsumerBinding query              → discovers user's extensions
```

---

## Architecture

### Boot Sequence

The kernel bridge initializes asynchronously on page load:

```
1. createAdapter()
   ├── Browser with OPFS? → OpfsAdapter
   ├── Browser with IndexedDB? → IndexedDbAdapter
   └── Fallback → MemoryAdapter (warn)

2. createIdentityAdapter('local', { storage })
   └── LocalIdentityAdapter
       ├── CertChainStore(storage)
       ├── KeyDerivationService
       ├── CapabilityTokenValidator
       └── RecoveryShareManager(storage)

3. createAnchorAdapter({ mode: walletConnected ? 'bsv' : 'stub' })
   ├── StubAnchorAdapter (default, no wallet)
   └── BsvAnchorAdapter (when wallet/ownerKey available)

4. new StubNetworkAdapter() (default)
   └── upgrades to BsvOverlayNetworkAdapter when online

5. ExtensionLoader(storage)
   └── Seed bundled configs into storage on first boot

6. ExtensionRegistry(nodeConfig)
   ├── Query storage for ConsumerBinding objects
   ├── For each binding → loader.loadExtension(path)
   └── registry.activate(extensionId, path, loader)

7. Expose window.SemantosKernel with real adapters
```

### Extension Discovery Flow

Extensions are NOT hardcoded. Discovery follows this chain:

```
User Identity (cert)
  → query storage: list('bindings/{certId}/')
    → returns ConsumerBinding objects
      → each has extensionId + extensionPath
        → ExtensionLoader.loadExtension(path)
          → reads config.json from StorageAdapter
          → validates manifest
          → loads taxonomy, flows, prompts
            → ExtensionRegistry.activate()
```

On first boot (no bindings exist), the kernel seeds default extensions:

1. Write navigator.json and consciousness.json configs into StorageAdapter
2. Create ConsumerBinding objects for each
3. Normal discovery finds them on next boot

### Adapter Upgrade Path

Adapters can upgrade at runtime without page reload:

```
Wallet connects (CWI detected):
  → kernel.upgradeAnchor({ mode: 'bsv', ownerKey })
  → kernel.upgradeNetwork(new BsvOverlayNetworkAdapter({ ownerKey }))
  → status bar dots: anchor ● green, network ● green

Wallet disconnects:
  → kernel.downgradeAnchor() → StubAnchorAdapter
  → kernel.downgradeNetwork() → StubNetworkAdapter
  → status bar dots: anchor ● grey, network ● grey
```

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `BRIDGE` | `packages/navigation_app/bsv-app/kernel-bridge.ts` | Current shim. Replace static imports and in-memory Map with real adapters. Keep the public API surface (createObject, listObjects, etc.) stable. |
| `STORAGE:IF` | `packages/protocol-types/src/storage.ts` | StorageAdapter interface: read, write, exists, list, delete, stat, watch. |
| `STORAGE:FACTORY` | `packages/protocol-types/src/adapters/create-adapter.ts` | createAdapter() — auto-detects OpfsAdapter → IndexedDbAdapter → MemoryAdapter for browser. |
| `STORAGE:OPFS` | `packages/protocol-types/src/adapters/opfs-adapter.ts` | OpfsAdapter — browser Origin Private File System. Primary for PWA. |
| `STORAGE:IDB` | `packages/protocol-types/src/adapters/indexed-db-adapter.ts` | IndexedDbAdapter — browser IndexedDB fallback. |
| `IDENTITY:IF` | `packages/protocol-types/src/identity.ts` | IdentityAdapter interface: registerIdentity, deriveChild, resolveIdentity, presentCapability, etc. |
| `IDENTITY:FACTORY` | `packages/protocol-types/src/adapters/create-identity-adapter.ts` | createIdentityAdapter() — mode resolution via PLEXUS_MODE env or options. |
| `IDENTITY:LOCAL` | `packages/protocol-types/src/identity-adapters/LocalIdentityAdapter.ts` | LocalIdentityAdapter — offline cert chains, key derivation, capability tokens, Shamir recovery. Depends on StorageAdapter. |
| `ANCHOR:IF` | `packages/protocol-types/src/anchor.ts` | AnchorAdapter interface + createAnchorAdapter() factory. Modes: stub, bsv. |
| `ANCHOR:STUB` | `packages/protocol-types/src/adapters/stub-anchor-adapter.ts` | StubAnchorAdapter — deterministic in-memory. Default when no wallet. |
| `ANCHOR:BSV` | `packages/protocol-types/src/adapters/bsv-anchor-adapter.ts` | BsvAnchorAdapter — OP_RETURN transactions, SPV verification, Merkle batching. Needs ownerKey. |
| `NETWORK:IF` | `packages/protocol-types/src/network.ts` | NetworkAdapter interface: publish, subscribe, resolve, resolveBCA, sendToNode. |
| `NETWORK:STUB` | `packages/protocol-types/src/adapters/stub-network-adapter.ts` | StubNetworkAdapter — in-memory pub/sub. Default offline. |
| `NETWORK:BSV` | `packages/protocol-types/src/adapters/bsv-overlay-network-adapter.ts` | BsvOverlayNetworkAdapter — BRC-22 SHIP + BRC-24 SLAP. Production overlay. |
| `EXTLOADER` | `packages/protocol-types/src/extension-loader.ts` | ExtensionLoader — reads config.json, taxonomy, flows, prompts from StorageAdapter. |
| `EXTREG` | `packages/protocol-types/src/extension-registry.ts` | ExtensionRegistry — activate/deactivate/getAllActive/isActive. Capability-gated. |
| `EXTCONFIG` | `packages/loom/src/config/extensionConfig.ts` | ExtensionConfig type, validateExtensionConfig(). |
| `GOVERNANCE` | `packages/extraction/src/governance/constraint-engine.ts` | enforceL0Constraints, enforceL1Constraints. Keep governance checks on object creation. |
| `NAVIGATOR:JS` | `packages/navigation_app/bsv-app/navigator.js` | Vanilla JS app. Must consume real adapter state (connection status, object persistence, extension discovery). |

---

## Deliverables

### D37.1 — `KernelBridge` class (replaces `initKernel()`)

Replace the procedural `initKernel()` with a class that owns the four adapters:

```typescript
export class KernelBridge {
  storage: StorageAdapter;
  identity: IdentityAdapter;
  anchor: AnchorAdapter;
  network: NetworkAdapter;
  registry: ExtensionRegistry;
  loader: ExtensionLoader;

  private constructor(deps: KernelDeps) { ... }

  static async boot(): Promise<KernelBridge> {
    // 1. Storage
    const storage = await createAdapter();

    // 2. Identity
    const identity = await createIdentityAdapter({ mode: 'local', storage });

    // 3. Anchor (stub by default, upgradeable)
    const anchor = await createAnchorAdapter({ mode: 'stub' });

    // 4. Network (stub by default, upgradeable)
    const network = new StubNetworkAdapter();

    // 5. Extension discovery
    const loader = new ExtensionLoader(storage);
    const nodeConfig = await KernelBridge.loadOrCreateNodeConfig(storage);
    const registry = new ExtensionRegistry(nodeConfig);

    // 6. Seed defaults on first boot
    await KernelBridge.seedDefaults(storage, identity);

    // 7. Activate extensions from ConsumerBindings
    await KernelBridge.discoverExtensions(storage, identity, loader, registry);

    return new KernelBridge({ storage, identity, anchor, network, registry, loader });
  }
}
```

**Critical constraints**:
- `boot()` is async — the bridge loads after DOM, navigator.js waits for it
- All four adapters are independently replaceable at runtime
- The public API (createObject, listObjects, etc.) stays identical
- Objects read/write through `StorageAdapter`, not an in-memory `Map`

### D37.2 — First Boot Seeding

On first boot (no node config exists in storage), the kernel:

1. Creates a `NodeConfig` with default extension paths
2. Writes bundled extension configs (navigator.json, consciousness.json) into StorageAdapter at canonical paths:
   - `extensions/navigator-core/config.json`
   - `extensions/consciousness-process/config.json`
3. Registers the user's root identity via `identity.registerIdentity()`
4. Creates ConsumerBinding objects for default extensions
5. Persists NodeConfig to storage at `node/config.json`

Subsequent boots read NodeConfig from storage and skip seeding.

```typescript
static async seedDefaults(storage: StorageAdapter, identity: IdentityAdapter): Promise<void> {
  const exists = await storage.exists('node/config.json');
  if (exists) return; // Already seeded

  // Seed bundled configs
  const encoder = new TextEncoder();
  await storage.write('extensions/navigator-core/config.json', encoder.encode(JSON.stringify(navigatorConfig)));
  await storage.write('extensions/consciousness-process/config.json', encoder.encode(JSON.stringify(consciousnessConfig)));

  // Register root identity
  const { certId } = await identity.registerIdentity('local-user@semantos.local');

  // Create ConsumerBindings
  const bindings = [
    { extensionId: 'navigator-core', extensionPath: 'extensions/navigator-core' },
    { extensionId: 'consciousness-process', extensionPath: 'extensions/consciousness-process' },
  ];
  for (const b of bindings) {
    const key = `bindings/${certId}/${b.extensionId}`;
    await storage.write(key, encoder.encode(JSON.stringify(b)));
  }

  // Persist NodeConfig
  const nodeConfig = { extensions: bindings.map(b => b.extensionPath) };
  await storage.write('node/config.json', encoder.encode(JSON.stringify(nodeConfig)));
}
```

### D37.3 — Extension Discovery via ConsumerBindings

Replace static imports with runtime discovery:

```typescript
static async discoverExtensions(
  storage: StorageAdapter,
  identity: IdentityAdapter,
  loader: ExtensionLoader,
  registry: ExtensionRegistry,
): Promise<void> {
  // Get current user's cert
  const userCert = await KernelBridge.getCurrentCert(storage);

  // List all ConsumerBindings for this user
  const bindingKeys = await storage.list(`bindings/${userCert}/`);

  for (const key of bindingKeys) {
    const data = await storage.read(`bindings/${userCert}/${key}`);
    if (!data) continue;
    const binding = JSON.parse(new TextDecoder().decode(data));

    // Activate extension from storage
    await registry.activate(binding.extensionId, binding.extensionPath, loader);
  }
}
```

### D37.4 — Persistent Object Store

Replace the in-memory `ObjectStore` class with one backed by `StorageAdapter`:

```typescript
class PersistentObjectStore {
  constructor(private storage: StorageAdapter) {}

  async create(typeDef: ObjectTypeDefinition, fields?: Record<string, unknown>): Promise<string> {
    const id = crypto.randomUUID();
    const obj = { id, type: typeDef.name, fields: fields ?? {}, visibility: 'draft', createdAt: Date.now(), updatedAt: Date.now() };
    const key = `objects/${typeDef.name}/${id}`;
    await this.storage.write(key, new TextEncoder().encode(JSON.stringify(obj)));
    this.notify();
    return id;
  }

  async get(objectId: string): Promise<KernelObject | null> { ... }
  async list(typeFilter?: string): Promise<KernelObject[]> { ... }
  async patch(objectId: string, delta: Record<string, unknown>): Promise<boolean> { ... }
}
```

**Critical constraints**:
- Objects survive page reload (OPFS/IndexedDB)
- `list()` uses `storage.list('objects/')` with prefix matching
- Writes are atomic — write to temp key, then rename (or rely on adapter atomicity)
- Subscribe/notify pattern still works for UI reactivity

### D37.5 — Anchor Integration

Wire anchor adapter so objects are periodically anchored:

```typescript
// On object create/patch, queue state hash for anchoring
async createObject(typeName: string, fields?: Record<string, unknown>): Promise<string | null> {
  const id = await this.store.create(typeDef, fields);
  if (id) {
    const stateHash = await this.computeStateHash(id);
    this.pendingAnchors.push({ stateHash, objectPath: `objects/${typeName}/${id}` });
  }
  return id;
}

// Periodic anchor flush (configurable interval)
private async flushAnchors(): Promise<void> {
  if (this.pendingAnchors.length === 0) return;
  const items = this.pendingAnchors.splice(0);
  const proofs = await this.anchor.batchAnchor(items);
  // Store proofs
  for (const proof of proofs) {
    await this.storage.write(`anchors/${proof.stateHash}`, encode(proof));
  }
}
```

### D37.6 — Network Integration

Wire network adapter for object publication and discovery:

```typescript
// After object creation, publish to network
async createObject(typeName: string, fields?: Record<string, unknown>): Promise<string | null> {
  const id = await this.store.create(typeDef, fields);
  if (id && this.network.isConnected()) {
    await this.network.publish({
      cellBytes: await this.store.getCellBytes(id),
      semanticPath: `objects/${typeName}/${id}`,
      contentHash: await this.computeContentHash(id),
      ownerCert: this.currentCert,
      typeHash: typeDef.typeHash,
    });
  }
  return id;
}

// Subscribe to incoming objects from other nodes
this.network.subscribe('tm_semantos_objects', async (event) => {
  // Ingest into local store
  await this.store.ingest(event.result);
  this.notify();
});
```

### D37.7 — Adapter Upgrade/Downgrade

Runtime adapter swapping when wallet connects/disconnects:

```typescript
async upgradeAnchor(config: AnchorConfig): Promise<void> {
  this.anchor = await createAnchorAdapter(config);
  // Flush any pending anchors with new adapter
  await this.flushAnchors();
}

async upgradeNetwork(adapter: NetworkAdapter): Promise<void> {
  // Transfer subscriptions from old adapter
  this.network = adapter;
  this.resubscribe();
}

// CWI detection hook
onWalletConnect(cwi: CWI) {
  const ownerKey = cwi.getOwnerKey();
  this.upgradeAnchor({ mode: 'bsv', ownerKey });
  this.upgradeNetwork(new BsvOverlayNetworkAdapter({ ownerKey }));
}

onWalletDisconnect() {
  this.upgradeAnchor({ mode: 'stub' });
  this.upgradeNetwork(new StubNetworkAdapter());
}
```

### D37.8 — Navigator JS Async Boot

Update navigator.js to handle async kernel initialization:

```javascript
// Current (synchronous):
init() {
  this.detectKernel();
  this.renderExtensions();
}

// New (async, waits for real kernel):
async init() {
  this.renderLoading();

  // Wait for kernel to boot (adapters, identity, extension discovery)
  if (window.SemantosKernel) {
    this.kernel = await window.SemantosKernel;
  }

  this.updateStatusDots();
  this.renderExtensions();
  this.renderLensStrip();
  this.renderObjects();

  // Watch for wallet connect/disconnect
  this.watchWallet();
}

updateStatusDots() {
  document.getElementById('kernel-dot').className = this.kernel ? 'dot on' : 'dot off';
  document.getElementById('node-dot').className = this.kernel?.network?.isConnected() ? 'dot on' : 'dot off';
  document.getElementById('cwi-dot').className = this.cwi ? 'dot on' : 'dot off';
}
```

### D37.9 — Status Bar Adapter Indicators

Update the status bar to reflect real adapter state:

```
Navigator                    ● kernel  ● anchor  ● network  ● wallet
                             green     grey      grey       grey
                             (always)  (stub)    (stub)     (no CWI)

After wallet connects:
Navigator                    ● kernel  ● anchor  ● network  ● wallet
                             green     green     green      green
                             (always)  (bsv)     (overlay)  (CWI)
```

### D37.10 — Tests

```
packages/__tests__/kernel-bridge-boot.test.ts
```

| Test | Description |
|------|-------------|
| T1 | `KernelBridge.boot()` completes with MemoryAdapter in test env |
| T2 | First boot seeds navigator.json and consciousness.json into storage |
| T3 | First boot creates ConsumerBinding objects |
| T4 | Second boot skips seeding, loads from storage |
| T5 | `discoverExtensions()` activates extensions from ConsumerBindings |
| T6 | `createObject()` persists to StorageAdapter |
| T7 | `listObjects()` reads from StorageAdapter |
| T8 | Objects survive simulated page reload (new KernelBridge from same storage) |
| T9 | `upgradeAnchor('bsv')` switches from StubAnchor to BsvAnchor |
| T10 | `upgradeNetwork()` switches from StubNetwork to BsvOverlay |
| T11 | `createObject()` calls `network.publish()` when connected |
| T12 | Network subscription ingests remote objects into local store |
| T13 | Governance constraints (L0, L1) still enforced on createObject |
| T14 | `listExtensions()` returns extensions from registry, not hardcoded |

---

## Build Considerations

### Browser Bundle

The kernel bridge is built via:
```
bun build kernel-bridge.ts --outfile kernel-bridge.js --target=browser --minify
```

**Critical**: The adapter stack uses dynamic imports (`await import(...)`) to avoid pulling Node.js-only code into the browser bundle. The build must:

1. Tree-shake NodeFsAdapter (references `fs/promises`)
2. Tree-shake BsvAnchorAdapter and BsvOverlayNetworkAdapter unless explicitly imported
3. Include OpfsAdapter and IndexedDbAdapter (browser targets)
4. Include StubAnchorAdapter and StubNetworkAdapter (always available)
5. Bundle LocalIdentityAdapter with its sub-services (CertChainStore, KeyDerivationService, CapabilityTokenValidator, RecoveryShareManager)

If dynamic import doesn't tree-shake properly in Bun's bundler, use conditional `import()` statements guarded by environment checks, or split into separate entry points.

### Async Initialization

`KernelBridge.boot()` is async. The current pattern of synchronous `initKernel()` + `(window as any).SemantosKernel = kernel` must change to:

```typescript
// Option A: Promise on window
(window as any).SemantosKernel = KernelBridge.boot();
// navigator.js: const kernel = await window.SemantosKernel;

// Option B: Callback
KernelBridge.boot().then(kernel => {
  (window as any).SemantosKernel = kernel;
  window.dispatchEvent(new Event('semantos:ready'));
});
// navigator.js: window.addEventListener('semantos:ready', () => { ... });
```

Option A is simpler. Option B gives the navigator.js a clear loading → ready transition.

---

## Migration Path

### Phase 37A — Storage + Persistence (Week 1)
- Wire `createAdapter()` into kernel bridge
- Replace in-memory `ObjectStore` with `PersistentObjectStore`
- First-boot seeding of bundled configs
- Objects survive page reload
- Tests T1–T8

### Phase 37B — Identity + Extension Discovery (Week 2)
- Wire `createIdentityAdapter('local')` into kernel bridge
- Extension discovery via ConsumerBindings
- Remove static config imports from kernel-bridge.ts
- ExtensionRegistry replaces hardcoded extensions array
- Tests T5, T13, T14

### Phase 37C — Anchor + Network (Week 3)
- Wire StubAnchorAdapter (default) with upgrade to BsvAnchorAdapter
- Wire StubNetworkAdapter (default) with upgrade to BsvOverlayNetworkAdapter
- CWI detection triggers adapter upgrades
- Status bar reflects real adapter state
- Tests T9–T12

---

## Key Files Summary

| Action | File |
|--------|------|
| **Rewrite** | `packages/navigation_app/bsv-app/kernel-bridge.ts` — KernelBridge class with four adapters |
| **Modify** | `packages/navigation_app/bsv-app/navigator.js` — async boot, real status dots, adapter state |
| **Modify** | `packages/navigation_app/bsv-app/index.html` — status bar labels (anchor, network), loading state |
| **Create** | `packages/__tests__/kernel-bridge-boot.test.ts` — 14 integration tests |
| **Read** | `packages/protocol-types/src/storage.ts` — StorageAdapter interface |
| **Read** | `packages/protocol-types/src/identity.ts` — IdentityAdapter interface |
| **Read** | `packages/protocol-types/src/anchor.ts` — AnchorAdapter interface |
| **Read** | `packages/protocol-types/src/network.ts` — NetworkAdapter interface |
| **Read** | `packages/protocol-types/src/adapters/create-adapter.ts` — storage factory |
| **Read** | `packages/protocol-types/src/adapters/create-identity-adapter.ts` — identity factory |
| **Read** | `packages/protocol-types/src/extension-loader.ts` — ExtensionLoader |
| **Read** | `packages/protocol-types/src/extension-registry.ts` — ExtensionRegistry |

---

## Verification

1. `bun test packages/__tests__/kernel-bridge-boot.test.ts` — all 14 tests pass
2. `bun run build:bridge` — kernel-bridge.js builds without errors, no Node.js imports leaked
3. Open index.html — kernel boots, extensions discovered from storage, objects persist across reload
4. Create object via `/create Release` → refresh page → object still visible
5. Status bar shows correct adapter states (kernel green, anchor/network grey without wallet)
6. Connect wallet → anchor and network dots turn green
