---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/theme/theme_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.588173+00:00
---

# cartridges/jambox/mobile/lib/src/theme/theme_service.dart

```dart
// D-O5.followup-6 — per-tenant theme fetched from the brain's
// `/api/v1/info` endpoint and applied to MaterialApp.
//
// Reference: runtime/semantos-brain/src/info_http.zig (the wire shape) and
// runtime/semantos-brain/src/tenant_manifest.zig (the canonical defaults the
// brain substitutes inline when `[theme]` is absent).
//
// ── Architecture ─────────────────────────────────────────────────────
//
// The pure-Dart core lives here (parsing, ARGB colour math, cache
// round-trip, fetch) so the unit-test suite runs under `dart test`
// without the Flutter SDK loaded.  The Flutter glue (Color / ThemeMode
// / ThemeData projections) lives in `theme_service_flutter.dart`,
// which imports `package:flutter/material.dart`; production code
// (main.dart) reaches through the Flutter wrapper.
//
// Lifecycle:
//   1. App boots → ThemeService.cached() returns the most-recent theme
//      persisted to SecureStore (or the canonical defaults if none).
//      MaterialApp builds with this immediately so the first paint
//      isn't flat material indigo.
//   2. After pairing succeeds → ThemeService.fetch() hits
//      `/api/v1/info`, persists the fresh theme, and notifies
//      listeners.  MaterialApp rebuilds with the operator's brand.
//   3. Subsequent launches start from step 1 with the cached value
//      already populated.
//
// Network failures fall back to the cached value (or the defaults if
// the cache is empty) so the app keeps rendering even when the brain
// is unreachable.  This is intentional — theme is cosmetic; an
// unavailable theme never blocks the user from filing a job.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../identity/child_cert_store.dart';

/// Named font shorthands the brain accepts.  Operators can also supply
/// a free-form CSS-style font-stack string, which we pass through to
/// the Flutter `fontFamily` slot verbatim (Flutter resolves it via the
/// platform font matcher).
enum TenantFontFamily {
  system,
  serif,
  mono,
  custom,
}

/// Theme mode selector mirroring Flutter's `ThemeMode` enum so the
/// pure-Dart core doesn't depend on `package:flutter`.  The Flutter
/// wrapper maps this to `ThemeMode` 1:1.
enum TenantThemeMode {
  /// Always render the light variant.
  light,

  /// Always render the dark variant.
  dark,

  /// Follow the OS preference (Flutter's `ThemeMode.system`).
  system,
}

/// Resolved theme, parsed from the brain's `/api/v1/info` `theme`
/// block.  Pure-data — `theme_service_flutter.dart` provides
/// `toMaterialTheme` / `toMaterialDarkTheme` projections.
class TenantTheme {
  /// 32-bit ARGB encoding of the primary brand color (matches
  /// Flutter's `Color.value`).  Stored as `int` so this module stays
  /// flutter-free.
  final int primaryArgb;

  /// 32-bit ARGB encoding of the accent color.
  final int accentArgb;

  /// `null` when no logo is configured.
  final String? logoUrl;

  final TenantFontFamily fontFamilyKind;

  /// Raw operator-supplied font-family string.  Held verbatim so
  /// `custom` round-trips the CSS-style stack to Flutter's slot.
  final String fontFamilyRaw;

  final TenantThemeMode mode;

  const TenantTheme({
    required this.primaryArgb,
    required this.accentArgb,
    required this.logoUrl,
    required this.fontFamilyKind,
    required this.fontFamilyRaw,
    required this.mode,
  });

  /// Canonical defaults — kept in sync with `tenant_manifest.zig`'s
  /// `THEME_DEFAULT_*` constants.  When `/api/v1/info` is reachable
  /// the brain substitutes its own defaults inline; this exists so a
  /// fresh-install render before the first fetch never blanks out.
  static const TenantTheme defaults = TenantTheme(
    primaryArgb: 0xFF4F46E5, // indigo-600
    accentArgb: 0xFF10B981, // emerald-500
    logoUrl: null,
    fontFamilyKind: TenantFontFamily.system,
    fontFamilyRaw: 'system',
    mode: TenantThemeMode.system,
  );

  /// Resolve `fontFamily` shorthands into Flutter's `fontFamily` slot.
  /// `system` returns null (Flutter picks the platform default), the
  /// `serif` / `mono` shorthands map to commonly-installed system
  /// faces, and `custom` is passed through verbatim.
  String? get fontFamilySlot {
    switch (fontFamilyKind) {
      case TenantFontFamily.system:
        return null;
      case TenantFontFamily.serif:
        return 'serif';
      case TenantFontFamily.mono:
        return 'monospace';
      case TenantFontFamily.custom:
        return fontFamilyRaw;
    }
  }

  /// JSON serialise for the SecureStore cache.  Round-trip via
  /// [TenantTheme.fromJson].
  Map<String, dynamic> toJson() => {
        'primary': primaryArgb,
        'accent': accentArgb,
        'logo_url': logoUrl,
        'font_family_kind': fontFamilyKind.name,
        'font_family_raw': fontFamilyRaw,
        'mode': mode.name,
      };

  factory TenantTheme.fromJson(Map<String, dynamic> json) {
    final kind = TenantFontFamily.values.firstWhere(
      (k) => k.name == json['font_family_kind'],
      orElse: () => TenantFontFamily.system,
    );
    final mode = TenantThemeMode.values.firstWhere(
      (m) => m.name == json['mode'],
      orElse: () => TenantThemeMode.system,
    );
    return TenantTheme(
      primaryArgb: (json['primary'] as int?) ?? defaults.primaryArgb,
      accentArgb: (json['accent'] as int?) ?? defaults.accentArgb,
      logoUrl: json['logo_url'] as String?,
      fontFamilyKind: kind,
      fontFamilyRaw: (json['font_family_raw'] as String?) ?? 'system',
      mode: mode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TenantTheme &&
      other.primaryArgb == primaryArgb &&
      other.accentArgb == accentArgb &&
      other.logoUrl == logoUrl &&
      other.fontFamilyKind == fontFamilyKind &&
      other.fontFamilyRaw == fontFamilyRaw &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(
      primaryArgb, accentArgb, logoUrl, fontFamilyKind, fontFamilyRaw, mode);

  @override
  String toString() =>
      'TenantTheme(primary=0x${primaryArgb.toRadixString(16)}, '
      'accent=0x${accentArgb.toRadixString(16)}, logoUrl=$logoUrl, '
      'fontFamily=$fontFamilyKind/$fontFamilyRaw, mode=$mode)';
}

/// Parse the wire-shape `theme` block returned by `/api/v1/info`.
/// Tolerant of missing/extra fields so a future brain rev can add new
/// theme properties without breaking older mobile clients.
TenantTheme parseTenantTheme(Map<String, dynamic> infoBody) {
  final raw = infoBody['theme'];
  if (raw is! Map) return TenantTheme.defaults;
  final t = Map<String, dynamic>.from(raw);
  final primary =
      _parseHexArgb(t['primary_hex']) ?? TenantTheme.defaults.primaryArgb;
  final accent =
      _parseHexArgb(t['accent_hex']) ?? TenantTheme.defaults.accentArgb;
  final logo = t['logo_url'];
  final logoUrl = logo is String && logo.isNotEmpty ? logo : null;
  final ffRaw =
      (t['font_family'] is String && (t['font_family'] as String).isNotEmpty)
          ? t['font_family'] as String
          : 'system';
  final ffKind = _parseFontFamilyKind(ffRaw);
  final modeRaw = (t['mode'] is String) ? t['mode'] as String : 'auto';
  final mode = _parseMode(modeRaw);
  return TenantTheme(
    primaryArgb: primary,
    accentArgb: accent,
    logoUrl: logoUrl,
    fontFamilyKind: ffKind,
    fontFamilyRaw: ffRaw,
    mode: mode,
  );
}

/// Parse a `#RRGGBB` hex color into a 32-bit ARGB int (alpha 0xFF).
/// Returns null on malformed input — callers fall back to the default.
int? _parseHexArgb(dynamic value) {
  if (value is! String) return null;
  if (value.length != 7 || !value.startsWith('#')) return null;
  final hex = value.substring(1);
  final v = int.tryParse(hex, radix: 16);
  if (v == null) return null;
  return 0xFF000000 | v;
}

TenantFontFamily _parseFontFamilyKind(String raw) {
  switch (raw) {
    case 'system':
      return TenantFontFamily.system;
    case 'serif':
      return TenantFontFamily.serif;
    case 'mono':
      return TenantFontFamily.mono;
    default:
      return TenantFontFamily.custom;
  }
}

TenantThemeMode _parseMode(String raw) {
  switch (raw) {
    case 'light':
      return TenantThemeMode.light;
    case 'dark':
      return TenantThemeMode.dark;
    case 'auto':
      return TenantThemeMode.system;
    default:
      return TenantThemeMode.system;
  }
}

/// SecureStore slot name for the JSON-encoded cached theme.  Versioned
/// so a future schema rev can be migrated without colliding.
const _themeCacheKey = 'd-o5.followup-6.v1.tenant_theme';

/// Pure-Dart core for the theme service.  `ThemeService` (the
/// Flutter-aware wrapper) lives in `theme_service_flutter.dart` and
/// adds the `ValueNotifier<TenantTheme>` surface that
/// `ValueListenableBuilder` consumes in MaterialApp.  Splitting the
/// two lets `dart test` exercise parse + cache + fetch without
/// pulling in `package:flutter/material.dart`.
class ThemeServiceCore {
  final ChildCertStore certStore;
  final SecureStore secureStore;
  final Dio dio;

  /// The most-recently-resolved theme.  Seeded with
  /// [TenantTheme.defaults]; [warmFromCache] overwrites this with the
  /// SecureStore-cached value before the first paint.
  TenantTheme current = TenantTheme.defaults;

  /// Fired on every successful theme update.  The Flutter wrapper
  /// adapts this to a `ValueNotifier`; pure-Dart consumers can
  /// listen directly.
  final StreamController<TenantTheme> _changes =
      StreamController<TenantTheme>.broadcast();

  Stream<TenantTheme> get changes => _changes.stream;

  ThemeServiceCore({
    required this.certStore,
    required this.secureStore,
    required this.dio,
  });

  /// Read the persisted theme out of the SecureStore.  Returns null
  /// when no cache exists (fresh install) or when the cached blob
  /// fails to decode.
  Future<TenantTheme?> cached() async {
    final raw = await secureStore.read(_themeCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = json.decode(raw) as Map<String, dynamic>;
      return TenantTheme.fromJson(parsed);
    } catch (_) {
      return null;
    }
  }

  /// Apply the SecureStore-cached value to [current].  Called at app
  /// boot so the first MaterialApp render uses the operator's brand
  /// even before [fetch] resolves.
  Future<void> warmFromCache() async {
    final c = await cached();
    if (c != null) {
      current = c;
      _changes.add(c);
    }
  }

  /// Round-trip `/api/v1/info` and update [current] on success.
  /// Falls back to the cached value on any failure (network error,
  /// 401, malformed body); falls back to [TenantTheme.defaults] when
  /// no cache exists.
  Future<TenantTheme> fetch() async {
    final record = await certStore.read();
    if (record == null) {
      // Not paired — nothing to fetch.  Return the current value.
      return current;
    }
    try {
      final url = '${record.brainPairEndpoint}/api/v1/info';
      final resp = await dio.getUri<Map<String, dynamic>>(
        Uri.parse(url),
        options: Options(
          headers: {'authorization': 'Bearer ${record.bearer}'},
          responseType: ResponseType.json,
        ),
      );
      if (resp.statusCode == null ||
          resp.statusCode! < 200 ||
          resp.statusCode! >= 300) {
        throw _ThemeFetchError('non-2xx: ${resp.statusCode}');
      }
      final body = resp.data;
      if (body == null) throw _ThemeFetchError('empty body');
      final fresh = parseTenantTheme(body);
      current = fresh;
      _changes.add(fresh);
      // Best-effort persist; ignore SecureStore failures.
      try {
        await secureStore.write(_themeCacheKey, json.encode(fresh.toJson()));
      } catch (_) {}
      return fresh;
    } catch (_) {
      final c = await cached();
      if (c != null) {
        current = c;
        _changes.add(c);
        return c;
      }
      return current;
    }
  }

  void dispose() {
    _changes.close();
  }
}

class _ThemeFetchError implements Exception {
  final String message;
  _ThemeFetchError(this.message);
  @override
  String toString() => 'ThemeFetchError($message)';
}

```
