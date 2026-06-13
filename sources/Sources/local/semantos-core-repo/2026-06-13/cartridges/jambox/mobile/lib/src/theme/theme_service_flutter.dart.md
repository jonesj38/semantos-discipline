---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/theme/theme_service_flutter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.587855+00:00
---

# cartridges/jambox/mobile/lib/src/theme/theme_service_flutter.dart

```dart
// D-O5.followup-6 — Flutter glue around the pure-Dart ThemeServiceCore.
//
// This file is the only theme-related module that imports
// `package:flutter/material.dart`; pure-Dart unit tests reach into
// `theme_service.dart` directly and stay flutter-free.
//
// The wrapper:
//   • Adapts the core's `Stream<TenantTheme>` to a
//     `ValueNotifier<TenantTheme>` that ValueListenableBuilder consumes.
//   • Projects `TenantTheme` to Flutter's `ThemeData` / `ThemeMode` so
//     MaterialApp can bind to it directly.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../identity/child_cert_store.dart';
import 'theme_service.dart';

export 'theme_service.dart' show TenantTheme, TenantFontFamily, TenantThemeMode;

/// Project a [TenantThemeMode] to Flutter's [ThemeMode].
ThemeMode toFlutterThemeMode(TenantThemeMode m) {
  switch (m) {
    case TenantThemeMode.light:
      return ThemeMode.light;
    case TenantThemeMode.dark:
      return ThemeMode.dark;
    case TenantThemeMode.system:
      return ThemeMode.system;
  }
}

/// Project a [TenantTheme] to Flutter's [ThemeData] (light variant).
ThemeData toMaterialTheme(TenantTheme t) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Color(t.primaryArgb),
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    fontFamily: t.fontFamilySlot,
  );
}

/// Project a [TenantTheme] to Flutter's [ThemeData] (dark variant).
ThemeData toMaterialDarkTheme(TenantTheme t) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Color(t.primaryArgb),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    fontFamily: t.fontFamilySlot,
  );
}

/// Production-side ThemeService — wraps [ThemeServiceCore] with a
/// `ValueNotifier<TenantTheme>` that MaterialApp's
/// `ValueListenableBuilder` binds to.
class ThemeService {
  final ThemeServiceCore _core;

  /// Notifies listeners on every successful theme update.  Seeded
  /// with [TenantTheme.defaults] so the first MaterialApp build never
  /// sees null.
  final ValueNotifier<TenantTheme> theme;

  ThemeService({
    required ChildCertStore certStore,
    required SecureStore secureStore,
    required Dio dio,
  })  : _core = ThemeServiceCore(
          certStore: certStore,
          secureStore: secureStore,
          dio: dio,
        ),
        theme = ValueNotifier<TenantTheme>(TenantTheme.defaults) {
    _core.changes.listen((fresh) {
      theme.value = fresh;
    });
  }

  /// Read the persisted theme out of the SecureStore.  Returns null
  /// when no cache exists.
  Future<TenantTheme?> cached() => _core.cached();

  /// Apply the SecureStore-cached value to the [theme] notifier.
  Future<void> warmFromCache() => _core.warmFromCache();

  /// Round-trip `/api/v1/info`, update the [theme] notifier on
  /// success, and return the fresh theme.
  Future<TenantTheme> fetch() => _core.fetch();

  void dispose() {
    _core.dispose();
    theme.dispose();
  }
}

```
