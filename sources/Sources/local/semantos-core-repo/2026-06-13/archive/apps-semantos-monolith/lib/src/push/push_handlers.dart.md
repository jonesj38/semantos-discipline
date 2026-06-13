---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/push/push_handlers.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.871172+00:00
---

# archive/apps-semantos-monolith/lib/src/push/push_handlers.dart

```dart
// Sovereign-push D.2 — Flutter-side wiring for the wake-only push
// pipeline.
//
// D.1 reduced every APNs/FCM payload to an opaque envelope
// `{event_id, ts, kind}` — Apple and Google never see operator
// content.  D.2 (this file + silent_push_handler.dart +
// last_seen_store.dart) is the device-side consumer:
//
//   FCM/APNs wake → onMessage / onBackgroundMessage fires →
//     SilentPushHandler.handle() → opens (or reuses) the WSS to
//     the brain → calls helm.fetch_since(since_ts=lastSeen) →
//     renders one local notification per returned event whose
//     kind warrants a banner → advances the lastSeen cursor.
//
// What this file owns:
//   - Wiring FirebaseMessaging onMessage / onMessageOpenedApp /
//     getInitialMessage / onBackgroundMessage to the handler.
//   - Production [LocalNotificationSink] backed by
//     flutter_local_notifications.
//   - Production stream factory that constructs an ephemeral
//     HelmEventStream for the background-isolate wake path.
//   - Routing taps on local notifications back through
//     PushNotificationRouter.
//
// What lives elsewhere:
//   - silent_push_handler.dart — pure-Dart fetch + render +
//     cursor-advance logic, unit-tested in isolation.
//   - last_seen_store.dart — SecureStorage-backed cursor.
//   - push_notification_router.dart — pure-Dart deep-link routing.
//
// Reference: https://firebase.flutter.dev/docs/messaging/usage

import 'dart:async';
import 'dart:convert';

// 2026-05-06 — firebase_messaging import temporarily removed alongside
// pubspec.yaml's firebase_core + firebase_messaging deps so the iOS
// Simulator build resolves.  setupPushHandlers() is now a no-op when
// Firebase is unavailable; UnifiedPush handles the Android wake path
// independently via the unified_push_adapter wiring in main.dart.
// import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../identity/child_cert_store.dart';
import '../identity/flutter_secure_store_adapter.dart';
import '../repl/helm_event_stream.dart';
import 'last_seen_store.dart';
import 'push_notification_router.dart';
import 'silent_push_handler.dart';

/// Default Android notification channel — must match the
/// `com.google.firebase.messaging.default_notification_channel_id`
/// metadata in AndroidManifest.xml.
const _kDefaultChannelId = 'oddjobz_default_channel';
const _kDefaultChannelName = 'Oddjobz alerts';
const _kDefaultChannelDescription =
    'New leads, job updates, and other operator-action alerts.';

/// Topics the throwaway background-isolate WSS subscribes to.  We
/// subscribe so the brain accepts the upgrade with the same shape
/// the foreground HomeScreen uses; the silent handler doesn't
/// actually consume the live `helm.event` notifications — it only
/// uses the same socket for `helm.fetch_since` request/response.
const _kBackgroundTopics = <String>[
  'jobs',
  'customers',
  'visits',
  'quotes',
  'invoices',
  'attachments',
  'leads',
];

/// Live-helm dedupe set.  When the foreground HomeScreen mounts a
/// HelmEventStream, every `helm.event` notification it surfaces
/// records its event_id here so a wake-push that races the live
/// notification doesn't double-render.  The set is bounded to
/// MAX_DEDUPE_ENTRIES so a long-running session doesn't grow
/// unboundedly.  Background isolates don't see this set (different
/// memory).
class LiveHelmEventDedupe {
  static final Set<String> _ids = <String>{};
  static const _maxEntries = 1024;

  /// Record an event_id surfaced by the live stream.  Called by
  /// the silent-push handler indirectly via the dedupe-set passed
  /// to SilentPushHandlerDeps; also called by foreground code that
  /// observes a `helm.event` notification.
  static void record(String eventId) {
    if (eventId.isEmpty) return;
    if (_ids.length >= _maxEntries) {
      // Drop the oldest half — we're keeping a sliding window.
      final keep = _ids.skip(_ids.length ~/ 2).toList();
      _ids
        ..clear()
        ..addAll(keep);
    }
    _ids.add(eventId);
  }

  /// True when the live stream has already surfaced this event.
  static bool contains(String eventId) =>
      eventId.isNotEmpty && _ids.contains(eventId);

  /// The shared set the silent handler reads.
  static Set<String> view() => _ids;

  /// Test-only — clear the dedupe set between tests.
  @visibleForTesting
  static void resetForTest() => _ids.clear();
}

/// Top-level entrypoint, must be wired BEFORE runApp().  Sets up
/// background handler + foreground delivery + tap routing.
///
/// Usage (in main.dart):
///
///   await Firebase.initializeApp();
///   await setupPushHandlers(navKey: globalNavKey);
///   runApp(...);
///
/// [navKey] is the same `GlobalKey<NavigatorState>` the MaterialApp
/// holds — the router uses it to push named routes from outside the
/// widget tree (taps on a notification while the app was terminated
/// fire BEFORE the first widget builds).
Future<void> setupPushHandlers({
  required GlobalKey<NavigatorState> navKey,
}) async {
  // 2026-05-06 — Firebase wake handlers temporarily stubbed out so the
  // iOS Simulator build resolves.  Pre-fix this function wired:
  //   - FirebaseMessaging.onBackgroundMessage(_backgroundHandler)
  //   - FirebaseMessaging.onMessage.listen(...)  (foreground wake)
  //   - FirebaseMessaging.onMessageOpenedApp.listen(...)  (tap while bg)
  //   - FirebaseMessaging.instance.getInitialMessage()  (tap while terminated)
  //
  // With the firebase_messaging dep commented out, none of those
  // callbacks fire.  UnifiedPush (Android) wakes via its own delivery
  // path in the unified_push_adapter, so Android still functions.  iOS
  // push is disabled entirely until we either restore Firebase or wire
  // a native APNs shim.
  //
  // We still build the local-notifications channel so any in-process
  // code that wants to render a banner has a sink — keeps the foreground
  // helm-event WSS path's "live tick" notification working.
  await _ensureLocalNotifications(navKey);
}

// 2026-05-06 — _handleForegroundWake / _backgroundHandler / _runSilentHandler
// removed as part of the Firebase iOS-Simulator stub.  They depended on
// the firebase_messaging RemoteMessage type which is no longer imported.
// Restore alongside the firebase_messaging dep + the imports + the
// FirebaseMessaging.* listener wire-ups in setupPushHandlers when
// re-enabling Firebase wakes.  Pre-stub bodies are preserved in git
// history at commit 4a0d92f and earlier.

Future<FlutterLocalNotificationsPlugin> _ensureLocalNotifications(
  GlobalKey<NavigatorState> navKey,
) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );
  await plugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (response) {
      // User tapped the foreground in-app banner — same routing as
      // the system tap path.
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;
      final data = _decodeStringMap(payload);
      PushNotificationRouter(navigator: _NavKeyNavigatorSink(navKey))
          .routeTap(data);
    },
  );

  await _ensureAndroidChannel(plugin);
  return plugin;
}

Future<void> _ensureAndroidChannel(
  FlutterLocalNotificationsPlugin plugin,
) async {
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      _kDefaultChannelId,
      _kDefaultChannelName,
      description: _kDefaultChannelDescription,
      importance: Importance.high,
    ),
  );
}

// 2026-05-06 — _dataFrom and _envelopeFrom removed as part of the Firebase
// iOS-Simulator stub.  They marshalled RemoteMessage data into the pure-Dart
// router/handler shapes; with the wake handlers gone, they're dead code.
// Restore alongside the Firebase wake handlers when re-enabling.
//
// Body retained as a multi-line comment for the convenience of the next
// reader who restores them:
//
//   Map<String, Object?> _dataFrom(RemoteMessage message) =>
//       Map<String, Object?>.from(message.data);
//
//   Map<String, String> _envelopeFrom(RemoteMessage message) {
//     final out = <String, String>{};
//     message.data.forEach((k, v) { out[k] = v?.toString() ?? ''; });
//     return out;
//   }

// _decodeStringMap is still used by the foreground in-app banner tap
// handler in _ensureLocalNotifications, so it stays (defined later in
// this file).

/// Production [LocalNotificationSink] backed by
/// flutter_local_notifications.  Lives in this file because it's the
/// only place that imports the plugin.
class FlutterLocalNotificationsSink implements LocalNotificationSink {
  final FlutterLocalNotificationsPlugin _plugin;

  FlutterLocalNotificationsSink(this._plugin);

  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required Map<String, String> payload,
  }) async {
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _kDefaultChannelId,
            _kDefaultChannelName,
            channelDescription: _kDefaultChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: _encodePayload(payload),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// JSON-encode a string map for flutter_local_notifications' payload
/// parameter (which is String?).  Round-trips through json.encode +
/// json.decode at routing time so future event types carrying nested
/// data shapes work without re-coding the encoder.
String _encodePayload(Map<String, String> payload) => jsonEncode(payload);

Map<String, Object?> _decodeStringMap(String payload) {
  // Try JSON first (the new D.2 encoding).  Fall back to the legacy
  // `key=value;...` shape so any in-flight notifications composed
  // before the upgrade still route correctly when tapped.
  try {
    final parsed = jsonDecode(payload);
    if (parsed is Map) {
      return Map<String, Object?>.from(parsed);
    }
  } catch (_) {
    // Fallthrough.
  }
  final out = <String, Object?>{};
  for (final pair in payload.split(';')) {
    if (pair.isEmpty) continue;
    final i = pair.indexOf('=');
    if (i < 0) continue;
    final k = Uri.decodeComponent(pair.substring(0, i));
    final v = Uri.decodeComponent(pair.substring(i + 1));
    out[k] = v;
  }
  return out;
}

/// Bridges a [GlobalKey<NavigatorState>] to the pure-Dart
/// [NavigatorSink] interface the router consumes.  Returns false
/// when the navigator isn't mounted yet so the router logs a
/// dropped-tap warning rather than crashing.
class _NavKeyNavigatorSink implements NavigatorSink {
  final GlobalKey<NavigatorState> navKey;
  _NavKeyNavigatorSink(this.navKey);

  @override
  bool pushNamed(String route, {Object? arguments}) {
    final state = navKey.currentState;
    if (state == null) return false;
    state.pushNamed(route, arguments: arguments);
    return true;
  }
}

```
