---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDK/Storage/LinearityTracker.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.987607+00:00
---

# platforms/ios/SemantosSDK/Storage/LinearityTracker.swift

```swift
// LinearityTracker.swift — Per-hash linearity enforcement for CAS
// Phase 30F.2: Linearity is per content hash, not per path.
//
// A LINEAR cell (identified by its content hash) can only be referenced
// by one path at a time. The hash is the asset; the path is a handle.
//
// Type class is parsed from the cell header:
//   - Magic: 0xDEADBEEF 0xCAFEBABE 0x13371337 0x42424242 (16 bytes)
//   - Linearity: u32 little-endian at offset 16
//   - Values: LINEAR=1, AFFINE=2, RELEVANT=3, DEBUG=4

import Foundation
import SQLite3

/// Cell type class matching packages/constants/constants.json
public enum CellTypeClass: Int {
    case linear   = 1
    case affine   = 2
    case relevant = 3
    case debug    = 4

    /// Parse type class from cell data by checking magic bytes and linearity field.
    /// Returns .relevant for non-cell data (no magic bytes) or unknown values.
    public static func parse(from data: Data) -> CellTypeClass {
        // Need at least 20 bytes: 16 magic + 4 linearity
        guard data.count >= 20 else { return .relevant }

        // Check magic bytes: 0xDEADBEEF at offset 0 (little-endian)
        let magic1 = data.withUnsafeBytes { buf -> UInt32 in
            buf.load(fromByteOffset: 0, as: UInt32.self)
        }
        guard magic1 == 0xDEADBEEF else { return .relevant }

        // Read linearity u32 at offset 16 (little-endian)
        let linearityRaw = data.withUnsafeBytes { buf -> UInt32 in
            buf.load(fromByteOffset: 16, as: UInt32.self)
        }

        return CellTypeClass(rawValue: Int(linearityRaw)) ?? .relevant
    }
}

/// Tracks linearity state per content hash.
public final class LinearityTracker {

    private let db: OpaquePointer?

    init(db: OpaquePointer?) {
        self.db = db
    }

    /// Register a new object's type class. Idempotent — duplicate hashes keep original.
    func register(hash: Data, typeClass: CellTypeClass) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "INSERT OR IGNORE INTO linearity (hash, type_class) VALUES (?, ?)",
            -1, &stmt, nil) == SQLITE_OK else {
            throw LinearityError.operationFailed(lastError)
        }
        bindBlob(stmt, index: 1, data: hash)
        sqlite3_bind_int(stmt, 2, Int32(typeClass.rawValue))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw LinearityError.operationFailed(lastError)
        }
    }

    /// Check if a hash can be referenced at a new path.
    /// Returns true if allowed, false if the hash is LINEAR and already referenced or consumed.
    func canReference(hash: Data) throws -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "SELECT type_class, consumed FROM linearity WHERE hash = ?",
            -1, &stmt, nil) == SQLITE_OK else {
            return true // unknown hash — allow (RELEVANT by default)
        }
        bindBlob(stmt, index: 1, data: hash)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return true // not tracked — allow
        }

        let typeClassRaw = Int(sqlite3_column_int(stmt, 0))
        let consumed = sqlite3_column_int(stmt, 1)

        // Already consumed — disallow
        if consumed != 0 { return false }

        // LINEAR hash: check if already referenced elsewhere
        if typeClassRaw == CellTypeClass.linear.rawValue {
            let refCount = countRefs(hash: hash)
            if refCount > 0 { return false }
        }

        return true
    }

    /// Consume a LINEAR cell. Atomically marks it consumed.
    /// Returns true on success, throws if not LINEAR or already consumed.
    @discardableResult
    func consume(hash: Data, consumerPath: String) throws -> Bool {
        // Check current state
        var checkStmt: OpaquePointer?
        defer { sqlite3_finalize(checkStmt) }

        guard sqlite3_prepare_v2(db,
            "SELECT type_class, consumed FROM linearity WHERE hash = ?",
            -1, &checkStmt, nil) == SQLITE_OK else {
            throw LinearityError.operationFailed(lastError)
        }
        bindBlob(checkStmt, index: 1, data: hash)

        guard sqlite3_step(checkStmt) == SQLITE_ROW else {
            throw LinearityError.notLinear // untracked hash
        }

        let typeClassRaw = Int(sqlite3_column_int(checkStmt, 0))
        let consumed = sqlite3_column_int(checkStmt, 1)

        guard typeClassRaw == CellTypeClass.linear.rawValue else {
            throw LinearityError.notLinear
        }

        if consumed != 0 {
            throw LinearityError.alreadyConsumed
        }

        // Atomically mark consumed
        var updateStmt: OpaquePointer?
        defer { sqlite3_finalize(updateStmt) }

        guard sqlite3_prepare_v2(db, """
            UPDATE linearity SET consumed = 1, consumed_at = strftime('%s','now'), consumer_path = ?
            WHERE hash = ? AND consumed = 0 AND type_class = ?
            """, -1, &updateStmt, nil) == SQLITE_OK else {
            throw LinearityError.operationFailed(lastError)
        }
        sqlite3_bind_text(updateStmt, 1, consumerPath, -1,
                         unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        bindBlob(updateStmt, index: 2, data: hash)
        sqlite3_bind_int(updateStmt, 3, Int32(CellTypeClass.linear.rawValue))

        guard sqlite3_step(updateStmt) == SQLITE_DONE else {
            throw LinearityError.operationFailed(lastError)
        }

        let affected = sqlite3_changes(db)
        if affected == 0 {
            throw LinearityError.alreadyConsumed
        }
        return true
    }

    /// Get the type class for a hash. Returns nil if not tracked.
    func typeClass(for hash: Data) -> CellTypeClass? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "SELECT type_class FROM linearity WHERE hash = ?",
            -1, &stmt, nil) == SQLITE_OK else { return nil }
        bindBlob(stmt, index: 1, data: hash)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return CellTypeClass(rawValue: Int(sqlite3_column_int(stmt, 0)))
    }

    // MARK: - Internal

    private func countRefs(hash: Data) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db,
            "SELECT COUNT(*) FROM refs WHERE hash = ?",
            -1, &stmt, nil) == SQLITE_OK else { return 0 }
        bindBlob(stmt, index: 1, data: hash)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
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

public enum LinearityError: Error, LocalizedError {
    case notLinear
    case alreadyConsumed
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notLinear: return "Cell is not LINEAR"
        case .alreadyConsumed: return "LINEAR cell already consumed"
        case .operationFailed(let msg): return "Linearity operation failed: \(msg)"
        }
    }
}

```
