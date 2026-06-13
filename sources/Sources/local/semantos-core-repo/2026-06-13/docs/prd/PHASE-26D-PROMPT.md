---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26D-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.713889+00:00
---

# Phase 26D Execution Prompt — NetworkAdapter Interface & Overlay Composition

> Paste this prompt into a fresh session to execute Phase 26D.

## Context

You are working in the `semantos-core` repo — the TypeScript protocol layer and kernel node infrastructure. Phase 25A–D established StorageAdapter with six implementations (Memory, NodeFs, OPFS, IndexedDB, Overlay, BSV). Phase 26A extracted IdentityAdapter. Phase 26B–C will add LocalIdentityAdapter and AnchorAdapter. Phase 26D is your task: define the `NetworkAdapter` interface and unify the three existing network clients (TopicManagerClient, LookupServiceClient, ShardProxyClient) behind it.

Currently, these clients are scattered: TopicManagerClient publishes to BRC-22 topics, LookupServiceClient queries BRC-24 lookup services, ShardProxyClient fans out via UDP multicast. They don't share a common contract. BsvOverlayAdapter conflates them with storage concerns. Phase 26D separates networking from storage and gives you a clean, swappable `NetworkAdapter` interface.

The commercial outcome: a Semantos node can be deployed with any combination of storage (local FS, overlay network, cloud) and networking (stub, overlay, LAN). An enterprise node running on a Colo can use NodeFsAdapter for storage + DirectNetworkAdapter for campus LAN. A tradie VPS can use NodeFsAdapter + BsvOverlayNetworkAdapter. A dev laptop can use MemoryAdapter + StubNetworkAdapter.

### The Boundary Rule

The kernel NEVER imports the three clients directly outside of the NetworkAdapter implementations. All network operations flow through the `NetworkAdapter` interface. In stub mode, it's in-memory pub/sub. In production (overlay or direct), it composes the real clients. No client types leak into the kernel or configuration code.

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are building on top of. If you haven't read them, you will produce stubs, mocks, or code that doesn't integrate. That is not acceptable.

**Read first** (the PRDs — your requirements):
- `docs/prd/PHASE-26D-NETWORK-ADAPTER.md` — Phase 26D spec with deliverables D26D.1–D26D.6, TDD gate T1–T15, completion criteria
- `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` — Architecture reference: four adapters, node deployment profiles, three boundaries
- `docs/prd/PLATFORM-ARCHITECTURE.md` — **Product context.** The V1→V2→V3 sync progression maps directly to NetworkAdapter implementations. V1 (shared Postgres) is direct API sync. V2 (Supabase Realtime) is a subscription-based NetworkAdapter. V3 (BSV overlay) is BsvOverlayNetworkAdapter with shard multicast. The dispatch envelope moves between verticals via NetworkAdapter — this is the wire that connects PM dispatching to tradie job intake.

**Read second** (the existing clients you are unifying):
- `packages/protocol-types/src/overlay/topic-manager-client.ts` — TopicManagerClient, SEMANTOS_TOPICS, topicForKey()
- `packages/protocol-types/src/overlay/lookup-service-client.ts` — LookupServiceClient, SEMANTOS_LOOKUP_SERVICES, DecodedLookupOutput
- `packages/protocol-types/src/overlay/shard-proxy-client.ts` — ShardProxyClient, PublishResult, MULTICAST_SCOPE
- `packages/protocol-types/src/adapters/bsv-overlay-adapter.ts` — How clients currently compose in BsvOverlayAdapter (understand the entanglement)

**Read third** (the reference adapter pattern):
- `packages/protocol-types/src/storage.ts` — StorageAdapter interface, StorageEvent structure, six implementations pattern
- `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` — StorageAdapter, IdentityAdapter examples for pattern reuse

**Read fourth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-26d-network-adapter`. Commits as `phase-26d/D26D.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 25A–D. Plus:

### 1. NO STUBS

Every function must do real work. StubNetworkAdapter is an in-memory implementation — it is NOT a mock. Every method must compute deterministic results. If a function body is `throw new Error("not implemented")` or `return undefined`, you have failed.

### 2. NO CLIENT IMPORTS OUTSIDE THE ADAPTER DIRECTORY

`TopicManagerClient`, `LookupServiceClient`, `ShardProxyClient` imports may ONLY appear in files under `packages/protocol-types/src/adapters/`. If any other file imports these clients directly, you have broken the abstraction boundary. Gate test T14 enforces this.

### 3. NO CLIENT TYPES IN THE ADAPTER INTERFACE

The `NetworkAdapter` interface uses ONLY primitive types and generic application types: `string`, `number`, `boolean`, `Uint8Array`, `Record<string, string>`. No `STEAK`, `TaggedBEEF`, `LookupAnswer`, `LookupQuestion`, `ShardFrame`, or any type from `@bsv/sdk/overlay-tools` in the interface signature. Gate test T13 enforces this.

### 4. NO MOCKS IN PRODUCTION PATHS

Test files may use fixtures. Source files may not contain mock data or hardcoded responses. StubNetworkAdapter computes results deterministically from inputs (map-based), not from canned data.

### 5. NO EASY TESTS

Tests must use real objects and verify real behavior. Tests that check `expect(result).toBeDefined()` are worthless. Delete them and write real tests.

### 6. NO TESTS THAT MATCH BROKEN CODE

If your code produces the wrong output, FIX THE CODE. Do not change the test expectation.

### 7. DECOUPLING IS NOT OPTIONAL

StorageAdapter and NetworkAdapter are independent. Prove it with test T13: use StubStorageAdapter with BsvOverlayNetworkAdapter. Use NodeFsAdapter with StubNetworkAdapter. No tangling.

### 8. THE STUBS ARE NEVER REMOVED

StubNetworkAdapter is permanent infrastructure. It is the dev/test harness forever. Build it as permanent, not temporary.

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

```bash
# Phase 26A must be complete (IdentityAdapter exists)
ls packages/protocol-types/src/identity.ts

# StorageAdapter pattern reference
ls packages/protocol-types/src/storage.ts

# Master PRD
ls docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md

# Existing clients
ls packages/protocol-types/src/overlay/topic-manager-client.ts
ls packages/protocol-types/src/overlay/lookup-service-client.ts
ls packages/protocol-types/src/overlay/shard-proxy-client.ts

# BsvOverlayAdapter (understand current entanglement)
ls packages/protocol-types/src/adapters/bsv-overlay-adapter.ts
```

All files must exist. If anything is missing, STOP.

### 0.4 Create Phase 26D branch

```bash
git checkout -b phase-26d-network-adapter
```

---

## Step 1: NetworkAdapter Interface (D26D.1)

Create `packages/protocol-types/src/network.ts`.

This defines the network abstraction boundary. Every method. Every JSDoc comment. Only primitive types in the signature. No `@bsv/sdk/overlay-tools` types.

Include:

- `NetworkAdapter` interface — full interface as specified in the PRD (publish, subscribe, resolve, resolveBCA, sendToNode, isConnected, getNodeBCA)
- JSDoc for every method and parameter
- Only types: `string`, `number`, `boolean`, `Uint8Array`, `Record<string, string>`

Commit: `phase-26d/D26D.1: NetworkAdapter interface — network abstraction boundary with primitive-only types`

---

## Step 2: Network Types (D26D.2)

Add to `packages/protocol-types/src/network.ts`:

- `NetworkQuery` interface: `path?`, `contentHash?`, `ownerCert?`, `typeHash?`, `parentPath?`, `limit?`, `depth?`
- `NetworkResult` interface: `txid`, `vout`, `cellBytes`, `semanticPath`, `contentHash`, `ownerCert`, `typeHash`, `parentPath?`, `publishedAt`, `multicastGroup?`
- `NetworkEvent` interface: `type`, `result`, `timestamp`
- `PublishableObject` interface: `cellBytes`, `semanticPath`, `contentHash`, `ownerCert`, `typeHash`, `parentPath?`, `metadata?`
- `PublishOptions` interface: `topic?`, `batch?`, `batchTimeoutMs?`, `skipLocalIndex?`
- `PublishResult` interface: `txid`, `multicastGroup?`, `shardIndex?`, `publishedAt`
- `NodeInfo` interface: `bca`, `nodeCert`, `name?`, `verticals`, `adapters`, `version`, `uptime`, `lastAnchorProof?`

Also add the relationship diagram from the PRD (ASCII diagram showing three independent concerns).

Commit: `phase-26d/D26D.2: NetworkQuery, NetworkEvent, NetworkResult, PublishableObject, NodeInfo types`

---

## Step 3: StubNetworkAdapter (D26D.4)

Create `packages/protocol-types/src/adapters/stub-network-adapter.ts`.

This is the in-memory implementation. It is NOT a mock. Every method computes deterministic results.

Implementation requirements:

- **publish()**: store in local Map (key: semanticPath), return deterministic txid ("stub" + counter), fire subscribers
- **subscribe()**: register callback in Map<topic, Set<callback>>, return unsubscribe function
- **resolve()**: iterate local Map, match against query (path, contentHash, ownerCert, typeHash, parentPath), return matching NetworkResult[] up to limit
- **resolveBCA()**: always return null (not applicable to stub)
- **sendToNode()**: always return `{ delivered: true }`
- **isConnected()**: always return true
- **getNodeBCA()**: return configured nodeBCA or null

Commit: `phase-26d/D26D.4: StubNetworkAdapter — in-memory pub/sub, deterministic txid, full interface compliance`

---

## Step 4: BsvOverlayNetworkAdapter (D26D.3)

Create `packages/protocol-types/src/adapters/bsv-overlay-network-adapter.ts`.

This composes the three existing clients. Do NOT modify the clients themselves — only use their public APIs.

Implementation requirements:

- Constructor takes `BsvOverlayNetworkAdapterConfig` with `topicManagerConfig?`, `lookupServiceConfig?`, `shardProxy?`, `nodeBCA?`
- Instantiate TopicManagerClient and LookupServiceClient
- **publish()**:
  - Build a transaction containing the PublishableObject (see CellToken usage in BsvOverlayAdapter)
  - Submit via TopicManagerClient.submit() if no shardProxy, else via ShardProxyClient.publish()
  - Fire subscribers with NetworkEvent
  - Return PublishResult with txid, shardIndex, multicastGroup, publishedAt
- **subscribe()**: register callback, return unsubscribe function
- **resolve()**:
  - If query.path: call LookupServiceClient.queryByPath()
  - If query.contentHash: call LookupServiceClient.queryByContent()
  - If query.ownerCert: call LookupServiceClient.queryByOwner()
  - If query.typeHash: call LookupServiceClient.queryByType()
  - If query.parentPath: call LookupServiceClient.queryByParent()
  - Decode LookupAnswer → NetworkResult[] using DecodedLookupOutput
  - Return results up to limit
- **resolveBCA()**: return null (placeholder for Phase 26E)
- **sendToNode()**: return `{ delivered: false }` (placeholder for Phase 26E)
- **isConnected()**: return true if SLAP resolvers are responding (stub for now)
- **getNodeBCA()**: return configured nodeBCA or null

Commit: `phase-26d/D26D.3: BsvOverlayNetworkAdapter — composes TopicManagerClient + LookupServiceClient + ShardProxyClient`

---

## Step 5: Decouple BsvOverlayAdapter (D26D.5)

Modify `packages/protocol-types/src/adapters/bsv-overlay-adapter.ts`.

Extract network-only logic into BsvOverlayNetworkAdapter. No breaking changes to BsvOverlayAdapter's StorageAdapter implementation.

- BsvOverlayAdapter.write() → persists cell to overlay (unchanged behavior)
- BsvOverlayAdapter.read() → queries overlay for stored objects (unchanged behavior)
- Any networking-specific code → move to BsvOverlayNetworkAdapter

Do NOT break any existing BsvOverlayAdapter tests or behavior.

Commit: `phase-26d/D26D.5: BsvOverlayAdapter — extract network concerns, remain StorageAdapter`

---

## Step 6: Export from Index

Create or update `packages/protocol-types/src/index.ts` (or similar barrel export):

```typescript
export * from './network';
export { StubNetworkAdapter } from './adapters/stub-network-adapter';
export { BsvOverlayNetworkAdapter } from './adapters/bsv-overlay-network-adapter';
```

Commit: `phase-26d/D26D.6: Barrel exports for NetworkAdapter and implementations`

---

## Step 7: Gate Tests

Create `packages/__tests__/phase26d-gate.test.ts`.

### Unit Tests (T1–T6)

```typescript
describe("StubNetworkAdapter", () => {
  // T1: publish stores object in map, returns txid with "stub" prefix
  // T2: subscribe registers callback, fires on publish
  // T3: resolve queries by path, returns matching objects from map
  // T4: resolve queries by contentHash, returns exact matches
  // T5: resolve queries by ownerCert, returns objects with matching cert
  // T6: resolve respects limit parameter (returns max N results)
});
```

### Integration Tests (T7–T12)

```typescript
describe("NetworkAdapter composition", () => {
  // T7: BsvOverlayNetworkAdapter instantiates TopicManagerClient
  // T8: BsvOverlayNetworkAdapter instantiates LookupServiceClient
  // T9: publish + subscribe round-trip: published object reaches subscriber callback
  // T10: resolve after publish: published object is returned by resolve(path)
  // T11: resolve by ownerCert: returns objects matching cert
  // T12: resolve by typeHash: returns objects matching type
});
```

### Decoupling Tests (T13–T15)

```typescript
describe("Storage and Network Decoupling", () => {
  // T13: StorageAdapter and NetworkAdapter are independent contracts
  //   → StubStorageAdapter + BsvOverlayNetworkAdapter work together without conflicts
  // T14: No TopicManagerClient imports outside adapters/
  //   → Scan all .ts files for TopicManagerClient, all should be in adapters/
  // T15: NetworkAdapter interface contains only primitives
  //   → Parse network.ts, verify no @bsv/sdk types in interface signature
});
```

Commit: `phase-26d/T1-T15: full gate test suite — unit, integration, decoupling`

---

## Step 8: CI Gate Extension

Verify the existing `.github/workflows/gate.yml` will pick up `packages/__tests__/phase26d-gate.test.ts` automatically (it runs `bun test packages/__tests__/`).

Add a lint check specific to Phase 26D:

```bash
# No TopicManagerClient, LookupServiceClient, ShardProxyClient imports outside adapters/
if grep -rn "import.*TopicManagerClient\|import.*LookupServiceClient\|import.*ShardProxyClient" packages/protocol-types/src/ --include="*.ts" | grep -v "/adapters/" | grep -v "node_modules"; then
  echo "FAIL: Network clients imported outside adapters directory"
  exit 1
fi

# No @bsv/sdk/overlay-tools types in network.ts interface
if grep -n "STEAK\|TaggedBEEF\|LookupAnswer\|LookupQuestion\|ShardFrame" packages/protocol-types/src/network.ts; then
  echo "FAIL: @bsv/sdk/overlay-tools types found in NetworkAdapter interface"
  exit 1
fi
```

This can be added to the lint job or as a separate step.

Commit: `phase-26d/CI: network adapter lint checks for client containment and type isolation`

---

## Step 9: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review of every new and modified file
2. Check that StubNetworkAdapter txid generation is truly deterministic (always "stub1", "stub2", etc.)
3. Check that subscribe callbacks are fired AFTER publish returns
4. Check that resolve respects limit (doesn't return more than N results)
5. Check that BsvOverlayNetworkAdapter doesn't leak client types in its public API
6. Check that BsvOverlayAdapter.write() is unchanged (no breaking changes to StorageAdapter)
7. Check that StorageAdapter and NetworkAdapter tests don't import each other
8. Check that no `any` casts mask type errors at the adapter boundary
9. Write errata doc as `docs/prd/PHASE-26D-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/protocol-types/src/network.ts` exists with full `NetworkAdapter` interface (no stubs)
- [ ] `NetworkQuery`, `NetworkEvent`, `NetworkResult`, `PublishableObject`, `NodeInfo` types defined
- [ ] `packages/protocol-types/src/adapters/stub-network-adapter.ts` exists with full `StubNetworkAdapter` (every method implemented)
- [ ] `packages/protocol-types/src/adapters/bsv-overlay-network-adapter.ts` exists and composes clients
- [ ] BsvOverlayAdapter refactored to decouple storage from network (no breaking changes)
- [ ] Barrel export added to `packages/protocol-types/src/index.ts` (or equivalent)
- [ ] Tests T1–T15 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No `TopicManagerClient`, `LookupServiceClient`, `ShardProxyClient` imports outside `packages/protocol-types/src/adapters/`
- [ ] No `@bsv/sdk/overlay-tools` types in NetworkAdapter interface signature
- [ ] Errata sprint complete with `docs/prd/PHASE-26D-ERRATA.md`
- [ ] All commits follow `phase-26d/D26D.N:` naming convention
- [ ] Branch is `phase-26d-network-adapter`

---

## Next Phase

Phase 26E (Node Bootstrap) composes all four adapters (StorageAdapter, IdentityAdapter, AnchorAdapter, NetworkAdapter) into a NodeConfig, creates the node self-object (sovereignty.node), and brings up the conversational shell.
