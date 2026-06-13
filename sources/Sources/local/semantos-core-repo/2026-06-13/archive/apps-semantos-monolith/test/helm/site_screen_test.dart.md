---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/site_screen_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.927614+00:00
---

# archive/apps-semantos-monolith/test/helm/site_screen_test.dart

```dart
// D-DOG.1.0c Phase 3 F.2 — site-pivot screen tests.
//
// Covers the F.2 acceptance set:
//   • SiteScreen calls oddjobz.get_site + oddjobz.find_jobs_at_site
//     once each on load (no N+1 across the rendered jobs).
//   • Renders the site's fullAddress at the top + the jobs at the
//     site below using JobListRow.
//   • "Site not found" empty-state when the brain returns
//     `{site: null}` without crashing the screen.
//   • JobListRow's address-cell tap fires a separate callback that
//     does NOT fire the row's main onTap (the v2 site-pivot vs.
//     job-detail split lives in the row widget).

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/helm/job_list_row.dart';
import 'package:semantos/src/helm/site_screen.dart';
import 'package:semantos/src/repl/helm_event_stream.dart';
import 'package:semantos/src/repl/jobs_repository.dart';
import 'package:semantos/src/repl/oddjobz_query_client.dart';
import 'package:semantos/src/repl/repl_client.dart';
import 'package:semantos/src/repl/visits_repository.dart';

void main() {
  group('JobListRow — address-cell tap (F.2)', () {
    testWidgets('address tap fires onAddressTap and not row onTap',
        (tester) async {
      var addressTaps = 0;
      var rowTaps = 0;
      final v2 = Job(
        id: 'J1',
        customerName: 'Sarah Liu',
        state: 'scheduled',
        scheduledAt: '2026-05-04T09:00:00Z',
        siteRef: 'a' * 64,
        propertyAddress: '47 Hygieta St, Doonside',
        hasPhotos: false,
        customerRefs: const [
          JobCustomerRef(cellId: 'c0', role: 'tenant', primary: true),
        ],
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: JobListRow(
            job: v2,
            primaryCustomer: null,
            onTap: () => rowTaps++,
            onAddressTap: () => addressTaps++,
          ),
        ),
      ));

      await tester.tap(find.text('47 Hygieta St, Doonside'));
      await tester.pumpAndSettle();

      expect(addressTaps, equals(1));
      expect(rowTaps, equals(0),
          reason: 'address tap must not bubble to row onTap');
    });

    testWidgets('omitting onAddressTap leaves the row tappable as a unit',
        (tester) async {
      var rowTaps = 0;
      final v2 = Job(
        id: 'J1',
        customerName: 'Sarah Liu',
        state: 'scheduled',
        scheduledAt: '',
        siteRef: 'a' * 64,
        propertyAddress: '47 Hygieta St',
        hasPhotos: false,
        customerRefs: const [],
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: JobListRow(
            job: v2,
            primaryCustomer: null,
            onTap: () => rowTaps++,
            // onAddressTap intentionally omitted — the entire row
            // (address included) routes to onTap.
          ),
        ),
      ));

      await tester.tap(find.text('47 Hygieta St'));
      await tester.pumpAndSettle();
      expect(rowTaps, equals(1));
    });
  });

  group('SiteScreen — load + render', () {
    testWidgets('renders site address + jobs and counts each verb once',
        (tester) async {
      final query = _StubQueryClient(
        site: OddjobzSite(
          cellId: 's' * 64,
          typeHash: 't' * 64,
          normalisedAddress: '47 hygieta st doonside',
          keyNumber: 'key #177',
          lookupKey: '47 hygieta st doonside|key #177',
          fullAddress: '47 Hygieta St, Doonside',
          suburb: 'Doonside',
          postcode: '2767',
          state: 'NSW',
          createdAt: 0,
        ),
        jobsAtSite: [
          {
            'id': 'J1',
            'customer_name': 'Sarah',
            'state': 'scheduled',
            'scheduled_at': '',
            'siteRef': 's' * 64,
            'hasPhotos': false,
            'customerRefs': [
              {'cellId': 'c' * 64, 'role': 'tenant', 'primary': true},
            ],
          },
          {
            'id': 'J2',
            'customer_name': 'Bob',
            'state': 'lead',
            'scheduled_at': '',
            'siteRef': 's' * 64,
            'hasPhotos': false,
            'customerRefs': [
              {'cellId': 'd' * 64, 'role': 'owner', 'primary': true},
            ],
          },
        ],
        customers: const [
          OddjobzCustomer(
            id: 'cust-1',
            displayName: 'Sarah Liu',
            phone: '',
            email: '',
            address: '',
            cellId: 'c0',
            typeHash: null,
            role: null,
            siteRef: null,
          ),
        ],
      );

      await tester.pumpWidget(_wrap(query));
      await tester.pumpAndSettle();

      expect(find.text('47 Hygieta St, Doonside'),
          findsWidgets); // header + 2 row titles after enrichment
      expect(find.text('key #177 · Doonside NSW 2767'), findsOneWidget);
      // Section header includes the count.
      expect(find.text('Jobs at this site (2)'), findsOneWidget);

      // Verb call counts: exactly one per resource.
      expect(query.getSiteCalls, equals(1));
      expect(query.findJobsAtSiteCalls, equals(1));
      expect(query.listCustomersCalls, equals(1));
    });

    testWidgets('renders "Site not found" when the brain returns null',
        (tester) async {
      final query = _StubQueryClient(
        site: null,
        jobsAtSite: const [],
        customers: const [],
      );

      await tester.pumpWidget(_wrap(query));
      await tester.pumpAndSettle();

      expect(find.text('Site not found.'), findsOneWidget);
      expect(query.getSiteCalls, equals(1));
    });

    testWidgets('renders empty jobs list when the site has no jobs yet',
        (tester) async {
      final query = _StubQueryClient(
        site: OddjobzSite(
          cellId: 's' * 64,
          typeHash: 't' * 64,
          normalisedAddress: 'addr',
          keyNumber: null,
          lookupKey: 'addr|',
          fullAddress: '12 Empty Ln',
          suburb: null,
          postcode: null,
          state: null,
          createdAt: 0,
        ),
        jobsAtSite: const [],
        customers: const [],
      );

      await tester.pumpWidget(_wrap(query));
      await tester.pumpAndSettle();

      expect(find.text('12 Empty Ln'), findsOneWidget);
      expect(find.text('Jobs at this site (0)'), findsOneWidget);
      expect(find.text('No jobs at this site.'), findsOneWidget);
    });
  });
}

/// Helper: wrap [SiteScreen] in a MaterialApp with stub repositories.
/// The repos are only touched when the operator taps a row to push
/// JobDetail — these tests never do, so a no-op-Dio-backed pair is
/// enough.
Widget _wrap(_StubQueryClient query) {
  final repl = ReplClient.withBearer(
    http: Dio()..httpClientAdapter = _NoopAdapter(),
    baseUrl: 'https://oddjobtodd.test',
    bearer: 'a' * 64,
  );
  return MaterialApp(
    home: SiteScreen(
      siteRef: 's' * 64,
      oddjobzQuery: query,
      jobs: JobsRepository(repl),
      visits: VisitsRepository(repl),
      onUnauthorised: () async {},
    ),
  );
}

/// In-memory OddjobzQueryClient that overrides every verb the
/// SiteScreen calls.  The base constructor wants a HelmEventStream
/// — we pass a never-connected one (the stream is only used by the
/// methods we override away).
class _StubQueryClient extends OddjobzQueryClient {
  final OddjobzSite? site;
  final List<Map<String, dynamic>> jobsAtSite;
  final List<OddjobzCustomer> customers;

  int getSiteCalls = 0;
  int findJobsAtSiteCalls = 0;
  int listCustomersCalls = 0;

  _StubQueryClient({
    required this.site,
    required this.jobsAtSite,
    required this.customers,
  }) : super(_neverConnectedStream());

  @override
  Future<OddjobzSite?> getSite(String siteRef) async {
    getSiteCalls++;
    return site;
  }

  @override
  Future<List<Map<String, dynamic>>> findJobsAtSite(String siteRef) async {
    findJobsAtSiteCalls++;
    return jobsAtSite;
  }

  @override
  Future<List<OddjobzCustomer>> listCustomers() async {
    listCustomersCalls++;
    return customers;
  }
}

HelmEventStream _neverConnectedStream() => HelmEventStream(
      wssUrl: 'ws://example.test/api/v1/wallet',
      bearer: 'a' * 64,
      topics: const ['jobs'],
    );

class _NoopAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(<int>[], 200);
  }
}

```
