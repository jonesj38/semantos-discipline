---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/find_node.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.888287+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/find_node.dart

```dart
// Helm v7 — FindNode.
//
// Unified find surface — 5 tabs (Jobs / Customers / Visits / Quotes /
// Invoices), each with a lazy-load list and pull-to-refresh.
// AutomaticKeepAliveClientMixin keeps each tab's state alive across
// tab switches — no reload on tab switch, only pull-to-refresh.
//
// D-DOG.1.0c Phase 3 F.1 — the Jobs tab is the operator's most-
// visited surface.  Extended to render graph-aware fields per the
// promotion-matrix's F.1 row: site address (v2), primary customer
// (v2), due date, has-photos icon.  v1 rows degrade to the legacy
// surface (customer-name title, "—" placeholders); no row ever
// gets filtered out because of missing v2 fields.  Enrichment is
// best-effort: the Jobs tab still loads when the WSS query channel
// is unavailable.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/attention_service.dart';
import '../repl/conversation_send_api.dart';
import '../repl/conversation_turns_repository.dart';
import '../repl/customers_repository.dart';
import '../repl/invoices_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/oddjobz_query_client.dart';
import '../repl/quotes_repository.dart';
import '../repl/repl_client.dart';
import '../repl/repl_errors.dart';
import '../repl/visits_repository.dart';
import '../talk/talk_surface_service.dart';
import 'attachment_screen.dart';
import 'customer_detail_screen.dart';
import 'customer_screen.dart';
import 'invoice_detail_screen.dart';
import 'job_detail_screen.dart';
import 'job_list_row.dart';
import 'quote_detail_screen.dart';
import 'site_screen.dart';
import 'visit_detail_screen.dart';

class FindNode extends StatefulWidget {
  final JobsRepository jobs;
  final CustomersRepository customers;
  final VisitsRepository visits;
  final QuotesRepository quotes;
  final InvoicesRepository invoices;
  final Future<void> Function() onUnauthorised;

  /// D-DOG.1.0c Phase 3 F.1 — graph-aware query client used by the
  /// Jobs tab for the bulk site/customer enrichment.  Optional;
  /// when null the tab loads un-enriched rows (legacy v1 surface).
  /// Wired by HomeScreen post-pairing once the WSS is open.
  final OddjobzQueryClient? oddjobzQuery;

  /// Tier 2P Phase E.1 — attention service propagated to the Jobs tab
  /// so rows can surface lane chip, score dot, and last-message snippet.
  /// Optional; same propagation pattern as [oddjobzQuery].
  final AttentionService? attention;

  /// Canonical conversation turns repository — threaded into
  /// JobDetailScreen so the thread button works from Find → Jobs tab.
  final ConversationTurnsRepository? turnsRepository;

  /// Conversation surface + send API — forwarded to JobDetailScreen
  /// so the operator gets the full conversation section and Twilio
  /// SMS tiles when navigating from the Find tab (previously missing).
  final TalkSurfaceService? talkSurface;
  final ConversationSendApi? conversationSendApi;

  /// REPL client — forwarded so operators can type notes from the
  /// JobThreadScreen send bar when navigating via Find → Jobs.
  final ReplClient? replClient;

  const FindNode({
    super.key,
    required this.jobs,
    required this.customers,
    required this.visits,
    required this.quotes,
    required this.invoices,
    required this.onUnauthorised,
    this.oddjobzQuery,
    this.attention,
    this.turnsRepository,
    this.talkSurface,
    this.conversationSendApi,
    this.replClient,
  });

  @override
  State<FindNode> createState() => _FindNodeState();
}

class _FindNodeState extends State<FindNode>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtl;

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabCtl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Jobs'),
            Tab(text: 'Customers'),
            Tab(text: 'Visits'),
            Tab(text: 'Quotes'),
            Tab(text: 'Invoices'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtl,
            children: [
              _JobsTab(
                jobs: widget.jobs,
                onUnauthorised: widget.onUnauthorised,
                visits: widget.visits,
                oddjobzQuery: widget.oddjobzQuery,
                attention: widget.attention,
                turnsRepository: widget.turnsRepository,
                talkSurface: widget.talkSurface,
                conversationSendApi: widget.conversationSendApi,
                replClient: widget.replClient,
              ),
              _CustomersTab(
                customers: widget.customers,
                onUnauthorised: widget.onUnauthorised,
              ),
              _VisitsTab(
                visits: widget.visits,
                onUnauthorised: widget.onUnauthorised,
              ),
              _QuotesTab(
                quotes: widget.quotes,
                onUnauthorised: widget.onUnauthorised,
              ),
              _InvoicesTab(
                invoices: widget.invoices,
                onUnauthorised: widget.onUnauthorised,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Jobs tab
// ---------------------------------------------------------------------------

class _JobsTab extends StatefulWidget {
  final JobsRepository jobs;
  final VisitsRepository visits;
  final Future<void> Function() onUnauthorised;

  /// D-DOG.1.0c Phase 3 F.1 — graph-aware query client.  Null when
  /// HomeScreen hasn't wired one (e.g. during a tear-down where the
  /// WSS is closing); the tab degrades gracefully to v1 rendering
  /// and the operator's existing 72 first-dogfood rows still show.
  final OddjobzQueryClient? oddjobzQuery;

  /// Tier 2P Phase E.1 — attention service for inline row augments.
  /// Optional; when null rows render as before E.1.
  final AttentionService? attention;

  /// Canonical conversation turns repository — forwarded to
  /// JobDetailScreen so the thread button works in the Jobs tab.
  final ConversationTurnsRepository? turnsRepository;

  /// Conversation surface + send API — forwarded to JobDetailScreen
  /// so the operator gets the full conversation section and Twilio
  /// SMS tiles from the Find tab.
  final TalkSurfaceService? talkSurface;
  final ConversationSendApi? conversationSendApi;

  /// REPL client — forwarded to JobDetailScreen → JobThreadScreen so
  /// the operator can type notes from the thread view.
  final ReplClient? replClient;

  const _JobsTab({
    required this.jobs,
    required this.visits,
    required this.onUnauthorised,
    required this.oddjobzQuery,
    this.attention,
    this.turnsRepository,
    this.talkSurface,
    this.conversationSendApi,
    this.replClient,
  });

  @override
  State<_JobsTab> createState() => _JobsTabState();
}

class _JobsTabState extends State<_JobsTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Job> _rows = const [];

  /// Bulk-fetched primary-customer lookup map.  Keyed by v2 cellId
  /// (the path job.customerRefs[primary].cellId points at) AND by
  /// legacy v1 string id as a defensive fallback.  Built once per
  /// _load(); rebuilt on pull-to-refresh.  Misses resolve to null
  /// at render-time and the row falls back to the v1 customerName
  /// string per Phase 3 F.1.e.
  Map<String, OddjobzCustomer> _customersByRef = const {};

  // ── Tier 2P Phase E.1 — attention data ──────────────────────────────

  Map<String, OddjobzAttentionSignal> _signalsByJobRef = const {};
  Map<String, OddjobzMessagePatch> _lastMessageByJobRef = const {};
  Map<String, OddjobzDispatchDecision> _dispatchByJobRef = const {};
  StreamSubscription<List<OddjobzAttentionSignal>>? _signalsSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToAttention();
  }

  void _subscribeToAttention() {
    final svc = widget.attention;
    if (svc == null) return;
    _signalsSub = svc.signals.listen((signals) {
      if (!mounted) return;
      _rebuildAttentionMaps(signals);
    });
  }

  void _rebuildAttentionMaps(List<OddjobzAttentionSignal> signals) {
    final newSignals = <String, OddjobzAttentionSignal>{};
    final newDispatches = <String, OddjobzDispatchDecision>{};

    for (final s in signals) {
      switch (s.kind) {
        case OddjobzAttentionKind.job:
          final existing = newSignals[s.ref];
          if (existing == null || s.score > existing.score) {
            newSignals[s.ref] = s;
          }
        case OddjobzAttentionKind.dispatch:
          try {
            final d = OddjobzDispatchDecision.fromJson(
              Map<String, dynamic>.from(s.raw),
            );
            if (d.primaryTarget.type == OddjobzDispatchTargetType.job &&
                d.primaryTarget.ref.isNotEmpty) {
              final existing = newDispatches[d.primaryTarget.ref];
              if (existing == null || d.timestamp > existing.timestamp) {
                newDispatches[d.primaryTarget.ref] = d;
              }
            }
          } catch (_) {
            // Malformed raw — skip.
          }
        case OddjobzAttentionKind.message:
          break;
      }
    }

    // Best-effort: match message-kind signals to job via dispatch sourcePatchId.
    final newMessages = <String, OddjobzMessagePatch>{};
    for (final entry in newDispatches.entries) {
      final jobRef = entry.key;
      final dispatch = entry.value;
      for (final s in signals) {
        if (s.kind == OddjobzAttentionKind.message) {
          try {
            final patch = OddjobzMessagePatch.fromJson(
              Map<String, dynamic>.from(s.raw),
            );
            if (patch.patchId == dispatch.sourcePatchId) {
              final existing = newMessages[jobRef];
              if (existing == null || patch.timestamp > existing.timestamp) {
                newMessages[jobRef] = patch;
              }
            }
          } catch (_) {
            // Skip.
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // D-DOG.1.0c Phase 3 F.1 — fan three reads out in parallel:
      //   1. REPL `find jobs`     — load-bearing (the row list)
      //   2. WSS list_sites       — best-effort (site addresses)
      //   3. WSS list_customers   — best-effort (primary customer)
      // Single round-trip's wall-clock when WSS is responsive.
      final futures = await Future.wait([
        widget.jobs.findJobs(),
        _fetchSitesMap(),
        _fetchCustomersMap(),
      ]);
      final jobs = futures[0] as List<Job>;
      final sitesByRef = futures[1] as Map<String, OddjobzSite>;
      final customersByRef = futures[2] as Map<String, OddjobzCustomer>;
      // Enrich v2 rows with their site's fullAddress.  v1 rows pass
      // through unchanged.
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

  /// Bulk-fetch every persisted Site cell, key by cellId.  Best-
  /// effort: a Semantos Brain-side error / WSS-not-connected returns empty
  /// (no enrichment) without breaking the list load.
  Future<Map<String, OddjobzSite>> _fetchSitesMap() async {
    final client = widget.oddjobzQuery;
    if (client == null) return const {};
    try {
      final list = await client.listSites();
      return {for (final s in list) s.cellId: s};
    } catch (_) {
      return const {};
    }
  }

  /// Bulk-fetch every persisted Customer (v1 + v2), keyed by both
  /// v2 cellId and legacy v1 id (for defensive fallback).  Same
  /// best-effort posture as _fetchSitesMap.
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

  /// D-DOG.1.0c Phase 3 F.4 — return a photos-icon tap handler that
  /// pushes [AttachmentScreen] for the given job.  Returns null when
  /// there's no oddjobz query client OR the job doesn't have a v2
  /// cellId-shaped id (v1 rows can't run the
  /// `find_attachments_for_job` verb).  In the null case the icon
  /// stays visual-only and a row tap falls through to the existing
  /// JobDetailScreen handler.
  VoidCallback? _photosTapHandler(BuildContext context, Job job) {
    final client = widget.oddjobzQuery;
    if (client == null) return null;
    // 64-hex cellId is the only shape `find_attachments_for_job`
    // accepts.  Job.id is the legacy v1 string for v1 rows; for
    // v2 rows the Semantos Brain-side dispatcher mints id == cellId so the
    // shape check below covers both.
    final id = job.id;
    if (id.length != 64 || !_isHex(id)) return null;
    final title = job.propertyAddress;
    return () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AttachmentScreen(
            jobRef: id,
            title: title,
            oddjobzQuery: client,
          ),
        ));
  }

  /// Cheap lowercase-hex check — kept inline so we don't import
  /// `dart:convert` just for one regex.  Bool-only; doesn't
  /// surface position info.
  bool _isHex(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      final ok = (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66);
      if (!ok) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _FindTabFrame(
      hintText: 'Search jobs (customer, state, id)…',
      bodyBuilder: (ctx, q) {
        if (_loading && _rows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_error != null) {
          return _ErrorRetry(error: _error!, onRetry: _load);
        }
        final filtered = q.isEmpty
            ? _rows
            : [
                for (final j in _rows)
                  if (j.customerName.toLowerCase().contains(q) ||
                      j.state.toLowerCase().contains(q) ||
                      j.id.toLowerCase().contains(q))
                    j,
              ];
        if (filtered.isEmpty) {
          return _EmptyPull(
              onRefresh: _load,
              message: q.isEmpty
                  ? 'No jobs found.'
                  : 'No jobs match "$q".');
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 16),
            itemBuilder: (context, i) {
              final job = filtered[i];
              return JobListRow(
            job: job,
            primaryCustomer: _resolvePrimaryCustomer(job),
            // Keep the inline FSM stage trail — it's been the
            // operator's at-a-glance position indicator since v7.
            showStageTrail: true,
            // D-DOG.1.0c Phase 3 F.3 — customer-name cell pivots
            // into the customer screen when the operator taps it.
            // Only wired when oddjobzQuery is non-null; F.3's
            // CustomerScreen requires it.  Tap on the rest of the
            // row still routes to JobDetailScreen via [onTap].
            onCustomerTap: widget.oddjobzQuery == null
                ? null
                : (customerRef) =>
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CustomerScreen(
                        customerRef: customerRef,
                        oddjobzQuery: widget.oddjobzQuery!,
                        jobs: widget.jobs,
                        onUnauthorised: widget.onUnauthorised,
                        turnsRepository: widget.turnsRepository,
                        replClient: widget.replClient,
                      ),
                    )),
            onAddressTap: (widget.oddjobzQuery == null || job.siteRef == null)
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SiteScreen(
                        siteRef: job.siteRef!,
                        oddjobzQuery: widget.oddjobzQuery!,
                        jobs: widget.jobs,
                        visits: widget.visits,
                        onUnauthorised: widget.onUnauthorised,
                        turnsRepository: widget.turnsRepository,
                        replClient: widget.replClient,
                      ),
                    )),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => JobDetailScreen(
                jobs: widget.jobs,
                jobId: job.id,
                initial: job,
                onUnauthorised: widget.onUnauthorised,
                visits: widget.visits,
                attention: widget.attention,
                oddjobzQuery: widget.oddjobzQuery,
                turnsRepository: widget.turnsRepository,
                talkSurface: widget.talkSurface,
                conversationSendApi: widget.conversationSendApi,
                replClient: widget.replClient,
              ),
            )),
            // D-DOG.1.0c Phase 3 F.4 — photos icon tap pivots to
            // the per-job attachment list.  Only wired when the v2
            // siteRef resolved to a cellId-shaped string; v1 rows
            // (and v2 rows whose siteRef hasn't enriched yet) keep
            // the icon as a visual hint without a destination.
            onPhotosTap: _photosTapHandler(context, job),
            // Tier 2P Phase E.1 — attention augments.
            attentionSignal: _signalsByJobRef[job.id],
            lastMessagePatch: _lastMessageByJobRef[job.id],
            primaryDispatch: _dispatchByJobRef[job.id],
          );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Customers tab
// ---------------------------------------------------------------------------

class _CustomersTab extends StatefulWidget {
  final CustomersRepository customers;
  final Future<void> Function() onUnauthorised;

  const _CustomersTab({
    required this.customers,
    required this.onUnauthorised,
  });

  @override
  State<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<_CustomersTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Customer> _rows = const [];

  @override
  bool get wantKeepAlive => true;

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
      final rows = await widget.customers.findCustomers();
      if (!mounted) return;
      setState(() => _rows = rows);
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _FindTabFrame(
      hintText: 'Search customers (name, phone)…',
      bodyBuilder: (ctx, q) {
        if (_loading && _rows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_error != null) {
          return _ErrorRetry(error: _error!, onRetry: _load);
        }
        final filtered = q.isEmpty
            ? _rows
            : [
                for (final c in _rows)
                  if (c.displayName.toLowerCase().contains(q) ||
                      c.phone.toLowerCase().contains(q) ||
                      c.id.toLowerCase().contains(q))
                    c,
              ];
        if (filtered.isEmpty) {
          return _EmptyPull(
            onRefresh: _load,
            message: q.isEmpty
                ? 'No customers found.'
                : 'No customers match "$q".',
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 16),
            itemBuilder: (context, i) {
              final c = filtered[i];
              return ListTile(
                title: Text(c.displayName.isEmpty ? c.id : c.displayName),
                subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CustomerDetailScreen(
                    customers: widget.customers,
                    customerId: c.id,
                    initial: c,
                    onUnauthorised: widget.onUnauthorised,
                  ),
                )),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Visits tab
// ---------------------------------------------------------------------------

class _VisitsTab extends StatefulWidget {
  final VisitsRepository visits;
  final Future<void> Function() onUnauthorised;

  const _VisitsTab({
    required this.visits,
    required this.onUnauthorised,
  });

  @override
  State<_VisitsTab> createState() => _VisitsTabState();
}

class _VisitsTabState extends State<_VisitsTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Visit> _rows = const [];

  @override
  bool get wantKeepAlive => true;

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
      final rows = await widget.visits.findVisits();
      if (!mounted) return;
      setState(() => _rows = rows);
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _FindTabFrame(
      hintText: 'Search visits (type, job, status)…',
      bodyBuilder: (ctx, q) {
        if (_loading && _rows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_error != null) {
          return _ErrorRetry(error: _error!, onRetry: _load);
        }
        final filtered = q.isEmpty
            ? _rows
            : [
                for (final v in _rows)
                  if (v.visitType.toLowerCase().contains(q) ||
                      v.jobId.toLowerCase().contains(q) ||
                      v.status.toLowerCase().contains(q))
                    v,
              ];
        if (filtered.isEmpty) {
          return _EmptyPull(
              onRefresh: _load,
              message: q.isEmpty
                  ? 'No visits found.'
                  : 'No visits match "$q".');
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 16),
            itemBuilder: (context, i) {
              final v = filtered[i];
              return ListTile(
                title: Text(v.visitType.isEmpty ? v.id : v.visitType),
                subtitle: Text('Job ${v.jobId}'),
                trailing: Chip(
                  label:
                      Text(v.status, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => VisitDetailScreen(
                    visits: widget.visits,
                    visitId: v.id,
                    initial: v,
                    onUnauthorised: widget.onUnauthorised,
                  ),
                )),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Quotes tab
// ---------------------------------------------------------------------------

class _QuotesTab extends StatefulWidget {
  final QuotesRepository quotes;
  final Future<void> Function() onUnauthorised;

  const _QuotesTab({
    required this.quotes,
    required this.onUnauthorised,
  });

  @override
  State<_QuotesTab> createState() => _QuotesTabState();
}

class _QuotesTabState extends State<_QuotesTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Quote> _rows = const [];

  @override
  bool get wantKeepAlive => true;

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
      final rows = await widget.quotes.findQuotes();
      if (!mounted) return;
      setState(() => _rows = rows);
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatCost(int cents) => '\$${(cents / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _FindTabFrame(
      hintText: 'Search quotes (id, job, status)…',
      bodyBuilder: (ctx, query) {
        if (_loading && _rows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_error != null) {
          return _ErrorRetry(error: _error!, onRetry: _load);
        }
        final filtered = query.isEmpty
            ? _rows
            : [
                for (final q in _rows)
                  if (q.id.toLowerCase().contains(query) ||
                      q.jobId.toLowerCase().contains(query) ||
                      q.status.toLowerCase().contains(query))
                    q,
              ];
        if (filtered.isEmpty) {
          return _EmptyPull(
              onRefresh: _load,
              message: query.isEmpty
                  ? 'No quotes found.'
                  : 'No quotes match "$query".');
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 16),
            itemBuilder: (context, i) {
              final q = filtered[i];
              final range = q.costMin == q.costMax
                  ? _formatCost(q.costMin)
                  : '${_formatCost(q.costMin)}–${_formatCost(q.costMax)}';
              return ListTile(
                title: Text(q.id),
                subtitle: Text('Job ${q.jobId}  ·  $range'),
                trailing: Chip(
                  label:
                      Text(q.status, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => QuoteDetailScreen(
                    quotes: widget.quotes,
                    quoteId: q.id,
                    initial: q,
                    onUnauthorised: widget.onUnauthorised,
                  ),
                )),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Invoices tab
// ---------------------------------------------------------------------------

class _InvoicesTab extends StatefulWidget {
  final InvoicesRepository invoices;
  final Future<void> Function() onUnauthorised;

  const _InvoicesTab({
    required this.invoices,
    required this.onUnauthorised,
  });

  @override
  State<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends State<_InvoicesTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Invoice> _rows = const [];

  @override
  bool get wantKeepAlive => true;

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
      final rows = await widget.invoices.findInvoices();
      if (!mounted) return;
      setState(() => _rows = rows);
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatAmount(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _FindTabFrame(
      hintText: 'Search invoices (id, job, status)…',
      bodyBuilder: (ctx, q) {
        if (_loading && _rows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_error != null) {
          return _ErrorRetry(error: _error!, onRetry: _load);
        }
        final filtered = q.isEmpty
            ? _rows
            : [
                for (final inv in _rows)
                  if (inv.id.toLowerCase().contains(q) ||
                      inv.jobId.toLowerCase().contains(q) ||
                      inv.status.toLowerCase().contains(q))
                    inv,
              ];
        if (filtered.isEmpty) {
          return _EmptyPull(
              onRefresh: _load,
              message: q.isEmpty
                  ? 'No invoices found.'
                  : 'No invoices match "$q".');
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 16),
            itemBuilder: (context, i) {
              final inv = filtered[i];
              return ListTile(
                title: Text(inv.id),
                subtitle: Text(
                    'Job ${inv.jobId}  ·  ${_formatAmount(inv.amount)}'),
                trailing: Chip(
                  label: Text(inv.status,
                      style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => InvoiceDetailScreen(
                    invoices: widget.invoices,
                    invoiceId: inv.id,
                    initial: inv,
                    onUnauthorised: widget.onUnauthorised,
                  ),
                )),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helper widgets
// ---------------------------------------------------------------------------

class _ErrorRetry extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Text('Error: $error', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyPull extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final String message;
  const _EmptyPull({required this.onRefresh, required this.message});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        children: [
          const SizedBox(height: 64),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(message, textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable Find-tab frame: search bar at top + body below.
///
/// Each of FindNode's five sub-tabs (Jobs / Customers / Visits / Quotes /
/// Invoices) wraps its content in this so the search affordance is the
/// same shape everywhere — same as the per-mode search CTA on the Talk
/// surface.  Filtering itself happens inside the body builder because
/// each tab's list shape is different; the frame just owns the query
/// state and the input.
class _FindTabFrame extends StatefulWidget {
  const _FindTabFrame({
    required this.hintText,
    required this.bodyBuilder,
  });

  final String hintText;

  /// Builds the tab body using the current query string.  Implementations
  /// apply their own substring / field filter and decide what "matches"
  /// means for their list type.
  final Widget Function(BuildContext, String query) bodyBuilder;

  @override
  State<_FindTabFrame> createState() => _FindTabFrameState();
}

class _FindTabFrameState extends State<_FindTabFrame> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: widget.hintText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(child: widget.bodyBuilder(context, _query.trim().toLowerCase())),
      ],
    );
  }
}

```
