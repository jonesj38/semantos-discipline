---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/do_node.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.886472+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/do_node.dart

```dart
// Helm v7 — DoNode.
//
// The "Do" node — verb shelf.  Shows jobs that need operator action
// (from findAttention()) grouped into three sections:
//   Quote    — pendingQuote list
//   Schedule — pendingSchedule list
//   Invoice  — pendingInvoice list
//
// Each row has a SlideToCommit that drives the corresponding
// JobsRepository verb.  On commit result, a SnackBar surfaces the
// outcome.  Live cache events trigger a refresh.

import 'dart:async';

import 'package:flutter/material.dart';

import '../pask/pask_session_service.dart';
import '../repl/conversation_send_api.dart';
import '../repl/conversation_turns_repository.dart';
import '../repl/hat_context.dart';
import '../repl/hat_entity_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/quotes_repository.dart';
import '../repl/repl_client.dart';
import '../repl/repl_errors.dart';
import '../repl/visits_repository.dart';
import '../talk/talk_surface_service.dart';
import 'job_detail_screen.dart';
import 'quote_catalogue.dart';
import 'invoice_document.dart';
import 'invoice_editor_sheet.dart';
import 'quote_document.dart';
import 'quote_editor_sheet.dart';
import 'quote_extractor.dart';
import 'receipt_ocr_service.dart';
import 'schedule_sheet.dart';
import 'slide_to_commit.dart';

class DoNode extends StatefulWidget {
  final JobsRepository jobs;
  final Future<void> Function() onUnauthorised;

  /// W1.3 — optional Pask session service.  When non-null, each
  /// confirmed FSM action (quote, schedule, invoice) fires an
  /// interact event so the attention graph stays current.
  final PaskSessionService? paskSession;

  /// Optional — when supplied, quote editor saves the document locally
  /// before driving the Semantos Brain FSM transition.
  final QuotesRepository? quotes;
  final HatEntityRepository? entityRepo;
  final HatContext? hat;

  /// Visits repository — forwarded to JobDetailScreen so the visits
  /// section renders when the operator taps a row to review context.
  final VisitsRepository? visits;

  /// Conversation surface + API passthrough — forwarded to
  /// JobDetailScreen so the operator can read/write the conversation
  /// thread before committing the action.
  final TalkSurfaceService? talkSurface;
  final ConversationSendApi? conversationSendApi;
  final ConversationTurnsRepository? turnsRepository;

  /// REPL client — forwarded to JobDetailScreen → JobThreadScreen so
  /// the operator can type notes from the thread view before committing
  /// the action.
  final ReplClient? replClient;

  const DoNode({
    super.key,
    required this.jobs,
    required this.onUnauthorised,
    this.paskSession,
    this.quotes,
    this.entityRepo,
    this.hat,
    this.visits,
    this.talkSurface,
    this.conversationSendApi,
    this.turnsRepository,
    this.replClient,
  });

  @override
  State<DoNode> createState() => _DoNodeState();
}

class _DoNodeState extends State<DoNode> {
  bool _loading = true;
  String? _error;
  AttentionFeed _feed = const AttentionFeed(
    pendingQuote: [],
    pendingSchedule: [],
    pendingInvoice: [],
    total: 0,
  );

  /// All jobs returned by `find jobs` — used to populate the Lead and
  /// Do tabs by client-side state filter.  The Quote/Schedule/Bill tabs
  /// continue to use [_feed]'s attention buckets (which carry the
  /// slide-to-commit semantics).  Future commit could unify both onto
  /// findJobs() once the brain exposes per-state SlideToCommit hints.
  List<Job> _allJobs = const [];

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
      // Load the attention feed (powers Quote / Schedule / Bill lanes
      // with slide-to-commit) and the full job list (powers Lead / Do
      // lanes via client-side FSM-state filter) in parallel.  Both come
      // from JobsRepository so a single error path catches either.
      final results = await Future.wait([
        widget.jobs.findAttention(),
        widget.jobs.findJobs(),
      ]);
      if (!mounted) return;
      setState(() {
        _feed = results[0] as AttentionFeed;
        _allJobs = results[1] as List<Job>;
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

  /// FSM-state allow-lists for the Lead and Do tabs.  Source of truth
  /// is `cartridges/oddjobz/brain/zig/src/job_fsm.zig` JOB_FSM_STATES
  /// (13 canonical states).  The 5 visible Do lanes group them as:
  ///
  ///   Lead     — lead, qualified
  ///   Quote    — (attention feed: pendingQuote — visit_pending..quoted)
  ///   Schedule — (attention feed: pendingSchedule — authorized, scheduled)
  ///   Do       — scheduled, in_progress
  ///   Bill     — (attention feed: pendingInvoice — completed, invoiced)
  ///
  /// Note: `scheduled` appears in both Schedule's attention bucket and
  /// the Do lane's client-side filter; that's deliberate — the Schedule
  /// lane shows jobs *needing* a schedule decision, the Do lane shows
  /// jobs already on the calendar that are ready to be worked.
  static const _leadStates = {'lead', 'qualified'};
  static const _doingStates = {'scheduled', 'in_progress'};

  List<Job> _jobsInStates(Set<String> states) =>
      [for (final j in _allJobs) if (states.contains(j.state)) j];

  Future<void> _doQuote(Job job) async {
    // Show the quote editor before driving the FSM transition.
    final entityRepo = widget.entityRepo;
    final hat = widget.hat;
    QuoteDocument? savedDoc;
    if (entityRepo != null && hat != null) {
      final docRepo = QuoteDocRepository(repo: entityRepo, hat: hat);
      final existing =
          await docRepo.findForJob(job.id) ?? QuoteDocument.newForJob(job.id);

      // Build catalogue + extractor when a replClient is available.
      // Both are optional — the quote editor degrades gracefully when absent.
      // AI calls route through the brain on rbs (no API key on device).
      final catalogue =
          QuoteCatalogueService(repo: entityRepo, hat: hat);
      await catalogue.load();

      final rc = widget.replClient;
      final extractor = rc != null
          ? QuoteExtractorService(replClient: rc, catalogue: catalogue)
          : null;
      // P2b: receipt OCR — routes through brain llm vision (4f3fbbb).
      // No ANTHROPIC_API_KEY needed on device.
      final receiptOcr =
          rc != null ? ReceiptOcrService(replClient: rc) : null;

      if (!mounted) return;
      final edited = await showQuoteEditor(
        context,
        initial: existing,
        jobTitle: job.customerName,
        extractor: extractor,
        receiptOcr: receiptOcr,
        job: job,
        turnsRepository: widget.turnsRepository,
      );
      if (!mounted || edited == null) return; // user dismissed
      savedDoc = await docRepo.save(edited);
    }

    // Drive the Semantos Brain FSM transition.
    final costMin = savedDoc?.totalCents ?? 0;
    JobTransitionResult result;
    if (widget.quotes != null && savedDoc != null) {
      // Create a Semantos Brain quote with the doc total, then transition the job.
      await widget.quotes!.createQuote(
        jobId: job.id,
        costMin: costMin,
        costMax: costMin,
        notes: savedDoc.notes,
      );
    }
    result = await widget.jobs.quoteJob(job.id);
    if (!mounted) return;
    _showResult(result, job);
    // W1.3 — fire pask interact on confirmed transition.
    if (result is JobTransitionSuccess) {
      widget.paskSession?.onFsmAction(job.id, 'oddjobz.job.quote');
    }
    await _load();
  }

  Future<void> _doSchedule(Job job) async {
    // Show date+time picker before driving the FSM transition.
    if (!mounted) return;
    final picked = await showScheduleSheet(context);
    if (!mounted || picked == null) return; // user dismissed

    final result = await widget.jobs.scheduleJob(job.id, at: picked);
    if (!mounted) return;
    _showResult(result, job);
    // W1.3 — fire pask interact on confirmed transition.
    if (result is JobTransitionSuccess) {
      widget.paskSession?.onFsmAction(job.id, 'oddjobz.job.schedule');
    }
    await _load();
  }

  Future<void> _doInvoice(Job job) async {
    // P3c: show the invoice editor before driving the FSM transition.
    final entityRepo = widget.entityRepo;
    final hat = widget.hat;
    InvoiceDocument? savedDoc;
    if (entityRepo != null && hat != null) {
      final invoiceDocRepo =
          InvoiceDocRepository(repo: entityRepo, hat: hat);
      final quoteDocRepo = QuoteDocRepository(repo: entityRepo, hat: hat);

      // Load or create the invoice document.  Prefer an existing draft;
      // if none exists, seed from the approved quote baseline if available.
      InvoiceDocument existing;
      final existingDraft = await invoiceDocRepo.findForJob(job.id);
      if (existingDraft != null) {
        existing = existingDraft;
      } else {
        final qDoc = await quoteDocRepo.findForJob(job.id);
        existing = qDoc != null
            ? InvoiceDocument.fromQuote(qDoc)
            : InvoiceDocument.newForJob(job.id);
      }

      // P3b / P2b — AI generation + receipt OCR both route through brain.
      // No ANTHROPIC_API_KEY needed on device.
      final rc = widget.replClient;
      final receiptOcr =
          rc != null ? ReceiptOcrService(replClient: rc) : null;

      final catalogue = QuoteCatalogueService(repo: entityRepo, hat: hat);
      await catalogue.load();
      final extractor = rc != null
          ? QuoteExtractorService(replClient: rc, catalogue: catalogue)
          : null;

      if (!mounted) return;
      final edited = await showInvoiceEditor(
        context,
        initial: existing,
        jobTitle: job.customerName,
        receiptOcr: receiptOcr,
        extractor: extractor,
        job: job,
        turnsRepository: widget.turnsRepository,
      );
      if (!mounted || edited == null) return; // user dismissed
      savedDoc = await invoiceDocRepo.save(edited);
    }

    // Drive the Semantos Brain FSM transition.
    final totalCents = savedDoc?.totalCents ?? 0;
    final result = await widget.jobs.invoiceJob(
      job.id,
      totalCents: totalCents > 0 ? totalCents : null,
    );
    if (!mounted) return;
    _showResult(result, job);
    // W1.3 — fire pask interact on confirmed transition.
    if (result is JobTransitionSuccess) {
      widget.paskSession?.onFsmAction(job.id, 'oddjobz.job.invoice');
    }
    await _load();
  }

  void _showResult(JobTransitionResult result, Job job) {
    String msg;
    if (result is JobTransitionSuccess) {
      msg = '${job.customerName.isEmpty ? job.id : job.customerName} → ${result.job.state}';
    } else if (result is JobTransitionAlreadyInState) {
      msg = '${job.customerName.isEmpty ? job.id : job.customerName}: already ${result.job.state}';
    } else if (result is JobTransitionError) {
      msg = 'Error: ${result.message}';
    } else {
      msg = 'Unknown result';
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _customerLabel(Job job) =>
      job.customerName.isEmpty ? job.id : job.customerName;

  @override
  Widget build(BuildContext context) {
    if (_loading && _feed.isEmpty && _allJobs.isEmpty) {
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
            Text('Failed to load attention:\n$_error',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    // 5-lane FSM-grouped Kanban (one tab per job-FSM stage cluster).
    // Lane order matches the natural funnel direction; counts in the
    // tab labels give the operator quick at-a-glance status without
    // entering each tab.  Mirrors FindNode's TabBar shape for muscle-
    // memory consistency.
    final leadJobs = _jobsInStates(_leadStates);
    final doingJobs = _jobsInStates(_doingStates);
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              _tabWithCount('Lead', leadJobs.length),
              _tabWithCount('Quote', _feed.pendingQuote.length),
              _tabWithCount('Schedule', _feed.pendingSchedule.length),
              _tabWithCount('Do', doingJobs.length),
              _tabWithCount('Bill', _feed.pendingInvoice.length),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _LanePage(
                  emptyMessage: 'No leads to nurture right now.',
                  jobs: leadJobs,
                  onRefresh: _load,
                  buildTile: _buildSimpleTile,
                ),
                _LanePage(
                  emptyMessage: 'Nothing waiting on a quote.',
                  jobs: _feed.pendingQuote,
                  onRefresh: _load,
                  buildTile: _buildQuoteRow,
                ),
                _LanePage(
                  emptyMessage: 'Nothing waiting on a schedule.',
                  jobs: _feed.pendingSchedule,
                  onRefresh: _load,
                  buildTile: _buildScheduleRow,
                ),
                _LanePage(
                  emptyMessage: 'Nothing in progress right now.',
                  jobs: doingJobs,
                  onRefresh: _load,
                  buildTile: _buildSimpleTile,
                ),
                _LanePage(
                  emptyMessage: 'Nothing waiting on an invoice.',
                  jobs: _feed.pendingInvoice,
                  onRefresh: _load,
                  buildTile: _buildInvoiceRow,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Tab _tabWithCount(String label, int count) => Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  /// Simple tap-to-detail tile used by the Lead and Do lanes which
  /// don't have a slide-to-commit verb.  Operator taps to enter
  /// JobDetailScreen for context + manual transitions.
  Widget _buildSimpleTile(Job job) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          _customerLabel(job).isEmpty
              ? '?'
              : _customerLabel(job)[0].toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(_customerLabel(job)),
      subtitle: Text(job.state),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => JobDetailScreen(
            jobId: job.id,
            initial: job,
            jobs: widget.jobs,
            visits: widget.visits,
            onUnauthorised: widget.onUnauthorised,
            talkSurface: widget.talkSurface,
            conversationSendApi: widget.conversationSendApi,
            turnsRepository: widget.turnsRepository,
            replClient: widget.replClient,
          ),
        ),
      ),
    );
  }

  Widget _buildQuoteRow(Job job) => _CommitRow(
        job: job,
        label: 'Quote · ${_customerLabel(job)}',
        onCommit: () => _doQuote(job),
        jobs: widget.jobs,
        visits: widget.visits,
        onUnauthorised: widget.onUnauthorised,
        talkSurface: widget.talkSurface,
        conversationSendApi: widget.conversationSendApi,
        turnsRepository: widget.turnsRepository,
        replClient: widget.replClient,
        skipActions: [
          _SkipAction(
            label: '→ Schedule',
            description: 'Mark as quoted and go to scheduling',
            action: () => _doSchedule(job),
          ),
          _SkipAction(
            label: '→ Invoice',
            description: 'Skip to invoice — job is done',
            action: () => _doInvoice(job),
          ),
          _SkipAction(
            label: '→ Complete',
            description: 'Mark job as already completed',
            action: () async {
              final result = await widget.jobs.completeJob(job.id);
              if (!mounted) return;
              _showResult(result, job);
              await _load();
            },
          ),
          _SkipAction(
            label: '→ Close',
            description: 'Close job — no further action needed',
            action: () async {
              final result = await widget.jobs.closeJob(job.id);
              if (!mounted) return;
              _showResult(result, job);
              await _load();
            },
          ),
        ],
      );

  Widget _buildScheduleRow(Job job) => _CommitRow(
        job: job,
        label: 'Schedule · ${_customerLabel(job)}',
        onCommit: () => _doSchedule(job),
        jobs: widget.jobs,
        visits: widget.visits,
        onUnauthorised: widget.onUnauthorised,
        talkSurface: widget.talkSurface,
        conversationSendApi: widget.conversationSendApi,
        turnsRepository: widget.turnsRepository,
        replClient: widget.replClient,
        skipActions: [
          _SkipAction(
            label: '→ Invoice',
            description: 'Skip to invoice — job is done',
            action: () => _doInvoice(job),
          ),
          _SkipAction(
            label: '→ Complete',
            description: 'Mark job as already completed',
            action: () async {
              final result = await widget.jobs.completeJob(job.id);
              if (!mounted) return;
              _showResult(result, job);
              await _load();
            },
          ),
          _SkipAction(
            label: '→ Close',
            description: 'Close job — no further action needed',
            action: () async {
              final result = await widget.jobs.closeJob(job.id);
              if (!mounted) return;
              _showResult(result, job);
              await _load();
            },
          ),
        ],
      );

  Widget _buildInvoiceRow(Job job) => _CommitRow(
        job: job,
        label: 'Invoice · ${_customerLabel(job)}',
        onCommit: () => _doInvoice(job),
        jobs: widget.jobs,
        visits: widget.visits,
        onUnauthorised: widget.onUnauthorised,
        talkSurface: widget.talkSurface,
        conversationSendApi: widget.conversationSendApi,
        turnsRepository: widget.turnsRepository,
        replClient: widget.replClient,
        skipActions: [
          _SkipAction(
            label: '→ Complete',
            description: 'Mark job as already completed',
            action: () async {
              final result = await widget.jobs.completeJob(job.id);
              if (!mounted) return;
              _showResult(result, job);
              await _load();
            },
          ),
          _SkipAction(
            label: '→ Close',
            description: 'Close job — no further action needed',
            action: () async {
              final result = await widget.jobs.closeJob(job.id);
              if (!mounted) return;
              _showResult(result, job);
              await _load();
            },
          ),
        ],
      );

}

/// One tab body in the 5-lane Do view.  Pull-to-refresh wrapping a
/// ListView of either _CommitRow (Quote/Schedule/Bill) or a simple
/// tap-to-detail tile (Lead/Do).  Empty state shows a lane-specific
/// message so the operator knows that lane isn't broken — just empty.
class _LanePage extends StatelessWidget {
  const _LanePage({
    required this.jobs,
    required this.onRefresh,
    required this.buildTile,
    required this.emptyMessage,
  });

  final List<Job> jobs;
  final Future<void> Function() onRefresh;
  final Widget Function(Job) buildTile;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: jobs.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      emptyMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 16, top: 4),
              itemCount: jobs.length,
              itemBuilder: (_, i) => buildTile(jobs[i]),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled shortcut action shown in the long-press skip sheet.
class _SkipAction {
  final String label;
  final String description;
  final Future<void> Function() action;
  const _SkipAction({
    required this.label,
    required this.description,
    required this.action,
  });
}

class _CommitRow extends StatelessWidget {
  final Job job;
  final String label;
  final Future<void> Function() onCommit;

  /// Alternative FSM transitions shown when the operator long-presses
  /// the row — lets them skip ahead for jobs that are already further
  /// along than the ingest pipeline knows.
  final List<_SkipAction> skipActions;

  // Navigation context — threaded through so tapping the info icon
  // opens JobDetailScreen with full conversation + visits wired.
  final JobsRepository jobs;
  final VisitsRepository? visits;
  final Future<void> Function() onUnauthorised;
  final TalkSurfaceService? talkSurface;
  final ConversationSendApi? conversationSendApi;
  final ConversationTurnsRepository? turnsRepository;
  final ReplClient? replClient;

  const _CommitRow({
    required this.job,
    required this.label,
    required this.onCommit,
    required this.jobs,
    required this.onUnauthorised,
    this.skipActions = const [],
    this.visits,
    this.talkSurface,
    this.conversationSendApi,
    this.turnsRepository,
    this.replClient,
  });

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobDetailScreen(
        jobs: jobs,
        jobId: job.id,
        initial: job,
        onUnauthorised: onUnauthorised,
        visits: visits,
        talkSurface: talkSurface,
        conversationSendApi: conversationSendApi,
        turnsRepository: turnsRepository,
        replClient: replClient,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Build a subtitle from whatever context the brain gave us so the
    // operator can tell jobs apart at a glance without tapping through.
    final address =
        (job.propertyAddress?.isNotEmpty ?? false) ? job.propertyAddress! : null;
    final desc =
        (job.description?.isNotEmpty ?? false) ? job.description! : null;
    // Trim description to ~80 chars so it doesn't swamp the row.
    final descShort =
        (desc != null && desc.length > 80) ? '${desc.substring(0, 80)}…' : desc;
    final subtitleParts = [?address, ?descShort];
    final subtitle = subtitleParts.join(' — ');

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SlideToCommit(
                  label: label,
                  onCommit: onCommit,
                ),
              ),
              // Tap to open job detail — operator can review the thread and
              // context before committing the action.
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 20),
                tooltip: 'View job detail',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                onPressed: () => _openDetail(context),
              ),
            ],
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4, right: 44),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
    if (skipActions.isEmpty) return row;
    return GestureDetector(
      onLongPress: () => _showSkipSheet(context),
      child: row,
    );
  }

  void _showSkipSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Skip to…',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            for (final action in skipActions)
              ListTile(
                title: Text(action.label),
                subtitle: Text(
                  action.description,
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  action.action();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

```
