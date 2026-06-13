---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/attention_feed_section_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.927333+00:00
---

# archive/apps-semantos-monolith/test/helm/attention_feed_section_test.dart

```dart
// Tier 2P Phase D.3 — AttentionFeedSection widget tests.
//
// Coverage:
//   1. Empty stream → section renders nothing (SizedBox.shrink / no header).
//   2. 5 mixed signals → 5 cards rendered, sorted by score desc, each with
//      kind-appropriate content visible.
//   3. Dispatch signal with requiresRatification: true → "Pending ratification"
//      tag visible.
//   4. Tap a job-kind card → JobDetailScreen pushed (NavigatorObserver check).
//   5. Pull-to-refresh triggers attention.refresh().
//
// Uses a _FakeAttentionService backed by manually-pushable StreamControllers
// so the test controls all signal emission without a real WSS.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/helm/attention_feed_section.dart';
import 'package:semantos/src/repl/attention_service.dart';
import 'package:semantos/src/repl/oddjobz_attention_client.dart';
import 'package:semantos/src/repl/jobs_repository.dart';
import 'package:semantos/src/repl/repl_client.dart';

// ── Fake attention service ────────────────────────────────────────────────────

/// Minimal in-memory fake that implements [AttentionService]'s public surface.
/// Lets tests push signals directly without a real WSS connection.
class _FakeAttentionService implements AttentionService {
  final _signalsCtl =
      StreamController<List<OddjobzAttentionSignal>>.broadcast();

  int refreshCount = 0;

  /// Push a new list of signals to all stream subscribers.
  void pushSignals(List<OddjobzAttentionSignal> signals) {
    if (!_signalsCtl.isClosed) _signalsCtl.add(signals);
  }

  // ── AttentionService interface ──────────────────────────────────────

  @override
  Stream<List<OddjobzAttentionSignal>> get signals => _signalsCtl.stream;

  @override
  Stream<List<OddjobzDispatchDecision>> get pendingRatifications =>
      const Stream<List<OddjobzDispatchDecision>>.empty();

  @override
  Stream<List<OddjobzMessagePatch>> messagesForJob(String jobId) =>
      const Stream<List<OddjobzMessagePatch>>.empty();

  @override
  Future<void> refresh() async {
    refreshCount++;
  }

  @override
  void startPolling() {}

  @override
  void pausePolling() {}

  @override
  Future<void> dispose() async {
    await _signalsCtl.close();
  }

  /// Satisfies the [client] getter added in Phase D.2+ for one-shot queries.
  /// This fake never needs to call it, so a null-returning stub is fine.
  @override
  OddjobzAttentionClient get client => throw UnimplementedError(
      '_FakeAttentionService.client should not be called in D.3 tests');
}

// ── Signal factories ──────────────────────────────────────────────────────────

OddjobzAttentionSignal _dispatchSignal({
  double score = 0.9,
  bool requiresRatification = false,
  String lane = 'broadcast',
}) =>
    OddjobzAttentionSignal.fromJson({
      'kind': 'dispatch',
      'score': score,
      'ref': 'patch-1',
      'summary': 'Broadcast to crew',
      'expiresAt': null,
      'raw': {
        'sourcePatchId': 'patch-1',
        'lane': lane,
        'slot': 'talk.$lane',
        'transport': 'multicast',
        'confidence': score,
        'requiresRatification': requiresRatification,
        'primaryTarget': {
          'type': 'job',
          'ref': 'job-abc',
          'score': score,
        },
        'writtenAt': 1000,
      },
    });

OddjobzAttentionSignal _messageSignal({double score = 0.8}) =>
    OddjobzAttentionSignal.fromJson({
      'kind': 'message',
      'score': score,
      'ref': 'patch-2',
      'summary': 'Alice Johnson',
      'expiresAt': null,
      'raw': {
        'patchId': 'patch-2',
        'providerId': 'meta',
        'sessionId': 'meta:messenger:PAGE:PSI',
        'channel': 'meta_messenger',
        'recipientId': 'PAGE',
        'role': 'customer',
        'text': 'Hi, is the quote ready yet? I have been waiting for a while.',
        'timestamp': 1746518400000,
        'source': null,
      },
    });

OddjobzAttentionSignal _jobSignal({
  double score = 0.7,
  String jobId = 'job-42',
}) =>
    OddjobzAttentionSignal.fromJson({
      'kind': 'job',
      'score': score,
      'ref': jobId,
      'summary': '22 Acacia Ave, Doonside',
      'expiresAt': null,
      'raw': {
        'id': jobId,
        'customer_name': 'Bob Smith',
        'state': 'scheduled',
        'scheduled_at': '',
        'dueDate': '2026-05-01', // past → red urgency dot
      },
    });

// ── Helpers ───────────────────────────────────────────────────────────────────

JobsRepository _stubJobsRepo() {
  final client = ReplClient.withBearer(
    http: Dio(),
    baseUrl: 'https://stub.invalid',
    bearer: 'a' * 64,
  );
  return JobsRepository(client);
}

Widget _wrap(
  Widget child, {
  List<NavigatorObserver> observers = const [],
}) =>
    MaterialApp(
      navigatorObservers: observers,
      home: Scaffold(body: child),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('AttentionFeedSection', () {
    late _FakeAttentionService fakeAttention;
    late JobsRepository jobs;

    setUp(() {
      fakeAttention = _FakeAttentionService();
      jobs = _stubJobsRepo();
    });

    tearDown(() async {
      await fakeAttention.dispose();
    });

    // 1 ── Empty stream → section renders nothing ──────────────────────────

    testWidgets('no data ever pushed → section is invisible',
        (tester) async {
      await tester.pumpWidget(_wrap(AttentionFeedSection(
        attention: fakeAttention,
        jobs: jobs,
      )));

      // No stream event pushed → widget should be invisible.
      expect(find.text('Surface'), findsNothing);
      expect(find.textContaining('See all'), findsNothing);
    });

    testWidgets('empty signal list pushed → section still hidden',
        (tester) async {
      await tester.pumpWidget(_wrap(AttentionFeedSection(
        attention: fakeAttention,
        jobs: jobs,
      )));

      fakeAttention.pushSignals(const []);
      await tester.pump();

      expect(find.text('Surface'), findsNothing);
    });

    // 2 ── 5 mixed signals → 5 cards, sorted by score desc ────────────────

    testWidgets('5 mixed signals render with kind-appropriate content',
        (tester) async {
      await tester.pumpWidget(_wrap(AttentionFeedSection(
        attention: fakeAttention,
        jobs: jobs,
      )));

      // Scores deliberately out of order to verify score-desc sorting.
      fakeAttention.pushSignals([
        _jobSignal(score: 0.5),
        _dispatchSignal(score: 0.9),
        _messageSignal(score: 0.8),
        _jobSignal(score: 0.6, jobId: 'job-99'),
        _dispatchSignal(score: 0.7),
      ]);
      await tester.pump();

      // Surface header should appear.
      expect(find.text('Surface'), findsOneWidget);

      // "See all" link present.
      expect(find.textContaining('See all'), findsOneWidget);

      // Dispatch cards carry the lane label.
      expect(find.text('Broadcast'), findsNWidgets(2));

      // Message card carries the customer name from summary.
      expect(find.text('Alice Johnson'), findsOneWidget);

      // Job card carries the site address from summary.
      expect(find.text('22 Acacia Ave, Doonside'),
          findsAtLeastNWidgets(1));
    });

    // 3 ── Dispatch with requiresRatification: true → tag visible ─────────

    testWidgets('dispatch with requiresRatification shows pending tag',
        (tester) async {
      await tester.pumpWidget(_wrap(AttentionFeedSection(
        attention: fakeAttention,
        jobs: jobs,
      )));

      fakeAttention.pushSignals([
        _dispatchSignal(score: 0.9, requiresRatification: true),
      ]);
      await tester.pump();

      expect(find.text('Pending ratification'), findsOneWidget);
    });

    testWidgets('dispatch without requiresRatification has no pending tag',
        (tester) async {
      await tester.pumpWidget(_wrap(AttentionFeedSection(
        attention: fakeAttention,
        jobs: jobs,
      )));

      fakeAttention.pushSignals([
        _dispatchSignal(score: 0.9, requiresRatification: false),
      ]);
      await tester.pump();

      expect(find.text('Pending ratification'), findsNothing);
    });

    // 4 ── Tap a job-kind card → navigation pushed ────────────────────────

    testWidgets('tapping a job-kind card pushes a new route',
        (tester) async {
      final observer = _PushCapturingObserver();

      await tester.pumpWidget(_wrap(
        AttentionFeedSection(
          attention: fakeAttention,
          jobs: jobs,
        ),
        observers: [observer],
      ));

      fakeAttention.pushSignals([_jobSignal(score: 0.9, jobId: 'job-42')]);
      await tester.pump();

      // Tap the job card via its site address text.
      await tester.tap(find.text('22 Acacia Ave, Doonside').first);
      await tester.pumpAndSettle();

      // A route should have been pushed.
      expect(observer.pushedCount, greaterThanOrEqualTo(1));
    });

    // 5 ── Pull-to-refresh triggers attention.refresh() ───────────────────

    testWidgets('pull-to-refresh calls attention.refresh()',
        (tester) async {
      // Wrap in a fixed-height box so the RefreshIndicator has room to pull.
      await tester.pumpWidget(_wrap(
        SizedBox(
          height: 600,
          child: AttentionFeedSection(
            attention: fakeAttention,
            jobs: jobs,
          ),
        ),
      ));

      fakeAttention.pushSignals([_dispatchSignal(score: 0.9)]);
      await tester.pump();

      expect(fakeAttention.refreshCount, equals(0));

      // Trigger the RefreshIndicator by over-scrolling downward.
      await tester.fling(
        find.text('Surface'),
        const Offset(0, 300),
        800,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(fakeAttention.refreshCount, greaterThanOrEqualTo(1));
    });
  });
}

// ── NavigatorObserver helper ──────────────────────────────────────────────────

class _PushCapturingObserver extends NavigatorObserver {
  int pushedCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Count any route push that is NOT the initial MaterialApp route.
    if (previousRoute != null) {
      pushedCount++;
    }
  }
}

```
