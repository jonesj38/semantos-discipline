---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26C-ANCHOR-ADAPTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.665354+00:00
---

# Phase 26C — Anchor Adapter (Decoupling Proof from Storage)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 26A complete (IdentityAdapter extraction)
**Master document**: `PHASE-26-KERNEL-ISOLATION-MASTER.md`
**Branch**: `phase-26c-anchor-adapter`

---

## Context

Semantos currently entangles anchoring with storage. BSV anchoring is hardcoded inside `BsvOverlayAdapter` — you can only anchor if you store on BSV. But a node using `NodeFsAdapter` for local filesystem storage still needs to anchor evidence chains to prove they existed at a specific time and block height.

Anchoring must be independent of storage backend. The anchor answers one question: **"Did this state exist at this time?"** The answer is a cryptographic proof (AnchorProof) verifiable by any third party without trusting the node.

This phase creates the `AnchorAdapter` interface and three implementations:
1. **BsvAnchorAdapter** — Real anchoring via OP_RETURN transactions on BSV, SPV proof chain
2. **StubAnchorAdapter** — In-memory, deterministic fake proofs (dev/test)
3. **AnchorScheduler** — Background task that batch-anchors unanchored state transitions

### The Boundary Rule

The kernel NEVER imports BSV SDK or anchoring code directly. It imports an `AnchorAdapter` interface. In production (Enterprise/Tradie nodes), this is backed by the real BSV SDK. In dev/test, it is backed by the stub. No BSV types cross the adapter boundary.

The anchor proof includes a jurisdiction proof mechanism: when a node has a registered BCA IPv6 address, every AnchorProof embeds that address. The chain is:
- BCA address → ARIN/APNIC registration → jurisdiction
- stateHash → exact state transition
- merkleProof (BRC-10 BUMP) → SPV proof in BSV block

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `PHASE-26-MASTER` | `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` | Architecture, AnchorAdapter interface, node deployment profiles |
| `PROTOCOL-STORAGE` | `packages/protocol-types/src/storage.ts` | StorageAdapter pattern for reference |
| `PROTOCOL-CELL` | `packages/protocol-types/src/cell-header.ts` | CellHeader, typeHash, ownerId structure |
| `CONSTANTS` | `packages/protocol-types/src/constants.ts` | Linearity, CELL_SIZE, magic numbers |
| `BSV-OVERLAY` | `packages/protocol-types/src/adapters/bsv-overlay-adapter.ts` | BsvOverlayAdapter implementation pattern |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming convention, branch rules |

---

## Deliverables

### D26C.1 — AnchorAdapter Interface

**New file**: `packages/protocol-types/src/anchor.ts`

The `AnchorAdapter` interface as the primary contract for proof generation and verification. All methods. All JSDoc. Only primitive types and standard structures in the signature — no BSV SDK types.

The interface defines:

```typescript
/**
 * AnchorAdapter — the membrane between kernel and anchoring backend.
 *
 * All state proof operations flow through this interface.
 * No BSV types leak into the kernel. No `@bsv/*` imports outside
 * the adapters/ directory.
 *
 * An AnchorProof answers: "Did this state exist at this time?"
 * The proof is verifiable by any third party without trusting the node.
 */
export interface AnchorAdapter {
  /**
   * Anchor a single state hash to a point in time and block height.
   *
   * @param stateHash - SHA-256 hex hash of the state being anchored
   * @param metadata - optional metadata (BCA address, type hint, etc)
   * @returns AnchorProof with txid, block height, timestamp, merkle proof
   */
  anchor(stateHash: string, metadata?: AnchorMetadata): Promise<AnchorProof>;

  /**
   * Batch anchor multiple state hashes in a single transaction.
   *
   * More efficient than calling anchor() N times. Creates a single
   * OP_RETURN transaction containing a Merkle root of all state hashes,
   * then issues an individual AnchorProof for each item with its
   * merkle path to the root.
   *
   * @param items - array of { stateHash, metadata? }
   * @returns array of AnchorProof, same length as items, in same order
   */
  batchAnchor(items: AnchorItem[]): Promise<AnchorProof[]>;

  /**
   * Verify an AnchorProof without trusting the node.
   *
   * Checks: (1) merkle proof validates stateHash to root,
   * (2) BUMP proof validates root to block header,
   * (3) block header is valid (uses local SPV cache if available).
   *
   * @param proof - AnchorProof to verify
   * @returns { valid: boolean; timestamp: number; blockHeight: number }
   */
  verify(proof: AnchorProof): Promise<{ valid: boolean; timestamp?: number; blockHeight?: number }>;

  /**
   * Get the most recent AnchorProof for a given state hash.
   *
   * @param stateHash - state hash to look up
   * @returns AnchorProof | null if not found or not yet anchored
   */
  getLatestAnchor(stateHash: string): Promise<AnchorProof | null>;

  /**
   * Get all AnchorProofs for a given object path (e.g. "objects/create/job/123").
   *
   * Returns proofs in chronological order (oldest first).
   *
   * @param objectPath - storage path of the object
   * @returns array of AnchorProof
   */
  getAnchorHistory(objectPath: string): Promise<AnchorProof[]>;

  /**
   * Get the current anchor interval in milliseconds.
   *
   * @returns interval, e.g. 600000 (10 minutes) for Tradie nodes
   */
  getAnchorInterval(): number;

  /**
   * Set the anchor interval in milliseconds.
   *
   * AnchorScheduler respects this. Useful for dynamic node reconfiguration.
   *
   * @param ms - interval, e.g. 60000 (1 minute) for Enterprise nodes
   */
  setAnchorInterval(ms: number): void;
}
```

Also include supporting types:

```typescript
/**
 * Metadata for an anchor operation.
 */
export interface AnchorMetadata {
  /** BCA address of the anchoring node (for jurisdiction proof). */
  bcaAddress?: string;
  /** Type hint for the state (e.g. 'sovereignty.node'). */
  typeHint?: string;
  /** Arbitrary string tags. */
  tags?: string[];
}

/**
 * Item for batch anchoring.
 */
export interface AnchorItem {
  stateHash: string;
  metadata?: AnchorMetadata;
}

/**
 * Configuration for anchor adapter initialization.
 */
export interface AnchorConfig {
  mode: 'stub' | 'bsv';
  interval?: number;  // default 600000 (10 min) for Tradie, 60000 (1 min) for Enterprise
  network?: 'mainnet' | 'testnet';  // BSV network for BsvAnchorAdapter
  ownerKey?: string;  // BSV owner private key (hex) for BsvAnchorAdapter
  debugLogging?: boolean;
}

/**
 * A cryptographic proof that a state hash existed at a specific time and block.
 * Verifiable by any third party.
 */
export interface AnchorProof {
  /** State hash that was anchored. */
  stateHash: string;
  /** BSV transaction ID containing the anchor. */
  txid: string;
  /** Output index in the transaction (typically 0 for OP_RETURN). */
  vout: number;
  /** Block height where the transaction was confirmed. */
  blockHeight: number;
  /** Block hash for verification. */
  blockHash: string;
  /** Unix epoch ms of the block. */
  timestamp: number;
  /** BRC-10 BUMP merkle proof (hex string). */
  merkleProof: string;
  /** BCA address of the anchoring node (if provided). */
  bcaAddress?: string;
  /** Anchor interval at the time of anchoring. */
  interval: number;
}

/**
 * AnchorError — loom-native error type.
 */
export interface AnchorError {
  code: string;  // ANCHOR_FAILED, VERIFY_FAILED, INVALID_PROOF, etc
  message: string;
  recoverable: boolean;
}

/**
 * AnchorState — snapshot for monitoring.
 */
export interface AnchorState {
  mode: 'stub' | 'bsv';
  interval: number;
  lastAnchorTime?: number;
  pendingStateHashes: string[];
  totalAnchored: number;
}
```

### D26C.2 — AnchorProof Type Definition

Included in D26C.1 as the `AnchorProof` interface. The structure mirrors BRC-10 BUMP format:

- `txid` / `vout` / `blockHeight` / `blockHash` — on-chain location
- `timestamp` — block timestamp (for temporal proof)
- `merkleProof` — hex-encoded Merkle path from stateHash to block root (BRC-10 BUMP)
- `bcaAddress` — jurisdiction identifier (if node is registered)
- `stateHash` — the state being proved

### D26C.3 — BsvAnchorAdapter Implementation

**New file**: `packages/protocol-types/src/adapters/bsv-anchor-adapter.ts`

Full implementation of AnchorAdapter backed by BSV SDK:

- `anchor()` creates an OP_RETURN transaction encoding `stateHash` as hex, signs with ownerKey, broadcasts via TopicManagerClient
- `batchAnchor()` creates a single OP_RETURN containing Merkle(stateHash_1, stateHash_2, ..., stateHash_N), returns N proofs with individual merkle paths
- `verify()` validates merkle proof paths, fetches block header from LookupServiceClient (or local SPV cache), validates BUMP proof
- `getLatestAnchor()` queries an internal index (populated by write() operations)
- `getAnchorHistory()` scans proof index by object path
- SPV validation: maintains a local cache of block headers, validates BUMP proof chain without requiring full node

Requirements:
- No @bsv/* imports outside this file
- No mutations to CellHeader or CellStore — anchoring is read-only from storage perspective
- Batch anchoring must compute Merkle root correctly (sha256(left + right) with canonical ordering)
- Jurisdiction proof: if bcaAddress is provided in metadata, include it in every AnchorProof
- Block header caching to avoid repeated lookups

### D26C.4 — StubAnchorAdapter Implementation

**New file**: `packages/protocol-types/src/adapters/stub-anchor-adapter.ts`

In-memory, deterministic fake proofs (for dev/test):

- `anchor()` generates a deterministic fake txid from `sha256("stub:" + stateHash)`, fake blockHeight from clock
- `batchAnchor()` generates N proofs with shared blockHash, sequential vout
- `verify()` always returns `{ valid: true, timestamp: now, blockHeight: 1000000 }` (deterministic block in the future)
- `getLatestAnchor()` returns the most recent proof from in-memory map
- `getAnchorHistory()` returns proofs by objectPath in chronological order
- `merkleProof` is always a valid-looking but fake BRC-10 hex string

Requirements:
- Every proof is deterministic (same input always produces same output)
- No actual wallet, no actual BSV SDK calls
- Interval and bcaAddress respected

### D26C.5 — AnchorScheduler

**New file**: `packages/protocol-types/src/anchor-scheduler.ts`

Background task that collects unanchored state transitions and batch-anchors them:

```typescript
export class AnchorScheduler {
  constructor(
    private adapter: AnchorAdapter,
    private storage: StorageAdapter
  ) {}

  /**
   * Start the scheduler.
   * Runs on configurable interval (from adapter.getAnchorInterval()).
   * Collects unanchored state hashes, batch-anchors them, stores proof references.
   */
  start(): void;

  /**
   * Stop the scheduler.
   */
  stop(): void;

  /**
   * Trigger an immediate anchor operation (for testing).
   */
  anchor(): Promise<void>;

  /**
   * Get current scheduler state (pending count, last run time, etc).
   */
  getState(): Promise<AnchorState>;
}
```

The scheduler:
1. Wakes up on interval (10 min for Tradie, 1 min for Enterprise)
2. Scans CellStore for cells with version > lastAnchored version (via internal index)
3. Collects their stateHashes
4. Calls `adapter.batchAnchor(items)`
5. For each returned AnchorProof, stores a proof reference in storage at `proofs/{stateHash}/{timestamp}.proof`
6. Updates lastAnchored index

Proof reference storage:
- Key: `proofs/{stateHash}/{timestamp}.proof`
- Value: JSON-encoded AnchorProof (Uint8Array)

The scheduler must not block — it runs async in background, catching and logging errors.

---

## Jurisdiction Proof Mechanism

When a Semantos node has a registered BCA IPv6 address, every AnchorProof includes that address. The chain of proof is:

```
bcaAddress (IPv6)
    ↓
ARIN/APNIC registration (public registry)
    ↓
Jurisdiction + geolocation data
    ↓
stateHash (from AnchorProof.stateHash)
    ↓
Exact semantic state (retrievable via storage)
    ↓
merkleProof (BRC-10 BUMP)
    ↓
SPV proof in BSV block
    ↓
Cryptographically verified without trusting the node
```

A third party can:
1. Verify the merkleProof against the blockHash
2. Look up the bcaAddress in ARIN/APNIC to confirm jurisdiction
3. Retrieve the full state from the node's storage (trustlessly, via CellStore verification)
4. Compute sha256(state) and match against stateHash

This satisfies "data residency" requirements for enterprise nodes and enables "provable sovereignty."

---

## TDD Gate

Create `packages/__tests__/phase26c-gate.test.ts` with 15+ tests:

### Unit Tests (T1–T8)

```typescript
describe("AnchorAdapter interface", () => {
  // T1: BsvAnchorAdapter.anchor() returns proof with valid txid, blockHeight, timestamp
  // T2: BsvAnchorAdapter.batchAnchor() produces N proofs with shared blockHash, sequential vout
  // T3: BsvAnchorAdapter.verify() validates merkle proof correctly
  // T4: StubAnchorAdapter.anchor() produces deterministic proof (same input → same output)
  // T5: StubAnchorAdapter.verify() always returns { valid: true }
  // T6: BsvAnchorAdapter.getLatestAnchor() returns most recent proof for a stateHash
  // T7: BsvAnchorAdapter.getAnchorHistory() returns proofs in chronological order by objectPath
  // T8: setAnchorInterval() changes interval; getAnchorInterval() reflects new value
});
```

### Integration Tests (T9–T12)

```typescript
describe("AnchorScheduler", () => {
  // T9: AnchorScheduler.start() collects unanchored stateHashes on interval
  // T10: AnchorScheduler batch-anchors 10 state hashes in one call
  // T11: After anchoring, getAnchorHistory() contains all proofs
  // T12: AnchorScheduler stores proof references in storage at proofs/{stateHash}/{timestamp}.proof
});
```

### Jurisdiction Proof Tests (T13–T15)

```typescript
describe("Jurisdiction proof", () => {
  // T13: BsvAnchorAdapter includes bcaAddress in AnchorProof when provided
  // T14: StubAnchorAdapter includes bcaAddress in AnchorProof when provided
  // T15: Proof verification works with or without bcaAddress
});
```

---

## Completion Criteria

- [ ] `packages/protocol-types/src/anchor.ts` exists with full `AnchorAdapter` interface (no stubs)
- [ ] `packages/protocol-types/src/anchor.ts` includes `AnchorProof`, `AnchorMetadata`, `AnchorConfig` types
- [ ] `packages/protocol-types/src/adapters/bsv-anchor-adapter.ts` exists with full `BsvAnchorAdapter` (every method implemented)
- [ ] `packages/protocol-types/src/adapters/stub-anchor-adapter.ts` exists with full `StubAnchorAdapter`
- [ ] `packages/protocol-types/src/anchor-scheduler.ts` exists with `AnchorScheduler` class
- [ ] Tests T1–T15 all pass
- [ ] BCA address is embedded in every AnchorProof when provided
- [ ] Batch anchoring works and produces correct merkle proofs
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No `@bsv/*` imports outside `packages/protocol-types/src/adapters/`
- [ ] All commits follow `phase-26c/D26C.N:` naming convention
- [ ] Branch is `phase-26c-anchor-adapter`

---

## Next Phase

Phase 26D unifies network operations under a `NetworkAdapter` interface, decoupling the kernel from specific transport backends (BsvOverlay, Direct LAN, etc).
