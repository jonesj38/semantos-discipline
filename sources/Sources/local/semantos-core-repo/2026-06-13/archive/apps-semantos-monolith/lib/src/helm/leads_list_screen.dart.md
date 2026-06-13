---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/leads_list_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.887395+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/leads_list_screen.dart

```dart
// D-O5m.followup-7 Phase B — LeadsListScreen.
//
// Read-only operator view of pending leads (lead.status == 'pending').
// Mirrors `JobListScreen` post-#311 in shape: live-cache subscription
// + tap-row → push detail.  The "detail" here is the
// RatificationCardScreen — operator taps the row, the route is pushed
// directly (no intermediate detail page) so the ratification flow is
// one-tap from the Leads tab.

import 'dart:async';

import 'package:flutter/material.dart';

import '../ratification/ratification_queue_client.dart';
import '../repl/repl_errors.dart';
import 'ratification_card_screen.dart';

class LeadsListScreen extends StatefulWidget {
  final RatificationQueueClient client;
  final Future<void> Function() onUnauthorised;

  /// Optional hat-id filter — when non-null, narrows the queue to
  /// leads scoped under that hat.  HomeScreen passes the operator's
  /// active hat when one is configured.
  final String? hatId;

  const LeadsListScreen({
    super.key,
    required this.client,
    required this.onUnauthorised,
    this.hatId,
  });

  @override
  State<LeadsListScreen> createState() => _LeadsListScreenState();
}

class _LeadsListScreenState extends State<LeadsListScreen> {
  bool _loading = true;
  String? _error;
  List<PendingLead> _rows = const [];
  StreamSubscription<LeadCacheEvent>? _cacheSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Live-tick cache invalidation — when a fresh lead arrives or any
    // lead transitions, refresh the list without a manual pull.
    _cacheSub = widget.client.cacheEvents.listen((_) {
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
      final rows = await widget.client.findPending(hatId: widget.hatId);
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

  Future<void> _openCard(PendingLead lead) async {
    await Navigator.of(context).pushNamed<RatificationCardOutcome>(
      '/ratify',
      arguments: {'lead_id': lead.id},
    );
    // The cache subscription invalidates on lead.transitioned anyway,
    // but pull a fresh page when the operator returns so the list is
    // correct even when the live-tick stream is offline.
    if (mounted) await _load();
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
            Text('Failed to load leads:\n$_error',
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
                  'No pending leads. Pull to refresh.',
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
          final lead = _rows[i];
          return ListTile(
            title: Text(
              lead.customerName.isEmpty ? '(no customer)' : lead.customerName,
            ),
            subtitle: Text(_subtitle(lead), maxLines: 2),
            trailing: Chip(
              label: Text(lead.source),
              visualDensity: VisualDensity.compact,
            ),
            onTap: () => _openCard(lead),
          );
        },
      ),
    );
  }

  String _subtitle(PendingLead lead) {
    final parts = <String>[];
    if (lead.summary.isNotEmpty) parts.add(lead.summary);
    if (lead.phone.isNotEmpty) parts.add(lead.phone);
    if (parts.isEmpty) parts.add(lead.id);
    return parts.join(' · ');
  }
}

```
