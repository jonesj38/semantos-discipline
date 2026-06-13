---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDKTests/SQLiteStorageProviderTests.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.983665+00:00
---

# platforms/ios/SemantosSDKTests/SQLiteStorageProviderTests.swift

```swift
// SQLiteStorageProviderTests.swift — Integration tests for SQLite storage adapter
// Phase 30F: Verify real SQLite persistence, round-trip, and concurrent access.

import XCTest
@testable import SemantosSDK

final class SQLiteStorageProviderTests: XCTestCase {

    private var provider: SQLiteStorageProvider!
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantos-test-\(UUID().uuidString)")
        provider = try SQLiteStorageProvider(directory: tempDir)
    }

    override func tearDownWithError() throws {
        provider = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Tests

    func testWriteAndReadCell() throws {
        let path = "/test/sqlite/cell"
        let data = "SQLite round-trip test".data(using: .utf8)!

        try provider.writeCell(path: path, data: data)
        let readBack = provider.readCell(path: path)

        XCTAssertNotNil(readBack)
        XCTAssertEqual(readBack, data, "SQLite round-trip must be byte-identical")
    }

    func testReadNonexistent() {
        let readBack = provider.readCell(path: "/does/not/exist")
        XCTAssertNil(readBack, "Reading nonexistent path should return nil")
    }

    func testOverwrite() throws {
        let path = "/test/sqlite/overwrite"
        try provider.writeCell(path: path, data: "v1".data(using: .utf8)!)
        try provider.writeCell(path: path, data: "v2".data(using: .utf8)!)

        let readBack = provider.readCell(path: path)
        XCTAssertEqual(readBack, "v2".data(using: .utf8)!)
    }

    func testBinaryData() throws {
        let path = "/test/sqlite/binary"
        var data = Data()
        for i: UInt8 in 0...255 { data.append(i) }

        try provider.writeCell(path: path, data: data)
        let readBack = provider.readCell(path: path)

        XCTAssertEqual(readBack, data, "Binary data with all byte values must round-trip")
    }

    func testLargeData() throws {
        let path = "/test/sqlite/large"
        let data = Data(repeating: 0x42, count: 100_000) // 100KB

        try provider.writeCell(path: path, data: data)
        let readBack = provider.readCell(path: path)

        XCTAssertNotNil(readBack)
        XCTAssertEqual(readBack!.count, 100_000)
        XCTAssertEqual(readBack, data)
    }

    func testStorageProviderProtocol() throws {
        let pathBytes = Array("/test/protocol".utf8)
        let dataBytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]

        // Write via protocol
        let writeResult = pathBytes.withUnsafeBufferPointer { pathBuf in
            dataBytes.withUnsafeBufferPointer { dataBuf in
                provider.write(path: pathBuf, data: dataBuf)
            }
        }
        XCTAssertEqual(writeResult, 0, "Protocol write should succeed")

        // Read via protocol
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

    func testConcurrentAccess() throws {
        let iterations = 50
        let expectation = XCTestExpectation(description: "Concurrent writes complete")
        expectation.expectedFulfillmentCount = iterations

        for i in 0..<iterations {
            DispatchQueue.global().async {
                let path = "/test/concurrent/\(i)"
                let data = "concurrent-\(i)".data(using: .utf8)!
                try? self.provider.writeCell(path: path, data: data)
                let readBack = self.provider.readCell(path: path)
                XCTAssertEqual(readBack, data, "Concurrent write/read \(i) should match")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10)
    }
}

```
