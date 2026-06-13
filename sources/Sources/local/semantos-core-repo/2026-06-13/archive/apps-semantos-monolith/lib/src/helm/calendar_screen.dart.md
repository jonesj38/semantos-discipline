---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/calendar_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.893799+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/calendar_screen.dart

```dart
// D-O5.followup-3 — Calendar screen (mobile).
//
// Per-day grouping of the operator's scheduled jobs, fetched via the
// typed `jobs.find_calendar` dispatcher resource.  Mirrors the shape
// of `apps/loom-svelte/src/views/Calendar.svelte`: one tile per day in
// [from, to] with the jobs that day rendered as nested ListTiles.
// Tapping a job pushes the existing JobDetailScreen.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §O5 (helm Calendar
// view).

import 'package:flutter/material.dart';

import '../repl/conversation_turns_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/repl_client.dart';
import '../repl/repl_errors.dart';
import 'job_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  final JobsRepository jobs;
  final Future<void> Function() onUnauthorised;

  /// Optional — forwarded to [JobDetailScreen] so the Thread tab renders
  /// for jobs accessed via the calendar.
  final ConversationTurnsRepository? turnsRepository;

  /// Optional — forwarded to [JobDetailScreen] for the send-SMS path.
  final ReplClient? replClient;

  const CalendarScreen({
    super.key,
    required this.jobs,
    required this.onUnauthorised,
    this.turnsRepository,
    this.replClient,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  bool _loading = true;
  String? _error;
  List<CalendarDay> _days = const [];

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
      // No explicit from/to — the Semantos Brain-side default (start-of-week →
      // start-of-week + 7 days) is what we want for the initial helm
      // render.  Future versions can wire date-pickers; the dispatcher
      // already accepts both bounds.
      final days = await widget.jobs.findCalendar();
      if (!mounted) return;
      setState(() => _days = days);
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
            Text('Failed to load calendar:\n$_error',
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
      child: ListView.builder(
        itemCount: _days.length,
        itemBuilder: (context, i) {
          final day = _days[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    day.date,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (day.jobs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text('No jobs scheduled.',
                        style: TextStyle(fontStyle: FontStyle.italic)),
                  )
                else
                  ...day.jobs.map(
                    (job) => ListTile(
                      dense: true,
                      title: Text(job.customerName.isEmpty
                          ? '(no customer)'
                          : job.customerName),
                      subtitle: Text(job.scheduledAt),
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
        },
      ),
    );
  }
}

```
