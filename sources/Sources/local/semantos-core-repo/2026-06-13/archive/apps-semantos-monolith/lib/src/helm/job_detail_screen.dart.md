---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/job_detail_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.894435+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/job_detail_screen.dart

```dart
// D-O5m — Job detail screen.
//
// MVP slice: read-only view of a single job, fetched via the same
// REPL surface the job list uses.  D-O5 followup-1 (Job FSM cutover)
// adds state-aware action buttons that drive `jobs.transition`
// through the dispatcher — `lead` shows "Quote", `quoted` shows
// "Schedule", and so on, mirroring the canonical §O4 FSM table.
//
// Voice input + the ratification card are still deferred to
// D-O5m.followup-7; this screen surfaces only the action affordance
// per state so the FSM cutover round-trip can be exercised end-to-end.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/attention_service.dart';
import '../repl/conversation_send_api.dart';
import '../repl/conversation_turns_repository.dart'
    show ConversationTurnsRepository;
import '../repl/repl_client.dart';
import '../repl/hat_context.dart';
import '../repl/hat_entity_repository.dart';
import '../repl/invoices_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/oddjobz_query_client.dart';
import '../repl/quotes_repository.dart';
import '../repl/repl_errors.dart';
import '../repl/visits_repository.dart';
import '../talk/conversation_cell.dart';
import '../talk/talk_surface_service.dart';
import 'contact_conversation_screen.dart';
import 'job_conversation_classifier.dart';
import 'invoice_detail_screen.dart';
import 'job_thread_screen.dart';
import 'quote_detail_screen.dart';
import 'quote_document.dart';
import 'quote_editor_sheet.dart';
import 'schedule_sheet.dart';
import 'visit_detail_screen.dart';

class JobDetailScreen extends StatefulWidget {
  final JobsRepository jobs;
  final String jobId;
  final Job initial;
  final Future<void> Function() onUnauthorised;

  /// D-O4.followup-2 — when supplied, the detail screen renders a
  /// "Visits" section showing visits scoped to this Job and a
  /// "Schedule visit" CTA.  Optional so legacy fixtures that don't
  /// wire a VisitsRepository keep building.
  final VisitsRepository? visits;

  /// D-O4.followup-3 — when supplied, the detail screen renders a
  /// "Quotes" section showing quotes scoped to this Job and a
  /// "Create quote" CTA.  Optional so legacy fixtures that don't
  /// wire a QuotesRepository keep building.
  final QuotesRepository? quotes;

  /// D-O4.followup-4 — when supplied, the detail screen renders an
  /// "Invoices" section showing invoices scoped to this Job and a
  /// "Create invoice" CTA.  Optional so legacy fixtures that don't
  /// wire an InvoicesRepository keep building.
  final InvoicesRepository? invoices;

  /// Tier 2P Phase E.2 — when supplied, an AppBar action button pushes
  /// JobThreadScreen, showing the chronological message + dispatch thread
  /// for this job.
  ///
  /// Superseded by [turnsRepository] when the job has a [Job.cellId].
  /// Kept for backward compatibility with call sites that haven't been
  /// updated to pass [turnsRepository] yet.
  final AttentionService? attention;

  /// Canonical conversation turns repository backed by
  /// GET /api/v1/conversation/turns.  When present AND the job row has a
  /// non-null [Job.cellId], the thread button uses this to show the
  /// canonical `oddjobz.conversation.turn` rows from Postgres — the
  /// same data shown by the operator web PWA.  Preferred over [attention]
  /// for all new call sites.
  final ConversationTurnsRepository? turnsRepository;

  /// When supplied, the detail screen resolves the job's siteRef and
  /// customerRefs to show an Address section and a Contacts section at
  /// the top of the detail view.  Optional so call-sites that haven't
  /// wired the WSS yet still build.
  final OddjobzQueryClient? oddjobzQuery;

  /// When supplied, shows a Conversation section with the job-linked
  /// ConversationCell, and turns can seed quote line items.
  final TalkSurfaceService? talkSurface;
  final HatEntityRepository? entityRepo;
  final HatContext? hat;

  /// W5 of CUSTOMER-CONV-LOOP-PLAN — when supplied, each contact tile
  /// in the Contacts section becomes tappable, opening a per-contact
  /// SMS composer that POSTs to /api/v1/conversation/<contact_id>/send
  /// (Twilio dispatch on the brain).  Without it, contact tiles stay
  /// read-only (Todd's pre-W5 behaviour).
  final ConversationSendApi? conversationSendApi;

  /// When supplied, passed through to JobThreadScreen so the operator
  /// can type notes directly from the thread view (rather than just
  /// reading it).  Posts to POST /api/v1/repl with a job-scoped prefix.
  final ReplClient? replClient;

  /// Phase 5 — D-OJ-conv-voice-intake.  When set, a mic button appears
  /// in the AppBar alongside the Thread button.  The callback receives
  /// the job's cellId and [turnsRepository] so the VoiceCommandSheet
  /// can anchor the transcript as a ConversationTurn.  Stays null for
  /// all call sites that don't have voice machinery wired.
  final Future<void> Function(
    BuildContext context,
    String jobCellId,
    ConversationTurnsRepository turns,
  )? openVoiceNote;

  const JobDetailScreen({
    super.key,
    required this.jobs,
    required this.jobId,
    required this.initial,
    required this.onUnauthorised,
    this.visits,
    this.quotes,
    this.invoices,
    this.attention,
    this.turnsRepository,
    this.oddjobzQuery,
    this.talkSurface,
    this.entityRepo,
    this.hat,
    this.conversationSendApi,
    this.replClient,
    this.openVoiceNote,
  });

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  late Job _job = widget.initial;
  bool _loading = false;
  bool _transitioning = false;
  String? _error;
  // D-O4.followup-2 — visits-for-this-job slice.  Lazily loaded after
  // the detail screen mounts so the legacy refresh path still serves
  // when no VisitsRepository is wired.
  List<Visit> _visits = const [];
  bool _visitsLoading = false;
  String? _visitsError;
  bool _schedulingVisit = false;
  // D-O4.followup-3 — quotes-for-this-job slice.  Same lazy-load shape
  // as the visits slice above.
  List<Quote> _quotes = const [];
  bool _quotesLoading = false;
  String? _quotesError;
  bool _creatingQuote = false;
  // D-O4.followup-4 — invoices-for-this-job slice.  Same lazy-load
  // shape as the quotes slice above.
  List<Invoice> _invoices = const [];
  bool _invoicesLoading = false;
  String? _invoicesError;
  bool _creatingInvoice = false;

  // D-O5.followup-4 — live cache invalidation subscription.  When
  // operator A transitions THIS job on another device, the brain
  // emits `job.transitioned` and we refetch the job here so the
  // detail view reflects the new state in real time.
  StreamSubscription<JobsCacheEvent>? _cacheSub;

  // Enrichment data resolved from OddjobzQueryClient.
  OddjobzSite? _site;
  List<OddjobzCustomer> _enrichedContacts = const [];
  bool _enrichmentLoading = false;

  // Job-linked conversation (loaded lazily from TalkSurfaceService).
  ConversationCell? _jobConversation;
  bool _loadingConversation = false;

  // Local quote document (loaded from QuoteDocRepository).
  QuoteDocument? _quoteDoc;

  @override
  void initState() {
    super.initState();
    // Always background-fetch the full record on open so the detail
    // view fills in even when the initial data is sparse (e.g. the Job
    // object from findAttention() carries only id/customer/state).
    // The initial render shows whatever was passed; the microtask fetch
    // replaces it silently once the brain responds.
    Future.microtask(_refetchJob);
    if (widget.oddjobzQuery != null) _loadEnrichment(_job);
    if (widget.visits != null) _loadVisits();
    if (widget.quotes != null) _loadQuotes();
    if (widget.invoices != null) _loadInvoices();
    if (widget.talkSurface != null) _loadJobConversation();
    if (widget.entityRepo != null && widget.hat != null) _loadQuoteDoc();
    _cacheSub = widget.jobs.cacheEvents.listen((evt) {
      if (!mounted) return;
      if (evt.jobId != widget.jobId) return;
      _refetchJob();
    });
  }

  @override
  void dispose() {
    _cacheSub?.cancel();
    super.dispose();
  }

  Future<void> _loadJobConversation() async {
    final talk = widget.talkSurface;
    if (talk == null) return;
    setState(() => _loadingConversation = true);
    try {
      final cell = await talk.findOrCreateJobConversation(
        jobId: widget.jobId,
        jobTitle: _job.customerName,
      );
      if (!mounted) return;
      setState(() => _jobConversation = cell);
    } catch (_) {
      // Non-fatal — conversation section just won't show.
    } finally {
      if (mounted) setState(() => _loadingConversation = false);
    }
  }

  Future<void> _loadQuoteDoc() async {
    final repo = widget.entityRepo;
    final hat = widget.hat;
    if (repo == null || hat == null) return;
    try {
      final docRepo = QuoteDocRepository(repo: repo, hat: hat);
      final doc = await docRepo.findForJob(widget.jobId);
      if (!mounted) return;
      if (doc != null) setState(() => _quoteDoc = doc);
    } catch (_) {}
  }

  Future<void> _loadEnrichment(Job job) async {
    final client = widget.oddjobzQuery;
    if (client == null) return;
    setState(() => _enrichmentLoading = true);
    try {
      // Resolve site and all customer refs in parallel.
      final siteRef = job.siteRef;
      final refs = job.customerRefs ?? const [];
      final futures = <Future<dynamic>>[
        if (siteRef != null && siteRef.isNotEmpty)
          client.getSite(siteRef).catchError((_) => null),
        ...refs.map((r) => client.getCustomer(r.cellId).catchError((_) => null)),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;
      OddjobzSite? site;
      final contacts = <OddjobzCustomer>[];
      if (siteRef != null && siteRef.isNotEmpty && results.isNotEmpty) {
        site = results[0] as OddjobzSite?;
      }
      final contactOffset = (siteRef != null && siteRef.isNotEmpty) ? 1 : 0;
      for (int i = contactOffset; i < results.length; i++) {
        final c = results[i];
        if (c is OddjobzCustomer) contacts.add(c);
      }
      setState(() {
        _site = site;
        _enrichedContacts = contacts;
      });
    } catch (_) {
      // Non-fatal — address/contacts section just won't show.
    } finally {
      if (mounted) setState(() => _enrichmentLoading = false);
    }
  }

  Future<void> _refetchJob() async {
    try {
      final fresh = await widget.jobs.findJob(widget.jobId);
      if (!mounted || fresh == null) return;
      // Capture old siteRef BEFORE setState so the comparison below
      // is old vs new (not fresh vs fresh).
      final oldSiteRef = _job.siteRef;
      setState(() => _job = fresh);
      if (widget.oddjobzQuery != null && fresh.siteRef != oldSiteRef) {
        _loadEnrichment(fresh);
      }
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception {
      // Silently swallow — the next manual interaction will surface
      // any persistent error through the existing _refresh handler.
    }
  }

  Future<void> _loadInvoices() async {
    final repo = widget.invoices;
    if (repo == null) return;
    setState(() {
      _invoicesLoading = true;
      _invoicesError = null;
    });
    try {
      final rows = await repo.findInvoices(jobId: widget.jobId);
      if (!mounted) return;
      setState(() => _invoices = rows);
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _invoicesError = e.toString());
    } finally {
      if (mounted) setState(() => _invoicesLoading = false);
    }
  }

  Future<void> _createInvoice() async {
    final repo = widget.invoices;
    if (repo == null) return;
    setState(() => _creatingInvoice = true);
    try {
      // MVP: create a draft invoice with zero amount.  The full
      // picker (amount / notes) ships in a future-PR follow-up
      // alongside the helm-side amount-input modality.
      final result = await repo.createInvoice(
        jobId: widget.jobId,
      );
      if (!mounted) return;
      if (result is InvoiceCreateSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created invoice ${result.id}')),
        );
        await _loadInvoices();
      } else if (result is InvoiceCreateError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Create invoice failed: ${result.kind}')),
        );
      }
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create invoice failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _creatingInvoice = false);
    }
  }

  Future<void> _loadQuotes() async {
    final repo = widget.quotes;
    if (repo == null) return;
    setState(() {
      _quotesLoading = true;
      _quotesError = null;
    });
    try {
      final rows = await repo.findQuotes(jobId: widget.jobId);
      if (!mounted) return;
      setState(() => _quotes = rows);
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _quotesError = e.toString());
    } finally {
      if (mounted) setState(() => _quotesLoading = false);
    }
  }

  Future<void> _createQuote() async {
    final repo = widget.quotes;
    if (repo == null) return;

    // Open the quote editor first.
    final entityRepo = widget.entityRepo;
    final hat = widget.hat;
    QuoteDocument? savedDoc;
    if (entityRepo != null && hat != null) {
      final docRepo = QuoteDocRepository(repo: entityRepo, hat: hat);
      final existing = _quoteDoc ??
          await docRepo.findForJob(widget.jobId) ??
          QuoteDocument.newForJob(widget.jobId);
      if (!mounted) return;
      final edited = await showQuoteEditor(
        context,
        initial: existing,
        jobTitle: _job.customerName,
      );
      if (!mounted || edited == null) return;
      savedDoc = await docRepo.save(edited);
      if (mounted) setState(() => _quoteDoc = savedDoc);
    }

    setState(() => _creatingQuote = true);
    try {
      final result = await repo.createQuote(
        jobId:   widget.jobId,
        costMin: savedDoc?.totalCents,
        costMax: savedDoc?.totalCents,
        notes:   savedDoc?.notes,
      );
      if (!mounted) return;
      if (result is QuoteCreateSuccess) {
        // Link the Semantos Brain quote id back to the local doc.
        if (savedDoc != null && entityRepo != null && hat != null) {
          final docRepo = QuoteDocRepository(repo: entityRepo, hat: hat);
          final linked = await docRepo.save(
            savedDoc.copyWith(quoteId: result.id),
          );
          if (mounted) setState(() => _quoteDoc = linked);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created quote ${result.id}')),
        );
        await _loadQuotes();
      } else if (result is QuoteCreateError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Create quote failed: ${result.kind}')),
        );
      }
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create quote failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _creatingQuote = false);
    }
  }

  Future<void> _loadVisits() async {
    final repo = widget.visits;
    if (repo == null) return;
    setState(() {
      _visitsLoading = true;
      _visitsError = null;
    });
    try {
      final rows = await repo.findVisits(jobId: widget.jobId);
      if (!mounted) return;
      setState(() => _visits = rows);
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _visitsError = e.toString());
    } finally {
      if (mounted) setState(() => _visitsLoading = false);
    }
  }

  Future<void> _scheduleVisit() async {
    final repo = widget.visits;
    if (repo == null) return;

    // Pick a date+time before creating the visit.
    if (!mounted) return;
    final picked = await showScheduleSheet(context);
    if (!mounted || picked == null) return;

    setState(() => _schedulingVisit = true);
    try {
      final result = await repo.createVisit(
        jobId:       widget.jobId,
        visitType:   'scheduled_work',
        scheduledAt: picked.toIso8601String(),
      );
      if (!mounted) return;
      if (result is VisitCreateSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scheduled visit ${result.id}')),
        );
        await _loadVisits();
      } else if (result is VisitCreateError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Schedule visit failed: ${result.kind}')),
        );
      }
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Schedule visit failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _schedulingVisit = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await widget.jobs.findJob(widget.jobId);
      if (!mounted) return;
      if (fresh != null) setState(() => _job = fresh);
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (widget.visits != null) await _loadVisits();
    if (widget.quotes != null) await _loadQuotes();
    if (widget.invoices != null) await _loadInvoices();
  }

  /// D-O5 followup-1 — drive a state transition through the
  /// dispatcher's `jobs.transition` resource.  The brain-side handler
  /// returns either a fresh Job (transition applied), an
  /// `already_in_state` body (idempotent retry), or a typed error
  /// (`wrong_cap` etc).  We refresh the screen on success and show a
  /// snackbar with the typed error message otherwise.
  Future<void> _runTransition(
    String label,
    Future<JobTransitionResult> Function() runner,
  ) async {
    setState(() {
      _transitioning = true;
      _error = null;
    });
    try {
      final result = await runner();
      if (!mounted) return;
      if (result is JobTransitionSuccess) {
        setState(() => _job = result.job);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: ${result.job.state}')),
        );
      } else if (result is JobTransitionAlreadyInState) {
        // Idempotent retry — show a soft notice rather than an error.
        setState(() => _job = result.job);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: already ${result.job.state}')),
        );
      } else if (result is JobTransitionError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label failed: ${result.message}')),
        );
      }
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  /// State-keyed action buttons.  Pulls the operator-readable verb
  /// directly off the FSM table:
  ///
  ///   lead          → Quote        (cap.oddjobz.quote)
  ///   quoted        → Schedule     (cap.oddjobz.dispatch)
  ///   scheduled     → Start        (no cap)
  ///   in_progress   → Complete     (no cap)
  ///   completed     → Invoice      (cap.oddjobz.invoice)
  ///   invoiced      → Mark Paid    (no cap)
  ///   paid          → Close        (cap.oddjobz.close)
  ///   closed        → (no actions)
  ///
  /// The backing repository methods round-trip the canonical §O4
  /// table verbatim — adding a row here is a one-line change.
  List<Widget> _actionsForState(BuildContext context) {
    final disabled = _transitioning;
    Widget btn(String label, IconData icon, VoidCallback? onTap) =>
        ElevatedButton.icon(
          onPressed: disabled ? null : onTap,
          icon: Icon(icon),
          label: Text(label),
        );
    // RM-123 — realigned to the shipped 13-state Job FSM
    // (job_fsm.zig JOB_TRANSITIONS). The old map drove the removed
    // direct lead→quoted edge, so every ingested job (all `lead`)
    // failed "Quote" with "not in FSM table". Correct path:
    // lead→qualified→quoted→scheduled→in_progress→completed→invoiced
    // →paid→closed, plus authorized / visit branches.
    final id = widget.jobId;
    // quoted + authorized both → scheduled (date picker → schedule job).
    Widget scheduleBtn() => btn('Schedule', Icons.event, () async {
          final picked = await showScheduleSheet(context);
          if (picked == null || !mounted) return;
          _runTransition('Schedule',
              () => widget.jobs.scheduleJob(id, at: picked));
        });
    switch (_job.state) {
      case 'lead':
        return [
          btn('Qualify', Icons.verified, () => _runTransition('Qualify',
              () => widget.jobs.transitionJob(
                  id: id, toState: 'qualified', principalKind: 'operator'))),
        ];
      case 'qualified':
        return [
          btn('Quote', Icons.request_quote,
              () => _runTransition('Quote', () => widget.jobs.quoteJob(id))),
        ];
      case 'visited':
        return [
          btn('Quote', Icons.request_quote,
              () => _runTransition('Quote', () => widget.jobs.quoteJob(id))),
        ];
      case 'quoted':
        return [scheduleBtn()];
      case 'authorized':
        return [scheduleBtn()];
      case 'visit_pending':
        return [
          btn('Set visit', Icons.event_available,
              () => _runTransition('Set visit',
                  () => widget.jobs.transitionJob(
                      id: id, toState: 'visit_scheduled', principalKind: 'operator'))),
        ];
      case 'visit_scheduled':
        return [
          btn('Visited', Icons.how_to_reg,
              () => _runTransition('Visited',
                  () => widget.jobs.transitionJob(
                      id: id, toState: 'visited', principalKind: 'operator'))),
        ];
      case 'scheduled':
        return [
          btn('Start', Icons.play_arrow,
              () => _runTransition('Start', () => widget.jobs.startJob(id))),
        ];
      case 'in_progress':
        return [
          btn('Complete', Icons.check_circle,
              () => _runTransition('Complete', () => widget.jobs.completeJob(id))),
        ];
      case 'completed':
        return [
          btn('Invoice', Icons.receipt_long,
              () => _runTransition('Invoice', () => widget.jobs.invoiceJob(id))),
        ];
      case 'invoiced':
        return [
          btn('Mark Paid', Icons.attach_money,
              () => _runTransition('Mark Paid', () => widget.jobs.markJobPaid(id))),
        ];
      case 'paid':
        return [
          btn('Close', Icons.lock,
              () => _runTransition('Close', () => widget.jobs.closeJob(id))),
        ];
      case 'closed':
        return const [];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actionsForState(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_job.customerName.isEmpty
            ? widget.jobId
            : _job.customerName),
        actions: [
          // Show thread + mic buttons when turnsRepository is wired AND
          // the job has a non-empty id (always true for real rows).
          // entityAnchor falls back from cellId (v2 LMDB entity hash) to
          // id (v1 UUID) so legacy JSONL jobs work before re-anchoring.
          if (widget.turnsRepository != null &&
              _job.id.isNotEmpty) ...[
            // Phase 5 — voice note mic button (only when voice is wired).
            if (widget.openVoiceNote != null)
              IconButton(
                tooltip: 'Voice note',
                onPressed: () => widget.openVoiceNote!(
                  context,
                  _job.cellId ?? _job.id,
                  widget.turnsRepository!,
                ),
                icon: const Icon(Icons.mic_none),
              ),
            IconButton(
              tooltip: 'Thread',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => JobThreadScreen(
                    entityRef: _job.cellId ?? _job.id,
                    jobTitle: _job.customerName,
                    turnsRepository: widget.turnsRepository!,
                    replClient: widget.replClient,
                    // Voice-first composer: when openVoiceNote is wired
                    // (i.e. the shell's voice pipeline is initialised),
                    // the thread shows a big mic button instead of the
                    // text+send bar.
                    openVoiceNote: widget.openVoiceNote,
                  ),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline),
            ),
          ],
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // RM-121 — render the brain-resolved site / contacts /
          // description DIRECTLY from the job row (find jobs now
          // emits propertyAddress, description, and customerRefs[]
          // with name+phone). Independent of the older getCustomer/
          // getSite enrichment below (which it supersedes for
          // ingested jobs); both can show — this always does when
          // the fields are present.
          if ((_job.propertyAddress ?? '').isNotEmpty)
            _row('Address', _job.propertyAddress!),
          if ((_job.description ?? '').isNotEmpty)
            _row('Work', _job.description!),
          // RM-125 — work-order metadata so the operator sees scope
          // without the source PDF.
          if ((_job.workOrderNumber ?? '').isNotEmpty)
            _row('Work order #', _job.workOrderNumber!),
          if ((_job.services ?? '').isNotEmpty)
            _row('Services', _job.services!),
          if ((_job.issuanceDate ?? '').isNotEmpty)
            _row('Issued', _job.issuanceDate!),
          if ((_job.dueDateRaw ?? '').isNotEmpty)
            _row('Due', _job.dueDateRaw!),
          if ((_job.photoCount ?? 0) > 0)
            _row('Photos', '${_job.photoCount} photo(s) in the work order'),
          if ((_job.customerRefs ?? const []).isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('Contacts',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            ...(_job.customerRefs ?? const []).map((r) {
              final nm = r.name.isNotEmpty ? r.name : '(unknown contact)';
              final label = r.role.isNotEmpty ? '$nm · ${r.role}' : nm;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: r.primary
                              ? FontWeight.w700
                              : FontWeight.w400,
                        )),
                    if (r.phone.isNotEmpty)
                      Text(r.phone,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          )),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
          if (widget.oddjobzQuery != null) ...[
            if (_enrichmentLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(),
              )
            else ...[
              if (_site != null)
                _row('Address', _site!.fullAddress.isNotEmpty
                    ? _site!.fullAddress
                    : _site!.normalisedAddress),
              if (_enrichedContacts.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text('Contacts',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                ..._enrichedContacts.map((c) => _buildContactTile(c)),
                const SizedBox(height: 8),
              ],
            ],
          ],
          _row('Job ID', _job.id),
          _row('Customer', _job.customerName),
          _row('State', _job.state),
          _row('Scheduled', _job.scheduledAt),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text('Refresh failed: $_error',
                style: const TextStyle(color: Colors.red)),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
          // D-O4.followup-2 — Visits section.  Lists visits scoped to
          // this Job + a "Schedule visit" CTA driving `visits.create`
          // with the parent job_id pre-filled.
          if (widget.visits != null) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('Visits',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _schedulingVisit ? null : _scheduleVisit,
                  icon: const Icon(Icons.add),
                  label: const Text('Schedule visit'),
                ),
              ],
            ),
            if (_visitsLoading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              )
            else if (_visitsError != null)
              Text('Failed to load visits: $_visitsError',
                  style: const TextStyle(color: Colors.red))
            else if (_visits.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No visits scheduled.'),
              )
            else
              ..._visits.map((v) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_visitIconForStatus(v.status)),
                    // RM-124 — show who/where, not the bare visit hex.
                    title: Text(v.jobCustomerName.isNotEmpty
                        ? v.jobCustomerName
                        : v.id),
                    subtitle: Text([
                      if (v.jobPropertyAddress.isNotEmpty) v.jobPropertyAddress,
                      '${v.status}  •  ${v.visitType}',
                    ].join('\n')),
                    isThreeLine: v.jobPropertyAddress.isNotEmpty,
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => VisitDetailScreen(
                          visits: widget.visits!,
                          visitId: v.id,
                          initial: v,
                          onUnauthorised: widget.onUnauthorised,
                        ),
                      ));
                    },
                  )),
          ],
          // D-O4.followup-3 — Quotes section.  Lists quotes scoped to
          // this Job + a "Create quote" CTA driving `quotes.create`
          // with the parent job_id pre-filled.  Mirrors the Visits
          // section above.
          if (widget.quotes != null) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('Quotes',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _creatingQuote ? null : _createQuote,
                  icon: const Icon(Icons.add),
                  label: const Text('Create quote'),
                ),
              ],
            ),
            if (_quotesLoading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              )
            else if (_quotesError != null)
              Text('Failed to load quotes: $_quotesError',
                  style: const TextStyle(color: Colors.red))
            else if (_quotes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No quotes yet.'),
              )
            else
              ..._quotes.map((q) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_quoteIconForStatus(q.status)),
                    title: Text(q.id),
                    subtitle: Text(
                        '${q.status}  •  \$${(q.costMin / 100).toStringAsFixed(2)} – \$${(q.costMax / 100).toStringAsFixed(2)}'),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => QuoteDetailScreen(
                          quotes: widget.quotes!,
                          quoteId: q.id,
                          initial: q,
                          onUnauthorised: widget.onUnauthorised,
                        ),
                      ));
                    },
                  )),
          ],
          // D-O4.followup-4 — Invoices section.  Lists invoices scoped
          // to this Job + a "Create invoice" CTA driving
          // `invoices.create` with the parent job_id pre-filled.
          // Mirrors the Quotes section above.  Closes the Semantos Brain-side
          // cutover of all 4 oddjobz FSMs.
          if (widget.invoices != null) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('Invoices',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _creatingInvoice ? null : _createInvoice,
                  icon: const Icon(Icons.add),
                  label: const Text('Create invoice'),
                ),
              ],
            ),
            if (_invoicesLoading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              )
            else if (_invoicesError != null)
              Text('Failed to load invoices: $_invoicesError',
                  style: const TextStyle(color: Colors.red))
            else if (_invoices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No invoices yet.'),
              )
            else
              ..._invoices.map((inv) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_invoiceIconForStatus(inv.status)),
                    title: Text(inv.id),
                    subtitle: Text(
                        '${inv.status}  •  \$${(inv.amount / 100).toStringAsFixed(2)}'),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => InvoiceDetailScreen(
                          invoices: widget.invoices!,
                          invoiceId: inv.id,
                          initial: inv,
                          onUnauthorised: widget.onUnauthorised,
                        ),
                      ));
                    },
                  )),
          ],
          // Conversation lives in its own screen — open it via the chat
          // icon in the AppBar (JobThreadScreen).  Voice notes are
          // recorded via the AppBar mic icon and their transcripts
          // appear there alongside any typed notes.  The Conversation
          // section + inline composer that used to live here at the
          // bottom of the detail screen was removed: it duplicated the
          // thread surface and competed for screen real estate.  When
          // the quote document is loaded we keep the quote chip up next
          // to the contacts section instead of conversation.
        ],
      ),
    );
  }

  List<Widget> _jobConversationPreview(ConversationCell cell) {
    final turns = cell.turns.reversed.take(3).toList().reversed.toList();
    if (turns.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('No messages yet.', style: TextStyle(color: Colors.grey)),
        ),
      ];
    }
    return turns.map((t) {
      final isSelf = t.from == 'self';
      return Align(
        alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: isSelf
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(t.body, style: const TextStyle(fontSize: 13)),
        ),
      );
    }).toList();
  }

  /// RM-126 — ② the conversation box drives the FSM through the
  /// on-device compression gradient.
  ///
  /// Every message lands as a conversation patch (the cheap path that
  /// always happens). The gradient then classifies it: a plain note
  /// stops there; a request to advance THIS job's FSM runs the single
  /// transition the §O4 table allows from the current state — through
  /// the same already-live JobsRepository verb the action buttons use
  /// (no brain redeploy, no bun self-call deadlock risk) — and the
  /// resulting flip is appended to the same conversation-patch log.
  Future<void> _addConversationTurn(String text) async {
    final talk = widget.talkSurface;
    if (talk == null || text.trim().isEmpty) return;
    final cell = _jobConversation;
    if (cell == null) return;

    // 1. Conversation patch — always lands.
    await _appendTurnAndPersist(ConversationTurn(
      from: 'self',
      body: text.trim(),
      ts:   DateTime.now(),
    ));

    // 2. Compression gradient: note vs FSM-advance.
    final c = classifyJobMessage(text, _job.state);
    if (c.kind != JobMessageKind.fsmAdvance) return;

    final runner = _runnerForActionKey(c.actionKey!);
    if (runner == null) return;

    // 3. Flip the FSM through the proven live path, then record the
    //    outcome back into the conversation-patch log.
    final fromState = _job.state;
    await _runTransition(c.actionLabel!, runner);
    if (!mounted) return;
    final outcome = _job.state == fromState
        ? '[FSM] ${c.actionLabel} — no change (still $fromState)'
        : '[FSM] ${c.actionLabel}: $fromState → ${_job.state}';
    await _appendTurnAndPersist(ConversationTurn(
      from: 'self',
      body: outcome,
      ts:   DateTime.now(),
    ));
  }

  /// Maps the gradient's action key to the already-live JobsRepository
  /// verb — the same mapping `_actionsForState` uses for the buttons.
  Future<JobTransitionResult> Function()? _runnerForActionKey(String key) {
    final id = widget.jobId;
    switch (key) {
      case 'qualify':
        return () => widget.jobs.transitionJob(
            id: id, toState: 'qualified', principalKind: 'operator');
      case 'quote':
        return () => widget.jobs.quoteJob(id);
      case 'schedule':
        return () => widget.jobs.scheduleJob(id);
      case 'setVisit':
        return () => widget.jobs.transitionJob(
            id: id, toState: 'visit_scheduled', principalKind: 'operator');
      case 'visited':
        return () => widget.jobs.transitionJob(
            id: id, toState: 'visited', principalKind: 'operator');
      case 'start':
        return () => widget.jobs.startJob(id);
      case 'complete':
        return () => widget.jobs.completeJob(id);
      case 'invoice':
        return () => widget.jobs.invoiceJob(id);
      case 'paid':
        return () => widget.jobs.markJobPaid(id);
      case 'close':
        return () => widget.jobs.closeJob(id);
    }
    return null;
  }

  /// Append a turn to the job-linked ConversationCell and persist it
  /// via the HatEntity store (the conversation-patch log).
  Future<void> _appendTurnAndPersist(ConversationTurn turn) async {
    final cell = _jobConversation;
    if (cell == null) return;
    final updated = cell.copyWith(turns: [...cell.turns, turn]);
    setState(() => _jobConversation = updated);

    final repo = widget.entityRepo;
    final hat  = widget.hat;
    if (repo != null && hat != null) {
      try {
        await repo.upsert(HatEntity(
          id:          updated.id,
          domainFlag:  hat.domainFlag,
          state:       updated.phase,
          scheduledAt: '',
          entityJson:  updated.toEntityJson(),
          updatedAt:   DateTime.now().toUtc().toIso8601String(),
        ));
      } catch (_) {}
    }
  }

  IconData _visitIconForStatus(String status) {
    switch (status) {
      case 'scheduled':
        return Icons.event_outlined;
      case 'in_progress':
        return Icons.directions_run;
      case 'completed':
        return Icons.check_circle_outline;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  IconData _invoiceIconForStatus(String status) {
    switch (status) {
      case 'draft':
        return Icons.edit_note;
      case 'sent':
        return Icons.outgoing_mail;
      case 'viewed':
        return Icons.visibility;
      case 'partial':
        return Icons.payments_outlined;
      case 'paid':
        return Icons.check_circle_outline;
      case 'overdue':
        return Icons.warning_amber_outlined;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  IconData _quoteIconForStatus(String status) {
    switch (status) {
      case 'draft':
        return Icons.edit_note;
      case 'presented':
        return Icons.outgoing_mail;
      case 'accepted':
        return Icons.check_circle_outline;
      case 'rejected':
        return Icons.thumb_down_outlined;
      case 'expired':
        return Icons.schedule;
      case 'superseded':
        return Icons.update;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildContactTile(OddjobzCustomer c) {
    final api = widget.conversationSendApi;
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              c.role != null
                  ? '${c.role![0].toUpperCase()}${c.role!.substring(1)}'
                  : 'Contact',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.displayName, style: const TextStyle(fontSize: 13)),
                if (c.phone.isNotEmpty)
                  Text(c.phone,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (c.email.isNotEmpty)
                  Text(c.email,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          if (api != null && c.phone.isNotEmpty)
            const Icon(Icons.send, size: 16, color: Colors.grey),
        ],
      ),
    );
    // Tile is tappable only when both the API is wired AND we have a
    // phone — without phone, the brain's lookup will 404 anyway.
    if (api == null || c.phone.isEmpty) return body;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ContactConversationScreen(
              contact: c,
              api: api,
              jobCellId: _job.cellId,
              jobState: _job.state,
            ),
      )),
      child: body,
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

// ── Inline message input for the job conversation section ─────────────────

class _AddTurnField extends StatefulWidget {
  final Future<void> Function(String) onSend;
  const _AddTurnField({required this.onSend});

  @override
  State<_AddTurnField> createState() => _AddTurnFieldState();
}

class _AddTurnFieldState extends State<_AddTurnField> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              hintText: 'Add a note…',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
        ),
      ],
    );
  }
}

```
