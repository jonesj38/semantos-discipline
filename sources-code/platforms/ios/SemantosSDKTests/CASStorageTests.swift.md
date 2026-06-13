---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDKTests/CASStorageTests.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.984246+00:00
---

# platforms/ios/SemantosSDKTests/CASStorageTests.swift

```swift
// CASStorageTests.swift — Integration tests for CAS storage layer
// Phase 30F.2: Tests verify real behavior — row counts, ordering, denial, independent proof verification.
//
// NO EASY TESTS: dedup counts rows, journal verifies ordering,
// linearity verifies denial, Merkle verifies proof independently.

import XCTest
import CryptoKit
@testable import SemantosSDK

final class CASStorageTests: XCTestCase {

    private var provider: SQLiteStorageProvider!
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantos-cas-test-\(UUID().uuidString)")
        provider = try SQLiteStorageProvider(directory: tempDir)
    }

    override func tearDownWithError() throws {
        provider = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - T1: Round-Trip via CAS

    func testCASRoundTrip() throws {
        let path = "/test/cas/round-trip"
        let data = "Hello, CAS!".data(using: .utf8)!

        try provider.writeCell(path: path, data: data)
        let readBack = provider.readCell(path: path)

        XCTAssertNotNil(readBack)
        XCTAssertEqual(readBack, data, "CAS round-trip must be byte-identical")
    }

    func testCASRoundTripBinary() throws {
        let path = "/test/cas/binary"
        var data = Data()
        for i: UInt8 in 0...255 { data.append(i) }

        try provider.writeCell(path: path, data: data)
        let readBack = provider.readCell(path: path)

        XCTAssertEqual(readBack, data, "Binary data with all byte values must round-trip")
    }

    // MARK: - T2: Deduplication (NO EASY TESTS)

    func testDeduplication() throws {
        let data = "dedup-test-data".data(using: .utf8)!
        let expectedHash = Data(SHA256.hash(data: data))

        try provider.writeCell(path: "/path/a", data: data)
        try provider.writeCell(path: "/path/b", data: data)

        // Verify: exactly ONE row in objects table for this hash
        let objectCount = countRows(table: "objects", whereClause: "hash = ?", blobParam: expectedHash)
        XCTAssertEqual(objectCount, 1, "Same data to two paths must produce exactly 1 object row")

        // Verify: exactly TWO rows in refs table pointing to this hash
        let refCount = countRows(table: "refs", whereClause: "hash = ?", blobParam: expectedHash)
        XCTAssertEqual(refCount, 2, "Two paths to same data must produce 2 ref rows")

        // Both paths read back identical data
        let readA = provider.readCell(path: "/path/a")
        let readB = provider.readCell(path: "/path/b")
        XCTAssertEqual(readA, data)
        XCTAssertEqual(readB, data)
    }

    // MARK: - T3: Journal Ordering (NO EASY TESTS)

    func testJournalOrdering() throws {
        for i in 0..<3 {
            try provider.writeCell(path: "/seq/\(i)", data: Data([UInt8(i)]))
        }

        let entries = try provider.journal.entriesBetween(fromSeq: 1, toSeq: Int64.max)
        XCTAssertEqual(entries.count, 3, "3 writes must produce 3 journal entries")

        // Verify strictly increasing sequence
        XCTAssertTrue(entries[0].seq < entries[1].seq, "Journal seq must be strictly increasing")
        XCTAssertTrue(entries[1].seq < entries[2].seq, "Journal seq must be strictly increasing")
    }

    // MARK: - T4: Journal History Chain

    func testJournalHistory() throws {
        let path = "/history/test"
        let data1 = "v1".data(using: .utf8)!
        let data2 = "v2".data(using: .utf8)!
        let data3 = "v3".data(using: .utf8)!

        try provider.writeCell(path: path, data: data1)
        try provider.writeCell(path: path, data: data2)
        try provider.writeCell(path: path, data: data3)

        let entries = try provider.journal.history(path: path)
        XCTAssertEqual(entries.count, 3, "3 overwrites must produce 3 journal entries for this path")

        // First write: old_hash is nil
        XCTAssertNil(entries[0].oldHash, "First write must have nil old_hash")

        // Subsequent writes: old_hash chains correctly
        let hash1 = Data(SHA256.hash(data: data1))
        let hash2 = Data(SHA256.hash(data: data2))

        XCTAssertEqual(entries[0].newHash, hash1)
        XCTAssertEqual(entries[1].oldHash, hash1, "Second write's old_hash must equal first write's new_hash")
        XCTAssertEqual(entries[1].newHash, hash2)
        XCTAssertEqual(entries[2].oldHash, hash2, "Third write's old_hash must equal second write's new_hash")
    }

    // MARK: - T5: Linearity Enforcement (NO EASY TESTS)

    func testLinearityEnforcement() throws {
        // Build a LINEAR cell with proper magic bytes and linearity=1
        let linearData = buildLinearCell()

        // Write LINEAR cell to path A
        try provider.writeCell(path: "/asset/original", data: linearData)

        // Verify it was registered as LINEAR
        let hash = Data(SHA256.hash(data: linearData))
        let typeClass = provider.linearityTracker.typeClass(for: hash)
        XCTAssertEqual(typeClass, .linear, "Cell with magic bytes and linearity=1 must be tracked as LINEAR")

        // Attempt to write same LINEAR data to path B — must fail
        XCTAssertThrowsError(try provider.writeCell(path: "/asset/copy", data: linearData)) { error in
            guard let sqliteError = error as? SQLiteStorageError else {
                XCTFail("Expected SQLiteStorageError, got \(error)")
                return
            }
            XCTAssertEqual(sqliteError, .linearityDenied,
                          "Writing LINEAR hash to second path must be denied")
        }
    }

    func testLinearConsumption() throws {
        let linearData = buildLinearCell()
        try provider.writeCell(path: "/asset/consumable", data: linearData)
        let hash = Data(SHA256.hash(data: linearData))

        // First consumption succeeds
        XCTAssertNoThrow(try provider.linearityTracker.consume(hash: hash, consumerPath: "/consumer/1"))

        // Second consumption fails
        XCTAssertThrowsError(try provider.linearityTracker.consume(hash: hash, consumerPath: "/consumer/2")) { error in
            guard let linError = error as? LinearityError else {
                XCTFail("Expected LinearityError, got \(error)")
                return
            }
            XCTAssertEqual(linError, .alreadyConsumed)
        }
    }

    // MARK: - T6: Linearity Default

    func testLinearityDefault() throws {
        // Non-cell data (no magic bytes) defaults to RELEVANT
        let plainData = "just text, no magic bytes".data(using: .utf8)!
        try provider.writeCell(path: "/text/file", data: plainData)

        let hash = Data(SHA256.hash(data: plainData))
        let typeClass = provider.linearityTracker.typeClass(for: hash)
        XCTAssertEqual(typeClass, .relevant, "Non-cell data must default to RELEVANT")

        // RELEVANT cells cannot be consumed
        XCTAssertThrowsError(try provider.linearityTracker.consume(hash: hash, consumerPath: "/consumer")) { error in
            guard let linError = error as? LinearityError else {
                XCTFail("Expected LinearityError")
                return
            }
            XCTAssertEqual(linError, .notLinear)
        }
    }

    // MARK: - T7: Merkle Proof (NO EASY TESTS)

    func testMerkleProofRoundTrip() throws {
        // Append 10 entries
        for i in 0..<10 {
            try provider.writeCell(path: "/merkle/\(i)", data: Data([UInt8(i)]))
        }

        let root = try provider.merkle.rootHash()
        XCTAssertEqual(root.count, 32, "Root hash must be 32 bytes")

        // Generate proof for entry at position 5
        let proof = try provider.merkle.proof(forPosition: 5)

        // Verify independently (static method, no database)
        XCTAssertTrue(
            JournalMerkle.verify(proof: proof, rootHash: root),
            "Valid Merkle proof must verify against root"
        )

        // Tamper with proof — verification must fail
        var tamperedProof = proof
        var tamperedLeaf = proof.leafHash
        tamperedLeaf[0] ^= 0xFF
        tamperedProof = MerkleProof(
            leafPosition: proof.leafPosition,
            leafHash: tamperedLeaf,
            siblings: proof.siblings
        )
        XCTAssertFalse(
            JournalMerkle.verify(proof: tamperedProof, rootHash: root),
            "Tampered proof must fail verification"
        )
    }

    func testMerkleRootChanges() throws {
        try provider.writeCell(path: "/mr/1", data: "a".data(using: .utf8)!)
        let root1 = try provider.merkle.rootHash()

        try provider.writeCell(path: "/mr/2", data: "b".data(using: .utf8)!)
        let root2 = try provider.merkle.rootHash()

        XCTAssertNotEqual(root1, root2, "Root must change with each journal entry")
    }

    // MARK: - T8: Integrity Detection (NO EASY TESTS)

    func testIntegrityDetection() throws {
        let data = "integrity-test".data(using: .utf8)!
        try provider.writeCell(path: "/integrity", data: data)

        // Corrupt the data in objects table directly
        let hash = Data(SHA256.hash(data: data))
        corruptObjectData(hash: hash)

        // Read must detect corruption and return nil
        let readBack = provider.readCell(path: "/integrity")
        XCTAssertNil(readBack, "Reading corrupted object must return nil (integrity error)")
    }

    func testIntegrityDetectionViaProtocol() throws {
        let data = "integrity-protocol".data(using: .utf8)!
        let pathBytes = Array("/integrity-proto".utf8)

        // Write via protocol
        let writeResult = pathBytes.withUnsafeBufferPointer { pathBuf in
            data.withUnsafeBytes { dataBuf in
                let dataBufPtr = UnsafeBufferPointer(
                    start: dataBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    count: dataBuf.count
                )
                return provider.write(path: pathBuf, data: dataBufPtr)
            }
        }
        XCTAssertEqual(writeResult, 0)

        // Corrupt the data
        let hash = Data(SHA256.hash(data: data))
        corruptObjectData(hash: hash)

        // Read via protocol must return -7 (SEMANTOS_ERR_INVALID_PROOF)
        var outBuffer = [UInt8](repeating: 0, count: 1024)
        let (readResult, _) = pathBytes.withUnsafeBufferPointer { pathBuf in
            outBuffer.withUnsafeMutableBufferPointer { outBuf in
                provider.read(path: pathBuf, into: outBuf)
            }
        }
        XCTAssertEqual(readResult, -7, "Integrity error must map to SEMANTOS_ERR_INVALID_PROOF (-7)")
    }

    // MARK: - T9: Migration from Flat Store

    func testMigration() throws {
        // Create a fresh database with the old flat schema directly
        let migrationDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantos-migration-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: migrationDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: migrationDir) }

        let dbPath = migrationDir.appendingPathComponent("semantos-cells.db").path

        // Open and create flat schema
        var flatDb: OpaquePointer?
        sqlite3_open_v2(dbPath, &flatDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        sqlite3_exec(flatDb, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(flatDb, """
            CREATE TABLE cells (
                path TEXT PRIMARY KEY NOT NULL,
                data BLOB NOT NULL,
                updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
            )
        """, nil, nil, nil)

        // Insert test data into flat table
        let testPaths = ["/flat/a", "/flat/b", "/flat/c"]
        let testData = ["alpha", "beta", "gamma"]
        for (path, text) in zip(testPaths, testData) {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(flatDb, "INSERT INTO cells (path, data) VALUES (?, ?)", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            let bytes = Array(text.utf8)
            bytes.withUnsafeBufferPointer { buf in
                sqlite3_bind_blob(stmt, 2, buf.baseAddress, Int32(buf.count),
                                 unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        sqlite3_close(flatDb)

        // Now open via SQLiteStorageProvider — migration should happen automatically
        let migratedProvider = try SQLiteStorageProvider(directory: migrationDir)

        // Verify: cells table is gone
        var checkStmt: OpaquePointer?
        sqlite3_prepare_v2(migratedProvider.dbHandle,
            "SELECT name FROM sqlite_master WHERE type='table' AND name='cells'",
            -1, &checkStmt, nil)
        let cellsTableExists = sqlite3_step(checkStmt) == SQLITE_ROW
        sqlite3_finalize(checkStmt)
        XCTAssertFalse(cellsTableExists, "Flat cells table must be dropped after migration")

        // Verify: all data preserved and readable
        for (path, text) in zip(testPaths, testData) {
            let readBack = migratedProvider.readCell(path: path)
            XCTAssertNotNil(readBack, "Path \(path) must survive migration")
            XCTAssertEqual(String(data: readBack!, encoding: .utf8), text,
                          "Data at \(path) must be preserved through migration")
        }

        // Verify: objects has correct rows (all 3 data values are different)
        var objCountStmt: OpaquePointer?
        sqlite3_prepare_v2(migratedProvider.dbHandle, "SELECT COUNT(*) FROM objects", -1, &objCountStmt, nil)
        sqlite3_step(objCountStmt)
        let objCount = sqlite3_column_int(objCountStmt, 0)
        sqlite3_finalize(objCountStmt)
        XCTAssertEqual(objCount, 3, "3 unique values must produce 3 object rows")

        // Verify: user_version is 1
        var versionStmt: OpaquePointer?
        sqlite3_prepare_v2(migratedProvider.dbHandle, "PRAGMA user_version", -1, &versionStmt, nil)
        sqlite3_step(versionStmt)
        let version = sqlite3_column_int(versionStmt, 0)
        sqlite3_finalize(versionStmt)
        XCTAssertEqual(version, 1, "Schema version must be 1 after migration")
    }

    // MARK: - T10: Concurrent Writes

    func testConcurrentWrites() throws {
        let iterations = 100
        let expectation = XCTestExpectation(description: "Concurrent CAS writes complete")
        expectation.expectedFulfillmentCount = iterations

        for i in 0..<iterations {
            DispatchQueue.global().async {
                let path = "/concurrent/\(i)"
                let data = Data([UInt8(i % 256)])
                try? self.provider.writeCell(path: path, data: data)
                let readBack = self.provider.readCell(path: path)
                XCTAssertEqual(readBack, data, "Concurrent write/read \(i) should match")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 30)

        // Verify all 100 cells readable
        for i in 0..<iterations {
            let readBack = provider.readCell(path: "/concurrent/\(i)")
            XCTAssertNotNil(readBack, "Cell \(i) must be readable after concurrent writes")
        }

        // Verify journal has entries for all writes
        let journalCount = provider.journal.count()
        XCTAssertGreaterThanOrEqual(journalCount, Int64(iterations),
            "Journal must have at least \(iterations) entries")
    }

    // MARK: - Existing Tests Must Still Pass (T10 from PRD)

    func testOverwrite() throws {
        let path = "/test/overwrite"
        try provider.writeCell(path: path, data: "v1".data(using: .utf8)!)
        try provider.writeCell(path: path, data: "v2".data(using: .utf8)!)

        let readBack = provider.readCell(path: path)
        XCTAssertEqual(readBack, "v2".data(using: .utf8)!)
    }

    func testReadNonexistent() {
        let readBack = provider.readCell(path: "/does/not/exist")
        XCTAssertNil(readBack, "Reading nonexistent path should return nil")
    }

    func testStorageProviderProtocol() throws {
        let pathBytes = Array("/test/protocol".utf8)
        let dataBytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]

        let writeResult = pathBytes.withUnsafeBufferPointer { pathBuf in
            dataBytes.withUnsafeBufferPointer { dataBuf in
                provider.write(path: pathBuf, data: dataBuf)
            }
        }
        XCTAssertEqual(writeResult, 0, "Protocol write should succeed")

        var outBuffer = [UInt8](repeating: 0, count: 256)
        let (readResult, readLen) = pathBytes.withUnsafeBufferPointer { pathBuf in
            outBuffer.withUnsafeMutableBufferPointer { outBuf in
                provider.read(path: pathBuf, into: outBuf)
            }
        }
        XCTAssertEqual(readResult, 0, "Protocol read should succeed")
        XCTAssertEqual(readLen, 4)
        XCTAssertEqual(Array(outBuffer[0..<4]), dataBytes, "Protocol read data must match write")
    }

    // MARK: - Helpers

    /// Build a cell with proper magic bytes and LINEAR type class.
    private func buildLinearCell() -> Data {
        var data = Data(count: 1024) // Standard cell size

        // Magic bytes (little-endian u32 each)
        data.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: UInt32(0xDEADBEEF).littleEndian, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: UInt32(0xCAFEBABE).littleEndian, toByteOffset: 4, as: UInt32.self)
            buf.storeBytes(of: UInt32(0x13371337).littleEndian, toByteOffset: 8, as: UInt32.self)
            buf.storeBytes(of: UInt32(0x42424242).littleEndian, toByteOffset: 12, as: UInt32.self)
            // Linearity = LINEAR (1) at offset 16
            buf.storeBytes(of: UInt32(1).littleEndian, toByteOffset: 16, as: UInt32.self)
        }

        return data
    }

    /// Count rows in a table with optional WHERE clause and BLOB parameter.
    private func countRows(table: String, whereClause: String? = nil, blobParam: Data? = nil) -> Int {
        var sql = "SELECT COUNT(*) FROM \(table)"
        if let w = whereClause { sql += " WHERE \(w)" }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(provider.dbHandle, sql, -1, &stmt, nil) == SQLITE_OK else {
            return -1
        }

        if let blob = blobParam {
            blob.withUnsafeBytes { buf in
                sqlite3_bind_blob(stmt, 1, buf.baseAddress, Int32(buf.count),
                                 unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Corrupt the data blob for a given hash in the objects table.
    private func corruptObjectData(hash: Data) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        sqlite3_prepare_v2(provider.dbHandle,
            "UPDATE objects SET data = X'DEADBEEF' WHERE hash = ?",
            -1, &stmt, nil)
        hash.withUnsafeBytes { buf in
            sqlite3_bind_blob(stmt, 1, buf.baseAddress, Int32(buf.count),
                             unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        sqlite3_step(stmt)
    }
}

// Make SQLiteStorageError Equatable for test assertions
extension SQLiteStorageError: Equatable {
    public static func == (lhs: SQLiteStorageError, rhs: SQLiteStorageError) -> Bool {
        switch (lhs, rhs) {
        case (.openFailed(let a), .openFailed(let b)): return a == b
        case (.prepareFailed(let a), .prepareFailed(let b)): return a == b
        case (.writeFailed(let a), .writeFailed(let b)): return a == b
        case (.executeFailed(let a), .executeFailed(let b)): return a == b
        case (.integrityError(let a1, let a2), .integrityError(let b1, let b2)): return a1 == b1 && a2 == b2
        case (.linearityDenied, .linearityDenied): return true
        default: return false
        }
    }
}

// Make LinearityError Equatable for test assertions
extension LinearityError: Equatable {
    public static func == (lhs: LinearityError, rhs: LinearityError) -> Bool {
        switch (lhs, rhs) {
        case (.notLinear, .notLinear): return true
        case (.alreadyConsumed, .alreadyConsumed): return true
        case (.operationFailed(let a), .operationFailed(let b)): return a == b
        default: return false
        }
    }
}

```
