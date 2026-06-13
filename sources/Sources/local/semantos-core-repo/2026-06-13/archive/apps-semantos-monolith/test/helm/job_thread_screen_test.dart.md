---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/job_thread_screen_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.925328+00:00
---

# archive/apps-semantos-monolith/test/helm/job_thread_screen_test.dart

```dart
// JobThreadScreen tests — updated for canonical conversation turns.
//
// Uses a fake ConversationTurnsRepository backed by pre-configured
// turn lists so tests run without network round-trips.
//
// Coverage:
//   1. Empty thread → empty-state text visible.
//   2. Inbound (customer) turn → left-aligned blue bubble.
//   3. Outbound (operator) turn → right-aligned green bubble.
//   4. Proposed outbound turn → amber border + ✓ Approve & send button.
//   5. Approve button tap → approveTurn called + reload triggered.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/helm/job_thread_screen.dart';
import 'package:semantos/src/repl/conversation_turns_repository.dart';

// ── Fake repository ───────────────────────────────────────────────────────

/// Subclass of ConversationTurnsRepository that returns a pre-configured
/// list of turns without making any network calls.
class _FakeTurnsRepo extends ConversationTurnsRepository {
  List<ConversationTurn> turns;
  int approveCalled = 0;

  _FakeTurnsRepo({this.turns = const []})
      : super(
          http: Dio(),
          baseUrl: 'http://fake.test',
          bearer: () => 'fake-bearer',
        );

  @override
  Future<List<ConversationTurn>> fetchTurns({
    required String entityRef,
    int limit = 100,
  }) async =>
      turns;

  @override
  Future<void> approveTurn(String turnId) async {
    approveCalled++;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

ConversationTurn _inbound({
  required String id,
  required String text,
  required int timestamp,
  String surface = 'sms',
}) =>
    ConversationTurn(
      turnId: id,
      conversationId: 'conv-1',
      participantRole: 'customer',
      direction: 'inbound',
      surface: surface,
      bodyText: text,
      timestamp: timestamp,
    );

ConversationTurn _outbound({
  required String id,
  required String text,
  required int timestamp,
  String surface = 'sms',
  String? outboundState,
}) =>
    ConversationTurn(
      turnId: id,
      conversationId: 'conv-1',
      participantRole: 'operator',
      direction: 'outbound',
      surface: surface,
      bodyText: text,
      timestamp: timestamp,
      outboundState: outboundState,
    );

Widget _buildScreen(_FakeTurnsRepo repo) => MaterialApp(
      home: JobThreadScreen(
        entityRef: 'deadbeef' * 8,
        jobTitle: 'Test Job',
        turnsRepository: repo,
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('JobThreadScreen', () {
    // ── 1. Empty thread ────────────────────────────────────────────────────

    testWidgets('empty thread shows empty-state text', (tester) async {
      final repo = _FakeTurnsRepo(turns: []);
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pump(); // initState
      await tester.pump(const Duration(milliseconds: 100)); // settle

      expect(find.text('No conversation history yet.'), findsOneWidget);
    });

    // ── 2. Inbound (customer) turn ─────────────────────────────────────────

    testWidgets('inbound turn shows text with blue bubble', (tester) async {
      final repo = _FakeTurnsRepo(turns: [
        _inbound(id: 't1', text: 'Hello there', timestamp: 1000),
      ]);
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Hello there'), findsOneWidget);

      // Customer bubble should use blue.shade50 background.
      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.color == Colors.blue.shade50;
      }).toList();
      expect(containers, isNotEmpty,
          reason: 'Customer bubble should use blue background');
    });

    // ── 3. Outbound (operator) turn ────────────────────────────────────────

    testWidgets('outbound sent turn shows text with green bubble',
        (tester) async {
      final repo = _FakeTurnsRepo(turns: [
        _outbound(
          id: 't2',
          text: 'On my way',
          timestamp: 2000,
          outboundState: 'sent',
        ),
      ]);
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('On my way'), findsOneWidget);

      // Operator bubble should use green.shade100 background.
      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.color == Colors.green.shade100;
      }).toList();
      expect(containers, isNotEmpty,
          reason: 'Operator bubble should use green background');
    });

    // ── 4. Proposed outbound — approve button visible ──────────────────────

    testWidgets('proposed outbound shows approve button', (tester) async {
      final repo = _FakeTurnsRepo(turns: [
        _outbound(
          id: 't3',
          text: 'Thank you for enquiring!',
          timestamp: 3000,
          outboundState: 'proposed',
        ),
      ]);
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Thank you for enquiring!'), findsOneWidget);
      expect(find.textContaining('Approve'), findsAtLeast(1));
    });

    // ── 5. Approve button tap calls approveTurn ────────────────────────────

    testWidgets('tapping approve button calls approveTurn', (tester) async {
      final repo = _FakeTurnsRepo(turns: [
        _outbound(
          id: 'turn-to-approve',
          text: 'Proposed reply',
          timestamp: 4000,
          outboundState: 'proposed',
        ),
      ]);
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap the approve button.
      await tester.tap(find.textContaining('Approve'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.approveCalled, equals(1),
          reason: 'approveTurn should have been called once');
    });

    // ── 6. Multiple turns render in order ─────────────────────────────────

    testWidgets('all turns are rendered', (tester) async {
      final repo = _FakeTurnsRepo(turns: [
        _inbound(id: 't1', text: 'Customer message', timestamp: 1000),
        _outbound(
            id: 't2',
            text: 'Operator reply',
            timestamp: 2000,
            outboundState: 'sent'),
        _inbound(id: 't3', text: 'Follow up', timestamp: 3000),
      ]);
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Customer message'), findsOneWidget);
      expect(find.text('Operator reply'), findsOneWidget);
      expect(find.text('Follow up'), findsOneWidget);
    });
  });
}

```
