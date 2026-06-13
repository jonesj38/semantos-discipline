---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30G-DART-FFI-PACKAGE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.690390+00:00
---

# Phase 30G — semantos_ffi Dart Package & Flutter Demo App

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 30D complete (all core C ABI functions)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30g-dart-ffi-package`

---

## Context

Dart's `dart:ffi` provides direct C interop. The same .a/.so from Zig links into Flutter apps. On iOS via Runner Xcode project, on Android via CMakeLists.txt. This phase creates the semantos_ffi Flutter package with auto-generated or hand-written FFI bindings, idiomatic Dart wrappers, and adapter implementations that handle Dart's async-in-sync-callback challenge.

### The Boundary Rule

Dart FFI callbacks must not call async code directly. The adapter implementations use a shared message queue: callback enqueues request → Dart isolate performs async I/O → Completer resolves → callback returns. This keeps the kernel's synchronous model intact while allowing Dart's async underneath. `Pointer.fromFunction<NativeCallback>()` for synchronous callbacks only.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | Dart integration, package structure, adapter table |
| `PHASE-30A` | `docs/prd/PHASE-30A-C-ABI-HEADER.md` | semantos.h for binding generation |
| `PHASE-30B` | `docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md` | Callback signatures |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming |

---

## Deliverables

### D30G.1 — Flutter package scaffold

New directory: `platforms/flutter/semantos_ffi/`

Package structure:
- `lib/src/bindings.dart`: FFI bindings from semantos.h (via ffigen or hand-written)
- `lib/src/kernel.dart`: SemantosKernel class wrapping bindings
- `lib/src/adapters/`: Abstract adapter interfaces in Dart
- `ios/`: Podspec linking libsemantos.a
- `android/`: CMakeLists.txt linking libsemantos.so
- `pubspec.yaml`: Package metadata and dependencies

**Acceptance criteria**:
- Package structure follows Dart package conventions
- `pubspec.yaml` is valid and lists all dependencies (ffi, path_provider, sqflite, http, etc.)
- iOS Podspec references semantos.xcframework (or equivalent)
- Android CMakeLists.txt references semantos library
- Package can be built with `flutter pub get`

### D30G.2 — Dart FFI bindings

New file: `lib/src/bindings.dart`

All C function signatures as Dart FFI types. `Pointer<Uint8>` for buffers, `Int32` for results, `NativeFunction` typedefs for callbacks.

**Acceptance criteria**:
- All C functions from semantos.h are declared
- Function signatures are correct (parameter types, return types)
- Callback typedefs match host import signatures
- Bindings can be generated via ffigen or are hand-written and match C exactly
- Library loading works on both iOS and Android

### D30G.3 — Dart kernel wrapper

New file: `lib/src/kernel.dart`

`SemantosKernel` class with:
- `init(config)`, `shutdown()`
- `cellWrite(path, data)`, `cellRead(path)` → `Uint8List`
- `capabilityCheck(certId, domainFlag)`, `capabilityPresent(certId, domainFlag)` → `Uint8List`
- `linearConsume(path, consumerCert)`
- `anchorBatch(stateHashes)` → `List<AnchorProof>`
- `anchorVerify(proof)` → `bool`

Memory management: `Pointer` allocation/free, `Uint8List` ↔ `Pointer` conversion

**Acceptance criteria**:
- Class initializes, shuts down cleanly
- `cellWrite()` accepts path and data
- `cellRead()` returns identical bytes as written
- `capabilityCheck()` calls C and returns result
- Memory: no leaks, all Pointers freed via `calloc.free()`
- Dart types correctly marshal to/from C types

### D30G.4 — Dart adapter implementations

New directory: `lib/src/adapters/`

Four files:
- `sqflite_storage_adapter.dart`: SQLite via sqflite, WAL mode, path_provider
- `platform_identity_adapter.dart`: flutter_secure_storage + platform channels (iOS: Keychain/Secure Enclave, Android: Keystore/StrongBox)
- `http_anchor_adapter.dart`: dio package, batching, offline queue
- `http_network_adapter.dart`: dio for REST (V1)

**Acceptance criteria**:
- SqfliteStorageAdapter persists and retrieves data correctly
- PlatformIdentityAdapter accesses device keystore securely
- HttpAnchorProvider batches state hashes and handles offline queue
- HttpNetworkProvider makes HTTP calls to relay node
- All adapters implement corresponding abstract interface

### D30G.5 — Async callback bridge

New file: `lib/src/callback_bridge.dart`

The shared message queue + isolate bridge that lets synchronous C callbacks trigger async Dart I/O. This is the hardest part of the Dart integration.

**Acceptance criteria**:
- Message queue forwards requests from callback to async handler
- Async handler waits for response and completes Completer
- Callback waits for Completer and returns result
- No deadlock under concurrent callbacks
- Isolate communication is safe and correct

### D30G.6 — Flutter demo app

New directory: `platforms/flutter/semantos_demo/`

Minimal Flutter app: init kernel, write cell, read back, display. Exercises capability and LINEAR consume. Works on both iOS and Android.

**Acceptance criteria**:
- App builds on iOS and Android
- App runs in Simulator and Emulator
- Cell write/read displays result
- UI is responsive, no ANRs
- Taps all buttons without crash

### D30G.7 — Dart/Flutter tests

New directory: `platforms/flutter/semantos_ffi/test/`

Tests:
- Binding correctness tests
- Kernel wrapper round-trip tests
- Callback bridge isolate tests
- Adapter integration tests

**Acceptance criteria**:
- Test suite runs with `flutter test`
- All tests pass
- Tests cover happy path and error cases
- Memory tests show no leaks

---

## TDD Gate Tests

- **T1**: FFI bindings load native library successfully on iOS and Android
- **T2**: Cell write/read round-trip through Dart wrapper returns identical bytes
- **T3**: Callback bridge correctly dispatches async I/O from synchronous callback
- **T4**: SqfliteStorageAdapter persists and retrieves data
- **T5**: PlatformIdentityAdapter accesses platform keystore
- **T6**: Pointer memory: no leaked allocations after 100 write/read cycles
- **T7**: Flutter demo app builds and runs on iOS Simulator and Android Emulator
- **T8**: Dart types correctly marshal to/from C types (Uint8List, String, int)
- **T9**: Isolate message queue handles concurrent callbacks without deadlock
- **T10**: Android CMakeLists.txt correctly links .so, iOS Podspec correctly links .a

---

## Completion Criteria

1. All 7 deliverables (D30G.1–D30G.7) complete and merged to `phase-30g-dart-ffi-package`
2. All 10 TDD Gate Tests pass
3. Flutter test suite passes with no failures
4. Demo app builds and runs on iOS Simulator and Android Emulator
5. Package can be published to pub.dev (structure, docs, metadata correct)
6. Memory: Instruments/profiler shows no leaks after 100 cycles
7. Documentation: Dart integration guide in README or docs/DART.md
8. CI/CD: Build pipeline validates Dart/Flutter builds on every commit

---

## Notes

- `dart:ffi` requires Dart 2.12+ and Flutter 2.0+
- Callbacks cannot directly call async code; use isolate message queue pattern
- `Pointer.fromFunction<NativeCallback>()` creates a stable callback pointer for passing to C
- ffigen can auto-generate bindings from semantos.h; hand-writing is alternative for control
- pubspec.yaml dependencies: ffi, path_provider, sqflite, flutter_secure_storage, dio
- Android requires CMakeLists.txt in android/CMakeLists.txt (or android/src/main/cpp/)
- iOS requires Podspec in ios/semantos_ffi.podspec or use XCFramework
