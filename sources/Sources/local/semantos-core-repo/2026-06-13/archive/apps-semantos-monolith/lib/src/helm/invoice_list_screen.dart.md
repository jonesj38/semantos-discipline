---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/invoice_list_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.891084+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/invoice_list_screen.dart

```dart
// D-O4.followup-4 — InvoiceList screen (mobile).
//
// View-shape mirror of `apps/loom-svelte/src/views/InvoiceList.svelte`.
// Calls the bearer-gated REPL (`find invoices`, optionally filtered by
// `--job-id`) and renders the result as a Material list.  Tapping a
// row pushes the InvoiceDetail screen.  Mirrors the shape of
// `quote_list_screen.dart`.  Closes the Semantos Brain-side cutover of all 4
// oddjobz FSMs.
//
// D-O5.followup-4 — subscribes to InvoicesRepository.cacheEvents and
// reloads on `invoice.created` / `invoice.transitioned` notifications.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/repl_errors.dart';
import '../repl/invoices_repository.dart';
import 'invoice_detail_screen.dart';

class InvoiceListScreen extends StatefulWidget {
  final InvoicesRepository invoices;
  final Future<void> Function() onUnauthorised;

  /// When non-null, the list is scoped to this parent Job's invoices
  /// via `invoices.find` with `{job_id}`.  Set by [JobDetailScreen]'s
  /// "View all invoices" affordance.
  final String? jobIdFilter;

  const InvoiceListScreen({
    super.key,
    required this.invoices,
    required this.onUnauthorised,
    this.jobIdFilter,
  });

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  bool _loading = true;
  String? _error;
  List<Invoice> _rows = const [];
  StreamSubscription<InvoicesCacheEvent>? _cacheSub;

  @override
  void initState() {
    super.initState();
    _load();
    // D-O5.followup-4 — subscribe to live cache invalidation.
    _cacheSub = widget.invoices.cacheEvents.listen((_) {
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
      final rows = await widget.invoices.findInvoices(jobId: widget.jobIdFilter);
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
            Text('Failed to load invoices:\n$_error',
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
                  'No invoices yet. Pull to refresh.',
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
          final invoice = _rows[i];
          // Subtitle: status + amount.  The full record sits behind the tap.
          final amount = '\$${(invoice.amount / 100).toStringAsFixed(2)}';
          final subtitle = '${invoice.status}  •  $amount';
          return ListTile(
            leading: Icon(_iconForStatus(invoice.status)),
            title: Text(invoice.id),
            subtitle: Text(subtitle),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => InvoiceDetailScreen(
                  invoices: widget.invoices,
                  invoiceId: invoice.id,
                  initial: invoice,
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
}

```
