---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.988243+00:00
---

# platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift

```swift
// SQLiteStorageProvider.swift — Persistent cell storage backed by SQLite3
// Phase 30F: Real SQLite implementation using Apple's built-in libsqlite3.
//
// Uses WAL mode for concurrent read access. Database lives in the app's
// Application Support directory for persistence across launches.

import Foundation
import SQLite3

public final class SQLiteStorageProvider: StorageProvider {

    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.semantos.storage", qos: .userInitiated)

    public init(directory: URL? = nil) throws {
        let dir = directory ?? SQLiteStorageProvider.defaultDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dbPath = dir.appendingPathComponent("semantos-cells.db").path

        var dbHandle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(dbPath, &dbHandle, flags, nil)
        guard rc == SQLITE_OK, let handle = dbHandle else {
            let msg = dbHandle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(dbHandle)
            throw SQLiteStorageError.openFailed(msg)
        }
        self.db = handle

        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("""
            CREATE TABLE IF NOT EXISTS cells (
                path TEXT PRIMARY KEY NOT NULL,
                data BLOB NOT NULL,
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
            )
        """)
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - StorageProvider Protocol

    public func read(path: UnsafeBufferPointer<UInt8>,
                     into buffer: UnsafeMutableBufferPointer<UInt8>) -> (Int32, Int) {
        let pathStr = String(bytes: path, encoding: .utf8) ?? ""
        guard !pathStr.isEmpty else { return (-1, 0) }

        var result: (Int32, Int) = (-1, 0)
        queue.sync {
            result = self.readSync(path: pathStr, into: buffer)
        }
        return result
    }

    public func write(path: UnsafeBufferPointer<UInt8>,
                      data: UnsafeBufferPointer<UInt8>) -> Int32 {
        let pathStr = String(bytes: path, encoding: .utf8) ?? ""
        guard !pathStr.isEmpty else { return -2 }

        var result: Int32 = -2
        queue.sync {
            result = self.writeSync(path: pathStr, data: Array(data))
        }
        return result
    }

    // MARK: - Public Convenience API

    /// Read cell data by path string. Returns nil if not found.
    public func readCell(path: String) -> Data? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "SELECT data FROM cells WHERE path = ?", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_bind_text(stmt, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let blobPtr = sqlite3_column_blob(stmt, 0)
        let blobLen = sqlite3_column_bytes(stmt, 0)
        guard let ptr = blobPtr, blobLen > 0 else { return Data() }
        return Data(bytes: ptr, count: Int(blobLen))
    }

    /// Write cell data by path string.
    public func writeCell(path: String, data: Data) throws {
        try data.withUnsafeBytes { rawBuf in
            guard let ptr = rawBuf.baseAddress else {
                try execute("INSERT OR REPLACE INTO cells (path, data) VALUES (?, zeroblob(0))",
                           bindings: [.text(path)])
                return
            }
            let sql = "INSERT OR REPLACE INTO cells (path, data, updated_at) VALUES (?, ?, strftime('%s','now'))"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SQLiteStorageError.prepareFailed(lastErrorMessage)
            }
            sqlite3_bind_text(stmt, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_blob(stmt, 2, ptr, Int32(rawBuf.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SQLiteStorageError.writeFailed(lastErrorMessage)
            }
        }
    }

    // MARK: - Internals

    private func readSync(path: String,
                          into buffer: UnsafeMutableBufferPointer<UInt8>) -> (Int32, Int) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "SELECT data FROM cells WHERE path = ?", -1, &stmt, nil) == SQLITE_OK else {
            return (-1, 0)
        }
        sqlite3_bind_text(stmt, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return (-1, 0) // SEMANTOS_ERR_NOT_FOUND
        }

        let blobPtr = sqlite3_column_blob(stmt, 0)
        let blobLen = Int(sqlite3_column_bytes(stmt, 0))

        guard blobLen <= buffer.count else {
            return (-6, blobLen) // SEMANTOS_ERR_BUFFER_TOO_SMALL
        }

        if let src = blobPtr, blobLen > 0 {
            buffer.baseAddress!.initialize(from: src.assumingMemoryBound(to: UInt8.self), count: blobLen)
        }
        return (0, blobLen)
    }

    private func writeSync(path: String, data: [UInt8]) -> Int32 {
        let sql = "INSERT OR REPLACE INTO cells (path, data, updated_at) VALUES (?, ?, strftime('%s','now'))"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -2 }

        sqlite3_bind_text(stmt, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        data.withUnsafeBufferPointer { buf in
            sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(buf.count),
                             unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        return sqlite3_step(stmt) == SQLITE_DONE ? 0 : -2
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(lastErrorMessage)
        }
        for (i, binding) in bindings.enumerated() {
            switch binding {
            case .text(let str):
                sqlite3_bind_text(stmt, Int32(i + 1), str, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE || sqlite3_step(stmt) == SQLITE_ROW else {
            throw SQLiteStorageError.executeFailed(lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }

    private static func defaultDirectory() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Semantos")
    }

    private enum SQLiteBinding {
        case text(String)
    }
}

public enum SQLiteStorageError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case writeFailed(String)
    case executeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg):    return "SQLite open failed: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        case .writeFailed(let msg):   return "SQLite write failed: \(msg)"
        case .executeFailed(let msg): return "SQLite execute failed: \(msg)"
        }
    }
}

```
