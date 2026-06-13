---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDK/Storage/Journal.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.986740+00:00
---

# platforms/ios/SemantosSDK/Storage/Journal.swift

```swift
// Journal.swift — Append-only mutation journal for CAS namespace changes
// Phase 30F.2: Every ref_set appends an immutable entry.
//
// CRITICAL: This table is APPEND-ONLY. No UPDATE, no DELETE, ever.
// The journal is the input for time-travel, anchoring, and replication.

import Foundation
import SQLite3
import CryptoKit

/// A single journal entry recording a namespace mutation.
public struct JournalEntry {
    public let seq: Int64
    public let pathHash: Data
    public let oldHash: Data?
    public let newHash: Data
    public let timestamp: Int64
    public let domainFlag: Int
}

/// Append-only mutation journal. Records every namespace change (ref_set).
public final class Journal {

    private let db: OpaquePointer?

    init(db: OpaquePointer?) {
        self.db = db
    }

    /// Append a mutation entry. Returns the new sequence number.
    /// old_hash is nil on first write to a path.
    @discardableResult
    func append(path: String, oldHash: Data?, newHash: Data, domainFlag: Int = 0) throws -> Int64 {
        let pathHash = Data(SHA256.hash(data: Data(path.utf8)))

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "INSERT INTO journal (path_hash, old_hash, new_hash, domain_flag) VALUES (?, ?, ?, ?)",
            -1, &stmt, nil) == SQLITE_OK else {
            throw JournalError.appendFailed(lastError)
        }

        bindBlob(stmt, index: 1, data: pathHash)

        if let old = oldHash {
            bindBlob(stmt, index: 2, data: old)
        } else {
            sqlite3_bind_null(stmt, 2)
        }

        bindBlob(stmt, index: 3, data: newHash)
        sqlite3_bind_int(stmt, 4, Int32(domainFlag))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw JournalError.appendFailed(lastError)
        }

        return sqlite3_last_insert_rowid(db)
    }

    /// Get mutation history for a path, ordered by sequence.
    func history(path: String) throws -> [JournalEntry] {
        let pathHash = Data(SHA256.hash(data: Data(path.utf8)))

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "SELECT seq, path_hash, old_hash, new_hash, timestamp, domain_flag FROM journal WHERE path_hash = ? ORDER BY seq ASC",
            -1, &stmt, nil) == SQLITE_OK else {
            throw JournalError.queryFailed(lastError)
        }
        bindBlob(stmt, index: 1, data: pathHash)

        return collectEntries(stmt: stmt)
    }

    /// Get journal entries in a sequence range (inclusive).
    func entriesBetween(fromSeq: Int64, toSeq: Int64) throws -> [JournalEntry] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "SELECT seq, path_hash, old_hash, new_hash, timestamp, domain_flag FROM journal WHERE seq BETWEEN ? AND ? ORDER BY seq ASC",
            -1, &stmt, nil) == SQLITE_OK else {
            throw JournalError.queryFailed(lastError)
        }
        sqlite3_bind_int64(stmt, 1, fromSeq)
        sqlite3_bind_int64(stmt, 2, toSeq)

        return collectEntries(stmt: stmt)
    }

    /// Current journal tip (latest sequence number). Returns 0 if empty.
    func latestSeq() -> Int64 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "SELECT MAX(seq) FROM journal", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        let val = sqlite3_column_int64(stmt, 0)
        return sqlite3_column_type(stmt, 0) == SQLITE_NULL ? 0 : val
    }

    /// Total entry count.
    func count() -> Int64 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM journal", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }
        return sqlite3_column_int64(stmt, 0)
    }

    // MARK: - Internal

    private func collectEntries(stmt: OpaquePointer?) -> [JournalEntry] {
        var entries: [JournalEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let seq = sqlite3_column_int64(stmt, 0)
            let pathHash = readBlob(stmt, column: 1) ?? Data()
            let oldHash = readBlob(stmt, column: 2)
            let newHash = readBlob(stmt, column: 3) ?? Data()
            let timestamp = sqlite3_column_int64(stmt, 4)
            let domainFlag = Int(sqlite3_column_int(stmt, 5))

            entries.append(JournalEntry(
                seq: seq, pathHash: pathHash, oldHash: oldHash,
                newHash: newHash, timestamp: timestamp, domainFlag: domainFlag
            ))
        }
        return entries
    }

    private func readBlob(_ stmt: OpaquePointer?, column: Int32) -> Data? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL else { return nil }
        let ptr = sqlite3_column_blob(stmt, column)
        let len = Int(sqlite3_column_bytes(stmt, column))
        guard let p = ptr, len > 0 else { return nil }
        return Data(bytes: p, count: len)
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

public enum JournalError: Error, LocalizedError {
    case appendFailed(String)
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .appendFailed(let msg): return "Journal append failed: \(msg)"
        case .queryFailed(let msg): return "Journal query failed: \(msg)"
        }
    }
}

```
