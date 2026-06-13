---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/gradient/intent_trace_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.874859+00:00
---

# archive/apps-semantos-monolith/lib/src/gradient/intent_trace_service.dart

```dart
// Wave 9 PWA surface — in-app trace recorder for `PipelineStageEvent`s.
//
// The Dart pipeline already emits one StageEvent per stage (sir_built,
// sir_lowered, ir_emitted, script_executed, cell_written,
// intent_completed, intent_rejected). Until now those events only
// flowed into `debugPrint` for log-grep. This service captures them
// into a per-correlationId ring buffer the UI subscribes to, so the
// user can SEE the cascade for their last action without leaving the
// PWA — round-trip inspectability as the DX-priorities memory rule
// asks for.
//
// Wire from `buildProductionPipelineDeps`:
//
//   final trace = IntentTraceService();
//   buildProductionPipelineDeps(
//     ...
//     audit: (msg) => debugPrint(msg),    // existing log sink
//   ).copyWithEmit(trace.recordEvent);    // add the UI sink alongside
//
// Then mount `IntentTraceService.of(context)` somewhere a debug-mode
// inspector button can reach (home_screen.dart's AppBar actions).
//
// No LLM in this layer — same stance as the substrate: the trace is
// the artifact, not an inferred summary of it.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'dart_pipeline.dart';

/// One correlation group — the cascade for a single turn/action.
class TraceGroup {
  TraceGroup({required this.correlationId, required this.firstSeenAt})
      : lastEventAt = firstSeenAt;

  final String correlationId;
  final DateTime firstSeenAt;
  final List<PipelineStageEvent> events = [];

  /// Wall-clock at which the most recent event was appended. The
  /// inspector reads this on the *tail* event of an in-flight group
  /// (e.g. `sir_extracting` while we're still waiting for the
  /// extractor) and renders LIVE elapsed time — so the user sees
  /// `extracting · 12300ms` ticking up instead of a frozen `0ms`.
  DateTime lastEventAt;

  /// Sum of `durationMs` across every event in the group. Mirrors the
  /// tree-header `Nms total` field in the TS cascade renderer.
  double get totalDurationMs =>
      events.fold(0.0, (acc, e) => acc + e.durationMs);

  /// `true` if the group contains an `intent_rejected` event.
  bool get isRejected => events.any((e) => e.stage == 'intent_rejected');

  /// `true` once an `intent_completed` event has landed (success path).
  bool get isCompleted => events.any((e) => e.stage == 'intent_completed');

  /// Convenience — the cellId from the `cell_written` event, when present.
  String? get cellId {
    for (final e in events) {
      if (e.stage == 'cell_written') {
        final id = e.data['cellId'];
        if (id is String) return id;
      }
    }
    return null;
  }
}

/// Service-of-record for the PWA's intent trace. Holds the last
/// [maxGroups] correlation groups in insertion order (newest first).
///
/// `ChangeNotifier` so widgets can `AnimatedBuilder` / `ListenableBuilder`
/// without pulling in a state-management package. Also exposes a
/// broadcast `Stream<PipelineStageEvent>` for callers that want per-event
/// granularity (e.g. a live "tail" view).
class IntentTraceService extends ChangeNotifier {
  IntentTraceService({this.maxGroups = 32});

  /// Bound on the number of correlation groups retained — protects RAM
  /// on long sessions. 32 turns ≈ a half-day of normal use.
  final int maxGroups;

  /// Newest first.
  final List<TraceGroup> _groups = [];
  final _eventCtl = StreamController<PipelineStageEvent>.broadcast();

  /// Index for O(1) lookup; kept in sync with [_groups].
  final Map<String, TraceGroup> _byCorrelation = HashMap();

  /// Newest-first view of the captured groups.
  UnmodifiableListView<TraceGroup> get groups => UnmodifiableListView(_groups);

  /// Most-recent group, or `null` when the buffer is empty.
  TraceGroup? get latest => _groups.isEmpty ? null : _groups.first;

  /// Live stream of every event the service records. Replays nothing —
  /// late subscribers see only future events. Use [groups] / [latest]
  /// for snapshot access.
  Stream<PipelineStageEvent> get events => _eventCtl.stream;

  /// Record one event. Idempotent on `(correlationId, stage)` — the
  /// pipeline shouldn't emit the same stage twice for one turn, but
  /// the recorder doesn't enforce it; duplicates accumulate so the UI
  /// can spot misbehaving callers.
  void recordEvent(PipelineStageEvent event) {
    var group = _byCorrelation[event.correlationId];
    if (group == null) {
      group = TraceGroup(
        correlationId: event.correlationId,
        firstSeenAt: DateTime.now(),
      );
      _byCorrelation[event.correlationId] = group;
      _groups.insert(0, group);
      // Cap retention.
      while (_groups.length > maxGroups) {
        final evicted = _groups.removeLast();
        _byCorrelation.remove(evicted.correlationId);
      }
    }
    group.events.add(event);
    group.lastEventAt = DateTime.now();
    _eventCtl.add(event);
    notifyListeners();
  }

  /// Convenience — drop every captured group. Used by the inspector's
  /// "clear" button so the operator can re-baseline mid-session.
  void clear() {
    _groups.clear();
    _byCorrelation.clear();
    notifyListeners();
  }

  /// Look up a group by correlationId. Returns `null` when the group
  /// has been evicted (older than [maxGroups]) or never existed.
  TraceGroup? groupFor(String correlationId) =>
      _byCorrelation[correlationId];

  @override
  void dispose() {
    _eventCtl.close();
    super.dispose();
  }
}

```
