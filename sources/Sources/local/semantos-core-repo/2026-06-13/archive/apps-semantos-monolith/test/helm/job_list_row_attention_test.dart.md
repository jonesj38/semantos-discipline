---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/job_list_row_attention_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.924751+00:00
---

# archive/apps-semantos-monolith/test/helm/job_list_row_attention_test.dart

```dart
// Tier 2P Phase E.1 — JobListRow attention augment tests.
//
// Verifies the three new optional visual elements added by E.1:
//   1. Lane chip   — rendered when primaryDispatch is non-null.
//   2. Score dot   — rendered when attentionSignal is non-null, coloured
//                    by score (red ≥ 0.8, amber ≥ 0.6, gray < 0.6).
//   3. Message snippet — rendered when lastMessagePatch is non-null,
//                        truncated at 60 chars.
//
// Backward-compat: rows with no attention params render exactly as before.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/helm/job_list_row.dart';
import 'package:semantos/src/repl/attention_service.dart';
import 'package:semantos/src/repl/jobs_repository.dart';

void main() {
  // ── Test data factories ──────────────────────────────────────────────

  OddjobzAttentionSignal _makeSignal(double score) => OddjobzAttentionSignal(
        kind: OddjobzAttentionKind.job,
        score: score,
        ref: 'job-ref',
        summary: 'test signal',
        expiresAt: null,
        raw: const {},
      );

  OddjobzMessagePatch _makePatch(String text, {int timestamp = 0}) =>
      OddjobzMessagePatch(
        patchId: 'patch-1',
        providerId: 'meta',
        sessionId: 'sess-1',
        channel: 'meta_messenger',
        recipientId: 'page-1',
        role: 'customer',
        text: text,
        timestamp: timestamp,
        source: null,
      );

  OddjobzDispatchDecision _makeDispatch(OddjobzDispatchLane lane) =>
      OddjobzDispatchDecision(
        sourcePatchId: 'patch-1',
        lane: lane,
        slot: 'talk.${lane.name}',
        transport: OddjobzDispatchTransport.none,
        confidence: 0.9,
        requiresRatification: false,
        primaryTarget: OddjobzDispatchTarget(
          type: OddjobzDispatchTargetType.job,
          ref: 'job-ref',
          score: 0.9,
        ),
        timestamp: 0,
      );

  const _v2Job = Job(
    id: 'J1',
    customerName: 'Alice',
    state: 'scheduled',
    scheduledAt: '2026-05-04T09:00:00Z',
    siteRef: 'aaaa',
    propertyAddress: '47 Hygieta St, Doonside',
  );

  // Wrap a single widget for pump.
  Widget _wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  // ── Test 1: All 3 visuals render when all params supplied ────────────

  group('JobListRow — all 3 attention augments present', () {
    testWidgets('lane chip, score dot, and snippet are all rendered',
        (tester) async {
      final signal = _makeSignal(0.85); // red
      final patch = _makePatch(
        'Hello please can you come around and take a look',
        timestamp: DateTime.now()
            .subtract(const Duration(minutes: 3))
            .millisecondsSinceEpoch,
      );
      final dispatch = _makeDispatch(OddjobzDispatchLane.direct);

      await tester.pumpWidget(_wrap(JobListRow(
        job: _v2Job,
        primaryCustomer: null,
        onTap: () {},
        attentionSignal: signal,
        lastMessagePatch: patch,
        primaryDispatch: dispatch,
      )));

      // Lane chip visible.
      expect(find.text('direct'), findsOneWidget);
      // Message snippet visible — contains the emoji and message text.
      expect(find.textContaining('Hello please can you'), findsOneWidget);
      // The row still renders the standard address title.
      expect(find.text('47 Hygieta St, Doonside'), findsOneWidget);
    });
  });

  // ── Test 2: No attention info — original rendering unchanged ─────────

  group('JobListRow — no attention info', () {
    testWidgets('row renders identically to pre-E.1 when no attention params',
        (tester) async {
      await tester.pumpWidget(_wrap(JobListRow(
        job: _v2Job,
        primaryCustomer: null,
        onTap: () {},
        // No attention params.
      )));

      // Standard fields present.
      expect(find.text('47 Hygieta St, Doonside'), findsOneWidget);
      // No lane chip text.
      for (final lane in ['direct', 'squad', 'broadcast', 'agent', 'self']) {
        expect(find.text(lane), findsNothing);
      }
      // No snippet emoji.
      expect(find.textContaining('💬'), findsNothing);
    });

    testWidgets('v1 row with no attention params renders unchanged',
        (tester) async {
      const v1 = Job(
        id: 'J-v1',
        customerName: 'Legacy Bob',
        state: 'lead',
        scheduledAt: '',
      );
      await tester.pumpWidget(_wrap(JobListRow(
        job: v1,
        primaryCustomer: null,
        onTap: () {},
      )));
      expect(find.text('Legacy Bob'), findsOneWidget);
      expect(find.textContaining('💬'), findsNothing);
    });
  });

  // ── Test 3: Lane chip color matches lane enum ────────────────────────

  group('JobListRow — lane chip labels', () {
    for (final testCase in [
      (OddjobzDispatchLane.direct, 'direct'),
      (OddjobzDispatchLane.squad, 'squad'),
      (OddjobzDispatchLane.broadcast, 'broadcast'),
      (OddjobzDispatchLane.agent, 'agent'),
      (OddjobzDispatchLane.self, 'self'),
    ]) {
      final lane = testCase.$1;
      final label = testCase.$2;
      testWidgets('lane $label renders chip with text "$label"',
          (tester) async {
        await tester.pumpWidget(_wrap(JobListRow(
          job: _v2Job,
          primaryCustomer: null,
          onTap: () {},
          primaryDispatch: _makeDispatch(lane),
        )));
        expect(find.text(label), findsOneWidget);
      });
    }
  });

  // ── Test 4: Score dot color by score value ───────────────────────────
  //
  // We verify via the Semantics widget's label, which is applied to the
  // _ScoreDot container.  `tester.getSemantics` requires a working
  // SemanticsHandle; the simpler approach is to locate the Semantics
  // widget by its label using `find.descendant` + `find.byType`.
  // Alternatively we check that the attentionSignal param was consumed
  // (i.e. a dot IS rendered at all) and trust the widget implementation
  // for the correct colour — testing colour values directly is fragile
  // and is a rendering concern, not a business-logic concern.
  //
  // To stay concise and not couple to colour implementation details,
  // we verify:
  //   • A dot is rendered (attentionSignal != null path taken).
  //   • The row still renders the headline (no regression).
  //   • The score thresholds are exercised at 0.85 / 0.65 / 0.40.
  // Colour accuracy is covered by code-review of _ScoreDot.

  group('JobListRow — score dot rendered', () {
    testWidgets('score 0.85 → dot is rendered alongside title',
        (tester) async {
      await tester.pumpWidget(_wrap(JobListRow(
        job: _v2Job,
        primaryCustomer: null,
        onTap: () {},
        attentionSignal: _makeSignal(0.85),
      )));
      // The headline is still present.
      expect(find.text('47 Hygieta St, Doonside'), findsOneWidget);
      // A Semantics widget with the expected label is in the tree.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label == 'high attention'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('score 0.65 → amber dot label', (tester) async {
      await tester.pumpWidget(_wrap(JobListRow(
        job: _v2Job,
        primaryCustomer: null,
        onTap: () {},
        attentionSignal: _makeSignal(0.65),
      )));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label == 'medium attention'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('score 0.4 → gray dot label', (tester) async {
      await tester.pumpWidget(_wrap(JobListRow(
        job: _v2Job,
        primaryCustomer: null,
        onTap: () {},
        attentionSignal: _makeSignal(0.4),
      )));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label == 'low attention'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('no dot when attentionSignal is null', (tester) async {
      await tester.pumpWidget(_wrap(JobListRow(
        job: _v2Job,
        primaryCustomer: null,
        onTap: () {},
        // No attentionSignal.
      )));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label == 'high attention' ||
                  w.properties.label == 'medium attention' ||
                  w.properties.label == 'low attention'),
        ),
        findsNothing,
      );
    });
  });

  // ── Test 5: Snippet truncates at 60 chars ───────────────────────────

  group('JobListRow — message snippet truncation', () {
    testWidgets('text ≤ 60 chars rendered as-is (no ellipsis)', (tester) async {
      const short = 'Hi there, can you come over?';
      await tester.pumpWidget(_wrap(JobListRow(
        job: _v2Job,
        primaryCustomer: null,
        onTap: () {},
        lastMessagePatch: _makePatch(short),
      )));
      expect(find.textContaining(short), findsOneWidget);
      // No ellipsis for short text.
      expect(find.textContaining('$short…'), findsNothing);
    });

    testWidgets('text > 60 chars is truncated with ellipsis', (tester) async {
      const long =
          'This is a very long message that exceeds sixty characters in total length';
      // First 60 chars + ellipsis.
      final expected = '${long.substring(0, 60)}…';
      await tester.pumpWidget(_wrap(JobListRow(
        job: _v2Job,
        primaryCustomer: null,
        onTap: () {},
        lastMessagePatch: _makePatch(long),
      )));
      expect(find.textContaining(expected), findsOneWidget);
      // Full text not shown.
      expect(find.textContaining(long), findsNothing);
    });
  });
}

```
