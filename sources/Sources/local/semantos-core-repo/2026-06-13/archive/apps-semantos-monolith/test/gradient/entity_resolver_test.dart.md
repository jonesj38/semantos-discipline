---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/gradient/entity_resolver_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.918371+00:00
---

# archive/apps-semantos-monolith/test/gradient/entity_resolver_test.dart

```dart
// Wave 9 PWA — EntityResolver unit tests.

import 'package:test/test.dart';

import 'package:semantos/src/gradient/entity_resolver.dart';
import 'package:semantos/src/repl/jobs_repository.dart'
    show Job, JobCustomerRef;

Job _job({
  required String id,
  required String customerName,
  String? address,
  List<JobCustomerRef>? refs,
}) {
  return Job(
    id: id,
    customerName: customerName,
    state: 'lead',
    scheduledAt: '',
    siteRef: null,
    propertyAddress: address,
    propertyKey: null,
    customerRefs: refs,
    dueDateRaw: null,
    workOrderNumber: null,
    hasPhotos: null,
    photoCount: null,
    legacyUnsigned: false,
  );
}

void main() {
  group('EntityResolver', () {
    final resolver = EntityResolver();

    test('E1 returns no_active_jobs when the list is empty', () {
      final r = resolver.resolve(
        activeJobs: const [],
        transcript: 'quote 750 for the pergola job',
      );
      expect(r, isA<ResolutionUnresolved>());
      expect((r as ResolutionUnresolved).code, 'no_active_jobs');
    });

    test('E2 returns no_tokens when transcript has no >=4-char words', () {
      final r = resolver.resolve(
        activeJobs: [_job(id: 'j1', customerName: 'Mel Collins')],
        transcript: 'a b c d',
      );
      expect(r, isA<ResolutionUnresolved>());
      expect((r as ResolutionUnresolved).code, 'no_tokens');
    });

    test('E3 matches the single highest-scoring job on address fragment',
        () {
      final jobs = [
        _job(
          id: 'job-cootharaba',
          customerName: 'Mel Collins',
          address: '142 Cootharaba Downs Rd, Cootharaba QLD 4565',
        ),
        _job(
          id: 'job-other',
          customerName: 'Other Customer',
          address: '55 Quarry Lane, Pomona',
        ),
      ];
      final r = resolver.resolve(
        activeJobs: jobs,
        transcript: 'send a quote for the cootharaba pergola damage',
      );
      expect(r, isA<ResolutionMatched>());
      final m = r as ResolutionMatched;
      expect(m.jobId, 'job-cootharaba');
      expect(m.reason, contains('cootharaba'));
    });

    test('E4 refuses to guess on a near-tie (ambiguous_match)', () {
      final jobs = [
        _job(id: 'j-wattle', customerName: 'wattle street'),
        _job(id: 'j-wattler', customerName: 'wattle street'),
      ];
      final r = resolver.resolve(
        activeJobs: jobs,
        transcript: 'fix the wattle street job',
      );
      expect(r, isA<ResolutionUnresolved>());
      expect((r as ResolutionUnresolved).code, 'ambiguous_match');
    });

    test('E5 picks the primary customer ref when available', () {
      final jobs = [
        _job(
          id: 'job-1',
          customerName: 'Pergola Owner',
          address: '16 Yellowood Cl, Tewantin',
          refs: [
            JobCustomerRef(cellId: 'cust-secondary', role: 'tenant', primary: false),
            JobCustomerRef(cellId: 'cust-primary', role: 'owner', primary: true),
          ],
        ),
      ];
      final r = resolver.resolve(
        activeJobs: jobs,
        transcript: 'quote yellowood pergola',
      );
      expect(r, isA<ResolutionMatched>());
      expect((r as ResolutionMatched).customerId, 'cust-primary');
    });

    test('E6 falls back to first customer ref when no primary flagged', () {
      final jobs = [
        _job(
          id: 'job-1',
          customerName: 'Pergola Owner',
          address: '16 Yellowood Cl, Tewantin',
          refs: [
            JobCustomerRef(cellId: 'cust-a', role: 'tenant', primary: false),
            JobCustomerRef(cellId: 'cust-b', role: 'tenant', primary: false),
          ],
        ),
      ];
      final r = resolver.resolve(
        activeJobs: jobs,
        transcript: 'yellowood pergola',
      );
      expect(r, isA<ResolutionMatched>());
      expect((r as ResolutionMatched).customerId, 'cust-a');
    });

    test('E7 customerId is null on v1 jobs (no refs)', () {
      final jobs = [
        _job(
          id: 'legacy-1',
          customerName: 'Legacy Customer Pergola',
        ),
      ];
      final r = resolver.resolve(
        activeJobs: jobs,
        transcript: 'pergola legacy quote',
      );
      expect(r, isA<ResolutionMatched>());
      expect((r as ResolutionMatched).customerId, isNull);
    });

    test('E8 picks taxonomy.where signal even when transcript is empty', () {
      final jobs = [
        _job(
          id: 'job-wattle',
          customerName: 'Plumber Co',
          address: '7 Wattle Street, Newtown',
        ),
      ];
      final r = resolver.resolve(
        activeJobs: jobs,
        taxonomyWhere: 'wattle street',
      );
      expect(r, isA<ResolutionMatched>());
      expect((r as ResolutionMatched).jobId, 'job-wattle');
    });
  });
}

```
