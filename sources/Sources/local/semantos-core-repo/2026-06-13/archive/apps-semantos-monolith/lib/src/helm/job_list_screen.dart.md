---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/job_list_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.893498+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/job_list_screen.dart

```dart
// D-O5m — JobList screen (mobile).
//
// View-shape mirror of `apps/loom-svelte/src/views/JobList.svelte`.
// Calls the bearer-gated REPL (`find jobs`) and renders the result
// as a Material list. Tapping a row pushes the JobDetail screen.
//
// D-O5.followup-4 — subscribes to JobsRepository.cacheEvents and
// reloads the list whenever the brain emits a `job.transitioned`
// notification (operator A's transition shows up on operator B's
// helm without a manual refresh).
//
// Offline read cache — on mount the screen first loads any cached
// snapshot from [JobsCache] (instant display, no spinner), then
// attempts a fresh fetch in the background.  When offline with a
// cached snapshot the list stays visible with a stale-data banner;
// when offline with no cache the screen shows the usual error + retry.
//
// D-DOG.1.0c Phase 3 F.1 — graph-aware row rendering.  Each row now
// shows (when available): property address (resolved from the job's
// siteRef via a single bulk `oddjobz.list_sites()` call), primary
// customer (resolved from the job's customerRefs[primary] entry via
// a single bulk `oddjobz.list_customers()` call), due date
// ("Due 24 Mar" relative format), and a camera icon when hasPhotos.
// v1 rows degrade gracefully — the v1 customer-name string still
// renders, and the unavailable fields show "—".  The two bulk calls
// run in parallel with the REPL `find jobs` fetch so list-time
// stays at one round-trip's wall-clock when the WSS is responsive.
// When the WSS isn't available (offline, paired-but-unconnected,
// reconnect-in-progress) the enrichment silently falls back to the
// un-enriched row shape — the list still renders.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/attention_service.dart';
import '../repl/invoices_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/oddjobz_query_client.dart';
import '../repl/quotes_repository.dart';
import '../repl/repl_errors.dart';
import '../repl/visits_repository.dart';
import 'attachment_screen.dart';
import 'customer_screen.dart';
import 'job_detail_screen.dart';
import 'job_list_row.dart';

class JobListScreen extends StatefulWidget {
  final JobsRepository jobs;
  final Future<void> Function() onUnauthorised;

  final VisitsRepository? visits;
  final QuotesRepository? quotes;
  final InvoicesRepository? invoices;

  /// D-DOG.1.0c Phase 3 F.1 — optional graph-aware query client used
  /// for the bulk-fetch enrichment of site addresses + customer
  /// display names.  Null is acceptable: when the brain isn't
  /// reachable over WSS (paired-but-not-connected, the Semantos Brain side
  /// pre-dates Phase 2B.3, etc.) the screen renders un-enriched
  /// rows.  Wave 2 site-pivot / customer-pivot screens will require
  /// it; F.1 keeps it optional for backward-compat with existing
  /// HomeScreen wiring.
  final OddjobzQueryClient? oddjobzQuery;

  /// Tier 2P Phase E.1 — optional attention service used to surface
  /// inline lane chip, score dot, and last-message snippet on each
  /// row.  When null, rows render exactly as before E.1 (backward-
  /// compatible).  When non-null, the screen subscribes to the
  /// signals stream and indexes the latest message per job.
  final AttentionService? attention;

  const JobListScreen({
    super.key,
    required this.jobs,
    required this.onUnauthorised,
    this.visits,
    this.quotes,
    this.invoices,
    this.oddjobzQuery,
    this.attention,
  });

  @override
  State<JobListScreen> createState() => _JobListScreenState();
}

class _JobListScreenState extends State<JobListScreen> {
  bool _loading = true;
  String? _error;
  List<Job> _rows = const [];
  bool _showStaleBanner = false;
  DateTime? _cachedAt;
  StreamSubscription<JobsCacheEvent>? _cacheSub;

  /// D-DOG.1.0c Phase 3 F.1 — primary-customer lookup map keyed by
  /// the v2 customer cellId (64-hex).  Built once per [_load] from
  /// the bulk `oddjobz.list_customers()` response.  v1 rows that
  /// lack a cellId are also indexed by their legacy id for
  /// defensive-fallback (the two id spaces don't collide because v1
  /// ids are UUID-shaped and v2 cellIds are 64-hex).  Missing keys
  /// resolve to null at render-time and the row falls back to its
  /// existing v1 customerName string.
  Map<String, OddjobzCustomer> _customersByRef = const {};

  // ── Tier 2P Phase E.1 — attention data ──────────────────────────────

  /// Attention signals indexed by job cellId (signal.ref for job-kind
  /// signals).  Updated on every signals stream emission.
  Map<String, OddjobzAttentionSignal> _signalsByJobRef = const {};

  /// Latest message patch per job, keyed by job cellId.
  /// Built by matching dispatch decisions' sourcePatchId → message.
  Map<String, OddjobzMessagePatch> _lastMessageByJobRef = const {};

  /// Primary dispatch decision per job (primaryTargetType == job),
  /// keyed by job cellId.
  Map<String, OddjobzDispatchDecision> _dispatchByJobRef = const {};

  StreamSubscription<List<OddjobzAttentionSignal>>? _signalsSub;

  @override
  void initState() {
    super.initState();
    _loadWithCache();
    _cacheSub = widget.jobs.cacheEvents.listen((_) {
      if (!mounted) return;
      // Live event means we're online — refresh without the stale banner.
      _load();
    });
    _subscribeToAttention();
  }

  /// Subscribe to the attention service signals stream.  Idempotent;
  /// safe to call when attention == null (no-op in that case).
  void _subscribeToAttention() {
    final svc = widget.attention;
    if (svc == null) return;
    _signalsSub = svc.signals.listen((signals) {
      if (!mounted) return;
      _rebuildAttentionMaps(signals, svc);
    });
  }

  /// Rebuild the three attention index maps from the latest signals
  /// list.  We also reach into the service's internal cached state
  /// via its public stream indirectly — the service already published
  /// dispatches and messages when it emitted the signals we're seeing,
  /// but we can't access those lists directly.  Instead we use a
  /// pragmatic approach: for each job-kind signal, the signal.ref IS
  /// the job cellId; for dispatch-kind signals we look at the raw map.
  void _rebuildAttentionMaps(
    List<OddjobzAttentionSignal> signals,
    AttentionService svc,
  ) {
    final newSignals = <String, OddjobzAttentionSignal>{};
    final newDispatches = <String, OddjobzDispatchDecision>{};

    for (final s in signals) {
      switch (s.kind) {
        case OddjobzAttentionKind.job:
          // signal.ref == job cellId for job-kind signals.
          final existing = newSignals[s.ref];
          if (existing == null || s.score > existing.score) {
            newSignals[s.ref] = s;
          }
        case OddjobzAttentionKind.dispatch:
          // raw contains the dispatch decision; primaryTarget.ref ==
          // job cellId when target type is job.
          try {
            final d = OddjobzDispatchDecision.fromJson(
              Map<String, dynamic>.from(s.raw),
            );
            if (d.primaryTarget.type == OddjobzDispatchTargetType.job &&
                d.primaryTarget.ref.isNotEmpty) {
              final existing = newDispatches[d.primaryTarget.ref];
              if (existing == null ||
                  d.timestamp > existing.timestamp) {
                newDispatches[d.primaryTarget.ref] = d;
              }
            }
          } catch (_) {
            // Malformed raw — skip silently.
          }
        case OddjobzAttentionKind.message:
          // Message-kind signals don't directly tell us the job ref;
          // we'd need the dispatch → job mapping.  The full message
          // index is rebuilt via _rebuildMessageIndex when attention
          // refreshes — handled separately below.
          break;
      }
    }

    // Message index: for each dispatch we know, look up the latest
    // message patch from the stream's last emitted value.
    // We don't have direct access to the internal message buffer, but
    // we can listen once to the per-job streams via the service API.
    // For now, leave message lookup to the signal raw data when available.
    // The per-job stream approach (messagesForJob) is used by E.2
    // JobThreadScreen; here we do a best-effort extraction from raw.
    final newMessages = <String, OddjobzMessagePatch>{};
    for (final entry in newDispatches.entries) {
      final jobRef = entry.key;
      final dispatch = entry.value;
      // Try to get the latest message for this job from dispatch-kind
      // signals whose ref matches the sourcePatchId.
      for (final s in signals) {
        if (s.kind == OddjobzAttentionKind.message) {
          try {
            final patch = OddjobzMessagePatch.fromJson(
              Map<String, dynamic>.from(s.raw),
            );
            if (patch.patchId == dispatch.sourcePatchId) {
              final existing = newMessages[jobRef];
              if (existing == null ||
                  patch.timestamp > existing.timestamp) {
                newMessages[jobRef] = patch;
              }
            }
          } catch (_) {
            // Skip malformed.
          }
        }
      }
    }

    setState(() {
      _signalsByJobRef = newSignals;
      _dispatchByJobRef = newDispatches;
      _lastMessageByJobRef = newMessages;
    });
  }

  @override
  void dispose() {
    _signalsSub?.cancel();
    _cacheSub?.cancel();
    super.dispose();
  }

  /// Phase 1: show cached snapshot immediately (no spinner).
  /// Phase 2: refresh from brain in the background.
  ///
  /// W1.1 — loadCached() now returns List<Job>? from the SQLite
  /// hat_entity_cache table (no savedAt; stale banner uses mount time).
  Future<void> _loadWithCache() async {
    final cached = await widget.jobs.loadCached();
    if (cached != null && mounted) {
      setState(() {
        _rows = cached;
        _loading = false;
        _showStaleBanner = true;
        _cachedAt = DateTime.now();
      });
    }
    await _load();
  }

  Future<void> _load() async {
    // Only show the full-screen spinner when we have nothing to display.
    if (_rows.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // D-DOG.1.0c Phase 3 F.1 — fan out three independent reads in
      // parallel: the REPL `find jobs` (the truth for the row list)
      // PLUS the two bulk-fetch enrichment calls (sites + customers).
      // The enrichment calls are best-effort: a failure swallows
      // back to an empty map and the rows render un-enriched.  The
      // jobs call's exceptions still propagate verbatim because that
      // one IS load-bearing.
      final futures = await Future.wait([
        widget.jobs.findJobs(),
        _fetchSitesMap(),
        _fetchCustomersMap(),
      ]);
      final jobs = futures[0] as List<Job>;
      final sitesByRef = futures[1] as Map<String, OddjobzSite>;
      final customersByRef = futures[2] as Map<String, OddjobzCustomer>;
      // Enrich each v2 row with its site's fullAddress.  v1 rows
      // (siteRef == null) pass through untouched.
      final enriched = jobs.map((j) {
        final ref = j.siteRef;
        if (ref == null) return j;
        final site = sitesByRef[ref];
        if (site == null) return j;
        return j.withPropertyAddress(site.fullAddress);
      }).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _rows = enriched;
        _customersByRef = customersByRef;
        _loading = false;
        _error = null;
        _showStaleBanner = false;
        _cachedAt = null;
      });
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      if (_rows.isNotEmpty) {
        // Cache is displayed — suppress the error, just stop the spinner.
        setState(() => _loading = false);
      } else {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Bulk-fetch every persisted Site cell, key by cellId.  Best-
  /// effort: a Semantos Brain-side error / WSS-not-connected returns empty
  /// (no enrichment) without breaking the list load.  The N+1
  /// alternative (one get_site per row) would round-trip through
  /// WSS for every job and is reserved for the F.2 site-pivot
  /// screen where the operator drilled down to a specific site.
  Future<Map<String, OddjobzSite>> _fetchSitesMap() async {
    final client = widget.oddjobzQuery;
    if (client == null) return const {};
    try {
      final list = await client.listSites();
      return {for (final s in list) s.cellId: s};
    } catch (_) {
      // Enrichment is non-load-bearing — swallow the error and let
      // rows render un-enriched.
      return const {};
    }
  }

  /// Bulk-fetch every persisted Customer (v1 + v2), keyed by EITHER
  /// the v2 cellId (when present, the path the JobList uses) OR the
  /// legacy v1 id (defensive fallback so a v1 row's customerName
  /// resolution doesn't fail when the operator's customerRefs entry
  /// happens to point at a v1 row).  Same best-effort posture as
  /// _fetchSitesMap.
  Future<Map<String, OddjobzCustomer>> _fetchCustomersMap() async {
    final client = widget.oddjobzQuery;
    if (client == null) return const {};
    try {
      final list = await client.listCustomers();
      final out = <String, OddjobzCustomer>{};
      for (final c in list) {
        if (c.cellId != null && c.cellId!.isNotEmpty) {
          out[c.cellId!] = c;
        }
        if (c.id.isNotEmpty) {
          // Don't clobber a v2 entry with a v1 one if the legacy id
          // happens to collide with a v2 cellId (it shouldn't, but
          // be defensive).
          out.putIfAbsent(c.id, () => c);
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text('Failed to load jobs:\n$_error',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final list = _rows.isEmpty
        ? RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: const [
                SizedBox(height: 64),
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No jobs yet. Pull to refresh.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final job = _rows[i];
                return JobListRow(
                  job: job,
                  primaryCustomer: _resolvePrimaryCustomer(job),
                  // D-DOG.1.0c Phase 3 F.3 — customer-name cell tap
                  // pushes the customer-pivot screen.  Wired only
                  // when oddjobzQuery is non-null; otherwise the
                  // cell stays plain text and only the row's onTap
                  // (JobDetailScreen) fires.
                  onCustomerTap: widget.oddjobzQuery == null
                      ? null
                      : (customerRef) {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CustomerScreen(
                              customerRef: customerRef,
                              oddjobzQuery: widget.oddjobzQuery!,
                              jobs: widget.jobs,
                              onUnauthorised: widget.onUnauthorised,
                            ),
                          ));
                        },
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => JobDetailScreen(
                        jobs: widget.jobs,
                        jobId: job.id,
                        initial: job,
                        onUnauthorised: widget.onUnauthorised,
                        visits: widget.visits,
                        quotes: widget.quotes,
                        invoices: widget.invoices,
                      ),
                    ));
                  },
                  // D-DOG.1.0c Phase 3 F.4 — photos icon pivots to the
                  // per-job attachment list.  Only wired when the
                  // job's id is a 64-hex cellId AND we have a query
                  // client; v1 rows leave the icon non-tappable.
                  onPhotosTap: _photosTapHandler(context, job),
                  // Tier 2P Phase E.1 — attention augments.  Only
                  // populated when attention service is wired; null
                  // values keep the row visually unchanged.
                  attentionSignal: _signalsByJobRef[job.id],
                  lastMessagePatch: _lastMessageByJobRef[job.id],
                  primaryDispatch: _dispatchByJobRef[job.id],
                );
              },
            ),
          );

    return Column(
      children: [
        if (_showStaleBanner && _cachedAt != null)
          _StaleBanner(cachedAt: _cachedAt!),
        Expanded(child: list),
      ],
    );
  }

  /// Resolve a Job row's primary customer.  Returns the matching
  /// [OddjobzCustomer] from the bulk-fetched map when the Job is v2
  /// AND has a primary customerRef AND the lookup resolves; null in
  /// every other case.  Render-time falls back to `job.customerName`
  /// when this returns null — the existing v1 surface.
  OddjobzCustomer? _resolvePrimaryCustomer(Job job) {
    final ref = job.primaryCustomerRef;
    if (ref == null) return null;
    return _customersByRef[ref.cellId];
  }

  /// D-DOG.1.0c Phase 3 F.4 — return a photos-icon tap handler that
  /// pushes [AttachmentScreen] for the given job.  Returns null when
  /// the WSS query client isn't wired OR the job's id isn't a v2
  /// 64-hex cellId (v1 rows have UUID-shaped ids the
  /// `find_attachments_for_job` verb rejects).  Mirrors the
  /// equivalent helper in `find_node.dart`.
  VoidCallback? _photosTapHandler(BuildContext context, Job job) {
    final client = widget.oddjobzQuery;
    if (client == null) return null;
    final id = job.id;
    if (id.length != 64 || !_isHexId(id)) return null;
    final title = job.propertyAddress;
    return () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AttachmentScreen(
            jobRef: id,
            title: title,
            oddjobzQuery: client,
          ),
        ));
  }

  /// Cheap lowercase-hex check; see find_node.dart for the rationale
  /// (one regex felt heavyweight here).
  bool _isHexId(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      final ok = (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66);
      if (!ok) return false;
    }
    return true;
  }
}


class _StaleBanner extends StatelessWidget {
  final DateTime cachedAt;
  const _StaleBanner({required this.cachedAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline · Showing data from ${_formatAge(cachedAt)}',
              style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatAge(DateTime savedAt) {
  final diff = DateTime.now().difference(savedAt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  return '${diff.inDays}d ago';
}

```
