---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/operator_shell.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.467483+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/operator_shell.dart

```dart
import 'package:flutter/material.dart';

import 'oddjobz_visuals.dart';
import 'attention_repository.dart';
import 'field_job_detail_screen.dart';
import 'operator_find_tab.dart';
import 'operator_jobs_repository.dart';
import 'oddjobz_rpc.dart';
import 'operator_talk_tab.dart';
import 'stage_trail.dart';

/// The oddjobz OPERATOR app — the faithful 4-tab field-service shell
/// (Home | Do | Talk | Find), replacing the generic verb-shelf helm for the
/// operator. Each tab is a task-oriented surface, not a verb picker:
///   Home  — jobs by significance (Needs attention / Active / Recent)
///   Do    — jobs by next action (Lead / Quote / Schedule / Do / Bill)
///   Talk  — conversations by mode (self / direct / squad / agent / broadcast)
///   Find  — search across Jobs / Customers / Visits / Quotes / Invoices
class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key, required this.rpc, this.onMePressed});

  final OddjobzRpc rpc;
  final VoidCallback? onMePressed;

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  int _index = 0;
  final _homeKey = GlobalKey<_HomeTabState>();
  final _doKey = GlobalKey<_DoTabState>();

  static const _titles = ['Home', 'Do', 'Talk', 'Find'];

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      _HomeTab(key: _homeKey, rpc: widget.rpc),
      _DoTab(key: _doKey, rpc: widget.rpc),
      OperatorTalkTab(rpc: widget.rpc),
      OperatorFindTab(rpc: widget.rpc),
    ];
    return OddjobzPaper(
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_index]),
          actions: [
            if (_index <= 1)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () {
                  _homeKey.currentState?.reload();
                  _doKey.currentState?.reload();
                },
              ),
            IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'Me',
              onPressed: widget.onMePressed,
            ),
          ],
        ),
        body: IndexedStack(index: _index, children: tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.inbox_outlined),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.flash_on_outlined),
              label: 'Do',
            ),
            NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              label: 'Talk',
            ),
            NavigationDestination(icon: Icon(Icons.search), label: 'Find'),
          ],
        ),
      ),
    );
  }
}

/// Shared job row — customer, site/services, StageTrail, photo chip.
class JobRow extends StatelessWidget {
  const JobRow({super.key, required this.rpc, required this.job});
  final OddjobzRpc rpc;
  final OperatorJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = <String>[
      if (job.propertyAddress.isNotEmpty &&
          job.propertyAddress != job.customerName)
        job.propertyAddress,
      if (job.services != null && job.services!.isNotEmpty) job.services!,
    ];
    return OddjobzCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FieldJobDetailScreen(
            rpc: rpc,
            jobId: job.id,
            initialTitle: job.customerName,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.customerName.isEmpty ? '(no customer)' : job.customerName,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (job.hasPhotos) ...[
                Icon(
                  Icons.photo_outlined,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                if (job.photoCount > 0)
                  Text(
                    ' ${job.photoCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          if (job.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                job.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (sub.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                sub.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 6),
          MiniStageTrail(state: job.state),
        ],
      ),
    );
  }
}

// ── Home tab — jobs by significance ──────────────────────────────────────────

class _HomeTab extends StatefulWidget {
  const _HomeTab({super.key, required this.rpc});
  final OddjobzRpc rpc;
  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutomaticKeepAliveClientMixin {
  late final OperatorJobsRepository _repo = OperatorJobsRepository(widget.rpc);
  late Future<JobSignificance> _future = _load();

  Future<JobSignificance> _load() async =>
      JobSignificance.from(await _repo.findJobs());

  void reload() => setState(() => _future = _load());

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<JobSignificance>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Err(error: snap.error.toString(), onRetry: reload);
        }
        final g = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView(
            children: [
              _Section(
                title: 'Needs attention',
                jobs: g.needsAttention,
                rpc: widget.rpc,
                initiallyOpen: true,
              ),
              _Section(title: 'Active', jobs: g.active, rpc: widget.rpc),
              _Section(
                title: 'Recent',
                jobs: g.recent,
                rpc: widget.rpc,
                initiallyOpen: false,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Collapsible job section (Home).
class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.jobs,
    required this.rpc,
    this.initiallyOpen = true,
  });
  final String title;
  final List<OperatorJob> jobs;
  final OddjobzRpc rpc;
  final bool initiallyOpen;
  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _open = widget.initiallyOpen && widget.jobs.isNotEmpty;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        InkWell(
          onTap: widget.jobs.isEmpty
              ? null
              : () => setState(() => _open = !_open),
          child: Row(
            children: [
              Expanded(
                child: OddjobzSectionLabel(
                  label: widget.title,
                  count: widget.jobs.length,
                ),
              ),
              if (widget.jobs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: OddjobzVisuals.inkSoft,
                  ),
                ),
            ],
          ),
        ),
        if (_open)
          for (final j in widget.jobs) ...[
            JobRow(rpc: widget.rpc, job: j),
            const Divider(height: 1),
          ],
      ],
    );
  }
}

// ── Do tab — jobs by next action (attention lanes) ───────────────────────────

class _DoTab extends StatefulWidget {
  const _DoTab({super.key, required this.rpc});
  final OddjobzRpc rpc;
  @override
  State<_DoTab> createState() => _DoTabState();
}

class _DoTabState extends State<_DoTab> with AutomaticKeepAliveClientMixin {
  late final OperatorJobsRepository _repo = OperatorJobsRepository(widget.rpc);
  late Future<List<OperatorJob>> _future = _repo.findJobs();

  void reload() => setState(() => _future = _repo.findJobs());

  @override
  bool get wantKeepAlive => true;

  static const _states = <String>[
    'lead',
    'qualified',
    'visit_pending',
    'visit_scheduled',
    'visited',
    'quoted',
    'authorized',
    'scheduled',
    'in_progress',
    'completed',
    'invoiced',
    'paid',
    'closed',
  ];

  static const _stateLabels = <String, String>{
    'lead': 'Lead',
    'qualified': 'Qualified',
    'visit_pending': 'Visit pending',
    'visit_scheduled': 'Visit scheduled',
    'visited': 'Visited',
    'quoted': 'Quoted',
    'authorized': 'Authorized',
    'scheduled': 'Scheduled',
    'in_progress': 'In progress',
    'completed': 'Completed',
    'invoiced': 'Invoiced',
    'paid': 'Paid',
    'closed': 'Closed',
  };

  static const _stateIcons = <String, IconData>{
    'lead': Icons.inbox_outlined,
    'qualified': Icons.verified_outlined,
    'visit_pending': Icons.event_available_outlined,
    'visit_scheduled': Icons.event_outlined,
    'visited': Icons.assignment_turned_in_outlined,
    'quoted': Icons.request_quote_outlined,
    'authorized': Icons.approval_outlined,
    'scheduled': Icons.calendar_today_outlined,
    'in_progress': Icons.construction_outlined,
    'completed': Icons.task_alt_outlined,
    'invoiced': Icons.receipt_long_outlined,
    'paid': Icons.payments_outlined,
    'closed': Icons.archive_outlined,
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<OperatorJob>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Err(error: snap.error.toString(), onRetry: reload);
        }
        final grouped = _groupByState(snap.data ?? const []);
        final hasJobs = grouped.values.any((jobs) => jobs.isNotEmpty);
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Jobs grouped by FSM state. Open a card to patch the conversation or advance the job.',
                  style: TextStyle(fontSize: 12, color: OddjobzVisuals.inkSoft),
                ),
              ),
              if (!hasJobs)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No jobs')),
                )
              else
                for (final state in _states)
                  _StateLane(
                    state: state,
                    label: _stateLabels[state] ?? state,
                    icon: _stateIcons[state] ?? Icons.view_kanban_outlined,
                    jobs: grouped[state] ?? const [],
                    rpc: widget.rpc,
                  ),
            ],
          ),
        );
      },
    );
  }

  static Map<String, List<OperatorJob>> _groupByState(List<OperatorJob> jobs) {
    final grouped = {for (final state in _states) state: <OperatorJob>[]};
    for (final job in jobs) {
      grouped.putIfAbsent(job.state, () => <OperatorJob>[]).add(job);
    }
    return grouped;
  }
}

/// One Do lane: a canonical FSM state containing jobs currently in that state.
class _StateLane extends StatelessWidget {
  const _StateLane({
    required this.state,
    required this.label,
    required this.icon,
    required this.jobs,
    required this.rpc,
  });
  final String state;
  final String label;
  final IconData icon;
  final List<OperatorJob> jobs;
  final OddjobzRpc rpc;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OddjobzSectionLabel(label: label, count: jobs.length, icon: icon),
        if (jobs.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'No jobs in this state',
              style: TextStyle(fontSize: 12, color: OddjobzVisuals.inkSoft),
            ),
          )
        else
          for (final job in jobs) JobRow(rpc: rpc, job: job),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.n});
  final int n;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$n',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Err extends StatelessWidget {
  const _Err({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

```
