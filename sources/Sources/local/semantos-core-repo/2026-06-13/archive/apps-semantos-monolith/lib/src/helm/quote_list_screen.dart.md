---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/quote_list_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.896633+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/quote_list_screen.dart

```dart
// D-O4.followup-3 — QuoteList screen (mobile).
//
// View-shape mirror of `apps/loom-svelte/src/views/QuoteList.svelte`.
// Calls the bearer-gated REPL (`find quotes`, optionally filtered by
// `--job-id`) and renders the result as a Material list.  Tapping a
// row pushes the QuoteDetail screen.  Mirrors the shape of
// `visit_list_screen.dart`.
//
// D-O5.followup-4 — subscribes to QuotesRepository.cacheEvents and
// reloads on `quote.created` / `quote.transitioned` notifications.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/repl_errors.dart';
import '../repl/quotes_repository.dart';
import 'quote_detail_screen.dart';

class QuoteListScreen extends StatefulWidget {
  final QuotesRepository quotes;
  final Future<void> Function() onUnauthorised;

  /// When non-null, the list is scoped to this parent Job's quotes via
  /// `quotes.find` with `{job_id}`.  Set by [JobDetailScreen]'s
  /// "View all quotes" affordance.
  final String? jobIdFilter;

  const QuoteListScreen({
    super.key,
    required this.quotes,
    required this.onUnauthorised,
    this.jobIdFilter,
  });

  @override
  State<QuoteListScreen> createState() => _QuoteListScreenState();
}

class _QuoteListScreenState extends State<QuoteListScreen> {
  bool _loading = true;
  String? _error;
  List<Quote> _rows = const [];
  StreamSubscription<QuotesCacheEvent>? _cacheSub;

  @override
  void initState() {
    super.initState();
    _load();
    // D-O5.followup-4 — subscribe to live cache invalidation.
    _cacheSub = widget.quotes.cacheEvents.listen((_) {
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
      final rows = await widget.quotes.findQuotes(jobId: widget.jobIdFilter);
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
            Text('Failed to load quotes:\n$_error',
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
                  'No quotes yet. Pull to refresh.',
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
          final quote = _rows[i];
          // Subtitle: status + cost range.  The full record sits behind the tap.
          final cost = '\$${(quote.costMin / 100).toStringAsFixed(2)} – '
              '\$${(quote.costMax / 100).toStringAsFixed(2)}';
          final subtitle = '${quote.status}  •  $cost';
          return ListTile(
            leading: Icon(_iconForStatus(quote.status)),
            title: Text(quote.id),
            subtitle: Text(subtitle),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => QuoteDetailScreen(
                  quotes: widget.quotes,
                  quoteId: quote.id,
                  initial: quote,
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
}

```
