---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/repositories/jobs_repository_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.130772+00:00
---

# apps/semantos/test/repositories/jobs_repository_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/repositories/job.dart';
import 'package:semantos/src/repositories/jobs_repository.dart';
import 'package:semantos/src/rpc/brain_rpc_client.dart';

/// Fake RpcCaller capturing calls + returning canned responses.
class FakeRpc implements RpcCaller {
  final List<String> replCalls = [];
  Map<String, dynamic>? lastCellQueryFilter;
  Map<String, dynamic> cellQueryResult;

  FakeRpc({this.cellQueryResult = const {'jobs': []}});

  @override
  Future<Map<String, dynamic>> cellQuery(String typeHash, {Map<String, dynamic>? filter}) async {
    expect(typeHash, 'oddjobz.job.v2');
    lastCellQueryFilter = filter;
    return cellQueryResult;
  }

  @override
  Future<String> replEval(String cmd) async {
    replCalls.add(cmd);
    return 'ok';
  }

  @override
  Future<Map<String, dynamic>> call(String method, [Map<String, dynamic>? params]) async => {};
}

void main() {
  Map<String, dynamic> job(String id, String state, {String name = 'Acme'}) => {
        'id': id,
        'state': state,
        'customer_name': name,
        'propertyAddress': '1 Test St',
      };

  group('reads', () {
    test('findJobs maps the {jobs:[…]} envelope to Job models', () async {
      final rpc = FakeRpc(cellQueryResult: {
        'jobs': [job('j1', 'lead'), job('j2', 'in_progress')],
      });
      final jobs = await JobsRepository(rpc).findJobs();
      expect(jobs.length, 2);
      expect(jobs.first.id, 'j1');
      expect(jobs.first.customerName, 'Acme');
      expect(jobs.first.propertyAddress, '1 Test St');
      expect(rpc.lastCellQueryFilter, isNull);
    });

    test('findJobs(state:) passes a filter', () async {
      final rpc = FakeRpc(cellQueryResult: {'jobs': [job('j1', 'lead')]});
      await JobsRepository(rpc).findJobs(state: 'lead');
      expect(rpc.lastCellQueryFilter, {'state': 'lead'});
    });

    test('findGrouped buckets by FSM section', () async {
      final rpc = FakeRpc(cellQueryResult: {
        'jobs': [
          job('j1', 'lead'), // needsAttention
          job('j2', 'in_progress'), // active
          job('j3', 'paid'), // recent
        ],
      });
      final g = await JobsRepository(rpc).findGrouped();
      expect(g[JobBucket.needsAttention]!.single.id, 'j1');
      expect(g[JobBucket.active]!.single.id, 'j2');
      expect(g[JobBucket.recent]!.single.id, 'j3');
    });

    test('findJob filters client-side', () async {
      final rpc = FakeRpc(cellQueryResult: {
        'jobs': [job('j1', 'lead'), job('j2', 'quoted')],
      });
      final j = await JobsRepository(rpc).findJob('j2');
      expect(j, isNotNull);
      expect(j!.state, 'quoted');
      expect(await JobsRepository(rpc).findJob('nope'), isNull);
    });
  });

  group('FSM transitions emit canonical repl strings', () {
    late FakeRpc rpc;
    late JobsRepository repo;
    setUp(() {
      rpc = FakeRpc();
      repo = JobsRepository(rpc);
    });

    test('quote/start/complete/markPaid/close', () async {
      await repo.quoteJob('j1');
      await repo.startJob('j1');
      await repo.completeJob('j1');
      await repo.markJobPaid('j1');
      await repo.closeJob('j1');
      expect(rpc.replCalls, [
        'quote job j1',
        'start job j1',
        'complete job j1',
        'mark job paid j1',
        'close job j1',
      ]);
    });

    test('schedule with --at and invoice with total_cents', () async {
      await repo.scheduleJob('j1', at: DateTime.utc(2026, 6, 9, 14, 30));
      await repo.invoiceJob('j1', totalCents: 12500);
      expect(rpc.replCalls[0], 'schedule job j1 --at 2026-06-09T14:30:00.000Z');
      expect(rpc.replCalls[1], 'invoice job j1 total_cents 12500');
    });

    test('schedule/invoice without optional args omit the suffix', () async {
      await repo.scheduleJob('j1');
      await repo.invoiceJob('j1');
      expect(rpc.replCalls, ['schedule job j1', 'invoice job j1']);
    });
  });
}

```
