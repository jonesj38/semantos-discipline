---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/push/push_notification_router.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.872382+00:00
---

# archive/apps-semantos-monolith/lib/src/push/push_notification_router.dart

```dart
// D-O5m.followup-9 Phase C — pure-Dart deep-link routing core.
//
// Owns the "incoming push payload → helm screen" routing logic so it
// can be unit-tested without instantiating a Flutter widget tree.
// The Flutter-side wiring (FirebaseMessaging.onMessage,
// onMessageOpenedApp, getInitialMessage, flutter_local_notifications
// foreground render) lives in push_handlers.dart and calls into this
// router for the actual decision logic.
//
// Wire shape — the brain-side dispatcher embeds a `data` payload on
// every push:
//
//   {
//     "screen":  "ratify" | "job" | <future event types here>,
//     "lead_id": "<cell id>"     (when screen == "ratify")
//     "job_id":  "<cell id>"     (when screen == "job")
//   }
//
// The router decodes that data map into a typed [PushTapPayload],
// then asks the injected [NavigatorSink] to push the right route.
// Unknown screens are NOT silently dropped — they're logged and
// surfaced via [LogSink] so an out-of-band event type added on the
// brain side without a corresponding mobile route shows up in QA.

/// Sealed family of typed routing decisions extracted from the
/// notification's `data` map.  Exposed for tests + the Flutter
/// router so the Flutter side does the same switch the tests do.
sealed class PushTapPayload {
  const PushTapPayload();
}

/// `screen=ratify` + `lead_id=<id>` → opens the ratification card
/// for the lead.  The `/ratify` route doesn't exist in the helm shell
/// yet (D-O5m.followup-7 ships it); the router still emits the
/// pushNamed call, the navigator falls through to the unknown-route
/// handler, and PushNotificationRouter logs a warning so QA spots it.
class RatifyLeadTap extends PushTapPayload {
  final String leadId;
  const RatifyLeadTap(this.leadId);
}

/// `screen=job` + `job_id=<id>` → opens the job detail screen.  The
/// `/job/:id` route is owned by HomeScreen → JobListScreen →
/// JobDetailScreen; the router pushes the named route the screen
/// registers.
class JobDetailTap extends PushTapPayload {
  final String jobId;
  const JobDetailTap(this.jobId);
}

/// Unknown / malformed payload — typically a brain-side event type
/// that doesn't have a mobile route yet.  The router logs the raw
/// data map via the injected [LogSink].
class UnknownPushTap extends PushTapPayload {
  /// The raw `screen` value the payload carried (or null if absent).
  final String? screen;
  final Map<String, Object?> rawData;
  const UnknownPushTap({this.screen, required this.rawData});
}

/// Decode a push payload's `data` map into a typed routing decision.
/// Pure function — no I/O, no Flutter dependencies.
PushTapPayload decodePushTap(Map<String, Object?> data) {
  final screen = data['screen'];
  if (screen is! String) {
    return UnknownPushTap(screen: null, rawData: data);
  }
  switch (screen) {
    case 'ratify':
      final leadId = data['lead_id'];
      if (leadId is String && leadId.isNotEmpty) {
        return RatifyLeadTap(leadId);
      }
      return UnknownPushTap(screen: screen, rawData: data);
    case 'job':
      final jobId = data['job_id'];
      if (jobId is String && jobId.isNotEmpty) {
        return JobDetailTap(jobId);
      }
      return UnknownPushTap(screen: screen, rawData: data);
    default:
      return UnknownPushTap(screen: screen, rawData: data);
  }
}

/// Minimal Navigator-like sink the router calls into.  Tests inject
/// a recording impl; production wraps `navKey.currentState?.pushNamed`.
abstract class NavigatorSink {
  /// Push a named route, optionally with arguments.  Returns false
  /// when the navigator isn't ready yet (router logs and drops the
  /// tap).
  bool pushNamed(String route, {Object? arguments});
}

/// Recording sink — used by the unit tests.  Stores every call so
/// the test can assert ordering + arguments.
class RecordingNavigatorSink implements NavigatorSink {
  final List<({String route, Object? arguments})> calls = [];

  /// When false, [pushNamed] returns false (simulates a not-yet-
  /// mounted navigator).  Default true so happy-path tests don't
  /// have to flip a flag.
  bool ready;

  RecordingNavigatorSink({this.ready = true});

  @override
  bool pushNamed(String route, {Object? arguments}) {
    if (!ready) return false;
    calls.add((route: route, arguments: arguments));
    return true;
  }
}

/// Sink that the router writes warnings + structured events to.
/// Tests inject a recording impl; production uses a thin print
/// shim.  Keeping the seam explicit lets us swap in a structured
/// audit log if/when the helm gains one (D-O5m.followup-N).
abstract class LogSink {
  void warn(String message);
}

/// Prints to stdout — the production default.  Avoids dragging in
/// `package:logging` for a single warn() call.
class StdoutLogSink implements LogSink {
  const StdoutLogSink();
  @override
  void warn(String message) {
    // ignore: avoid_print
    print('[push-router] $message');
  }
}

/// Recording log sink for tests.
class RecordingLogSink implements LogSink {
  final List<String> warnings = [];
  @override
  void warn(String message) => warnings.add(message);
}

/// Pure-Dart routing core.  Hand it a [NavigatorSink] + [LogSink];
/// it owns the decision logic.  PushHandlers (in push_handlers.dart)
/// wires this up to FirebaseMessaging callbacks and a
/// `GlobalKey<NavigatorState>`.
class PushNotificationRouter {
  final NavigatorSink _navigator;
  final LogSink _log;

  PushNotificationRouter({
    required NavigatorSink navigator,
    LogSink log = const StdoutLogSink(),
  })  : _navigator = navigator,
        _log = log;

  /// Decode + dispatch a tapped notification's data map.  Returns
  /// the typed decision so callers can assert in tests.
  PushTapPayload routeTap(Map<String, Object?> data) {
    final payload = decodePushTap(data);
    switch (payload) {
      case RatifyLeadTap(:final leadId):
        final ok = _navigator.pushNamed(
          '/ratify',
          arguments: {'lead_id': leadId},
        );
        if (!ok) {
          _log.warn(
            'navigator not ready for /ratify (lead_id=$leadId) — dropped tap',
          );
        }
        // The /ratify route is owned by D-O5m.followup-7; if it
        // hasn't been registered yet, the navigator's
        // onUnknownRoute handler will fall back to home and the
        // helm shell logs the miss here.
      case JobDetailTap(:final jobId):
        final ok = _navigator.pushNamed('/job/$jobId');
        if (!ok) {
          _log.warn(
            'navigator not ready for /job/$jobId — dropped tap',
          );
        }
      case UnknownPushTap(:final screen, :final rawData):
        _log.warn(
          'unknown push screen=${screen ?? "<missing>"} data=$rawData '
          '— no route taken',
        );
    }
    return payload;
  }
}

```
