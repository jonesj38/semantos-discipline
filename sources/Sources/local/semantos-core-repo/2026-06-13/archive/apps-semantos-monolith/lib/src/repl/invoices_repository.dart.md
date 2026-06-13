---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/invoices_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.882101+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/invoices_repository.dart

```dart
// D-O4.followup-4 — InvoiceList view-shape repository.
//
// Mirrors the parser in `apps/loom-svelte/src/views/InvoiceList.svelte`'s
// `parseInvoices` and the shape of `quotes_repository.dart`'s
// `parseQuotes` + the FSM transition wrappers.  Backed by the Semantos Brain
// dispatcher's typed `invoices` resource (runtime/semantos-brain/src/resources/
// invoices_handler.zig); `find invoices` / `find invoice <id>` /
// `add invoice ...` / FSM verbs all route through that resource and emit
// canonical JSON.
//
// Field shape mirrors a SUBSET of the canonical `oddjobz.invoice.v1`
// cell payload — enough for the helm InvoiceList table + drill-down
// detail view + state-aware action buttons.  Closes the Semantos Brain-side
// cutover of all 4 oddjobz FSMs.
//
// D-O5.followup-4 client hooks — when a [HelmEventStream] is supplied,
// the repo subscribes to `invoice.created` + `invoice.transitioned`
// notifications and surfaces them as [InvoicesCacheEvent]s on
// [cacheEvents].  Mirrors the shape of `jobs_repository.dart`
// post-#318.

import 'dart:async';
import 'dart:convert';

import 'helm_event_stream.dart';
import 'repl_client.dart';

/// Single row of the helm Invoices view.
class Invoice {
  final String id;
  final String jobId;

  /// One of: `draft | sent | viewed | partial | paid | overdue |
  /// cancelled`.
  final String status;

  /// Total amount due, in cents.
  final int amount;

  /// Amount already paid, in cents (0 unless partial/paid).
  final int amountPaid;

  /// External invoice reference (Xero/Stripe id, etc.) — may be empty.
  final String externalInvoiceId;

  final String notes;
  final String sentAt;
  final String viewedAt;
  final String paidAt;
  final String createdAt;
  final String updatedAt;

  const Invoice({
    required this.id,
    required this.jobId,
    required this.status,
    required this.amount,
    required this.amountPaid,
    required this.externalInvoiceId,
    required this.notes,
    required this.sentAt,
    required this.viewedAt,
    required this.paidAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'job_id': jobId,
        'status': status,
        'amount': amount,
        'amount_paid': amountPaid,
        'external_invoice_id': externalInvoiceId,
        'notes': notes,
        'sent_at': sentAt,
        'viewed_at': viewedAt,
        'paid_at': paidAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// D-O5.followup-4 — cache-invalidation event surfaced by
/// [InvoicesRepository] when the live stream delivers an
/// `invoice.created` or `invoice.transitioned` notification.  Screens
/// (`InvoiceListScreen`, `InvoiceDetailScreen`) subscribe to
/// [InvoicesRepository.cacheEvents] and refresh themselves on each
/// emission.  Mirrors `JobsCacheEvent` post-#318.
class InvoicesCacheEvent {
  /// The invoice id that changed.  Empty when the upstream payload
  /// didn't carry an id (defensive; the Semantos Brain emit always populates it).
  final String invoiceId;

  const InvoicesCacheEvent({required this.invoiceId});
}

/// Repository over the REPL — the helm screens call this rather than
/// hand-parsing the REPL response themselves.  Mirrors
/// `QuotesRepository`.
///
/// D-O5.followup-4 — when a [HelmEventStream] is supplied, the repo
/// subscribes to `invoice.created` + `invoice.transitioned`
/// notifications and surfaces them as [InvoicesCacheEvent]s on
/// [cacheEvents].  Screens listen to the cache-event stream and
/// refresh themselves on each emission.  When the stream is null
/// (tests, pull-only mode) the cacheEvents stream is silent — no
/// emissions, ever — and the repo behaves as it did pre-followup-4.
class InvoicesRepository {
  final ReplClient _repl;
  final StreamController<InvoicesCacheEvent> _cacheCtl =
      StreamController<InvoicesCacheEvent>.broadcast();
  StreamSubscription<HelmEvent>? _eventSub;

  InvoicesRepository(this._repl, {HelmEventStream? eventStream}) {
    if (eventStream != null) {
      _eventSub = eventStream.events.listen(_onHelmEvent);
    }
  }

  /// Stream of cache-invalidation events the helm screens listen to.
  /// Broadcast — multiple screens can subscribe simultaneously.
  Stream<InvoicesCacheEvent> get cacheEvents => _cacheCtl.stream;

  /// Release the event subscription + close the cache stream.  Call
  /// on logout / unpair so the next pairing starts with a clean
  /// repository.
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    if (!_cacheCtl.isClosed) await _cacheCtl.close();
  }

  void _onHelmEvent(HelmEvent event) {
    if (event.type != 'invoice.created' &&
        event.type != 'invoice.transitioned') {
      return;
    }
    final id = event.data['id'];
    if (id is! String || id.isEmpty) return;
    _cacheCtl.add(InvoicesCacheEvent(invoiceId: id));
  }

  /// Fetch all invoices, optionally filtered by parent [jobId].
  /// Throws [ReplUnauthorisedError] on transport-level 401 (helm
  /// pivots to pairing).
  Future<List<Invoice>> findInvoices({String? jobId}) async {
    final cmd = jobId == null ? 'find invoices' : 'find invoices --job-id $jobId';
    final resp = await _repl.send(cmd);
    return parseInvoices(resp.result);
  }

  /// Fetch a single invoice by id via the typed `invoices.find_by_id`
  /// resource.  Returns null on the typed `{error: "not_found", id}`
  /// envelope or any parse failure.
  Future<Invoice?> findInvoice(String id) async {
    final resp = await _repl.send('find invoice $id');
    return parseInvoiceOne(resp.result);
  }

  /// Create a new invoice via the typed `invoices.create` cmd.
  /// Returns the typed result body — either `{id, status: "created" |
  /// "already_exists"}` or `{error: "job_not_found", job_id}` when the
  /// FK doesn't resolve.
  Future<InvoiceCreateResult> createInvoice({
    required String jobId,
    int? amount,
    String? notes,
  }) async {
    final args = StringBuffer('add invoice --job $jobId');
    if (amount != null) args.write(' --amount $amount');
    if (notes != null && notes.isNotEmpty) {
      args.write(' --notes "${_escapeQuotes(notes)}"');
    }
    final resp = await _repl.send(args.toString());
    return parseInvoiceCreateResult(resp.result);
  }

  /// D-O4.followup-4 — drive an invoice through the canonical §O4
  /// Invoice FSM via the typed `invoices.transition` dispatcher
  /// resource.  Mirrors `QuotesRepository.transitionQuote` shape
  /// exactly.
  Future<InvoiceTransitionResult> transitionInvoice({
    required String id,
    required String toState,
    String? presentedCap,
    required String principalKind,
    int? amountPaid,
  }) async {
    final args = StringBuffer('transition invoice $id $toState')
      ..write(' --principal $principalKind');
    if (presentedCap != null) args.write(' --cap $presentedCap');
    final resp = await _repl.send(args.toString());
    return parseInvoiceTransitionResult(resp.result);
  }

  /// draft → sent (operator principal).  Server stamps sent_at when
  /// omitted.
  Future<InvoiceTransitionResult> sendInvoice(String id) async {
    final resp = await _repl.send('send invoice $id');
    return parseInvoiceTransitionResult(resp.result);
  }

  /// any → paid (service principal).  Server stamps paid_at +
  /// amount_paid := amount when omitted.
  Future<InvoiceTransitionResult> markPaid(String id, {int? amount}) async {
    final cmd = amount == null
        ? 'mark invoice paid $id'
        : 'mark invoice paid $id --amount $amount';
    final resp = await _repl.send(cmd);
    return parseInvoiceTransitionResult(resp.result);
  }

  /// sent|viewed|overdue → partial (service principal).
  Future<InvoiceTransitionResult> markPartial(String id, {required int amount}) async {
    final resp = await _repl.send('mark invoice partial $id --amount $amount');
    return parseInvoiceTransitionResult(resp.result);
  }

  /// sent → viewed (service principal).  Server stamps viewed_at.
  Future<InvoiceTransitionResult> markViewed(String id) async {
    final resp = await _repl.send('mark invoice viewed $id');
    return parseInvoiceTransitionResult(resp.result);
  }

  /// sent|viewed|partial → overdue (service principal).
  Future<InvoiceTransitionResult> markOverdue(String id) async {
    final resp = await _repl.send('mark invoice overdue $id');
    return parseInvoiceTransitionResult(resp.result);
  }

  /// draft|sent|viewed → cancelled (operator principal).
  Future<InvoiceTransitionResult> cancelInvoice(String id) async {
    final resp = await _repl.send('cancel invoice $id');
    return parseInvoiceTransitionResult(resp.result);
  }
}

String _escapeQuotes(String s) => s.replaceAll('"', r'\"');

/// Typed result for `invoices.create`.
sealed class InvoiceCreateResult {
  const InvoiceCreateResult();
}

class InvoiceCreateSuccess extends InvoiceCreateResult {
  final String id;

  /// One of: `created | already_exists`.
  final String status;
  const InvoiceCreateSuccess({required this.id, required this.status});
}

class InvoiceCreateError extends InvoiceCreateResult {
  /// One of: `job_not_found | parse_error`.  Free-form so future kinds
  /// don't require an SDK churn.
  final String kind;
  final String? jobId;
  const InvoiceCreateError({required this.kind, this.jobId});
}

InvoiceCreateResult parseInvoiceCreateResult(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return const InvoiceCreateError(kind: 'parse_error');
  }
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['error'] == 'job_not_found') {
        return InvoiceCreateError(
          kind: 'job_not_found',
          jobId: parsed['job_id']?.toString(),
        );
      }
      if (parsed['id'] != null && parsed['status'] != null) {
        return InvoiceCreateSuccess(
          id: parsed['id'].toString(),
          status: parsed['status'].toString(),
        );
      }
    }
  } catch (_) {
    // Fall through to parse_error.
  }
  return const InvoiceCreateError(kind: 'parse_error');
}

/// Typed result shape for `invoices.transition`.  Mirrors
/// QuoteTransitionResult.
sealed class InvoiceTransitionResult {
  const InvoiceTransitionResult();
}

class InvoiceTransitionSuccess extends InvoiceTransitionResult {
  final Invoice invoice;
  const InvoiceTransitionSuccess(this.invoice);
}

class InvoiceTransitionAlreadyInState extends InvoiceTransitionResult {
  final Invoice invoice;
  const InvoiceTransitionAlreadyInState(this.invoice);
}

class InvoiceTransitionError extends InvoiceTransitionResult {
  /// One of: `wrong_cap | not_reachable | wrong_principal |
  /// unknown_state | not_found | parse_error`.
  final String kind;
  final String from;
  final String to;
  final String? capRequired;

  const InvoiceTransitionError({
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
        return 'Invoice no longer exists.';
      default:
        return 'Transition failed: $kind';
    }
  }
}

InvoiceTransitionResult parseInvoiceTransitionResult(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return const InvoiceTransitionError(kind: 'parse_error', from: '', to: '');
  }
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['status'] == 'already_in_state' &&
          parsed['invoice'] is Map<String, dynamic>) {
        return InvoiceTransitionAlreadyInState(
          _invoiceFromJson(parsed['invoice'] as Map<String, dynamic>),
        );
      }
      if (parsed['error'] is String) {
        return InvoiceTransitionError(
          kind: parsed['error'] as String,
          from: (parsed['from'] ?? '').toString(),
          to: (parsed['to'] ?? '').toString(),
          capRequired: parsed['cap_required'] is String
              ? parsed['cap_required'] as String
              : null,
        );
      }
      if (parsed['id'] != null && parsed['status'] != null) {
        return InvoiceTransitionSuccess(_invoiceFromJson(parsed));
      }
    }
  } catch (_) {
    // Fall through to parse_error.
  }
  return const InvoiceTransitionError(kind: 'parse_error', from: '', to: '');
}

/// Parse the REPL's `find invoices` output into [Invoice] rows.
/// JSON-only — invoices have no TSV legacy.
List<Invoice> parseInvoices(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  if (!(trimmed.startsWith('[') || trimmed.startsWith('{'))) return const [];
  try {
    final parsed = json.decode(trimmed);
    if (parsed is List) {
      return parsed.whereType<Map<String, dynamic>>().map(_invoiceFromJson).toList();
    }
  } catch (_) {
    // Fall through to empty.
  }
  return const [];
}

/// Parse a single-invoice response from `invoices.find_by_id`.
/// Returns null on the typed `{"error":"not_found", ...}` envelope or
/// any parse failure.
Invoice? parseInvoiceOne(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return null;
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['error'] == 'not_found') return null;
      if (parsed['id'] == null) return null;
      return _invoiceFromJson(parsed);
    }
    if (parsed is List && parsed.isNotEmpty) {
      final first = parsed.first;
      if (first is Map<String, dynamic>) return _invoiceFromJson(first);
    }
  } catch (_) {
    // Fall through to null.
  }
  return null;
}

Invoice _invoiceFromJson(Map<String, dynamic> row) => Invoice(
      id: (row['id'] ?? '').toString(),
      jobId: (row['job_id'] ?? '').toString(),
      status: (row['status'] ?? '').toString(),
      amount: _toInt(row['amount']),
      amountPaid: _toInt(row['amount_paid']),
      externalInvoiceId: (row['external_invoice_id'] ?? '').toString(),
      notes: (row['notes'] ?? '').toString(),
      sentAt: (row['sent_at'] ?? '').toString(),
      viewedAt: (row['viewed_at'] ?? '').toString(),
      paidAt: (row['paid_at'] ?? '').toString(),
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
