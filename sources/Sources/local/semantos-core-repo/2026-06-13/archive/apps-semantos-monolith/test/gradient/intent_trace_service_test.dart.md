---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/gradient/intent_trace_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.918928+00:00
---

# archive/apps-semantos-monolith/test/gradient/intent_trace_service_test.dart

```dart
// Wave 9 PWA surface — IntentTraceService unit tests.
//
// Covers:
//   T1  events are bucketed by correlationId.
//   T2  buffer evicts oldest correlation group past maxGroups.
//   T3  latest returns the most recently-touched group.
//   T4  isCompleted / isRejected reflect the cascade's terminal event.
//   T5  cellId surfaces from the cell_written event when present.
//   T6  notifyListeners fires on every recordEvent.
//   T7  clear() empties the buffer + notifies.
//   T8  events stream forwards every event in arrival order.

import 'package:test/test.dart';

import 'package:semantos/src/gradient/dart_pipeline.dart'
    show PipelineStageEvent;
import 'package:semantos/src/gradient/intent_trace_service.dart';

PipelineStageEvent _ev({
  required String cid,
  required String stage,
  double durationMs = 1.0,
  Map<String, dynamic>? data,
}) =>
    PipelineStageEvent(
      correlationId: cid,
      stage: stage,
      durationMs: durationMs,
      data: data ?? <String, dynamic>{},
    );

void main() {
  group('IntentTraceService', () {
    test('T1 buckets events by correlationId', () {
      final svc = IntentTraceService();
      svc.recordEvent(_ev(cid: 'a', stage: 'sir_built'));
      svc.recordEvent(_ev(cid: 'a', stage: 'sir_lowered'));
      svc.recordEvent(_ev(cid: 'b', stage: 'sir_built'));

      expect(svc.groups, hasLength(2));
      expect(svc.groupFor('a')!.events, hasLength(2));
      expect(svc.groupFor('b')!.events, hasLength(1));
    });

    test('T2 evicts oldest correlation group past maxGroups', () {
      final svc = IntentTraceService(maxGroups: 2);
      svc.recordEvent(_ev(cid: 'a', stage: 'sir_built'));
      svc.recordEvent(_ev(cid: 'b', stage: 'sir_built'));
      svc.recordEvent(_ev(cid: 'c', stage: 'sir_built'));

      expect(svc.groups, hasLength(2));
      expect(svc.groupFor('a'), isNull);
      expect(svc.groupFor('b'), isNotNull);
      expect(svc.groupFor('c'), isNotNull);
    });

    test('T3 latest returns the most recently-touched group', () {
      final svc = IntentTraceService();
      svc.recordEvent(_ev(cid: 'a', stage: 'sir_built'));
      svc.recordEvent(_ev(cid: 'b', stage: 'sir_built'));
      expect(svc.latest!.correlationId, 'b');
    });

    test('T4 isCompleted / isRejected reflect terminal events', () {
      final svc = IntentTraceService();
      svc.recordEvent(_ev(cid: 'ok', stage: 'sir_built'));
      svc.recordEvent(_ev(cid: 'ok', stage: 'intent_completed'));
      svc.recordEvent(_ev(cid: 'no', stage: 'sir_built'));
      svc.recordEvent(_ev(cid: 'no', stage: 'intent_rejected', data: {
        'stage': 'kernel',
        'code': 'k4',
        'message': 'linearity violation',
      }));

      expect(svc.groupFor('ok')!.isCompleted, isTrue);
      expect(svc.groupFor('ok')!.isRejected, isFalse);
      expect(svc.groupFor('no')!.isRejected, isTrue);
      expect(svc.groupFor('no')!.isCompleted, isFalse);
    });

    test('T5 cellId surfaces from the cell_written event when present', () {
      final svc = IntentTraceService();
      svc.recordEvent(_ev(
        cid: 'c1',
        stage: 'cell_written',
        data: {'cellId': 'cell-abc', 'bytes': 42},
      ));
      expect(svc.groupFor('c1')!.cellId, 'cell-abc');
    });

    test('T6 notifyListeners fires on every recordEvent', () {
      final svc = IntentTraceService();
      int notifications = 0;
      svc.addListener(() => notifications++);

      svc.recordEvent(_ev(cid: 'a', stage: 'sir_built'));
      svc.recordEvent(_ev(cid: 'a', stage: 'sir_lowered'));
      svc.recordEvent(_ev(cid: 'b', stage: 'sir_built'));

      expect(notifications, 3);
    });

    test('T7 clear() empties the buffer + notifies', () {
      final svc = IntentTraceService();
      svc.recordEvent(_ev(cid: 'a', stage: 'sir_built'));
      int notifications = 0;
      svc.addListener(() => notifications++);
      svc.clear();
      expect(svc.groups, isEmpty);
      expect(svc.latest, isNull);
      expect(notifications, 1);
    });

    test('T8 events stream forwards every event in arrival order', () async {
      final svc = IntentTraceService();
      final received = <String>[];
      final sub = svc.events.listen((e) {
        received.add('${e.correlationId}:${e.stage}');
      });

      svc.recordEvent(_ev(cid: 'a', stage: 'sir_built'));
      svc.recordEvent(_ev(cid: 'a', stage: 'sir_lowered'));
      svc.recordEvent(_ev(cid: 'b', stage: 'sir_built'));

      // Flush microtasks so the broadcast stream delivers.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(received, [
        'a:sir_built',
        'a:sir_lowered',
        'b:sir_built',
      ]);
    });

    test('T9 totalDurationMs sums every event in the group', () {
      final svc = IntentTraceService();
      svc.recordEvent(_ev(cid: 'a', stage: 'sir_built', durationMs: 1.5));
      svc.recordEvent(_ev(cid: 'a', stage: 'sir_lowered', durationMs: 2.5));
      svc.recordEvent(_ev(cid: 'a', stage: 'cell_written', durationMs: 0.1));
      expect(svc.groupFor('a')!.totalDurationMs, closeTo(4.1, 1e-6));
    });
  });
}

```
