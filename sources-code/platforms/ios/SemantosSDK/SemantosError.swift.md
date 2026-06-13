---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDK/SemantosError.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.985166+00:00
---

# platforms/ios/SemantosSDK/SemantosError.swift

```swift
// SemantosError.swift — Error types mapped from semantos.h error codes
// Phase 30F: Swift bridging layer

import Foundation

/// Maps 1:1 to the SemantosResult error codes defined in semantos.h.
/// Each case carries the raw Int32 code from the C ABI for debugging.
public enum SemantosError: Error, Equatable {
    case notFound(Int32)
    case invalidJSON(Int32)
    case alreadyConsumed(Int32)
    case alreadyInitialized(Int32)
    case notInitialized(Int32)
    case bufferTooSmall(Int32)
    case invalidProof(Int32)
    case denied(Int32)
    case expired(Int32)
    case callbackNotRegistered(Int32)
    case unknown(Int32)

    /// Create from a raw C ABI result code. Returns nil for SEMANTOS_OK (0).
    static func from(code: Int32) -> SemantosError? {
        switch code {
        case 0:     return nil  // SEMANTOS_OK
        case -1:    return .notFound(code)
        case -2:    return .invalidJSON(code)
        case -3:    return .alreadyConsumed(code)
        case -4:    return .alreadyInitialized(code)
        case -5:    return .notInitialized(code)
        case -6:    return .bufferTooSmall(code)
        case -7:    return .invalidProof(code)
        case -8:    return .denied(code)
        case -9:    return .expired(code)
        case -10:   return .callbackNotRegistered(code)
        default:    return .unknown(code)
        }
    }

    /// Throw if the result code is non-zero.
    static func check(_ code: Int32) throws {
        if let error = from(code: code) {
            throw error
        }
    }
}

extension SemantosError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound:              return "Cell not found"
        case .invalidJSON:           return "Invalid JSON configuration"
        case .alreadyConsumed:       return "Linear cell already consumed"
        case .alreadyInitialized:    return "Kernel already initialized"
        case .notInitialized:        return "Kernel not initialized"
        case .bufferTooSmall:        return "Output buffer too small"
        case .invalidProof:          return "Invalid proof"
        case .denied:                return "Access denied"
        case .expired:               return "Certificate expired"
        case .callbackNotRegistered: return "Required callback not registered"
        case .unknown(let code):     return "Unknown kernel error (\(code))"
        }
    }
}

```
