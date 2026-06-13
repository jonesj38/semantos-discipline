---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/push/push_registration_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.916256+00:00
---

# archive/apps-semantos-monolith/test/push/push_registration_service_test.dart

```dart
// D-O5m.followup-9 Phase C — PushRegistrationService conformance.
//
// Pure-Dart coverage of the service's happy + degraded paths:
//
//   - Happy path: InMemoryPushAdapter returns a token, service POSTs
//     to brain, response parsed, persisted in SecureStore.
//   - Permission denied: service short-circuits without POSTing.
//   - Unsupported device: service short-circuits without POSTing.
//   - HTTP failure: service surfaces PushRegistrationFailed with the
//     status code preserved.
//   - Token refresh: stream emits new token → service POSTs.
//   - Unregister: service calls DELETE /api/v1/push-register and
//     wipes the local persisted record.
//
// Runs under `dart test` (no Flutter SDK gate) — that's why the
// service file is split from FirebasePushAdapter.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:semantos/src/push/push_platform.dart';
import 'package:semantos/src/push/push_registration_service.dart';

void main() {
  group('PushRegistrationService.registerOnPair', () {
    test('happy path POSTs token + persists registration', () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      await certStore.write(_fixtureRecord());

      final adapter = InMemoryPushAdapter(
        permissionGranted: true,
        token: 'fcm-tok-001',
        platformName: 'fcm',
      );
      final recording = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(json.encode({
          'registered': true,
          'platform': 'fcm',
          'registered_at': '2026-05-02T10:00:00Z',
        })),
      );
      final dio = Dio()..httpClientAdapter = recording;

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: adapter,
        brainBaseUrl: 'https://brain.example/',
      );

      final result = await svc.registerOnPair();
      expect(result, isA<PushRegistered>());
      final ok = result as PushRegistered;
      expect(ok.token, equals('fcm-tok-001'));
      expect(ok.platform, equals('fcm'));
      expect(ok.registeredAt, equals('2026-05-02T10:00:00Z'));

      // Wire-shape assertions.
      final req = recording.lastRequest!;
      expect(req.method, equalsIgnoringCase('post'));
      expect(req.uri.toString(),
          equals('https://brain.example/api/v1/push-register'));
      expect(req.headers['authorization'], startsWith('Bearer '));
      final body = req.data as Map;
      expect(body['cert_id'], equals(_fixtureRecord().operatorCertId));
      expect(body['platform'], equals('fcm'));
      expect(body['token'], equals('fcm-tok-001'));

      // Persisted state matches.
      final persisted = await svc.readPersisted();
      expect(persisted.platform, equals(PushPlatform.fcm));
      expect(persisted.token, equals('fcm-tok-001'));
      expect(persisted.registeredAt, equals('2026-05-02T10:00:00Z'));
      expect(persisted.isRegistered, isTrue);
    });

    test('permission denied returns PushPermissionDenied without HTTP',
        () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      await certStore.write(_fixtureRecord());

      final adapter = InMemoryPushAdapter(permissionGranted: false);
      final recording = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(json.encode({'registered': true})),
      );
      final dio = Dio()..httpClientAdapter = recording;

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: adapter,
        brainBaseUrl: 'https://brain.example',
      );

      final result = await svc.registerOnPair();
      expect(result, isA<PushPermissionDenied>());
      // No HTTP request should have fired.
      expect(recording.lastRequest, isNull);
      // Nothing persisted.
      final persisted = await svc.readPersisted();
      expect(persisted.isRegistered, isFalse);
    });

    test('unsupported device (null token) returns PushUnsupported',
        () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      await certStore.write(_fixtureRecord());

      final adapter = InMemoryPushAdapter(unsupported: true);
      final recording = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(json.encode({'registered': true})),
      );
      final dio = Dio()..httpClientAdapter = recording;

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: adapter,
        brainBaseUrl: 'https://brain.example',
      );

      final result = await svc.registerOnPair();
      expect(result, isA<PushUnsupported>());
      expect(recording.lastRequest, isNull);
    });

    test('HTTP 401 returns PushRegistrationFailed with statusCode',
        () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      await certStore.write(_fixtureRecord());

      final adapter = InMemoryPushAdapter(
        permissionGranted: true,
        token: 'tok-401',
      );
      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 401,
          body: utf8.encode(json.encode({'error': 'unauthorised'})),
        );

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: adapter,
        brainBaseUrl: 'https://brain.example',
      );

      final result = await svc.registerOnPair();
      expect(result, isA<PushRegistrationFailed>());
      final fail = result as PushRegistrationFailed;
      expect(fail.statusCode, equals(401));
      expect(fail.reason, contains('unauthorised'));

      // Local registration NOT persisted on a failed HTTP.
      final persisted = await svc.readPersisted();
      expect(persisted.isRegistered, isFalse);
    });

    test(
        'cert not yet persisted returns PushRegistrationFailed without HTTP',
        () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      // Note: NO certStore.write — the device hasn't paired yet.

      final adapter = InMemoryPushAdapter();
      final recording = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode('{}'),
      );
      final dio = Dio()..httpClientAdapter = recording;

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: adapter,
        brainBaseUrl: 'https://brain.example',
      );

      final result = await svc.registerOnPair();
      expect(result, isA<PushRegistrationFailed>());
      expect(recording.lastRequest, isNull);
    });
  });

  group('PushRegistrationService token refresh', () {
    test('emits the rotated token on the brain', () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      await certStore.write(_fixtureRecord());

      final adapter = InMemoryPushAdapter(token: 'tok-original');
      final recording = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(json.encode({
          'registered': true,
          'platform': 'fcm',
          'registered_at': '2026-05-02T10:00:00Z',
        })),
      );
      final dio = Dio()..httpClientAdapter = recording;

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: adapter,
        brainBaseUrl: 'https://brain.example',
      );

      svc.startTokenRefreshListener();
      adapter.emitTokenRefresh('tok-rotated-001');
      // Allow the listener microtask to drain.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(recording.lastRequest, isNotNull);
      final body = recording.lastRequest!.data as Map;
      expect(body['token'], equals('tok-rotated-001'));

      await svc.stop();
      await adapter.dispose();
    });
  });

  group('PushRegistrationService backend preference (D.3)', () {
    test('readBackendPreference defaults to unifiedpush for new installs',
        () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      final adapter = InMemoryPushAdapter();
      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: Dio(),
        adapter: adapter,
        brainBaseUrl: 'https://brain.example',
      );
      expect(
        await svc.readBackendPreference(),
        equals(PushBackendPreference.unifiedpush),
      );
    });

    test('writeBackendPreference round-trips through SecureStore', () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: Dio(),
        adapter: InMemoryPushAdapter(),
        brainBaseUrl: 'https://brain.example',
      );
      await svc.writeBackendPreference(PushBackendPreference.fcm);
      expect(
        await svc.readBackendPreference(),
        equals(PushBackendPreference.fcm),
      );
      await svc.writeBackendPreference(PushBackendPreference.unifiedpush);
      expect(
        await svc.readBackendPreference(),
        equals(PushBackendPreference.unifiedpush),
      );
    });

    test('registerOnPair falls back to FCM when UP returns no token',
        () async {
      // Sovereign-push D.3 — operator chose UnifiedPush but no
      // distributor is installed.  Primary adapter
      // (`platformName=unifiedpush`) returns null on getDeviceToken;
      // service silently swaps to the fallback (FCM) adapter and
      // POSTs with platform=fcm.  lastUsedFallback flips to true so
      // the SettingsScreen renders the "install a distributor" hint.
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      await certStore.write(_fixtureRecord());

      final upAdapter = InMemoryPushAdapter(
        permissionGranted: true,
        token: null, // no distributor installed
        platformName: 'unifiedpush',
        unsupported: true,
      );
      final fcmAdapter = InMemoryPushAdapter(
        permissionGranted: true,
        token: 'fcm-tok-fallback',
        platformName: 'fcm',
      );
      final recording = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(json.encode({
          'registered': true,
          'platform': 'fcm',
          'registered_at': '2026-05-02T10:00:00Z',
        })),
      );
      final dio = Dio()..httpClientAdapter = recording;

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: upAdapter,
        fallbackAdapter: fcmAdapter,
        brainBaseUrl: 'https://brain.example',
      );

      final result = await svc.registerOnPair();
      expect(result, isA<PushRegistered>());
      expect(svc.lastUsedFallback, isTrue);
      expect(svc.activeBackendName, equals('fcm'));

      // The HTTP body MUST carry platform=fcm and the FCM token,
      // not the UP empty endpoint.
      final body = recording.lastRequest!.data as Map;
      expect(body['platform'], equals('fcm'));
      expect(body['token'], equals('fcm-tok-fallback'));
    });

    test('registerOnPair uses primary directly when it has a token', () async {
      // Both adapters available; primary returns a token; fallback
      // is never consulted.
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      await certStore.write(_fixtureRecord());

      final upAdapter = InMemoryPushAdapter(
        permissionGranted: true,
        token: 'https://ntfy.example/UP-OK',
        platformName: 'unifiedpush',
      );
      final fcmAdapter = InMemoryPushAdapter(
        permissionGranted: true,
        token: 'fcm-should-not-be-used',
        platformName: 'fcm',
      );
      final recording = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(json.encode({
          'registered': true,
          'platform': 'unifiedpush',
          'registered_at': '2026-05-02T10:00:00Z',
        })),
      );
      final dio = Dio()..httpClientAdapter = recording;

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: upAdapter,
        fallbackAdapter: fcmAdapter,
        brainBaseUrl: 'https://brain.example',
      );

      final result = await svc.registerOnPair();
      expect(result, isA<PushRegistered>());
      expect(svc.lastUsedFallback, isFalse);
      expect(svc.activeBackendName, equals('unifiedpush'));

      final body = recording.lastRequest!.data as Map;
      expect(body['platform'], equals('unifiedpush'));
      expect(body['token'], equals('https://ntfy.example/UP-OK'));
    });

    test('registerOnPair returns PushUnsupported when neither adapter has token',
        () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      await certStore.write(_fixtureRecord());

      final upAdapter = InMemoryPushAdapter(unsupported: true);
      final fcmAdapter = InMemoryPushAdapter(unsupported: true);
      final recording = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode('{}'),
      );
      final dio = Dio()..httpClientAdapter = recording;

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: upAdapter,
        fallbackAdapter: fcmAdapter,
        brainBaseUrl: 'https://brain.example',
      );

      final result = await svc.registerOnPair();
      expect(result, isA<PushUnsupported>());
      // Neither adapter produced a token → no HTTP fired.
      expect(recording.lastRequest, isNull);
    });

    test('swapAdapters changes active adapter for next registerOnPair call',
        () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      await certStore.write(_fixtureRecord());

      final initial = InMemoryPushAdapter(
        token: 'tok-initial',
        platformName: 'fcm',
      );
      final swapped = InMemoryPushAdapter(
        token: 'https://ntfy.example/UP-AFTER',
        platformName: 'unifiedpush',
      );

      final dio = Dio()
        ..httpClientAdapter = _SequenceAdapter([
          _ScriptedResponse(
            statusCode: 200,
            body: utf8.encode(json.encode({
              'registered': true,
              'platform': 'fcm',
              'registered_at': '2026-05-02T10:00:00Z',
            })),
          ),
          _ScriptedResponse(
            statusCode: 200,
            body: utf8.encode(json.encode({
              'registered': true,
              'platform': 'unifiedpush',
              'registered_at': '2026-05-02T11:00:00Z',
            })),
          ),
        ]);

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: initial,
        brainBaseUrl: 'https://brain.example',
      );

      await svc.registerOnPair();
      expect(svc.activeBackendName, equals('fcm'));

      svc.swapAdapters(primary: swapped);
      await svc.registerOnPair();
      expect(svc.activeBackendName, equals('unifiedpush'));

      final adapterAsSeq = (dio.httpClientAdapter as _SequenceAdapter);
      expect(adapterAsSeq.requests.length, equals(2));
      final body2 = adapterAsSeq.requests[1].data as Map;
      expect(body2['platform'], equals('unifiedpush'));
      expect(body2['token'], equals('https://ntfy.example/UP-AFTER'));
    });
  });

  group('PushRegistrationService.unregister', () {
    test('calls DELETE /api/v1/push-register and wipes local record',
        () async {
      final secure = InMemorySecureStore();
      final certStore = ChildCertStore(secure);
      await certStore.write(_fixtureRecord());

      final adapter = InMemoryPushAdapter(token: 'tok-1');
      // Register first to populate persisted state.
      final dio = Dio()
        ..httpClientAdapter = _SequenceAdapter([
          // POST register.
          _ScriptedResponse(
            statusCode: 200,
            body: utf8.encode(json.encode({
              'registered': true,
              'platform': 'fcm',
              'registered_at': '2026-05-02T10:00:00Z',
            })),
          ),
          // DELETE unregister.
          _ScriptedResponse(
            statusCode: 200,
            body: utf8.encode(json.encode({'registered': false})),
          ),
        ]);

      final svc = PushRegistrationService(
        certStore: certStore,
        secureStore: secure,
        dio: dio,
        adapter: adapter,
        brainBaseUrl: 'https://brain.example',
      );

      await svc.registerOnPair();
      expect((await svc.readPersisted()).isRegistered, isTrue);

      await svc.unregister();
      final after = await svc.readPersisted();
      expect(after.isRegistered, isFalse);
      expect(after.platform, equals(PushPlatform.none));

      // Two requests fired — POST + DELETE.
      final adapterAsSeq = (dio.httpClientAdapter as _SequenceAdapter);
      expect(adapterAsSeq.requests.length, equals(2));
      expect(adapterAsSeq.requests[1].method, equalsIgnoringCase('delete'));
      expect(adapterAsSeq.requests[1].uri.path,
          equals('/api/v1/push-register'));
    });
  });
}

// ─── fixtures + adapters ─────────────────────────────────────────────

ChildCertRecord _fixtureRecord() {
  return ChildCertRecord(
    devicePrivHex: 'aa' * 32,
    childPubHex: '02${'bb' * 32}',
    operatorRootPub: '03${'cc' * 32}',
    operatorCertId: 'cc' * 16,
    contextTag: 7,
    label: 'Phone of Alice',
    capabilities: const ['cap.attach.photo'],
    brainPairEndpoint: 'https://brain.example/api/v1/device-pair',
    brainWssEndpoint: 'wss://brain.example/api/v1/wallet',
    brainPinCertId: 'cc' * 16,
    brainPinPubkey: '03${'cc' * 32}',
    bearer: 'a' * 64,
  );
}

class _StaticAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int> body;
  _StaticAdapter({required this.statusCode, required this.body});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(body, statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int> body;
  RequestOptions? lastRequest;
  _RecordingAdapter({required this.statusCode, required this.body});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromBytes(body, statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

class _ScriptedResponse {
  final int statusCode;
  final List<int> body;
  _ScriptedResponse({required this.statusCode, required this.body});
}

class _SequenceAdapter implements HttpClientAdapter {
  final List<_ScriptedResponse> _responses;
  final List<RequestOptions> requests = [];
  int _idx = 0;

  _SequenceAdapter(this._responses);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final r = _responses[_idx++ % _responses.length];
    return ResponseBody.fromBytes(r.body, r.statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

```
