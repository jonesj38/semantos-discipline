---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDKTests/SemantosKernelTests.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.983947+00:00
---

# platforms/ios/SemantosSDKTests/SemantosKernelTests.swift

```swift
// SemantosKernelTests.swift — XCTest integration tests for the Semantos kernel FFI
// Phase 30F: Tests verify behavior, not just compilation.
//
// These tests exercise the C ABI through the Swift bridging layer.
// They require the Semantos.xcframework to be linked.

import XCTest
@testable import SemantosSDK

final class SemantosKernelTests: XCTestCase {

    // MARK: - T1: Kernel Initialization

    func testKernelInitialization() throws {
        let kernel = SemantosKernel()
        XCTAssertNoThrow(try kernel.initialize())
        kernel.shutdown()
    }

    func testKernelDoubleInitFails() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        // Second init on the same thread-local state should fail
        let kernel2 = SemantosKernel()
        XCTAssertThrowsError(try kernel2.initialize()) { error in
            guard let semError = error as? SemantosError else {
                XCTFail("Expected SemantosError, got \(error)")
                return
            }
            XCTAssertEqual(semError, .alreadyInitialized(-4))
        }
    }

    func testKernelVersion() throws {
        let version = SemantosKernel.version
        XCTAssertFalse(version.isEmpty, "Version string should not be empty")
        XCTAssertTrue(version.contains("0.30"), "Version should contain 0.30, got: \(version)")
    }

    // MARK: - T2: Cell Round-Trip

    func testCellRoundTrip() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        let path = "/test/roundtrip"
        let data = "Hello, Semantos!".data(using: .utf8)!

        try kernel.cellWrite(path: path, data: data)
        let readBack = try kernel.cellRead(path: path)

        XCTAssertNotNil(readBack, "Cell read should return data")
        XCTAssertEqual(readBack, data, "Read data must be byte-identical to written data")
    }

    func testCellRoundTripBinaryData() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        let path = "/test/binary"
        // Binary data with null bytes and all byte values 0-255
        var data = Data()
        for i: UInt8 in 0...255 {
            data.append(i)
        }

        try kernel.cellWrite(path: path, data: data)
        let readBack = try kernel.cellRead(path: path)

        XCTAssertNotNil(readBack)
        XCTAssertEqual(readBack!.count, 256, "Should read back all 256 bytes")
        XCTAssertEqual(readBack, data, "Binary data round-trip must be byte-identical")
    }

    func testCellOverwrite() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        let path = "/test/overwrite"
        let data1 = "version1".data(using: .utf8)!
        let data2 = "version2-longer".data(using: .utf8)!

        try kernel.cellWrite(path: path, data: data1)
        try kernel.cellWrite(path: path, data: data2)
        let readBack = try kernel.cellRead(path: path)

        XCTAssertEqual(readBack, data2, "Overwritten cell should contain latest data")
    }

    func testCellReadNotFound() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        let readBack = try kernel.cellRead(path: "/nonexistent/path")
        XCTAssertNil(readBack, "Reading nonexistent cell should return nil")
    }

    // MARK: - T3: Cell Verification

    func testCellVerifyValidProof() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        let path = "/test/verify"
        let data = "verifiable data".data(using: .utf8)!
        try kernel.cellWrite(path: path, data: data)

        // Compute SHA-256 proof
        let hash = sha256(data)
        XCTAssertNoThrow(try kernel.cellVerify(path: path, proof: hash))
    }

    func testCellVerifyInvalidProof() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        let path = "/test/verify-bad"
        let data = "some data".data(using: .utf8)!
        try kernel.cellWrite(path: path, data: data)

        // Wrong hash
        let badProof = Data(repeating: 0xAB, count: 32)
        XCTAssertThrowsError(try kernel.cellVerify(path: path, proof: badProof)) { error in
            guard let semError = error as? SemantosError else {
                XCTFail("Expected SemantosError")
                return
            }
            XCTAssertEqual(semError, .invalidProof(-7))
        }
    }

    // MARK: - T4: Capability Check (without identity callback)

    func testCapabilityCheckWithoutCallback() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        let certId = "test-cert".data(using: .utf8)!
        XCTAssertThrowsError(try kernel.capabilityCheck(certId: certId, domainFlag: 1)) { error in
            // Should fail because no identity resolve callback is registered
            guard let semError = error as? SemantosError else {
                XCTFail("Expected SemantosError, got \(error)")
                return
            }
            // Either denied or callback not registered
            let validErrors: [SemantosError] = [.denied(-8), .callbackNotRegistered(-10)]
            XCTAssertTrue(validErrors.contains(semError),
                         "Expected denied or callback_not_registered, got \(semError)")
        }
    }

    // MARK: - T5: Linear Consume

    func testLinearConsumeNonLinearCell() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        // Write a regular cell (not marked LINEAR)
        let path = "/test/linear"
        let data = "not-linear".data(using: .utf8)!
        try kernel.cellWrite(path: path, data: data)

        let consumer = "consumer-001".data(using: .utf8)!
        XCTAssertThrowsError(try kernel.linearConsume(path: path, consumerCert: consumer)) { error in
            guard let semError = error as? SemantosError else {
                XCTFail("Expected SemantosError")
                return
            }
            // Regular cells should be denied for linear consumption
            XCTAssertEqual(semError, .denied(-8))
        }
    }

    // MARK: - T6: Anchor Verify (offline, no callback needed)

    func testAnchorVerifyInvalidProof() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        // Invalid JSON proof
        let badProof = "not valid json".data(using: .utf8)!
        XCTAssertThrowsError(try kernel.anchorVerify(proof: badProof)) { error in
            guard let semError = error as? SemantosError else {
                XCTFail("Expected SemantosError")
                return
            }
            XCTAssertEqual(semError, .invalidProof(-7))
        }
    }

    // MARK: - T7: Operations Before Init

    func testOperationsBeforeInitFail() throws {
        // Fresh kernel, never initialized
        let kernel = SemantosKernel()

        XCTAssertThrowsError(try kernel.cellWrite(path: "/x", data: Data([1]))) { error in
            guard let semError = error as? SemantosError else {
                XCTFail("Expected SemantosError")
                return
            }
            XCTAssertEqual(semError, .notInitialized(-5))
        }
    }

    // MARK: - T8: Memory Stress Test

    func testMemoryStress100Cycles() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        let path = "/test/stress"

        for i in 0..<100 {
            let data = "cycle-\(i)-\(String(repeating: "x", count: 100))".data(using: .utf8)!
            try kernel.cellWrite(path: path, data: data)
            let readBack = try kernel.cellRead(path: path)
            XCTAssertEqual(readBack, data, "Cycle \(i): round-trip mismatch")
        }
    }

    // MARK: - T9: Error Type Mapping

    func testErrorFromCodeMapping() {
        XCTAssertNil(SemantosError.from(code: 0), "Code 0 should map to nil (success)")
        XCTAssertEqual(SemantosError.from(code: -1), .notFound(-1))
        XCTAssertEqual(SemantosError.from(code: -2), .invalidJSON(-2))
        XCTAssertEqual(SemantosError.from(code: -3), .alreadyConsumed(-3))
        XCTAssertEqual(SemantosError.from(code: -4), .alreadyInitialized(-4))
        XCTAssertEqual(SemantosError.from(code: -5), .notInitialized(-5))
        XCTAssertEqual(SemantosError.from(code: -6), .bufferTooSmall(-6))
        XCTAssertEqual(SemantosError.from(code: -7), .invalidProof(-7))
        XCTAssertEqual(SemantosError.from(code: -8), .denied(-8))
        XCTAssertEqual(SemantosError.from(code: -9), .expired(-9))
        XCTAssertEqual(SemantosError.from(code: -10), .callbackNotRegistered(-10))
        XCTAssertEqual(SemantosError.from(code: -999), .unknown(-999))
    }

    // MARK: - T10: Callback Registration

    func testCallbackRegistration() throws {
        let kernel = SemantosKernel()
        try kernel.initialize()
        defer { kernel.shutdown() }

        // Register with all nil callbacks (valid — each is optional)
        let result = AdapterRegistry.registerWithKernel()
        XCTAssertEqual(result, 0, "Registration with nil callbacks should succeed")

        // Double registration should fail
        let result2 = AdapterRegistry.registerWithKernel()
        XCTAssertEqual(result2, -4, "Double registration should return ALREADY_INIT")
    }

    // MARK: - Helpers

    private func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            CC_SHA256(ptr, CC_LONG(buf.count), &hash)
        }
        return Data(hash)
    }
}

#if canImport(CommonCrypto)
import CommonCrypto
#endif

```
