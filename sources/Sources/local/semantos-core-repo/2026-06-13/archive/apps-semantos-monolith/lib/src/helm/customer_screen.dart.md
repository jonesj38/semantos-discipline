---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/customer_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.897517+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/customer_screen.dart

```dart
// D-DOG.1.0c Phase 3 F.3 — mobile customer-pivot screen.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
//            sub-deliverable F.3;
//            apps/oddjobz-mobile/lib/src/repl/oddjobz_query_client.dart
//            (F.1 wired the eight `oddjobz.*` query verbs);
//            apps/oddjobz-mobile/lib/src/helm/job_list_row.dart
//            (F.1 row widget reused for the per-customer job list).
//
// One-customer pivot — given a 64-hex `customer.v2` cellRef, render
//   1. the customer's contact card (name, role, phone, email), AND
//   2. every `job.v2` cell whose `customerRefs[]` contains this
//      customerRef, rendered with the same [JobListRow] used by the
//      JobList screen (so a job tapped from here lands on the same
//      JobDetailScreen the operator already knows).
//
// Two graph-aware verbs land here, both already wired by F.1:
//   • `oddjobz.get_customer(customerRef)`        → contact card
//   • `oddjobz.find_jobs_for_customer(customerRef)` → jobs list
//
// Both ride the long-lived WSS HelmEventStream maintains; this
// screen has no REPL dependency.  When the WSS is unavailable the
// fetches fail with [OddjobzQueryError] / [TimeoutException] and
// the screen surfaces a retry button — same posture every other
// graph-aware screen uses.
//
// v1 fallback: this screen is v2-only by design.  v1 customers (no
// cellId) don't have a customerRef to navigate from in the first
// place, so they never reach here; the v1 [CustomerDetailScreen]
// (legacy d-O5 surface, keyed by string id) stays the entry-point
// for those.
//
// `tap to call` button: gated on `phone.isNotEmpty`.  The mobile
// pubspec doesn't carry `url_launcher` yet (it'd be the obvious
// dep) — pulling it in is out of scope for F.3 since this screen
// works without it; the phone is rendered as plain selectable text
// the operator can long-press to copy.  When `url_launcher` lands
// in a follow-up the [_PhoneCell] widget is the single insertion
// point.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repl/conversation_turns_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/oddjobz_query_client.dart';
import '../repl/repl_client.dart';
import 'job_detail_screen.dart';
import 'job_list_row.dart';

/// Minimal subset of [OddjobzQueryClient] [CustomerScreen] uses —
/// pulled into its own interface so widget tests can drive the
/// screen through a hand-rolled fake without spinning up a real
/// WSS / HelmEventStream.  The production wiring satisfies this
/// implicitly via [_OddjobzQueryClientAdapter] in the screen's
/// constructor.
abstract class CustomerPivotQuery {
  Future<OddjobzCustomer?> getCustomer(String customerRef);
  Future<List<Map<String, dynamic>>> findJobsForCustomer(String customerRef);
}

/// Production adapter wrapping the real [OddjobzQueryClient].  Kept
/// inside this file so the screen's public API stays single-class.
class _OddjobzQueryClientAdapter implements CustomerPivotQuery {
  final OddjobzQueryClient _client;
  _OddjobzQueryClientAdapter(this._client);

  @override
  Future<OddjobzCustomer?> getCustomer(String customerRef) =>
      _client.getCustomer(customerRef);

  @override
  Future<List<Map<String, dynamic>>> findJobsForCustomer(
          String customerRef) =>
      _client.findJobsForCustomer(customerRef);
}

/// Customer-pivot screen — the F.3 operator-facing surface.
///
/// Navigated to from any [JobListRow] tap on the customer-name cell.
/// Owns its own loading / error state; doesn't share state with the
/// JobList that pushed it (the job list re-renders independently
/// when its repo's cacheEvents fire).
class CustomerScreen extends StatefulWidget {
  /// 64-lowercase-hex `customer.v2` cellId.  The wire shape every
  /// `oddjobz.*` customer verb keys on.
  final String customerRef;

  /// Graph-aware query surface.  In production this is built from
  /// the real [OddjobzQueryClient]; widget tests inject a fake
  /// [CustomerPivotQuery] directly via [CustomerScreen.test].
  final CustomerPivotQuery query;

  /// Used to push [JobDetailScreen] when the operator taps a job in
  /// the per-customer list.  Same instance HomeScreen already wires
  /// into FindNode / JobList — the JobDetail screen needs it for
  /// state-transition commits.
  final JobsRepository jobs;

  /// Forwarded to JobDetailScreen for the unauthorised redirect.
  final Future<void> Function() onUnauthorised;

  /// Kept to forward into JobDetailScreen so detail views can resolve
  /// address + contacts for the jobs listed here.
  final OddjobzQueryClient? oddjobzQueryClient;

  /// Optional — forwarded to [JobDetailScreen] so the Thread tab renders
  /// for jobs accessed via the customer pivot.
  final ConversationTurnsRepository? turnsRepository;

  /// Optional — forwarded to [JobDetailScreen] for the send-SMS path.
  final ReplClient? replClient;

  CustomerScreen({
    super.key,
    required this.customerRef,
    required OddjobzQueryClient oddjobzQuery,
    required this.jobs,
    required this.onUnauthorised,
    this.turnsRepository,
    this.replClient,
  })  : query = _OddjobzQueryClientAdapter(oddjobzQuery),
        oddjobzQueryClient = oddjobzQuery;

  /// Test-only constructor — accepts a hand-rolled [CustomerPivotQuery]
  /// fake so widget tests don't need to spin up an HelmEventStream.
  /// `jobs` is still required because tapping a job in the per-
  /// customer list pushes [JobDetailScreen]; tests that don't
  /// exercise that path can pass a JobsRepository wrapping a stub
  /// REPL client.
  @visibleForTesting
  const CustomerScreen.forTest({
    super.key,
    required this.customerRef,
    required this.query,
    required this.jobs,
    required this.onUnauthorised,
  })  : oddjobzQueryClient = null,
        turnsRepository = null,
        replClient = null;

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  bool _loading = true;
  String? _error;
  OddjobzCustomer? _customer;
  List<Job> _jobs = const [];

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
      // Fan the two graph-aware fetches out in parallel — same
      // wall-clock as one round-trip when the WSS is responsive.
      // get_customer is load-bearing (the screen has nothing else
      // to render without it); find_jobs_for_customer is degraded
      // to an empty list on per-call failure so the contact card
      // still surfaces when the customer has no jobs (or the brain
      // index isn't populated).
      final customerFut = widget.query.getCustomer(widget.customerRef);
      final jobsFut = widget.query
          .findJobsForCustomer(widget.customerRef)
          .catchError((Object _) => const <Map<String, dynamic>>[]);
      final results = await Future.wait([customerFut, jobsFut]);
      if (!mounted) return;
      final customer = results[0] as OddjobzCustomer?;
      final rawJobs = results[1] as List<Map<String, dynamic>>;
      // Re-route the raw job rows through `parseJobs` so the row
      // shape matches every other Job entry-point (including v2
      // graph-aware fields).  parseJobs tolerates the `{jobs:[...]}`
      // envelope OR a bare array — we re-encode as bare to stay on
      // the most-tested path.
      final jobs = parseJobs(jsonEncode(rawJobs));
      setState(() {
        _customer = customer;
        _jobs = jobs;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _customer?.displayName.isNotEmpty == true
        ? _customer!.displayName
        : 'Customer';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _customer == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _customer == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(
              'Failed to load customer:\n$_error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final customer = _customer;
    if (customer == null) {
      // get_customer returned null — the cellRef doesn't match any
      // persisted customer.  Surface a typed miss state rather than
      // an empty card so the operator knows the navigation didn't
      // silently no-op.
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_off_outlined, size: 48),
            const SizedBox(height: 8),
            Text(
              'Customer not found.\n\nRef: ${widget.customerRef}',
              textAlign: TextAlign.center,
            ),
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
          _ContactCard(customer: customer),
          const Divider(height: 1),
          _JobsHeader(count: _jobs.length),
          if (_jobs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Text(
                'No jobs linked to this customer yet.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            )
          else
            ..._jobs.map((j) => _JobTile(
                  job: j,
                  onTap: () => _openJob(j),
                )),
        ],
      ),
    );
  }

  void _openJob(Job job) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => JobDetailScreen(
          jobs: widget.jobs,
          jobId: job.id,
          initial: job,
          onUnauthorised: widget.onUnauthorised,
          oddjobzQuery: widget.oddjobzQueryClient,
          turnsRepository: widget.turnsRepository,
          replClient: widget.replClient,
        ),
      ),
    );
  }
}

/// Contact-info card — name, role, phone, email, address, siteRef.
/// Phone is rendered as a long-pressable selectable text so the
/// operator can copy it; a follow-up wires `url_launcher` for tap-
/// to-call once that dep lands.
class _ContactCard extends StatelessWidget {
  final OddjobzCustomer customer;
  const _ContactCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.person, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.displayName.isEmpty
                          ? '(no name)'
                          : customer.displayName,
                      style: theme.textTheme.titleLarge,
                    ),
                    if (customer.role != null && customer.role!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          customer.role!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (customer.phone.isNotEmpty)
            _PhoneCell(phone: customer.phone),
          if (customer.email.isNotEmpty)
            _LabelCell(
              icon: Icons.email_outlined,
              label: 'Email',
              value: customer.email,
              copyOnLongPress: true,
            ),
          if (customer.address.isNotEmpty)
            _LabelCell(
              icon: Icons.place_outlined,
              label: 'Address',
              value: customer.address,
            ),
        ],
      ),
    );
  }
}

/// Phone row — surfaces a "Call" button when the platform side
/// could route the tap.  For now (no `url_launcher` dep on the
/// pubspec) the tap copies the number to the clipboard so the
/// operator can paste into the dialer; a follow-up upgrades this
/// to a real `tel:` launch without changing the call-site.
class _PhoneCell extends StatelessWidget {
  final String phone;
  const _PhoneCell({required this.phone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Row(
              children: [
                Icon(Icons.phone_outlined,
                    size: 16, color: theme.hintColor),
                const SizedBox(width: 4),
                Text('Phone',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor)),
              ],
            ),
          ),
          Expanded(
            child: SelectableText(
              phone,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          IconButton(
            tooltip: 'Copy number',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: phone));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Phone number copied'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LabelCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool copyOnLongPress;

  const _LabelCell({
    required this.icon,
    required this.label,
    required this.value,
    this.copyOnLongPress = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Row(
              children: [
                Icon(icon, size: 16, color: theme.hintColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
    if (!copyOnLongPress) return body;
    return GestureDetector(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: value));
      },
      child: body,
    );
  }
}

class _JobsHeader extends StatelessWidget {
  final int count;
  const _JobsHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.work_outline, size: 18, color: theme.hintColor),
          const SizedBox(width: 6),
          Text(
            count == 1 ? '1 job' : '$count jobs',
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

/// Wraps [JobListRow] in a Card-like row with separators.  The
/// underlying [JobListRow] doesn't include its own divider; we
/// add one here so the per-customer list reads as a list rather
/// than a flat block of stacked columns.
class _JobTile extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;
  const _JobTile({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        JobListRow(
          job: job,
          // The customer-pivot screen is already filtered to a
          // single customer — re-rendering the customer-name cell
          // on every row would be visual noise.  Pass null and let
          // [JobListRow] fall through to its existing v2-without-
          // primaryCustomer rendering (cellId-as-name); the
          // customer is the screen's title, so the operator already
          // knows.  v1 rows still render their customer-name title.
          primaryCustomer: null,
          onTap: onTap,
        ),
        const Divider(height: 1, indent: 16),
      ],
    );
  }
}

```
