---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/site_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.900006+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/site_screen.dart

```dart
// D-DOG.1.0c Phase 3 F.2 — mobile site-pivot screen.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
//            sub-deliverable F.2;
//            apps/oddjobz-mobile/lib/src/repl/oddjobz_query_client.dart —
//            consumes `oddjobz.get_site` + `oddjobz.find_jobs_at_site`
//            wired by F.1 (#378);
//            apps/oddjobz-mobile/lib/src/helm/job_list_row.dart — row
//            widget reused for the per-site jobs list.
//
// Sibling pattern to E.2 (`apps/loom-svelte/src/views/SiteScreen.svelte`)
// but for the operator's mobile surface.  When the operator taps a
// row's address in `_JobsTab` of [FindNode], we pivot here: a single
// site's full address at the top, then every `oddjobz.job.v2` cell
// whose `siteRef` points at this site.  Reverse navigation: tapping a
// job in the list pushes [JobDetailScreen] (same widget JobList uses).
//
// Layout:
//
//   ┌─ AppBar ────────────────────────────────────────────────────┐
//   │  ←  Site                                          [refresh] │
//   ├─────────────────────────────────────────────────────────────┤
//   │  47 Hygieta St, Doonside                                    │
//   │  key #177 · NSW 2767                                        │
//   ├──────────── Jobs at this site (3) ──────────────────────────┤
//   │  ┃ 47 Hygieta St    Sarah Liu (tenant)    Due 24 Mar  📷 3  │
//   │  ┃ 47 Hygieta St    Bob Smith (owner)     Due 12 Apr        │
//   │  …                                                          │
//   └─────────────────────────────────────────────────────────────┘
//
// Best-effort enrichment: `oddjobz.find_jobs_at_site` returns the v2
// jobs; we additionally call `oddjobz.list_customers` once so each
// row's primaryCustomerRef → displayName resolves without an N+1
// fan-out.  A bulk-customers failure degrades to cellId-as-name (same
// fallback JobList uses).  We do NOT call `list_sites` — the screen
// has a single site cell, [getSite] is the right verb.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../repl/conversation_turns_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/oddjobz_query_client.dart';
import '../repl/repl_client.dart';
import '../repl/repl_errors.dart';
import '../repl/visits_repository.dart';
import 'job_detail_screen.dart';
import 'job_list_row.dart';

/// Pivot screen for a single `site.v2` cell.
///
/// Pushes from `_JobsTab` in [FindNode] when the operator taps a
/// JobListRow's address.  Carries enough state to navigate back to
/// per-job detail (via [jobs] + [visits]) and to retry on transient
/// WSS failures (via [onUnauthorised]).
class SiteScreen extends StatefulWidget {
  /// 64-lowercase-hex cellId of the `site.v2` cell to pivot on.  This
  /// is what `Job.siteRef` points at — the caller in `_JobsTab`
  /// passes `job.siteRef!`.  v1 jobs have `siteRef == null` and never
  /// reach this screen (their JobListRow address tap is suppressed).
  final String siteRef;

  /// Graph-aware query client.  Required (the screen has no useful
  /// fallback if WSS isn't open — unlike JobList which still renders
  /// v1 rows un-enriched, SiteScreen is wholly v2).
  final OddjobzQueryClient oddjobzQuery;

  /// JobsRepository — needed only to push [JobDetailScreen] for
  /// per-row tap.  We don't fetch jobs through it; the find-by-site
  /// path is the WSS query verb, not the REPL `find jobs` command.
  final JobsRepository jobs;

  /// VisitsRepository — same reason as [jobs]: passed straight through
  /// to [JobDetailScreen] so the visit timeline tab renders there.
  final VisitsRepository visits;

  /// Surface a 401 from the WSS the same way the rest of the helm
  /// does (HomeScreen renders the pairing screen).  Wired by the
  /// caller in `_JobsTab`.
  final Future<void> Function() onUnauthorised;

  /// Optional — forwarded to [JobDetailScreen] so the Thread tab renders
  /// for jobs accessed via the site pivot.
  final ConversationTurnsRepository? turnsRepository;

  /// Optional — forwarded to [JobDetailScreen] for the send-SMS path.
  final ReplClient? replClient;

  const SiteScreen({
    super.key,
    required this.siteRef,
    required this.oddjobzQuery,
    required this.jobs,
    required this.visits,
    required this.onUnauthorised,
    this.turnsRepository,
    this.replClient,
  });

  @override
  State<SiteScreen> createState() => _SiteScreenState();
}

class _SiteScreenState extends State<SiteScreen> {
  bool _loading = true;
  String? _error;

  /// The site itself.  Null while loading or when the brain returns
  /// the typed `{site: null}` miss envelope (caller passed a bogus
  /// cellId).  The latter renders as a "Site not found" empty state
  /// rather than crashing.
  OddjobzSite? _site;

  /// Jobs whose `siteRef == widget.siteRef`.  Decoded through
  /// [parseJobs] off the `find_jobs_at_site` envelope so the row
  /// objects share the exact same shape as the JobList — letting us
  /// reuse [JobListRow] verbatim.
  List<Job> _rows = const [];

  /// Customer-ref → row map for primary-customer resolution in each
  /// JobListRow.  Same enrichment pattern as `_JobsTab._customersByRef`.
  Map<String, OddjobzCustomer> _customersByRef = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fan three reads in parallel.  All three ride the same WSS so
      // wall-clock is one round-trip when the brain is responsive.
      final futures = await Future.wait<Object?>([
        widget.oddjobzQuery.getSite(widget.siteRef),
        widget.oddjobzQuery.findJobsAtSite(widget.siteRef),
        _fetchCustomersMap(),
      ]);
      final site = futures[0] as OddjobzSite?;
      final rawJobs = futures[1] as List<Map<String, dynamic>>;
      final customersByRef = futures[2] as Map<String, OddjobzCustomer>;

      // Re-shape raw maps → typed Job rows via parseJobs's envelope
      // path so v2 fields (customerRefs, dueDate, photos…) all parse
      // through the same code path as `find jobs`.  Then enrich each
      // row's propertyAddress from the site we just fetched (so
      // JobListRow's title shows the address rather than "—").
      final jobs = parseJobs(json.encode({'jobs': rawJobs}));
      final enriched = site == null
          ? jobs
          : jobs
              .map((j) => j.withPropertyAddress(site.fullAddress))
              .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _site = site;
        _rows = enriched;
        _customersByRef = customersByRef;
      });
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Bulk-fetch every persisted Customer (v1 + v2), keyed by both v2
  /// cellId and legacy v1 string id.  Best-effort — a Semantos Brain-side error
  /// returns empty (no enrichment) without breaking the screen.
  Future<Map<String, OddjobzCustomer>> _fetchCustomersMap() async {
    try {
      final list = await widget.oddjobzQuery.listCustomers();
      final out = <String, OddjobzCustomer>{};
      for (final c in list) {
        if (c.cellId != null && c.cellId!.isNotEmpty) {
          out[c.cellId!] = c;
        }
        if (c.id.isNotEmpty) {
          out.putIfAbsent(c.id, () => c);
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  OddjobzCustomer? _resolvePrimaryCustomer(Job job) {
    final ref = job.primaryCustomerRef;
    if (ref == null) return null;
    return _customersByRef[ref.cellId];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Site'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _rows.isEmpty && _site == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorRetry(error: _error!, onRetry: _load);
    }
    if (_site == null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 96),
            Center(child: Text('Site not found.')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          _SiteHeader(site: _site!),
          _SectionHeader(label: 'Jobs at this site (${_rows.length})'),
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text('No jobs at this site.'),
            )
          else
            ..._rows.map((job) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    JobListRow(
                      job: job,
                      primaryCustomer: _resolvePrimaryCustomer(job),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => JobDetailScreen(
                            jobs: widget.jobs,
                            jobId: job.id,
                            initial: job,
                            onUnauthorised: widget.onUnauthorised,
                            visits: widget.visits,
                            oddjobzQuery: widget.oddjobzQuery,
                            turnsRepository: widget.turnsRepository,
                            replClient: widget.replClient,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 16),
                  ],
                )),
        ],
      ),
    );
  }
}

/// Header card showing the site's full address + secondary line
/// (key + suburb/postcode/state when populated).  Sits above the
/// jobs list; visually distinct from JobListRow so the operator
/// doesn't confuse the pivot subject with one of its rows.
class _SiteHeader extends StatelessWidget {
  final OddjobzSite site;
  const _SiteHeader({required this.site});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryParts = <String>[];
    if (site.keyNumber != null) secondaryParts.add(site.keyNumber!);
    final loc = <String>[
      if (site.suburb != null) site.suburb!,
      if (site.state != null) site.state!,
      if (site.postcode != null) site.postcode!,
    ].join(' ');
    if (loc.isNotEmpty) secondaryParts.add(loc);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            site.fullAddress.isEmpty ? '—' : site.fullAddress,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (secondaryParts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              secondaryParts.join(' · '),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.hintColor),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        label,
        style: theme.textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Mirror of [_JobsTab]'s error-retry view.  Kept private to this
/// screen so a future tweak doesn't ripple across the codebase
/// before the wider helm error-state spike lands.
class _ErrorRetry extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;
  const _ErrorRetry({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load: $error'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

```
