---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDK/Storage/JournalMerkle.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.987025+00:00
---

# platforms/ios/SemantosSDK/Storage/JournalMerkle.swift

```swift
// JournalMerkle.swift — Incremental Merkle tree over journal entries
// Phase 30F.2: The root hash commits to the entire mutation history.
//
// Structure:
//   - Leaves: SHA-256(seq_le_8bytes || new_hash)
//   - Interior: SHA-256(left_child || right_child)
//   - Stored in journal_roots(level, position, hash)
//   - Incremental: each append updates O(log n) nodes

import Foundation
import SQLite3
import CryptoKit

/// Merkle inclusion proof for a journal entry.
public struct MerkleProof {
    public let leafPosition: Int64
    public let leafHash: Data
    /// Sibling hashes from leaf to root. Each entry: (sibling hash, sibling is on left).
    public let siblings: [(hash: Data, isLeft: Bool)]
}

/// Incremental binary Merkle tree persisted in journal_roots table.
public final class JournalMerkle {

    private let db: OpaquePointer?

    init(db: OpaquePointer?) {
        self.db = db
    }

    /// Append a journal entry as a new leaf. Returns the updated root hash.
    @discardableResult
    func appendLeaf(seq: Int64, newHash: Data) throws -> Data {
        // Compute leaf hash: SHA-256(seq_le_8bytes || new_hash)
        var seqBytes = withUnsafeBytes(of: seq.littleEndian) { Data($0) }
        seqBytes.append(newHash)
        let leafHash = Data(SHA256.hash(data: seqBytes))

        // Store leaf at level 0
        let position = nextPosition(level: 0)
        try storeNode(level: 0, position: position, hash: leafHash)

        // Propagate up
        try propagateUp(level: 0, position: position)

        return try rootHash()
    }

    /// Get the current root hash. Computes from the highest level node(s).
    func rootHash() throws -> Data {
        let maxLevel = highestLevel()
        if maxLevel < 0 {
            // Empty tree — return hash of empty
            return Data(SHA256.hash(data: Data()))
        }

        // Walk from highest level down, combining unpaired nodes
        var level = Int64(0)
        let leafCount = nextPosition(level: 0)
        if leafCount == 0 {
            return Data(SHA256.hash(data: Data()))
        }

        // For a complete tree, root is at the highest level, position 0
        // For an incomplete tree, we need to combine partial nodes
        return computeRoot(leafCount: leafCount)
    }

    /// Generate a Merkle inclusion proof for the entry at the given position.
    func proof(forPosition position: Int64) throws -> MerkleProof {
        let leafHash = try getNode(level: 0, position: position)
        guard let leaf = leafHash else {
            throw MerkleError.nodeNotFound(level: 0, position: position)
        }

        var siblings: [(hash: Data, isLeft: Bool)] = []
        var pos = position
        var level: Int64 = 0
        let leafCount = nextPosition(level: 0)
        var levelSize = leafCount

        while levelSize > 1 {
            let siblingPos = pos ^ 1 // XOR to get sibling index
            let siblingHash: Data
            if siblingPos < levelSize {
                siblingHash = try getNode(level: level, position: siblingPos) ?? Data(repeating: 0, count: 32)
            } else {
                // No sibling (odd tree) — use zero hash
                siblingHash = Data(repeating: 0, count: 32)
            }
            let siblingIsLeft = (pos % 2 == 1)
            siblings.append((hash: siblingHash, isLeft: siblingIsLeft))

            pos /= 2
            level += 1
            levelSize = (levelSize + 1) / 2
        }

        return MerkleProof(leafPosition: position, leafHash: leaf, siblings: siblings)
    }

    /// Verify a proof independently. Pure computation — no database access.
    public static func verify(proof: MerkleProof, rootHash: Data) -> Bool {
        var current = proof.leafHash
        for sibling in proof.siblings {
            if sibling.isLeft {
                current = sha256Concat(sibling.hash, current)
            } else {
                current = sha256Concat(current, sibling.hash)
            }
        }
        return current == rootHash
    }

    // MARK: - Internal

    private func nextPosition(level: Int64) -> Int64 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "SELECT COUNT(*) FROM journal_roots WHERE level = ?",
            -1, &stmt, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_int64(stmt, 1, level)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(stmt, 0)
    }

    private func storeNode(level: Int64, position: Int64, hash: Data) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "INSERT OR REPLACE INTO journal_roots (level, position, hash) VALUES (?, ?, ?)",
            -1, &stmt, nil) == SQLITE_OK else {
            throw MerkleError.storeFailed(lastError)
        }
        sqlite3_bind_int64(stmt, 1, level)
        sqlite3_bind_int64(stmt, 2, position)
        bindBlob(stmt, index: 3, data: hash)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MerkleError.storeFailed(lastError)
        }
    }

    private func getNode(level: Int64, position: Int64) throws -> Data? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "SELECT hash FROM journal_roots WHERE level = ? AND position = ?",
            -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int64(stmt, 1, level)
        sqlite3_bind_int64(stmt, 2, position)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let ptr = sqlite3_column_blob(stmt, 0)
        let len = Int(sqlite3_column_bytes(stmt, 0))
        guard let p = ptr, len > 0 else { return nil }
        return Data(bytes: p, count: len)
    }

    private func propagateUp(level: Int64, position: Int64) throws {
        var currentLevel = level
        var currentPos = position

        while true {
            let parentPos = currentPos / 2
            let siblingPos = currentPos ^ 1

            // Get sibling (if it exists)
            let currentHash = try getNode(level: currentLevel, position: currentPos)
            let siblingHash = try getNode(level: currentLevel, position: siblingPos)

            guard let current = currentHash else { break }

            let parentHash: Data
            if let sibling = siblingHash {
                if currentPos % 2 == 0 {
                    parentHash = JournalMerkle.sha256Concat(current, sibling)
                } else {
                    parentHash = JournalMerkle.sha256Concat(sibling, current)
                }
            } else {
                // No sibling — promote current as parent
                parentHash = JournalMerkle.sha256Concat(current, Data(repeating: 0, count: 32))
            }

            try storeNode(level: currentLevel + 1, position: parentPos, hash: parentHash)
            currentLevel += 1
            currentPos = parentPos

            // Stop if we're at the only node at this level
            let levelCount = nextPosition(level: currentLevel)
            if levelCount <= 1 { break }
        }
    }

    private func computeRoot(leafCount: Int64) -> Data {
        if leafCount == 0 {
            return Data(SHA256.hash(data: Data()))
        }
        if leafCount == 1 {
            return (try? getNode(level: 0, position: 0)) ?? Data(SHA256.hash(data: Data()))
        }

        // Find the highest stored level with a single node
        var level: Int64 = 0
        var size = leafCount
        while size > 1 {
            level += 1
            size = (size + 1) / 2
        }

        return (try? getNode(level: level, position: 0)) ?? Data(SHA256.hash(data: Data()))
    }

    private func highestLevel() -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "SELECT MAX(level) FROM journal_roots",
            -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return -1 }

        if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return -1 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    static func sha256Concat(_ left: Data, _ right: Data) -> Data {
        var combined = left
        combined.append(right)
        return Data(SHA256.hash(data: combined))
    }

    private func bindBlob(_ stmt: OpaquePointer?, index: Int32, data: Data) {
        data.withUnsafeBytes { buf in
            sqlite3_bind_blob(stmt, index, buf.baseAddress, Int32(buf.count),
                             unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }

    private var lastError: String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }
}

public enum MerkleError: Error, LocalizedError {
    case nodeNotFound(level: Int64, position: Int64)
    case storeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .nodeNotFound(let level, let position):
            return "Merkle node not found at level \(level), position \(position)"
        case .storeFailed(let msg):
            return "Merkle store failed: \(msg)"
        }
    }
}

```
