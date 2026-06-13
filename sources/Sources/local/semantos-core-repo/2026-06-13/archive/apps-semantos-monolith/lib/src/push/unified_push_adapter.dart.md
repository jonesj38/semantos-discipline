---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/push/unified_push_adapter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.873299+00:00
---

# archive/apps-semantos-monolith/lib/src/push/unified_push_adapter.dart

```dart
// Sovereign-push D.3 — UnifiedPush adapter for the mobile shell.
//
// Wraps the `unifiedpush` Flutter plugin behind the
// [PushPlatformAdapter] interface defined in
// push_registration_service.dart, so the rest of the helm shell
// reaches it through the same surface as [FirebasePushAdapter].
//
// Reference:
//   - https://unifiedpush.org/spec/server/
//   - https://pub.dev/packages/unifiedpush (^6.x)
//   - docs/operator-runbooks/push-architecture.md §"Phase D.3:
//     UnifiedPush"
//
// What this adapter is responsible for:
//
//   1. `register()` — calls UnifiedPush.registerApp() and waits
//      (with a finite timeout) for the plugin to invoke
//      `onNewEndpoint` with the distributor's per-instance URL.
//      That URL becomes the "device token" the brain stores in
//      cert.up_endpoint.
//
//   2. `unregister()` — calls UnifiedPush.unregister().
//
//   3. `onMessage(handler)` — wires the plugin's onMessage callback
//      into the same silent-push handler D.2 uses for FCM.  The
//      payload bytes are the brain's raw JSON envelope —
//      `{"event_id":"...","ts":...,"kind":"helm.event"}` — verbatim,
//      with no provider wrapping.
//
//   4. `getDistributors()` — returns the list of installed UP
//      distributor app ids so the operator can pick one in Settings
//      → Push.
//
// Why this lives in its own file (mirrors firebase_push_adapter.dart):
// the unifiedpush plugin pulls in native Android receivers; co-locating
// it with PushRegistrationService would force `dart test` (which the
// unit-test suite uses to stay Flutter-SDK-free) to fail on a missing
// transitive dep.  Splitting keeps the service file pure-Dart-importable.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:unifiedpush/unifiedpush.dart';

import 'push_registration_service.dart';

/// How long to wait for the distributor to mint and deliver an
/// endpoint URL after [UnifiedPushAdapter.register] is called.
/// 30 seconds is generous: ntfy / NextPush typically reply in
/// well under 5s, but a freshly-installed Conversations distributor
/// negotiating with its XMPP server can take longer on a cold start.
const _kEndpointMintTimeout = Duration(seconds: 30);

/// The instance string the helm registers under.  UP supports
/// multiple instances per app (e.g. one per tenant), but the helm
/// only ever speaks for one operator-cert at a time, so a fixed
/// string is fine.
const _kHelmInstance = 'oddjobz';

/// Production [PushPlatformAdapter] backed by the `unifiedpush`
/// plugin.  Constructed lazily at app boot when the operator's
/// stored preference is `unifiedpush`; the FCM adapter is also
/// constructed and held in reserve as a fallback.
///
/// NOTE: This adapter SHARES the same notification-permission
/// surface with the FCM adapter — banners are still composed by
/// flutter_local_notifications, so Android 13+ POST_NOTIFICATIONS
/// is still required.  iOS doesn't reach this code path at all
/// (Apple sandbox bans alternative wake mechanisms).
class UnifiedPushAdapter implements PushPlatformAdapter {
  /// Latest endpoint URL the distributor has minted for us, or null
  /// if registration hasn't completed yet.
  String? _currentEndpoint;

  /// Pending Completer waiting on the next onNewEndpoint callback.
  /// Reset to null after each completion.
  Completer<String?>? _pendingMint;

  /// Stream of refreshed endpoints.  UP fires onNewEndpoint whenever
  /// the distributor rotates the URL (e.g. after a server-side
  /// account migration).  PushRegistrationService listens to this
  /// once at startup and POSTs each rotation to the brain.
  final StreamController<String> _endpointRefresh =
      StreamController<String>.broadcast();

  /// Test seam — the production constructor wires
  /// UnifiedPush.initialize at construction time; tests pass
  /// [skipInitialize]=true and drive the callbacks via
  /// [debugFireOnNewEndpoint] / [debugFireOnMessage] directly.
  final bool _skipInitialize;

  /// External handler for onMessage.  Wired by the production
  /// boot path to the silent-push handler from D.2 so a UP wake
  /// drives the same fetch_since → render flow as an FCM wake.
  void Function(Map<String, String> envelope)? _onMessage;

  UnifiedPushAdapter({bool skipInitialize = false})
      : _skipInitialize = skipInitialize {
    if (!_skipInitialize) {
      // Fire-and-forget — the plugin's initialize() returns a Future<bool>
      // for connection-ready confirmation, but the helm registers lazily
      // via [register()] so we don't need to block on it here.
      // ignore: discarded_futures
      UnifiedPush.initialize(
        onNewEndpoint: _handleNewEndpoint,
        onUnregistered: _handleUnregistered,
        onMessage: _handleMessage,
        onRegistrationFailed: _handleRegistrationFailed,
      );
    }
  }

  // ── PushPlatformAdapter interface ──

  /// Stable wire-name — matches the brain-side enum variant.
  @override
  String get platformName => 'unifiedpush';

  /// On Android the helm still uses flutter_local_notifications to
  /// render banners, which means POST_NOTIFICATIONS is still needed
  /// on API ≥33.  iOS never reaches this adapter.
  @override
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (!status.isGranted && !status.isLimited) return false;
    }
    return true;
  }

  /// Drives a UP registration to completion.  Returns the
  /// distributor's endpoint URL when onNewEndpoint fires; returns
  /// null on registration failure / timeout / no distributor.
  ///
  /// PushRegistrationService treats a null result as
  /// [PushUnsupported] which the prefer-UP-fallback-FCM path
  /// surfaces to the operator as "install a distributor (e.g.
  /// ntfy) or stay on Firebase".
  @override
  Future<String?> getDeviceToken() async {
    // If we already have a live endpoint and the distributor hasn't
    // unregistered, reuse it — registerApp() is idempotent on the
    // plugin side but skipping a round-trip is cleaner.
    if (_currentEndpoint != null && _currentEndpoint!.isNotEmpty) {
      return _currentEndpoint;
    }

    // Otherwise drive a fresh registration: tell the plugin which
    // distributor to use (the previously-saved one, or the OS
    // default if unset), then call registerApp + await
    // onNewEndpoint.
    final ok = await tryUseCurrentOrDefaultDistributor();
    if (!ok) return null;

    final completer = Completer<String?>();
    _pendingMint = completer;
    try {
      await UnifiedPush.register(instance: _kHelmInstance);
    } catch (_) {
      _pendingMint = null;
      return null;
    }
    return completer.future.timeout(
      _kEndpointMintTimeout,
      onTimeout: () {
        _pendingMint = null;
        return null;
      },
    );
  }

  @override
  Stream<String> get tokenRefreshStream => _endpointRefresh.stream;

  // ── UP-specific surface (called from SettingsScreen + boot) ──

  /// List of installed distributor app ids the operator can pick
  /// from in Settings → Push.  Empty list means no distributor is
  /// installed; the helm should suggest the operator install one
  /// (https://unifiedpush.org/users/distributors/) and fall back
  /// to FCM in the meantime.
  Future<List<String>> getDistributors() async {
    try {
      return await UnifiedPush.getDistributors();
    } catch (_) {
      return const <String>[];
    }
  }

  /// Persist the operator's distributor choice for future
  /// registrations.  The plugin remembers this across cold starts.
  Future<void> saveDistributor(String distributorId) async {
    try {
      await UnifiedPush.saveDistributor(distributorId);
    } catch (_) {
      // Best-effort — caller will discover the failure when the
      // next register() call returns null.
    }
  }

  /// Ask the plugin to use the previously-saved distributor (or
  /// auto-pick a default when only one is installed).  Returns
  /// false when no distributor is available.
  Future<bool> tryUseCurrentOrDefaultDistributor() async {
    try {
      return await UnifiedPush.tryUseCurrentOrDefaultDistributor();
    } catch (_) {
      return false;
    }
  }

  /// Tell the distributor to drop our subscription.  The plugin
  /// fires `onUnregistered` shortly after — we clear the cached
  /// endpoint there.
  Future<void> unregister() async {
    try {
      await UnifiedPush.unregister(_kHelmInstance);
    } catch (_) {
      // Best-effort.
    }
    _currentEndpoint = null;
  }

  /// Wire the silent-push handler.  Called once at boot from
  /// push_handlers.dart so a UP wake drives the same fetch_since
  /// pipeline an FCM wake does.  The handler receives the wake
  /// envelope flattened to a string-keyed map, matching the
  /// FirebaseMessaging RemoteMessage.data shape.
  void onMessage(void Function(Map<String, String> envelope) handler) {
    _onMessage = handler;
  }

  /// Tear-down for tests + logout.
  Future<void> dispose() async {
    await _endpointRefresh.close();
    _pendingMint = null;
  }

  // ── Plugin callbacks (called from background isolate sometimes) ──

  void _handleNewEndpoint(PushEndpoint endpoint, String instance) {
    final url = endpoint.url;
    _currentEndpoint = url;
    final pending = _pendingMint;
    _pendingMint = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(url);
    }
    if (!_endpointRefresh.isClosed) {
      _endpointRefresh.add(url);
    }
  }

  void _handleUnregistered(String instance) {
    _currentEndpoint = null;
    final pending = _pendingMint;
    _pendingMint = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
  }

  void _handleRegistrationFailed(FailedReason reason, String instance) {
    final pending = _pendingMint;
    _pendingMint = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
  }

  void _handleMessage(PushMessage message, String instance) {
    final handler = _onMessage;
    if (handler == null) return;
    final envelope = _parseEnvelope(message.content);
    handler(envelope);
  }

  // ── Test-only helpers ──

  /// TEST-ONLY: pretend the distributor delivered an endpoint URL.
  /// Used by unit tests to drive the [getDeviceToken] / refresh
  /// stream pipeline without spinning up the plugin.
  void debugFireOnNewEndpoint(String url, {String instance = _kHelmInstance}) {
    _handleNewEndpoint(PushEndpoint(url, null), instance);
  }

  /// TEST-ONLY: pretend the distributor reported the registration
  /// has been torn down.
  void debugFireOnUnregistered({String instance = _kHelmInstance}) {
    _handleUnregistered(instance);
  }

  /// TEST-ONLY: pretend the distributor reported a registration
  /// failure (no distributor installed, network error, …).
  void debugFireOnRegistrationFailed({
    FailedReason reason = FailedReason.network,
    String instance = _kHelmInstance,
  }) {
    _handleRegistrationFailed(reason, instance);
  }

  /// TEST-ONLY: deliver a synthetic push message into the wired
  /// handler (the silent-push pipeline in production).
  void debugFireOnMessage(
    Map<String, dynamic> envelope, {
    String instance = _kHelmInstance,
  }) {
    final bytes = utf8.encode(jsonEncode(envelope));
    _handleMessage(PushMessage(Uint8List.fromList(bytes), true), instance);
  }
}

/// Decode a UP message body into the flat string→string envelope the
/// silent-push handler from D.2 expects.  The brain POSTs the wake
/// envelope as raw JSON: `{"event_id":"...","ts":1234,"kind":"..."}`.
/// Numeric / boolean values get stringified to match the RemoteMessage
/// shape FirebaseMessaging delivers.
Map<String, String> _parseEnvelope(Uint8List bytes) {
  if (bytes.isEmpty) return const <String, String>{};
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return const <String, String>{};
    final out = <String, String>{};
    decoded.forEach((k, v) {
      out[k.toString()] = v?.toString() ?? '';
    });
    return out;
  } catch (_) {
    return const <String, String>{};
  }
}

```
