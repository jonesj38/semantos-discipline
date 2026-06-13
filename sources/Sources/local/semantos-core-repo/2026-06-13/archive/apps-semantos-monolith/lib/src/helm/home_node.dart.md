---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/home_node.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.892585+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/home_node.dart

```dart
// Helm v7 — HomeNode.
//
// "Jobs at their stage" — the home/loom view.  Groups all jobs into
// three sections by operator-action significance, overlays in-progress
// visit pips, and subscribes to live cache events for auto-refresh.
//
// Sections (only shown when non-empty). Realigned 2026-05-18 to the
// SHIPPED 13-state lead-nurture remodel (job_fsm.zig JOB_TRANSITIONS /
// JobFSM.lean) — the original §O4-linear buckets silently dropped
// qualified/authorized/visit_* jobs (they rendered in NO section):
//   1. Needs attention — lead / qualified / authorized /
//                        visit_pending / visited / quoted / completed
//                        (each awaits an operator step)
//   2. Active          — visit_scheduled / scheduled / in_progress
//   3. Recent          — invoiced / paid / closed  ← collapsed by default
// Union covers all 13 canonical states so no job falls through.
//
// UX additions:
//   • Search bar — live client-side filter by name / state.
//   • Recent section collapsed by default — tap header to expand.
//   • Swipe left on any row — reveals the next FSM action chip.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/attention_service.dart';
import '../repl/conversation_send_api.dart';
import '../repl/conversation_turns_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/oddjobz_query_client.dart';
import '../repl/repl_client.dart';
import '../repl/repl_errors.dart';
import '../repl/visits_repository.dart';
import '../talk/talk_surface_service.dart';
import 'attention_feed_section.dart';
import 'job_detail_screen.dart';
import 'schedule_sheet.dart';
import 'stage_trail.dart';

// 13-state remodel buckets (SD2/JobFSM-faithful). Needs-attention =
// every state awaiting an operator step; Active = work/visit in
// flight; Recent = closed-out lifecycle tail.
const _kAttentionStates = {
  'lead',
  'qualified',
  'authorized',
  'visit_pending',
  'visited',
  'quoted',
  'completed',
};
const _kActiveStates    = {'visit_scheduled', 'scheduled', 'in_progress'};
const _kRecentStates    = {'invoiced', 'paid', 'closed'};

/// Which Home section a job state renders in. `null` ⇒ the job would
/// render in NO section (the exact §O4-drift bug: pre-remodel buckets
/// silently dropped qualified/authorized/visit_*). Public so the
/// conformance test can guard against re-drift.
enum HomeSection { attention, active, recent }

HomeSection? homeSectionForState(String state) {
  if (_kAttentionStates.contains(state)) return HomeSection.attention;
  if (_kActiveStates.contains(state)) return HomeSection.active;
  if (_kRecentStates.contains(state)) return HomeSection.recent;
  return null;
}

/// The 13 canonical Job-FSM states — a mirror of
/// `extensions/oddjobz/zig/src/job_fsm.zig` JOB_FSM_STATES /
/// `JobFSM.lean` JobState. The conformance test asserts EVERY one
/// maps to a non-null [HomeSection], so a shipped state can never
/// again silently vanish from the operator's Home.
const kCanonicalJobFsmStates = <String>{
  'lead', 'qualified', 'authorized', 'visit_pending', 'visit_scheduled',
  'visited', 'quoted', 'scheduled', 'in_progress', 'completed',
  'invoiced', 'paid', 'closed',
};

// RM-121 — a resolved contact for Home rendering/ordering.
class _Contact {
  final String name;
  final String phone;
  final String role;
  const _Contact(this.name, this.phone, this.role);
}

/// RM-121 — the operator's point-of-contact + the other contacts for
/// a job, derived from the brain-resolved `customerRefs`. The brain
/// already sets customer_name = the point-of-contact per the operator
/// rule (primary:true tenant; else first tenant; else agent/PM);
/// here we surface the same primary + the rest so Home shows who to
/// call. v1 rows with no customerRefs fall back to the plain name.
({_Contact? primary, List<_Contact> others}) jobContacts(Job j) {
  final refs = j.customerRefs;
  if (refs == null || refs.isEmpty) {
    return (
      primary: j.customerName.isNotEmpty
          ? _Contact(j.customerName, '', '')
          : null,
      others: const <_Contact>[],
    );
  }
  _Contact? primary;
  final others = <_Contact>[];
  for (final r in refs) {
    final c = _Contact(
      r.name.isNotEmpty ? r.name : '(unknown contact)',
      r.phone,
      r.role,
    );
    if (primary == null && r.primary) {
      primary = c;
    } else {
      others.add(c);
    }
  }
  if (primary == null) {
    if (others.isNotEmpty) {
      primary = others.removeAt(0);
    } else if (j.customerName.isNotEmpty) {
      primary = _Contact(j.customerName, '', '');
    }
  }
  return (primary: primary, others: others);
}

/// RM-121 — site grouping/sort key (resolved street address; empty →
/// grouped under "No site address", sorted last).
String _siteKey(Job j) => (j.propertyAddress ?? '').trim();

// Width revealed by a full swipe, and the threshold to keep it open.
const double _kRevealWidth     = 84.0;
const double _kSnapThreshold   = 44.0;

class HomeNode extends StatefulWidget {
  final JobsRepository jobs;
  final VisitsRepository? visits;
  final Future<void> Function() onUnauthorised;
  final AttentionService? attention;
  final OddjobzQueryClient? oddjobzQuery;

  /// W4 of CUSTOMER-CONV-LOOP-PLAN — when supplied, the per-job
  /// detail screen renders the Conversation section.  Without it,
  /// JobDetailScreen falls back to the FSM-only view (Todd's
  /// 2026-05-14 complaint: "the jobs only have the capacity to
  /// increment the job state machine").
  final TalkSurfaceService? talkSurface;

  /// W5 — when supplied, contact tiles in JobDetailScreen become
  /// tappable, opening the SMS composer that dispatches via the
  /// brain's POST /api/v1/conversation/<id>/send (Twilio).
  final ConversationSendApi? conversationSendApi;

  /// Canonical conversation turns repository.  When supplied, the
  /// thread button in JobDetailScreen fetches turns from the brain's
  /// GET /api/v1/conversation/turns endpoint.
  final ConversationTurnsRepository? turnsRepository;

  /// REPL client — when supplied, operators can type notes directly
  /// from the JobThreadScreen send bar (conversation-native loop).
  final ReplClient? replClient;

  /// Phase 5 — D-OJ-conv-voice-intake.  When set, a mic button appears
  /// in the AppBar of JobDetailScreen.  See [JobDetailScreen.openVoiceNote].
  final Future<void> Function(
    BuildContext context,
    String jobCellId,
    ConversationTurnsRepository turns,
  )? openVoiceNote;

  const HomeNode({
    super.key,
    required this.jobs,
    this.visits,
    required this.onUnauthorised,
    this.attention,
    this.oddjobzQuery,
    this.talkSurface,
    this.conversationSendApi,
    this.turnsRepository,
    this.replClient,
    this.openVoiceNote,
  });

  @override
  State<HomeNode> createState() => _HomeNodeState();
}

class _HomeNodeState extends State<HomeNode> {
  bool _loading = true;
  String? _error;
  List<Job> _jobs = const [];
  Set<String> _inProgressJobIds = const {};
  bool _recentExpanded = false;
  String _searchQuery = '';

  StreamSubscription<JobsCacheEvent>? _cacheSub;

  @override
  void initState() {
    super.initState();
    _load();
    _cacheSub = widget.jobs.cacheEvents.listen((_) {
      if (!mounted) return;
      _load();
    });
  }

  @override
  void dispose() {
    _cacheSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobs = await widget.jobs.findJobs();
      Set<String> inProgressJobIds = const {};
      if (widget.visits != null) {
        try {
          final allVisits = await widget.visits!.findVisits();
          inProgressJobIds = allVisits
              .where((v) => v.status == 'in_progress')
              .map((v) => v.jobId)
              .toSet();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _inProgressJobIds = inProgressJobIds;
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

  List<Job> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _jobs;
    return _jobs.where((j) =>
        j.customerName.toLowerCase().contains(q) ||
        j.state.toLowerCase().contains(q) ||
        j.id.toLowerCase().contains(q) ||
        (j.scheduledAt.isNotEmpty && j.scheduledAt.toLowerCase().contains(q))).toList();
  }

  /// RM-121 — operator-confirmed organisation: within each FSM
  /// section, order + group jobs by site (address) → point-of-contact
  /// → work description, emitting a `_SiteHeader` whenever the site
  /// changes. Preserves the §O4 FSM sections (the bucket conformance
  /// test is pure `homeSectionForState` logic, unaffected).
  List<Widget> _groupedRows(
    List<Job> jobs, {
    required bool attentionDots,
    required bool liveDots,
  }) {
    final sorted = [...jobs]..sort((a, b) {
        final sa = _siteKey(a);
        final sb = _siteKey(b);
        // Empty address sorts last ("No site address" group).
        if (sa.isEmpty != sb.isEmpty) return sa.isEmpty ? 1 : -1;
        final s = sa.toLowerCase().compareTo(sb.toLowerCase());
        if (s != 0) return s;
        final ca = (jobContacts(a).primary?.name ?? '').toLowerCase();
        final cb = (jobContacts(b).primary?.name ?? '').toLowerCase();
        final c = ca.compareTo(cb);
        if (c != 0) return c;
        final da = (a.description ?? '').toLowerCase();
        final db = (b.description ?? '').toLowerCase();
        final d = da.compareTo(db);
        if (d != 0) return d;
        return a.id.compareTo(b.id);
      });
    final out = <Widget>[];
    String? lastSite;
    for (final j in sorted) {
      final site = _siteKey(j);
      if (site != lastSite) {
        out.add(_SiteHeader(
          address: site.isEmpty ? 'No site address' : site,
        ));
        lastSite = site;
      }
      out.add(_JobRow(
        key: ValueKey(j.id),
        job: j,
        showAttentionDot: attentionDots,
        showLivePip: liveDots && _inProgressJobIds.contains(j.id),
        jobs: widget.jobs,
        visits: widget.visits,
        onUnauthorised: widget.onUnauthorised,
        onTransitioned: _load,
        oddjobzQuery: widget.oddjobzQuery,
        talkSurface: widget.talkSurface,
        conversationSendApi: widget.conversationSendApi,
        turnsRepository: widget.turnsRepository,
        replClient: widget.replClient,
        openVoiceNote: widget.openVoiceNote,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _jobs.isEmpty) {
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
            Text('Failed to load jobs:\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final filtered   = _filtered;
    final attention  = filtered.where((j) => _kAttentionStates.contains(j.state)).toList();
    final active     = filtered.where((j) => _kActiveStates.contains(j.state)).toList();
    final recent     = filtered.where((j) => _kRecentStates.contains(j.state)).toList();

    if (filtered.isEmpty) {
      return Column(
        children: [
          _SearchBar(
            query: _searchQuery,
            onChanged: (q) => setState(() => _searchQuery = q),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  const SizedBox(height: 64),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'No jobs match "$_searchQuery".'
                            : 'No jobs yet. Pull to refresh.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final sections = <Widget>[
      if (widget.attention != null)
        AttentionFeedSection(
          attention: widget.attention!,
          jobs: widget.jobs,
          turnsRepository: widget.turnsRepository,
          replClient: widget.replClient,
        ),
      if (attention.isNotEmpty) ...[
        _SectionHeader(title: 'Needs attention', count: attention.length),
        ..._groupedRows(attention, attentionDots: true, liveDots: false),
      ],
      if (active.isNotEmpty) ...[
        _SectionHeader(title: 'Active', count: active.length),
        ..._groupedRows(active, attentionDots: false, liveDots: true),
      ],
      if (recent.isNotEmpty) ...[
        _SectionHeader(
          title: 'Recent',
          count: recent.length,
          isCollapsible: true,
          isExpanded: _recentExpanded,
          onToggle: () => setState(() => _recentExpanded = !_recentExpanded),
        ),
        if (_recentExpanded)
          ..._groupedRows(recent, attentionDots: false, liveDots: false),
      ],
    ];

    return Column(
      children: [
        _SearchBar(
          query: _searchQuery,
          onChanged: (q) => setState(() => _searchQuery = q),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              itemCount: sections.length,
              separatorBuilder: (_, i) {
                final item = sections[i];
                final next = i + 1 < sections.length ? sections[i + 1] : null;
                // No divider around section/site headers — a site
                // group reads as a block under its address.
                if (item is _SectionHeader || item is _SiteHeader) {
                  return const SizedBox.shrink();
                }
                if (next is _SectionHeader || next is _SiteHeader) {
                  return const SizedBox.shrink();
                }
                return const Divider(height: 1, indent: 56);
              },
              itemBuilder: (_, i) => sections[i],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final String query;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.query, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search jobs…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => onChanged(''),
                )
              : null,
          isDense: true,
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }
}

// ── Section header (collapsible) ──────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool isCollapsible;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const _SectionHeader({
    required this.title,
    required this.count,
    this.isCollapsible = false,
    this.isExpanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
          if (isCollapsible) ...[
            const Spacer(),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    if (isCollapsible && onToggle != null) {
      return InkWell(onTap: onToggle, child: header);
    }
    return header;
  }
}

// ── Site group header (RM-121) ────────────────────────────────────────────

/// A within-section group header showing the resolved site address.
/// Jobs are organised site → contact → description per the operator.
class _SiteHeader extends StatelessWidget {
  final String address;
  const _SiteHeader({required this.address});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined,
              size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              address,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action info ───────────────────────────────────────────────────────────

class _ActionInfo {
  final String label;
  final IconData icon;
  final Color Function(ColorScheme) color;

  const _ActionInfo(this.label, this.icon, this.color);
}

// RM-123 — the primary forward action per state, realigned to the
// shipped 13-state Job FSM (job_fsm.zig JOB_TRANSITIONS). The old map
// assumed the removed direct lead→quoted edge, so every ingested job
// (all `lead`) rejected "Quote" with "not in FSM table". Correct path:
// lead→qualified→quoted→scheduled→in_progress→completed→invoiced→paid
// →closed, plus the authorized / visit branches (no dead-ends except
// the terminal `closed`).
_ActionInfo? _actionForState(String state) => switch (state) {
      'lead'            => _ActionInfo('Qualify',   Icons.verified_outlined,        (cs) => cs.primary),
      'qualified'       => _ActionInfo('Quote',     Icons.request_quote_outlined,   (cs) => cs.primary),
      'visited'         => _ActionInfo('Quote',     Icons.request_quote_outlined,   (cs) => cs.primary),
      'quoted'          => _ActionInfo('Schedule',  Icons.event_outlined,           (cs) => cs.primary),
      'authorized'      => _ActionInfo('Schedule',  Icons.event_outlined,           (cs) => cs.primary),
      'visit_pending'   => _ActionInfo('Set visit', Icons.event_available_outlined, (cs) => cs.primary),
      'visit_scheduled' => _ActionInfo('Visited',   Icons.how_to_reg_outlined,      (cs) => cs.secondary),
      'scheduled'       => _ActionInfo('Start',     Icons.play_arrow_rounded,       (cs) => cs.secondary),
      'in_progress'     => _ActionInfo('Done',      Icons.check_circle_outline,     (cs) => cs.secondary),
      'completed'       => _ActionInfo('Invoice',   Icons.receipt_long_outlined,    (cs) => cs.tertiary),
      'invoiced'        => _ActionInfo('Paid',      Icons.attach_money,             (cs) => cs.tertiary),
      'paid'            => _ActionInfo('Close',     Icons.task_alt,                 (cs) => cs.tertiary),
      _ => null, // closed = terminal
    };

// ── Job row (swipe-to-action) ─────────────────────────────────────────────

class _JobRow extends StatefulWidget {
  final Job job;
  final bool showAttentionDot;
  final bool showLivePip;
  final JobsRepository jobs;
  final VisitsRepository? visits;
  final Future<void> Function() onUnauthorised;
  final Future<void> Function() onTransitioned;
  final OddjobzQueryClient? oddjobzQuery;
  final TalkSurfaceService? talkSurface;
  final ConversationSendApi? conversationSendApi;
  final ConversationTurnsRepository? turnsRepository;
  final ReplClient? replClient;
  final Future<void> Function(
    BuildContext context,
    String jobCellId,
    ConversationTurnsRepository turns,
  )? openVoiceNote;

  const _JobRow({
    super.key,
    required this.job,
    required this.showAttentionDot,
    required this.showLivePip,
    required this.jobs,
    required this.visits,
    required this.onUnauthorised,
    required this.onTransitioned,
    this.oddjobzQuery,
    this.talkSurface,
    this.conversationSendApi,
    this.turnsRepository,
    this.replClient,
    this.openVoiceNote,
  });

  @override
  State<_JobRow> createState() => _JobRowState();
}

class _JobRowState extends State<_JobRow> {
  double _offset = 0.0;
  bool _acting = false;

  void _onDragUpdate(DragUpdateDetails d) {
    final delta = -d.delta.dx;
    setState(() => _offset = (_offset + delta).clamp(0.0, _kRevealWidth));
  }

  void _onDragEnd(DragEndDetails d) {
    setState(() => _offset = _offset > _kSnapThreshold ? _kRevealWidth : 0.0);
  }

  void _snapBack() => setState(() => _offset = 0.0);

  Future<void> _executeAction() async {
    if (_acting) return;
    final state = widget.job.state;

    // Schedule needs the date picker.
    if (state == 'quoted') {
      final picked = await showScheduleSheet(context);
      if (!mounted || picked == null) { _snapBack(); return; }
      setState(() { _acting = true; _offset = _kRevealWidth; });
      try {
        await widget.jobs.scheduleJob(widget.job.id, at: picked);
        if (mounted) await widget.onTransitioned();
      } on ReplUnauthorisedError {
        await widget.onUnauthorised();
      } catch (_) {} finally {
        if (mounted) setState(() { _acting = false; _offset = 0; });
      }
      return;
    }

    setState(() => _acting = true);
    try {
      final result = await _runTransition(state);
      if (!mounted) return;
      if (result is JobTransitionSuccess || result is JobTransitionAlreadyInState) {
        await widget.onTransitioned();
      }
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } catch (_) {} finally {
      if (mounted) setState(() { _acting = false; _offset = 0; });
    }
  }

  // RM-123 — drive the exact 13-state FSM edge. Dedicated verbs where
  // they correctly implement the edge (+ side effects like quote
  // seeding); the generic `transition job <id> <to> --principal
  // operator` for lead→qualified and the visit edges (ungated,
  // operator principal, no presented cap per JOB_TRANSITIONS).
  Future<JobTransitionResult> _runTransition(String state) => switch (state) {
        'lead'            => widget.jobs.transitionJob(
              id: widget.job.id, toState: 'qualified', principalKind: 'operator'),
        'qualified'       => widget.jobs.quoteJob(widget.job.id),    // →quoted
        'visited'         => widget.jobs.quoteJob(widget.job.id),    // →quoted
        'quoted'          => widget.jobs.scheduleJob(widget.job.id), // →scheduled
        'authorized'      => widget.jobs.scheduleJob(widget.job.id), // →scheduled
        'visit_pending'   => widget.jobs.transitionJob(
              id: widget.job.id, toState: 'visit_scheduled', principalKind: 'operator'),
        'visit_scheduled' => widget.jobs.transitionJob(
              id: widget.job.id, toState: 'visited', principalKind: 'operator'),
        'scheduled'       => widget.jobs.startJob(widget.job.id),    // →in_progress
        'in_progress'     => widget.jobs.completeJob(widget.job.id), // →completed
        'completed'       => widget.jobs.invoiceJob(widget.job.id),  // →invoiced
        'invoiced'        => widget.jobs.markJobPaid(widget.job.id), // →paid
        'paid'            => widget.jobs.closeJob(widget.job.id),    // →closed
        _ => throw StateError('No swipe transition for $state'),
      };

  void _navigateToDetail(BuildContext context) {
    if (_offset > 0) { _snapBack(); return; }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobDetailScreen(
        jobs: widget.jobs,
        jobId: widget.job.id,
        initial: widget.job,
        onUnauthorised: widget.onUnauthorised,
        visits: widget.visits,
        oddjobzQuery: widget.oddjobzQuery,
        talkSurface: widget.talkSurface,
        conversationSendApi: widget.conversationSendApi,
        turnsRepository: widget.turnsRepository,
        replClient: widget.replClient,
        openVoiceNote: widget.openVoiceNote,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final info   = _actionForState(widget.job.state);
    final contacts = jobContacts(widget.job);
    final primaryC = contacts.primary;
    final name = (primaryC?.name.isNotEmpty ?? false)
        ? primaryC!.name
        : (widget.job.customerName.isEmpty
            ? widget.job.id
            : widget.job.customerName);
    final primaryPhone = primaryC?.phone ?? '';
    final otherContacts = contacts.others
        .map((c) => c.phone.isNotEmpty ? '${c.name} (${c.phone})' : c.name)
        .where((s) => s.isNotEmpty)
        .toList();
    final desc = (widget.job.description ?? '').trim();

    final rowContent = GestureDetector(
      onTap: () => _navigateToDetail(context),
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 12,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: widget.showLivePip
                        ? const _PulsingDot()
                        : widget.showAttentionDot
                            ? _AttentionDot()
                            : const SizedBox.shrink(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _stateChipColor(cs, widget.job.state),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.job.state.replaceAll('_', ' '),
                            style: TextStyle(
                              fontSize: 10,
                              color: _stateChipTextColor(cs, widget.job.state),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // RM-121 — point-of-contact phone (who to call to
                    // arrange a visit), other contacts, then the work
                    // description. The bold name above is the primary
                    // contact (brain-resolved per the operator rule).
                    if (primaryPhone.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.phone,
                                size: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                primaryPhone,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (otherContacts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Also: ${otherContacts.join(', ')}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.85),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (desc.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          desc,
                          style: const TextStyle(fontSize: 12.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (widget.job.scheduledAt.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            Icon(Icons.event_outlined,
                                size: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              widget.job.scheduledAt,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    StageTrail(currentState: widget.job.state, compact: true),
                  ],
                ),
              ),
              // Chevron hint when action is available.
              if (info != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.chevron_left,
                      size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                ),
            ],
          ),
        ),
      ),
    );

    if (info == null) return rowContent;

    return ClipRect(
      child: GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Action reveal panel (right-aligned).
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _executeAction,
                  child: Container(
                    width: _kRevealWidth,
                    color: info.color(cs),
                    child: _acting
                        ? const Center(
                            child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(info.icon, color: Colors.white, size: 22),
                              const SizedBox(height: 3),
                              Text(
                                info.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            // Row content — slides left to reveal the action panel.
            Transform.translate(
              offset: Offset(-_offset, 0),
              child: rowContent,
            ),
          ],
        ),
      ),
    );
  }

  Color _stateChipColor(ColorScheme cs, String state) {
    if (_kAttentionStates.contains(state)) {
      return cs.errorContainer.withValues(alpha: 0.6);
    }
    if (_kActiveStates.contains(state)) {
      return cs.primaryContainer.withValues(alpha: 0.6);
    }
    return cs.surfaceContainerHighest;
  }

  Color _stateChipTextColor(ColorScheme cs, String state) {
    if (_kAttentionStates.contains(state)) return cs.onErrorContainer;
    if (_kActiveStates.contains(state)) return cs.onPrimaryContainer;
    return cs.onSurfaceVariant;
  }
}

// ── Indicators ────────────────────────────────────────────────────────────

class _AttentionDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.orange,
          shape: BoxShape.circle,
        ),
      );
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

```
