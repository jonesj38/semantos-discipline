---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/push/push_handlers_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.915678+00:00
---

# archive/apps-semantos-monolith/test/push/push_handlers_test.dart

```dart
// Sovereign-push D.2 — push handlers + silent-push handler tests.
//
// Two coverage scopes:
//
// 1. push_notification_router (pure-Dart): tap-routing decode +
//    /ratify, /job/<id> dispatch, navigator-not-ready warnings.
//    Pre-D.2 surface; still load-bearing because the router runs
//    on every notification tap.
//
// 2. silent_push_handler (D.2): wake-only payload triggers
//    helm.fetch_since, banners are rendered locally, last-seen
//    cursor advances, WSS failures are silent (no notification).
//
// Both scopes stay Flutter-SDK-free under `dart test` — the
// silent-handler test injects a fake HelmEventStreamLike + a
// RecordingNotificationSink so the suite doesn't need to spin up
// flutter_local_notifications or web_socket_channel.

import 'dart:async';

import 'package:test/test.dart';

import 'package:semantos/src/identity/child_cert_store.dart'
    show InMemorySecureStore;
import 'package:semantos/src/push/last_seen_store.dart';
import 'package:semantos/src/push/push_notification_router.dart';
import 'package:semantos/src/push/silent_push_handler.dart';
import 'package:semantos/src/repl/helm_event_stream.dart';

void main() {
  group('decodePushTap', () {
    test('screen=ratify + lead_id returns RatifyLeadTap', () {
      final r = decodePushTap({'screen': 'ratify', 'lead_id': 'lead-001'});
      expect(r, isA<RatifyLeadTap>());
      expect((r as RatifyLeadTap).leadId, equals('lead-001'));
    });

    test('screen=job + job_id returns JobDetailTap', () {
      final r = decodePushTap({'screen': 'job', 'job_id': 'job-abc'});
      expect(r, isA<JobDetailTap>());
      expect((r as JobDetailTap).jobId, equals('job-abc'));
    });

    test('screen=ratify without lead_id returns UnknownPushTap', () {
      final r = decodePushTap({'screen': 'ratify'});
      expect(r, isA<UnknownPushTap>());
      expect((r as UnknownPushTap).screen, equals('ratify'));
    });

    test('unknown screen returns UnknownPushTap with raw screen', () {
      final r = decodePushTap({'screen': 'nope', 'foo': 'bar'});
      expect(r, isA<UnknownPushTap>());
      expect((r as UnknownPushTap).screen, equals('nope'));
    });

    test('missing screen field returns UnknownPushTap with null screen', () {
      final r = decodePushTap({'lead_id': 'l-1'});
      expect(r, isA<UnknownPushTap>());
      expect((r as UnknownPushTap).screen, isNull);
    });
  });

  group('PushNotificationRouter.routeTap', () {
    test('routes ratify tap to /ratify with lead_id argument', () {
      final nav = RecordingNavigatorSink();
      final log = RecordingLogSink();
      final router = PushNotificationRouter(navigator: nav, log: log);

      final payload = router.routeTap({
        'screen': 'ratify',
        'lead_id': 'lead-42',
      });
      expect(payload, isA<RatifyLeadTap>());
      expect(nav.calls.length, equals(1));
      expect(nav.calls.first.route, equals('/ratify'));
      expect(nav.calls.first.arguments, equals({'lead_id': 'lead-42'}));
      expect(log.warnings, isEmpty);
    });

    test('routes job tap to /job/<id>', () {
      final nav = RecordingNavigatorSink();
      final router = PushNotificationRouter(navigator: nav);

      router.routeTap({'screen': 'job', 'job_id': 'job-7'});
      expect(nav.calls.length, equals(1));
      expect(nav.calls.first.route, equals('/job/job-7'));
    });

    test('unknown screen logs a warning + does not push', () {
      final nav = RecordingNavigatorSink();
      final log = RecordingLogSink();
      final router = PushNotificationRouter(navigator: nav, log: log);

      router.routeTap({'screen': 'unknown_event_type'});
      expect(nav.calls, isEmpty);
      expect(log.warnings.length, equals(1));
      expect(log.warnings.first, contains('unknown_event_type'));
    });

    test('navigator not ready logs a dropped-tap warning', () {
      final nav = RecordingNavigatorSink(ready: false);
      final log = RecordingLogSink();
      final router = PushNotificationRouter(navigator: nav, log: log);

      router.routeTap({'screen': 'ratify', 'lead_id': 'lead-99'});
      expect(nav.calls, isEmpty);
      expect(log.warnings.length, equals(1));
      expect(log.warnings.first, contains('lead-99'));
    });

    test('cold-start initial tap routes the same as a warm tap', () {
      // Simulates the FirebaseMessaging.getInitialMessage() path —
      // the router doesn't care which call site fed it the data.
      final nav = RecordingNavigatorSink();
      final router = PushNotificationRouter(navigator: nav);

      // Initial-message data — a ratify tap from a cold start.
      router.routeTap({'screen': 'ratify', 'lead_id': 'cold-start-lead'});
      expect(nav.calls.first.route, equals('/ratify'));
      expect(nav.calls.first.arguments, equals({'lead_id': 'cold-start-lead'}));
    });
  });

  group('composeBanner', () {
    test('lead.created builds a Ratify banner with customer + summary', () {
      final ev = HelmEvent(
        type: 'lead.created',
        eventId: '0000000000000001',
        ts: 1_700_000_001,
        data: const {
          'id': 'L1',
          'customer_name': 'Alice',
          'summary': 'Wants kitchen remodel quote',
        },
      );
      final banner = composeBanner(ev)!;
      expect(banner.title, equals('New lead — Alice'));
      expect(banner.body, equals('Wants kitchen remodel quote'));
      expect(banner.tapPayload['screen'], equals('ratify'));
      expect(banner.tapPayload['lead_id'], equals('L1'));
      expect(banner.tapPayload['event_id'], equals('0000000000000001'));
      expect(banner.tapPayload['kind'], equals('lead.created'));
    });

    test('job.transitioned builds a Job banner with from/to', () {
      final ev = HelmEvent(
        type: 'job.transitioned',
        eventId: '0000000000000002',
        ts: 1_700_000_002,
        data: const {'id': 'J1', 'from': 'lead', 'to': 'quoted'},
      );
      final banner = composeBanner(ev)!;
      expect(banner.title, equals('Job updated'));
      expect(banner.body, contains('lead'));
      expect(banner.body, contains('quoted'));
      expect(banner.tapPayload['screen'], equals('job'));
      expect(banner.tapPayload['job_id'], equals('J1'));
    });

    test('unknown kind falls through to a generic banner', () {
      final ev = HelmEvent(
        type: 'voice.captured',
        eventId: '0000000000000003',
        ts: 1_700_000_003,
        data: const {},
      );
      final banner = composeBanner(ev)!;
      expect(banner.title, equals('oddjobz'));
      expect(banner.tapPayload['screen'], equals('unknown'));
      expect(banner.tapPayload['kind'], equals('voice.captured'));
    });
  });

  group('SilentPushHandler', () {
    test('wake triggers helm.fetch_since with persisted lastSeen cursor',
        () async {
      final secure = InMemorySecureStore();
      final lastSeen = LastSeenStore(
        secureStore: secure,
        brainEndpoint: 'https://brain.example/',
      );
      await lastSeen.write(1_700_000_005);

      final fake = _FakeHelmStream(
        result: FetchSinceResult(events: const [], nextCursorTs: 1_700_000_005),
      );
      final notifications = RecordingNotificationSink();

      final handler = SilentPushHandler(SilentPushHandlerDeps(
        openStream: () => fake,
        notifications: notifications,
        lastSeen: lastSeen,
      ));

      final result = await handler.handle(
        wakeEnvelope: const {'event_id': 'x', 'ts': '1700000005'},
      );
      expect(result.error, isNull);
      expect(fake.fetchCalls, hasLength(1));
      expect(fake.fetchCalls.first.sinceTs, equals(1_700_000_005));
      expect(notifications.shown, isEmpty);
    });

    test('renders one local notification per fetched event', () async {
      final secure = InMemorySecureStore();
      final lastSeen = LastSeenStore(
        secureStore: secure,
        brainEndpoint: 'https://brain.example/',
      );

      final fake = _FakeHelmStream(
        result: FetchSinceResult(
          events: [
            HelmEvent(
              type: 'lead.created',
              eventId: '0000000000000001',
              ts: 1_700_000_001,
              data: const {
                'id': 'L1',
                'customer_name': 'Alice',
                'summary': 'kitchen remodel',
              },
            ),
            HelmEvent(
              type: 'job.transitioned',
              eventId: '0000000000000002',
              ts: 1_700_000_002,
              data: const {'id': 'J1', 'from': 'lead', 'to': 'quoted'},
            ),
          ],
          nextCursorTs: 1_700_000_002,
        ),
      );
      final notifications = RecordingNotificationSink();

      final handler = SilentPushHandler(SilentPushHandlerDeps(
        openStream: () => fake,
        notifications: notifications,
        lastSeen: lastSeen,
      ));

      final result = await handler.handle();
      expect(result.error, isNull);
      expect(result.notificationsShown, equals(2));
      expect(notifications.shown, hasLength(2));
      expect(notifications.shown[0].title, equals('New lead — Alice'));
      expect(notifications.shown[0].body, equals('kitchen remodel'));
      expect(notifications.shown[1].title, equals('Job updated'));
      expect(notifications.shown[1].payload['job_id'], equals('J1'));
    });

    test('cursor advances to highest ts returned', () async {
      final secure = InMemorySecureStore();
      final lastSeen = LastSeenStore(
        secureStore: secure,
        brainEndpoint: 'https://brain.example/',
      );
      final fake = _FakeHelmStream(
        result: FetchSinceResult(
          events: [
            HelmEvent(
              type: 'lead.created',
              eventId: '0000000000000001',
              ts: 1_700_000_010,
              data: const {'id': 'L1'},
            ),
            HelmEvent(
              type: 'lead.created',
              eventId: '0000000000000002',
              ts: 1_700_000_050,
              data: const {'id': 'L2'},
            ),
          ],
          nextCursorTs: 1_700_000_050,
        ),
      );

      final handler = SilentPushHandler(SilentPushHandlerDeps(
        openStream: () => fake,
        notifications: RecordingNotificationSink(),
        lastSeen: lastSeen,
      ));

      final result = await handler.handle();
      expect(result.cursorAdvanced, isTrue);
      expect(result.newCursor, equals(1_700_000_050));
      expect(await lastSeen.read(), equals(1_700_000_050));
    });

    test('WSS connect failure is silent — no notifications, cursor unchanged',
        () async {
      final secure = InMemorySecureStore();
      final lastSeen = LastSeenStore(
        secureStore: secure,
        brainEndpoint: 'https://brain.example/',
      );
      await lastSeen.write(1_700_000_005);

      final fake = _FakeHelmStream(throwOnConnect: true);
      final notifications = RecordingNotificationSink();

      final handler = SilentPushHandler(SilentPushHandlerDeps(
        openStream: () => fake,
        notifications: notifications,
        lastSeen: lastSeen,
      ));

      final result = await handler.handle();
      expect(result.error, isNotNull);
      expect(result.notificationsShown, equals(0));
      expect(notifications.shown, isEmpty);
      expect(await lastSeen.read(), equals(1_700_000_005));
    });

    test('fetch_since timeout is silent — no notifications, cursor unchanged',
        () async {
      final secure = InMemorySecureStore();
      final lastSeen = LastSeenStore(
        secureStore: secure,
        brainEndpoint: 'https://brain.example/',
      );
      await lastSeen.write(1_700_000_005);

      final fake = _FakeHelmStream(
        throwOnFetch: const HelmFetchSinceTimeout(Duration(seconds: 10)),
      );
      final notifications = RecordingNotificationSink();

      final handler = SilentPushHandler(SilentPushHandlerDeps(
        openStream: () => fake,
        notifications: notifications,
        lastSeen: lastSeen,
      ));

      final result = await handler.handle();
      expect(result.error, isA<HelmFetchSinceTimeout>());
      expect(notifications.shown, isEmpty);
      expect(await lastSeen.read(), equals(1_700_000_005));
    });

    test('event already in dedupe set is skipped', () async {
      final lastSeen = LastSeenStore(
        secureStore: InMemorySecureStore(),
        brainEndpoint: 'https://brain.example/',
      );
      final dedupe = <String>{'0000000000000001'};
      final fake = _FakeHelmStream(
        result: FetchSinceResult(
          events: [
            HelmEvent(
              type: 'lead.created',
              eventId: '0000000000000001',
              ts: 1_700_000_001,
              data: const {'id': 'L1'},
            ),
            HelmEvent(
              type: 'lead.created',
              eventId: '0000000000000002',
              ts: 1_700_000_002,
              data: const {'id': 'L2'},
            ),
          ],
          nextCursorTs: 1_700_000_002,
        ),
      );
      final notifications = RecordingNotificationSink();

      final handler = SilentPushHandler(SilentPushHandlerDeps(
        openStream: () => fake,
        notifications: notifications,
        lastSeen: lastSeen,
        alreadyShownEventIds: dedupe,
      ));

      final result = await handler.handle();
      expect(result.dedupedSkipped, equals(1));
      expect(result.notificationsShown, equals(1));
      expect(notifications.shown, hasLength(1));
      expect(notifications.shown.first.payload['event_id'],
          equals('0000000000000002'));
      // Dedupe set updated with the freshly-rendered event_id so a
      // re-entrant wake within the same isolate doesn't double-show.
      expect(dedupe, contains('0000000000000002'));
    });

    test('handler always disposes the stream factory it built', () async {
      final lastSeen = LastSeenStore(
        secureStore: InMemorySecureStore(),
        brainEndpoint: 'https://brain.example/',
      );
      final fake = _FakeHelmStream(
        result: const FetchSinceResult(events: [], nextCursorTs: 0),
      );
      final handler = SilentPushHandler(SilentPushHandlerDeps(
        openStream: () => fake,
        notifications: RecordingNotificationSink(),
        lastSeen: lastSeen,
      ));
      await handler.handle();
      expect(fake.disposed, isTrue);
    });
  });
}

class _FetchCall {
  final int? sinceTs;
  final int? limit;
  final Duration timeout;
  _FetchCall({this.sinceTs, this.limit, required this.timeout});
}

class _FakeHelmStream implements HelmEventStreamLike {
  final FetchSinceResult? result;
  final Object? throwOnFetch;
  final bool throwOnConnect;
  final List<_FetchCall> fetchCalls = [];
  bool connected = false;
  bool disposed = false;

  _FakeHelmStream({
    this.result,
    this.throwOnFetch,
    this.throwOnConnect = false,
  });

  @override
  Future<void> connect() async {
    if (throwOnConnect) {
      throw const HelmFetchSinceError(-32000, 'simulated connect failure');
    }
    connected = true;
  }

  @override
  Future<FetchSinceResult> fetchSince({
    int? sinceTs,
    int? limit,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    fetchCalls.add(_FetchCall(
      sinceTs: sinceTs,
      limit: limit,
      timeout: timeout,
    ));
    if (throwOnFetch != null) {
      throw throwOnFetch!;
    }
    if (result != null) return result!;
    throw const HelmFetchSinceError(-32603, 'no result configured');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

```
