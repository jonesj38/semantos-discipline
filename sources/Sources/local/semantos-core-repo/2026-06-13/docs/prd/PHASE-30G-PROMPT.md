---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30G-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.699773+00:00
---

# Phase 30G Execution Prompt — semantos_ffi Dart Package & Flutter Demo App

> Paste this prompt into a fresh session to execute Phase 30G.

## Context

Dart's `dart:ffi` provides direct C interop. The same .a/.so from Zig links into Flutter apps. On iOS via Runner Xcode project, on Android via CMakeLists.txt. This phase creates the semantos_ffi Flutter package with FFI bindings, idiomatic Dart wrappers, and adapter implementations that handle Dart's async-in-sync-callback challenge.

### The Boundary Rule

Dart FFI callbacks must not call async code directly. The adapter implementations use a shared message queue: callback enqueues request → Dart isolate performs async I/O → Completer resolves → callback returns. This keeps the kernel's synchronous model intact while allowing Dart's async underneath. `Pointer.fromFunction<NativeCallback>()` for synchronous callbacks only.

---

## CRITICAL: READ THESE FILES FIRST

1. `docs/prd/PHASE-30-FFI-MASTER.md` — Dart integration, package structure, adapter table, rationale
2. `docs/prd/PHASE-30A-C-ABI-HEADER.md` — semantos.h for binding generation
3. `docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md` — Callback signatures (host_storage_read, etc.)
4. `docs/BRANCHING-AND-CI-POLICY.md` — Commit naming convention
5. `build.zig` — Current build configuration

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

1. **NO STUBS**: Every Dart adapter does real work. No placeholder implementations. SqfliteStorageAdapter persists to SQLite, PlatformIdentityAdapter accesses device keystore, HttpAnchorProvider makes HTTP calls.
2. **CALLBACK BRIDGE IS MANDATORY**: Async Dart I/O from sync C callbacks via isolate queue. This is NOT optional. Callbacks must not block on async operations directly. Use `SendPort` and `ReceivePort` or equivalent.
3. **BOTH PLATFORMS**: Must work on iOS AND Android. Build and test on both. iOS uses Podspec/XCFramework, Android uses CMakeLists.txt.
4. **POINTER SAFETY**: Every `Pointer<Uint8>` allocated via `calloc.allocate()` must be freed via `calloc.free()`. No memory leaks. Use `try/finally` or `using` pattern.
5. **NO EASY TESTS**: Tests must verify behavior. Cell write → read must return identical bytes. Callback bridge must handle concurrent requests without deadlock.
6. **NO TESTS THAT MATCH BROKEN CODE**: If you write a test that passes only because the code is broken, rewrite both.
7. **FFIGEN DECISION MUST BE DOCUMENTED**: Decide whether to auto-generate bindings via ffigen or hand-write them. Document why in `lib/src/bindings.dart` header comment.
8. **DEMO APP MUST RUN**: Not just compile. The app must launch on both iOS Simulator and Android Emulator, write a cell, read it back, and display the result.

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
- If they're relevant to Phase 30G, commit them first
- If not, discard: `git checkout -- .`

### 0.3 Verify prerequisites

- Phase 30D must be merged
- All C ABI functions must exist in `src/`
- `.a` files must build for iOS targets (from Phase 30F)
- `.so` files must build for Android targets (from Phase 30D or new build script)
- `build.zig` must be stable
- Run `zig build` to verify baseline

### 0.4 Create branch

```bash
git checkout -b phase-30g-dart-ffi-package
```

Verify: `git branch`

---

## Step 1: Flutter Package Scaffold (D30G.1)

Commit: `phase-30g/D30G.1: scaffold semantos_ffi Dart/Flutter package`

### What to do

1. Create `platforms/flutter/semantos_ffi/` directory
2. Initialize as a Dart package:
   ```bash
   cd platforms/flutter/semantos_ffi
   flutter create --template=plugin .
   ```
   Or manually create structure:
   - `pubspec.yaml`: package metadata, dependencies (ffi, path_provider, sqflite, flutter_secure_storage, dio, etc.)
   - `lib/src/bindings.dart` (placeholder)
   - `lib/src/kernel.dart` (placeholder)
   - `lib/src/adapters/` (placeholder)
   - `lib/semantos_ffi.dart` (main export)
   - `ios/semantos_ffi.podspec` (for iOS)
   - `android/CMakeLists.txt` (for Android)
   - `test/` (directory for tests)
3. Populate `pubspec.yaml` with all dependencies:
   ```yaml
   name: semantos_ffi
   version: 1.0.0
   dependencies:
     ffi: ^2.0.0
     path_provider: ^2.0.0
     sqflite: ^2.0.0
     flutter_secure_storage: ^8.0.0
     dio: ^5.0.0
   dev_dependencies:
     flutter_test:
       sdk: flutter
   ```
4. Create iOS Podspec linking to semantos.xcframework:
   ```ruby
   Pod::Spec.new do |s|
     s.name             = 'semantos_ffi'
     s.version          = '1.0.0'
     s.summary          = 'Semantos FFI bindings for Flutter'
     s.homepage         = 'https://semantos.io'
     s.license          = { :file => '../LICENSE' }
     s.author           = { 'Semantos' => 'hello@semantos.io' }
     s.source           = { :path => '.' }
     s.platform         = :ios, '13.0'
     s.vendored_frameworks = 'Frameworks/Semantos.xcframework'
   end
   ```
5. Create Android CMakeLists.txt linking native library:
   ```cmake
   cmake_minimum_required(VERSION 3.16)
   project(semantos_ffi)

   add_library(semantos STATIC IMPORTED)
   set_property(TARGET semantos PROPERTY IMPORTED_LOCATION
                "${CMAKE_CURRENT_SOURCE_DIR}/../../build/android/${ANDROID_ABI}/libsemantos.a")

   # Expose for Flutter plugin
   target_include_directories(semantos INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/include)
   ```
6. Test: `flutter pub get` succeeds

### Acceptance

- Package structure follows Dart conventions
- `pubspec.yaml` is valid
- iOS Podspec is valid (can be validated by `pod lib lint`)
- Android CMakeLists.txt is syntactically correct
- `flutter pub get` completes without error

### Commit

```bash
git add platforms/flutter/semantos_ffi/
git commit -m "phase-30g/D30G.1: scaffold semantos_ffi Dart/Flutter package"
```

---

## Step 2: Dart FFI Bindings (D30G.2)

Commit: `phase-30g/D30G.2: generate FFI bindings from semantos.h`

### What to do

**Option A: Use ffigen (auto-generated)**
1. Install ffigen: `flutter pub add dev:ffigen`
2. Create `pubspec.yaml` ffigen config:
   ```yaml
   ffigen:
     output: 'lib/src/bindings.dart'
     headers:
       entry-points:
         - 'path/to/semantos.h'
     exclude-all-by-default: true
     functions:
       - semantos_version
       - semantos_init
       - ... (all other C functions)
   ```
3. Run: `flutter pub run ffigen`
4. Review generated bindings

**Option B: Hand-written (more control)**
1. Create `lib/src/bindings.dart` manually
2. Define all C functions:
   ```dart
   import 'dart:ffi' as ffi;

   typedef SemantosFfiNative = ffi.DynamicLibrary Function();

   ffi.DynamicLibrary _loadLibrary() {
     if (ffi.Platform.isIOS) {
       return ffi.DynamicLibrary.open('Semantos.framework/Semantos');
     } else if (ffi.Platform.isAndroid) {
       return ffi.DynamicLibrary.open('libsemantos.so');
     } else {
       throw UnsupportedError('Unknown platform');
     }
   }

   // C function signatures
   typedef SemantoVersionNative = ffi.Pointer<ffi.Char> Function();
   typedef SemantoVersionDart = String Function();

   class SemantosBindings {
     final ffi.DynamicLibrary _lib = _loadLibrary();

     late final semantos_version = _lib
       .lookup<ffi.NativeFunction<SemantoVersionNative>>('semantos_version')
       .asFunction<SemantoVersionDart>();

     // ... other functions
   }
   ```
3. Document why hand-written in header comments

### Acceptance

- All C functions from semantos.h are declared
- Function signatures are correct (match C exactly)
- Library loading works on iOS and Android
- Binding types are correct (Pointer, Int32, callconv(.C), etc.)

### Commit

```bash
git add lib/src/bindings.dart
git commit -m "phase-30g/D30G.2: generate FFI bindings from semantos.h"
```

---

## Step 3: Dart Kernel Wrapper (D30G.3)

Commit: `phase-30g/D30G.3: implement SemantosKernel Dart wrapper`

### What to do

1. Create `lib/src/kernel.dart`:
   ```dart
   class SemantosKernel {
     late final SemantosBindings _bindings;

     SemantosKernel() {
       _bindings = SemantosBindings();
     }

     Future<void> initialize(Uint8List config) async {
       final configPtr = _allocateBuffer(config);
       try {
         final result = _bindings.semantos_init(
           configPtr.cast<ffi.Uint8>(),
           config.length,
         );
         if (result != 0) {
           throw SemantosException('Init failed: $result');
         }
       } finally {
         calloc.free(configPtr);
       }
     }

     Future<void> shutdown() async {
       _bindings.semantos_shutdown();
     }

     Future<void> cellWrite(String path, Uint8List data) async {
       final pathPtr = _allocateString(path);
       final dataPtr = _allocateBuffer(data);
       try {
         final result = _bindings.semantos_cell_write(
           pathPtr.cast<ffi.Uint8>(),
           path.length,
           dataPtr.cast<ffi.Uint8>(),
           data.length,
         );
         if (result != 0) throw SemantosException('Write failed: $result');
       } finally {
         calloc.free(pathPtr);
         calloc.free(dataPtr);
       }
     }

     Future<Uint8List?> cellRead(String path) async {
       // Similar pattern with allocation/deallocation
     }

     // ... other kernel functions

     ffi.Pointer<ffi.Uint8> _allocateBuffer(Uint8List data) {
       final ptr = calloc<ffi.Uint8>(data.length);
       ptr.asTypedList(data.length).setAll(0, data);
       return ptr;
     }

     ffi.Pointer<ffi.Char> _allocateString(String s) {
       final units = utf8.encode(s);
       final ptr = calloc<ffi.Char>(units.length + 1);
       ptr.asTypedList(units.length).setAll(0, units);
       ptr[units.length] = 0; // null terminator
       return ptr;
     }
   }
   ```
2. Use `try/finally` or `using` to guarantee cleanup
3. All C function calls wrapped with error checking
4. Return idiomatic Dart types (Uint8List, String, etc.)

### Acceptance

- Class initializes without error
- `cellWrite()` and `cellRead()` work correctly
- Memory: no leaks, all Pointers freed
- Error handling is correct
- Dart types marshal correctly to/from C

### Commit

```bash
git add lib/src/kernel.dart
git commit -m "phase-30g/D30G.3: implement SemantosKernel Dart wrapper"
```

---

## Step 4: Dart Adapter Implementations (D30G.4)

Commit: `phase-30g/D30G.4: implement storage, identity, anchor, network adapters`

### What to do

1. Create `lib/src/adapters/sqflite_storage_adapter.dart`:
   - Use sqflite package
   - Create database in path_provider.getApplicationDocumentsDirectory()
   - Enable WAL mode
   - Implement cell write/read with path as key
   - Handle concurrent access with locks if needed

2. Create `lib/src/adapters/platform_identity_adapter.dart`:
   - Use flutter_secure_storage for Keychain (iOS) and Keystore (Android)
   - Generate keys via platform channels if needed
   - Store certificates securely
   - Handle Secure Enclave on iOS (via platform channel)
   - Handle StrongBox on Android (via platform channel)

3. Create `lib/src/adapters/http_anchor_adapter.dart`:
   - Use dio package for HTTP
   - Batch state hashes before submitting
   - Queue offline requests in SQLite
   - Flush queue when online (use ConnectivityPlus or similar)

4. Create `lib/src/adapters/http_network_adapter.dart`:
   - Use dio for REST calls
   - Configurable endpoint
   - Handle timeouts and retries

### Acceptance

- All adapters compile without error
- SqfliteStorageAdapter persists data to SQLite
- PlatformIdentityAdapter stores/retrieves keys securely
- HttpAnchorProvider batches and queues correctly
- HttpNetworkProvider makes HTTP calls
- All adapters error handling is correct

### Commit

```bash
git add lib/src/adapters/
git commit -m "phase-30g/D30G.4: implement storage, identity, anchor, network adapters"
```

---

## Step 5: Async Callback Bridge (D30G.5)

Commit: `phase-30g/D30G.5: implement callback bridge for async I/O in sync context`

### What to do

1. Create `lib/src/callback_bridge.dart`:
   ```dart
   class CallbackBridge {
     static final CallbackBridge _instance = CallbackBridge._internal();

     factory CallbackBridge() => _instance;

     CallbackBridge._internal();

     late SendPort _port;
     final Map<int, Completer> _pendingRequests = {};
     int _requestId = 0;

     Future<void> initialize() async {
       final receivePort = ReceivePort();
       _port = receivePort.sendPort;

       receivePort.listen((message) {
         // Handle responses from async isolate
         if (message is Map && message.containsKey('requestId')) {
           final requestId = message['requestId'];
           final result = message['result'];
           if (_pendingRequests.containsKey(requestId)) {
             _pendingRequests[requestId]!.complete(result);
             _pendingRequests.remove(requestId);
           }
         }
       });
     }

     // Called from @convention(c) callback in C context
     Uint8List storageRead(String path) {
       final requestId = _requestId++;
       final completer = Completer<Uint8List>();
       _pendingRequests[requestId] = completer;

       _port.send({
         'type': 'storage_read',
         'path': path,
         'requestId': requestId,
       });

       // Busy-wait or platform-specific blocking
       // This is the hard part: we're in a sync context but need async result
       // One approach: busy-wait with small sleeps in a loop
       // Another: use native async-capable library on each platform

       while (!completer.isCompleted) {
         // Yield to event loop (platform-specific)
         // This is tricky in Dart FFI context
       }

       return completer.future.result;
     }

     // ... similar for other callbacks
   }
   ```
2. Alternative approach: Use isolate.compute() for CPU-bound, RawReceivePort for IPC
3. Document the trade-offs and chosen approach

### Acceptance

- Callback bridge forwards requests to async handler
- Async handler waits for response
- Callback waits for response and returns result
- No deadlock under concurrent callbacks
- No blocking that freezes UI

### Commit

```bash
git add lib/src/callback_bridge.dart
git commit -m "phase-30g/D30G.5: implement callback bridge for async I/O in sync context"
```

---

## Step 6: Flutter Demo App (D30G.6)

Commit: `phase-30g/D30G.6: create Flutter demo app (iOS + Android)`

### What to do

1. Create `platforms/flutter/semantos_demo/` as Flutter app:
   ```bash
   flutter create semantos_demo
   cd semantos_demo
   flutter pub add semantos_ffi
   ```
2. Create `lib/main.dart` with SwiftUI-like UI:
   ```dart
   class SemantosDemo extends StatefulWidget {
     @override
     _SemantoDemoState createState() => _SemantoDemoState();
   }

   class _SemantoDemoState extends State<SemantosDemo> {
     late SemantosKernel _kernel;
     String _status = 'Initializing...';
     String _cellData = '';

     @override
     void initState() {
       super.initState();
       _initialize();
     }

     void _initialize() async {
       try {
         _kernel = SemantosKernel();
         await _kernel.initialize(Uint8List(0));
         setState(() { _status = 'Initialized'; });
       } catch (e) {
         setState(() { _status = 'Init failed: $e'; });
       }
     }

     void _writeCell() async {
       try {
         final data = Uint8List.fromList(utf8.encode('Hello, Semantos!'));
         await _kernel.cellWrite('/test/cell', data);
         setState(() { _status = 'Cell written'; });
       } catch (e) {
         setState(() { _status = 'Write failed: $e'; });
       }
     }

     void _readCell() async {
       try {
         final data = await _kernel.cellRead('/test/cell');
         setState(() {
           _cellData = utf8.decode(data ?? []);
           _status = 'Cell read: $_cellData';
         });
       } catch (e) {
         setState(() { _status = 'Read failed: $e'; });
       }
     }

     @override
     Widget build(BuildContext context) {
       return MaterialApp(
         home: Scaffold(
           appBar: AppBar(title: Text('Semantos Demo')),
           body: Center(
             child: Column(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 Text(_status),
                 SizedBox(height: 20),
                 ElevatedButton(onPressed: _writeCell, child: Text('Write Cell')),
                 ElevatedButton(onPressed: _readCell, child: Text('Read Cell')),
                 SizedBox(height: 20),
                 Text('Cell Data: $_cellData'),
               ],
             ),
           ),
         ),
       );
     }
   }
   ```
3. Test: `flutter run` on iOS Simulator and Android Emulator

### Acceptance

- App builds on iOS and Android
- App runs in Simulator/Emulator without crash
- Write button stores data
- Read button retrieves identical data
- UI is responsive

### Commit

```bash
git add platforms/flutter/semantos_demo/
git commit -m "phase-30g/D30G.6: create Flutter demo app (iOS + Android)"
```

---

## Step 7: Dart/Flutter Tests (D30G.7)

Commit: `phase-30g/D30G.7: add comprehensive Dart/Flutter integration tests`

### What to do

1. Create `platforms/flutter/semantos_ffi/test/bindings_test.dart`:
   - Test library loading
   - Test function lookup
   - Test callback pointer creation

2. Create `platforms/flutter/semantos_ffi/test/kernel_test.dart`:
   ```dart
   test('cellWrite and cellRead return identical bytes', () async {
     final kernel = SemantosKernel();
     final originalData = Uint8List.fromList(utf8.encode('Hello, World!'));

     await kernel.cellWrite('/test/path', originalData);
     final readData = await kernel.cellRead('/test/path');

     expect(readData, equals(originalData));
   });
   ```

3. Create `platforms/flutter/semantos_ffi/test/callback_bridge_test.dart`:
   - Test message queue
   - Test concurrent requests
   - Test no deadlock

4. Create `platforms/flutter/semantos_ffi/test/adapters_test.dart`:
   - Test SqfliteStorageAdapter
   - Test PlatformIdentityAdapter
   - Test HttpAnchorAdapter
   - Test HttpNetworkAdapter

5. Run tests: `flutter test`

### Acceptance

- Test suite runs with `flutter test`
- All tests pass
- Tests cover happy path and error cases
- Memory profiler shows no leaks

### Commit

```bash
git add platforms/flutter/semantos_ffi/test/
git commit -m "phase-30g/D30G.7: add comprehensive Dart/Flutter integration tests"
```

---

## Completion Criteria

1. All 7 deliverables (D30G.1–D30G.7) complete and committed
2. All 10 TDD Gate Tests pass
3. Flutter test suite passes with 100% success on both iOS and Android
4. Demo app builds and runs on iOS Simulator and Android Emulator
5. Package structure follows Dart conventions and can be published to pub.dev
6. Memory: profiler shows no leaks after 100 cycles
7. ffigen decision documented (auto-generated vs hand-written)
8. CI/CD validates Dart/Flutter builds on every commit

---

## Post-Phase: Errata Sprint

After Phase 30G merges to main:

1. **Code review**: Verify memory safety (no UAF, no dangling pointers)
2. **Security audit**: Keystore/Secure Enclave access is correct, keys are protected
3. **Performance**: Profile callback bridge latency and throughput
4. **Compatibility**: Test on multiple Android API levels (21+) and iOS versions (13+)
5. **Documentation**: Add Dart integration guide to docs/DART.md
6. **pub.dev**: Publish semantos_ffi package to pub.dev for easy dependency
7. **CI/CD**: Add GitHub Actions for Dart/Flutter build and test

---

## Notes

- `dart:ffi` requires Dart 2.12+ (null safety) and Flutter 2.0+
- Callbacks in FFI context cannot block on async code; use isolate message queue
- `Pointer.fromFunction<NativeCallback>()` creates a stable callback pointer
- ffigen auto-generates bindings; hand-writing gives more control and docs
- pubspec.yaml dependencies: ffi, path_provider, sqflite, flutter_secure_storage, dio
- Android requires NDK and CMakeLists.txt; iOS requires Podspec or XCFramework
- Test on real device for Secure Enclave/StrongBox behavior (simulator is limited)
