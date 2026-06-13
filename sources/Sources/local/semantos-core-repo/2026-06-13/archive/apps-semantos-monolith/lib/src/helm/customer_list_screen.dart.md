---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/customer_list_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.891661+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/customer_list_screen.dart

```dart
// D-O5.followup-3 — CustomerList screen (mobile).
//
// View-shape mirror of `apps/loom-svelte/src/views/CustomerList.svelte`.
// Calls the bearer-gated REPL (`find customers`) and renders the
// result as a Material list. Tapping a row pushes the CustomerDetail
// screen.  Mirrors the shape of `job_list_screen.dart` exactly.
//
// D-O5.followup-4 — subscribes to CustomersRepository.cacheEvents and
// reloads the list whenever the brain emits a `customer.created`
// notification.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/customers_repository.dart';
import '../repl/repl_errors.dart';
import 'customer_detail_screen.dart';

class CustomerListScreen extends StatefulWidget {
  final CustomersRepository customers;
  final Future<void> Function() onUnauthorised;
  const CustomerListScreen({
    super.key,
    required this.customers,
    required this.onUnauthorised,
  });

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  bool _loading = true;
  String? _error;
  List<Customer> _rows = const [];
  StreamSubscription<CustomersCacheEvent>? _cacheSub;

  @override
  void initState() {
    super.initState();
    _load();
    // D-O5.followup-4 — subscribe to live cache invalidation.
    // When operator A creates a customer on the phone, operator B's
    // helm sees the brain's `customer.created` event here and
    // refreshes its list without a manual pull.
    _cacheSub = widget.customers.cacheEvents.listen((_) {
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
      final rows = await widget.customers.findCustomers();
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
            Text('Failed to load customers:\n$_error',
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
                  'No customers yet. Pull to refresh.',
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
          final customer = _rows[i];
          // Subtitle prefers email > phone > address; whatever's
          // populated first.  The full record sits behind the tap.
          final subtitle = [customer.email, customer.phone, customer.address]
              .where((s) => s.isNotEmpty)
              .join('  •  ');
          return ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(customer.displayName.isEmpty
                ? '(no name)'
                : customer.displayName),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CustomerDetailScreen(
                  customers: widget.customers,
                  customerId: customer.id,
                  initial: customer,
                  onUnauthorised: widget.onUnauthorised,
                ),
              ));
            },
          );
        },
      ),
    );
  }
}

```
