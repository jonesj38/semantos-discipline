---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/quote_detail_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.885857+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/quote_detail_screen.dart

```dart
// D-O4.followup-3 — Quote detail screen (mobile).
//
// MVP slice: read-only view of a single quote, fetched via
// `quotes.find_by_id`.  D-O4.followup-3 (Quote FSM cutover) adds
// state-aware action buttons that drive `quotes.transition` through
// the dispatcher — `draft` shows "Present" + "Supersede"; `presented`
// shows "Accept" + "Decline" + "Expire" + "Supersede"; terminal states
// (accepted/rejected/expired/superseded) show no actions.  Mirrors
// visit_detail_screen.dart's shape.
//
// D-O5.followup-4 — subscribes to QuotesRepository.cacheEvents and
// re-fetches when the displayed quote's id matches an emission.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/repl_errors.dart';
import '../repl/quotes_repository.dart';

class QuoteDetailScreen extends StatefulWidget {
  final QuotesRepository quotes;
  final String quoteId;
  final Quote initial;
  final Future<void> Function() onUnauthorised;
  const QuoteDetailScreen({
    super.key,
    required this.quotes,
    required this.quoteId,
    required this.initial,
    required this.onUnauthorised,
  });

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  late Quote _quote = widget.initial;
  bool _loading = false;
  bool _transitioning = false;
  String? _error;
  StreamSubscription<QuotesCacheEvent>? _cacheSub;

  @override
  void initState() {
    super.initState();
    // D-O5.followup-4 — re-fetch this specific quote when the brain
    // emits a `quote.*` event matching our id.
    _cacheSub = widget.quotes.cacheEvents.listen((evt) {
      if (!mounted) return;
      if (evt.quoteId != widget.quoteId) return;
      _refresh();
    });
  }

  @override
  void dispose() {
    _cacheSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await widget.quotes.findQuote(widget.quoteId);
      if (!mounted) return;
      if (fresh != null) setState(() => _quote = fresh);
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runTransition(
    String label,
    Future<QuoteTransitionResult> Function() runner,
  ) async {
    setState(() {
      _transitioning = true;
      _error = null;
    });
    try {
      final result = await runner();
      if (!mounted) return;
      if (result is QuoteTransitionSuccess) {
        setState(() => _quote = result.quote);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: ${result.quote.status}')),
        );
      } else if (result is QuoteTransitionAlreadyInState) {
        setState(() => _quote = result.quote);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: already ${result.quote.status}')),
        );
      } else if (result is QuoteTransitionError) {
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
  /// directly off the §O4 Quote FSM table:
  ///
  ///   draft      → Present (operator) | Supersede (operator)
  ///   presented  → Accept (service)   | Decline (service)
  ///                                   | Expire (service)
  ///                                   | Supersede (operator)
  ///   accepted   → (no actions — terminal)
  ///   rejected   → (no actions — terminal)
  ///   expired    → (no actions — terminal)
  ///   superseded → (no actions — terminal)
  List<Widget> _actionsForState(BuildContext context) {
    final disabled = _transitioning;
    switch (_quote.status) {
      case 'draft':
        return [
          ElevatedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Present',
                      () => widget.quotes.presentQuote(widget.quoteId),
                    ),
            icon: const Icon(Icons.outgoing_mail),
            label: const Text('Present'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Supersede',
                      () => widget.quotes.supersedeQuote(widget.quoteId),
                    ),
            icon: const Icon(Icons.update),
            label: const Text('Supersede'),
          ),
        ];
      case 'presented':
        return [
          ElevatedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Accept',
                      () => widget.quotes.acceptQuote(widget.quoteId),
                    ),
            icon: const Icon(Icons.check_circle),
            label: const Text('Accept'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Decline',
                      () => widget.quotes.declineQuote(widget.quoteId),
                    ),
            icon: const Icon(Icons.thumb_down_outlined),
            label: const Text('Decline'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Expire',
                      () => widget.quotes.expireQuote(widget.quoteId),
                    ),
            icon: const Icon(Icons.schedule),
            label: const Text('Expire'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Supersede',
                      () => widget.quotes.supersedeQuote(widget.quoteId),
                    ),
            icon: const Icon(Icons.update),
            label: const Text('Supersede'),
          ),
        ];
      case 'accepted':
      case 'rejected':
      case 'expired':
      case 'superseded':
        return const [];
      default:
        return const [];
    }
  }

  String _formatCost(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final actions = _actionsForState(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Quote ${_quote.id}'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _row('Quote ID', _quote.id),
          _row('Job', _quote.jobId),
          _row('Status', _quote.status),
          _row('Cost min', _formatCost(_quote.costMin)),
          _row('Cost max', _formatCost(_quote.costMax)),
          if (_quote.acceptedAt.isNotEmpty)
            _row('Accepted', _quote.acceptedAt),
          if (_quote.rejectedAt.isNotEmpty)
            _row('Rejected', _quote.rejectedAt),
          if (_quote.notes.isNotEmpty) _row('Notes', _quote.notes),
          _row('Created', _quote.createdAt),
          _row('Updated', _quote.updatedAt),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text('Refresh failed: $_error',
                style: const TextStyle(color: Colors.red)),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 24),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
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

```
