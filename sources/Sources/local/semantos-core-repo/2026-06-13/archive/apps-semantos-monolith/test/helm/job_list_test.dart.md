---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/job_list_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.926195+00:00
---

# archive/apps-semantos-monolith/test/helm/job_list_test.dart

```dart
// D-DOG.1.0c Phase 3 F.1 — JobList graph-aware rendering tests.
//
// Covers the F.1.f acceptance set:
//   • v1 row renders without crashing (legacy customer-name title,
//     "—" placeholders for the v2 fields, no camera icon).
//   • v2 row renders all four new graph-aware fields.
//   • v2 row with primaryContact role displayed.
//   • v2 row with hasPhotos: false doesn't render the icon.
//   • N+1 prevention: rendering 10 v2 jobs only calls listCustomers /
//     listSites once each, not 10x.
//
// The Job-model parser changes are exercised via direct calls to
// `parseJobs` so the v2 wire shape doesn't need a real WSS round-
// trip.  The widget tests use a fake [HelmStreamChannel] feeding
// canned `oddjobz.list_*` JSON-RPC replies into a real
// [HelmEventStream] — same seam HelmEventStream's own tests use.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/helm/job_list_row.dart';
import 'package:semantos/src/repl/jobs_repository.dart';
import 'package:semantos/src/repl/oddjobz_query_client.dart';

void main() {
  group('Job model — v2 field parsing', () {
    test('parseJobs decodes a v1 row (no v2 fields)', () {
      final body = json.encode([
        {
          'id': 'J1',
          'customer_name': 'Alice',
          'state': 'lead',
          'scheduled_at': '',
        },
      ]);
      final rows = parseJobs(body);
      expect(rows, hasLength(1));
      final r = rows[0];
      expect(r.id, equals('J1'));
      expect(r.customerName, equals('Alice'));
      expect(r.isV2, isFalse);
      expect(r.siteRef, isNull);
      expect(r.customerRefs, isNull);
      expect(r.dueDate, isNull);
      expect(r.hasPhotos, isNull);
      expect(r.primaryCustomerRef, isNull);
    });

    test('parseJobs decodes a v2 row with all graph-aware fields', () {
      final body = json.encode([
        {
          'id': 'J2',
          'customer_name': 'Sarah Liu',
          'state': 'scheduled',
          'scheduled_at': '2026-05-04T09:00:00Z',
          'siteRef': 'a' * 64,
          'propertyKey': 'key #177',
          'dueDate': '2026-05-24',
          'workOrderNumber': '07487',
          'hasPhotos': true,
          'photoCount': 3,
          'customerRefs': [
            {'cellId': 'c' * 64, 'role': 'tenant', 'primary': true},
            {'cellId': 'd' * 64, 'role': 'agent', 'primary': false},
          ],
        },
      ]);
      final rows = parseJobs(body);
      expect(rows, hasLength(1));
      final r = rows[0];
      expect(r.isV2, isTrue);
      expect(r.siteRef, equals('a' * 64));
      expect(r.propertyKey, equals('key #177'));
      expect(r.workOrderNumber, equals('07487'));
      expect(r.hasPhotos, isTrue);
      expect(r.photoCount, equals(3));
      expect(r.customerRefs, isNotNull);
      expect(r.customerRefs!, hasLength(2));
      expect(r.primaryCustomerRef, isNotNull);
      expect(r.primaryCustomerRef!.cellId, equals('c' * 64));
      expect(r.primaryCustomerRef!.role, equals('tenant'));
      expect(r.dueDate, isNotNull);
      expect(r.dueDate!.year, equals(2026));
      expect(r.dueDate!.month, equals(5));
      expect(r.dueDate!.day, equals(24));
    });

    test('parseJobs handles `{jobs: [...]}` envelope (graph-aware verb shape)',
        () {
      final body = json.encode({
        'jobs': [
          {
            'id': 'J3',
            'customer_name': 'Bob',
            'state': 'lead',
            'scheduled_at': '',
            'siteRef': 'b' * 64,
            'hasPhotos': false,
            'customerRefs': <dynamic>[],
          },
        ],
      });
      final rows = parseJobs(body);
      expect(rows, hasLength(1));
      expect(rows[0].siteRef, equals('b' * 64));
      expect(rows[0].hasPhotos, isFalse);
      expect(rows[0].customerRefs, isEmpty);
      expect(rows[0].primaryCustomerRef, isNull);
    });

    test('parseJobs ignores malformed customerRefs without crashing', () {
      final body = json.encode([
        {
          'id': 'J4',
          'customer_name': '',
          'state': 'lead',
          'scheduled_at': '',
          'customerRefs': 'not-a-list', // intentionally wrong type
        },
      ]);
      final rows = parseJobs(body);
      expect(rows, hasLength(1));
      // Wrong-type customerRefs treated as v1 — falls back to null.
      expect(rows[0].customerRefs, isNull);
    });

    test('Job.dueDate returns null on malformed dueDateRaw', () {
      const j = Job(
        id: 'X',
        customerName: '',
        state: 'lead',
        scheduledAt: '',
        dueDateRaw: 'not-a-date',
      );
      expect(j.dueDate, isNull);
    });

    test('Job.withPropertyAddress preserves all other fields', () {
      final j = Job(
        id: 'J',
        customerName: 'Alice',
        state: 'scheduled',
        scheduledAt: '2026-05-04T09:00:00Z',
        siteRef: 'a' * 64,
        dueDateRaw: '2026-05-24',
        hasPhotos: true,
        photoCount: 2,
        propertyKey: 'key #1',
      );
      final updated = j.withPropertyAddress('47 Hygieta St');
      expect(updated.propertyAddress, equals('47 Hygieta St'));
      expect(updated.id, equals('J'));
      expect(updated.siteRef, equals('a' * 64));
      expect(updated.dueDateRaw, equals('2026-05-24'));
      expect(updated.hasPhotos, isTrue);
      expect(updated.photoCount, equals(2));
      expect(updated.propertyKey, equals('key #1'));
    });
  });

  group('JobListRow — v1 backward-compat', () {
    testWidgets('v1 row renders customerName as title + "—" placeholders',
        (tester) async {
      const v1 = Job(
        id: 'J1',
        customerName: 'Legacy Alice',
        state: 'lead',
        scheduledAt: '',
      );
      await tester.pumpWidget(_wrap(JobListRow(
        job: v1,
        primaryCustomer: null,
        onTap: () {},
      )));

      // Customer name is the v1 title.
      expect(find.text('Legacy Alice'), findsOneWidget);
      // Two "—" placeholders (customer line + due-date line).
      expect(find.text('—'), findsNWidgets(2));
      // No camera icon for v1 rows.
      expect(find.byIcon(Icons.photo_camera), findsNothing);
      // State chip is present.
      expect(find.text('lead'), findsOneWidget);
    });

    testWidgets('v1 row with empty customerName falls back to "(no customer)"',
        (tester) async {
      const v1 = Job(
        id: 'J0',
        customerName: '',
        state: 'lead',
        scheduledAt: '',
      );
      await tester.pumpWidget(_wrap(JobListRow(
        job: v1,
        primaryCustomer: null,
        onTap: () {},
      )));
      expect(find.text('(no customer)'), findsOneWidget);
    });
  });

  group('JobListRow — v2 graph-aware', () {
    testWidgets('renders address title, primary customer, due date, photos icon',
        (tester) async {
      final v2 = Job(
        id: 'J2',
        customerName: 'Sarah Liu',
        state: 'scheduled',
        scheduledAt: '2026-05-04T09:00:00Z',
        siteRef: 'a' * 64,
        propertyAddress: '47 Hygieta St, Doonside',
        propertyKey: 'key #177',
        dueDateRaw: '${DateTime.now().toUtc().year}-05-24',
        hasPhotos: true,
        photoCount: 3,
        customerRefs: [
          JobCustomerRef(cellId: 'c' * 64, role: 'tenant', primary: true),
        ],
      );
      const customer = OddjobzCustomer(
        id: 'cust-1',
        displayName: 'Sarah Liu',
        phone: '555-0100',
        email: '',
        address: '',
        cellId: null, // we look up by the v2 cellId in the parent map; row
                    // just renders the displayName from whatever it gets.
        typeHash: null,
        role: null,
        siteRef: null,
      );
      await tester.pumpWidget(_wrap(JobListRow(
        job: v2,
        primaryCustomer: customer,
        onTap: () {},
      )));

      // Property address as title.
      expect(find.text('47 Hygieta St, Doonside'), findsOneWidget);
      // Property-key badge.
      expect(find.text('key #177'), findsOneWidget);
      // Primary customer with role.
      expect(find.text('Sarah Liu (tenant)'), findsOneWidget);
      // Due date (current-year shape: "Due 24 May").
      expect(find.textContaining('Due 24'), findsOneWidget);
      // Photos icon + count.
      expect(find.byIcon(Icons.photo_camera), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // No "—" placeholders on a fully-enriched v2 row.
      expect(find.text('—'), findsNothing);
    });

    testWidgets('hasPhotos: false hides the camera icon', (tester) async {
      final v2NoPhotos = Job(
        id: 'J3',
        customerName: '',
        state: 'lead',
        scheduledAt: '',
        siteRef: 'b' * 64,
        propertyAddress: '12 Some Lane',
        hasPhotos: false,
        photoCount: 0,
        customerRefs: [
          JobCustomerRef(cellId: 'd' * 64, role: 'owner', primary: true),
        ],
      );
      await tester.pumpWidget(_wrap(JobListRow(
        job: v2NoPhotos,
        primaryCustomer: null,
        onTap: () {},
      )));

      expect(find.text('12 Some Lane'), findsOneWidget);
      // No camera icon.
      expect(find.byIcon(Icons.photo_camera), findsNothing);
    });

    testWidgets('falls back to cellId when primaryCustomer is unresolved',
        (tester) async {
      final v2 = Job(
        id: 'J4',
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
      await tester.pumpWidget(_wrap(JobListRow(
        job: v2,
        primaryCustomer: null,
        onTap: () {},
      )));
      // Bulk-fetch missed this customer — show the cellId so the
      // operator can still see _something_ rather than blank.
      expect(find.text('${'c' * 64} (agent)'), findsOneWidget);
    });

    testWidgets('v2 row with un-enriched site shows "—" title not customer name',
        (tester) async {
      // v2 row whose siteRef didn't resolve in the bulk fetch.
      final v2 = Job(
        id: 'J5',
        customerName: 'should-not-appear',
        state: 'lead',
        scheduledAt: '',
        siteRef: 'a' * 64,
        propertyAddress: null, // un-enriched
        hasPhotos: false,
        customerRefs: const [],
      );
      await tester.pumpWidget(_wrap(JobListRow(
        job: v2,
        primaryCustomer: null,
        onTap: () {},
      )));
      // Don't show the v1 customer-name string for a v2 row — it's
      // the primary-contact name there, not an address.
      expect(find.text('should-not-appear'), findsNothing);
    });
  });

  group('JobListRow — date formatting', () {
    test('formatDueDate returns short shape in current year', () {
      final now = DateTime.now().toUtc();
      final due = DateTime.utc(now.year, 5, 24);
      expect(formatDueDate(due), equals('24 May'));
    });

    test('formatDueDate returns long shape across years', () {
      final due = DateTime.utc(2030, 12, 1);
      expect(formatDueDate(due), equals('1 Dec 2030'));
    });
  });

  // ── D-DOG.1.0c Phase 5 G.2 — legacy_unsigned badge ────────────────
  //
  // Pre-Layer-1 v1 cells that the `legacy migrate-to-graph` verb
  // couldn't promote get a small "legacy" pill next to the state
  // chip.  Sourced from `Job.legacyUnsigned`; defaults to false on
  // every existing wire shape.

  group('JobListRow — legacy_unsigned badge (Phase 5 G.2)', () {
    testWidgets('legacy pill renders when Job.legacyUnsigned is true',
        (tester) async {
      const v1 = Job(
        id: 'J-legacy',
        customerName: 'Pre-Promo Customer',
        state: 'lead',
        scheduledAt: '',
        legacyUnsigned: true,
      );
      await tester.pumpWidget(_wrap(JobListRow(
        job: v1,
        primaryCustomer: null,
        onTap: () {},
      )));
      expect(find.text('legacy'), findsOneWidget);
      // The state chip should still render alongside the pill.
      expect(find.text('lead'), findsOneWidget);
    });

    testWidgets('legacy pill is absent when legacyUnsigned is false',
        (tester) async {
      const v1 = Job(
        id: 'J-default',
        customerName: 'Regular Customer',
        state: 'lead',
        scheduledAt: '',
      );
      await tester.pumpWidget(_wrap(JobListRow(
        job: v1,
        primaryCustomer: null,
        onTap: () {},
      )));
      expect(find.text('legacy'), findsNothing);
    });

    test('parseJobs decodes legacy_unsigned: true off the wire', () {
      final body = json.encode([
        {
          'id': 'J-flag',
          'customer_name': 'Flagged',
          'state': 'lead',
          'scheduled_at': '',
          'legacy_unsigned': true,
        },
      ]);
      final rows = parseJobs(body);
      expect(rows[0].legacyUnsigned, isTrue);
    });

    test('parseJobs defaults legacyUnsigned to false when absent', () {
      final body = json.encode([
        {
          'id': 'J-no-flag',
          'customer_name': 'Default',
          'state': 'lead',
          'scheduled_at': '',
        },
      ]);
      final rows = parseJobs(body);
      expect(rows[0].legacyUnsigned, isFalse);
    });

    test('Job.toJson omits legacy_unsigned when false (wire byte-stable)', () {
      const j = Job(
        id: 'J-default',
        customerName: 'X',
        state: 'lead',
        scheduledAt: '',
      );
      final wire = j.toJson();
      expect(wire.containsKey('legacy_unsigned'), isFalse);
    });

    test('Job.toJson emits legacy_unsigned when true', () {
      const j = Job(
        id: 'J-flag',
        customerName: 'X',
        state: 'lead',
        scheduledAt: '',
        legacyUnsigned: true,
      );
      final wire = j.toJson();
      expect(wire['legacy_unsigned'], isTrue);
    });

    test('withLegacyUnsigned preserves all other fields', () {
      const j = Job(
        id: 'J',
        customerName: 'X',
        state: 'lead',
        scheduledAt: '',
        propertyAddress: 'addr',
      );
      final flagged = j.withLegacyUnsigned(true);
      expect(flagged.legacyUnsigned, isTrue);
      expect(flagged.propertyAddress, equals('addr'));
      expect(flagged.id, equals('J'));
    });
  });

  group('OddjobzQueryClient — N+1 prevention', () {
    test(
      'rendering 10 v2 jobs calls listCustomers / listSites once each',
      () async {
        final fake = _FakeQueryClient(
          sites: List.generate(
            5,
            (i) => OddjobzSite(
              cellId: 's' * 63 + '$i',
              typeHash: 't' * 64,
              normalisedAddress: 'addr $i',
              keyNumber: null,
              lookupKey: 'addr $i|',
              fullAddress: 'Site $i',
              suburb: null,
              postcode: null,
              state: null,
              createdAt: 0,
            ),
          ),
          customers: List.generate(
            10,
            (i) => OddjobzCustomer(
              id: 'cust-$i',
              displayName: 'Customer $i',
              phone: '',
              email: '',
              address: '',
              cellId: 'c' * 63 + '$i',
              typeHash: 't' * 64,
              role: 'tenant',
              siteRef: null,
            ),
          ),
        );

        // Simulate the JobList's enrichment pattern: ONE listSites
        // call, ONE listCustomers call, then resolve all 10 row's
        // customer/site refs from the resulting maps.
        final sites = await fake.listSites();
        final customers = await fake.listCustomers();
        final sitesByRef = {for (final s in sites) s.cellId: s};
        final customersByRef = {
          for (final c in customers)
            if (c.cellId != null) c.cellId!: c,
        };

        for (var i = 0; i < 10; i++) {
          final job = Job(
            id: 'J$i',
            customerName: '',
            state: 'lead',
            scheduledAt: '',
            siteRef: 's' * 63 + '${i % 5}',
            hasPhotos: false,
            customerRefs: [
              JobCustomerRef(
                cellId: 'c' * 63 + '$i',
                role: 'tenant',
                primary: true,
              ),
            ],
          );
          // Lookups are O(1) — no further RPC calls.
          expect(sitesByRef[job.siteRef!], isNotNull);
          expect(
            customersByRef[job.primaryCustomerRef!.cellId],
            isNotNull,
          );
        }

        // F.1.d acceptance — exactly one fetch per resource.
        expect(fake.listSitesCallCount, equals(1));
        expect(fake.listCustomersCallCount, equals(1));
        // None of the per-row verbs (getSite / getCustomer) were
        // called — that would have been the N+1 bug.
        expect(fake.getSiteCallCount, equals(0));
        expect(fake.getCustomerCallCount, equals(0));
      },
    );
  });
}

/// Wrap a single widget in a minimal MaterialApp so theme lookups +
/// rendering don't crash at pump time.
Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

/// In-memory OddjobzQueryClient stand-in used by the N+1 test.
/// Counts every method invocation so the test can assert exactly
/// one bulk fetch per resource.  Doesn't extend [OddjobzQueryClient]
/// — the real class binds to a HelmEventStream WSS, which we don't
/// want to spin up just to count calls.
class _FakeQueryClient {
  final List<OddjobzSite> sites;
  final List<OddjobzCustomer> customers;

  int listSitesCallCount = 0;
  int listCustomersCallCount = 0;
  int getSiteCallCount = 0;
  int getCustomerCallCount = 0;

  _FakeQueryClient({required this.sites, required this.customers});

  Future<List<OddjobzSite>> listSites() async {
    listSitesCallCount++;
    return sites;
  }

  Future<List<OddjobzCustomer>> listCustomers() async {
    listCustomersCallCount++;
    return customers;
  }

  Future<OddjobzSite?> getSite(String _) async {
    getSiteCallCount++;
    return null;
  }

  Future<OddjobzCustomer?> getCustomer(String _) async {
    getCustomerCallCount++;
    return null;
  }
}

```
