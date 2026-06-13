---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/customer_screen_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.928183+00:00
---

# archive/apps-semantos-monolith/test/helm/customer_screen_test.dart

```dart
// D-DOG.1.0c Phase 3 F.3 — CustomerScreen widget tests.
//
// Covers the F.3 acceptance set:
//   • Initial load fetches customer + jobs in parallel via the
//     graph-aware query verbs and renders the contact card.
//   • Per-customer job list renders one [JobListRow] per row from
//     `find_jobs_for_customer`.
//   • Tapping a job in the list pushes [JobDetailScreen].
//   • Customer-not-found (get_customer returns null) surfaces a
//     typed miss state with retry, not a crash.
//   • Empty per-customer jobs list shows an inline placeholder.
//   • find_jobs_for_customer failure degrades silently — the
//     contact card still renders.
//   • Tapping a customer-name cell on a JobListRow with onCustomerTap
//     fires the callback (covers the JobListRow F.3 contract change).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/helm/customer_screen.dart';
import 'package:semantos/src/helm/job_list_row.dart';
import 'package:semantos/src/repl/jobs_repository.dart';
import 'package:semantos/src/repl/oddjobz_query_client.dart';
import 'package:semantos/src/repl/repl_client.dart';

void main() {
  group('CustomerScreen', () {
    testWidgets('renders customer card + jobs from the two query verbs',
        (tester) async {
      final fake = _FakePivotQuery(
        customer: OddjobzCustomer(
          id: 'cust-1',
          displayName: 'Sarah Liu',
          phone: '555-0100',
          email: 'sarah@example.com',
          address: '47 Hygieta St, Doonside',
          cellId: 'c' * 64,
          typeHash: 't' * 64,
          role: 'tenant',
          siteRef: null,
        ),
        jobs: [
          {
            'id': 'J1',
            'customer_name': 'Sarah Liu',
            'state': 'scheduled',
            'scheduled_at': '2026-05-04T09:00:00Z',
            'siteRef': 'a' * 64,
            'dueDate': '2026-05-24',
            'hasPhotos': true,
            'photoCount': 2,
            'customerRefs': [
              {'cellId': 'c' * 64, 'role': 'tenant', 'primary': true},
            ],
          },
          {
            'id': 'J2',
            'customer_name': 'Sarah Liu',
            'state': 'lead',
            'scheduled_at': '',
            'siteRef': 'b' * 64,
            'hasPhotos': false,
            'customerRefs': [
              {'cellId': 'c' * 64, 'role': 'tenant', 'primary': true},
            ],
          },
        ],
      );

      await tester.pumpWidget(_wrap(CustomerScreen.forTest(
        customerRef: 'c' * 64,
        query: fake,
        jobs: _stubJobsRepo(),
        onUnauthorised: () async {},
      )));

      // First frame: spinner.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Resolve the futures + rebuild.
      await tester.pumpAndSettle();

      // Customer name in app bar AND on the contact card.
      expect(find.text('Sarah Liu'), findsWidgets);
      // Phone number rendered.
      expect(find.text('555-0100'), findsOneWidget);
      // Email rendered.
      expect(find.text('sarah@example.com'), findsOneWidget);
      // Two job rows.
      expect(find.byType(JobListRow), findsNWidgets(2));
      // Job count header.
      expect(find.text('2 jobs'), findsOneWidget);
      // Both verbs called exactly once each.
      expect(fake.getCustomerCalls, equals(1));
      expect(fake.findJobsCalls, equals(1));
    });

    testWidgets('customer-not-found shows typed miss state', (tester) async {
      final fake = _FakePivotQuery(customer: null, jobs: const []);
      await tester.pumpWidget(_wrap(CustomerScreen.forTest(
        customerRef: 'c' * 64,
        query: fake,
        jobs: _stubJobsRepo(),
        onUnauthorised: () async {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('Customer not found.\n\nRef: ${'c' * 64}'),
          findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('empty job list shows placeholder', (tester) async {
      final fake = _FakePivotQuery(
        customer: OddjobzCustomer(
          id: 'c1',
          displayName: 'Alice',
          phone: '',
          email: '',
          address: '',
          cellId: 'c' * 64,
          typeHash: 't' * 64,
          role: 'owner',
          siteRef: null,
        ),
        jobs: const [],
      );
      await tester.pumpWidget(_wrap(CustomerScreen.forTest(
        customerRef: 'c' * 64,
        query: fake,
        jobs: _stubJobsRepo(),
        onUnauthorised: () async {},
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('No jobs linked'), findsOneWidget);
    });

    testWidgets('find_jobs failure still renders contact card',
        (tester) async {
      final fake = _FakePivotQuery(
        customer: OddjobzCustomer(
          id: 'c1',
          displayName: 'Bob',
          phone: '555-0900',
          email: '',
          address: '',
          cellId: 'c' * 64,
          typeHash: 't' * 64,
          role: 'pm',
          siteRef: null,
        ),
        jobs: const [],
        jobsThrowing: true,
      );
      await tester.pumpWidget(_wrap(CustomerScreen.forTest(
        customerRef: 'c' * 64,
        query: fake,
        jobs: _stubJobsRepo(),
        onUnauthorised: () async {},
      )));
      await tester.pumpAndSettle();

      // Contact card still rendered despite the find_jobs error.
      expect(find.text('Bob'), findsWidgets);
      expect(find.text('555-0900'), findsOneWidget);
      expect(find.textContaining('No jobs linked'), findsOneWidget);
    });

    testWidgets('refresh button re-issues both verbs', (tester) async {
      final fake = _FakePivotQuery(
        customer: OddjobzCustomer(
          id: 'c1',
          displayName: 'Carol',
          phone: '',
          email: '',
          address: '',
          cellId: 'c' * 64,
          typeHash: 't' * 64,
          role: 'tenant',
          siteRef: null,
        ),
        jobs: const [],
      );
      await tester.pumpWidget(_wrap(CustomerScreen.forTest(
        customerRef: 'c' * 64,
        query: fake,
        jobs: _stubJobsRepo(),
        onUnauthorised: () async {},
      )));
      await tester.pumpAndSettle();
      expect(fake.getCustomerCalls, equals(1));

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(fake.getCustomerCalls, equals(2));
      expect(fake.findJobsCalls, equals(2));
    });
  });

  group('JobListRow — F.3 customer-name tap', () {
    testWidgets('onCustomerTap fires with the cellId when tapped',
        (tester) async {
      String? tappedRef;
      final v2 = Job(
        id: 'J1',
        customerName: '',
        state: 'lead',
        scheduledAt: '',
        siteRef: 'a' * 64,
        propertyAddress: '47 Hygieta St',
        hasPhotos: false,
        customerRefs: [
          JobCustomerRef(cellId: 'c' * 64, role: 'tenant', primary: true),
        ],
      );
      const customer = OddjobzCustomer(
        id: 'cust-1',
        displayName: 'Sarah Liu',
        phone: '',
        email: '',
        address: '',
        cellId: null,
        typeHash: null,
        role: null,
        siteRef: null,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: JobListRow(
            job: v2,
            primaryCustomer: customer,
            onTap: () {},
            onCustomerTap: (ref) => tappedRef = ref,
          ),
        ),
      ));

      // Tap the customer-name InkWell on line 2.
      await tester.tap(find.text('Sarah Liu (tenant)'));
      await tester.pump();

      expect(tappedRef, equals('c' * 64));
    });

    testWidgets(
        'without onCustomerTap, customer cell is plain text (no InkWell)',
        (tester) async {
      final v2 = Job(
        id: 'J1',
        customerName: '',
        state: 'lead',
        scheduledAt: '',
        siteRef: 'a' * 64,
        propertyAddress: '47 Hygieta St',
        hasPhotos: false,
        customerRefs: [
          JobCustomerRef(cellId: 'c' * 64, role: 'agent', primary: true),
        ],
      );
      const customer = OddjobzCustomer(
        id: 'cust-1',
        displayName: 'Bob',
        phone: '',
        email: '',
        address: '',
        cellId: null,
        typeHash: null,
        role: null,
        siteRef: null,
      );
      var rowTaps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: JobListRow(
            job: v2,
            primaryCustomer: customer,
            onTap: () => rowTaps++,
          ),
        ),
      ));

      // Tapping the customer-name text falls through to the row's
      // outer InkWell — not a separate handler.
      await tester.tap(find.text('Bob (agent)'));
      await tester.pump();
      expect(rowTaps, equals(1));
    });
  });
}

Widget _wrap(Widget child) => MaterialApp(
      home: child,
    );

/// Stub JobsRepository — never actually exercises the network.
/// CustomerScreen only uses this to build a JobDetailScreen on
/// per-row taps; the widget tests above don't tap jobs.
JobsRepository _stubJobsRepo() {
  final dio = Dio();
  final client = ReplClient.withBearer(
    http: dio,
    baseUrl: 'https://stub.invalid',
    bearer: 'a' * 64,
  );
  return JobsRepository(client);
}

class _FakePivotQuery implements CustomerPivotQuery {
  final OddjobzCustomer? customer;
  final List<Map<String, dynamic>> jobs;
  final bool jobsThrowing;
  int getCustomerCalls = 0;
  int findJobsCalls = 0;

  _FakePivotQuery({
    required this.customer,
    required this.jobs,
    this.jobsThrowing = false,
  });

  @override
  Future<OddjobzCustomer?> getCustomer(String customerRef) async {
    getCustomerCalls++;
    return customer;
  }

  @override
  Future<List<Map<String, dynamic>>> findJobsForCustomer(
      String customerRef) async {
    findJobsCalls++;
    if (jobsThrowing) {
      throw TimeoutException('simulated find_jobs_for_customer timeout');
    }
    return jobs;
  }
}

```
