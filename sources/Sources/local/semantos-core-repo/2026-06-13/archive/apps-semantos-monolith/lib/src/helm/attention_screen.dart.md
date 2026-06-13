---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/attention_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.898138+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/attention_screen.dart

```dart
// D-O5.followup-3 — Attention feed screen (mobile).
//
// Three operator-action buckets surfaced by the typed `jobs.find_
// attention` dispatcher resource: pending_quote (state=lead), pending_
// schedule (state=quoted), pending_invoice (state=completed).  Mirrors
// the shape of `apps/loom-svelte/src/views/Attention.svelte`.  Tapping
// a row navigates to the existing JobDetailScreen.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5 (helm Attention
// view).

import 'package:flutter/material.dart';

import '../repl/conversation_send_api.dart';
import '../repl/conversation_turns_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/repl_client.dart';
import '../repl/repl_errors.dart';
import '../repl/visits_repository.dart';
import '../talk/talk_surface_service.dart';
import 'job_detail_screen.dart';

class AttentionScreen extends StatefulWidget {
  final JobsRepository jobs;
  final Future<void> Function() onUnauthorised;

  // Full wiring forwarded to JobDetailScreen so the detail view shows
  // address, contacts, conversation thread, and send bar.
  final VisitsRepository? visits;
  final TalkSurfaceService? talkSurface;
  final ConversationSendApi? conversationSendApi;
  final ConversationTurnsRepository? turnsRepository;
  final ReplClient? replClient;

  const AttentionScreen({
    super.key,
    required this.jobs,
    required this.onUnauthorised,
    this.visits,
    this.talkSurface,
    this.conversationSendApi,
    this.turnsRepository,
    this.replClient,
  });

  @override
  State<AttentionScreen> createState() => _AttentionScreenState();
}

class _AttentionScreenState extends State<AttentionScreen> {
  bool _loading = true;
  String? _error;
  AttentionFeed _feed = const AttentionFeed(
    pendingQuote: [],
    pendingSchedule: [],
    pendingInvoice: [],
    total: 0,
  );

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
      final feed = await widget.jobs.findAttention();
      if (!mounted) return;
      setState(() => _feed = feed);
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
            Text('Failed to load attention feed:\n$_error',
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          if (_feed.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Nothing needs your attention right now. Pull to refresh.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            )
          else ...[
            _section(context, 'Pending Quote', _feed.pendingQuote,
                'Send a quote to the customer.'),
            _section(context, 'Pending Schedule', _feed.pendingSchedule,
                'Customer accepted — schedule the visit.'),
            _section(context, 'Pending Invoice', _feed.pendingInvoice,
                'Work complete — issue the invoice.'),
          ],
        ],
      ),
    );
  }

  Widget _section(
      BuildContext context, String label, List<Job> rows, String hint) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              '$label  (${rows.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(hint,
                style: const TextStyle(
                    fontSize: 12, fontStyle: FontStyle.italic)),
          ),
          ...rows.map(
            (job) => ListTile(
              dense: true,
              title: Text(job.customerName.isEmpty
                  ? '(no customer)'
                  : job.customerName),
              subtitle: Text(job.scheduledAt.isEmpty
                  ? job.id
                  : '${job.id}  •  ${job.scheduledAt}'),
              trailing: Chip(
                label: Text(job.state),
                visualDensity: VisualDensity.compact,
              ),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => JobDetailScreen(
                    jobs: widget.jobs,
                    jobId: job.id,
                    initial: job,
                    onUnauthorised: widget.onUnauthorised,
                    visits: widget.visits,
                    talkSurface: widget.talkSurface,
                    conversationSendApi: widget.conversationSendApi,
                    turnsRepository: widget.turnsRepository,
                    replClient: widget.replClient,
                  ),
                ));
              },
            ),
          ),
        ],
      ),
    );
  }
}

```
