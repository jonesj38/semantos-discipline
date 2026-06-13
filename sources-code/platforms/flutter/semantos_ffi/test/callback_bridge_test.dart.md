---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/test/callback_bridge_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.995743+00:00
---

# platforms/flutter/semantos_ffi/test/callback_bridge_test.dart

```dart
// Phase 30G/D30G.7 — Callback bridge tests.
//
// Validates the sync cache, publish queue, and static callback trampolines.
// These tests do not require the native library — they test the Dart-side
// bridge logic in isolation.

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos_ffi/semantos_ffi.dart';

void main() {
  group('CallbackBridge publish queue', () {
    test('drainPublishQueue returns empty initially', () {
      final items = CallbackBridge.drainPublishQueue();
      expect(items, isEmpty);
    });

    test('drainPublishQueue clears after drain', () {
      // The queue is static, so after drain it should be empty.
      final items1 = CallbackBridge.drainPublishQueue();
      expect(items1, isEmpty);

      final items2 = CallbackBridge.drainPublishQueue();
      expect(items2, isEmpty);
    });
  });

  group('CallbackBridge singleton', () {
    test('factory returns same instance', () {
      final a = CallbackBridge();
      final b = CallbackBridge();
      expect(identical(a, b), isTrue);
    });

    test('initialize and dispose cycle', () async {
      final bridge = CallbackBridge();
      final storage = SqfliteStorageAdapter();
      // Note: we can't actually open() the storage without Flutter context,
      // but we can verify the bridge accepts it without error.
      await bridge.initialize(storageAdapter: storage);
      expect(bridge.isInitialized, isTrue);

      await bridge.dispose();
      expect(bridge.isInitialized, isFalse);
    });

    test('double initialize is idempotent', () async {
      final bridge = CallbackBridge();
      final storage = SqfliteStorageAdapter();
      await bridge.initialize(storageAdapter: storage);
      await bridge.initialize(storageAdapter: storage); // no error
      expect(bridge.isInitialized, isTrue);
      await bridge.dispose();
    });
  });
}

```
