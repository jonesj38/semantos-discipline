---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30F.2-CAS-STORAGE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.692428+00:00
---

# Phase 30F.2 — Content-Addressed Cell Store & Journal

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 30F complete (XCFramework + Swift adapters), Phase 30B (adapter callbacks)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30f2-cas-storage`

---

## Context

The kernel's cell store is currently an in-memory `StringHashMap` in `exports.zig`. When host storage callbacks are registered (Phase 30B), I/O routes through `SQLiteStorageProvider` — so persistence works — but the storage model is `path → bytes`, which is a filesystem, not a semantic layer.

This phase upgrades the storage model to content-addressed storage (CAS) with a journal. The upgrade is **entirely a host adapter change** — no Zig kernel modifications required. The kernel continues to call `storage_write(path, data)` and `storage_read(path, ...)` through the existing callback interface. What changes is what happens inside the host adapter.

### The Core Insight: Split Object Identity from Location

```
path → hash → bytes
```

Two separate concerns:
- **Object store**: `SHA-256(cell) → cell_bytes` — immutable, content-addressed
- **Namespace index**: `path → hash` — mutable, the only thing that changes

This is how git works. It's why git is universal.

### Why This Is Generalizable, Universal, and Versatile

- **Deduplication is free**: Write the same cell twice, store it once. Two paths point to the same hash.
- **Integrity verification is free**: The address is the proof. Read the bytes, hash them, compare to the address.
- **Replication is just sharing hashes**: Two nodes with the same object store are automatically consistent. Sync objects, not paths.
- **BSV anchoring becomes precise**: Anchor the journal root hash — one SHA-256 that commits to the entire mutation history. Verifying any historical state is a Merkle path, not a full replay.
- **Layered stores**: Memory cache → SQLite → IPFS → BSV. Each layer speaks `(hash) → bytes`. The kernel doesn't know which layer answered.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | Adapter callback model, deployment profiles |
| `PHASE-30A` | `docs/prd/PHASE-30A-C-ABI-HEADER.md` | semantos.h, cell_write/cell_read signatures |
| `PHASE-30B` | `docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md` | Callback signatures (host_storage_read/write) |
| `PHASE-30F` | `docs/prd/PHASE-30F-XCFRAMEWORK-SWIFT.md` | Swift adapter implementations |
| `EXPORTS` | `src/ffi/exports.zig` | Current in-memory StringHashMap store |
| `HOSTCALL` | `packages/cell-engine/src/opcodes/hostcall.zig` | OP_CALLHOST dispatch (0xD0) |
| `HOST` | `packages/cell-engine/src/host.zig` | Host function externs |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming |

---

## Architecture

### Storage Model

```
┌─────────────────────────────────────────────┐
│              Semantos Kernel (Zig)          │
│                                             │
│  cell_write(path, data) ─────────────┐     │
│  cell_read(path) ────────────────────┤     │
│                                      │     │
│  (unchanged C ABI — kernel doesn't   │     │
│   know the host switched to CAS)     │     │
└──────────────────────────────────────┼─────┘
                                       │
                          host callback │
                                       ▼
┌─────────────────────────────────────────────┐
│         CAS Host Adapter (Swift)           │
│                                             │
│  cell_write(path, data):                   │
│    hash = SHA-256(data)                    │
│    INSERT OR IGNORE objects(hash, data)    │
│    UPSERT refs(path, hash)                 │
│    APPEND journal(seq, path, old, new)     │
│                                             │
│  cell_read(path):                          │
│    hash = SELECT hash FROM refs(path)      │
│    data = SELECT data FROM objects(hash)   │
│    VERIFY SHA-256(data) == hash            │
│    return data                             │
│                                             │
├─────────────────────────────────────────────┤
│  Namespace   path → hash (refs table)      │
│  Object DB   hash → bytes (objects table)  │
│  Journal     append-only mutation log      │
│  Linearity   consumption state per hash    │
└─────────────────────────────────────────────┘
```

### SQLite Schema

```sql
-- Immutable content-addressed blob store
CREATE TABLE objects (
    hash   BLOB PRIMARY KEY,   -- SHA-256, 32 bytes
    data   BLOB NOT NULL,
    size   INTEGER NOT NULL,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
) WITHOUT ROWID;

-- Mutable namespace: path → hash
CREATE TABLE refs (
    path       TEXT PRIMARY KEY,
    hash       BLOB NOT NULL REFERENCES objects(hash),
    updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
);

-- Append-only mutation journal
CREATE TABLE journal (
    seq        INTEGER PRIMARY KEY AUTOINCREMENT,
    path_hash  BLOB NOT NULL,      -- SHA-256(path) for compact indexing
    old_hash   BLOB,               -- NULL on first write
    new_hash   BLOB NOT NULL,
    timestamp  INTEGER NOT NULL DEFAULT (strftime('%s','now')),
    domain_flag INTEGER DEFAULT 0   -- capability domain if applicable
);

-- Linearity tracking per content hash
CREATE TABLE linearity (
    hash          BLOB PRIMARY KEY REFERENCES objects(hash),
    type_class    INTEGER NOT NULL,   -- 0=RELEVANT, 1=AFFINE, 2=LINEAR
    consumed      INTEGER NOT NULL DEFAULT 0,
    consumed_at   INTEGER,
    consumer_path TEXT                -- which path consumed it
) WITHOUT ROWID;

-- Journal root cache (Merkle tree of journal entries)
CREATE TABLE journal_roots (
    level      INTEGER NOT NULL,
    position   INTEGER NOT NULL,
    hash       BLOB NOT NULL,        -- SHA-256
    PRIMARY KEY (level, position)
) WITHOUT ROWID;

CREATE INDEX idx_refs_hash ON refs(hash);
CREATE INDEX idx_journal_path ON journal(path_hash);
CREATE INDEX idx_journal_ts ON journal(timestamp);
```

### Journal Structure

Every namespace mutation gets appended:

```
[seq][path_hash][old_hash][new_hash][timestamp][domain_flag]
```

This gives:
- **Time-travel**: Read the cell as it existed at any point
- **Audit trail**: Who consumed what, when
- **Anchoring input**: Hash the journal root → submit to BSV → prove any historical state offline
- **Replication**: Sync the journal, reconstruct the namespace anywhere

### Linearity Upgrade

Currently linearity is per-path. With CAS it becomes per-hash:
- A LINEAR object can only be referenced by one path at a time
- `ref_set` checks: is this hash currently referenced elsewhere? If LINEAR → denied
- This is true linear ownership — the hash is the asset, the path is just a handle

### Layered Store (Future Extension)

```
Memory cache (hot cells)
    ↓ miss
SQLite (local persistence)
    ↓ miss
IPFS / overlay network (distributed)
    ↓ miss
BSV (anchored, immutable history)
```

Each layer speaks: `(hash) → bytes`. Phase 30F.2 implements the SQLite layer. Upper and lower layers are future phases.

---

## OP_CALL_HOST Extensions (Optional, Deferred)

Three new `OP_CALL_HOST` function IDs let scripts reference cells by hash. These are **not required** for the CAS storage upgrade — they're a separate concern for when scripts need to speak in hashes rather than paths.

| Function ID | Name | Signature | Purpose |
|-------------|------|-----------|---------|
| `0x0010` | `HOST_FETCH_BY_HASH` | `[32-byte hash] → [cell_bytes]` | Fetch cell by content hash |
| `0x0011` | `HOST_JOURNAL_TIP` | `(no args) → [32-byte hash]` | Current journal root hash |
| `0x0012` | `HOST_DEREF` | `[path_bytes] → [32-byte hash]` | Resolve path → content hash |

These are host I/O operations, not kernel consensus rules. They belong in `OP_CALL_HOST` (0xD0), not as new opcodes. The kernel guarantees determinism for opcodes; for `OP_CALL_HOST`, the host is responsible for the result.

**These are NOT deliverables for Phase 30F.2.** They are documented here for architectural completeness and will be delivered in a future phase when script-level hash references are needed.

---

## Deliverables

### D30F.2.1 — CAS SQLite schema and migration

New file: `platforms/ios/SemantosSDK/Storage/CASSchema.swift`

Creates the SQLite schema (objects, refs, journal, linearity, journal_roots tables). Includes migration logic from the Phase 30F flat key-value schema.

**Acceptance criteria**:
- Schema creates all 5 tables with correct types and constraints
- Migration from flat `cells(path, data)` table to CAS tables preserves all existing data
- Migration is idempotent (can run multiple times safely)
- WAL mode enabled
- Schema version tracked in a `schema_version` table or pragma

### D30F.2.2 — Content-addressed object store

Modified file: `platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift`

Implements the object store layer: `put(data) → hash`, `get(hash) → data`.

**Acceptance criteria**:
- `put(data)` computes SHA-256, stores in objects table, returns hash
- `put(data)` is idempotent — same data produces same hash, no duplicate rows
- `get(hash)` retrieves data and verifies integrity (SHA-256(data) == hash)
- `get(hash)` returns nil/error for missing objects
- Deduplication verified: write same data twice, only one row in objects table

### D30F.2.3 — Namespace reference layer

Modified file: `platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift`

Implements the namespace layer: `ref_set(path, hash)`, `ref_get(path) → hash`.

The existing `storage_write(path, data)` callback becomes:
```
hash = SHA-256(data)
object_put(hash, data)
ref_set(path, hash)
journal_append(path, old_hash, new_hash)
```

The existing `storage_read(path)` callback becomes:
```
hash = ref_get(path)
data = object_get(hash)
return data
```

**Acceptance criteria**:
- `cell_write(path, data)` through the kernel still works identically
- `cell_read(path)` through the kernel still returns identical bytes
- The kernel is completely unaware of the CAS layer underneath
- Namespace correctly maps paths to content hashes
- Multiple paths can reference the same hash (dedup works at namespace level)

### D30F.2.4 — Append-only journal

New file: `platforms/ios/SemantosSDK/Storage/Journal.swift`

Implements the append-only mutation journal. Every `ref_set` appends a journal entry.

**Acceptance criteria**:
- Every namespace mutation creates a journal entry with (seq, path_hash, old_hash, new_hash, timestamp)
- Journal entries are immutable (no updates, no deletes)
- First write to a path records old_hash as NULL
- Journal can be queried by path_hash to get mutation history
- Journal can be queried by timestamp range
- `journal_tip()` returns SHA-256 of the latest journal state (root of Merkle tree over entries)

### D30F.2.5 — Linearity-per-hash enforcement

Modified files: `platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift`, `platforms/ios/SemantosSDK/Storage/LinearityTracker.swift`

Upgrades linearity enforcement from per-path to per-hash.

**Acceptance criteria**:
- LINEAR objects can only be referenced by one path at a time
- Attempting to `ref_set` a LINEAR hash that is already referenced elsewhere → denied (error)
- Consuming a LINEAR cell marks it consumed in the linearity table
- Consumed LINEAR cells cannot be referenced again
- AFFINE and RELEVANT type classes retain existing behavior
- Type class is recorded when object is first stored

### D30F.2.6 — Journal Merkle tree for anchoring

New file: `platforms/ios/SemantosSDK/Storage/JournalMerkle.swift`

Builds an incremental Merkle tree over journal entries. The root hash commits to the entire mutation history and is the input for BSV anchoring.

**Acceptance criteria**:
- Merkle tree is built incrementally (no full rebuild on each append)
- `journal_tip()` returns the current root hash in O(log n)
- Merkle proof can be generated for any journal entry
- Proof can be verified independently (given root + entry + proof → valid/invalid)
- Tree uses SHA-256 for all internal nodes

### D30F.2.7 — Integration tests

New file: `platforms/ios/SemantosSDKTests/CASStorageTests.swift`

XCTest suite covering all CAS functionality.

**Acceptance criteria**:
- Round-trip test: write via kernel → read via kernel → identical bytes
- Deduplication test: write same data to two paths → one object row, two ref rows
- Journal test: write 3 cells → journal has 3 entries in correct order
- Linearity test: LINEAR cell referenced at path A → attempt ref at path B → denied
- Migration test: start with flat schema, migrate, verify all data preserved
- Merkle test: build tree from N entries → verify root → verify proof for entry K
- Integrity test: corrupt an object row → read detects SHA-256 mismatch
- Concurrency test: 100 concurrent writes → no corruption, all journal entries present

---

## TDD Gate Tests

- **T1**: `cell_write()` → `cell_read()` round-trip returns identical bytes through CAS layer
- **T2**: Writing same data to two paths produces exactly one object row
- **T3**: Journal records every namespace mutation with correct old_hash/new_hash
- **T4**: `journal_tip()` returns a 32-byte SHA-256 hash that changes with each mutation
- **T5**: LINEAR hash referenced at path A → `ref_set` at path B → returns error
- **T6**: Migration from flat schema preserves all existing cell data
- **T7**: Merkle proof for journal entry K verifies against journal root
- **T8**: Corrupted object (data doesn't match hash) → read returns integrity error
- **T9**: 100 concurrent write/read cycles → zero corruption, all journal entries present
- **T10**: Kernel is completely unaware of CAS — all existing FFI gate tests still pass unchanged

---

## Capabilities Enabled

| Capability | Before (flat store) | After (CAS + Journal) |
|------------|--------------------|-----------------------|
| Deduplication | No | Free — content-addressed |
| Time-travel | No | Merkle path from journal |
| Cross-device sync | Via HTTP | Sync hashes — automatic consistency |
| True linear ownership | Path-based | Hash-based (real digital asset ownership) |
| BSV anchoring | Hash of data | Hash of journal root (entire history) |
| Offline verification | No | Yes — Merkle proof |
| Garbage collection | No | Trace from namespace roots |
| Integrity verification | Manual | Free — address is proof |

---

## What This Phase Does NOT Include

- **New opcodes**: No Zig kernel changes. The three `OP_CALL_HOST` function IDs (0x0010-0x0012) are documented but deferred.
- **Upper storage layers**: IPFS, overlay network, remote BSV reads — future phases.
- **Garbage collection**: Object pruning when no refs point to a hash — future phase.
- **Conflict resolution**: Multi-device journal merge — addressed in Phase 30I (Offline Queue).

---

## Completion Criteria

1. All 7 deliverables (D30F.2.1–D30F.2.7) complete and committed
2. All 10 TDD Gate Tests pass
3. All existing Phase 30A-30F FFI gate tests still pass unchanged (T10)
4. XCTest suite passes with no failures
5. SQLite schema migration is idempotent and safe
6. Journal Merkle root changes predictably with each mutation
7. LINEAR enforcement works per-hash, not per-path
8. Memory: no leaks after 100 write/read cycles through CAS layer

---

## Notes

- The kernel's `storage_write(path, data)` and `storage_read(path, ...)` callbacks are unchanged — this is a pure host adapter upgrade
- SHA-256 is already in the kernel (`cell.zig`) and in CommonCrypto on iOS — use the host-side implementation for CAS hashing
- WAL mode is already enabled in the Phase 30F SQLiteStorageProvider
- The journal root hash is the single input for BSV anchoring — one hash commits to the entire mutation history
- Content addressing means the same cell stored by two different users on two different devices produces the same hash — replication becomes hash comparison
