---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/ratification/ratification_queue_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.874509+00:00
---

# archive/apps-semantos-monolith/lib/src/ratification/ratification_queue_client.dart

```dart
// D-O5m.followup-7 Phase B — Ratification queue client (mobile-helm).
//
// Mirrors `JobsRepository` in shape (post-#311) — typed Dart client over
// the bearer-gated REPL HTTP endpoint, plus a live cache-event stream
// consumed by screens for invalidate-on-write semantics.
//
// Wire mapping — REPL verbs that the brain ships in Phase A (post-#332,
// runtime/semantos-brain/src/repl.zig):
//
//   findPending({hatId})  → `find leads --status pending [--hat <id>]`
//                            (the Semantos Brain handler emits a JSON array; one
//                            row per Lead — see leads_handler.zig
//                            ::writeLeadJson for the full field set).
//   findById(id)          → `find lead <id>`
//                            (single-object `Lead` body OR the typed
//                             `{error:"not_found",id}` envelope when
//                             the id is missing).
//   ratify(id)            → `ratify lead <id>`
//   reject(id, reason)    → `reject lead <id> --reason <wire>`
//   defer(id)             → `defer lead <id>`
//
// Each transition verb returns one of three JSON bodies (per
// leads_handler.zig::handleTransition):
//
//   • Success: the new Lead row (post-transition shape).
//   • Idempotent: `{status: "already_in_state", lead: {...}}` — the
//     lead was already at to_state.
//   • Error: `{error: <kind>, from, to, cap_required}` — surfaced as
//     RatifyError / RejectError / DeferError so the helm can render a
//     typed snackbar.
//
// Cache events — when the live-tick HelmEventStream is wired, the
// client subscribes to `lead.created` + `lead.transitioned` and
// surfaces them as [LeadCacheEvent]s on [cacheEvents].  Screens
// (LeadsListScreen, RatificationCardScreen) listen and refresh
// themselves so operator A's transition shows up on operator B's
// helm without a manual pull.

import 'dart:async';
import 'dart:convert';

import '../repl/helm_event_stream.dart';
import '../repl/repl_client.dart';

/// One row of the operator's pending-ratification queue.  Field set
/// matches `leads_handler.zig::writeLeadJson` exactly so a future
/// brain-side rename breaks loud here.
class PendingLead {
  /// Cell id (32-hex when server-stamped at create-time).
  final String id;

  /// Customer name as captured at lead-creation time.  Always non-empty
  /// (the brain rejects empty names at validation).
  final String customerName;

  /// Optional contact phone — empty when not captured.
  final String phone;

  /// Optional contact email — empty when not captured.
  final String email;

  /// Free-form summary the operator reviews before ratifying.  Empty
  /// when the lead came in via a path that didn't supply one (e.g.
  /// manual quick-add).
  final String summary;

  /// One of `chat | voice | text | manual` — the path the lead was
  /// captured through.  Operators see this as "From [chat / voice /
  /// text / manual]" attribution on the ratification card.
  final String source;

  /// Path-specific correlation id (e.g. the chat-thread id, voice
  /// session id).  Empty when not applicable.
  final String sourceCorrelationId;

  /// FSM state — for findPending() this is always `pending` but the
  /// shape is preserved in case the helm wants to display a deferred-
  /// requeue view.
  final String status;

  /// Optional rejection reason — populated when status == 'rejected'.
  final String rejectionReason;

  /// Optional hat scope — empty when the lead is unscoped.
  final String hatId;

  /// ISO-8601 created_at timestamp from the brain.
  final String createdAt;

  /// ISO-8601 updated_at timestamp from the brain.
  final String updatedAt;

  const PendingLead({
    required this.id,
    required this.customerName,
    required this.phone,
    required this.email,
    required this.summary,
    required this.source,
    required this.sourceCorrelationId,
    required this.status,
    required this.rejectionReason,
    required this.hatId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_name': customerName,
        'phone': phone,
        'email': email,
        'summary': summary,
        'source': source,
        'source_correlation_id': sourceCorrelationId,
        'status': status,
        'rejection_reason': rejectionReason,
        'hat_id': hatId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// Parse a Lead row from a JSON object — defaults all optional
  /// string fields to empty so the Dart side has no nullable fields
  /// to thread through the UI.
  factory PendingLead.fromJson(Map<String, dynamic> row) => PendingLead(
        id: (row['id'] ?? '').toString(),
        customerName: (row['customer_name'] ?? '').toString(),
        phone: (row['phone'] ?? '').toString(),
        email: (row['email'] ?? '').toString(),
        summary: (row['summary'] ?? '').toString(),
        source: (row['source'] ?? '').toString(),
        sourceCorrelationId: (row['source_correlation_id'] ?? '').toString(),
        status: (row['status'] ?? '').toString(),
        rejectionReason: (row['rejection_reason'] ?? '').toString(),
        hatId: (row['hat_id'] ?? '').toString(),
        createdAt: (row['created_at'] ?? '').toString(),
        updatedAt: (row['updated_at'] ?? '').toString(),
      );
}

/// Operator-pickable rejection reasons.  The wire form is the snake_case
/// string suffix; the brain stores it verbatim in the Lead's
/// `rejection_reason` column.  Adding a reason: append a value here +
/// surface it in the reject sheet's UI.
enum RejectionReason {
  notViable('not_viable'),
  duplicate('duplicate'),
  spam('spam'),
  outOfScope('out_of_scope'),
  other('other');

  final String wireValue;
  const RejectionReason(this.wireValue);

  /// Operator-readable label for the bottom-sheet picker.
  String get label {
    switch (this) {
      case RejectionReason.notViable:
        return 'Not viable';
      case RejectionReason.duplicate:
        return 'Duplicate';
      case RejectionReason.spam:
        return 'Spam';
      case RejectionReason.outOfScope:
        return 'Out of scope';
      case RejectionReason.other:
        return 'Other';
    }
  }
}

/// D-O5m.followup-7 Phase B — cache-invalidation event surfaced to
/// LeadsListScreen + RatificationCardScreen on `lead.created` /
/// `lead.transitioned` notifications from the live-tick stream.
class LeadCacheEvent {
  /// Stable kind token — `lead.created` or `lead.transitioned`.  Free-
  /// form so a future brain-side event type doesn't require a Dart enum
  /// bump.
  final String kind;

  /// The lead id the event refers to.  Empty when the upstream payload
  /// didn't carry one (defensive — the Semantos Brain emit always populates it).
  final String leadId;

  /// `from` state for transitioned events; empty for created events.
  final String fromState;

  /// `to` state for transitioned events; empty for created events.
  final String toState;

  const LeadCacheEvent({
    required this.kind,
    required this.leadId,
    this.fromState = '',
    this.toState = '',
  });
}

/// Result of `ratify lead <id>` — either the post-transition Lead, an
/// idempotent already-ratified short-circuit, or a typed error.
sealed class RatifyResult {
  const RatifyResult();
}

class RatifySuccess extends RatifyResult {
  final PendingLead lead;
  const RatifySuccess(this.lead);
}

class RatifyAlreadyInState extends RatifyResult {
  final PendingLead lead;
  const RatifyAlreadyInState(this.lead);
}

class RatifyError extends RatifyResult {
  /// One of: `wrong_cap | not_reachable | wrong_principal |
  /// unknown_state | not_found | parse_error`.  Free-form so a future
  /// brain-side error kind doesn't churn the Dart enum.
  final String kind;
  final String from;
  final String to;
  final String? capRequired;

  const RatifyError({
    required this.kind,
    required this.from,
    required this.to,
    this.capRequired,
  });

  String get message => _transitionErrorMessage(kind, from, to, capRequired);
}

/// Result of `reject lead <id>` — same three branches as RatifyResult.
sealed class RejectResult {
  const RejectResult();
}

class RejectSuccess extends RejectResult {
  final PendingLead lead;
  const RejectSuccess(this.lead);
}

class RejectAlreadyInState extends RejectResult {
  final PendingLead lead;
  const RejectAlreadyInState(this.lead);
}

class RejectError extends RejectResult {
  final String kind;
  final String from;
  final String to;
  final String? capRequired;

  const RejectError({
    required this.kind,
    required this.from,
    required this.to,
    this.capRequired,
  });

  String get message => _transitionErrorMessage(kind, from, to, capRequired);
}

/// Result of `defer lead <id>`.
sealed class DeferResult {
  const DeferResult();
}

class DeferSuccess extends DeferResult {
  final PendingLead lead;
  const DeferSuccess(this.lead);
}

class DeferAlreadyInState extends DeferResult {
  final PendingLead lead;
  const DeferAlreadyInState(this.lead);
}

class DeferError extends DeferResult {
  final String kind;
  final String from;
  final String to;
  final String? capRequired;

  const DeferError({
    required this.kind,
    required this.from,
    required this.to,
    this.capRequired,
  });

  String get message => _transitionErrorMessage(kind, from, to, capRequired);
}

String _transitionErrorMessage(
  String kind,
  String from,
  String to,
  String? capRequired,
) {
  switch (kind) {
    case 'wrong_cap':
      return 'This action requires capability ${capRequired ?? "(unknown)"}.';
    case 'not_reachable':
      return 'Cannot transition $from to $to (not in the FSM table).';
    case 'wrong_principal':
      return 'This transition requires a different signing principal.';
    case 'unknown_state':
      return 'Unknown target state "$to".';
    case 'not_found':
      return 'Lead no longer exists.';
    case 'parse_error':
      return 'Brain returned an unparseable response.';
    default:
      return 'Transition failed: $kind';
  }
}

/// Typed client over the REPL — LeadsListScreen and
/// RatificationCardScreen call this rather than constructing the wire
/// command + parsing the response themselves.
///
/// When a [HelmEventStream] is supplied, the client subscribes to
/// `lead.created` + `lead.transitioned` notifications and surfaces them
/// as [LeadCacheEvent]s on [cacheEvents].  When the stream is null
/// (tests, pull-only mode) cacheEvents is silent.
class RatificationQueueClient {
  final ReplClient _repl;
  final StreamController<LeadCacheEvent> _cacheCtl =
      StreamController<LeadCacheEvent>.broadcast();
  StreamSubscription<HelmEvent>? _eventSub;

  RatificationQueueClient(this._repl, {HelmEventStream? eventStream}) {
    if (eventStream != null) {
      _eventSub = eventStream.events.listen(_onHelmEvent);
    }
  }

  /// Stream of cache-invalidation events the screens listen to.
  /// Broadcast — multiple subscribers (list screen + open card) can
  /// coexist.
  Stream<LeadCacheEvent> get cacheEvents => _cacheCtl.stream;

  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    if (!_cacheCtl.isClosed) await _cacheCtl.close();
  }

  void _onHelmEvent(HelmEvent event) {
    if (event.type != 'lead.created' && event.type != 'lead.transitioned') {
      return;
    }
    // `lead.created` carries `lead_id` (the explicit operator-attention
    // field) AND `id` (canonical).  `lead.transitioned` only carries
    // `id` + `from` + `to`.  Be defensive against either shape.
    final idRaw = event.data['lead_id'] ?? event.data['id'];
    final id = idRaw is String ? idRaw : '';
    final from = event.data['from'];
    final to = event.data['to'];
    _cacheCtl.add(LeadCacheEvent(
      kind: event.type,
      leadId: id,
      fromState: from is String ? from : '',
      toState: to is String ? to : '',
    ));
  }

  /// Fetch the operator's pending-ratification queue.  When [hatId] is
  /// supplied, narrows to leads scoped under that hat (forwarded as
  /// `--hat`); otherwise returns all pending leads in the brain's
  /// store.
  Future<List<PendingLead>> findPending({String? hatId}) async {
    final cmd = StringBuffer('find leads --status pending');
    if (hatId != null && hatId.isNotEmpty) {
      cmd
        ..write(' --hat ')
        ..write(hatId);
    }
    final resp = await _repl.send(cmd.toString());
    return parsePendingLeads(resp.result);
  }

  /// Fetch a single lead by id via `find lead <id>`.  Returns null when
  /// the brain emits the typed `{error:"not_found",id}` envelope or
  /// when the response isn't parseable.
  Future<PendingLead?> findById(String leadId) async {
    final resp = await _repl.send('find lead $leadId');
    return parsePendingLeadOne(resp.result);
  }

  /// Drive a `pending → ratified` transition via `ratify lead <id>`.
  Future<RatifyResult> ratify(String leadId) async {
    final resp = await _repl.send('ratify lead $leadId');
    return _parseRatifyResult(resp.result);
  }

  /// Drive a `pending → rejected` transition with a typed reason via
  /// `reject lead <id> --reason <wire-value>`.
  Future<RejectResult> reject(String leadId, RejectionReason reason) async {
    final resp =
        await _repl.send('reject lead $leadId --reason ${reason.wireValue}');
    return _parseRejectResult(resp.result);
  }

  /// Drive a `pending → deferred` transition via `defer lead <id>`.
  Future<DeferResult> defer(String leadId) async {
    final resp = await _repl.send('defer lead $leadId');
    return _parseDeferResult(resp.result);
  }
}

// ─────────────────────────────────────────────────────────────────────
// Parsers — split out as top-level functions so the test suite can
// pin them against the verbatim brain handler bytes.
// ─────────────────────────────────────────────────────────────────────

/// Parse `leads.find` response into a list of [PendingLead].  Falls
/// back to the empty list on parse failure / non-JSON input.
List<PendingLead> parsePendingLeads(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('[')) return const [];
  try {
    final parsed = json.decode(trimmed);
    if (parsed is List) {
      return parsed
          .whereType<Map<String, dynamic>>()
          .map(PendingLead.fromJson)
          .toList();
    }
  } catch (_) {
    // Fall through to empty.
  }
  return const [];
}

/// Parse `leads.find_by_id` response into a single [PendingLead] or
/// null on the typed not_found envelope / any parse failure.
PendingLead? parsePendingLeadOne(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['error'] == 'not_found') return null;
      if (parsed['id'] == null) return null;
      return PendingLead.fromJson(parsed);
    }
  } catch (_) {
    // Fall through.
  }
  return null;
}

RatifyResult _parseRatifyResult(String text) {
  final body = _parseTransitionBody(text);
  return switch (body) {
    _TransitionSuccessBody(:final lead) => RatifySuccess(lead),
    _TransitionAlreadyInStateBody(:final lead) => RatifyAlreadyInState(lead),
    _TransitionErrorBody(:final kind, :final from, :final to, :final cap) =>
      RatifyError(kind: kind, from: from, to: to, capRequired: cap),
  };
}

RejectResult _parseRejectResult(String text) {
  final body = _parseTransitionBody(text);
  return switch (body) {
    _TransitionSuccessBody(:final lead) => RejectSuccess(lead),
    _TransitionAlreadyInStateBody(:final lead) => RejectAlreadyInState(lead),
    _TransitionErrorBody(:final kind, :final from, :final to, :final cap) =>
      RejectError(kind: kind, from: from, to: to, capRequired: cap),
  };
}

DeferResult _parseDeferResult(String text) {
  final body = _parseTransitionBody(text);
  return switch (body) {
    _TransitionSuccessBody(:final lead) => DeferSuccess(lead),
    _TransitionAlreadyInStateBody(:final lead) => DeferAlreadyInState(lead),
    _TransitionErrorBody(:final kind, :final from, :final to, :final cap) =>
      DeferError(kind: kind, from: from, to: to, capRequired: cap),
  };
}

/// Internal sum type — we parse the body once and then dispatch into
/// the typed RatifyResult / RejectResult / DeferResult so the three
/// public APIs share a single decode path.
sealed class _TransitionBody {
  const _TransitionBody();
}

class _TransitionSuccessBody extends _TransitionBody {
  final PendingLead lead;
  const _TransitionSuccessBody(this.lead);
}

class _TransitionAlreadyInStateBody extends _TransitionBody {
  final PendingLead lead;
  const _TransitionAlreadyInStateBody(this.lead);
}

class _TransitionErrorBody extends _TransitionBody {
  final String kind;
  final String from;
  final String to;
  final String? cap;
  const _TransitionErrorBody({
    required this.kind,
    required this.from,
    required this.to,
    required this.cap,
  });
}

_TransitionBody _parseTransitionBody(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return const _TransitionErrorBody(
      kind: 'parse_error',
      from: '',
      to: '',
      cap: null,
    );
  }
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      // Idempotent already_in_state body — brain emits
      // {"status":"already_in_state","lead":{...}}.
      if (parsed['status'] == 'already_in_state' &&
          parsed['lead'] is Map<String, dynamic>) {
        return _TransitionAlreadyInStateBody(
          PendingLead.fromJson(parsed['lead'] as Map<String, dynamic>),
        );
      }
      // Typed error body.
      if (parsed['error'] is String) {
        return _TransitionErrorBody(
          kind: parsed['error'] as String,
          from: (parsed['from'] ?? '').toString(),
          to: (parsed['to'] ?? '').toString(),
          cap: parsed['cap_required'] is String
              ? parsed['cap_required'] as String
              : null,
        );
      }
      // Bare Lead success body.
      if (parsed['id'] != null && parsed['status'] != null) {
        return _TransitionSuccessBody(PendingLead.fromJson(parsed));
      }
    }
  } catch (_) {
    // Fall through.
  }
  return const _TransitionErrorBody(
    kind: 'parse_error',
    from: '',
    to: '',
    cap: null,
  );
}

```
