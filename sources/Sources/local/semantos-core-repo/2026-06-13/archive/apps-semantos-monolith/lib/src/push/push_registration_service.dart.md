---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/push/push_registration_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.870854+00:00
---

# archive/apps-semantos-monolith/lib/src/push/push_registration_service.dart

```dart
// D-O5m.followup-9 Phase C / Sovereign-push D.3 —
// PushRegistrationService.
//
// Captures the platform-specific device token (APNs on iOS / FCM or
// UnifiedPush on Android) and POSTs it to the brain's
// /api/v1/push-register endpoint, then persists the registration on
// the device's SecureStore so we don't re-register on every cold
// launch unless the platform rotates the token.
//
// Sovereign-push D.3 — adds a "preferred backend" knob.  On Android
// the operator can choose between FCM and UnifiedPush.  Default for
// new installs is `unifiedpush` (sovereignty-first); when no
// distributor is installed the service falls back to FCM and surfaces
// a one-time banner suggesting the operator install one.  iOS always
// uses APNs (Apple sandbox bans alternative wakes).
//
// Architectural seam — this file is pure-Dart-importable: it depends
// only on `dart:async`, dio, and the abstract [PushPlatformAdapter]
// interface (defined here).  The production [FirebasePushAdapter]
// lives in `firebase_push_adapter.dart` and imports
// firebase_messaging; the unit-test suite injects
// [InMemoryPushAdapter] (also defined here) so the tests run under
// pure `dart test` with no Flutter SDK in the loop.
//
// Wire shape (POST /api/v1/push-register) — see
// runtime/semantos-brain/src/push_register_http.zig:
//
//   POST /api/v1/push-register
//     Authorization: Bearer <hex64>
//     Content-Type: application/json
//     {
//       "cert_id":  "<32 hex>",
//       "platform": "apns" | "fcm",
//       "token":    "<opaque platform token, ≤ 4 KiB>"
//     }
//
//   200 → { "registered": true, "platform": "apns", "registered_at": "<ISO-8601>" }
//
// DELETE shape (operator-initiated unregister via Settings):
//
//   DELETE /api/v1/push-register
//     Authorization: Bearer <hex64>
//     Content-Type: application/json
//     { "cert_id": "<32 hex>" }
//
//   200 → { "registered": false }

import 'dart:async';

import 'package:dio/dio.dart';

import '../identity/child_cert_store.dart';
import 'push_platform.dart';

/// Platform abstraction over Firebase / APNs / FCM token retrieval.
/// Production wraps firebase_messaging via [FirebasePushAdapter] (in
/// firebase_push_adapter.dart); tests inject [InMemoryPushAdapter]
/// for hermetic coverage.
abstract class PushPlatformAdapter {
  /// Prompt the user for permission (iOS UNUserNotificationCenter +
  /// Android 13+ POST_NOTIFICATIONS).  Returns true iff the user
  /// granted at least the basic alert permission.  `provisional`
  /// authorisation also counts as true — the brain doesn't
  /// distinguish.
  Future<bool> requestPermission();

  /// Fetch the platform device token.  Returns null when the device
  /// has no Google Play Services / running on iOS Simulator without
  /// push entitlement / similar.  PushRegistrationService surfaces a
  /// null result as [PushUnsupported].
  Future<String?> getDeviceToken();

  /// Wire-name for this transport — `'apns'` or `'fcm'`.  Matches
  /// [PushPlatform.toJson] so the brain dispatcher routes correctly.
  String get platformName;

  /// Stream of refreshed tokens.  firebase_messaging emits whenever
  /// the OS rotates the underlying token (e.g. after an OS update,
  /// app reinstall, or APNs sandbox/production swap).  The service
  /// listens to this stream once at startup and POSTs each refresh
  /// to the brain so the cert record stays current.
  Stream<String> get tokenRefreshStream;
}

/// In-memory adapter for tests + the desktop dev harness.  Returns
/// scripted responses; the [tokenRefresh] sink lets a test push
/// rotated tokens through the listener pipeline.
class InMemoryPushAdapter implements PushPlatformAdapter {
  bool permissionGranted;
  String? token;
  @override
  final String platformName;
  final StreamController<String> _tokenRefresh =
      StreamController<String>.broadcast();

  /// True if the production adapter would surface `Unsupported` —
  /// the test seam for `PushUnsupported` outcomes (simulator, no
  /// Play Services, etc.).
  bool unsupported;

  InMemoryPushAdapter({
    this.permissionGranted = true,
    this.token = 'in-memory-tok',
    this.platformName = 'fcm',
    this.unsupported = false,
  });

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<String?> getDeviceToken() async {
    if (unsupported) return null;
    return token;
  }

  @override
  Stream<String> get tokenRefreshStream => _tokenRefresh.stream;

  /// Test helper — emits a refreshed token through the listener.
  void emitTokenRefresh(String tok) {
    _tokenRefresh.add(tok);
  }

  /// Tear-down for test rigs.
  Future<void> dispose() async {
    await _tokenRefresh.close();
  }
}

/// Outcome of [PushRegistrationService.registerOnPair].  Sealed
/// hierarchy so the helm UI's switch-on-runtime-type is exhaustive
/// without a default arm.
sealed class PushRegistrationResult {
  const PushRegistrationResult();
}

/// Successful registration — the brain persisted the token and
/// echoed back the platform + registered_at timestamp.  The shell
/// stores [token] + [platform] + [registeredAt] on SecureStore so
/// startup checks can avoid the round-trip when the cached values
/// match.
class PushRegistered extends PushRegistrationResult {
  final String token;
  final String platform;
  final String registeredAt;
  const PushRegistered({
    required this.token,
    required this.platform,
    required this.registeredAt,
  });
}

/// User declined the iOS / Android permission prompt.  The helm UI
/// renders a "Notifications disabled — Open Settings" CTA in
/// SettingsScreen.  PushRegistrationService does NOT auto-retry; the
/// operator has to take an explicit action to flip the OS-level
/// permission back on.
class PushPermissionDenied extends PushRegistrationResult {
  final String reason;
  const PushPermissionDenied({required this.reason});
}

/// Push is not supported on this device — typically iOS Simulator
/// (no APNs at all) or an Android device without Google Play
/// Services (FCM unavailable).  The helm UI surfaces this as an
/// info banner; the operator can still use every other helm feature.
class PushUnsupported extends PushRegistrationResult {
  final String reason;
  const PushUnsupported({required this.reason});
}

/// Registration HTTP failed at the brain side.  Wraps the HTTP
/// status code so the helm UI can show a "retry" CTA on transient
/// 5xx and a "re-pair this device" CTA on a 401 (the cert was
/// revoked and the bearer is stale).
class PushRegistrationFailed extends PushRegistrationResult {
  final String reason;
  final int? statusCode;
  const PushRegistrationFailed({required this.reason, this.statusCode});
}

/// SecureStore slot keys for the persisted registration record.
/// Versioned so a future schema rev can do a zero-downtime migration.
class _PushKeys {
  static const platform = 'd-o5m.v1.push_platform';
  static const token = 'd-o5m.v1.push_token';
  static const registeredAt = 'd-o5m.v1.push_registered_at';
  /// Sovereign-push D.3 — operator's preferred Android push backend.
  /// One of `unifiedpush` (default for new installs, sovereignty-
  /// first) or `fcm`.  iOS ignores this field; APNs is the only
  /// option Apple permits.
  static const backendPreference = 'd-o5m.v3.push_backend_preference';
}

/// Sovereign-push D.3 — operator-facing choice for the Android push
/// backend.  Surfaced in Settings → Push.  iOS always uses APNs
/// regardless.
enum PushBackendPreference {
  /// Prefer UnifiedPush.  When no UP distributor is installed the
  /// service falls back to FCM (and the SettingsScreen renders a
  /// "install a distributor for full sovereignty" hint).  Default
  /// for new installs.
  unifiedpush,

  /// Use Firebase Cloud Messaging directly.  No fallback —
  /// operators who explicitly chose FCM probably want predictability.
  fcm;

  String toJson() => name;

  static PushBackendPreference? fromJson(String value) {
    for (final p in PushBackendPreference.values) {
      if (p.name == value) return p;
    }
    return null;
  }
}

/// Owns the push-token lifecycle for the mobile shell.
class PushRegistrationService {
  final ChildCertStore _certStore;
  final SecureStore _secureStore;
  final Dio _dio;
  PushPlatformAdapter _adapter;
  /// Sovereign-push D.3 — optional secondary adapter.  When the
  /// primary returns null on `getDeviceToken()` AND the operator's
  /// stored preference allows fallback, the service swaps in this
  /// adapter and retries.  Construction-time wiring on Android is
  /// `primary = UnifiedPushAdapter, fallback = FirebasePushAdapter`;
  /// on iOS the fallback is null (APNs is the only option).
  PushPlatformAdapter? _fallbackAdapter;
  /// Whether the most recent registerOnPair() call had to fall back
  /// to the secondary adapter.  Surfaced via [lastUsedFallback] so
  /// the SettingsScreen can render the "install a distributor" hint.
  bool _lastUsedFallback = false;
  final String _brainBaseUrl;

  StreamSubscription<String>? _tokenRefreshSub;

  PushRegistrationService({
    required ChildCertStore certStore,
    required SecureStore secureStore,
    required Dio dio,
    required PushPlatformAdapter adapter,
    required String brainBaseUrl,
    PushPlatformAdapter? fallbackAdapter,
  })  : _certStore = certStore,
        _secureStore = secureStore,
        _dio = dio,
        _adapter = adapter,
        _fallbackAdapter = fallbackAdapter,
        _brainBaseUrl = _stripTrailingSlash(brainBaseUrl);

  /// Sovereign-push D.3 — true when the most recent registerOnPair
  /// fell through from the primary (UnifiedPush) to the fallback
  /// (FCM).  The SettingsScreen reads this to decide whether to
  /// surface the "install a distributor for full sovereignty" hint.
  bool get lastUsedFallback => _lastUsedFallback;

  /// The adapter currently in use.  Reflects the result of the last
  /// fallback decision, so SettingsScreen can show the operator
  /// which backend ended up serving the registration.
  String get activeBackendName => _adapter.platformName;

  /// Read the persisted Android backend preference.  Defaults to
  /// `unifiedpush` for new installs (sovereignty-first); explicit
  /// `fcm` is only set when the operator chooses it in Settings.
  Future<PushBackendPreference> readBackendPreference() async {
    final raw = await _secureStore.read(_PushKeys.backendPreference);
    if (raw == null || raw.isEmpty) return PushBackendPreference.unifiedpush;
    return PushBackendPreference.fromJson(raw) ??
        PushBackendPreference.unifiedpush;
  }

  /// Persist the operator's backend preference.  Called from the
  /// SettingsScreen apply-button handler.  The next registerOnPair()
  /// will honour the new preference.
  Future<void> writeBackendPreference(PushBackendPreference pref) async {
    await _secureStore.write(_PushKeys.backendPreference, pref.toJson());
  }

  /// Sovereign-push D.3 — swap the active adapters at runtime.  The
  /// SettingsScreen calls this after the operator picks a different
  /// backend so the next registerOnPair() uses the updated wiring.
  /// `primary` is what the service will try first; `fallback` (if
  /// non-null) is what it falls back to when primary returns null.
  void swapAdapters({
    required PushPlatformAdapter primary,
    PushPlatformAdapter? fallback,
  }) {
    _adapter = primary;
    _fallbackAdapter = fallback;
  }

  /// Read the persisted registration (if any).  Returns the empty
  /// sentinel when the device hasn't registered or has unregistered.
  Future<PushTokenRegistration> readPersisted() async {
    final platformRaw = await _secureStore.read(_PushKeys.platform);
    if (platformRaw == null || platformRaw.isEmpty) {
      return PushTokenRegistration.empty;
    }
    final platform = PushPlatform.fromJson(platformRaw);
    if (platform == null || platform == PushPlatform.none) {
      return PushTokenRegistration.empty;
    }
    final token = await _secureStore.read(_PushKeys.token) ?? '';
    final registeredAt =
        await _secureStore.read(_PushKeys.registeredAt) ?? '';
    return PushTokenRegistration(
      platform: platform,
      token: token,
      registeredAt: registeredAt,
    );
  }

  /// Called after a successful pairing.  Asks for permission, gets
  /// the platform token, POSTs it to the brain, and persists the
  /// resulting registration.
  ///
  /// Sovereign-push D.3: when the primary adapter returns null
  /// (e.g. UnifiedPush has no distributor installed) AND a
  /// fallback adapter was wired at construction, the service
  /// transparently retries via the fallback.  `lastUsedFallback`
  /// flips to true so the SettingsScreen can render a hint.
  Future<PushRegistrationResult> registerOnPair() async {
    _lastUsedFallback = false;

    final cert = await _certStore.read();
    if (cert == null) {
      return const PushRegistrationFailed(
        reason: 'cert not yet persisted — pairing must complete first',
      );
    }

    final granted = await _adapter.requestPermission();
    if (!granted) {
      return const PushPermissionDenied(
        reason: 'OS-level notifications permission denied',
      );
    }

    final token = await _adapter.getDeviceToken();
    if (token != null && token.isNotEmpty) {
      return _postRegister(
        certId: cert.operatorCertId,
        bearer: cert.bearer,
        platform: _adapter.platformName,
        token: token,
      );
    }

    // Sovereign-push D.3 — primary adapter returned null.  Try the
    // fallback (FCM on Android when the primary was UnifiedPush and
    // no distributor is installed).
    final fb = _fallbackAdapter;
    if (fb != null) {
      final fbGranted = await fb.requestPermission();
      if (!fbGranted) {
        return const PushPermissionDenied(
          reason:
              'OS-level notifications permission denied (fallback adapter)',
        );
      }
      final fbToken = await fb.getDeviceToken();
      if (fbToken != null && fbToken.isNotEmpty) {
        // Swap the active adapter so subsequent token-refresh
        // listening attaches to the right stream.  The fallback
        // now is the active backend until the operator changes
        // their preference in Settings.
        _adapter = fb;
        _fallbackAdapter = null;
        _lastUsedFallback = true;
        return _postRegister(
          certId: cert.operatorCertId,
          bearer: cert.bearer,
          platform: fb.platformName,
          token: fbToken,
        );
      }
    }

    return const PushUnsupported(
      reason: 'no platform device token available '
          '(no distributor installed? simulator? missing Play Services?)',
    );
  }

  /// Listen for refreshed tokens.  Idempotent — calling twice is
  /// safe (the previous subscription is cancelled before the new
  /// one is wired).  Caller is responsible for calling [stop] /
  /// [dispose] on logout.
  void startTokenRefreshListener() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _adapter.tokenRefreshStream.listen(_onTokenRefresh);
  }

  Future<void> _onTokenRefresh(String token) async {
    final cert = await _certStore.read();
    if (cert == null) return;
    if (token.isEmpty) return;
    await _postRegister(
      certId: cert.operatorCertId,
      bearer: cert.bearer,
      platform: _adapter.platformName,
      token: token,
    );
  }

  /// Stop the refresh listener.  Called on logout / unpair.
  Future<void> stop() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }

  /// Operator-initiated unregister via Settings.  POSTs DELETE to
  /// the brain and clears the local persisted record.  Best-effort
  /// — even if the network call fails, the local record is cleared
  /// so the helm UI reflects "not subscribed".
  Future<void> unregister() async {
    final cert = await _certStore.read();
    await _clearPersisted();
    await stop();
    if (cert == null) return;

    final headers = <String, String>{
      'content-type': 'application/json',
      'authorization': 'Bearer ${cert.bearer}',
    };
    try {
      await _dio.deleteUri<dynamic>(
        Uri.parse('$_brainBaseUrl/api/v1/push-register'),
        data: {'cert_id': cert.operatorCertId},
        options: Options(
          headers: headers,
          validateStatus: (_) => true,
          responseType: ResponseType.json,
        ),
      );
    } on DioException {
      // Best-effort — we already cleared the local record.
    }
  }

  Future<PushRegistrationResult> _postRegister({
    required String certId,
    required String bearer,
    required String platform,
    required String token,
  }) async {
    final headers = <String, String>{
      'content-type': 'application/json',
      'authorization': 'Bearer $bearer',
    };

    Response<dynamic> resp;
    try {
      resp = await _dio.postUri<dynamic>(
        Uri.parse('$_brainBaseUrl/api/v1/push-register'),
        data: {
          'cert_id': certId,
          'platform': platform,
          'token': token,
        },
        options: Options(
          headers: headers,
          validateStatus: (_) => true,
          responseType: ResponseType.json,
        ),
      );
    } on DioException catch (e) {
      return PushRegistrationFailed(
        reason: 'network error: ${e.message ?? e.type.name}',
      );
    }

    final status = resp.statusCode ?? 0;
    final body = resp.data;
    if (status < 200 || status >= 300) {
      return PushRegistrationFailed(
        reason: _extractError(body) ?? 'HTTP $status',
        statusCode: status,
      );
    }
    if (body is! Map) {
      return const PushRegistrationFailed(
        reason: 'response body was not a JSON object',
      );
    }
    if (body['registered'] != true) {
      return PushRegistrationFailed(
        reason: _extractError(body) ?? 'brain returned registered=false',
        statusCode: status,
      );
    }
    final platformResp = body['platform'] is String
        ? body['platform'] as String
        : platform;
    final registeredAt = body['registered_at'] is String
        ? body['registered_at'] as String
        : '';

    await _persist(
      platform: platformResp,
      token: token,
      registeredAt: registeredAt,
    );

    return PushRegistered(
      token: token,
      platform: platformResp,
      registeredAt: registeredAt,
    );
  }

  Future<void> _persist({
    required String platform,
    required String token,
    required String registeredAt,
  }) async {
    await _secureStore.write(_PushKeys.platform, platform);
    await _secureStore.write(_PushKeys.token, token);
    await _secureStore.write(_PushKeys.registeredAt, registeredAt);
  }

  Future<void> _clearPersisted() async {
    await _secureStore.delete(_PushKeys.platform);
    await _secureStore.delete(_PushKeys.token);
    await _secureStore.delete(_PushKeys.registeredAt);
  }
}

String? _extractError(dynamic body) {
  if (body is Map && body['error'] is String) return body['error'] as String;
  return null;
}

String _stripTrailingSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

```
