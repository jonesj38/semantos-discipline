---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDK/Storage/CASSchema.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.987320+00:00
---

# platforms/ios/SemantosSDK/Storage/CASSchema.swift

```swift
// CASSchema.swift — Content-Addressed Storage schema and migration
// Phase 30F.2: Upgrades flat cells(path, data) to CAS (objects, refs, journal, linearity, journal_roots).
//
// Schema version tracked via PRAGMA user_version:
//   0 = Phase 30F flat store (cells table)
//   1 = Phase 30F.2 CAS store (5 tables)

import Foundation
import SQLite3
import CryptoKit

public enum CASSchema {

    /// Current schema version.
    static let currentVersion: Int32 = 1

    /// Ensure the database is at the current schema version.
    /// Creates tables if fresh, migrates if coming from flat store.
    /// Idempotent — safe to call multiple times.
    static func ensureSchema(db: OpaquePointer?) throws {
        let version = pragmaUserVersion(db: db)
        if version < currentVersion {
            try migrateToV1(db: db)
        }
    }

    // MARK: - Schema DDL

    private static let createObjectsTable = """
        CREATE TABLE IF NOT EXISTS objects (
            hash       BLOB PRIMARY KEY,
            data       BLOB NOT NULL,
            size       INTEGER NOT NULL,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        ) WITHOUT ROWID
    """

    private static let createRefsTable = """
        CREATE TABLE IF NOT EXISTS refs (
            path       TEXT PRIMARY KEY,
            hash       BLOB NOT NULL REFERENCES objects(hash),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        )
    """

    private static let createJournalTable = """
        CREATE TABLE IF NOT EXISTS journal (
            seq        INTEGER PRIMARY KEY AUTOINCREMENT,
            path_hash  BLOB NOT NULL,
            old_hash   BLOB,
            new_hash   BLOB NOT NULL,
            timestamp  INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            domain_flag INTEGER DEFAULT 0
        )
    """

    private static let createLinearityTable = """
        CREATE TABLE IF NOT EXISTS linearity (
            hash          BLOB PRIMARY KEY REFERENCES objects(hash),
            type_class    INTEGER NOT NULL,
            consumed      INTEGER NOT NULL DEFAULT 0,
            consumed_at   INTEGER,
            consumer_path TEXT
        ) WITHOUT ROWID
    """

    private static let createJournalRootsTable = """
        CREATE TABLE IF NOT EXISTS journal_roots (
            level      INTEGER NOT NULL,
            position   INTEGER NOT NULL,
            hash       BLOB NOT NULL,
            PRIMARY KEY (level, position)
        ) WITHOUT ROWID
    """

    private static let createIndexes = [
        "CREATE INDEX IF NOT EXISTS idx_refs_hash ON refs(hash)",
        "CREATE INDEX IF NOT EXISTS idx_journal_path ON journal(path_hash)",
        "CREATE INDEX IF NOT EXISTS idx_journal_ts ON journal(timestamp)",
    ]

    // MARK: - Migration

    private static func migrateToV1(db: OpaquePointer?) throws {
        // Use EXCLUSIVE transaction for migration safety
        try execSQL(db: db, sql: "BEGIN EXCLUSIVE")

        do {
            // Create all 5 tables
            try execSQL(db: db, sql: createObjectsTable)
            try execSQL(db: db, sql: createRefsTable)
            try execSQL(db: db, sql: createJournalTable)
            try execSQL(db: db, sql: createLinearityTable)
            try execSQL(db: db, sql: createJournalRootsTable)

            // Create indexes
            for indexSQL in createIndexes {
                try execSQL(db: db, sql: indexSQL)
            }

            // Migrate data from flat cells table if it exists
            if tableExists(db: db, name: "cells") {
                try migrateFlatCells(db: db)
                try execSQL(db: db, sql: "DROP TABLE cells")
            }

            // Set schema version
            try execSQL(db: db, sql: "PRAGMA user_version = \(currentVersion)")

            try execSQL(db: db, sql: "COMMIT")
        } catch {
            // Roll back on any failure
            try? execSQL(db: db, sql: "ROLLBACK")
            throw error
        }
    }

    /// Migrate rows from flat cells(path, data) table to CAS tables.
    private static func migrateFlatCells(db: OpaquePointer?) throws {
        var selectStmt: OpaquePointer?
        defer { sqlite3_finalize(selectStmt) }

        guard sqlite3_prepare_v2(db, "SELECT path, data FROM cells", -1, &selectStmt, nil) == SQLITE_OK else {
            throw CASMigrationError.prepareFailed(lastError(db: db))
        }

        // Prepared statements for inserts
        var insertObject: OpaquePointer?
        var insertRef: OpaquePointer?
        var insertJournal: OpaquePointer?
        defer {
            sqlite3_finalize(insertObject)
            sqlite3_finalize(insertRef)
            sqlite3_finalize(insertJournal)
        }

        guard sqlite3_prepare_v2(db,
            "INSERT OR IGNORE INTO objects (hash, data, size) VALUES (?, ?, ?)",
            -1, &insertObject, nil) == SQLITE_OK else {
            throw CASMigrationError.prepareFailed(lastError(db: db))
        }

        guard sqlite3_prepare_v2(db,
            "INSERT OR IGNORE INTO refs (path, hash) VALUES (?, ?)",
            -1, &insertRef, nil) == SQLITE_OK else {
            throw CASMigrationError.prepareFailed(lastError(db: db))
        }

        guard sqlite3_prepare_v2(db,
            "INSERT INTO journal (path_hash, old_hash, new_hash) VALUES (?, NULL, ?)",
            -1, &insertJournal, nil) == SQLITE_OK else {
            throw CASMigrationError.prepareFailed(lastError(db: db))
        }

        while sqlite3_step(selectStmt) == SQLITE_ROW {
            // Read path
            guard let pathCStr = sqlite3_column_text(selectStmt, 0) else { continue }
            let path = String(cString: pathCStr)

            // Read data
            let dataPtr = sqlite3_column_blob(selectStmt, 1)
            let dataLen = Int(sqlite3_column_bytes(selectStmt, 1))
            let data: Data
            if let ptr = dataPtr, dataLen > 0 {
                data = Data(bytes: ptr, count: dataLen)
            } else {
                data = Data()
            }

            // Compute SHA-256
            let hash = Data(SHA256.hash(data: data))

            // Insert into objects
            try bindAndStep(stmt: insertObject, bindings: [
                .blob(hash), .blob(data), .int(Int64(data.count))
            ])
            sqlite3_reset(insertObject)

            // Insert into refs
            try bindAndStep(stmt: insertRef, bindings: [
                .text(path), .blob(hash)
            ])
            sqlite3_reset(insertRef)

            // Insert into journal
            let pathHash = Data(SHA256.hash(data: Data(path.utf8)))
            try bindAndStep(stmt: insertJournal, bindings: [
                .blob(pathHash), .blob(hash)
            ])
            sqlite3_reset(insertJournal)
        }
    }

    // MARK: - Helpers

    private static func pragmaUserVersion(db: OpaquePointer?) -> Int32 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }
        return sqlite3_column_int(stmt, 0)
    }

    private static func tableExists(db: OpaquePointer?, name: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db,
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            -1, &stmt, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(stmt, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private static func execSQL(db: OpaquePointer?, sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.flatMap { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw CASMigrationError.executeFailed(msg)
        }
    }

    private static func lastError(db: OpaquePointer?) -> String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }

    private enum BindValue {
        case blob(Data)
        case text(String)
        case int(Int64)
    }

    private static func bindAndStep(stmt: OpaquePointer?, bindings: [BindValue]) throws {
        for (i, binding) in bindings.enumerated() {
            let idx = Int32(i + 1)
            switch binding {
            case .blob(let data):
                data.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, idx, buf.baseAddress, Int32(buf.count),
                                     unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            case .text(let str):
                sqlite3_bind_text(stmt, idx, str, -1,
                                 unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .int(let val):
                sqlite3_bind_int64(stmt, idx, val)
            }
        }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw CASMigrationError.executeFailed("step returned \(rc)")
        }
        sqlite3_clear_bindings(stmt)
    }
}

public enum CASMigrationError: Error, LocalizedError {
    case prepareFailed(String)
    case executeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .prepareFailed(let msg): return "CAS migration prepare failed: \(msg)"
        case .executeFailed(let msg): return "CAS migration execute failed: \(msg)"
        }
    }
}

```
