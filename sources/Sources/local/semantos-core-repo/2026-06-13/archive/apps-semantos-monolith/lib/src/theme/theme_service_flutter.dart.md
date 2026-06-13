---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/theme/theme_service_flutter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.861992+00:00
---

# archive/apps-semantos-monolith/lib/src/theme/theme_service_flutter.dart

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
//   • When the tenant uses the canonical Helm v7 palette (the defaults),
//     `_buildHelmDark` returns a hand-tuned ThemeData that matches the
//     cockpit aesthetic exactly — every surface and chrome token is
//     wired to the Helm v7 colour constants rather than derived by
//     Material's seed algorithm.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../identity/child_cert_store.dart';
import 'theme_service.dart';

export 'theme_service.dart' show TenantTheme, TenantFontFamily, TenantThemeMode;

// ── Helm v7 palette constants ─────────────────────────────────────────────
// Kept in sync with app.css / theme-store.ts canonical defaults.

const _kVoid        = Color(0xFF0d1014);
const _kShell       = Color(0xFF14181e);
const _kShell2      = Color(0xFF1a1f27);
const _kShell3      = Color(0xFF232932);
const _kRule        = Color(0xFF2a3340);
const _kRuleBright  = Color(0xFF3a4555);
const _kInk         = Color(0xFFe7eef5);
const _kInkSoft     = Color(0xFFaab6c4);
const _kInkFaint    = Color(0xFF6b7889);
const _kActivation  = Color(0xFF7fd9ff);   // primary / ice cyan
const _kLinear      = Color(0xFFffb24a);   // secondary / amber commit gate
const _kHold        = Color(0xFF6fd6b5);   // tertiary / teal

// ─────────────────────────────────────────────────────────────────────────

const ColorScheme _helmDarkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: _kActivation,
  onPrimary: _kVoid,
  primaryContainer: Color(0xFF1a3040),
  onPrimaryContainer: _kActivation,
  secondary: _kLinear,
  onSecondary: _kVoid,
  secondaryContainer: Color(0xFF2e2010),
  onSecondaryContainer: _kLinear,
  tertiary: _kHold,
  onTertiary: _kVoid,
  tertiaryContainer: Color(0xFF152b24),
  onTertiaryContainer: _kHold,
  error: Color(0xFFcf6679),
  onError: _kVoid,
  errorContainer: Color(0xFF3a1020),
  onErrorContainer: Color(0xFFcf6679),
  surface: _kShell,
  onSurface: _kInk,
  surfaceContainerLowest: _kVoid,
  surfaceContainerLow: _kShell,
  surfaceContainer: _kShell2,
  surfaceContainerHigh: _kShell3,
  surfaceContainerHighest: _kShell3,
  onSurfaceVariant: _kInkSoft,
  outline: _kRule,
  outlineVariant: _kRuleBright,
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: _kInk,
  onInverseSurface: _kVoid,
  inversePrimary: Color(0xFF005070),
);

ThemeData _buildHelmDark(String? fontFamily) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: _helmDarkScheme,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: _kVoid,
    appBarTheme: const AppBarTheme(
      backgroundColor: _kShell,
      foregroundColor: _kInk,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: _kInk,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.12,
      ),
      iconTheme: IconThemeData(color: _kInkSoft),
      actionsIconTheme: IconThemeData(color: _kInkSoft),
    ),
    cardTheme: const CardThemeData(
      color: _kShell,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: _kRule),
      ),
      margin: EdgeInsets.symmetric(vertical: 4),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _kShell,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Color(0x287fd9ff), // activation @ 16 %
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: _kActivation, size: 22);
        }
        return const IconThemeData(color: _kInkFaint, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final base = const TextStyle(fontSize: 10, letterSpacing: 0.06);
        if (states.contains(WidgetState.selected)) {
          return base.copyWith(color: _kActivation, fontWeight: FontWeight.w600);
        }
        return base.copyWith(color: _kInkFaint);
      }),
      elevation: 0,
      height: 60,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _kShell2,
      selectedColor: const Color(0x287fd9ff),
      surfaceTintColor: Colors.transparent,
      labelStyle: const TextStyle(fontSize: 10, color: _kInkSoft),
      secondaryLabelStyle: const TextStyle(fontSize: 10, color: _kActivation),
      side: const BorderSide(color: _kRule),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: _kShell2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: _kRule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: _kRule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: _kActivation),
      ),
      hintStyle: TextStyle(color: _kInkFaint, fontSize: 13),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _kActivation,
      foregroundColor: _kVoid,
      elevation: 0,
      highlightElevation: 2,
      shape: CircleBorder(),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: _kShell3,
      contentTextStyle: TextStyle(color: _kInk, fontSize: 13),
      actionTextColor: _kActivation,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: _kRule),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: _kRule,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
      selectedTileColor: Color(0x147fd9ff),
      iconColor: _kInkFaint,
      textColor: _kInk,
      subtitleTextStyle: TextStyle(color: _kInkSoft, fontSize: 12),
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(color: _kInk, fontSize: 16, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: _kInk, fontSize: 14, fontWeight: FontWeight.w500),
      titleSmall: TextStyle(color: _kInkSoft, fontSize: 12, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(color: _kInk, fontSize: 14),
      bodyMedium: TextStyle(color: _kInkSoft, fontSize: 13),
      bodySmall: TextStyle(color: _kInkFaint, fontSize: 12),
      labelLarge: TextStyle(color: _kInk, fontSize: 11, letterSpacing: 0.08),
      labelMedium: TextStyle(color: _kInkSoft, fontSize: 10, letterSpacing: 0.06),
      labelSmall: TextStyle(color: _kInkFaint, fontSize: 10, letterSpacing: 0.1),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────

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
/// For operator-customised tenants only — the canonical Helm v7 palette
/// has no light variant, so we fall through to a seeded scheme.
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
/// When the tenant is using the canonical Helm v7 defaults the hand-tuned
/// cockpit theme is returned; otherwise a seed-derived scheme is used so
/// the operator's primary colour is honoured.
ThemeData toMaterialDarkTheme(TenantTheme t) {
  if (t.primaryArgb == TenantTheme.defaults.primaryArgb &&
      t.accentArgb == TenantTheme.defaults.accentArgb) {
    return _buildHelmDark(t.fontFamilySlot);
  }
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
