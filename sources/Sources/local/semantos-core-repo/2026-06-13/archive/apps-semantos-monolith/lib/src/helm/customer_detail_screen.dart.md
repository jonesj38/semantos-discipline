---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/customer_detail_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.892897+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/customer_detail_screen.dart

```dart
// D-O5.followup-3 — Customer detail screen.
//
// MVP slice: read-only view of a single customer, fetched via the
// typed `customers.find_by_id` dispatcher resource.  Mirrors the shape
// of `job_detail_screen.dart`.  Edit / merge affordances ship in a
// future follow-up alongside the typed `customers.update` command.
//
// D-O5.followup-4 — subscribes to CustomersRepository.cacheEvents
// and re-fetches when the displayed customer's id matches an
// emission.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/customers_repository.dart';
import '../repl/repl_errors.dart';

class CustomerDetailScreen extends StatefulWidget {
  final CustomersRepository customers;
  final String customerId;
  final Customer initial;
  final Future<void> Function() onUnauthorised;
  const CustomerDetailScreen({
    super.key,
    required this.customers,
    required this.customerId,
    required this.initial,
    required this.onUnauthorised,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Customer _customer = widget.initial;
  bool _loading = false;
  String? _error;
  StreamSubscription<CustomersCacheEvent>? _cacheSub;

  @override
  void initState() {
    super.initState();
    // D-O5.followup-4 — re-fetch this specific customer when the
    // brain emits a `customer.created` matching our id.
    _cacheSub = widget.customers.cacheEvents.listen((evt) {
      if (!mounted) return;
      if (evt.customerId != widget.customerId) return;
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
      final fresh = await widget.customers.findCustomer(widget.customerId);
      if (!mounted) return;
      if (fresh != null) setState(() => _customer = fresh);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_customer.displayName.isEmpty
            ? widget.customerId
            : _customer.displayName),
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
          _row('Customer ID', _customer.id),
          _row('Name', _customer.displayName),
          if (_customer.phone.isNotEmpty) _row('Phone', _customer.phone),
          if (_customer.email.isNotEmpty) _row('Email', _customer.email),
          if (_customer.address.isNotEmpty) _row('Address', _customer.address),
          if (_customer.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Notes',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_customer.notes),
              ),
            ),
          ],
          _row('Created', _customer.createdAt),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text('Refresh failed: $_error',
                style: const TextStyle(color: Colors.red)),
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
