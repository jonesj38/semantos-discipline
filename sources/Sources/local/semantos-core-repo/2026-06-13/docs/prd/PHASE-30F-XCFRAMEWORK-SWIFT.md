---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30F-XCFRAMEWORK-SWIFT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.695754+00:00
---

# Phase 30F — XCFramework Packaging & Swift Demo App

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 30D complete (all core C ABI functions)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30f-xcframework-swift`

---

## Context

Swift has native C interop. The Zig-compiled .a file links directly into Xcode via a bridging header. This phase packages all iOS architecture slices (arm64 device, arm64 simulator, x86_64 simulator) into an XCFramework and creates a Swift demo app that exercises the full FFI surface.

### The Boundary Rule

Swift calls C functions directly. Callbacks from kernel to host use `@convention(c)` top-level Swift functions that dispatch to singleton adapter instances (Swift closures cannot be passed as C function pointers). The XCFramework bundles all architecture slices so Xcode resolves the correct one automatically.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | iOS integration details, Swift adapter table |
| `PHASE-30A` | `docs/prd/PHASE-30A-C-ABI-HEADER.md` | semantos.h, error codes |
| `PHASE-30B` | `docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md` | Callback signatures |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming |

---

## Deliverables

### D30F.1 — Cross-compilation build scripts

New file: `scripts/build-ios.sh`

Builds .a files for all iOS targets: aarch64-ios, aarch64-ios-simulator, x86_64-ios-simulator. Uses `zig build` with appropriate target triples and ReleaseSafe.

**Acceptance criteria**:
- Script builds .a for `aarch64-ios` (device)
- Script builds .a for `aarch64-ios-simulator` (ARM64 sim)
- Script builds .a for `x86_64-ios-simulator` (Intel sim)
- All three .a files are valid and under 10MB each
- Script is idempotent (can run multiple times safely)
- Output directory clearly labeled with architecture

### D30F.2 — XCFramework creation

In `scripts/build-ios.sh`:

Uses `xcodebuild -create-xcframework` to bundle all .a slices + headers into `Semantos.xcframework`.

**Acceptance criteria**:
- `xcodebuild -create-xcframework` command runs without error
- Output `Semantos.xcframework` is a valid Xcode framework
- Framework contains all three architecture slices
- Framework header includes `semantos.h` (bridging header for Swift)
- `xcodebuild` validation passes (`xcodebuild -validateInputFile` or import test)

### D30F.3 — Swift bridging layer

New directory: `platforms/ios/SemantosSDK/`

Three files:
- `SemantosKernel.swift`: Swift class wrapping C functions with idiomatic Swift API. Handles UnsafeMutablePointer management, String ↔ UnsafeBufferPointer conversion, and memory cleanup via defer blocks.
- `SemantosError.swift`: Swift enum mapping SemantosResult error codes
- `Callbacks.swift`: `@convention(c)` callback functions for all 4 adapters

**Acceptance criteria**:
- `SemantosKernel` class initializes, shuts down, and survives deinit without crash
- `cellWrite(path: String, data: Data)` accepts UTF-8 string and Data, calls C function
- `cellRead(path: String) -> Data?` returns Data with identical bytes as written
- `capabilityCheck(certId: Data, domainFlag: UInt32)` calls C function and returns result
- `SemantosError` enum covers all error codes from semantos.h
- `@convention(c)` callbacks (storage_read, identity_resolve, etc.) are callable from C

### D30F.4 — Host adapter implementations (Swift)

New directory: `platforms/ios/SemantosSDK/Adapters/`

Four files:
- `SQLiteStorageProvider.swift`: Local SQLite via GRDB, WAL mode, Application Support directory
- `KeychainIdentityProvider.swift`: Secure Enclave key generation (kSecAttrTokenIDSecureEnclave), cert chain in Keychain, biometric gate for admin domain flags
- `HttpAnchorProvider.swift`: URLSession-based, batches when offline, queues in SQLite
- `HttpNetworkProvider.swift`: REST to relay node (V1)

**Acceptance criteria**:
- SQLiteStorageProvider persists cell data to device SQLite database
- KeychainIdentityProvider generates keys in Secure Enclave (device test only)
- Keychain stores certificates and retrieves them
- HttpAnchorProvider batches state hashes before submitting
- HttpNetworkProvider makes REST calls to configurable endpoint
- All adapters implement corresponding adapter protocol/interface
- Memory: no retained references to kernel after shutdown

### D30F.5 — Swift demo app

New directory: `platforms/ios/SemantosDemo/`

Minimal SwiftUI app that:
- Initializes kernel
- Writes a cell
- Reads it back
- Displays result
- Exercises capability check and LINEAR consume
- Demonstrates Secure Enclave key storage

**Acceptance criteria**:
- App builds in Xcode with no errors or warnings
- App runs on iOS Simulator (arm64 or x86_64)
- Cell write → read displays identical data on screen
- Capability check button shows success/failure
- Demonstrates Secure Enclave access (or mock on simulator)
- UI is responsive, no ANRs (app not responding)

### D30F.6 — Swift integration tests

New directory: `platforms/ios/SemantosSDKTests/`

XCTest suite that covers:
- Kernel initialization and shutdown
- Cell round-trip via Swift wrapper
- Callback registration and invocation
- Error mapping (SemantosResult → SemantosError)
- Memory leak detection (no orphaned kernel allocations)

**Acceptance criteria**:
- XCTest suite runs in Xcode with `Cmd+U`
- All tests pass
- Instruments (Xcode memory profiler) shows no leaked allocations
- Tests cover both happy path and error cases

---

## TDD Gate Tests

- **T1**: `scripts/build-ios.sh` produces .a files for all 3 architectures (aarch64-ios, aarch64-ios-simulator, x86_64-ios-simulator)
- **T2**: XCFramework bundles all slices and is valid (xcodebuild validates)
- **T3**: Swift wrapper initializes kernel and returns version string
- **T4**: Cell write/read round-trip works through Swift wrapper
- **T5**: `@convention(c)` callbacks receive correct arguments from kernel
- **T6**: SemantosError enum covers all error codes
- **T7**: Demo app builds and runs in Simulator
- **T8**: KeychainIdentityProvider accesses Secure Enclave (device test)
- **T9**: Memory: no leaked kernel allocations after 100 write/read cycles

---

## Completion Criteria

1. All 6 deliverables (D30F.1–D30F.6) complete and merged to `phase-30f-xcframework-swift`
2. All 9 TDD Gate Tests pass
3. XCTest suite passes with no failures
4. Demo app builds and runs on iOS Simulator
5. Device test: Secure Enclave key access verified on physical device
6. Xcode no warnings about deprecated APIs or unsafe pointer usage
7. Documentation: iOS integration guide in README or docs/iOS.md
8. CI/CD: Build pipeline validates XCFramework creation on every commit

---

## Notes

- XCFramework is the modern replacement for fat binaries; it handles architecture selection automatically
- `@convention(c)` functions must be top-level (not instance methods) to be callable from C
- Swift closures cannot be passed as C function pointers; use global functions with state stored in singletons
- Secure Enclave is device-only; simulator falls back to software keychain
- GRDB is a popular SQLite wrapper for Swift; alternative is Realm or SQLite.swift
