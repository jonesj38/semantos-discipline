---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/visits_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.880324+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/visits_repository.dart

```dart
// D-O4.followup-2 — VisitList view-shape repository.
//
// Mirrors the parser in `apps/loom-svelte/src/views/VisitList.svelte`'s
// `parseVisits` and the shape of `customers_repository.dart`'s
// `parseCustomers` + the FSM transition wrappers in
// `jobs_repository.dart`.  Backed by the Semantos Brain dispatcher's typed
// `visits` resource (runtime/semantos-brain/src/resources/visits_handler.zig);
// `find visits` / `find visit <id>` / `add visit ...` / FSM verbs all
// route through that resource and emit canonical JSON.
//
// Field shape mirrors a SUBSET of the canonical `oddjobz.visit.v1`
// cell payload — enough for the helm VisitList table + drill-down
// detail view + state-aware action buttons.
//
// D-O5.followup-4 client hooks — when a [HelmEventStream] is supplied,
// the repo subscribes to `visit.created` + `visit.transitioned`
// notifications and surfaces them as [VisitsCacheEvent]s on
// [cacheEvents].  Mirrors the shape of `jobs_repository.dart`
// post-#318.

import 'dart:async';
import 'dart:convert';

import 'helm_event_stream.dart';
import 'repl_client.dart';

/// Single row of the helm Visits view.
class Visit {
  final String id;
  final String jobId;
  final String visitType;

  /// One of: `scheduled | in_progress | completed | cancelled`.
  final String status;
  final String notes;
  final String actualStart;
  final String outcome;
  final String createdAt;
  final String updatedAt;

  /// RM-124 — resolved parent-job context (the brain visits
  /// serializer now resolves the job → its RM-121 customer / site /
  /// work). Empty on pre-RM-124 rows / unresolved job.
  final String jobCustomerName;
  final String jobPropertyAddress;
  final String jobDescription;

  const Visit({
    required this.id,
    required this.jobId,
    required this.visitType,
    required this.status,
    required this.notes,
    required this.actualStart,
    required this.outcome,
    required this.createdAt,
    required this.updatedAt,
    this.jobCustomerName = '',
    this.jobPropertyAddress = '',
    this.jobDescription = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'job_id': jobId,
        'visit_type': visitType,
        'status': status,
        'notes': notes,
        'actual_start': actualStart,
        'outcome': outcome,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// D-O5.followup-4 — cache-invalidation event surfaced by
/// [VisitsRepository] when the live stream delivers a `visit.created`
/// or `visit.transitioned` notification.  Screens
/// (`VisitListScreen`, `VisitDetailScreen`) subscribe to
/// [VisitsRepository.cacheEvents] and refresh themselves on each
/// emission.  Mirrors `JobsCacheEvent` post-#318.
class VisitsCacheEvent {
  /// The visit id that changed.  Empty when the upstream payload
  /// didn't carry an id (defensive; the Semantos Brain emit always populates it).
  final String visitId;

  const VisitsCacheEvent({required this.visitId});
}

/// Repository over the REPL — the helm screens call this rather than
/// hand-parsing the REPL response themselves.  Mirrors
/// `JobsRepository` + `CustomersRepository`.
///
/// D-O5.followup-4 — when a [HelmEventStream] is supplied, the repo
/// subscribes to `visit.created` + `visit.transitioned` notifications
/// and surfaces them as [VisitsCacheEvent]s on [cacheEvents].  Screens
/// listen to the cache-event stream and refresh themselves on each
/// emission.  When the stream is null (tests, pull-only mode) the
/// cacheEvents stream is silent — no emissions, ever — and the repo
/// behaves as it did pre-followup-4.
class VisitsRepository {
  final ReplClient _repl;
  final StreamController<VisitsCacheEvent> _cacheCtl =
      StreamController<VisitsCacheEvent>.broadcast();
  StreamSubscription<HelmEvent>? _eventSub;

  VisitsRepository(this._repl, {HelmEventStream? eventStream}) {
    if (eventStream != null) {
      _eventSub = eventStream.events.listen(_onHelmEvent);
    }
  }

  /// Stream of cache-invalidation events the helm screens listen to.
  /// Broadcast — multiple screens can subscribe simultaneously.
  Stream<VisitsCacheEvent> get cacheEvents => _cacheCtl.stream;

  /// Release the event subscription + close the cache stream.  Call
  /// on logout / unpair so the next pairing starts with a clean
  /// repository.
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    if (!_cacheCtl.isClosed) await _cacheCtl.close();
  }

  void _onHelmEvent(HelmEvent event) {
    if (event.type != 'visit.created' && event.type != 'visit.transitioned') {
      return;
    }
    final id = event.data['id'];
    if (id is! String || id.isEmpty) return;
    _cacheCtl.add(VisitsCacheEvent(visitId: id));
  }

  /// Fetch all visits, optionally filtered by parent [jobId].  Throws
  /// [ReplUnauthorisedError] on transport-level 401 (helm pivots to
  /// pairing).
  Future<List<Visit>> findVisits({String? jobId}) async {
    final cmd = jobId == null ? 'find visits' : 'find visits --job-id $jobId';
    final resp = await _repl.send(cmd);
    return parseVisits(resp.result);
  }

  /// Fetch a single visit by id via the typed `visits.find_by_id`
  /// resource.  Returns null on the typed `{error: "not_found", id}`
  /// envelope or any parse failure.
  Future<Visit?> findVisit(String id) async {
    final resp = await _repl.send('find visit $id');
    return parseVisitOne(resp.result);
  }

  /// Create a new visit via the typed `visits.create` cmd.  Returns
  /// the typed result body — either `{id, status: "created" |
  /// "already_exists"}` or `{error: "job_not_found", job_id}` when the
  /// FK doesn't resolve.
  Future<VisitCreateResult> createVisit({
    required String jobId,
    required String visitType,
    String? notes,
    String? scheduledAt,
  }) async {
    final args = StringBuffer('add visit --job $jobId --type $visitType');
    if (notes != null && notes.isNotEmpty) {
      args.write(' --notes "${_escapeQuotes(notes)}"');
    }
    if (scheduledAt != null && scheduledAt.isNotEmpty) {
      args.write(' --at $scheduledAt');
    }
    final resp = await _repl.send(args.toString());
    return parseVisitCreateResult(resp.result);
  }

  /// D-O4.followup-2 — drive a visit through the canonical §O4 Visit
  /// FSM via the typed `visits.transition` dispatcher resource.
  /// Mirrors `JobsRepository.transitionJob` shape exactly.
  Future<VisitTransitionResult> transitionVisit({
    required String id,
    required String toState,
    String? presentedCap,
    required String principalKind,
  }) async {
    final args = StringBuffer('transition visit $id $toState')
      ..write(' --principal $principalKind');
    if (presentedCap != null) args.write(' --cap $presentedCap');
    final resp = await _repl.send(args.toString());
    return parseVisitTransitionResult(resp.result);
  }

  /// scheduled → in_progress (service principal).
  Future<VisitTransitionResult> startVisit(String id) async {
    final resp = await _repl.send('start visit $id');
    return parseVisitTransitionResult(resp.result);
  }

  /// in_progress → completed.  Optional [outcome] is stamped on the
  /// successor (defaults to "completed" server-side).
  Future<VisitTransitionResult> completeVisit(String id, {String? outcome}) async {
    final cmd = outcome == null
        ? 'complete visit $id'
        : 'complete visit $id --outcome $outcome';
    final resp = await _repl.send(cmd);
    return parseVisitTransitionResult(resp.result);
  }

  /// scheduled | in_progress → cancelled.  Outcome auto-stamps to
  /// "cancelled" server-side.
  Future<VisitTransitionResult> cancelVisit(String id) async {
    final resp = await _repl.send('cancel visit $id');
    return parseVisitTransitionResult(resp.result);
  }
}

String _escapeQuotes(String s) => s.replaceAll('"', r'\"');

/// Typed result for `visits.create`.
sealed class VisitCreateResult {
  const VisitCreateResult();
}

class VisitCreateSuccess extends VisitCreateResult {
  final String id;

  /// One of: `created | already_exists`.
  final String status;
  const VisitCreateSuccess({required this.id, required this.status});
}

class VisitCreateError extends VisitCreateResult {
  /// One of: `job_not_found | parse_error`.  Free-form so future kinds
  /// don't require an SDK churn.
  final String kind;
  final String? jobId;
  const VisitCreateError({required this.kind, this.jobId});
}

VisitCreateResult parseVisitCreateResult(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return const VisitCreateError(kind: 'parse_error');
  }
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['error'] == 'job_not_found') {
        return VisitCreateError(
          kind: 'job_not_found',
          jobId: parsed['job_id']?.toString(),
        );
      }
      if (parsed['id'] != null && parsed['status'] != null) {
        return VisitCreateSuccess(
          id: parsed['id'].toString(),
          status: parsed['status'].toString(),
        );
      }
    }
  } catch (_) {
    // Fall through to parse_error.
  }
  return const VisitCreateError(kind: 'parse_error');
}

/// Typed result shape for `visits.transition`.  Mirrors
/// JobTransitionResult.
sealed class VisitTransitionResult {
  const VisitTransitionResult();
}

class VisitTransitionSuccess extends VisitTransitionResult {
  final Visit visit;
  const VisitTransitionSuccess(this.visit);
}

class VisitTransitionAlreadyInState extends VisitTransitionResult {
  final Visit visit;
  const VisitTransitionAlreadyInState(this.visit);
}

class VisitTransitionError extends VisitTransitionResult {
  /// One of: `wrong_cap | not_reachable | wrong_principal |
  /// unknown_state | not_found | parse_error`.
  final String kind;
  final String from;
  final String to;
  final String? capRequired;

  const VisitTransitionError({
    required this.kind,
    required this.from,
    required this.to,
    this.capRequired,
  });

  String get message {
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
        return 'Visit no longer exists.';
      default:
        return 'Transition failed: $kind';
    }
  }
}

VisitTransitionResult parseVisitTransitionResult(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return const VisitTransitionError(kind: 'parse_error', from: '', to: '');
  }
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['status'] == 'already_in_state' &&
          parsed['visit'] is Map<String, dynamic>) {
        return VisitTransitionAlreadyInState(
          _visitFromJson(parsed['visit'] as Map<String, dynamic>),
        );
      }
      if (parsed['error'] is String) {
        return VisitTransitionError(
          kind: parsed['error'] as String,
          from: (parsed['from'] ?? '').toString(),
          to: (parsed['to'] ?? '').toString(),
          capRequired: parsed['cap_required'] is String
              ? parsed['cap_required'] as String
              : null,
        );
      }
      if (parsed['id'] != null && parsed['status'] != null) {
        return VisitTransitionSuccess(_visitFromJson(parsed));
      }
    }
  } catch (_) {
    // Fall through to parse_error.
  }
  return const VisitTransitionError(kind: 'parse_error', from: '', to: '');
}

/// Parse the REPL's `find visits` output into [Visit] rows.  JSON-only
/// — visits have no TSV legacy.
List<Visit> parseVisits(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  if (!(trimmed.startsWith('[') || trimmed.startsWith('{'))) return const [];
  try {
    final parsed = json.decode(trimmed);
    if (parsed is List) {
      return parsed.whereType<Map<String, dynamic>>().map(_visitFromJson).toList();
    }
  } catch (_) {
    // Fall through to empty.
  }
  return const [];
}

/// Parse a single-visit response from `visits.find_by_id`.  Returns
/// null on the typed `{"error":"not_found", ...}` envelope or any
/// parse failure.
Visit? parseVisitOne(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return null;
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['error'] == 'not_found') return null;
      if (parsed['id'] == null) return null;
      return _visitFromJson(parsed);
    }
    if (parsed is List && parsed.isNotEmpty) {
      final first = parsed.first;
      if (first is Map<String, dynamic>) return _visitFromJson(first);
    }
  } catch (_) {
    // Fall through to null.
  }
  return null;
}

Visit _visitFromJson(Map<String, dynamic> row) => Visit(
      id: (row['id'] ?? '').toString(),
      jobId: (row['job_id'] ?? '').toString(),
      visitType: (row['visit_type'] ?? '').toString(),
      status: (row['status'] ?? '').toString(),
      notes: (row['notes'] ?? '').toString(),
      actualStart: (row['actual_start'] ?? '').toString(),
      outcome: (row['outcome'] ?? '').toString(),
      createdAt: (row['created_at'] ?? '').toString(),
      updatedAt: (row['updated_at'] ?? '').toString(),
      jobCustomerName: (row['job_customer_name'] ?? '').toString(),
      jobPropertyAddress: (row['job_property_address'] ?? '').toString(),
      jobDescription: (row['job_description'] ?? '').toString(),
    );

```
