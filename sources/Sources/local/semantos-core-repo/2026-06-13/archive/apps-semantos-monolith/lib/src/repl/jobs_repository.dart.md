---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/jobs_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.883917+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/jobs_repository.dart

```dart
// D-O5m — JobList view-shape repository.
//
// Mirrors the parser in `apps/loom-svelte/src/views/JobList.svelte`'s
// `parseJobs`.  As of D-O5.followup-1 / D-O5m.followup-4 the Semantos Brain REPL
// emits canonical JSON for both `find jobs` and `find job <id>` via
// the typed `jobs` dispatcher resource (runtime/semantos-brain/src/resources/
// jobs_handler.zig); the TSV fallback stays in place for backwards-
// compat with any operator wiring a different upstream.

import 'dart:async';
import 'dart:convert';

import 'hat_entity_repository.dart';
import 'helm_event_stream.dart';
import 'repl_client.dart';

/// One element of `Job.customerRefs` — D-DOG.1.0c Phase 3 F.1 v2
/// graph-aware addition.  Mirrors the Semantos Brain-side
/// `oddjobz_query_handler.zig::writeJob` `customerRefs[]` shape.  v1
/// rows don't have customerRefs at all (the field on Job is null);
/// v2 rows always have a non-null array (possibly empty when a job
/// was minted before the operator triaged its customer).  Within a
/// non-empty array, exactly one entry has `primary == true` per the
/// `oddjobz.job.v2` schema's exactly-one-primary invariant.
class JobCustomerRef {
  /// 64-lowercase-hex cellId of the linked `customer.v2` cell.
  final String cellId;

  /// Customer role per `oddjobz.job.v2` `CUSTOMER_ROLES` —
  /// `tenant | agent | owner | pm | sub-tradie | other`.  Free-form
  /// from the Dart side so a future role enum addition doesn't
  /// require a model bump.
  final String role;

  /// True for exactly one entry per non-empty `customerRefs` array.
  /// The JobList uses this to pick the row's "primary customer"
  /// without scanning the whole array twice.
  final bool primary;

  /// RM-121 — resolved contact identity from the linked customer
  /// cell so Home can show who to call without a second fetch.
  /// Empty when the brain hasn't resolved it (pre-RM-121 rows).
  final String name;

  /// RM-121 — resolved contact phone (empty when unresolved).
  final String phone;

  const JobCustomerRef({
    required this.cellId,
    required this.role,
    required this.primary,
    this.name = '',
    this.phone = '',
  });
}

/// Single row of the helm Jobs view.
///
/// D-DOG.1.0c Phase 3 F.1 — extended with optional v2 graph-aware
/// fields.  v1 rows still parse cleanly: every v2 field defaults to
/// null and renderers fall back to the existing v1 surface (customer
/// name string, no site address, no due date, no photos icon).  v2
/// rows populate the v2 fields from the `oddjobz.list_*` /
/// `oddjobz.find_jobs_*` / `oddjobz.get_job` query handler responses
/// (`runtime/semantos-brain/src/oddjobz_query_handler.zig::writeJob`).  The
/// existing REPL `find jobs` path is forward-compatible — if the
/// brain serialises v2 fields they're captured, otherwise they stay
/// null without breaking the row.
class Job {
  final String id;
  final String customerName;
  final String state;
  final String scheduledAt;

  // ── v2 graph-aware fields (null on v1 rows) ───────────────────────

  /// 64-lowercase-hex cellId of the linked `site.v2` cell, or null
  /// for v1 rows.  Phase 3 F.2 (mobile site-pivot) keys off this.
  final String? siteRef;

  /// Convenience: full normalised property address derived from the
  /// linked `site.v2` cell.  Populated by the JobList screen after
  /// it bulk-fetches `oddjobz.list_sites()` and looks up each row's
  /// siteRef in the resulting map.  Null on v1 rows.  Mirrors the
  /// helm SPA's `Site.fullAddress` field.
  final String? propertyAddress;

  /// RM-121 — the work description (ingest `summary`). Surfaced on
  /// Home under site → contact. Null on rows without a description.
  final String? description;

  /// Operator-facing access key (e.g. "key #177") for the
  /// tradesperson.  Mirrors `oddjobz.job.v2.propertyKey`; nullable
  /// on v2 rows (not every WO carries one) and always null on v1.
  final String? propertyKey;

  /// cellIDs + role + primary flag of linked `customer.v2` cells.
  /// v1 rows have null; v2 rows have a non-null (possibly-empty)
  /// list.  Render the primary entry by scanning for `primary ==
  /// true` (exactly one in a non-empty list per the v2 schema).
  final List<JobCustomerRef>? customerRefs;

  /// ISO 8601 calendar date (YYYY-MM-DD) the work order is due.
  /// v1 rows: null.  v2 rows: nullable per the schema (operator may
  /// not have set a deadline).  The JobList parses this to a
  /// [DateTime] via [dueDate]; this raw field is preserved for
  /// round-tripping.
  final String? dueDateRaw;

  /// Verbatim work-order number from the source PDF (e.g. "07487").
  /// v1: null.  v2: nullable.  Phase 3 F.4's attachment screen
  /// surfaces this prominently; F.1 doesn't render it in the list
  /// but parses it for completeness so the row survives a navigate-
  /// to-detail without re-fetching.
  final String? workOrderNumber;

  /// RM-125 — WO issuance date (ISO yyyy-mm-dd) + the joined
  /// services list ("a, b, c") so the operator sees scope/details
  /// without the source PDF. Null when absent.
  final String? issuanceDate;
  final String? services;

  /// Convenience derived flag: photos present in the source PDF.
  /// v1: null.  v2: required-true-or-false per the schema.  The
  /// JobList renders the camera icon when this is true.
  final bool? hasPhotos;

  /// Number of distinct embedded photos (Vision-detected).  v1:
  /// null.  v2: nullable when the source can't be counted reliably.
  /// When non-null + hasPhotos==true the JobList shows the count
  /// next to the icon.
  final int? photoCount;

  /// D-DOG.1.0c Phase 5 G.2 — true when this row is a pre-Layer-1 v1
  /// flat cell that the `legacy migrate-to-graph` verb couldn't match
  /// to a source proposal.  The JobList renders a small "legacy" pill
  /// next to the state chip when this is true so the operator knows
  /// the cell pre-dates Layer 1 promotion and is unsigned (per Phase
  /// 4's BKDS posture).  False for every v2 graph-aware row and for
  /// v1 rows that successfully migrated.  Defaults to false on the
  /// existing wire shape since the Semantos Brain side will only emit it once
  /// the query handler is taught to read the marker file (the
  /// follow-up to this PR's TS verb work).
  final bool legacyUnsigned;

  /// 64-lowercase-hex cell hash of this job's LMDB cell.  Present on
  /// v2 (entity-anchored) rows; null on legacy v1 rows that pre-date
  /// the entity-anchoring migration.  Used as the `entityRef` query
  /// parameter when fetching the job's conversation turns from
  /// GET /api/v1/conversation/turns.
  final String? cellId;

  const Job({
    required this.id,
    required this.customerName,
    required this.state,
    required this.scheduledAt,
    this.siteRef,
    this.propertyAddress,
    this.description,
    this.propertyKey,
    this.customerRefs,
    this.dueDateRaw,
    this.workOrderNumber,
    this.issuanceDate,
    this.services,
    this.hasPhotos,
    this.photoCount,
    this.legacyUnsigned = false,
    this.cellId,
  });

  /// Parse [dueDateRaw] (`YYYY-MM-DD`) into a [DateTime].  Returns
  /// null on missing or malformed input — the row renderer falls
  /// back to "—" in either case so a single bad date doesn't break
  /// the whole list.
  DateTime? get dueDate {
    final raw = dueDateRaw;
    if (raw == null || raw.isEmpty) return null;
    // ISO calendar date + UTC midnight — parse as UTC so the helm's
    // "Due 24 Mar" relative format doesn't drift across timezones.
    return DateTime.tryParse('${raw}T00:00:00Z');
  }

  /// True when this is a v2 (graph-aware) row.  Heuristic — siteRef
  /// is present iff the Semantos Brain side emitted a v2 row.  Used by the
  /// JobList renderer to decide whether to show "—" placeholders or
  /// the v2 enriched fields.
  bool get isV2 => siteRef != null;

  /// Return the entry in [customerRefs] flagged `primary: true`, or
  /// null when this is a v1 row OR a v2 row with no customers
  /// linked yet.  The v2 schema guarantees at most one primary per
  /// non-empty list; we surface the first match defensively in case
  /// the wire payload violates that invariant.
  JobCustomerRef? get primaryCustomerRef {
    final refs = customerRefs;
    if (refs == null || refs.isEmpty) return null;
    for (final r in refs) {
      if (r.primary) return r;
    }
    return null;
  }

  /// Return a copy of this row with [propertyAddress] replaced.  The
  /// JobList screen uses this to enrich rows after the bulk site
  /// fetch resolves `siteRef → fullAddress`.  All other fields are
  /// preserved verbatim.
  Job withPropertyAddress(String? newAddress) => Job(
        id: id,
        customerName: customerName,
        state: state,
        scheduledAt: scheduledAt,
        siteRef: siteRef,
        propertyAddress: newAddress,
        description: description,
        propertyKey: propertyKey,
        customerRefs: customerRefs,
        dueDateRaw: dueDateRaw,
        workOrderNumber: workOrderNumber,
        issuanceDate: issuanceDate,
        services: services,
        hasPhotos: hasPhotos,
        photoCount: photoCount,
        legacyUnsigned: legacyUnsigned,
        cellId: cellId,
      );

  /// D-DOG.1.0c Phase 5 G.2 — return a copy with [legacyUnsigned]
  /// replaced.  The JobList screen uses this when it cross-references
  /// the (eventually-wired) brain-side legacy-unsigned marker query
  /// against the row id, so the row carries the badge-flag once the
  /// brain confirms it.
  Job withLegacyUnsigned(bool flag) => Job(
        id: id,
        customerName: customerName,
        state: state,
        scheduledAt: scheduledAt,
        siteRef: siteRef,
        propertyAddress: propertyAddress,
        description: description,
        propertyKey: propertyKey,
        customerRefs: customerRefs,
        dueDateRaw: dueDateRaw,
        workOrderNumber: workOrderNumber,
        issuanceDate: issuanceDate,
        services: services,
        hasPhotos: hasPhotos,
        photoCount: photoCount,
        legacyUnsigned: flag,
        cellId: cellId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_name': customerName,
        'state': state,
        'scheduled_at': scheduledAt,
        if (siteRef != null) 'siteRef': siteRef,
        if (propertyAddress != null) 'propertyAddress': propertyAddress,
        if (description != null) 'description': description,
        if (propertyKey != null) 'propertyKey': propertyKey,
        if (customerRefs != null)
          'customerRefs': customerRefs!
              .map((r) => {
                    'cellId': r.cellId,
                    'role': r.role,
                    'primary': r.primary,
                  })
              .toList(),
        if (dueDateRaw != null) 'dueDate': dueDateRaw,
        if (workOrderNumber != null) 'workOrderNumber': workOrderNumber,
        if (issuanceDate != null) 'issuanceDate': issuanceDate,
        if (services != null) 'services': services,
        if (hasPhotos != null) 'hasPhotos': hasPhotos,
        if (photoCount != null) 'photoCount': photoCount,
        // D-DOG.1.0c Phase 5 G.2 — only emit the flag when set so the
        // existing wire shape stays byte-identical for the common case
        // (Phase 4 graph rows and migrated rows both produce false).
        if (legacyUnsigned) 'legacy_unsigned': legacyUnsigned,
      };
}

/// One day in the helm Calendar view — date plus the jobs scheduled
/// for that day (sorted by `scheduledAt` ascending).  Days with no
/// jobs scheduled return `jobs: []` so the helm renders a calendar
/// grid without missing-key checks.  D-O5.followup-3.
class CalendarDay {
  /// ISO-8601 date (YYYY-MM-DD).
  final String date;
  final List<Job> jobs;

  const CalendarDay({required this.date, required this.jobs});
}

/// Three operator-action buckets surfaced by `jobs.find_attention`
/// — `pendingQuote` (state=lead → operator should respond with a
/// quote), `pendingSchedule` (state=quoted → operator schedules),
/// `pendingInvoice` (state=completed → operator invoices).  Jobs in
/// non-action states (scheduled, in_progress, invoiced, paid, closed)
/// are deliberately excluded.  D-O5.followup-3.
class AttentionFeed {
  final List<Job> pendingQuote;
  final List<Job> pendingSchedule;
  final List<Job> pendingInvoice;
  final int total;

  const AttentionFeed({
    required this.pendingQuote,
    required this.pendingSchedule,
    required this.pendingInvoice,
    required this.total,
  });

  /// Convenience: total across all three categories.  Mirrors the
  /// dispatcher payload's `total` field — the Semantos Brain side computes it,
  /// we trust it; this getter doubles up so the helm doesn't need to
  /// recompute the sum locally.
  bool get isEmpty => total == 0;
}

/// D-O5.followup-4 — cache-invalidation event surfaced by
/// [JobsRepository] when the live stream delivers a `job.transitioned`
/// notification.  Screens (`JobListScreen`, `JobDetailScreen`)
/// subscribe to [JobsRepository.cacheEvents] and refresh themselves
/// on each emission.
class JobsCacheEvent {
  /// The job id that changed.  Empty when the upstream payload didn't
  /// carry an id (defensive; the Semantos Brain emit always populates it).
  final String jobId;

  /// The from/to states (best-effort; empty when the upstream
  /// payload's shape didn't match).  Screens use these to render an
  /// inline transition banner if they want — no current callsite
  /// requires them, but they're free-of-charge alongside the cache
  /// invalidation signal.
  final String fromState;
  final String toState;

  const JobsCacheEvent({
    required this.jobId,
    this.fromState = '',
    this.toState = '',
  });
}

/// Repository over the REPL — the helm screens call this rather than
/// hand-parsing the REPL response themselves.
///
/// W1.1 — cache is now backed by [HatEntityRepository] (SQLite
/// `hat_entity_cache` table) instead of the old file-based JobsCache.
/// The oddjobz domain_flag is 0x000101 (257).
///
/// D-O5.followup-4 — when a [HelmEventStream] is supplied, the repo
/// subscribes to `job.transitioned` notifications and surfaces them
/// as [JobsCacheEvent]s on [cacheEvents].  Screens listen to the
/// cache event stream and refresh themselves on each emission.  When
/// the stream is null (tests, pull-only mode) the cacheEvents stream
/// is silent — no emissions, ever — and the repo behaves as it did
/// pre-followup-4.
class JobsRepository {
  final ReplClient _repl;
  HatEntityRepository? _entityCache;
  final StreamController<JobsCacheEvent> _cacheCtl =
      StreamController<JobsCacheEvent>.broadcast();
  StreamSubscription<HelmEvent>? _eventSub;

  /// Oddjobz domain flag (0x000101 = 257).
  static const int oddjobzDomainFlag = 0x000101;

  JobsRepository(
    this._repl, {
    HelmEventStream? eventStream,
    HatEntityRepository? entityCache,
  }) : _entityCache = entityCache {
    if (eventStream != null) {
      _eventSub = eventStream.events.listen(_onHelmEvent);
    }
  }

  /// W1.1 — wire in the cache after async DB open.  Called by
  /// HomeScreen once [HatEntityRepository.fromDatabase] resolves so
  /// subsequent findJobs() calls write through to the cache and
  /// loadCached() returns persisted rows on the next cold-start.
  void setEntityCache(HatEntityRepository cache) {
    _entityCache = cache;
  }

  /// Stream of cache-invalidation events the helm screens listen to.
  /// Broadcast — multiple screens can subscribe simultaneously.
  Stream<JobsCacheEvent> get cacheEvents => _cacheCtl.stream;

  /// Release the event subscription + close the cache stream.  Call
  /// on logout / unpair so the next pairing starts with a clean
  /// repository.
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    if (!_cacheCtl.isClosed) await _cacheCtl.close();
  }

  void _onHelmEvent(HelmEvent event) {
    if (event.type != 'job.transitioned') return;
    final id = event.data['id'];
    if (id is! String || id.isEmpty) return;
    final from = event.data['from'];
    final to = event.data['to'];
    _cacheCtl.add(JobsCacheEvent(
      jobId: id,
      fromState: from is String ? from : '',
      toState: to is String ? to : '',
    ));
  }

  /// Return the last cached jobs from the SQLite hat_entity_cache table,
  /// or null when no [HatEntityRepository] was supplied.
  /// Cold-start reads from SQLite directly.
  Future<List<Job>?> loadCached() async {
    final cache = _entityCache;
    if (cache == null) return null;
    try {
      final rows =
          await cache.queryAll(domainFlag: oddjobzDomainFlag);
      if (rows.isEmpty) return null;
      return rows
          .map((r) {
            try {
              return parseJobOne(r.entityJson);
            } catch (_) {
              return null;
            }
          })
          .whereType<Job>()
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Fetch the operator's open jobs. Throws ReplUnauthorisedError on
  /// 401 (the helm screen catches that and transitions to the
  /// pairing screen); other typed exceptions propagate verbatim so
  /// the helm screen can surface them in-line.  On success the result
  /// is written through to the [HatEntityRepository] (fire-and-forget).
  Future<List<Job>> findJobs() async {
    final resp = await _repl.send('find jobs');
    final jobs = parseJobs(resp.result);
    _persistJobs(jobs); // fire-and-forget; DB failure is non-fatal
    return jobs;
  }

  /// Persist [jobs] to the hat_entity_cache SQLite table.
  void _persistJobs(List<Job> jobs) {
    final cache = _entityCache;
    if (cache == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    Future(() async {
      for (final job in jobs) {
        try {
          await cache.upsert(HatEntity(
            id: job.id,
            domainFlag: oddjobzDomainFlag,
            state: job.state,
            scheduledAt: job.scheduledAt,
            entityJson: jsonEncode(job.toJson()),
            updatedAt: now,
          ));
        } catch (_) {
          // Non-fatal — cache miss on next cold-start is safe.
        }
      }
    });
  }

  /// Fetch a single job by id via the typed `jobs.find_by_id`
  /// dispatcher resource — the JSON branch always wins.  Returns null
  /// when the Semantos Brain side emits the typed `{error: "not_found", id}`
  /// envelope (handler-level not_found, NOT a transport error) or
  /// when the response isn't parseable.  Pre-D-O5.followup-3 this was
  /// a stopgap filter over the findJobs() result; the typed path
  /// avoids the round-trip-and-scan and gives the dispatcher a clean
  /// audit-line per detail-screen open.
  Future<Job?> findJob(String id) async {
    final resp = await _repl.send('find job $id');
    return parseJobOne(resp.result);
  }

  /// Fetch the per-day calendar grid for [from, to].  Both bounds are
  /// optional; when omitted, the Semantos Brain side defaults to the current
  /// week (Monday → Monday + 7).  Each [CalendarDay] in the returned
  /// list represents one day in [from, to] inclusive (so days with no
  /// jobs are present with empty `jobs` arrays — the helm renders a
  /// grid).  D-O5.followup-3.
  Future<List<CalendarDay>> findCalendar({DateTime? from, DateTime? to}) async {
    final args = <String>[];
    if (from != null) args.add('--from ${_isoDate(from)}');
    if (to != null) args.add('--to ${_isoDate(to)}');
    final cmd = args.isEmpty ? 'find calendar' : 'find calendar ${args.join(' ')}';
    final resp = await _repl.send(cmd);
    return parseCalendar(resp.result);
  }

  /// Fetch the attention feed — three buckets of jobs needing
  /// operator action (lead/quoted/completed) plus a total.
  /// D-O5.followup-3.
  Future<AttentionFeed> findAttention() async {
    final resp = await _repl.send('find attention');
    return parseAttention(resp.result);
  }

  /// D-O5 followup-1 — drive a job through the canonical §O4 FSM via
  /// the typed `jobs.transition` dispatcher resource.  Returns either
  /// the new [Job] (post-transition shape) or a [JobTransitionError]
  /// when the Semantos Brain side rejects with a typed body.  Throws
  /// [ReplUnauthorisedError] on transport-level 401 (helm pivots to
  /// the pairing screen); other transport errors propagate verbatim.
  ///
  /// The seven typed wrappers below ([quoteJob] / [scheduleJob] / …)
  /// pre-fill `toState` + `principalKind` per the canonical FSM table
  /// — operators interact with those, not this generic method.
  Future<JobTransitionResult> transitionJob({
    required String id,
    required String toState,
    String? presentedCap,
    required String principalKind,
    String? scheduledAt,
  }) async {
    // The REPL's generic `transition job <id> <to_state> ...` verb
    // takes flag-style args; the typed wrappers below route through
    // the operator-readable verbs (`quote job <id>`, `schedule job
    // <id> [--at X]`, etc.).  This method goes through the generic
    // fallback so callers can drive cancellation / rejection rows the
    // FSM table may grow later without an SDK churn.
    final args = StringBuffer('transition job $id $toState')
      ..write(' --principal $principalKind');
    if (presentedCap != null) args.write(' --cap $presentedCap');
    // scheduledAt is supported by the per-row `schedule job` verb;
    // the generic verb doesn't take it as a flag.  Callers that need
    // to set scheduled_at use [scheduleJob] directly.
    final resp = await _repl.send(args.toString());
    return parseJobTransitionResult(resp.result);
  }

  Future<JobTransitionResult> quoteJob(String id) async {
    final resp = await _repl.send('quote job $id');
    return parseJobTransitionResult(resp.result);
  }

  Future<JobTransitionResult> scheduleJob(String id, {DateTime? at}) async {
    final cmd = at == null
        ? 'schedule job $id'
        : 'schedule job $id --at ${_isoTimestamp(at)}';
    final resp = await _repl.send(cmd);
    return parseJobTransitionResult(resp.result);
  }

  Future<JobTransitionResult> startJob(String id) async {
    final resp = await _repl.send('start job $id');
    return parseJobTransitionResult(resp.result);
  }

  Future<JobTransitionResult> completeJob(String id) async {
    final resp = await _repl.send('complete job $id');
    return parseJobTransitionResult(resp.result);
  }

  /// Transition job to invoiced state.
  ///
  /// P3d: when [totalCents] is non-null it is appended to the REPL command
  /// so the brain can store the invoice total alongside the FSM transition.
  Future<JobTransitionResult> invoiceJob(String id, {int? totalCents}) async {
    final cmd = totalCents != null && totalCents > 0
        ? 'invoice job $id total_cents $totalCents'
        : 'invoice job $id';
    final resp = await _repl.send(cmd);
    return parseJobTransitionResult(resp.result);
  }

  Future<JobTransitionResult> markJobPaid(String id) async {
    final resp = await _repl.send('mark job paid $id');
    return parseJobTransitionResult(resp.result);
  }

  Future<JobTransitionResult> closeJob(String id) async {
    final resp = await _repl.send('close job $id');
    return parseJobTransitionResult(resp.result);
  }
}

String _isoTimestamp(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}T'
      '${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

/// D-O5 followup-1 — typed result shape for `jobs.transition`.  The
/// brain dispatcher returns one of three JSON bodies:
///
///   • Success: the new Job (`{id, customer_name, state, scheduled_at,
///     created_at}`).  We surface this as [JobTransitionSuccess].
///   • Idempotent: `{status: "already_in_state", job: {...}}` — the
///     job was already at to_state.  Surfaced as [JobTransitionAlreadyInState];
///     the helm treats this as a no-op success.
///   • Error: `{error: <kind>, from, to, cap_required}` — surfaced
///     as [JobTransitionError]; helm shows a snackbar.
sealed class JobTransitionResult {
  const JobTransitionResult();
}

class JobTransitionSuccess extends JobTransitionResult {
  final Job job;
  const JobTransitionSuccess(this.job);
}

class JobTransitionAlreadyInState extends JobTransitionResult {
  final Job job;
  const JobTransitionAlreadyInState(this.job);
}

class JobTransitionError extends JobTransitionResult {
  /// One of: `wrong_cap | not_reachable | wrong_principal |
  /// unknown_state | not_found`.  Free-form so a future kind doesn't
  /// require a Dart enum bump.
  final String kind;
  final String from;
  final String to;
  final String? capRequired;

  const JobTransitionError({
    required this.kind,
    required this.from,
    required this.to,
    this.capRequired,
  });

  /// Operator-readable summary the helm renders in a snackbar.
  String get message {
    switch (kind) {
      case 'wrong_cap':
        return 'This action requires capability '
            '${capRequired ?? "(unknown)"}.';
      case 'not_reachable':
        return 'Cannot transition $from to $to (not in the FSM table).';
      case 'wrong_principal':
        return 'This transition requires a different signing principal.';
      case 'unknown_state':
        return 'Unknown target state "$to".';
      case 'not_found':
        return 'Job no longer exists.';
      default:
        return 'Transition failed: $kind';
    }
  }
}

/// Parse the Semantos Brain `jobs.transition` response into a [JobTransitionResult].
/// On a parse-level failure (the response isn't JSON or is shaped
/// unexpectedly) we synthesize a generic [JobTransitionError] with
/// `kind = 'parse_error'` so the helm always has something to show.
JobTransitionResult parseJobTransitionResult(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return const JobTransitionError(
      kind: 'parse_error',
      from: '',
      to: '',
    );
  }
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      // Idempotent already_in_state body.
      if (parsed['status'] == 'already_in_state' &&
          parsed['job'] is Map<String, dynamic>) {
        return JobTransitionAlreadyInState(
          _jobFromTransitionBody(parsed['job'] as Map<String, dynamic>),
        );
      }
      // Typed error body.
      if (parsed['error'] is String) {
        return JobTransitionError(
          kind: parsed['error'] as String,
          from: (parsed['from'] ?? '').toString(),
          to: (parsed['to'] ?? '').toString(),
          capRequired: parsed['cap_required'] is String
              ? parsed['cap_required'] as String
              : null,
        );
      }
      // Success body — bare Job shape.
      if (parsed['id'] != null && parsed['state'] != null) {
        return JobTransitionSuccess(_jobFromTransitionBody(parsed));
      }
    }
  } catch (_) {
    // Fall through to parse_error.
  }
  return const JobTransitionError(
    kind: 'parse_error',
    from: '',
    to: '',
  );
}

// Transition responses use the same row shape as list responses —
// route through the shared decoder so v2 fields carry through after
// a transition without an extra round-trip.
Job _jobFromTransitionBody(Map<String, dynamic> row) => _jobFromJsonRow(row);

String _isoDate(DateTime d) {
  // Render YYYY-MM-DD in UTC — mirrors the Semantos Brain-side validator
  // (jobs_handler.zig::isIsoDate).  We deliberately strip the
  // time-of-day bits; the Semantos Brain handler keys off the date prefix.
  final u = d.toUtc();
  final y = u.year.toString().padLeft(4, '0');
  final m = u.month.toString().padLeft(2, '0');
  final day = u.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Parse the REPL's free-text `find jobs` output into [Job] rows.
///
/// Mirrors the desktop helm's parser in
/// `apps/loom-svelte/src/views/JobList.svelte` exactly:
///   1. JSON if the trimmed result starts with `[` or `{` — return
///      typed rows;
///   2. otherwise, tab-separated lines (`# id\tcustomer\tstate\tscheduled_at`,
///      header line skipped);
///   3. otherwise, the empty list.
List<Job> parseJobs(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];

  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    try {
      final parsed = json.decode(trimmed);
      if (parsed is List) {
        return parsed
            .whereType<Map<String, dynamic>>()
            .map(_jobFromJsonRow)
            .toList();
      }
      // D-DOG.1.0c Phase 3 F.1 — `oddjobz.find_jobs_*` and
      // `oddjobz.list_*` query verbs wrap the array in a `{jobs: [...]}`
      // envelope.  The JobList screen calls those over WSS rather
      // than the REPL, but parseJobs is also a path the helm uses to
      // re-decode cached snapshots written through `JobsCache`, so we
      // peel the envelope here for forward-compat.
      if (parsed is Map<String, dynamic>) {
        final jobs = parsed['jobs'];
        if (jobs is List) {
          return jobs
              .whereType<Map<String, dynamic>>()
              .map(_jobFromJsonRow)
              .toList();
        }
      }
    } catch (_) {
      // Fall through to TSV.
    }
  }

  // TSV / line fallback — REPL's text emit is line-based.
  final lines = trimmed
      .split('\n')
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  return lines
      .map((line) {
        final cols = line.split('\t');
        if (cols.length < 4) return null;
        return Job(
          id: cols[0],
          customerName: cols[1],
          state: cols[2],
          scheduledAt: cols[3],
        );
      })
      .whereType<Job>()
      .toList();
}

/// Parse the typed `jobs.find_calendar` response into a list of
/// [CalendarDay].  The brain dispatcher emits a JSON array
/// `[{date, jobs:[Job, ...]}, ...]`; days with no jobs scheduled
/// still appear with empty `jobs` arrays so the helm renders a
/// calendar grid without missing-key checks.  Falls back to the
/// empty list on parse failure / non-JSON input — same posture as
/// `parseJobs`.  D-O5.followup-3.
List<CalendarDay> parseCalendar(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  if (!(trimmed.startsWith('[') || trimmed.startsWith('{'))) return const [];
  try {
    final parsed = json.decode(trimmed);
    if (parsed is List) {
      return parsed.whereType<Map<String, dynamic>>().map((row) {
        final jobsRaw = row['jobs'];
        final jobs = (jobsRaw is List)
            ? jobsRaw
                .whereType<Map<String, dynamic>>()
                .map(_jobFromCalendarRow)
                .toList()
            : <Job>[];
        return CalendarDay(
          date: (row['date'] ?? '').toString(),
          jobs: jobs,
        );
      }).toList();
    }
  } catch (_) {
    // Fall through to empty.
  }
  return const [];
}

/// Parse the typed `jobs.find_attention` response into an
/// [AttentionFeed].  The brain dispatcher emits an object with three
/// keyed arrays (`pending_quote`, `pending_schedule`,
/// `pending_invoice`) plus a `total` int.  Returns an empty feed on
/// parse failure / non-JSON input.  D-O5.followup-3.
AttentionFeed parseAttention(String text) {
  final trimmed = text.trim();
  const empty = AttentionFeed(
    pendingQuote: [],
    pendingSchedule: [],
    pendingInvoice: [],
    total: 0,
  );
  if (trimmed.isEmpty) return empty;
  if (!trimmed.startsWith('{')) return empty;
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      final pq = _extractAttentionJobs(parsed['pending_quote']);
      final ps = _extractAttentionJobs(parsed['pending_schedule']);
      final pi = _extractAttentionJobs(parsed['pending_invoice']);
      final totalRaw = parsed['total'];
      final total = totalRaw is int
          ? totalRaw
          : (totalRaw is num
              ? totalRaw.toInt()
              : pq.length + ps.length + pi.length);
      return AttentionFeed(
        pendingQuote: pq,
        pendingSchedule: ps,
        pendingInvoice: pi,
        total: total,
      );
    }
  } catch (_) {
    // Fall through to empty.
  }
  return empty;
}

List<Job> _extractAttentionJobs(dynamic raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map<String, dynamic>>().map(_jobFromCalendarRow).toList();
}

Job _jobFromCalendarRow(Map<String, dynamic> row) => _jobFromJsonRow(row);

/// D-DOG.1.0c Phase 3 F.1 — single forward-compat decoder shared by
/// every JSON-shaped Job entry-point ([parseJobs], [parseJobOne],
/// [parseCalendar], [parseAttention]).  v1 rows produce a Job with
/// every v2 field null; v2 rows populate the v2 fields per the
/// `oddjobz_query_handler::writeJob` wire shape.  Unknown / null v2
/// fields don't crash — they just stay null.
Job _jobFromJsonRow(Map<String, dynamic> row) {
  // Customer refs — emitted as null on v1 rows and as a (possibly
  // empty) array on v2 rows.  We treat anything that isn't a List
  // as v1-shaped.
  List<JobCustomerRef>? customerRefs;
  final cr = row['customerRefs'];
  if (cr is List) {
    customerRefs = cr
        .whereType<Map<String, dynamic>>()
        .map((m) => JobCustomerRef(
              cellId: (m['cellId'] ?? '').toString(),
              role: (m['role'] ?? '').toString(),
              primary: m['primary'] == true,
              name: (m['name'] ?? '').toString(),
              phone: (m['phone'] ?? '').toString(),
            ))
        .toList();
  }

  // siteRef — null on v1; 64-hex string on v2.  We don't validate
  // length here; the renderer just treats null as v1.
  final siteRefRaw = row['siteRef'];
  final siteRef = siteRefRaw is String && siteRefRaw.isNotEmpty
      ? siteRefRaw
      : null;

  final propertyKeyRaw = row['propertyKey'];
  final propertyKey = propertyKeyRaw is String && propertyKeyRaw.isNotEmpty
      ? propertyKeyRaw
      : null;

  final dueDateRaw = row['dueDate'];
  final dueDate = dueDateRaw is String && dueDateRaw.isNotEmpty
      ? dueDateRaw
      : null;

  final workOrderRaw = row['workOrderNumber'];
  final workOrderNumber = workOrderRaw is String && workOrderRaw.isNotEmpty
      ? workOrderRaw
      : null;

  // RM-125 — WO issuance date + joined services list.
  final issuanceRaw = row['issuanceDate'];
  final issuanceDate = issuanceRaw is String && issuanceRaw.isNotEmpty
      ? issuanceRaw
      : null;
  final servicesRaw = row['services'];
  final services = servicesRaw is String && servicesRaw.isNotEmpty
      ? servicesRaw
      : null;

  final hasPhotosRaw = row['hasPhotos'];
  final hasPhotos = hasPhotosRaw is bool ? hasPhotosRaw : null;

  final photoCountRaw = row['photoCount'];
  final photoCount = photoCountRaw is int
      ? photoCountRaw
      : (photoCountRaw is num ? photoCountRaw.toInt() : null);

  // propertyAddress is NOT emitted by the Semantos Brain side (the wire shape
  // links to a Site cell via siteRef; the helm enriches in-process).
  // The field on Job is reserved for the post-enrichment value the
  // JobList writes via [Job.withPropertyAddress] after listSites().
  final propertyAddressRaw = row['propertyAddress'];
  final propertyAddress =
      propertyAddressRaw is String && propertyAddressRaw.isNotEmpty
          ? propertyAddressRaw
          : null;

  // RM-121 — work description (ingest `summary`), emitted by the
  // brain's writeJob. Null/absent on rows without one.
  final descriptionRaw = row['description'];
  final description = descriptionRaw is String && descriptionRaw.isNotEmpty
      ? descriptionRaw
      : null;

  // D-DOG.1.0c Phase 5 G.2 — when the Semantos Brain side adds the legacy-
  // unsigned marker join (a follow-up to the TS verb), it'll emit
  // `legacy_unsigned: true` on un-migrated v1 rows.  We read it
  // forward-compat — absent or non-bool defaults to false so the
  // existing wire shape parses identically.
  final legacyUnsignedRaw = row['legacy_unsigned'];
  final legacyUnsigned = legacyUnsignedRaw is bool ? legacyUnsignedRaw : false;

  // cellId — 64-hex LMDB cell hash; emitted by the brain's
  // jobs_handler.zig writeJob for v2 (entity-anchored) rows.  Used as
  // the `entityRef` query parameter for the conversation turns endpoint.
  // Null on v1 legacy rows.
  final cellIdRaw = row['cellId'];
  final cellId = cellIdRaw is String && cellIdRaw.isNotEmpty
      ? cellIdRaw
      : null;

  return Job(
    id: (row['id'] ?? '').toString(),
    customerName: (row['customer_name'] ?? row['customer'] ?? '').toString(),
    state: (row['state'] ?? '').toString(),
    scheduledAt: (row['scheduled_at'] ?? '').toString(),
    siteRef: siteRef,
    propertyAddress: propertyAddress,
    description: description,
    propertyKey: propertyKey,
    customerRefs: customerRefs,
    dueDateRaw: dueDate,
    workOrderNumber: workOrderNumber,
    issuanceDate: issuanceDate,
    services: services,
    hasPhotos: hasPhotos,
    photoCount: photoCount,
    legacyUnsigned: legacyUnsigned,
    cellId: cellId,
  );
}

/// Parse a single-job response from the typed `jobs.find_by_id`
/// resource (D-O5.followup-3 polish).  Returns null on the typed
/// `{"error":"not_found", ...}` envelope or any parse failure — the
/// caller surfaces a "no longer exists" message.  Mirrors the shape
/// of `parseCustomerOne`.
Job? parseJobOne(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return null;
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      // Typed not_found envelope — handler returns this when the id
      // doesn't exist (200 with the typed body).
      if (parsed['error'] == 'not_found') return null;
      // D-DOG.1.0c Phase 3 F.1 — `oddjobz.get_job` wraps the row in
      // `{job: ... | null}`.  Peel the envelope when present so the
      // helm can use the same parser regardless of which transport
      // emitted the body.
      final inner = parsed['job'];
      if (inner is Map<String, dynamic>) {
        return _jobFromJsonRow(inner);
      }
      if (inner == null && parsed.containsKey('job')) {
        // Explicit `{job: null}` from the Semantos Brain-side miss path.
        return null;
      }
      if (parsed['id'] == null) return null;
      return _jobFromJsonRow(parsed);
    }
  } catch (_) {
    // Fall through to null.
  }
  return null;
}

```
