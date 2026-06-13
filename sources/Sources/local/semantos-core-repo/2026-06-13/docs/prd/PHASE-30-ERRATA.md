---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.687357+00:00
---

# PHASE 30 Errata Template: Multi-Target Compilation & Mobile FFI Integration

**Verification Checklist & Known Limitations**

| Metadata | Value |
|----------|-------|
| Template Version | 1.0 |
| Date | April 2026 |
| Purpose | Track FFI implementation correctness across all sub-phases |
| Reference | PHASE-30-FFI-MASTER.md |

---

## 1. Memory Safety Across FFI Boundary

**Critical Focus**: Use-after-free, double-free, buffer overflows at C ABI boundary

### Sub-Phase 30A: C ABI Header

- [ ] `semantos_init()` correctly initializes all kernel state without memory leaks
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `semantos_free()` properly deallocates kernel-allocated buffers without double-free
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Input buffer overflow protection: all `semantos_cell_write()` calls bounds-checked
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `semantos_last_error()` buffer safe for 256-byte error messages
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30B: Adapter Callbacks

- [ ] Function pointer registration validates memory alignment (4-byte or 8-byte per platform)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `host_storage_read()` callback returns data without corrupting kernel heap
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `host_storage_write()` callback accepts kernel-allocated buffers without overwrites
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Callback invocation stack safe: no unbounded recursion from adapter calls
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30C-30D: Capability & Anchor FFI

- [ ] `semantos_capability_check()` verifies caller-provided capability structs without buffer overflow
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `semantos_anchor_batch()` correctly handles variable-length anchor arrays
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `semantos_anchor_verify()` validates proof buffers and signature sizes
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30E: WASM Target

- [ ] WASM linear memory boundary: kernel never writes past heap.base() + heap.size()
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Host import callbacks trap on invalid memory addresses before dereferencing
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phases 30F-30G: iOS/Flutter

- [ ] XCFramework `.a` library memory-safe when linked into Swift app
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `semantos_ffi` Dart bindings use `Pointer<T>()` correctly; no stale pointers
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] ASAN/MSAN test runs report zero use-after-free or double-free violations
  - Status: _______
  - Explanation: ___________________________________________________

---

## 2. Callback Registration Correctness

**Critical Focus**: Function pointer alignment, calling convention, lifecycle management

### Sub-Phase 30B: Adapter Callbacks

- [ ] Callback function pointers conform to platform calling convention (cdecl on x86, ARM EABI)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `StorageAdapter` callbacks registered in correct order (read before write)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `IdentityAdapter` callbacks (sign, verify, get_pub) invoked with correct context
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `AnchorAdapter` callbacks queue and verify operations correctly
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `NetworkAdapter` callbacks handle both sync and async (queued) operations
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30F: iOS Integration

- [ ] Swift `@convention(c)` closures correctly convert to C function pointers
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Singleton adapter instances persist for kernel lifetime (never deallocated early)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] KeychainIdentityProvider registered before first capability check
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30G: Flutter Integration

- [ ] `Pointer.fromFunction()` correctly wraps Dart closures as C callbacks
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Message queue prevents callback reentry (enqueue on host, dequeue on next kernel call)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Adapter instance lifecycle tied to Dart main isolate (no dangling pointers after isolate exit)
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30E: WASM Callbacks

- [ ] Host import function objects correctly implement callback signature
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] WASM table entries never overwritten during kernel execution
  - Status: _______
  - Explanation: ___________________________________________________

---

## 3. WASM Linear Memory Boundary Integrity

**Critical Focus**: Module instantiation, memory page allocation, guest/host pointer safety

### Sub-Phase 30E: WASM Target

- [ ] `wasm32-wasi` linear memory initialized with correct initial and max pages
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Kernel heap allocations never exceed `heap.capacity()` (linear memory size)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Host imports receive guest pointers and validate against guest memory bounds
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] WASM module name exports: `memory`, `__heap_base`, `__data_end` present and correct
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Guest/host pointer translation: guest offset + heap_base = host address verified
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30H: Build Matrix

- [ ] `.wasm` artifact generated from `wasm32-wasi` target passes `wasmvalidate` tool
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] WASM module loads in Node.js + browser without memory trap errors
  - Status: _______
  - Explanation: ___________________________________________________

---

## 4. Platform-Specific Adapter Implementations

**Critical Focus**: No stub implementations, all adapters complete and tested

### Sub-Phase 30F: iOS Adapters

- [ ] `SQLiteStorageProvider` (GRDB) reads/writes cells to persistent DB without stubs
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `KeychainIdentityProvider` signs with Secure Enclave, handles key rotation
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `HttpAnchorProvider` queries anchors via URLSession, handles redirects
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `HttpNetworkProvider` sends/receives node messages (not stub)
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30G: Flutter Adapters

- [ ] `SqfliteStorageAdapter` persists to mobile SQLite without test data
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `PlatformIdentityAdapter` uses flutter_secure_storage for key storage (not plain text)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `HttpAnchorAdapter` integrates with dio package for HTTP calls
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `HttpNetworkAdapter`/`GrpcNetworkAdapter` message routing complete (not stubs)
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30E: WASM Adapters (Demo Portal)

- [ ] `IndexedDBStorageAdapter` writes to browser IndexedDB (not localStorage)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `WebCryptoIdentityAdapter` uses SubtleCrypto.sign() for signing
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] `HttpAnchorAdapter` (fetch-based) handles CORS, timeouts
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30J: Docker Adapters

- [ ] PostgreSQL StorageAdapter uses connection pool, prepared statements
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] HSM IdentityAdapter connects to external key management system
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Batch anchor service AnchorAdapter queues and flushes in batches
  - Status: _______
  - Explanation: ___________________________________________________

---

## 5. Build Matrix Artifact Integrity

**Critical Focus**: All 7 targets produce valid, linkable binaries

### Sub-Phase 30H: CI Pipeline

- [ ] Target: `aarch64-ios` produces `.a` library, symbols table includes all 12 core functions
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Target: `aarch64-simulator-ios` produces `.a` library, debug symbols present
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Target: `aarch64-linux-android` produces `.a` library, NDK compatible ABI
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Target: `wasm32-wasi` produces `.wasm` module, passes `wasmvalidate`
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Target: `x86_64-linux-musl` produces binary, ldd reports no missing dependencies
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Target: `aarch64-linux-musl` produces binary, file reports ELF 64-bit ARM
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Target: `x86_64-linux-gnu` produces binary (dev), linkable with -lsemantos
  - Status: _______
  - Explanation: ___________________________________________________

### Artifact Size Verification

- [ ] XCFramework combined size <50 MB (aarch64-ios + simulator)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] .so (Android) size <10 MB stripped
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] .wasm size <2 MB (ReleaseSafe with LTO)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Docker image size <100 MB (multi-arch with common layers)
  - Status: _______
  - Explanation: ___________________________________________________

---

## 6. Offline Queue Persistence & Replay Ordering

**Critical Focus**: Operation queue durability, replay correctness, conflict resolution

### Sub-Phase 30I: Offline Queue

- [ ] Operations enqueued to StorageAdapter in FIFO order when offline
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Queue persisted to durable storage (SQLite for mobile, IndexedDB for web)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] On reconnect, queued operations replayed in original order without duplication
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Conflict resolution engine handles all 4 modes: LWW, Merge, Flag, LINEAR
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] LWW mode: newer timestamp wins, older write discarded
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Merge mode: custom merge function called, result persisted
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Flag mode: conflict marked for manual resolution, neither version overwritten
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] LINEAR mode: cell linear history maintained, causality preserved
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Dead-letter queue created for operations exceeding max retries
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Replay performance: 1000 queued operations complete in <2 seconds
  - Status: _______
  - Explanation: ___________________________________________________

### End-to-End Replay Testing

- [ ] Test scenario: 5 offline cell writes, reconnect, verify replayed to network
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Test scenario: Offline write, network write to same cell, LWW conflict resolved
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Test scenario: Anchor query queued offline, replayed on reconnect, verified
  - Status: _______
  - Explanation: ___________________________________________________

---

## 7. Secure Enclave / StrongBox Key Lifecycle

**Critical Focus**: Key generation, signing, rotation, platform-specific storage

### Sub-Phase 30F: iOS Secure Enclave

- [ ] Key generated in Secure Enclave (not importable, never leaves enclave)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Signing operations routed to Secure Enclave via Keychain APIs
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Public key exportable, private key never accessible to app
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Key persists across app restarts (stored in Keychain)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Key rotation: new key generated, old key archived, signings use latest
  - Status: _______
  - Explanation: ___________________________________________________

### Sub-Phase 30G: Android StrongBox

- [ ] Key stored in StrongBox if available, falls back to TEE/software
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Signing operations routed to KeyStore (hardware-backed if available)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Key protected by device lock (PIN/biometric)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Key rotation on device factory reset handled gracefully (error code returned)
  - Status: _______
  - Explanation: ___________________________________________________

### Migration & Loss Scenarios

- [ ] iOS: Key migration on new device requires manual user action (design TBD)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Android: Loss of StrongBox key on factory reset documented in user guide
  - Status: _______
  - Explanation: ___________________________________________________

---

## 8. Cross-Compilation Correctness

**Critical Focus**: Zig target triples match platform expectations, no ABI mismatches

### Sub-Phase 30A-30D: Zig Source

- [ ] Triple `aarch64-ios`: Zig target produces arm64-architecture Mach-O
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Triple `aarch64-simulator-ios`: produces x86_64 for Intel, arm64 for Apple Silicon sim
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Triple `aarch64-linux-android`: NDK API level correct (API 21+), ABI compatible
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Triple `wasm32-wasi`: produces valid WASM MVP module with WASI imports
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Triple `x86_64-linux-musl`: produces PIE binary, musl libc symbols correct
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Triple `aarch64-linux-musl`: produces PIE binary, musl libc symbols correct
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Triple `x86_64-linux-gnu`: produces dynamic binary, glibc symbols correct (dev only)
  - Status: _______
  - Explanation: ___________________________________________________

### ABI Verification

- [ ] struct SemantosResult layout matches across all targets (size, alignment, padding)
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Function calling convention: all 12 core functions use same signature on all platforms
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Pointer sizes: 8 bytes on all 64-bit targets, handled correctly in WASM offset calc
  - Status: _______
  - Explanation: ___________________________________________________

- [ ] Integer sizes: i32, i64 consistent across targets (no platform-specific int sizes)
  - Status: _______
  - Explanation: ___________________________________________________

---

## Known Limitations & Design Trade-Offs

### Limitation 1: WASM Linear Memory Growth
- **Description**: WASM linear memory is fixed at instantiation time; cannot grow dynamically
- **Impact**: Application kernel heap limited to initial memory pages; large bulk operations may fail
- **Mitigation**: Pre-allocate sufficient memory, or implement paging (out of scope Phase 30)
- **Status**: ACCEPTED

### Limitation 2: WASM Callback Latency
- **Description**: WASM → JavaScript callbacks incur crossing boundary; no inline optimization
- **Impact**: Storage/anchor operations in WASM slower than native by 2-5x (measured)
- **Mitigation**: Acceptable for PM web portal use cases (not real-time); offload hot paths to Zig
- **Status**: ACCEPTED

### Limitation 3: iOS Simulator ARM64 (Apple Silicon)
- **Description**: `aarch64-simulator-ios` requires separate build from `aarch64-ios`; cannot use device binary in simulator
- **Impact**: XCFramework size doubled; build time increased slightly
- **Mitigation**: Apple Silicon Macs run both natively; Intel Macs use x86_64 simulator (separate issue)
- **Status**: ACCEPTED

### Limitation 4: Callback Reentry Protection (Flutter)
- **Description**: Message queue prevents callback reentry within single kernel call; async operations may queue out-of-order
- **Impact**: Anchor batch operations must complete before next callback; no concurrent operations per kernel call
- **Mitigation**: Acceptable for tradie app; async I/O handled by message queue on reconnect
- **Status**: ACCEPTED

### Limitation 5: Secure Enclave Key Export (iOS)
- **Description**: Secure Enclave keys cannot be exported; lost on device factory reset
- **Impact**: User data tied to device; no cloud backup of keys
- **Mitigation**: Design offline queue recovery for lost keys (manual re-anchor); user documentation
- **Status**: OPEN (pre-launch resolution required)

### Limitation 6: Android StrongBox Availability
- **Description**: StrongBox not available on all devices; software fallback less secure
- **Impact**: Security varies by device; no guarantee of hardware backing
- **Mitigation**: Check `KeyInfo.isInsideSecurityHardware()` at runtime; document limitations
- **Status**: ACCEPTED

### Limitation 7: ReleaseSafe Performance Overhead
- **Description**: ReleaseSafe bounds checking adds 5-15% runtime overhead vs ReleaseFast
- **Impact**: Mobile app performance on older devices may be impacted
- **Mitigation**: Profile on target devices; consider ReleaseFast if acceptable risk (see Open Question 3)
- **Status**: OPEN (decision required)

### Limitation 8: Docker Multi-Arch Build Complexity
- **Description**: Building x86_64 and arm64 binaries requires separate machine or QEMU emulation
- **Impact**: CI build time increases; cross-compilation complexity
- **Mitigation**: Use buildx or separate runners; leverage Docker cache layers
- **Status**: ACCEPTED

---

## Verification Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Phase Lead | _______________ | ________ | _______________ |
| QA Lead | _______________ | ________ | _______________ |
| Security Review | _______________ | ________ | _______________ |
| Arch Review | _______________ | ________ | _______________ |

---

## Errata Updates

| Date | Section | Change | Author |
|------|---------|--------|--------|
| April 2026 | All | Template created | Semantos Core Team |
| | | | |
| | | | |

