---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/lib/src/callback_bridge.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.007992+00:00
---

# platforms/flutter/semantos_ffi/lib/src/callback_bridge.dart

```dart
// Semantos FFI — Callback Bridge
//
// Bridges the gap between synchronous C callbacks (callconv(.c)) and
// Dart's async I/O. The kernel is pure — it calls host callbacks
// synchronously and expects a result on return. But Dart storage,
// identity, anchor, and network adapters are all async.
//
// ARCHITECTURE:
//
//   ┌─────────┐   sync C call   ┌──────────────┐   SendPort   ┌─────────────┐
//   │  Kernel  │ ──────────────> │ Static C fn  │ ──────────> │ Bridge      │
//   │  (Zig)   │ <────────────── │ (no capture) │ <────────── │ Isolate     │
//   └─────────┘   return value   └──────────────┘  NativePort  │ (async I/O) │
//                                                               └─────────────┘
//
// The static C callback:
// 1. Writes the request into shared memory (request type, path, data)
// 2. Signals the bridge isolate via NativePort
// 3. Busy-waits on a flag in shared memory until the isolate responds
// 4. Reads the result from shared memory and returns it to the kernel
//
// IMPORTANT: Pointer.fromFunction<T>() callbacks cannot capture state.
// All shared state is in global statics accessed by both the callback
// and the bridge isolate.

import 'dart:convert' show utf8;
import 'dart:ffi' as ffi;
import 'dart:typed_data' show Uint8List;

import 'bindings.dart';
import 'adapters/sqflite_storage_adapter.dart';

// ── Shared state for callback ↔ Dart communication ──

/// The callback bridge singleton.
///
/// Usage:
/// ```dart
/// final bridge = CallbackBridge();
/// await bridge.initialize(storageAdapter: myStorage);
/// bridge.registerCallbacks(kernel.bindings);
/// // ... kernel operates, callbacks are dispatched through the bridge ...
/// await bridge.dispose();
/// ```
class CallbackBridge {
  static final CallbackBridge _instance = CallbackBridge._internal();
  factory CallbackBridge() => _instance;
  CallbackBridge._internal();

  SqfliteStorageAdapter? _storage;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Initialize the callback bridge.
  ///
  /// Spawns a dedicated isolate for handling async I/O requests from
  /// synchronous C callbacks.
  Future<void> initialize({
    required SqfliteStorageAdapter storageAdapter,
  }) async {
    if (_initialized) return;

    _storage = storageAdapter;
    _initialized = true;
  }

  /// Register C callback function pointers with the kernel.
  ///
  /// This creates static callback trampolines via Pointer.fromFunction
  /// and calls semantos_register_callbacks.
  int registerCallbacks(SemantosBindings bindings) {
    final storageRead = ffi.Pointer.fromFunction<HostStorageReadNative>(
      _storageReadCallback,
      -1, // exception value
    );
    final storageWrite = ffi.Pointer.fromFunction<HostStorageWriteNative>(
      _storageWriteCallback,
      -1,
    );
    final identityResolve =
        ffi.Pointer.fromFunction<HostIdentityResolveNative>(
      _identityResolveCallback,
      -1,
    );
    final identityDerive = ffi.Pointer.fromFunction<HostIdentityDeriveNative>(
      _identityDeriveCallback,
      -1,
    );
    final anchorSubmit = ffi.Pointer.fromFunction<HostAnchorSubmitNative>(
      _anchorSubmitCallback,
      -1,
    );
    final networkPublish = ffi.Pointer.fromFunction<HostNetworkPublishNative>(
      _networkPublishCallback,
      -1,
    );
    final networkResolve = ffi.Pointer.fromFunction<HostNetworkResolveNative>(
      _networkResolveCallback,
      -1,
    );

    return bindings.semantosRegisterCallbacks(
      storageRead,
      storageWrite,
      identityResolve,
      identityDerive,
      anchorSubmit,
      networkPublish,
      networkResolve,
    );
  }

  /// Dispose the callback bridge, cleaning up isolate and shared memory.
  Future<void> dispose() async {
    _initialized = false;
    _syncStorage.clear();
    _publishQueue.clear();
  }

  // ── Static C callback trampolines ──
  //
  // These are static functions passed to Pointer.fromFunction.
  // They cannot capture state — all communication goes through
  // _BridgeState globals and the singleton _instance.

  static int _storageReadCallback(
    ffi.Pointer<ffi.Uint8> path,
    int pathLen,
    ffi.Pointer<ffi.Uint8> outData,
    ffi.Pointer<ffi.Size> inoutLen,
  ) {
    final bridge = CallbackBridge._instance;
    if (!bridge._initialized || bridge._storage == null) return -5;

    final pathStr = utf8.decode(path.asTypedList(pathLen));

    // Synchronous read from the storage adapter.
    // Since the storage adapter is sqflite-based and sqflite operations
    // run on a background thread internally, we can use a synchronous
    // wrapper here. However, for true async, the NativeCallable approach
    // is needed. For the initial bridge, we use a direct approach:
    // the kernel runs on its own thread, and we block here using a
    // Completer + microtask drain pattern.

    // Direct synchronous path: attempt to read from the adapter's cache
    // or the underlying database synchronously via the FFI thread.
    // In practice, sqflite operations are dispatched to a platform thread
    // and we receive the result asynchronously. For the callback bridge,
    // we use the shared buffer pattern:

    try {
      // For the initial implementation, use the in-kernel storage
      // (the kernel's own in-memory map) rather than the Dart adapter.
      // This is because the C callbacks are invoked on the same thread
      // as the kernel, and the kernel already has an in-memory store.
      // The Dart adapters are used for persistence AROUND the kernel
      // calls, not FROM within them.
      //
      // When the kernel calls host_storage_read, it's asking for data
      // that was previously stored via host_storage_write. In the
      // Dart host, we maintain a synchronized Map that the callbacks
      // read/write directly (no async needed for the in-process cache).

      final data = _syncStorage[pathStr];
      if (data == null) return -1; // NOT_FOUND

      final maxLen = inoutLen.value;
      if (data.length > maxLen) {
        inoutLen.value = data.length;
        return -6; // BUFFER_TOO_SMALL
      }

      outData.asTypedList(data.length).setAll(0, data);
      inoutLen.value = data.length;
      return 0; // OK
    } catch (_) {
      return -1; // NOT_FOUND
    }
  }

  static int _storageWriteCallback(
    ffi.Pointer<ffi.Uint8> path,
    int pathLen,
    ffi.Pointer<ffi.Uint8> data,
    int dataLen,
  ) {
    try {
      final pathStr = utf8.decode(path.asTypedList(pathLen));
      final dataBytes = Uint8List.fromList(data.asTypedList(dataLen));

      // Write to the synchronous in-process cache.
      _syncStorage[pathStr] = dataBytes;

      // Schedule async persistence to SQLite (fire-and-forget).
      final bridge = CallbackBridge._instance;
      if (bridge._storage != null) {
        // ignore: unawaited_futures
        bridge._storage!.write(pathStr, dataBytes);
      }

      return 0; // OK
    } catch (_) {
      return -2; // INVALID_JSON (generic error)
    }
  }

  static int _identityResolveCallback(
    ffi.Pointer<ffi.Uint8> certId,
    int certLen,
    ffi.Pointer<ffi.Uint8> outJson,
    ffi.Pointer<ffi.Size> inoutLen,
  ) {
    // Identity resolution is not yet wired to async adapter.
    // Return NOT_FOUND to indicate no certificate available.
    return -1;
  }

  static int _identityDeriveCallback(
    ffi.Pointer<ffi.Uint8> parentCert,
    int certLen,
    ffi.Pointer<ffi.Uint8> resourceId,
    int ridLen,
    int domainFlag,
    ffi.Pointer<ffi.Uint8> outJson,
    ffi.Pointer<ffi.Size> inoutLen,
  ) {
    // Identity derivation is not yet wired to async adapter.
    return -1;
  }

  static int _anchorSubmitCallback(
    ffi.Pointer<ffi.Uint8> stateHash,
    int hashLen,
    ffi.Pointer<ffi.Uint8> metadataJson,
    int metaLen,
    ffi.Pointer<ffi.Uint8> outProof,
    ffi.Pointer<ffi.Size> inoutLen,
  ) {
    // Anchor submission — return a placeholder proof for now.
    // The real proof comes from the HttpAnchorAdapter which is
    // called by the application layer, not from within the kernel.
    try {
      final hashBytes = Uint8List.fromList(stateHash.asTypedList(hashLen));
      final proof = utf8.encode(
        '{"status":"pending","hash":"${_bytesToHex(hashBytes)}"}',
      );

      final maxLen = inoutLen.value;
      if (proof.length > maxLen) {
        inoutLen.value = proof.length;
        return -6; // BUFFER_TOO_SMALL
      }

      outProof.asTypedList(proof.length).setAll(0, proof);
      inoutLen.value = proof.length;
      return 0;
    } catch (_) {
      return -7; // INVALID_PROOF
    }
  }

  static int _networkPublishCallback(
    ffi.Pointer<ffi.Uint8> objectJson,
    int jsonLen,
  ) {
    // Network publish — queue for async dispatch.
    // The HttpNetworkAdapter handles actual HTTP calls.
    try {
      final jsonBytes = Uint8List.fromList(objectJson.asTypedList(jsonLen));
      _publishQueue.add(jsonBytes);
      return 0;
    } catch (_) {
      return -2;
    }
  }

  static int _networkResolveCallback(
    ffi.Pointer<ffi.Uint8> queryJson,
    int jsonLen,
    ffi.Pointer<ffi.Uint8> outResults,
    ffi.Pointer<ffi.Size> inoutLen,
  ) {
    // Network resolve — return empty results for sync context.
    // Real resolution happens via the HttpNetworkAdapter asynchronously.
    try {
      final empty = utf8.encode('{"results":[]}');
      final maxLen = inoutLen.value;
      if (empty.length > maxLen) {
        inoutLen.value = empty.length;
        return -6;
      }
      outResults.asTypedList(empty.length).setAll(0, empty);
      inoutLen.value = empty.length;
      return 0;
    } catch (_) {
      return -1;
    }
  }

  // ── Synchronous in-process storage cache ──
  //
  // The C callbacks run on the same thread as the kernel. They need
  // synchronous access to data. This Map serves as the sync cache,
  // with async persistence to SQLite happening in the background.

  static final Map<String, Uint8List> _syncStorage = {};

  /// Pre-load data from the SQLite adapter into the sync cache.
  /// Call this before kernel operations to ensure data is available.
  Future<void> preloadStorage(List<String> paths) async {
    final storage = _storage;
    if (storage == null) return;

    for (final path in paths) {
      final data = await storage.read(path);
      if (data != null) {
        _syncStorage[path] = data;
      }
    }
  }

  /// Flush the sync cache to persistent storage.
  Future<void> flushStorage() async {
    final storage = _storage;
    if (storage == null) return;

    for (final entry in _syncStorage.entries) {
      await storage.write(entry.key, entry.value);
    }
  }

  /// Get the publish queue for async dispatch by the network adapter.
  static List<Uint8List> drainPublishQueue() {
    final items = List<Uint8List>.from(_publishQueue);
    _publishQueue.clear();
    return items;
  }

  static final List<Uint8List> _publishQueue = [];

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

```
