---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/ratification/ratification_card_controller.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.873918+00:00
---

# archive/apps-semantos-monolith/lib/src/ratification/ratification_card_controller.dart

```dart
// D-O5m.followup-7 Phase B — pure-Dart state machine for the
// ratification card screen.
//
// Factored out of `helm/ratification_card_screen.dart` so the unit
// tests import the controller without dragging in flutter/material —
// the same posture other controllers in this app use (e.g.
// PushNotificationRouter post-#328).
//
// The screen widget owns the visual rendering; this controller owns:
//   - the lifecycle phase (loading → ready → submitting → succeeded /
//     actionError; plus loadError + noLeadId)
//   - the lead being acted on
//   - the typed [RatificationCardOutcome] surfaced via [onCompleted]
//
// Listeners get notified on every phase change so the screen can call
// setState.

import 'ratification_queue_client.dart';

/// Operator-driven outcome of a ratification card session.  Surfaced
/// to the route caller via Navigator.pop so the leads list can
/// invalidate its row + the helm input bar can render a confirmation
/// banner.
sealed class RatificationCardOutcome {
  const RatificationCardOutcome();
}

class RatificationCardRatified extends RatificationCardOutcome {
  final PendingLead lead;
  const RatificationCardRatified(this.lead);
}

class RatificationCardRejected extends RatificationCardOutcome {
  final PendingLead lead;
  final RejectionReason reason;
  const RatificationCardRejected(this.lead, this.reason);
}

class RatificationCardDeferred extends RatificationCardOutcome {
  final PendingLead lead;
  const RatificationCardDeferred(this.lead);
}

class RatificationCardDismissed extends RatificationCardOutcome {
  const RatificationCardDismissed();
}

/// Lifecycle phase of the controller.
enum RatificationCardPhase {
  /// Initial fetch in flight.
  loading,

  /// Fetch failed — render an error with retry.
  loadError,

  /// Lead loaded; awaiting operator action.
  ready,

  /// Action submitted; awaiting brain response.
  submitting,

  /// Action succeeded; the screen will pop next frame.
  succeeded,

  /// Action failed with a typed transition error.
  actionError,

  /// `lead_id` route argument was missing or empty.
  noLeadId,
}

/// State machine for the ratification card.  Holds the
/// [RatificationQueueClient], the lead being acted on, and the
/// transient submission state.
class RatificationCardController {
  final RatificationQueueClient client;

  /// The lead id from the route arguments.  Empty/null → noLeadId.
  final String? leadId;

  /// Called when the operator's action succeeds.
  final void Function(RatificationCardOutcome outcome)? onCompleted;

  PendingLead? _lead;
  RatificationCardPhase _phase = RatificationCardPhase.loading;
  String? _errorMessage;

  RatificationCardController({
    required this.client,
    required this.leadId,
    this.onCompleted,
  }) {
    if (leadId == null || leadId!.isEmpty) {
      _phase = RatificationCardPhase.noLeadId;
    }
  }

  RatificationCardPhase get phase => _phase;
  PendingLead? get lead => _lead;
  String? get errorMessage => _errorMessage;

  final List<void Function()> _listeners = [];
  void addListener(void Function() cb) => _listeners.add(cb);
  void removeListener(void Function() cb) => _listeners.remove(cb);
  void _notify() {
    for (final l in List<void Function()>.from(_listeners)) {
      l();
    }
  }

  /// Initial fetch.  Called from the widget's initState.  No-op when
  /// the route arguments were missing.
  Future<void> load() async {
    if (_phase == RatificationCardPhase.noLeadId) return;
    _phase = RatificationCardPhase.loading;
    _errorMessage = null;
    _notify();
    try {
      final fetched = await client.findById(leadId!);
      if (fetched == null) {
        _errorMessage = 'Lead $leadId no longer exists';
        _phase = RatificationCardPhase.loadError;
      } else {
        _lead = fetched;
        _phase = RatificationCardPhase.ready;
      }
    } catch (e) {
      _errorMessage = e.toString();
      _phase = RatificationCardPhase.loadError;
    }
    _notify();
  }

  Future<void> ratify() async {
    if (_lead == null) return;
    _phase = RatificationCardPhase.submitting;
    _errorMessage = null;
    _notify();
    try {
      final r = await client.ratify(_lead!.id);
      switch (r) {
        case RatifySuccess(:final lead):
        case RatifyAlreadyInState(:final lead):
          _lead = lead;
          _phase = RatificationCardPhase.succeeded;
          _notify();
          onCompleted?.call(RatificationCardRatified(lead));
        case RatifyError():
          _errorMessage = r.message;
          _phase = RatificationCardPhase.actionError;
          _notify();
      }
    } catch (e) {
      _errorMessage = e.toString();
      _phase = RatificationCardPhase.actionError;
      _notify();
    }
  }

  Future<void> reject(RejectionReason reason) async {
    if (_lead == null) return;
    _phase = RatificationCardPhase.submitting;
    _errorMessage = null;
    _notify();
    try {
      final r = await client.reject(_lead!.id, reason);
      switch (r) {
        case RejectSuccess(:final lead):
        case RejectAlreadyInState(:final lead):
          _lead = lead;
          _phase = RatificationCardPhase.succeeded;
          _notify();
          onCompleted?.call(RatificationCardRejected(lead, reason));
        case RejectError():
          _errorMessage = r.message;
          _phase = RatificationCardPhase.actionError;
          _notify();
      }
    } catch (e) {
      _errorMessage = e.toString();
      _phase = RatificationCardPhase.actionError;
      _notify();
    }
  }

  Future<void> defer() async {
    if (_lead == null) return;
    _phase = RatificationCardPhase.submitting;
    _errorMessage = null;
    _notify();
    try {
      final r = await client.defer(_lead!.id);
      switch (r) {
        case DeferSuccess(:final lead):
        case DeferAlreadyInState(:final lead):
          _lead = lead;
          _phase = RatificationCardPhase.succeeded;
          _notify();
          onCompleted?.call(RatificationCardDeferred(lead));
        case DeferError():
          _errorMessage = r.message;
          _phase = RatificationCardPhase.actionError;
          _notify();
      }
    } catch (e) {
      _errorMessage = e.toString();
      _phase = RatificationCardPhase.actionError;
      _notify();
    }
  }
}

```
