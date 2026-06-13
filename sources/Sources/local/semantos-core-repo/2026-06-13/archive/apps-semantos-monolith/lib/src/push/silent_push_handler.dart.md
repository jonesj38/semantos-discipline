---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/push/silent_push_handler.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.872685+00:00
---

# archive/apps-semantos-monolith/lib/src/push/silent_push_handler.dart

```dart
// Sovereign-push D.2 — pure-Dart silent-push handler.
//
// Owns the wake-only push pipeline:
//
//   1. Decode the wake envelope ({event_id, ts, kind}) — these are
//      the only fields APNs/FCM ever see.
//   2. Open (or reuse) a WSS connection to the brain via the
//      injected [HelmEventStreamLike] factory.
//   3. Call `helm.fetch_since(since_ts=lastSeen)` to get the actual
//      event content.
//   4. Render one local notification per returned event whose `kind`
//      warrants a banner — title + body composed from the payload.
//   5. Advance the [LastSeenStore] cursor to the highest `ts`
//      returned (or the brain's `next_cursor_ts` echo when newer).
//
// Why this lives in its own file and is import-clean of Flutter:
// the unit-test suite drives this through in-memory fakes for the
// notification surface + the WSS so the handler logic can be tested
// without spinning up the platform plugin.  push_handlers.dart wires
// the production adapters in.
//
// Failure model — mirrors the spec: a failed fetch (timeout, broker
// error, connection refused) is silent.  The operator does not see
// "fetch failed" notifications.  The next foregrounding of the app
// will re-establish the live HelmEventStream which back-fills any
// missed events through the same fetch_since call.

import 'dart:async';

import '../repl/helm_event_stream.dart'
    show FetchSinceResult, HelmEvent, HelmEventStream;
import 'last_seen_store.dart';

/// The minimal HelmEventStream surface the silent handler depends on.
/// Production wires this to [HelmEventStream]; tests inject a fake
/// that returns a canned [FetchSinceResult] without opening a real
/// socket.  Defined here so the handler test doesn't have to depend
/// on `web_socket_channel`.
abstract class HelmEventStreamLike {
  /// Connect (or no-op when already connected).  The silent handler
  /// always calls this first — the underlying impl is idempotent.
  Future<void> connect();

  /// Issue `helm.fetch_since` and await the brain's reply.
  Future<FetchSinceResult> fetchSince({
    int? sinceTs,
    int? limit,
    Duration timeout,
  });

  /// Tear down — called when the silent handler builds an ephemeral
  /// stream (no live helm UI in the foreground) and wants to release
  /// the socket after rendering.
  Future<void> dispose();
}

/// Renders one local notification.  Production wires this to
/// `flutter_local_notifications` via [FlutterLocalNotificationsSink];
/// tests inject [RecordingNotificationSink] to assert what would
/// have been shown.
abstract class LocalNotificationSink {
  /// Show a notification with the given (id, title, body, payload).
  /// Returns true on success, false if the platform refused (e.g.
  /// notifications not authorised on iOS).
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required Map<String, String> payload,
  });
}

/// In-memory test sink — records every show() call so the test
/// suite can assert ordering + content.  Production never uses this.
class RecordingNotificationSink implements LocalNotificationSink {
  final List<({int id, String title, String body, Map<String, String> payload})>
      shown = [];
  bool nextResult = true;

  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required Map<String, String> payload,
  }) async {
    shown.add((id: id, title: title, body: body, payload: payload));
    return nextResult;
  }
}

/// Composes a (title, body) banner pair from a brain-side event
/// payload.  Pure function — the silent handler calls this for every
/// event returned by `helm.fetch_since` whose `kind` it knows how to
/// render.  Returning null means "no banner for this event kind"
/// (e.g. internal event types the operator doesn't need a wake-up
/// for; the live stream still consumes them).
class HelmEventBanner {
  final String title;
  final String body;
  /// Payload stored with the local notification — surfaces back to
  /// `PushNotificationRouter.routeTap` when the operator taps the
  /// banner so the router can deep-link without another fetch.
  final Map<String, String> tapPayload;

  const HelmEventBanner({
    required this.title,
    required this.body,
    required this.tapPayload,
  });
}

/// Render a [HelmEvent] into a [HelmEventBanner], or null when the
/// event kind is informational-only and shouldn't wake the operator.
///
/// The known kinds map 1:1 to the deep-link surfaces
/// `PushNotificationRouter` already understands (`screen=ratify` →
/// `/ratify`; `screen=job` → `/job/<id>`).  An unknown kind falls
/// through to a generic banner so the operator still gets a wake;
/// the router will log the unknown screen on tap.
HelmEventBanner? composeBanner(HelmEvent event) {
  final data = event.data;
  switch (event.type) {
    case 'lead.created':
      final id = (data['id'] ?? '').toString();
      final customer = (data['customer_name'] ?? '').toString();
      final summary = (data['summary'] ?? '').toString();
      final title =
          customer.isNotEmpty ? 'New lead — $customer' : 'New lead';
      final body = summary.isNotEmpty ? summary : 'Tap to ratify';
      return HelmEventBanner(
        title: title,
        body: body,
        tapPayload: {
          'screen': 'ratify',
          'lead_id': id,
          'event_id': event.eventId,
          'kind': event.type,
        },
      );
    case 'job.transitioned':
      final id = (data['id'] ?? '').toString();
      final from = (data['from'] ?? '').toString();
      final to = (data['to'] ?? '').toString();
      final body = (from.isNotEmpty && to.isNotEmpty)
          ? 'Moved from $from → $to'
          : 'Status updated';
      return HelmEventBanner(
        title: 'Job updated',
        body: body,
        tapPayload: {
          'screen': 'job',
          'job_id': id,
          'event_id': event.eventId,
          'kind': event.type,
        },
      );
    default:
      // Unknown kind — fall through to a generic banner.  Skipping
      // would mean the operator's phone wakes for nothing the user
      // can see; an unknown banner at least gives them the chance to
      // open the app and discover the new event in the helm.
      return HelmEventBanner(
        title: 'oddjobz',
        body: 'New activity — open to view',
        tapPayload: {
          'screen': 'unknown',
          'event_id': event.eventId,
          'kind': event.type,
        },
      );
  }
}

/// Configuration for one [SilentPushHandler] invocation.  Bound to
/// a single brain endpoint — re-pairings construct a fresh handler.
class SilentPushHandlerDeps {
  final HelmEventStreamLike Function() openStream;
  final LocalNotificationSink notifications;
  final LastSeenStore lastSeen;

  /// IDs the live HelmEventStream has already surfaced in the current
  /// foreground session.  When non-null, the silent handler skips
  /// notifications whose event_id appears in the set so a wake that
  /// arrives while the app is open doesn't double-render.  Pass null
  /// (the background-isolate default) to disable dedupe.
  final Set<String>? alreadyShownEventIds;

  const SilentPushHandlerDeps({
    required this.openStream,
    required this.notifications,
    required this.lastSeen,
    this.alreadyShownEventIds,
  });
}

/// Result of one silent-push processing pass.  Returned for tests
/// + log triage; production callers can ignore it.
class SilentPushResult {
  /// Number of local notifications successfully shown.  Zero is a
  /// success result when fetch_since returned no new events (e.g.
  /// the live stream had already pulled them).
  final int notificationsShown;

  /// Number of events the handler suppressed because their event_id
  /// was already in [SilentPushHandlerDeps.alreadyShownEventIds].
  final int dedupedSkipped;

  /// True when the cursor was advanced past the request's value.
  /// False on a fetch error (no cursor write happens).
  final bool cursorAdvanced;

  /// The new cursor value persisted to [LastSeenStore], or the
  /// previous one when no advance happened.
  final int newCursor;

  /// On error, the captured exception.  null on success.
  final Object? error;

  const SilentPushResult({
    required this.notificationsShown,
    required this.dedupedSkipped,
    required this.cursorAdvanced,
    required this.newCursor,
    this.error,
  });
}

/// Adapter that wraps a real [HelmEventStream] into the
/// [HelmEventStreamLike] surface the silent handler consumes.
/// Two adapter modes:
///
///   - `shared`: the wrapped stream is owned by the foreground UI
///     (e.g. HomeScreen's `_eventStream`).  `dispose()` is a no-op
///     so the silent handler doesn't tear down the live helm
///     connection out from under the foreground.
///
///   - `owned`: the wrapped stream was constructed by the silent
///     handler itself (the background-isolate path that has no
///     foreground UI to share with).  `dispose()` calls through to
///     the underlying stream's dispose so the WSS releases promptly
///     after the fetch completes.
class HelmEventStreamAdapter implements HelmEventStreamLike {
  final HelmEventStream _inner;
  final bool _ownsStream;

  HelmEventStreamAdapter.shared(HelmEventStream inner)
      : _inner = inner,
        _ownsStream = false;

  HelmEventStreamAdapter.owned(HelmEventStream inner)
      : _inner = inner,
        _ownsStream = true;

  @override
  Future<void> connect() => _inner.connect();

  @override
  Future<FetchSinceResult> fetchSince({
    int? sinceTs,
    int? limit,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _inner.fetchSince(sinceTs: sinceTs, limit: limit, timeout: timeout);

  @override
  Future<void> dispose() async {
    if (_ownsStream) await _inner.dispose();
  }
}

/// Pure-Dart silent-push handler.  Construct, call [handle] from
/// the wake callback, dispose.
class SilentPushHandler {
  final SilentPushHandlerDeps _deps;

  SilentPushHandler(this._deps);

  /// Process one wake envelope.  The envelope's own `event_id` and
  /// `ts` are not consumed directly — they're advisory (the handler
  /// trusts the brain's `helm.fetch_since` cursor over the wake
  /// payload, which can race the live event stream).
  ///
  /// Errors are CAUGHT and surfaced via [SilentPushResult.error].
  /// The handler never throws into the FirebaseMessaging callback
  /// (which would deliver the operator a "fetch failed" toast on
  /// some Android versions).  Operator-visible silence on failure
  /// is the spec.
  Future<SilentPushResult> handle({
    Map<String, String>? wakeEnvelope,
  }) async {
    final stream = _deps.openStream();
    var notificationsShown = 0;
    var dedupedSkipped = 0;
    var newCursor = await _deps.lastSeen.read();
    final initialCursor = newCursor;

    try {
      await stream.connect();
      final result = await stream.fetchSince(
        sinceTs: initialCursor,
        timeout: const Duration(seconds: 10),
      );

      for (final event in result.events) {
        // Dedupe against the live stream — a wake arriving while the
        // foreground UI is connected may pull an event the live
        // helm.event notify already handed to the helm.  We skip the
        // banner for that case so the operator doesn't see a duplicate.
        // Same dedupe also catches a second wake for the same event
        // within the same isolate — e.g. an APNs retry — because the
        // first wake's render path records the event_id below.
        final id = event.eventId;
        if (id.isNotEmpty &&
            _deps.alreadyShownEventIds != null &&
            _deps.alreadyShownEventIds!.contains(id)) {
          dedupedSkipped += 1;
          continue;
        }

        final banner = composeBanner(event);
        if (banner == null) continue;
        // Record the event_id BEFORE the show() call so a re-entrant
        // wake arriving mid-render still dedupes.  No-op when the
        // dedupe set is null (background isolate) or the event_id is
        // empty (live-notify shape, pre-D.1).
        if (id.isNotEmpty && _deps.alreadyShownEventIds != null) {
          _deps.alreadyShownEventIds!.add(id);
        }
        // Use the event's ts as the notification id when present so
        // the OS coalesces re-deliveries for the same event_id.
        // Fallback to the event_id hashCode keeps things unique
        // when ts is zero.
        final notifId = event.ts != 0
            ? event.ts
            : (id.isNotEmpty
                ? id.hashCode
                : DateTime.now().millisecondsSinceEpoch);
        final ok = await _deps.notifications.show(
          id: notifId,
          title: banner.title,
          body: banner.body,
          payload: banner.tapPayload,
        );
        if (ok) notificationsShown += 1;
      }

      // Advance cursor to the higher of (max ts seen, brain's
      // next_cursor_ts).  Both advance monotonically; we trust the
      // brain's echo when the events list was empty.
      var maxTs = result.nextCursorTs;
      for (final ev in result.events) {
        if (ev.ts > maxTs) maxTs = ev.ts;
      }
      if (maxTs > initialCursor) {
        await _deps.lastSeen.write(maxTs);
        newCursor = maxTs;
      }

      return SilentPushResult(
        notificationsShown: notificationsShown,
        dedupedSkipped: dedupedSkipped,
        cursorAdvanced: newCursor > initialCursor,
        newCursor: newCursor,
      );
    } catch (e) {
      // Spec: on failure, silently retry on next app foreground.
      // No "fetch failed" notification, no operator-visible error.
      return SilentPushResult(
        notificationsShown: notificationsShown,
        dedupedSkipped: dedupedSkipped,
        cursorAdvanced: false,
        newCursor: initialCursor,
        error: e,
      );
    } finally {
      // The stream factory decides whether to keep the connection
      // open — for the foreground path it returns the live shared
      // HelmEventStream and dispose is a no-op; for the background
      // path it returns a throwaway stream that this handler tears
      // down here.
      try {
        await stream.dispose();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }
}

```
