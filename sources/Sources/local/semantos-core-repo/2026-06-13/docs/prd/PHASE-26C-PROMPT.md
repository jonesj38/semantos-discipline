---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26C-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.685430+00:00
---

# Phase 26C Execution Prompt — Anchor Adapter (Decoupling Proof from Storage)

> Paste this prompt into a fresh session to execute Phase 26C.

## Context

You are working in the `semantos-core` repo — the TypeScript protocol types and adapters for Bitcoin-native semantic objects. Phase 25A–D extracted and implemented the `StorageAdapter` interface with six backends (Memory, NodeFs, OPFS, IndexedDB, Overlay, BSV). Phase 26A extracted the `IdentityAdapter` interface. Phase 26B will implement local identity derivation.

Your task is Phase 26C: define the `AnchorAdapter` interface, implement `BsvAnchorAdapter` (real BSV anchoring with SPV verification), implement `StubAnchorAdapter` (deterministic in-memory), and create `AnchorScheduler` to batch-anchor unanchored state transitions. After this phase, every semantic state can be anchored to BSV at a configurable interval, proving it existed at a specific time and block height, without requiring the entire state to be stored on-chain.

### The Boundary Rule

The kernel NEVER imports `@bsv/*` packages directly. It imports an `AnchorAdapter` interface. In production (Enterprise/Tradie nodes), this is backed by the real BSV SDK. In dev/test, it is backed by the stub. No BSV-internal types cross the adapter boundary. Everything is expressed in loom-native types (string hashes, hex proofs, jurisdiction addresses).

The anchor proof includes a jurisdiction mechanism: when a node has a registered BCA IPv6 address, every AnchorProof embeds that address, enabling third-party verification of data residency and sovereignty.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations and specifications you are building on top of. If you haven't read them, you will produce incomplete adapters or code that doesn't integrate. That is not acceptable.

**Read first** (the PRDs — your requirements):
- `docs/prd/PHASE-26C-ANCHOR-ADAPTER.md` — Phase 26C spec with deliverables D26C.1–D26C.5, TDD gate T1–T15, completion criteria
- `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` — Architecture reference, AnchorAdapter interface, node deployment profiles
- `docs/prd/PLATFORM-ARCHITECTURE.md` — **Product context.** The dispatch envelope is a semantic object that crosses vertical boundaries. When disputes arise ("the tradie says they completed the job, the PM says they didn't"), the BSV-anchored evidence chain is the arbiter. AnchorAdapter makes every state transition on the dispatch envelope independently verifiable by any party.

**Read second** (the adapter interfaces — understand the pattern):
- `packages/protocol-types/src/storage.ts` — StorageAdapter pattern (reference for AnchorAdapter design)
- `packages/protocol-types/src/adapters/bsv-overlay-adapter.ts` — BsvOverlayAdapter implementation pattern (SPV, BUMP, block headers, TopicManagerClient, LookupServiceClient)

**Read third** (the types your adapter will work with):
- `packages/protocol-types/src/cell-header.ts` — CellHeader, typeHash, ownerId field, serialization
- `packages/protocol-types/src/cell-store.ts` — CellStore interface and pattern
- `packages/protocol-types/src/constants.ts` — Linearity, magic numbers, header offsets

**Read fourth** (protocol specifications):
- BRC-10 (BUMP) — Merkle proof format for SPV verification
- Any existing documentation on jurisdiction proof in `docs/`

**Read fifth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-26c-anchor-adapter`. Commits as `phase-26c/D26C.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 25A–D. Plus:

### 1. NO STUBS

Every function must do real work. The `StubAnchorAdapter` is an in-memory implementation — it is NOT a mock. Every method must compute deterministic results. If a function body is `throw new Error("not implemented")` or `return undefined`, you have failed.

### 2. NO BSV IMPORTS OUTSIDE THE ADAPTERS DIRECTORY

`@bsv/*` imports may ONLY appear in files under `packages/protocol-types/src/adapters/`. If any other protocol-types file imports from `@bsv/*`, you have broken the containment boundary. Gate test T16 (from implicit governance) enforces this.

### 3. NO BSV TYPES IN THE ANCHOR INTERFACE

The `AnchorAdapter` interface uses ONLY primitive types: `string`, `number`, `boolean`, `Record<string, string>`. No `Transaction`, `PrivateKey`, `PublicKey`, or any type from `@bsv/sdk` in the interface signature. Gate test T17 (implicit) enforces this.

### 4. NO MOCKS IN PRODUCTION PATHS

Test files may use fixtures. Source files may not contain mock data or hardcoded responses. The stub adapter computes results deterministically from inputs (sha256-based), not from canned data.

### 5. NO EASY TESTS

Tests must verify real behavior. Tests that check `expect(result).toBeDefined()` are worthless. Delete them and write real tests. Verify merkle proofs, verify block height logic, verify batch anchoring produces correct merkle paths.

### 6. NO TESTS THAT MATCH BROKEN CODE

If your code produces the wrong output, FIX THE CODE. Do not change the test expectation.

### 7. BATCH ANCHORING IS CORE

Don't treat batch anchoring as a nice-to-have. It is the primary use case. Single anchoring is a convenience wrapper. Batch anchoring must:
- Compute Merkle root correctly (sha256 with canonical byte ordering)
- Return N proofs with individual merkle paths from stateHash to root
- Produce identical results for identical input order

### 8. JURISDICTION PROOF IS NOT OPTIONAL

Every AnchorProof must include bcaAddress (when provided). The proof chain must be:
- bcaAddress (IPv6) → ARIN/APNIC registration
- stateHash → state value
- merkleProof → block proof
This is not decorative — it is how enterprise nodes prove sovereignty.

### 9. THE STUB IS DETERMINISTIC

`StubAnchorAdapter` must produce identical results for identical inputs. If you call `anchor("hash1", {bcaAddress: "2602::1"})` twice, both calls must return identical proofs (same txid, same blockHeight, same timestamp).

### 10. SPV VERIFICATION IS NOT OPTIONAL

`BsvAnchorAdapter.verify()` must validate merkle proofs. It must fetch and cache block headers. It must reject tampered proofs. This is not decorative — it is how third parties verify anchors without trusting the node.

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
# Phase 26A: IdentityAdapter exists
ls packages/protocol-types/src/identity.ts

# Phase 25A–D: StorageAdapter exists
ls packages/protocol-types/src/storage.ts
ls packages/protocol-types/src/adapters/bsv-overlay-adapter.ts

# Types and constants exist
ls packages/protocol-types/src/cell-header.ts
ls packages/protocol-types/src/cell-store.ts
ls packages/protocol-types/src/constants.ts

# Adapters directory exists
ls packages/protocol-types/src/adapters/
```

All files must exist. If anything is missing, STOP and raise an error.

### 0.4 Create Phase 26C branch

```bash
git checkout -b phase-26c-anchor-adapter
```

---

## Step 1: AnchorAdapter Interface (D26C.1)

Create `packages/protocol-types/src/anchor.ts`.

This defines the anchoring boundary. Every method. Every JSDoc comment. Only primitive types in the signature.

Include:

- `AnchorAdapter` interface — full interface as specified in the PRD (anchor, batchAnchor, verify, getLatestAnchor, getAnchorHistory, interval methods)
- `AnchorProof` type definition — txid, vout, blockHeight, blockHash, timestamp, merkleProof, bcaAddress, stateHash, interval
- `AnchorMetadata` type — bcaAddress, typeHint, tags
- `AnchorItem` type — stateHash, metadata
- `AnchorConfig` interface — mode, interval, network, ownerKey, debugLogging
- `AnchorError` interface — code, message, recoverable
- `AnchorState` interface — mode, interval, lastAnchorTime, pendingStateHashes, totalAnchored

Verify: no `@bsv/*` imports in this file. The interface is pure protocol-types types.

Commit: `phase-26c/D26C.1: AnchorAdapter interface — proof generation and verification boundary`

---

## Step 2: StubAnchorAdapter (D26C.4)

Create `packages/protocol-types/src/adapters/stub-anchor-adapter.ts`.

This is the in-memory implementation. It is NOT a mock. Every method computes deterministic results.

Implementation requirements:

- **Anchor**: `anchor(stateHash, metadata?)` → deterministic `txid = sha256("stub:" + stateHash)`, `blockHeight = 1000000 + ceil(Date.now() / 1000)`, `blockHash = sha256("block:" + blockHeight)`, `timestamp = Date.now()`, `merkleProof = sha256("merkle:" + stateHash)`
- **Batch anchor**: `batchAnchor(items[])` → compute Merkle root of all hashes, return N proofs with individual merkle paths
- **Verify**: always returns `{ valid: true, timestamp: now, blockHeight: 1000000... }`
- **Latest anchor**: `getLatestAnchor(stateHash)` → returns most recent proof from in-memory map
- **History**: `getAnchorHistory(objectPath)` → returns proofs in chronological order
- **Interval**: getter/setter for anchor interval
- **Jurisdiction**: include bcaAddress in every proof when provided

Use Node's `crypto.createHash('sha256')` for hashing. Do NOT import `@bsv/*`.

Maintain an in-memory index:
- `proofs: Map<stateHash, AnchorProof[]>` — all proofs by stateHash
- `byObjectPath: Map<objectPath, AnchorProof[]>` — all proofs by object path
- `lastAnchored: Map<stateHash, number>` — timestamp of last anchor

Commit: `phase-26c/D26C.4: StubAnchorAdapter — in-memory, deterministic proofs`

---

## Step 3: BsvAnchorAdapter (D26C.3)

Create `packages/protocol-types/src/adapters/bsv-anchor-adapter.ts`.

This is the production implementation. All BSV imports must stay here.

Implementation requirements:

- **Anchor**: Create OP_RETURN transaction with `stateHash` as hex payload, sign with ownerKey, broadcast via TopicManagerClient
- **Batch anchor**: Create single OP_RETURN with Merkle root, return N proofs with merkle paths. Merkle computation: `sha256(sha256(left) + sha256(right))` with canonical byte ordering
- **Verify**: Walk merkle proof, fetch block header from LookupServiceClient (or local cache), validate BUMP proof structure
- **Latest/History**: Query internal indices (populated on anchor operations)
- **Interval**: getter/setter
- **Jurisdiction**: include bcaAddress in every proof when provided

Block header caching:
- Maintain `blockHeaderCache: Map<blockHeight, BlockHeader>`
- Avoid repeated LookupServiceClient calls
- Expire stale entries (e.g., only keep last 1000 blocks)

Structure:
```typescript
export class BsvAnchorAdapter implements AnchorAdapter {
  private readonly ownerKey: PrivateKey;
  private readonly ownerPubKey: PublicKey;
  private readonly topicManager: TopicManagerClient;
  private readonly lookupService: LookupServiceClient;
  private readonly blockHeaderCache = new Map<number, BlockHeader>();
  private readonly proofIndex = new Map<string, AnchorProof[]>();
  private interval: number;

  constructor(config: AnchorConfig) { ... }

  async anchor(stateHash: string, metadata?: AnchorMetadata): Promise<AnchorProof> { ... }
  async batchAnchor(items: AnchorItem[]): Promise<AnchorProof[]> { ... }
  async verify(proof: AnchorProof): Promise<{ valid: boolean; timestamp?: number; blockHeight?: number }> { ... }
  async getLatestAnchor(stateHash: string): Promise<AnchorProof | null> { ... }
  async getAnchorHistory(objectPath: string): Promise<AnchorProof[]> { ... }
  getAnchorInterval(): number { ... }
  setAnchorInterval(ms: number): void { ... }

  private async fetchBlockHeader(blockHeight: number): Promise<BlockHeader> { ... }
  private computeMerkleRoot(hashes: string[]): string { ... }
  private merkleProofPath(hashes: string[], targetHash: string): string { ... }
}
```

Commit: `phase-26c/D26C.3: BsvAnchorAdapter — real BSV anchoring with SPV verification`

---

## Step 4: AnchorScheduler (D26C.5)

Create `packages/protocol-types/src/anchor-scheduler.ts`.

Background task that runs on configurable interval, collects unanchored state transitions, batch-anchors them.

```typescript
export class AnchorScheduler {
  private timer?: NodeJS.Timeout;
  private isRunning = false;
  private lastAnchorTime = 0;
  private pendingHashes = new Set<string>();

  constructor(
    private readonly adapter: AnchorAdapter,
    private readonly storage: StorageAdapter,
    private readonly config?: { debugLogging?: boolean }
  ) {}

  /**
   * Start the scheduler.
   * Runs on configurable interval (from adapter.getAnchorInterval()).
   */
  start(): void {
    if (this.isRunning) return;
    this.isRunning = true;
    this.scheduleAnchor();
  }

  /**
   * Stop the scheduler.
   */
  stop(): void {
    this.isRunning = false;
    if (this.timer) clearTimeout(this.timer);
  }

  /**
   * Trigger an immediate anchor operation.
   */
  async anchor(): Promise<void> {
    if (this.pendingHashes.size === 0) return;

    const items = Array.from(this.pendingHashes).map(stateHash => ({
      stateHash,
      metadata: { typeHint: 'unknown' }
    }));

    const proofs = await this.adapter.batchAnchor(items);

    // Store proof references
    for (const proof of proofs) {
      const proofKey = `proofs/${proof.stateHash}/${proof.timestamp}.proof`;
      const proofData = JSON.stringify(proof);
      await this.storage.write(proofKey, new TextEncoder().encode(proofData));
    }

    this.lastAnchorTime = Date.now();
    this.pendingHashes.clear();
  }

  /**
   * Add a state hash to the pending set.
   */
  addPending(stateHash: string): void {
    this.pendingHashes.add(stateHash);
  }

  /**
   * Get current scheduler state.
   */
  async getState(): Promise<AnchorState> {
    return {
      mode: this.adapter instanceof BsvAnchorAdapter ? 'bsv' : 'stub',
      interval: this.adapter.getAnchorInterval(),
      lastAnchorTime: this.lastAnchorTime,
      pendingStateHashes: Array.from(this.pendingHashes),
      totalAnchored: (await this.storage.list('proofs/')).length,
    };
  }

  private scheduleAnchor(): void {
    if (!this.isRunning) return;
    const interval = this.adapter.getAnchorInterval();
    this.timer = setTimeout(async () => {
      try {
        await this.anchor();
      } catch (err) {
        if (this.config?.debugLogging) console.error('AnchorScheduler error:', err);
      }
      this.scheduleAnchor();
    }, interval);
  }
}
```

The scheduler:
1. Accepts a `StorageAdapter` and `AnchorAdapter`
2. Maintains a set of pending stateHashes (added via `addPending()`)
3. On interval, calls `adapter.batchAnchor()` with all pending hashes
4. Stores proofs in storage at `proofs/{stateHash}/{timestamp}.proof`
5. Clears pending set

Commit: `phase-26c/D26C.5: AnchorScheduler — batch anchor on configurable interval`

---

## Step 5: Factory Function (D26C.1 extension)

Add to `packages/protocol-types/src/anchor.ts`:

```typescript
/**
 * Factory function to create an AnchorAdapter.
 */
export async function createAnchorAdapter(config: AnchorConfig): Promise<AnchorAdapter> {
  if (config.mode === 'stub') {
    return new StubAnchorAdapter(config.interval ?? 600000);
  }
  if (config.mode === 'bsv') {
    if (!config.ownerKey) throw new Error('ownerKey required for BSV mode');
    return new BsvAnchorAdapter(config);
  }
  throw new Error(`Unknown anchor mode: ${config.mode}`);
}
```

Also add a barrel export in `packages/protocol-types/src/index.ts`:

```typescript
export * from './anchor';
export { BsvAnchorAdapter } from './adapters/bsv-anchor-adapter';
export { StubAnchorAdapter } from './adapters/stub-anchor-adapter';
export { AnchorScheduler } from './anchor-scheduler';
```

Commit: `phase-26c/factory: AnchorAdapter factory and barrel exports`

---

## Step 6: Gate Tests

Create `packages/__tests__/phase26c-gate.test.ts`.

### Unit Tests (T1–T8)

```typescript
describe("StubAnchorAdapter", () => {
  // T1: anchor() returns proof with txid, blockHeight, timestamp, merkleProof
  // T2: anchor() is deterministic (same stateHash → same proof)
  // T3: batchAnchor() produces N proofs with shared blockHash, sequential vout
  // T4: batchAnchor() merkle paths validate correctly
  // T5: verify() always returns { valid: true }
  // T6: getLatestAnchor() returns most recent proof for a stateHash
  // T7: getAnchorHistory() returns proofs in chronological order
  // T8: setAnchorInterval() changes interval; getAnchorInterval() reflects new value
});

describe("BsvAnchorAdapter", () => {
  // T9: anchor() creates OP_RETURN transaction with stateHash
  // T10: batchAnchor() creates single OP_RETURN with Merkle root
  // T11: verify() validates merkle proof
  // T12: verify() validates block header from cache or LookupService
});

describe("Jurisdiction proof", () => {
  // T13: StubAnchorAdapter includes bcaAddress in proof when provided
  // T14: BsvAnchorAdapter includes bcaAddress in proof when provided
  // T15: Proof can be verified with or without bcaAddress
});
```

Verify:
- Merkle proofs validate correctly (don't just check they exist)
- Batch anchoring produces N distinct proofs
- bcaAddress is preserved in all proofs
- Determinism is enforced (same input → same output)

Commit: `phase-26c/T1-T15: full gate test suite — unit, SPV, jurisdiction`

---

## Step 7: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review of every new file
2. Check that `BsvAnchorAdapter.verify()` properly validates merkle proofs (don't trust the proof blindly)
3. Check that batch anchoring produces correct merkle paths for each stateHash
4. Check that `AnchorScheduler.anchor()` properly stores proof references in storage
5. Check that block header cache expires old entries
6. Check that no `@bsv/*` imports leak outside the adapters/ directory
7. Check that `StubAnchorAdapter` is truly deterministic (no randomness, no timestamps that vary)
8. Check that jurisdiction proof chain is unbroken (bcaAddress → stateHash → proof)
9. Write errata doc as `docs/prd/PHASE-26C-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/protocol-types/src/anchor.ts` exists with full `AnchorAdapter` interface (no stubs)
- [ ] `packages/protocol-types/src/anchor.ts` includes all supporting types (AnchorProof, AnchorMetadata, AnchorConfig, AnchorError, AnchorState)
- [ ] `packages/protocol-types/src/adapters/stub-anchor-adapter.ts` exists with full `StubAnchorAdapter` (every method implemented, deterministic)
- [ ] `packages/protocol-types/src/adapters/bsv-anchor-adapter.ts` exists with full `BsvAnchorAdapter` (SPV, BUMP, batch anchoring)
- [ ] `packages/protocol-types/src/anchor-scheduler.ts` exists with `AnchorScheduler` class
- [ ] `createAnchorAdapter()` factory function in `anchor.ts` creates appropriate adapter by mode
- [ ] Tests T1–T15 all pass
- [ ] Merkle proofs validate correctly in BsvAnchorAdapter
- [ ] Batch anchoring works and produces correct merkle paths
- [ ] BCA address is embedded in every AnchorProof when provided
- [ ] Block header caching works (no repeated lookups)
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No `@bsv/*` imports outside `packages/protocol-types/src/adapters/`
- [ ] All commits follow `phase-26c/D26C.N:` naming convention
- [ ] Branch is `phase-26c-anchor-adapter`
- [ ] Errata sprint complete with `docs/prd/PHASE-26C-ERRATA.md`

---

## Next Phase

Phase 26D unifies network operations under a `NetworkAdapter` interface, decoupling the kernel from specific transport backends (BsvOverlay, Direct LAN, cloud mesh, etc).
