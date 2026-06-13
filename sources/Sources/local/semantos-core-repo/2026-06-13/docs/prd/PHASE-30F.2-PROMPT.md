---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30F.2-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.707566+00:00
---

# Phase 30F.2 Execution Prompt — Content-Addressed Cell Store & Journal

> Paste this prompt into a fresh session to execute Phase 30F.2.

## Context

The kernel's cell store is an in-memory `StringHashMap` in `exports.zig`. Host storage callbacks (Phase 30B) route I/O through `SQLiteStorageProvider`, but the model is `path → bytes`. This phase upgrades to content-addressed storage: `path → hash → bytes`, with an append-only journal for time-travel, anchoring, and replication. **This is entirely a host adapter change — zero Zig kernel modifications.**

### The Core Design

```
cell_write(path, data):
    hash = SHA-256(data)
    INSERT OR IGNORE objects(hash, data)     -- content-addressed, deduplicated
    old  = SELECT hash FROM refs(path)       -- capture previous state
    UPSERT refs(path, hash)                  -- update namespace
    APPEND journal(path, old, hash)          -- immutable mutation log

cell_read(path):
    hash = SELECT hash FROM refs(path)       -- resolve namespace
    data = SELECT data FROM objects(hash)    -- fetch by content hash
    VERIFY SHA-256(data) == hash             -- integrity check is free
    return data
```

The kernel calls the same `storage_write(path, data)` and `storage_read(path, ...)` callbacks as before. It doesn't know the host switched to CAS.

---

## CRITICAL: READ THESE FILES FIRST

1. `docs/prd/PHASE-30F.2-CAS-STORAGE.md` — Full PRD with architecture, schema, deliverables
2. `docs/prd/PHASE-30-FFI-MASTER.md` — Adapter callback model, deployment profiles
3. `docs/prd/PHASE-30A-C-ABI-HEADER.md` — semantos.h, cell_write/cell_read signatures
4. `docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md` — Callback signatures (host_storage_read/write)
5. `docs/prd/PHASE-30F-XCFRAMEWORK-SWIFT.md` — Swift adapter implementations (current state)
6. `docs/BRANCHING-AND-CI-POLICY.md` — Commit naming convention
7. `platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift` — Current flat storage implementation

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

1. **ZERO KERNEL CHANGES**: Do not modify any Zig source files. Not `exports.zig`, not `cell.zig`, not `host.zig`, not `build.zig`. This is a pure host adapter upgrade. If you think you need to change the kernel, you're wrong — re-read the architecture.
2. **KERNEL MUST NOT KNOW**: After your changes, all existing Phase 30A-30F FFI gate tests must pass unchanged. The kernel calls `storage_write(path, data)` and `storage_read(path, ...)` and gets back identical results. It never learns about hashes, journals, or Merkle trees.
3. **SHA-256 INTEGRITY IS MANDATORY**: Every `object_get(hash)` must verify `SHA-256(data) == hash`. If they don't match, return an integrity error — do not return corrupt data. This is the entire point of content addressing.
4. **JOURNAL IS APPEND-ONLY**: No updates, no deletes, ever. The journal table is an immutable log. If you write SQL with UPDATE or DELETE on the journal table, you've broken the design.
5. **DEDUPLICATION MUST WORK**: Writing the same data to two different paths must produce exactly one row in the objects table and two rows in the refs table. Test this explicitly.
6. **LINEARITY IS PER-HASH, NOT PER-PATH**: A LINEAR cell is identified by its content hash. If hash H is referenced at path A, attempting to reference H at path B must fail. The hash is the asset; the path is a handle.
7. **MIGRATION MUST BE SAFE**: The flat `cells(path, data)` table from Phase 30F must be migrated to CAS without data loss. Migration must be idempotent.
8. **NO EASY TESTS**: Tests must verify real behavior. Dedup test must COUNT rows. Journal test must verify ordering. Linearity test must verify denial. Merkle test must verify a proof independently.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
git status
git log --oneline -10
git branch -a
```

What is the current state? Any uncommitted changes?

### 0.2 Commit or discard

If there are uncommitted changes:
- If they're relevant to Phase 30F.2, commit them first
- If not, discard: `git checkout -- .`

### 0.3 Verify prerequisites

- Phase 30F must be merged (XCFramework + Swift adapters exist)
- `platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift` must exist
- All Phase 30A-30F FFI gate tests must pass
- Run `zig build test` to verify baseline

### 0.4 Create branch

```bash
git checkout -b phase-30f2-cas-storage
```

Verify: `git branch`

---

## Step 1: CAS SQLite Schema & Migration (D30F.2.1)

Commit: `phase-30f2/D30F.2.1: add CAS SQLite schema and migration from flat store`

### What to do

1. Create `platforms/ios/SemantosSDK/Storage/CASSchema.swift`
2. Define the 5-table schema:
   ```sql
   CREATE TABLE objects (
       hash       BLOB PRIMARY KEY,
       data       BLOB NOT NULL,
       size       INTEGER NOT NULL,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
   ) WITHOUT ROWID;

   CREATE TABLE refs (
       path       TEXT PRIMARY KEY,
       hash       BLOB NOT NULL REFERENCES objects(hash),
       updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
   );

   CREATE TABLE journal (
       seq        INTEGER PRIMARY KEY AUTOINCREMENT,
       path_hash  BLOB NOT NULL,
       old_hash   BLOB,
       new_hash   BLOB NOT NULL,
       timestamp  INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       domain_flag INTEGER DEFAULT 0
   );

   CREATE TABLE linearity (
       hash          BLOB PRIMARY KEY REFERENCES objects(hash),
       type_class    INTEGER NOT NULL,
       consumed      INTEGER NOT NULL DEFAULT 0,
       consumed_at   INTEGER,
       consumer_path TEXT
   ) WITHOUT ROWID;

   CREATE TABLE journal_roots (
       level      INTEGER NOT NULL,
       position   INTEGER NOT NULL,
       hash       BLOB NOT NULL,
       PRIMARY KEY (level, position)
   ) WITHOUT ROWID;
   ```
3. Add indexes: `idx_refs_hash ON refs(hash)`, `idx_journal_path ON journal(path_hash)`, `idx_journal_ts ON journal(timestamp)`
4. Implement migration from flat `cells(path TEXT, data BLOB)`:
   ```swift
   func migrateFromFlatStore() {
       // For each row in cells:
       //   hash = SHA256(data)
       //   INSERT OR IGNORE INTO objects(hash, data, size)
       //   INSERT INTO refs(path, hash)
       //   INSERT INTO journal(path_hash, old_hash, new_hash) -- old_hash = NULL
       // Then DROP TABLE cells
   }
   ```
5. Track schema version via `PRAGMA user_version`
6. Migration must be idempotent

### Acceptance

- Schema creates all 5 tables with correct types
- Migration preserves all existing cell data
- `PRAGMA user_version` tracks schema version
- WAL mode enabled
- Running migration twice is safe (no duplicates, no errors)

### Commit

```bash
git add platforms/ios/SemantosSDK/Storage/CASSchema.swift
git commit -m "phase-30f2/D30F.2.1: add CAS SQLite schema and migration from flat store"
```

---

## Step 2: Content-Addressed Object Store (D30F.2.2)

Commit: `phase-30f2/D30F.2.2: implement content-addressed object store (put/get by hash)`

### What to do

1. Modify `SQLiteStorageProvider.swift` to add object store methods:
   ```swift
   /// Store data by content hash. Idempotent — same data always produces same hash.
   func objectPut(_ data: Data) -> Data {  // returns 32-byte SHA-256 hash
       let hash = SHA256.hash(data: data)
       let hashData = Data(hash)
       // INSERT OR IGNORE — deduplication is automatic
       db.execute("INSERT OR IGNORE INTO objects(hash, data, size) VALUES (?, ?, ?)",
                  hashData, data, data.count)
       return hashData
   }

   /// Retrieve data by content hash. Verifies integrity on read.
   func objectGet(_ hash: Data) -> Data? {
       guard let data = db.query("SELECT data FROM objects WHERE hash = ?", hash) else {
           return nil
       }
       // Integrity check: content addressing means the address IS the proof
       let computedHash = Data(SHA256.hash(data: data))
       guard computedHash == hash else {
           // Corruption detected — data doesn't match its address
           return nil  // or throw integrity error
       }
       return data
   }
   ```
2. Use `CryptoKit` for SHA-256 (`import CryptoKit`)
3. `INSERT OR IGNORE` ensures deduplication — same hash can't be inserted twice
4. Read-time integrity verification is mandatory

### Acceptance

- `objectPut(data)` returns correct SHA-256 hash
- `objectPut(data)` is idempotent — same data twice → one row
- `objectGet(hash)` returns original data
- `objectGet(hash)` verifies SHA-256 integrity
- `objectGet(hash)` returns nil for missing hashes
- `objectGet(hash)` returns nil/error for corrupted data

### Commit

```bash
git add platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift
git commit -m "phase-30f2/D30F.2.2: implement content-addressed object store (put/get by hash)"
```

---

## Step 3: Namespace Reference Layer (D30F.2.3)

Commit: `phase-30f2/D30F.2.3: implement namespace reference layer (path → hash resolution)`

### What to do

1. Add namespace methods to `SQLiteStorageProvider.swift`:
   ```swift
   func refSet(_ path: String, hash: Data) {
       // Get old hash for journal entry
       let oldHash = refGet(path)
       // Upsert: create or update path → hash mapping
       db.execute("INSERT INTO refs(path, hash) VALUES (?, ?) ON CONFLICT(path) DO UPDATE SET hash = ?, updated_at = strftime('%s','now')",
                  path, hash, hash)
       // Journal the mutation
       journalAppend(path: path, oldHash: oldHash, newHash: hash)
   }

   func refGet(_ path: String) -> Data? {
       return db.query("SELECT hash FROM refs WHERE path = ?", path)
   }
   ```
2. Rewrite the `@convention(c)` storage callbacks to use CAS:
   ```swift
   // storage_write callback: path + data → CAS store
   @convention(c) func hostStorageWrite(pathPtr: ..., dataPtr: ...) -> Int32 {
       let provider = SQLiteStorageProvider.shared
       let hash = provider.objectPut(data)
       provider.refSet(path, hash: hash)
       return 0  // SEMANTOS_OK
   }

   // storage_read callback: path → resolve → fetch → return
   @convention(c) func hostStorageRead(pathPtr: ..., outPtr: ...) -> Int32 {
       let provider = SQLiteStorageProvider.shared
       guard let hash = provider.refGet(path) else { return -2 } // NOT_FOUND
       guard let data = provider.objectGet(hash) else { return -3 } // INTEGRITY_ERROR
       // Copy data to output buffer
       return 0  // SEMANTOS_OK
   }
   ```
3. **Critical**: The kernel's `cell_write(path, data)` and `cell_read(path)` must behave identically to before. The CAS layer is invisible to the kernel.

### Acceptance

- `cell_write("/foo", data)` through the kernel works identically
- `cell_read("/foo")` through the kernel returns identical bytes
- The kernel is completely unaware of the CAS layer
- Two paths pointing to same data → one object row, two ref rows
- All existing Phase 30A-30F FFI gate tests pass unchanged

### Commit

```bash
git add platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift
git add platforms/ios/SemantosSDK/Callbacks.swift
git commit -m "phase-30f2/D30F.2.3: implement namespace reference layer (path → hash resolution)"
```

---

## Step 4: Append-Only Journal (D30F.2.4)

Commit: `phase-30f2/D30F.2.4: implement append-only mutation journal`

### What to do

1. Create `platforms/ios/SemantosSDK/Storage/Journal.swift`:
   ```swift
   class Journal {
       private let db: SQLiteDatabase

       /// Append a mutation entry. Never updates or deletes.
       func append(path: String, oldHash: Data?, newHash: Data, domainFlag: Int = 0) {
           let pathHash = Data(SHA256.hash(data: Data(path.utf8)))
           db.execute("""
               INSERT INTO journal(path_hash, old_hash, new_hash, domain_flag)
               VALUES (?, ?, ?, ?)
           """, pathHash, oldHash, newHash, domainFlag)
       }

       /// Get mutation history for a path.
       func history(path: String) -> [(seq: Int, oldHash: Data?, newHash: Data, timestamp: Int)] {
           let pathHash = Data(SHA256.hash(data: Data(path.utf8)))
           return db.query("SELECT seq, old_hash, new_hash, timestamp FROM journal WHERE path_hash = ? ORDER BY seq", pathHash)
       }

       /// Get journal entries in a time range.
       func entriesBetween(start: Int, end: Int) -> [...] {
           return db.query("SELECT * FROM journal WHERE timestamp BETWEEN ? AND ? ORDER BY seq", start, end)
       }

       /// Current journal tip (latest seq).
       func latestSeq() -> Int {
           return db.query("SELECT MAX(seq) FROM journal") ?? 0
       }
   }
   ```
2. Wire `journalAppend()` into `refSet()` from Step 3
3. Journal entries are immutable — no UPDATE, no DELETE on journal table. Ever.

### Acceptance

- Every `cell_write()` creates a journal entry
- First write to a path has old_hash = NULL
- Subsequent writes capture the previous hash as old_hash
- Journal entries are ordered by seq
- `history(path)` returns all mutations for that path
- Journal table has no UPDATE or DELETE statements in any code path

### Commit

```bash
git add platforms/ios/SemantosSDK/Storage/Journal.swift
git commit -m "phase-30f2/D30F.2.4: implement append-only mutation journal"
```

---

## Step 5: Linearity-Per-Hash Enforcement (D30F.2.5)

Commit: `phase-30f2/D30F.2.5: enforce linearity per content hash (not per path)`

### What to do

1. Create `platforms/ios/SemantosSDK/Storage/LinearityTracker.swift`:
   ```swift
   enum TypeClass: Int {
       case relevant = 0   // can be referenced any number of times
       case affine = 1     // can be referenced at most once (soft)
       case linear = 2     // must be referenced exactly once (strict)
   }

   class LinearityTracker {
       /// Register a new object's type class.
       func register(hash: Data, typeClass: TypeClass) {
           db.execute("INSERT OR IGNORE INTO linearity(hash, type_class) VALUES (?, ?)",
                      hash, typeClass.rawValue)
       }

       /// Check if hash can be referenced at a new path.
       func canReference(hash: Data) -> Bool {
           guard let row = db.query("SELECT type_class, consumed FROM linearity WHERE hash = ?", hash) else {
               return true  // unknown hash — allow (RELEVANT by default)
           }
           if row.consumed != 0 { return false }  // already consumed
           if row.typeClass == TypeClass.linear.rawValue {
               // Check if already referenced elsewhere
               let refCount = db.query("SELECT COUNT(*) FROM refs WHERE hash = ?", hash)
               if refCount > 0 { return false }  // LINEAR hash already referenced
           }
           return true
       }

       /// Consume a LINEAR cell.
       func consume(hash: Data, consumerPath: String) -> Bool {
           // Atomically mark consumed
           let affected = db.execute("""
               UPDATE linearity SET consumed = 1, consumed_at = strftime('%s','now'), consumer_path = ?
               WHERE hash = ? AND consumed = 0 AND type_class = ?
           """, consumerPath, hash, TypeClass.linear.rawValue)
           return affected > 0
       }
   }
   ```
2. Wire linearity checks into `refSet()`:
   ```swift
   func refSet(_ path: String, hash: Data) {
       guard linearityTracker.canReference(hash) else {
           throw SemantosError.denied  // LINEAR hash already referenced elsewhere
       }
       // ... proceed with ref set
   }
   ```
3. Type class comes from the cell header (byte offset in 1024-byte cell format) — parse it when storing

### Acceptance

- RELEVANT cells can be referenced by multiple paths
- LINEAR cells can only be referenced by one path at a time
- Attempting to reference a LINEAR hash at a second path → denied
- Consuming a LINEAR cell marks it consumed atomically
- Consumed cells cannot be referenced again
- Existing linearity tests still pass

### Commit

```bash
git add platforms/ios/SemantosSDK/Storage/LinearityTracker.swift
git add platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift
git commit -m "phase-30f2/D30F.2.5: enforce linearity per content hash (not per path)"
```

---

## Step 6: Journal Merkle Tree (D30F.2.6)

Commit: `phase-30f2/D30F.2.6: implement incremental Merkle tree over journal for anchoring`

### What to do

1. Create `platforms/ios/SemantosSDK/Storage/JournalMerkle.swift`:
   ```swift
   class JournalMerkle {
       /// Append a leaf (journal entry hash) and update the Merkle tree incrementally.
       func appendLeaf(_ entryHash: Data) {
           // Store leaf at level 0
           let position = nextLeafPosition()
           storeNode(level: 0, position: position, hash: entryHash)
           // Propagate up: if this position is even, combine with sibling
           propagateUp(level: 0, position: position)
       }

       /// Get the current root hash. This commits to the entire journal history.
       func rootHash() -> Data {
           return computeRoot()
       }

       /// Generate a Merkle inclusion proof for entry at position.
       func proof(forPosition position: Int) -> MerkleProof {
           // Collect sibling hashes from leaf to root
           var siblings: [(hash: Data, isLeft: Bool)] = []
           var level = 0
           var pos = position
           while level < treeHeight {
               let siblingPos = pos ^ 1  // XOR to get sibling
               let siblingHash = getNode(level: level, position: siblingPos)
               siblings.append((siblingHash, pos % 2 == 1))
               pos /= 2
               level += 1
           }
           return MerkleProof(leafPosition: position, siblings: siblings)
       }

       /// Verify a proof independently.
       static func verify(proof: MerkleProof, leafHash: Data, rootHash: Data) -> Bool {
           var current = leafHash
           for sibling in proof.siblings {
               if sibling.isLeft {
                   current = sha256(sibling.hash + current)
               } else {
                   current = sha256(current + sibling.hash)
               }
           }
           return current == rootHash
       }
   }
   ```
2. Store Merkle nodes in `journal_roots` table for persistence
3. Tree is built incrementally — each new journal entry only recomputes O(log n) nodes
4. Wire into journal: every `Journal.append()` also calls `merkle.appendLeaf(entryHash)`

### Acceptance

- `rootHash()` returns a 32-byte SHA-256 hash
- `rootHash()` changes with each journal entry
- `proof(forPosition:)` generates a valid Merkle path
- `JournalMerkle.verify(proof, leafHash, rootHash)` returns true for valid proofs
- Verification works independently (no database access needed)
- Incremental — appending one entry updates O(log n) nodes, not O(n)

### Commit

```bash
git add platforms/ios/SemantosSDK/Storage/JournalMerkle.swift
git commit -m "phase-30f2/D30F.2.6: implement incremental Merkle tree over journal for anchoring"
```

---

## Step 7: Integration Tests (D30F.2.7)

Commit: `phase-30f2/D30F.2.7: add CAS storage integration tests`

### What to do

1. Create `platforms/ios/SemantosSDKTests/CASStorageTests.swift`:
   ```swift
   class CASStorageTests: XCTestCase {

       func testRoundTrip() {
           // Write via kernel → read via kernel → identical bytes
           let kernel = SemantosKernel()
           try kernel.initialize(...)
           let data = "Hello, CAS!".data(using: .utf8)!
           try kernel.cellWrite(path: "/test/round-trip", data: data)
           let readBack = kernel.cellRead(path: "/test/round-trip")
           XCTAssertEqual(readBack, data)
       }

       func testDeduplication() {
           // Same data to two paths → COUNT objects = 1, COUNT refs = 2
           let data = "dedup-test".data(using: .utf8)!
           try kernel.cellWrite(path: "/path/a", data: data)
           try kernel.cellWrite(path: "/path/b", data: data)
           let objectCount = db.query("SELECT COUNT(*) FROM objects WHERE hash = ?", sha256(data))
           let refCount = db.query("SELECT COUNT(*) FROM refs WHERE hash = ?", sha256(data))
           XCTAssertEqual(objectCount, 1)
           XCTAssertEqual(refCount, 2)
       }

       func testJournalOrdering() {
           // Write 3 cells → journal has 3 entries in seq order
           for i in 0..<3 {
               try kernel.cellWrite(path: "/seq/\(i)", data: Data([UInt8(i)]))
           }
           let entries = journal.entriesBetween(start: 0, end: Int.max)
           XCTAssertEqual(entries.count, 3)
           XCTAssert(entries[0].seq < entries[1].seq)
           XCTAssert(entries[1].seq < entries[2].seq)
       }

       func testLinearityPerHash() {
           // LINEAR cell at path A → attempt ref at path B → denied
           let linearData = buildLinearCell(...)  // cell with LINEAR type class
           try kernel.cellWrite(path: "/asset/original", data: linearData)
           XCTAssertThrowsError(try kernel.cellWrite(path: "/asset/copy", data: linearData))
       }

       func testMigration() {
           // Start with flat schema, write data, migrate, verify preserved
       }

       func testMerkleProof() {
           // Build tree, generate proof for entry K, verify independently
           for i in 0..<10 {
               try kernel.cellWrite(path: "/merkle/\(i)", data: Data([UInt8(i)]))
           }
           let root = merkle.rootHash()
           let proof = merkle.proof(forPosition: 5)
           let leafHash = sha256(journalEntry5)
           XCTAssertTrue(JournalMerkle.verify(proof: proof, leafHash: leafHash, rootHash: root))
       }

       func testIntegrityDetection() {
           // Corrupt an object row → read returns error
           try kernel.cellWrite(path: "/integrity", data: validData)
           db.execute("UPDATE objects SET data = ? WHERE hash = ?", corruptData, hash)
           XCTAssertNil(kernel.cellRead(path: "/integrity"))
       }

       func testConcurrentWrites() {
           // 100 concurrent writes → no corruption
           let group = DispatchGroup()
           for i in 0..<100 {
               group.enter()
               DispatchQueue.global().async {
                   try? kernel.cellWrite(path: "/concurrent/\(i)", data: Data([UInt8(i % 256)]))
                   group.leave()
               }
           }
           group.wait()
           // Verify all 100 cells readable and journal has 100 entries
       }

       func testExistingFFIGateTests() {
           // ALL Phase 30A-30F gate tests must still pass unchanged
           // This is T10 — the most important test
       }
   }
   ```

### Acceptance

- All 8 test categories pass
- Round-trip verifies byte-level equality
- Dedup verifies row counts
- Journal verifies ordering
- Linearity verifies denial
- Migration verifies data preservation
- Merkle verifies independent proof
- Integrity verifies corruption detection
- Concurrency verifies no corruption under load

### Commit

```bash
git add platforms/ios/SemantosSDKTests/CASStorageTests.swift
git commit -m "phase-30f2/D30F.2.7: add CAS storage integration tests"
```

---

## Completion Criteria

1. All 7 deliverables (D30F.2.1–D30F.2.7) complete and committed
2. All 10 TDD Gate Tests pass
3. **ALL existing Phase 30A-30F FFI gate tests pass unchanged** (most important)
4. XCTest suite passes with no failures
5. SQLite schema migration is idempotent and safe
6. Journal Merkle root changes predictably with each mutation
7. LINEAR enforcement works per-hash, not per-path
8. Memory: no leaks after 100 write/read cycles through CAS layer

---

## Post-Phase: Errata Sprint

After Phase 30F.2 merges to main:

1. **Regression sweep**: Run ALL Phase 30A-30G test suites to confirm zero regressions
2. **Performance**: Profile CAS overhead vs flat store (SHA-256 computation + extra SQL queries)
3. **Schema audit**: Verify all indexes are optimal, no missing constraints
4. **Concurrency audit**: Verify WAL mode handles concurrent reads/writes correctly
5. **Documentation**: Add CAS architecture diagram to docs/ARCHITECTURE.md
6. **Dart parity**: Port CAS storage to Dart `SqfliteStorageAdapter` (Phase 30G.2)

---

## Notes

- The kernel's `storage_write(path, data)` and `storage_read(path, ...)` callbacks are unchanged — this is a pure host adapter upgrade
- SHA-256 in Swift: `import CryptoKit` → `SHA256.hash(data:)` — available on iOS 13+
- WAL mode is already enabled from Phase 30F
- The journal root hash is the single input for BSV anchoring — one hash commits to the entire mutation history
- Content addressing means the same cell stored on two different devices produces the same hash — replication is hash comparison
- The three `OP_CALL_HOST` function IDs (0x0010-0x0012) are documented in the PRD but NOT part of this phase — they're for when scripts need hash-level references
- `INSERT OR IGNORE` on objects table handles deduplication at the SQL level — no application-level check needed
- `WITHOUT ROWID` on objects and linearity tables optimizes for BLOB primary key lookups
