---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/test/bindings_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.996020+00:00
---

# platforms/flutter/semantos_ffi/test/bindings_test.dart

```dart
// Phase 30G/D30G.7 — FFI bindings tests.
//
// Validates that the native library loads and all function symbols resolve.
// Uses the macOS dylib built from src/ffi/ via `zig build dylib`.

import 'dart:ffi' as ffi;
import 'dart:io' show Directory, Platform;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos_ffi/semantos_ffi.dart';

/// Resolve the absolute path to the test dylib.
/// Walks up from the test file to find the repo root's zig-out.
String _testLibPath() {
  // Find repo root by walking up from this package's directory.
  var dir = Directory.current;
  // If CWD is the package dir, go up to repo root.
  // Package: <repo>/platforms/flutter/semantos_ffi
  // Library: <repo>/src/ffi/zig-out/lib/libsemantos.{dylib,so}
  var root = dir.path;
  // Try to find src/ffi/zig-out from CWD or parent dirs.
  for (var i = 0; i < 6; i++) {
    final candidate = '$root/src/ffi/zig-out/lib';
    if (Directory(candidate).existsSync()) {
      if (Platform.isMacOS) return '$candidate/libsemantos.dylib';
      if (Platform.isLinux) return '$candidate/libsemantos.so';
    }
    root = Directory(root).parent.path;
  }
  throw StateError(
    'Could not find libsemantos in zig-out. '
    'Run `zig build dylib` in src/ffi/ first. CWD: ${dir.path}',
  );
}

void main() {
  late SemantosBindings bindings;

  setUpAll(() {
    bindings = SemantosBindings.fromPath(_testLibPath());
  });

  group('Library loading', () {
    test('loads the native library without error', () {
      expect(bindings, isNotNull);
    });

    test('semantos_version returns a non-empty string', () {
      final versionPtr = bindings.semantosVersion();
      expect(versionPtr, isNot(equals(ffi.nullptr)));
      final version = versionPtr.toDartString();
      expect(version, isNotEmpty);
      // Version format: "X.Y.Z-phase-NNx" (e.g., "0.30.0-phase-30d")
      expect(version, matches(RegExp(r'\d+\.\d+\.\d+')));
    });
  });

  group('Function lookup', () {
    test('all core functions resolve', () {
      // These will throw if the symbol is not found, so simply
      // accessing them validates the lookup.
      expect(bindings.semantosInit, isNotNull);
      expect(bindings.semantosShutdown, isNotNull);
      expect(bindings.semantosCellWrite, isNotNull);
      expect(bindings.semantosCellRead, isNotNull);
      expect(bindings.semantosCellVerify, isNotNull);
      expect(bindings.semantosFree, isNotNull);
      expect(bindings.semantosVersion, isNotNull);
      expect(bindings.semantosLastError, isNotNull);
    });

    test('capability functions resolve', () {
      expect(bindings.semantosCapabilityCheck, isNotNull);
      expect(bindings.semantosCapabilityPresent, isNotNull);
    });

    test('anchor functions resolve', () {
      expect(bindings.semantosAnchorBatch, isNotNull);
      expect(bindings.semantosAnchorVerify, isNotNull);
    });

    test('linearity function resolves', () {
      expect(bindings.semantosLinearConsume, isNotNull);
    });

    test('callback registration function resolves', () {
      expect(bindings.semantosRegisterCallbacks, isNotNull);
    });
  });
}

```
