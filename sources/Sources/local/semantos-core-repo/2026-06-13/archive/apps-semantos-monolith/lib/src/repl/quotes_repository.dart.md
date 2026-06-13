---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/quotes_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.882400+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/quotes_repository.dart

```dart
// D-O4.followup-3 — QuoteList view-shape repository.
//
// Mirrors the parser in `apps/loom-svelte/src/views/QuoteList.svelte`'s
// `parseQuotes` and the shape of `visits_repository.dart`'s
// `parseVisits` + the FSM transition wrappers.  Backed by the Semantos Brain
// dispatcher's typed `quotes` resource (runtime/semantos-brain/src/resources/
// quotes_handler.zig); `find quotes` / `find quote <id>` /
// `add quote ...` / FSM verbs all route through that resource and emit
// canonical JSON.
//
// Field shape mirrors a SUBSET of the canonical `oddjobz.quote.v1`
// cell payload — enough for the helm QuoteList table + drill-down
// detail view + state-aware action buttons.
//
// D-O5.followup-4 client hooks — when a [HelmEventStream] is supplied,
// the repo subscribes to `quote.created` + `quote.transitioned`
// notifications and surfaces them as [QuotesCacheEvent]s on
// [cacheEvents].  Mirrors the shape of `jobs_repository.dart`
// post-#318.

import 'dart:async';
import 'dart:convert';

import 'helm_event_stream.dart';
import 'repl_client.dart';

/// Single row of the helm Quotes view.
class Quote {
  final String id;
  final String jobId;

  /// One of: `draft | presented | accepted | rejected | expired |
  /// superseded`.
  final String status;

  /// Lower bound of price quoted, in cents.
  final int costMin;

  /// Upper bound of price quoted, in cents.
  final int costMax;

  final String notes;
  final String acceptedAt;
  final String rejectedAt;
  final String createdAt;
  final String updatedAt;

  const Quote({
    required this.id,
    required this.jobId,
    required this.status,
    required this.costMin,
    required this.costMax,
    required this.notes,
    required this.acceptedAt,
    required this.rejectedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'job_id': jobId,
        'status': status,
        'cost_min': costMin,
        'cost_max': costMax,
        'notes': notes,
        'accepted_at': acceptedAt,
        'rejected_at': rejectedAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// D-O5.followup-4 — cache-invalidation event surfaced by
/// [QuotesRepository] when the live stream delivers a `quote.created`
/// or `quote.transitioned` notification.  Screens (`QuoteListScreen`,
/// `QuoteDetailScreen`) subscribe to [QuotesRepository.cacheEvents]
/// and refresh themselves on each emission.  Mirrors `JobsCacheEvent`
/// post-#318.
class QuotesCacheEvent {
  /// The quote id that changed.  Empty when the upstream payload
  /// didn't carry an id (defensive; the Semantos Brain emit always populates it).
  final String quoteId;

  const QuotesCacheEvent({required this.quoteId});
}

/// Repository over the REPL — the helm screens call this rather than
/// hand-parsing the REPL response themselves.  Mirrors
/// `VisitsRepository`.
///
/// D-O5.followup-4 — when a [HelmEventStream] is supplied, the repo
/// subscribes to `quote.created` + `quote.transitioned` notifications
/// and surfaces them as [QuotesCacheEvent]s on [cacheEvents].  Screens
/// listen to the cache-event stream and refresh themselves on each
/// emission.  When the stream is null (tests, pull-only mode) the
/// cacheEvents stream is silent — no emissions, ever — and the repo
/// behaves as it did pre-followup-4.
class QuotesRepository {
  final ReplClient _repl;
  final StreamController<QuotesCacheEvent> _cacheCtl =
      StreamController<QuotesCacheEvent>.broadcast();
  StreamSubscription<HelmEvent>? _eventSub;

  QuotesRepository(this._repl, {HelmEventStream? eventStream}) {
    if (eventStream != null) {
      _eventSub = eventStream.events.listen(_onHelmEvent);
    }
  }

  /// Stream of cache-invalidation events the helm screens listen to.
  /// Broadcast — multiple screens can subscribe simultaneously.
  Stream<QuotesCacheEvent> get cacheEvents => _cacheCtl.stream;

  /// Release the event subscription + close the cache stream.  Call
  /// on logout / unpair so the next pairing starts with a clean
  /// repository.
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    if (!_cacheCtl.isClosed) await _cacheCtl.close();
  }

  void _onHelmEvent(HelmEvent event) {
    if (event.type != 'quote.created' && event.type != 'quote.transitioned') {
      return;
    }
    final id = event.data['id'];
    if (id is! String || id.isEmpty) return;
    _cacheCtl.add(QuotesCacheEvent(quoteId: id));
  }

  /// Fetch all quotes, optionally filtered by parent [jobId].  Throws
  /// [ReplUnauthorisedError] on transport-level 401 (helm pivots to
  /// pairing).
  Future<List<Quote>> findQuotes({String? jobId}) async {
    final cmd = jobId == null ? 'find quotes' : 'find quotes --job-id $jobId';
    final resp = await _repl.send(cmd);
    return parseQuotes(resp.result);
  }

  /// Fetch a single quote by id via the typed `quotes.find_by_id`
  /// resource.  Returns null on the typed `{error: "not_found", id}`
  /// envelope or any parse failure.
  Future<Quote?> findQuote(String id) async {
    final resp = await _repl.send('find quote $id');
    return parseQuoteOne(resp.result);
  }

  /// Create a new quote via the typed `quotes.create` cmd.  Returns
  /// the typed result body — either `{id, status: "created" |
  /// "already_exists"}` or `{error: "job_not_found", job_id}` when the
  /// FK doesn't resolve.
  Future<QuoteCreateResult> createQuote({
    required String jobId,
    int? costMin,
    int? costMax,
    String? notes,
  }) async {
    final args = StringBuffer('add quote --job $jobId');
    if (costMin != null) args.write(' --cost-min $costMin');
    if (costMax != null) args.write(' --cost-max $costMax');
    if (notes != null && notes.isNotEmpty) {
      args.write(' --notes "${_escapeQuotes(notes)}"');
    }
    final resp = await _repl.send(args.toString());
    return parseQuoteCreateResult(resp.result);
  }

  /// D-O4.followup-3 — drive a quote through the canonical §O4 Quote
  /// FSM via the typed `quotes.transition` dispatcher resource.
  /// Mirrors `VisitsRepository.transitionVisit` shape exactly.
  Future<QuoteTransitionResult> transitionQuote({
    required String id,
    required String toState,
    String? presentedCap,
    required String principalKind,
  }) async {
    final args = StringBuffer('transition quote $id $toState')
      ..write(' --principal $principalKind');
    if (presentedCap != null) args.write(' --cap $presentedCap');
    final resp = await _repl.send(args.toString());
    return parseQuoteTransitionResult(resp.result);
  }

  /// draft → presented (operator principal).
  Future<QuoteTransitionResult> presentQuote(String id) async {
    final resp = await _repl.send('present quote $id');
    return parseQuoteTransitionResult(resp.result);
  }

  /// presented → accepted (service principal).  Server stamps
  /// accepted_at when omitted.
  Future<QuoteTransitionResult> acceptQuote(String id) async {
    final resp = await _repl.send('accept quote $id');
    return parseQuoteTransitionResult(resp.result);
  }

  /// presented → rejected (service principal).  Server stamps
  /// rejected_at when omitted.
  Future<QuoteTransitionResult> declineQuote(String id, {String? reason}) async {
    final cmd = reason == null
        ? 'decline quote $id'
        : 'decline quote $id --reason "${_escapeQuotes(reason)}"';
    final resp = await _repl.send(cmd);
    return parseQuoteTransitionResult(resp.result);
  }

  /// presented → expired (service principal).
  Future<QuoteTransitionResult> expireQuote(String id) async {
    final resp = await _repl.send('expire quote $id');
    return parseQuoteTransitionResult(resp.result);
  }

  /// draft | presented → superseded (operator principal).
  Future<QuoteTransitionResult> supersedeQuote(String id) async {
    final resp = await _repl.send('supersede quote $id');
    return parseQuoteTransitionResult(resp.result);
  }
}

String _escapeQuotes(String s) => s.replaceAll('"', r'\"');

/// Typed result for `quotes.create`.
sealed class QuoteCreateResult {
  const QuoteCreateResult();
}

class QuoteCreateSuccess extends QuoteCreateResult {
  final String id;

  /// One of: `created | already_exists`.
  final String status;
  const QuoteCreateSuccess({required this.id, required this.status});
}

class QuoteCreateError extends QuoteCreateResult {
  /// One of: `job_not_found | parse_error`.  Free-form so future kinds
  /// don't require an SDK churn.
  final String kind;
  final String? jobId;
  const QuoteCreateError({required this.kind, this.jobId});
}

QuoteCreateResult parseQuoteCreateResult(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return const QuoteCreateError(kind: 'parse_error');
  }
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['error'] == 'job_not_found') {
        return QuoteCreateError(
          kind: 'job_not_found',
          jobId: parsed['job_id']?.toString(),
        );
      }
      if (parsed['id'] != null && parsed['status'] != null) {
        return QuoteCreateSuccess(
          id: parsed['id'].toString(),
          status: parsed['status'].toString(),
        );
      }
    }
  } catch (_) {
    // Fall through to parse_error.
  }
  return const QuoteCreateError(kind: 'parse_error');
}

/// Typed result shape for `quotes.transition`.  Mirrors
/// VisitTransitionResult.
sealed class QuoteTransitionResult {
  const QuoteTransitionResult();
}

class QuoteTransitionSuccess extends QuoteTransitionResult {
  final Quote quote;
  const QuoteTransitionSuccess(this.quote);
}

class QuoteTransitionAlreadyInState extends QuoteTransitionResult {
  final Quote quote;
  const QuoteTransitionAlreadyInState(this.quote);
}

class QuoteTransitionError extends QuoteTransitionResult {
  /// One of: `wrong_cap | not_reachable | wrong_principal |
  /// unknown_state | not_found | parse_error`.
  final String kind;
  final String from;
  final String to;
  final String? capRequired;

  const QuoteTransitionError({
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
        return 'Quote no longer exists.';
      default:
        return 'Transition failed: $kind';
    }
  }
}

QuoteTransitionResult parseQuoteTransitionResult(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return const QuoteTransitionError(kind: 'parse_error', from: '', to: '');
  }
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['status'] == 'already_in_state' &&
          parsed['quote'] is Map<String, dynamic>) {
        return QuoteTransitionAlreadyInState(
          _quoteFromJson(parsed['quote'] as Map<String, dynamic>),
        );
      }
      if (parsed['error'] is String) {
        return QuoteTransitionError(
          kind: parsed['error'] as String,
          from: (parsed['from'] ?? '').toString(),
          to: (parsed['to'] ?? '').toString(),
          capRequired: parsed['cap_required'] is String
              ? parsed['cap_required'] as String
              : null,
        );
      }
      if (parsed['id'] != null && parsed['status'] != null) {
        return QuoteTransitionSuccess(_quoteFromJson(parsed));
      }
    }
  } catch (_) {
    // Fall through to parse_error.
  }
  return const QuoteTransitionError(kind: 'parse_error', from: '', to: '');
}

/// Parse the REPL's `find quotes` output into [Quote] rows.  JSON-only
/// — quotes have no TSV legacy.
List<Quote> parseQuotes(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  if (!(trimmed.startsWith('[') || trimmed.startsWith('{'))) return const [];
  try {
    final parsed = json.decode(trimmed);
    if (parsed is List) {
      return parsed.whereType<Map<String, dynamic>>().map(_quoteFromJson).toList();
    }
  } catch (_) {
    // Fall through to empty.
  }
  return const [];
}

/// Parse a single-quote response from `quotes.find_by_id`.  Returns
/// null on the typed `{"error":"not_found", ...}` envelope or any
/// parse failure.
Quote? parseQuoteOne(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return null;
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['error'] == 'not_found') return null;
      if (parsed['id'] == null) return null;
      return _quoteFromJson(parsed);
    }
    if (parsed is List && parsed.isNotEmpty) {
      final first = parsed.first;
      if (first is Map<String, dynamic>) return _quoteFromJson(first);
    }
  } catch (_) {
    // Fall through to null.
  }
  return null;
}

Quote _quoteFromJson(Map<String, dynamic> row) => Quote(
      id: (row['id'] ?? '').toString(),
      jobId: (row['job_id'] ?? '').toString(),
      status: (row['status'] ?? '').toString(),
      costMin: _toInt(row['cost_min']),
      costMax: _toInt(row['cost_max']),
      notes: (row['notes'] ?? '').toString(),
      acceptedAt: (row['accepted_at'] ?? '').toString(),
      rejectedAt: (row['rejected_at'] ?? '').toString(),
      createdAt: (row['created_at'] ?? '').toString(),
      updatedAt: (row['updated_at'] ?? '').toString(),
    );

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

```
