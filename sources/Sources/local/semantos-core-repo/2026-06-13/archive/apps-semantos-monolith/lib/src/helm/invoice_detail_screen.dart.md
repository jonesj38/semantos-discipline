---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/invoice_detail_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.887103+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/invoice_detail_screen.dart

```dart
// D-O4.followup-4 — Invoice detail screen (mobile).
//
// MVP slice: read-only view of a single invoice, fetched via
// `invoices.find_by_id`.  D-O4.followup-4 (Invoice FSM cutover) adds
// state-aware action buttons that drive `invoices.transition` through
// the dispatcher — `draft` shows "Send" + "Cancel"; `sent` shows
// "Mark Viewed" + "Mark Paid" + "Mark Partial" + "Mark Overdue" +
// "Cancel"; `viewed` shows "Mark Paid" + "Mark Partial" + "Mark
// Overdue" + "Cancel"; `partial` shows "Mark Paid" + "Mark Overdue";
// `overdue` shows "Mark Paid" + "Mark Partial".  Terminal states
// (paid/cancelled) show no actions.  Mirrors quote_detail_screen.dart's
// shape.  Closes the Semantos Brain-side cutover of all 4 oddjobz FSMs.
//
// D-O5.followup-4 — subscribes to InvoicesRepository.cacheEvents and
// re-fetches when the displayed invoice's id matches an emission.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/repl_errors.dart';
import '../repl/invoices_repository.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final InvoicesRepository invoices;
  final String invoiceId;
  final Invoice initial;
  final Future<void> Function() onUnauthorised;
  const InvoiceDetailScreen({
    super.key,
    required this.invoices,
    required this.invoiceId,
    required this.initial,
    required this.onUnauthorised,
  });

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  late Invoice _invoice = widget.initial;
  bool _loading = false;
  bool _transitioning = false;
  String? _error;
  StreamSubscription<InvoicesCacheEvent>? _cacheSub;

  @override
  void initState() {
    super.initState();
    // D-O5.followup-4 — re-fetch this specific invoice when the
    // brain emits an `invoice.*` event matching our id.
    _cacheSub = widget.invoices.cacheEvents.listen((evt) {
      if (!mounted) return;
      if (evt.invoiceId != widget.invoiceId) return;
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
      final fresh = await widget.invoices.findInvoice(widget.invoiceId);
      if (!mounted) return;
      if (fresh != null) setState(() => _invoice = fresh);
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
    Future<InvoiceTransitionResult> Function() runner,
  ) async {
    setState(() {
      _transitioning = true;
      _error = null;
    });
    try {
      final result = await runner();
      if (!mounted) return;
      if (result is InvoiceTransitionSuccess) {
        setState(() => _invoice = result.invoice);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: ${result.invoice.status}')),
        );
      } else if (result is InvoiceTransitionAlreadyInState) {
        setState(() => _invoice = result.invoice);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: already ${result.invoice.status}')),
        );
      } else if (result is InvoiceTransitionError) {
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
  /// directly off the §O4 Invoice FSM table.
  List<Widget> _actionsForState(BuildContext context) {
    final disabled = _transitioning;
    switch (_invoice.status) {
      case 'draft':
        return [
          ElevatedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Send',
                      () => widget.invoices.sendInvoice(widget.invoiceId),
                    ),
            icon: const Icon(Icons.outgoing_mail),
            label: const Text('Send'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Cancel',
                      () => widget.invoices.cancelInvoice(widget.invoiceId),
                    ),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel'),
          ),
        ];
      case 'sent':
        return [
          ElevatedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Mark Paid',
                      () => widget.invoices.markPaid(widget.invoiceId),
                    ),
            icon: const Icon(Icons.check_circle),
            label: const Text('Mark Paid'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Mark Viewed',
                      () => widget.invoices.markViewed(widget.invoiceId),
                    ),
            icon: const Icon(Icons.visibility),
            label: const Text('Mark Viewed'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Mark Overdue',
                      () => widget.invoices.markOverdue(widget.invoiceId),
                    ),
            icon: const Icon(Icons.warning_amber_outlined),
            label: const Text('Mark Overdue'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Cancel',
                      () => widget.invoices.cancelInvoice(widget.invoiceId),
                    ),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel'),
          ),
        ];
      case 'viewed':
        return [
          ElevatedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Mark Paid',
                      () => widget.invoices.markPaid(widget.invoiceId),
                    ),
            icon: const Icon(Icons.check_circle),
            label: const Text('Mark Paid'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Mark Overdue',
                      () => widget.invoices.markOverdue(widget.invoiceId),
                    ),
            icon: const Icon(Icons.warning_amber_outlined),
            label: const Text('Mark Overdue'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Cancel',
                      () => widget.invoices.cancelInvoice(widget.invoiceId),
                    ),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel'),
          ),
        ];
      case 'partial':
        return [
          ElevatedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Mark Paid',
                      () => widget.invoices.markPaid(widget.invoiceId),
                    ),
            icon: const Icon(Icons.check_circle),
            label: const Text('Mark Paid'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Mark Overdue',
                      () => widget.invoices.markOverdue(widget.invoiceId),
                    ),
            icon: const Icon(Icons.warning_amber_outlined),
            label: const Text('Mark Overdue'),
          ),
        ];
      case 'overdue':
        return [
          ElevatedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Mark Paid',
                      () => widget.invoices.markPaid(widget.invoiceId),
                    ),
            icon: const Icon(Icons.check_circle),
            label: const Text('Mark Paid'),
          ),
        ];
      case 'paid':
      case 'cancelled':
        return const [];
      default:
        return const [];
    }
  }

  String _formatAmount(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final actions = _actionsForState(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice ${_invoice.id}'),
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
          _row('Invoice ID', _invoice.id),
          _row('Job', _invoice.jobId),
          _row('Status', _invoice.status),
          _row('Amount', _formatAmount(_invoice.amount)),
          if (_invoice.amountPaid > 0)
            _row('Amount paid', _formatAmount(_invoice.amountPaid)),
          if (_invoice.externalInvoiceId.isNotEmpty)
            _row('External ID', _invoice.externalInvoiceId),
          if (_invoice.sentAt.isNotEmpty) _row('Sent', _invoice.sentAt),
          if (_invoice.viewedAt.isNotEmpty) _row('Viewed', _invoice.viewedAt),
          if (_invoice.paidAt.isNotEmpty) _row('Paid', _invoice.paidAt),
          if (_invoice.notes.isNotEmpty) _row('Notes', _invoice.notes),
          _row('Created', _invoice.createdAt),
          _row('Updated', _invoice.updatedAt),
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
