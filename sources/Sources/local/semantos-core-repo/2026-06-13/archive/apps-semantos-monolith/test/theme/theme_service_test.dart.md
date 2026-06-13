---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/theme/theme_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.905187+00:00
---

# archive/apps-semantos-monolith/test/theme/theme_service_test.dart

```dart
// D-O5.followup-6 — theme_service unit tests.
//
// Covers parseTenantTheme + ThemeServiceCore.cached / .fetch end-to-end
// against a Dio HttpClientAdapter test double + the in-memory
// SecureStore.  Pure-Dart so the suite runs under `dart test` without
// the Flutter SDK runtime — Flutter projections (Color, ThemeMode,
// ThemeData) live in `theme_service_flutter.dart` and are exercised
// indirectly by the Flutter widget test path.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:semantos/src/theme/theme_service.dart';

final _bearer64 = 'beef' * 16;

ChildCertRecord _testRecord({String? bearer}) {
  return ChildCertRecord(
    devicePrivHex: '00' * 32,
    childPubHex: '02${'aa' * 32}',
    operatorRootPub: '02${'bb' * 32}',
    operatorCertId: 'aabbccddeeff00112233445566778899',
    contextTag: 0,
    label: 'phone',
    capabilities: const ['cap.attach.photo'],
    brainPairEndpoint: 'https://acme.example',
    brainWssEndpoint: 'wss://acme.example/api/v1/wallet',
    brainPinCertId: 'aabbccddeeff00112233445566778899',
    brainPinPubkey: '02${'bb' * 32}',
    bearer: bearer ?? _bearer64,
  );
}

void main() {
  group('parseTenantTheme', () {
    test('missing theme block → defaults', () {
      final t = parseTenantTheme({'shard_proxy_endpoint': null});
      expect(t, equals(TenantTheme.defaults));
    });

    test('full block parses every field', () {
      final t = parseTenantTheme({
        'theme': {
          'primary_hex': '#FF6F61',
          'accent_hex': '#2EC4B6',
          'logo_url': '/branding/acme.svg',
          'font_family': 'serif',
          'mode': 'dark',
        },
      });
      expect(t.primaryArgb, equals(0xFFFF6F61));
      expect(t.accentArgb, equals(0xFF2EC4B6));
      expect(t.logoUrl, equals('/branding/acme.svg'));
      expect(t.fontFamilyKind, equals(TenantFontFamily.serif));
      expect(t.mode, equals(TenantThemeMode.dark));
    });

    test('logo_url null → TenantTheme.logoUrl null', () {
      final t = parseTenantTheme({
        'theme': {
          'primary_hex': '#000000',
          'accent_hex': '#FFFFFF',
          'logo_url': null,
          'font_family': 'system',
          'mode': 'auto',
        },
      });
      expect(t.logoUrl, isNull);
      expect(t.mode, equals(TenantThemeMode.system));
    });

    test('arbitrary font_family stack → TenantFontFamily.custom', () {
      final t = parseTenantTheme({
        'theme': {
          'font_family': 'Roboto, sans-serif',
          'primary_hex': '#000000',
          'accent_hex': '#FFFFFF',
        },
      });
      expect(t.fontFamilyKind, equals(TenantFontFamily.custom));
      expect(t.fontFamilyRaw, equals('Roboto, sans-serif'));
      expect(t.fontFamilySlot, equals('Roboto, sans-serif'));
    });

    test('malformed primary_hex → falls back to default primary', () {
      final t = parseTenantTheme({
        'theme': {
          'primary_hex': 'not-a-color',
          'accent_hex': '#10B981',
          'mode': 'auto',
        },
      });
      expect(t.primaryArgb, equals(TenantTheme.defaults.primaryArgb));
      expect(t.accentArgb, equals(0xFF10B981));
    });
  });

  group('ThemeServiceCore', () {
    late InMemorySecureStore secureStore;
    late ChildCertStore certStore;

    setUp(() {
      secureStore = InMemorySecureStore();
      certStore = ChildCertStore(secureStore);
    });

    test('cached() returns null on a fresh install', () async {
      final svc = ThemeServiceCore(
        certStore: certStore,
        secureStore: secureStore,
        dio: Dio(),
      );
      expect(await svc.cached(), isNull);
      svc.dispose();
    });

    test('cached() round-trips a previously persisted theme', () async {
      final fresh = TenantTheme(
        primaryArgb: 0xFFFF6F61,
        accentArgb: 0xFF2EC4B6,
        logoUrl: '/logo.svg',
        fontFamilyKind: TenantFontFamily.serif,
        fontFamilyRaw: 'serif',
        mode: TenantThemeMode.dark,
      );
      // Direct write so we don't need to stand up a fetch round.
      await secureStore.write(
          'd-o5.followup-6.v1.tenant_theme', json.encode(fresh.toJson()));

      final svc = ThemeServiceCore(
        certStore: certStore,
        secureStore: secureStore,
        dio: Dio(),
      );
      final c = await svc.cached();
      expect(c, equals(fresh));
      svc.dispose();
    });

    test('fetch() posts to <brain>/api/v1/info, parses theme, persists cache',
        () async {
      await certStore.write(_testRecord());

      final adapter = _RecordingAdapter(
        statusCode: 200,
        bodyBytes: utf8.encode(json.encode({
          'shard_proxy_endpoint': null,
          'shard_group_id': '',
          'brain_pin_cert_id': 'aabbccddeeff00112233445566778899',
          'brain_pin_pubkey': '02${'bb' * 32}',
          'server_version': 'brain 0.1.0',
          'theme': {
            'primary_hex': '#FF6F61',
            'accent_hex': '#2EC4B6',
            'logo_url': '/branding/acme.svg',
            'font_family': 'mono',
            'mode': 'dark',
          },
        })),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final svc = ThemeServiceCore(
        certStore: certStore,
        secureStore: secureStore,
        dio: dio,
      );

      final t = await svc.fetch();
      expect(t.primaryArgb, equals(0xFFFF6F61));
      expect(t.fontFamilyKind, equals(TenantFontFamily.mono));
      expect(t.mode, equals(TenantThemeMode.dark));
      // Right URL hit.
      expect(adapter.lastRequest?.uri.toString(),
          equals('https://acme.example/api/v1/info'));
      // Right Authorization header sent.
      final auth =
          adapter.lastRequest?.headers['authorization']?.toString() ?? '';
      expect(auth, contains('Bearer '));
      // Persisted cache.
      final cached = await svc.cached();
      expect(cached, equals(t));
      // Notifier updated.
      expect(svc.current, equals(t));
      svc.dispose();
    });

    test('fetch() network error → falls back to cached theme', () async {
      await certStore.write(_testRecord());
      final cachedTheme = TenantTheme(
        primaryArgb: 0xFF1F6FEB,
        accentArgb: 0xFF22CC66,
        logoUrl: null,
        fontFamilyKind: TenantFontFamily.system,
        fontFamilyRaw: 'system',
        mode: TenantThemeMode.light,
      );
      await secureStore.write('d-o5.followup-6.v1.tenant_theme',
          json.encode(cachedTheme.toJson()));

      final dio = Dio()..httpClientAdapter = _ThrowingAdapter();
      final svc = ThemeServiceCore(
        certStore: certStore,
        secureStore: secureStore,
        dio: dio,
      );

      final t = await svc.fetch();
      expect(t, equals(cachedTheme));
      svc.dispose();
    });

    test('fetch() with no paired record returns the current notifier value',
        () async {
      // No record seeded → certStore.read() returns null.
      final dio = Dio()..httpClientAdapter = _ThrowingAdapter();
      final svc = ThemeServiceCore(
        certStore: certStore,
        secureStore: secureStore,
        dio: dio,
      );
      final t = await svc.fetch();
      expect(t, equals(TenantTheme.defaults));
      svc.dispose();
    });
  });
}

// ─── Adapter helpers ───────────────────────────────────────────────────

class _RecordingAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int> bodyBytes;
  RequestOptions? lastRequest;
  _RecordingAdapter({required this.statusCode, required this.bodyBytes});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromBytes(bodyBytes, statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      message: 'simulated connection failure',
      type: DioExceptionType.connectionError,
    );
  }
}

```
