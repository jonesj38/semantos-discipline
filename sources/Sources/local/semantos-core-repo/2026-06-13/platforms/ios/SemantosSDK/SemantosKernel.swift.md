---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDK/SemantosKernel.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.985722+00:00
---

# platforms/ios/SemantosSDK/SemantosKernel.swift

```swift
// SemantosKernel.swift — Swift wrapper for the Semantos C ABI
// Phase 30F: All C functions wrapped with safe memory management.
//
// Memory contract:
// - Input data is copied by the kernel; callers may free after call returns.
// - Output buffers use inout_len pattern: caller provides size, kernel fills and updates.
// - Kernel-allocated pointers (capability_present, anchor_batch) freed via semantos_free.
// - All pointer handling uses withUnsafeBytes / withUnsafeMutableBytes + defer.

import Foundation

public final class SemantosKernel {

    /// Whether this instance has called init (tracks Swift-side state).
    private var initialized = false

    public init() {}

    deinit {
        if initialized {
            shutdown()
        }
    }

    // MARK: - Lifecycle

    /// Initialize the kernel with a JSON configuration blob.
    /// Throws SemantosError if config is invalid or kernel already initialized.
    public func initialize(config: Data) throws {
        let result: Int32 = config.withUnsafeBytes { rawBuf in
            guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Int32(-2) // SEMANTOS_ERR_INVALID_JSON
            }
            return semantos_init(ptr, rawBuf.count)
        }
        try SemantosError.check(result)
        initialized = true
    }

    /// Initialize with default empty JSON config.
    public func initialize() throws {
        let emptyConfig = "{}".data(using: .utf8)!
        try initialize(config: emptyConfig)
    }

    /// Shut down the kernel and release all resources.
    public func shutdown() {
        _ = semantos_shutdown()
        initialized = false
    }

    // MARK: - Cell Operations

    /// Write data to a cell at the given path.
    public func cellWrite(path: String, data: Data) throws {
        let pathData = Array(path.utf8)
        let result: Int32 = data.withUnsafeBytes { dataBuf in
            guard let dataPtr = dataBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return pathData.withUnsafeBufferPointer { pathBuf in
                    semantos_cell_write(
                        pathBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: pathBuf.count) { $0 },
                        pathBuf.count,
                        nil,
                        0
                    )
                }
            }
            return pathData.withUnsafeBufferPointer { pathBuf in
                pathBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: pathBuf.count) { pathPtr in
                    semantos_cell_write(pathPtr, pathBuf.count, dataPtr, dataBuf.count)
                }
            }
        }
        try SemantosError.check(result)
    }

    /// Read data from a cell at the given path.
    /// Returns nil if the cell is not found. Throws on other errors.
    public func cellRead(path: String) throws -> Data? {
        let pathData = Array(path.utf8)
        var bufferSize: Int = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        let result: Int32 = pathData.withUnsafeBufferPointer { pathBuf in
            pathBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: pathBuf.count) { pathPtr in
                semantos_cell_read(pathPtr, pathBuf.count, &buffer, &bufferSize)
            }
        }

        if result == -1 { // SEMANTOS_ERR_NOT_FOUND
            return nil
        }

        // If buffer was too small, retry with the required size
        if result == -6 { // SEMANTOS_ERR_BUFFER_TOO_SMALL
            buffer = [UInt8](repeating: 0, count: bufferSize)
            let retryResult: Int32 = pathData.withUnsafeBufferPointer { pathBuf in
                pathBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: pathBuf.count) { pathPtr in
                    semantos_cell_read(pathPtr, pathBuf.count, &buffer, &bufferSize)
                }
            }
            try SemantosError.check(retryResult)
        } else {
            try SemantosError.check(result)
        }

        return Data(buffer[0..<bufferSize])
    }

    /// Verify a proof against the cell at the given path.
    /// The proof must contain the SHA-256 hash of the stored data in its first 32 bytes.
    public func cellVerify(path: String, proof: Data) throws {
        let pathData = Array(path.utf8)
        let result: Int32 = proof.withUnsafeBytes { proofBuf in
            guard let proofPtr = proofBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Int32(-7) // SEMANTOS_ERR_INVALID_PROOF
            }
            return pathData.withUnsafeBufferPointer { pathBuf in
                pathBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: pathBuf.count) { pathPtr in
                    semantos_cell_verify(pathPtr, pathBuf.count, proofPtr, proofBuf.count)
                }
            }
        }
        try SemantosError.check(result)
    }

    // MARK: - Capability Operations

    /// Check whether a certificate grants access to the specified domain.
    /// Requires host_identity_resolve callback to be registered.
    public func capabilityCheck(certId: Data, domainFlag: UInt32) throws {
        let result: Int32 = certId.withUnsafeBytes { certBuf in
            guard let certPtr = certBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Int32(-8) // SEMANTOS_ERR_DENIED
            }
            return semantos_capability_check(certPtr, certBuf.count, domainFlag)
        }
        try SemantosError.check(result)
    }

    /// Generate a BRC-108 capability token for the given certificate and domain.
    /// Returns the token bytes. Caller does not need to free (Swift manages via Data copy).
    public func capabilityPresent(certId: Data, domainFlag: UInt32) throws -> Data {
        var tokenPtr: UnsafeMutablePointer<UInt8>? = nil
        var tokenLen: Int = 0

        let result: Int32 = certId.withUnsafeBytes { certBuf in
            guard let certP = certBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Int32(-8)
            }
            return semantos_capability_present(certP, certBuf.count, domainFlag, &tokenPtr, &tokenLen)
        }
        try SemantosError.check(result)

        guard let ptr = tokenPtr, tokenLen > 0 else {
            throw SemantosError.unknown(-99)
        }

        // Copy kernel-allocated data into Swift-managed Data, then free kernel memory
        let data = Data(bytes: ptr, count: tokenLen)
        semantos_free(ptr, tokenLen)
        return data
    }

    // MARK: - Linearity Operations

    /// Consume a LINEAR cell exactly once.
    /// Throws alreadyConsumed if already consumed by this consumer,
    /// denied if the cell is not LINEAR.
    public func linearConsume(path: String, consumerCert: Data) throws {
        let pathData = Array(path.utf8)
        let result: Int32 = consumerCert.withUnsafeBytes { certBuf in
            guard let certPtr = certBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Int32(-8)
            }
            return pathData.withUnsafeBufferPointer { pathBuf in
                pathBuf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: pathBuf.count) { pathPtr in
                    semantos_linear_consume(pathPtr, pathBuf.count, certPtr, certBuf.count)
                }
            }
        }
        try SemantosError.check(result)
    }

    // MARK: - Anchor Operations

    /// Submit a batch of state hashes for anchoring.
    /// stateHashesJSON: JSON array of hex state hash strings.
    /// Returns serialized proof bytes.
    public func anchorBatch(stateHashesJSON: Data) throws -> Data {
        var proofsPtr: UnsafeMutablePointer<UInt8>? = nil
        var proofsLen: Int = 0

        let result: Int32 = stateHashesJSON.withUnsafeBytes { jsonBuf in
            guard let jsonPtr = jsonBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Int32(-2) // SEMANTOS_ERR_INVALID_JSON
            }
            return semantos_anchor_batch(jsonPtr, jsonBuf.count, &proofsPtr, &proofsLen)
        }
        try SemantosError.check(result)

        guard let ptr = proofsPtr, proofsLen > 0 else {
            throw SemantosError.unknown(-99)
        }

        let data = Data(bytes: ptr, count: proofsLen)
        semantos_free(ptr, proofsLen)
        return data
    }

    /// Verify an anchor proof offline using SPV validation.
    /// proof: JSON-encoded AnchorProof object bytes.
    public func anchorVerify(proof: Data) throws {
        let result: Int32 = proof.withUnsafeBytes { proofBuf in
            guard let proofPtr = proofBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Int32(-7) // SEMANTOS_ERR_INVALID_PROOF
            }
            return semantos_anchor_verify(proofPtr, proofBuf.count)
        }
        try SemantosError.check(result)
    }

    // MARK: - Metadata

    /// Return the kernel version string.
    public static var version: String {
        guard let cStr = semantos_version() else { return "unknown" }
        return String(cString: cStr)
    }

    /// Retrieve the last error message from the kernel.
    public static var lastError: String? {
        var bufferSize: Int = 256
        var buffer = [CChar](repeating: 0, count: bufferSize)
        let result = semantos_last_error(&buffer, &bufferSize)
        if result == 0 && bufferSize > 0 {
            return String(cString: buffer)
        }
        return nil
    }
}

```
