---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/visit_list_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.900326+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/visit_list_screen.dart

```dart
// D-O4.followup-2 — VisitList screen (mobile).
//
// View-shape mirror of `apps/loom-svelte/src/views/VisitList.svelte`.
// Calls the bearer-gated REPL (`find visits`, optionally filtered by
// `--job-id`) and renders the result as a Material list.  Tapping a
// row pushes the VisitDetail screen.  Mirrors the shape of
// `customer_list_screen.dart` and `job_list_screen.dart`.
//
// D-O5.followup-4 — subscribes to VisitsRepository.cacheEvents and
// reloads on `visit.created` / `visit.transitioned` notifications.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/repl_errors.dart';
import '../repl/visits_repository.dart';
import 'visit_detail_screen.dart';

class VisitListScreen extends StatefulWidget {
  final VisitsRepository visits;
  final Future<void> Function() onUnauthorised;

  /// When non-null, the list is scoped to this parent Job's visits via
  /// `visits.find` with `{job_id}`.  Set by [JobDetailScreen]'s
  /// "View all visits" affordance.
  final String? jobIdFilter;

  const VisitListScreen({
    super.key,
    required this.visits,
    required this.onUnauthorised,
    this.jobIdFilter,
  });

  @override
  State<VisitListScreen> createState() => _VisitListScreenState();
}

class _VisitListScreenState extends State<VisitListScreen> {
  bool _loading = true;
  String? _error;
  List<Visit> _rows = const [];
  StreamSubscription<VisitsCacheEvent>? _cacheSub;

  @override
  void initState() {
    super.initState();
    _load();
    // D-O5.followup-4 — subscribe to live cache invalidation.  Both
    // visit.created (a new visit landed) and visit.transitioned (an
    // existing visit changed status) refresh the list.
    _cacheSub = widget.visits.cacheEvents.listen((_) {
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
      final rows = await widget.visits.findVisits(jobId: widget.jobIdFilter);
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
            Text('Failed to load visits:\n$_error',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 64),
            Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No visits yet. Pull to refresh.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final visit = _rows[i];
          // Subtitle: status + visit type.  The full record sits behind the tap.
          final subtitle =
              '${visit.status}  •  ${visit.visitType}${visit.actualStart.isEmpty ? "" : "  •  ${visit.actualStart}"}';
          return ListTile(
            leading: Icon(_iconForStatus(visit.status)),
            title: Text(visit.id),
            subtitle: Text(subtitle),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => VisitDetailScreen(
                  visits: widget.visits,
                  visitId: visit.id,
                  initial: visit,
                  onUnauthorised: widget.onUnauthorised,
                ),
              ));
            },
          );
        },
      ),
    );
  }

  IconData _iconForStatus(String status) {
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
}

```
