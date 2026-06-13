---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30F-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.668334+00:00
---

# Phase 30F Execution Prompt — XCFramework Packaging & Swift Demo App

> Paste this prompt into a fresh session to execute Phase 30F.

## Context

Swift has native C interop. The Zig-compiled .a file links directly into Xcode via a bridging header. This phase packages all iOS architecture slices (arm64 device, arm64 simulator, x86_64 simulator) into an XCFramework and creates a Swift demo app that exercises the full FFI surface.

### The Boundary Rule

Swift calls C functions directly. Callbacks from kernel to host use `@convention(c)` top-level Swift functions that dispatch to singleton adapter instances (Swift closures cannot be passed as C function pointers). The XCFramework bundles all architecture slices so Xcode resolves the correct one automatically.

---

## CRITICAL: READ THESE FILES FIRST

1. `docs/prd/PHASE-30-FFI-MASTER.md` — iOS integration details, Swift adapter table, rationale
2. `docs/prd/PHASE-30A-C-ABI-HEADER.md` — semantos.h, all function signatures, error codes
3. `docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md` — Callback signatures (host_storage_read, etc.)
4. `docs/BRANCHING-AND-CI-POLICY.md` — Commit naming convention
5. `build.zig` — Current build configuration

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

1. **NO STUBS**: Every Swift adapter does real work. No placeholder implementations. SQLiteStorageProvider must use real SQLite, KeychainIdentityProvider must access real Keychain/Secure Enclave, HttpAnchorProvider must make real HTTP calls.
2. **SECURE ENCLAVE IS MANDATORY**: KeychainIdentityProvider must use `kSecAttrTokenIDSecureEnclave` on device. On simulator, fall back to software Keychain but document the fallback.
3. **MEMORY MANAGEMENT IS EXPLICIT**: Every kernel allocation freed via defer blocks. Use `withUnsafeBytes`, `withUnsafeMutableBufferPointer`, and `defer` to guarantee cleanup.
4. **XCFRAMEWORK MUST BE VALID**: `xcodebuild -create-xcframework` must complete without error. The framework must be importable in a test Xcode project.
5. **DEMO APP MUST RUN**: Not just compile. The app must launch, write a cell, read it back, and display the result. Exercise all paths: capability check, LINEAR consume, Secure Enclave.
6. **NO EASY TESTS**: Tests must verify behavior. Cell write → read must return identical bytes. Callbacks must receive correct arguments with correct data.
7. **@CONVENTION(C) ONLY**: No closures as callbacks. Callbacks are global @convention(c) functions that dispatch to singleton instances. Document why in code.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
git status
git log --oneline -10
git branch -a
```

What is the current state? Any uncommitted changes?

### 0.2 Commit or discard

If there are uncommitted changes:
- If they're relevant to Phase 30F, commit them first
- If not, discard: `git checkout -- .`

### 0.3 Verify prerequisites

- Phase 30D must be merged
- All C ABI functions must exist in `src/`
- `build.zig` must be stable
- Run `zig build` to verify baseline

### 0.4 Create branch

```bash
git checkout -b phase-30f-xcframework-swift
```

Verify: `git branch`

---

## Step 1: Cross-Compilation Build Scripts (D30F.1)

Commit: `phase-30f/D30F.1: add cross-compilation build script for iOS targets`

### What to do

1. Create `scripts/build-ios.sh`
2. Script must build .a files for three targets:
   - `aarch64-ios` (device): `zig build -Dtarget=aarch64-ios -Doptimize=ReleaseSafe`
   - `aarch64-ios-simulator` (ARM64 sim): `zig build -Dtarget=aarch64-ios-simulator -Doptimize=ReleaseSafe`
   - `x86_64-ios-simulator` (Intel sim): `zig build -Dtarget=x86_64-ios-simulator -Doptimize=ReleaseSafe`
3. Each target outputs a .a file (static library)
4. Script copies outputs to a staging directory (e.g., `build/ios-libs/`)
5. Script is idempotent and has clear success/failure messages
6. Test: `bash scripts/build-ios.sh` produces three .a files

### Acceptance

- Script runs without error
- All three .a files are produced
- Each is valid (not corrupted, correct architecture)
- Script can run multiple times safely
- Output directory is clean and organized

### Commit

```bash
git add scripts/build-ios.sh
git commit -m "phase-30f/D30F.1: add cross-compilation build script for iOS targets"
```

---

## Step 2: XCFramework Creation (D30F.2)

Commit: `phase-30f/D30F.2: create XCFramework with all iOS architecture slices`

### What to do

1. Extend `scripts/build-ios.sh` to run XCFramework creation after building .a files
2. Use `xcodebuild -create-xcframework`:
   ```bash
   xcodebuild -create-xcframework \
     -library build/ios-libs/aarch64-ios/semantos.a \
     -headers include/ \
     -library build/ios-libs/aarch64-ios-simulator/semantos.a \
     -headers include/ \
     -library build/ios-libs/x86_64-ios-simulator/semantos.a \
     -headers include/ \
     -output Semantos.xcframework
   ```
3. Verify output: `ls -R Semantos.xcframework/` should show all architectures
4. Test: `xcodebuild -validateInputFile Semantos.xcframework` (if available)

### Acceptance

- `xcodebuild -create-xcframework` completes without error
- `Semantos.xcframework` exists and is a valid framework
- Framework contains all three architecture slices
- Headers are included and readable
- Framework can be imported in Xcode project

### Commit

```bash
git add scripts/build-ios.sh
git commit -m "phase-30f/D30F.2: create XCFramework with all iOS architecture slices"
```

---

## Step 3: Swift Bridging Layer (D30F.3)

Commit: `phase-30f/D30F.3: implement Swift bridging layer (SemantosKernel, SemantosError, Callbacks)`

### What to do

1. Create `platforms/ios/SemantosSDK/` directory
2. Create `SemantosError.swift`:
   ```swift
   enum SemantosError: Error {
       case initFailed(Int32)
       case cellWriteFailed(Int32)
       case cellReadFailed(Int32)
       case capabilityCheckFailed(Int32)
       // ... other error cases mapped from semantos.h error codes
   }
   ```
3. Create `SemantosKernel.swift`:
   ```swift
   class SemantosKernel {
       func initialize(config: Data) throws { ... }
       func shutdown() { ... }
       func cellWrite(path: String, data: Data) throws { ... }
       func cellRead(path: String) -> Data? { ... }
       func capabilityCheck(certId: Data, domainFlag: UInt32) throws -> Data { ... }
       // ... other C ABI functions
   }
   ```
   - Use `withUnsafeBytes` and `withUnsafeMutableBytes` for Data ↔ pointer conversion
   - Use `defer` to guarantee cleanup
   - All C function calls wrapped with error checking
4. Create `Callbacks.swift`:
   ```swift
   @convention(c) func hostStorageRead(pathPtr: UnsafeRawPointer, pathLen: Int, ...) -> Int32 {
       let singleton = StorageAdapter.shared
       return singleton.read(...)
   }
   // ... other @convention(c) callbacks
   ```
   - Each callback is a top-level function that dispatches to singleton adapters
   - No closures, no instance methods

### Acceptance

- Code compiles with `xcodebuild build` (or `swift build` if using SPM)
- `SemantosKernel().initialize()` succeeds
- `cellWrite()` and `cellRead()` work without crash
- All callbacks are callable from C
- No Swift errors or warnings

### Commit

```bash
git add platforms/ios/SemantosSDK/
git commit -m "phase-30f/D30F.3: implement Swift bridging layer (SemantosKernel, SemantosError, Callbacks)"
```

---

## Step 4: Host Adapter Implementations (D30F.4)

Commit: `phase-30f/D30F.4: implement Swift adapters (Storage, Identity, Anchor, Network)`

### What to do

1. Create `platforms/ios/SemantosSDK/Adapters/SQLiteStorageProvider.swift`:
   - Use GRDB (or SQLite.swift), WAL mode, Application Support directory
   - Implement cell write/read with path as key
   - Handle concurrent access safely
2. Create `platforms/ios/SemantosSDK/Adapters/KeychainIdentityProvider.swift`:
   - Generate keys in Secure Enclave (device) or software Keychain (simulator)
   - Store certificates in Keychain
   - Support biometric access control for sensitive operations
   - Document fallback for simulator
3. Create `platforms/ios/SemantosSDK/Adapters/HttpAnchorProvider.swift`:
   - Use URLSession
   - Batch state hashes before submitting
   - Queue offline requests in SQLite, flush when online
4. Create `platforms/ios/SemantosSDK/Adapters/HttpNetworkProvider.swift`:
   - Make REST calls to configurable endpoint
   - Handle timeouts and retries gracefully

### Acceptance

- All adapters compile without error
- SQLiteStorageProvider persists data to device database
- KeychainIdentityProvider generates and stores keys
- HttpAnchorProvider batches and queues correctly
- HttpNetworkProvider makes HTTP calls
- All adapters handle errors gracefully

### Commit

```bash
git add platforms/ios/SemantosSDK/Adapters/
git commit -m "phase-30f/D30F.4: implement Swift adapters (Storage, Identity, Anchor, Network)"
```

---

## Step 5: Swift Demo App (D30F.5)

Commit: `phase-30f/D30F.5: create minimal SwiftUI demo app`

### What to do

1. Create `platforms/ios/SemantosDemo/` as a new SwiftUI Xcode project
2. Add `Semantos.xcframework` to project: Xcode → Targets → Build Phases → Link Binary With Libraries
3. Create `ContentView.swift` with:
   - Initialize button: calls `SemantosKernel().initialize()`
   - Write button: writes sample cell, displays result
   - Read button: reads cell back, displays bytes
   - Capability check button: calls `capabilityCheck()`, shows success/failure
   - LINEAR consume button: demonstrates linear proof consumption
   - Status display: shows kernel version, cell data, errors
4. Test: `xcodebuild build -scheme SemantosDemo`

### Acceptance

- App builds with no errors or warnings
- App runs in iOS Simulator (arm64 or x86_64)
- Cell write displays confirmation
- Cell read displays identical data as written
- Capability check shows result
- UI is responsive, no ANRs
- Tap all buttons without crash

### Commit

```bash
git add platforms/ios/SemantosDemo/
git commit -m "phase-30f/D30F.5: create minimal SwiftUI demo app"
```

---

## Step 6: Swift Integration Tests (D30F.6)

Commit: `phase-30f/D30F.6: add XCTest integration tests`

### What to do

1. Create `platforms/ios/SemantosSDKTests/` as XCTest target
2. Add tests:
   ```swift
   func testKernelInitialization() {
       let kernel = SemantosKernel()
       XCTAssertNoThrow(try kernel.initialize(...))
   }
   func testCellRoundTrip() {
       let kernel = SemantosKernel()
       try kernel.initialize(...)
       let data = "Hello, Semantos!".data(using: .utf8)!
       try kernel.cellWrite(path: "/test/cell", data: data)
       let readBack = kernel.cellRead(path: "/test/cell")
       XCTAssertEqual(readBack, data)
   }
   func testCallbackInvocation() {
       // Verify callbacks are called with correct arguments
   }
   func testMemoryLeaks() {
       // Run 100 write/read cycles, use Instruments to verify no leaks
   }
   ```
3. Run tests: `xcodebuild test -scheme SemantosSDK`
4. Use Xcode Instruments (Memory, Allocations) to verify no leaks

### Acceptance

- XCTest suite runs with `xcodebuild test`
- All tests pass
- Instruments shows no memory leaks
- Tests cover happy path and error cases

### Commit

```bash
git add platforms/ios/SemantosSDKTests/
git commit -m "phase-30f/D30F.6: add XCTest integration tests"
```

---

## Completion Criteria

1. All 6 deliverables (D30F.1–D30F.6) complete and committed
2. All 9 TDD Gate Tests pass
3. XCTest suite passes with 100% success
4. Demo app builds and runs on iOS Simulator
5. Device test (if available): Secure Enclave key access verified
6. Xcode validation: no errors, no deprecation warnings
7. Framework validation: `xcodebuild -create-xcframework` completes cleanly
8. Memory: Instruments shows no leaks after 100 cycles

---

## Post-Phase: Errata Sprint

After Phase 30F merges to main:

1. **Code review**: Verify memory safety (no UAF, no dangling pointers)
2. **Security audit**: Keychain/Secure Enclave access is correct, keys are protected
3. **Performance**: Profile app startup and cell I/O latency
4. **Compatibility**: Test on multiple iOS versions (13.0+, 14.0+, etc.)
5. **Documentation**: Add iOS integration guide to docs/iOS.md
6. **CI/CD**: Add GitHub Actions or equivalent to build and test on every commit

---

## Notes

- XCFramework is the modern Xcode framework format; use this instead of fat binaries
- `@convention(c)` functions must be top-level; closures cannot be C function pointers
- Secure Enclave is device-only; simulator uses software keychain (document this)
- GRDB is lightweight and Swift-friendly; Realm is heavier but more powerful
- URLSession is the modern networking API; AFNetworking is legacy
