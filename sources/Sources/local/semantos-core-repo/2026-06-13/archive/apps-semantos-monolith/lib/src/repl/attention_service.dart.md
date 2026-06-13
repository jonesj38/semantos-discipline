---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/attention_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.883609+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/attention_service.dart

```dart
// Tier 2P Phase D.2 — mobile AttentionService.
//
// Reference: docs/prd/TIER-2P-PHASE-D2-BRIEF.md;
//            lib/src/repl/oddjobz_attention_client.dart (D.1 typed client).
//
// Single instance per paired session; owned by AuthRouter alongside
// OutboxService.  Wraps the three Phase B attention verbs via
// OddjobzAttentionClient, maintains in-memory cached state, and exposes
// three broadcast streams for UI consumers.
//
// Lifecycle:
//   • Created by _AuthRouterState._ensureAttention() once per AuthAuthenticated
//     session (mirroring _ensureOutbox() from Phase A).
//   • Disposed by _AuthRouterState._tearDownAttention() on logout/unpair.
//   • Periodic poll every 30 s while the app is foregrounded; paused in
//     background / resumed on foreground via WidgetsBindingObserver in
//     HomeScreen (see home_screen.dart).
//
// Topic-driven invalidation (existing brain topics):
//   • `job.transitioned` — a job FSM change often means attention changed;
//     triggers a fresh pollAttentionSignals().
//   • `lead.created` / `lead.transitioned` — a new or transitioned lead
//     (ratification queue) implies fresh dispatch decisions; triggers refresh.
//
// Topic emission note:
//   New topics `oddjobz.message.appended` and `oddjobz.dispatch.appended`
//   would provide finer-grained invalidation for messages and dispatch
//   buffers respectively, but these topics are NOT yet emitted by the Semantos Brain
//   side (Phase B only adds the query verbs; the emit-on-write seam is a
//   follow-up).  This service subscribes to the already-existing
//   `job.transitioned` and `lead.created`/`lead.transitioned` topics for
//   partial real-time freshness; the 30 s poll is the safety net for the
//   rest.  See D.3 or a dedicated follow-up phase for the new topic wires.
//
// Cached state:
//   _signals    — latest pollAttentionSignals() result.
//   _messages   — latest listMessages() result, newest first.
//   _dispatches — latest listDispatchDecisions() result.
//   _jobToPatches — map from job-cellId → list of patchIds whose
//                   primaryTarget.ref equals that job.  Rebuilt on every
//                   dispatch refresh so messagesForJob() can answer without
//                   a network round-trip.
//
// Public streams:
//   signals            — Stream<List<OddjobzAttentionSignal>>  (all signals)
//   messagesForJob(id) — Stream<List<OddjobzMessagePatch>>     (filtered)
//   pendingRatifications — Stream<List<OddjobzDispatchDecision>> (requiresRatification==true)

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'helm_event_stream.dart';
import 'oddjobz_attention_client.dart';

// Re-export the client types so screens can import just this file.
export 'oddjobz_attention_client.dart'
    show
        OddjobzAttentionSignal,
        OddjobzAttentionKind,
        OddjobzMessagePatch,
        OddjobzMessageSource,
        OddjobzDispatchDecision,
        OddjobzDispatchLane,
        OddjobzDispatchTransport,
        OddjobzDispatchTarget,
        OddjobzDispatchTargetType;

/// How many signals to request per poll.
const int _kSignalLimit = 50;

/// How many messages to request per refresh.
const int _kMessageLimit = 200;

/// How many dispatch decisions to request per refresh.
const int _kDispatchLimit = 200;

/// Periodic poll interval while foregrounded.
const Duration _kPollInterval = Duration(seconds: 30);

/// Single-instance attention service owned by AuthRouter.  Exposes three
/// broadcast streams for UI consumers; performs a periodic 30 s poll and
/// reacts to existing brain topics for partial real-time invalidation.
class AttentionService {
  final OddjobzAttentionClient _client;

  // ── Cached state ──────────────────────────────────────────────────────

  List<OddjobzAttentionSignal> _signals = const [];
  List<OddjobzMessagePatch> _messages = const [];
  List<OddjobzDispatchDecision> _dispatches = const [];

  /// job-cellId → patchIds whose dispatch primaryTarget.ref matches.
  /// Rebuilt on every _refreshDispatches call.
  final Map<String, List<String>> _jobToPatches = {};

  // ── Broadcast stream controllers ──────────────────────────────────────

  final StreamController<List<OddjobzAttentionSignal>> _signalsCtl =
      StreamController<List<OddjobzAttentionSignal>>.broadcast();

  final StreamController<List<OddjobzDispatchDecision>> _pendingRatCtl =
      StreamController<List<OddjobzDispatchDecision>>.broadcast();

  // Per-job message stream controllers — lazily created, removed on dispose.
  final Map<String, StreamController<List<OddjobzMessagePatch>>>
      _perJobCtls = {};

  // ── Topic subscription + polling ──────────────────────────────────────

  StreamSubscription<HelmEvent>? _eventSub;
  Timer? _pollTimer;
  bool _disposed = false;

  AttentionService({
    required OddjobzAttentionClient client,
    HelmEventStream? eventStream,
  }) : _client = client {
    if (eventStream != null) {
      _eventSub = eventStream.events.listen(_onHelmEvent);
    }
  }

  // ── Public client access ──────────────────────────────────────────────

  /// Exposes the underlying [OddjobzAttentionClient] for one-shot queries
  /// that need to pass filter parameters not surfaced by the cached streams.
  /// Used by JobThreadScreen (Phase E.2) for per-job dispatch filtering.
  OddjobzAttentionClient get client => _client;

  // ── Public streams ────────────────────────────────────────────────────

  /// Latest ranked attention signals from pollAttentionSignals().  Emits
  /// immediately on subscribe if data has already been fetched.
  Stream<List<OddjobzAttentionSignal>> get signals => _signalsCtl.stream;

  /// Dispatch decisions that require operator ratification.  Filtered
  /// from the latest dispatch refresh.  Emits on every dispatch refresh.
  Stream<List<OddjobzDispatchDecision>> get pendingRatifications =>
      _pendingRatCtl.stream;

  /// Message patches whose most-recent dispatch decision targeted [jobId].
  /// Backed by a per-job broadcast stream; lazily created on first call.
  /// Returns an empty list immediately after subscribe if the job has no
  /// messages yet.
  Stream<List<OddjobzMessagePatch>> messagesForJob(String jobId) {
    final ctl = _perJobCtls.putIfAbsent(
      jobId,
      () => StreamController<List<OddjobzMessagePatch>>.broadcast(),
    );
    return ctl.stream;
  }

  // ── Polling lifecycle ─────────────────────────────────────────────────

  /// Start the 30 s periodic poll.  Idempotent — calling while already
  /// running just resets the timer interval.  Called by HomeScreen on
  /// foreground resume.
  void startPolling() {
    if (_disposed) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_kPollInterval, (_) => _poll());
    // Kick an immediate poll so the UI has data on first foreground.
    _poll();
  }

  /// Pause the periodic poll (battery/network conservation).  Called by
  /// HomeScreen when the app goes to background.
  void pausePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Trigger a single immediate refresh of all three buffers.  Used by
  /// tests and by the WSS-reconnect seam (see HomeScreen._streamStateSub).
  Future<void> refresh() => _poll();

  // ── Dispose ───────────────────────────────────────────────────────────

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _eventSub?.cancel();
    _eventSub = null;
    if (!_signalsCtl.isClosed) await _signalsCtl.close();
    if (!_pendingRatCtl.isClosed) await _pendingRatCtl.close();
    for (final ctl in _perJobCtls.values) {
      if (!ctl.isClosed) await ctl.close();
    }
    _perJobCtls.clear();
  }

  // ── Internal ──────────────────────────────────────────────────────────

  void _onHelmEvent(HelmEvent event) {
    // job.transitioned → signals + dispatches might have changed.
    // lead.created / lead.transitioned → ratification queue may have changed.
    switch (event.type) {
      case 'job.transitioned':
      case 'lead.created':
      case 'lead.transitioned':
        _poll();
        break;
      default:
        break;
    }
  }

  Future<void> _poll() async {
    if (_disposed) return;
    // Run all three refreshes in parallel; individual errors are swallowed
    // so one failing verb doesn't block the other two.
    await Future.wait([
      _refreshSignals(),
      _refreshMessages(),
      _refreshDispatches(),
    ]);
  }

  Future<void> _refreshSignals() async {
    try {
      final result =
          await _client.pollAttentionSignals(limit: _kSignalLimit);
      if (_disposed) return;
      _signals = result;
      if (!_signalsCtl.isClosed) _signalsCtl.add(_signals);
    } catch (e) {
      debugPrint('[AttentionService] pollAttentionSignals error: $e');
    }
  }

  Future<void> _refreshMessages() async {
    try {
      final result = await _client.listMessages(limit: _kMessageLimit);
      if (_disposed) return;
      _messages = result;
      // Update per-job streams with current data.
      _emitPerJobMessages();
    } catch (e) {
      debugPrint('[AttentionService] listMessages error: $e');
    }
  }

  Future<void> _refreshDispatches() async {
    try {
      final result =
          await _client.listDispatchDecisions(limit: _kDispatchLimit);
      if (_disposed) return;
      _dispatches = result;
      _rebuildJobToPatchMap();
      // Emit pending-ratification subset.
      final pending =
          _dispatches.where((d) => d.requiresRatification).toList();
      if (!_pendingRatCtl.isClosed) _pendingRatCtl.add(pending);
      // Refresh per-job message streams because the map changed.
      _emitPerJobMessages();
    } catch (e) {
      debugPrint('[AttentionService] listDispatchDecisions error: $e');
    }
  }

  /// Rebuild _jobToPatches from current _dispatches state.
  void _rebuildJobToPatchMap() {
    _jobToPatches.clear();
    for (final d in _dispatches) {
      if (d.primaryTarget.type == OddjobzDispatchTargetType.job &&
          d.primaryTarget.ref.isNotEmpty) {
        _jobToPatches
            .putIfAbsent(d.primaryTarget.ref, () => [])
            .add(d.sourcePatchId);
      }
    }
  }

  /// For every active per-job stream controller, emit the current
  /// filtered message list.
  void _emitPerJobMessages() {
    for (final entry in _perJobCtls.entries) {
      final ctl = entry.value;
      if (ctl.isClosed) continue;
      final jobId = entry.key;
      final patchIds = _jobToPatches[jobId] ?? const [];
      final filtered = _messages
          .where((m) => patchIds.contains(m.patchId))
          .toList();
      ctl.add(filtered);
    }
  }
}

```
