---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDK/Callbacks.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.985442+00:00
---

# platforms/ios/SemantosSDK/Callbacks.swift

```swift
// Callbacks.swift — @convention(c) callback functions for host adapter dispatch
// Phase 30F: Swift bridging layer
//
// WHY @convention(c) ONLY:
// Swift closures capture context and have a different memory layout than C function
// pointers. The Zig kernel expects plain C function pointers (no context pointer,
// no Swift metadata). Only top-level functions or static methods marked @convention(c)
// produce compatible pointers. We dispatch to singleton adapter instances to get
// object-oriented behavior without violating the C calling convention.

import Foundation

// MARK: - Adapter Protocols

/// Provides persistent key-value storage for cells.
public protocol StorageProvider: AnyObject {
    func read(path: UnsafeBufferPointer<UInt8>, into buffer: UnsafeMutableBufferPointer<UInt8>) -> (Int32, Int)
    func write(path: UnsafeBufferPointer<UInt8>, data: UnsafeBufferPointer<UInt8>) -> Int32
}

/// Resolves and derives identity certificates.
public protocol IdentityProvider: AnyObject {
    func resolve(certId: UnsafeBufferPointer<UInt8>, into buffer: UnsafeMutableBufferPointer<UInt8>) -> (Int32, Int)
    func derive(parentCert: UnsafeBufferPointer<UInt8>, resourceId: UnsafeBufferPointer<UInt8>,
                domainFlag: UInt32, into buffer: UnsafeMutableBufferPointer<UInt8>) -> (Int32, Int)
}

/// Submits state hashes for blockchain anchoring.
public protocol AnchorProvider: AnyObject {
    func submit(stateHash: UnsafeBufferPointer<UInt8>, metadata: UnsafeBufferPointer<UInt8>,
                into buffer: UnsafeMutableBufferPointer<UInt8>) -> (Int32, Int)
}

/// Publishes objects and resolves queries over the network.
public protocol NetworkProvider: AnyObject {
    func publish(objectJSON: UnsafeBufferPointer<UInt8>) -> Int32
    func resolve(queryJSON: UnsafeBufferPointer<UInt8>, into buffer: UnsafeMutableBufferPointer<UInt8>) -> (Int32, Int)
}

// MARK: - Singleton Adapter Registry

/// Central registry holding singleton adapter instances.
/// Set these before calling semantos_register_callbacks.
public enum AdapterRegistry {
    public static var storage: StorageProvider?
    public static var identity: IdentityProvider?
    public static var anchor: AnchorProvider?
    public static var network: NetworkProvider?

    /// Register all non-nil adapters with the kernel.
    /// Call after setting the adapter properties and after semantos_init.
    public static func registerWithKernel() -> Int32 {
        return semantos_register_callbacks(
            storage != nil ? hostStorageRead : nil,
            storage != nil ? hostStorageWrite : nil,
            identity != nil ? hostIdentityResolve : nil,
            identity != nil ? hostIdentityDerive : nil,
            anchor != nil ? hostAnchorSubmit : nil,
            network != nil ? hostNetworkPublish : nil,
            network != nil ? hostNetworkResolve : nil
        )
    }
}

// MARK: - @convention(c) Callback Trampolines

// Each function is a top-level @convention(c) function that dispatches to the
// corresponding singleton adapter. This is the ONLY way to produce C-compatible
// function pointers from Swift.

private let hostStorageRead: @convention(c) (
    UnsafePointer<UInt8>, Int, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<Int>
) -> Int32 = { pathPtr, pathLen, outData, inoutLen in
    guard let provider = AdapterRegistry.storage else { return -10 }
    let path = UnsafeBufferPointer(start: pathPtr, count: pathLen)
    let buffer = UnsafeMutableBufferPointer(start: outData, count: inoutLen.pointee)
    let (result, bytesWritten) = provider.read(path: path, into: buffer)
    if result == 0 {
        inoutLen.pointee = bytesWritten
    }
    return result
}

private let hostStorageWrite: @convention(c) (
    UnsafePointer<UInt8>, Int, UnsafePointer<UInt8>, Int
) -> Int32 = { pathPtr, pathLen, dataPtr, dataLen in
    guard let provider = AdapterRegistry.storage else { return -10 }
    let path = UnsafeBufferPointer(start: pathPtr, count: pathLen)
    let data = UnsafeBufferPointer(start: dataPtr, count: dataLen)
    return provider.write(path: path, data: data)
}

private let hostIdentityResolve: @convention(c) (
    UnsafePointer<UInt8>, Int, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<Int>
) -> Int32 = { certPtr, certLen, outJSON, inoutLen in
    guard let provider = AdapterRegistry.identity else { return -10 }
    let certId = UnsafeBufferPointer(start: certPtr, count: certLen)
    let buffer = UnsafeMutableBufferPointer(start: outJSON, count: inoutLen.pointee)
    let (result, bytesWritten) = provider.resolve(certId: certId, into: buffer)
    if result == 0 {
        inoutLen.pointee = bytesWritten
    }
    return result
}

private let hostIdentityDerive: @convention(c) (
    UnsafePointer<UInt8>, Int, UnsafePointer<UInt8>, Int, UInt32, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<Int>
) -> Int32 = { parentPtr, certLen, ridPtr, ridLen, domainFlag, outJSON, inoutLen in
    guard let provider = AdapterRegistry.identity else { return -10 }
    let parent = UnsafeBufferPointer(start: parentPtr, count: certLen)
    let rid = UnsafeBufferPointer(start: ridPtr, count: ridLen)
    let buffer = UnsafeMutableBufferPointer(start: outJSON, count: inoutLen.pointee)
    let (result, bytesWritten) = provider.derive(parentCert: parent, resourceId: rid,
                                                  domainFlag: domainFlag, into: buffer)
    if result == 0 {
        inoutLen.pointee = bytesWritten
    }
    return result
}

private let hostAnchorSubmit: @convention(c) (
    UnsafePointer<UInt8>, Int, UnsafePointer<UInt8>, Int, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<Int>
) -> Int32 = { hashPtr, hashLen, metaPtr, metaLen, outProof, inoutLen in
    guard let provider = AdapterRegistry.anchor else { return -10 }
    let stateHash = UnsafeBufferPointer(start: hashPtr, count: hashLen)
    let metadata = UnsafeBufferPointer(start: metaPtr, count: metaLen)
    let buffer = UnsafeMutableBufferPointer(start: outProof, count: inoutLen.pointee)
    let (result, bytesWritten) = provider.submit(stateHash: stateHash, metadata: metadata, into: buffer)
    if result == 0 {
        inoutLen.pointee = bytesWritten
    }
    return result
}

private let hostNetworkPublish: @convention(c) (
    UnsafePointer<UInt8>, Int
) -> Int32 = { jsonPtr, jsonLen in
    guard let provider = AdapterRegistry.network else { return -10 }
    let json = UnsafeBufferPointer(start: jsonPtr, count: jsonLen)
    return provider.publish(objectJSON: json)
}

private let hostNetworkResolve: @convention(c) (
    UnsafePointer<UInt8>, Int, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<Int>
) -> Int32 = { queryPtr, queryLen, outResults, inoutLen in
    guard let provider = AdapterRegistry.network else { return -10 }
    let query = UnsafeBufferPointer(start: queryPtr, count: queryLen)
    let buffer = UnsafeMutableBufferPointer(start: outResults, count: inoutLen.pointee)
    let (result, bytesWritten) = provider.resolve(queryJSON: query, into: buffer)
    if result == 0 {
        inoutLen.pointee = bytesWritten
    }
    return result
}

```
