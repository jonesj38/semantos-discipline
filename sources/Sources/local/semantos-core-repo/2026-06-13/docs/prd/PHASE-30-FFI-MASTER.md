---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30-FFI-MASTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.659758+00:00
---

# PHASE 30: Multi-Target Compilation & Mobile FFI Integration

**Master PRD Document**

| Metadata | Value |
|----------|-------|
| Phase | 30 |
| Version | 1.0 |
| Date | April 2026 |
| Duration | ~8-10 weeks total |
| Prerequisites | Phase 25A-25D (Kernel proof boundary), Phase 26A-26C (Adapter specs) |
| Master Document | KERNEL-MULTI-TARGET-FFI-PRD.docx |
| Branch Prefix | `phase-30` |

---

## Context

### Commercial Motivation

Phase 30 enables three critical market capabilities:

1. **Tradie Mobile Apps (iOS/Flutter)**: OddJobTodd tradie phone apps for job sites require native iOS libraries and Dart FFI bindings. Phase 30F (XCFramework) and 30G (Dart FFI) deliver native libraries for Product Phase 2 (tradie app launch). Without Phase 30I (offline queue), phone apps are unusable offline on job sites — critical blocker.

2. **PM Web Portal (WASM)**: WebAssembly target (Phase 30E) enables browser-based kernel execution for project manager portal, reducing server load and improving latency. Same C ABI boundary ensures behavioral consistency across all deployment environments.

3. **Enterprise Colo Deployment (Docker Multi-Arch)**: Docker multi-arch image (Phase 30J) supports enterprise Colo deployments on both x86_64 and arm64 hardware, unlocking high-margin B2B contracts. Node bootstrap integration ensures secure kernel initialization.

FFI track is the critical path to Product Phase 2 go-live and must start no later than beginning of Product Phase 2 planning.

---

## Architecture Diagram

```
                         Semantos Kernel (Zig)
                              │
                    ┌─────────┼─────────┐
                    │         │         │
                    ▼         ▼         ▼
            C ABI Boundary (semantos.h)
            Memory ownership | Callbacks | Error codes
                    │         │         │
        ┌───────────┴─────────┼─────────┴──────────┐
        │                     │                    │
        ▼                     ▼                    ▼
   Native Targets        WASM Target          Docker (OCI)
        │                     │                    │
   ┌────┴────┐           ┌────┴────┐         ┌────┴────┐
   │    │    │           │         │         │    │    │
  iOS Sim And    wasm32  amd64  arm64
  aarch aarch x86    -wasi linux linux
  64    64_64         /amd /arm
  -ios  -linux        64   64
  -and  -android
  roid
        │                     │                    │
        ├─ XCFramework ────┐  ├─ .wasm ─────┐    ├─ ghcr.io ┐
        ├─ Swift Adapters │  └─ npm pkg   │    ├─ OCI cfg │
        └─ SPM metadata   │                │    └─ Bootstrap
           │              │                │
           ├─ .so (Maven/ │                │
           │  JitPack)    │                │
           │              │                │
           ├─ Dart FFI ────┤ ◄─ C ABI ────┤
           │  (pub.dev)    │                │
           │              │                │
           └─ Flutter ────┘                │
              Demo                        │
                                         ▼
                              Enterprise Colo
                              PM Web Portal
                              Dev Laptop
```

---

## C ABI Surface & Adapter Callbacks Diagram

### Core C ABI Boundary

```
┌─────────────────────────────────────────────────────────┐
│                   Semantos Kernel (Zig)                │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  semantos_init()              semantos_shutdown()      │
│  semantos_cell_read/write()   semantos_cell_verify()   │
│  semantos_capability_*()      semantos_linear_*()      │
│  semantos_anchor_batch/verify()  semantos_free()       │
│  semantos_version()           semantos_last_error()    │
│                                                         │
│                     ┌─────────────────┐                │
│                     │ SemantosResult  │                │
│                     │ (0=OK, -E=err)  │                │
│                     └─────────────────┘                │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  All return SemantosResult                             │
│  Memory: caller-allocated or kernel-freed via free()  │
│  FFI boundary is security boundary                     │
│  Kernel bounds-checks all inputs, never trusts host   │
└─────────────────────────────────────────────────────────┘
          │
          │ Adapter Callbacks
          ▼
┌─────────────────────────────────────────────────────────┐
│              Host-Registered Callbacks                 │
│                                                         │
│  ┌────────────────┐  ┌────────────────┐              │
│  │ StorageAdapter │  │ IdentityAdapter│              │
│  ├────────────────┤  ├────────────────┤              │
│  │ read()         │  │ sign()         │              │
│  │ write()        │  │ verify()       │              │
│  │ exists()       │  │ get_pub()      │              │
│  └────────────────┘  └────────────────┘              │
│                                                         │
│  ┌────────────────┐  ┌────────────────┐              │
│  │ AnchorAdapter  │  │ NetworkAdapter │              │
│  ├────────────────┤  ├────────────────┤              │
│  │ batch()        │  │ send()         │              │
│  │ verify()       │  │ recv()         │              │
│  │ queue()        │  │ status()       │              │
│  └────────────────┘  └────────────────┘              │
│                                                         │
│  All callbacks: synchronous from kernel perspective   │
│  Function pointers registered at init time             │
│  Return SemantosResult or callback-specific codes     │
│                                                         │
└─────────────────────────────────────────────────────────┘
          │
          ▼
    Host Implementation
    (per platform, per deployment)
```

---

## C ABI Memory Ownership & Error Model

### Memory Management
- **Caller-allocated**: Input buffers managed by host (e.g., cell data to write)
- **Kernel-allocated**: Kernel allocates (e.g., cell read result), host frees via `semantos_free()`
- **Zero-copy where possible**: For large blobs, pass host buffer pointers with bounds
- **No host pointer dereferencing**: Kernel copies data in/out, never follows pointers into host memory

### Error Handling
All functions return `SemantosResult`:
- `0` = Success
- Negative values = Error codes (e.g., `-1` = InvalidInput, `-2` = NotFound, `-3` = MemoryError)
- `semantos_last_error()` provides extended error message for debugging

---

## Mobile Platform Integration

### iOS/Swift Integration
- **Artifact**: XCFramework (Phase 30F) containing `.a` for aarch64-ios + aarch64-simulator
- **Linking**: `.a` links via bridging header, `@convention(c)` callbacks dispatch to singleton adapters
- **Adapters**:
  - `SQLiteStorageProvider`: GRDB for SQLite storage
  - `KeychainIdentityProvider`: Secure Enclave signing, key protection
  - `HttpAnchorProvider`: URLSession HTTP anchor lookups
  - `HttpNetworkProvider`/`GrpcNetworkProvider`: URLSession or gRPC for node comms

### Flutter/Dart FFI Integration
- **Artifact**: `semantos_ffi` Dart package (Phase 30G) with `dart:ffi` bindings
- **Async I/O**: Dart FFI callbacks use `Pointer.fromFunction` + shared message queue for async operations (e.g., network calls don't block kernel)
- **Adapters**:
  - `SqfliteStorageAdapter`: sqflite for SQLite storage
  - `PlatformIdentityAdapter`: flutter_secure_storage + platform channels for per-platform key management
  - `HttpAnchorAdapter`: dio for HTTP anchor operations
  - `HttpNetworkAdapter`/`GrpcNetworkAdapter`: dio or similar for node communication
- **Distribution**: pub.dev

---

## Build Pipeline: 7-Target Matrix

All targets cross-compiled from same Zig source, ReleaseSafe default (see Open Question 3).

| Target | Triple | Artifact | Purpose | CI Step |
|--------|--------|----------|---------|---------|
| iOS | `aarch64-macos-ios` | `.a` | Native tradie app | XCFramework packaging |
| iOS Simulator | `aarch64-simulator-macos-ios` | `.a` | Xcode simulator testing | XCFramework packaging |
| Android | `aarch64-linux-android` | `.a` | Native Android NDK build | Maven/JitPack release |
| WebAssembly | `wasm32-wasi` | `.wasm` | Browser portal execution | npm package release |
| x86_64 Docker | `x86_64-linux-musl` | binary | Server deployment x86 | Docker build x86 |
| arm64 Docker | `aarch64-linux-musl` | binary | Server deployment ARM | Docker build arm64 |
| x86_64 Dev | `x86_64-linux-gnu` | binary | Developer testing | CI artifact upload |

**Build Matrix in CI**: Phase 30H orchestrates all 7 builds in parallel/sequence, with artifact integrity verification.

---

## Artifact Distribution

| Artifact | Distribution | Ecosystem | Audience |
|----------|--------------|-----------|----------|
| XCFramework | GitHub Releases + Swift Package Manager | iOS dev | Tradie app iOS developers |
| .a (Android) | Maven Central / JitPack | Android NDK | Android app developers |
| .wasm | npm registry (@semantos/kernel) | JS/TS ecosystem | Web portal developers |
| Docker image | ghcr.io/oddjobtodo/semantos | OCI | Enterprise Colo operators |
| semantos_ffi | pub.dev | Dart/Flutter | Tradie/PM app developers |

---

## Deployment Profiles (6)

Each profile defined by 4 adapter choices. All profiles share same kernel & C ABI.

| Profile | Storage | Identity | Anchor | Network | Use Case |
|---------|---------|----------|--------|---------|----------|
| Tradie Phone (Flutter) | Sqflite | flutter_secure_storage | HTTP (dio) | HTTP/gRPC | Job site tradie app |
| Tradie Phone (Swift) | GRDB | Keychain (SE) | HTTP (URLSession) | HTTP/gRPC | Job site tradie app (iOS) |
| PM Web Portal | IndexedDB/LocalStorage | WebCrypto | HTTP fetch | HTTP/gRPC | Browser-based PM tool |
| Tradie VPS | PostgreSQL | Vault/HSM | HTTP | HTTP/gRPC | Self-hosted tradie infrastructure |
| Dev Laptop | SQLite (file) | File-based keys | HTTP mock | HTTP mock | Local development/testing |
| Enterprise Colo | PostgreSQL + S3 | HSM (external) | Batch anchor service | gRPC + TLS | High-volume deployments |

---

## Offline-First Architecture

### Disconnected-by-Default Model
- Mobile apps operate locally without network by default
- StorageAdapter provides local operation queue
- Anchor/Network operations queue locally when offline

### Replay on Reconnect
- On network restoration, queued operations replay in order
- Anchor batch queries replay against current state
- Cell updates replay with conflict resolution

### Conflict Resolution
When offline changes conflict with network state:
- **LWW** (Last-Write-Wins): Timestamp-based, latest wins
- **Merge**: Custom merge function per cell type
- **Flag**: Mark cell conflicted, manual resolution required
- **LINEAR**: Cell-level linear history, total ordering per node

---

## Security Model

### Key Storage per Platform
- **iOS**: Secure Enclave via Keychain (hardware-backed)
- **Android**: StrongBox/TEE via KeyStore API (hardware-backed if available)
- **Web**: WebCrypto API (browser-managed, limited to session)
- **Server**: File-based keys (encrypted at rest) or Hardware Security Module (HSM)

### FFI Boundary as Security Boundary
- Kernel trusts nothing from host
- All inputs bounds-checked before processing
- Data copied in/out of kernel, never dereferences host pointers
- Error messages scrubbed to prevent information leakage
- Callback function pointers validated at registration time

---

## Sub-Phases Breakdown

| Phase | Name | Deliverable | Duration | Dependencies |
|-------|------|-------------|----------|--------------|
| 30A | C ABI Header | `semantos.h` with core functions (init, shutdown, cell_read, cell_write, free, version, last_error) | 1 week | Kernel proof boundary (25A-25D) |
| 30B | Adapter Callbacks | Callback registration API + `host_storage_read/write` implementation | 1 week | 30A + adapter spec 26A |
| 30C | Capability FFI | `capability_check`, `capability_present`, `linear_consume` FFI bindings | 1 week | 30B + adapter spec 26B |
| 30D | Anchor FFI | `anchor_batch`, `anchor_verify` FFI bindings + error propagation | 3-4 days | 30C + adapter spec 26C |
| 30E | WASM Target | `wasm32-wasi` target + host import bindings (WASI Preview 1 or 2) | 1 week | 30D |
| 30F | XCFramework + Swift | XCFramework packaging (aarch64-ios + simulator) + Swift demo app + bridging header | 1 week | 30D |
| 30G | Dart FFI Package | `semantos_ffi` Dart package + Flutter demo app + async callback queue | 1 week | 30D |
| 30H | CI Pipeline | Build matrix (7 targets) + artifact integrity verification in CI | 3-4 days | 30E + 30F + 30G |
| 30I | Offline Queue | Operation queue + replay logic + conflict resolution engine + persistence via StorageAdapter | 1-2 weeks | 30G (or 30F) |
| 30J | Docker Multi-Arch | Multi-arch Docker image (linux/amd64 + linux/arm64) + node bootstrap integration | 3-4 days | 30D + adapter spec 26E |

---

## Dependency Graph

```
30A (C ABI Header)
  │
  ├─→ 30B (Adapter Callbacks)
         │
         ├─→ 30C (Capability FFI)
                │
                ├─→ 30D (Anchor FFI)
                       │
                       ├─→┐
                       │  │
        ┌──────────────┘  │
        │                 │
        ▼                 ▼
      30E              30F         30G
     (WASM)        (XCFramework)  (Dart FFI)
      (parallel)     (parallel)    (parallel)
        │                │           │
        └────────────────┼───────────┘
                         │
                         ▼
                      30H (CI Pipeline)
                         │
                         ▼
                      30I (Offline Queue)
                         │
                    (also depends on 30G or 30F)

   26E (Adapter Spec: Network)
     │
     └────────→ 30J (Docker Multi-Arch)
                └── 30D dependency

Critical Path: 30A → 30B → 30C → 30D → {30E, 30F, 30G} → 30H → 30I
Estimated: ~7-8 weeks from 30A start
```

---

## Relationship to Product Phases

- **Product Phase 2**: Tradie app launch (Flutter iOS/Android)
  - Depends on: 30F (XCFramework), 30G (Dart FFI), 30I (offline queue)
  - **Critical blocker**: 30I offline queue is prerequisite for usable app on job sites without consistent connectivity
  - FFI track must start no later than beginning of Product Phase 2 planning

- **Product Phase 3**: PM web portal
  - Depends on: 30E (WASM target)
  - Server-side kernel offload reduces latency, improves portal responsiveness

- **Product Phase 4**: Enterprise Colo
  - Depends on: 30J (Docker multi-arch)
  - Node bootstrap ensures secure kernel initialization in customer infrastructure

---

## Open Questions

| # | Question | Impact | Status |
|---|----------|--------|--------|
| 1 | WASI Preview 1 vs Preview 2? | Phase 30E target selection, host bindings, JS interop complexity | OPEN |
| 2 | ffigen auto-generated vs hand-written Dart bindings? | Phase 30G: maintenance burden vs customization flexibility | OPEN |
| 3 | ReleaseSafe vs ReleaseFast for production mobile? | All native targets: performance vs runtime safety (bounds checks, overflow detection) | OPEN |
| 4 | Anchor queue: timer-based vs connectivity-change triggered? | Phase 30I: battery drain vs latency, depends on job site connectivity patterns | OPEN |
| 5 | Kotlin/JNI wrapper alongside Dart FFI? | Post-30G: native Android app option, extends market reach | OPEN |
| 6 | Secure Enclave key migration on new phone? | Pre-launch: user experience risk if key lost, requires test infrastructure | OPEN |

---

## Testing Strategy Overview

### Kernel-Level Tests (Zig)
- FFI boundary contract tests: all 12 core functions tested with invalid inputs, buffer overflows, null pointers
- Memory safety: ASAN/MSAN coverage for use-after-free, double-free, leaks
- Callback invocation: mock adapters verify correct sequencing and error propagation

### FFI Integration Tests (per platform)
- **iOS/Swift**: XCTest suite validates bridging header, callback dispatch, Secure Enclave integration
- **Flutter/Dart**: dart_ffi test suite validates function pointer conversion, async message queue
- **WASM**: JavaScript test harness validates host imports, linear memory boundary, module loading

### Platform-Specific Tests
- **iOS**: Xcode simulator + device testing with TestFlight beta (Phase 30F)
- **Android**: Android Emulator + Firebase Test Lab (Phase 30G)
- **Web**: Karma/Jest test runners (Phase 30E)
- **Docker**: OCI conformance testing, multi-arch binary verification (Phase 30J)

### Deployment Profile Validation
- Each of 6 profiles tested with mock adapters in CI
- Integration tests verify adapter callback correctness per profile
- End-to-end offline queue replay testing (Phase 30I)

---

## Acceptance Criteria

- [ ] All 7 build targets produce valid, linkable binaries
- [ ] FFI boundary passes 100+ integration tests per platform
- [ ] XCFramework and .so libraries distributed via official registries
- [ ] semantos_ffi published to pub.dev with full documentation
- [ ] Offline queue replay tested end-to-end with all conflict resolution modes
- [ ] Docker multi-arch image boots successfully on x86 and ARM hardware
- [ ] Zero memory safety violations in ASAN/MSAN test runs
- [ ] Performance benchmarks: FFI overhead <10% vs native kernel (measured on iOS/Android)

---

## Success Metrics

- **Product Phase 2 Timeline**: FFI track complete no later than 4 weeks before tradie app beta
- **Adoption**: XCFramework and semantos_ffi adopted in all primary app variants
- **Reliability**: <0.1% FFI-related crashes in production over first 30 days
- **Developer Experience**: <2 hours to integrate semantos_ffi into new Flutter app
- **Performance**: Offline queue replay completes <2 seconds for 1000 queued operations

---

## Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | April 2026 | Semantos Core Team | Initial PRD for Phase 30 FFI integration |

