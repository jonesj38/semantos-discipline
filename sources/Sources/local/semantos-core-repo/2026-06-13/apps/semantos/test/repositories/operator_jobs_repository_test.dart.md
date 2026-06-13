---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/repositories/operator_jobs_repository_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.130222+00:00
---

# apps/semantos/test/repositories/operator_jobs_repository_test.dart

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/repositories/operator_jobs_repository.dart';
import 'package:semantos/src/rpc/brain_rpc_client.dart';

/// Fake RpcCaller returning a canned raw string per `query <noun>` command.
class FakeRpc implements RpcCaller {
  final Map<String, String> responses;
  final List<String> calls = [];
  FakeRpc(this.responses);

  @override
  Future<String> replEval(String cmd) async {
    calls.add(cmd);
    return responses[cmd] ?? '{}';
  }

  @override
  Future<Map<String, dynamic>> cellQuery(String typeHash,
          {Map<String, dynamic>? filter}) async =>
      {};

  @override
  Future<Map<String, dynamic>> call(String method,
          [Map<String, dynamic>? params]) async =>
      {};
}

void main() {
  const siteHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const custHash =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const agentHash =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
  const jobHash =
      'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

  group('OperatorJobsRepository.findJobs (substrate query + local resolve)', () {
    test('uses the `query` primitive for each cell type', () async {
      final rpc = FakeRpc({
        'query jobs': '{"jobs":[]}',
        'query sites': '{"sites":[]}',
        'query customers': '{"customers":[]}',
      });
      await OperatorJobsRepository(rpc).findJobs();
      expect(rpc.calls, containsAll(<String>[
        'query jobs',
        'query sites',
        'query customers',
      ]));
    });

    test('resolves site_ref → address and customer_refs → contact name',
        () async {
      final rpc = FakeRpc({
        'query jobs': jsonEncode({
          'jobs': [
            {
              'cellHash': jobHash,
              'state': 'lead',
              'summary': 'Leaking tap',
              'site_ref': siteHash,
              'customer_refs': [
                {'cell_id': custHash, 'role': 'tenant', 'primary': true},
              ],
              'work_order_number': 'WO-1',
              'has_pictures': true,
              'picture_count': 2,
              'services': ['plumbing', 'leak'],
            }
          ]
        }),
        'query sites': jsonEncode({
          'sites': [
            {'cellHash': siteHash, 'normalized_address': '10 List Lane, Brisbane'},
          ]
        }),
        'query customers': jsonEncode({
          'customers': [
            {'cellHash': custHash, 'name': 'Jo Smith', 'role': 'tenant', 'phone': '0400'},
          ]
        }),
      });
      final jobs = await OperatorJobsRepository(rpc).findJobs();
      expect(jobs.length, 1);
      final j = jobs.first;
      expect(j.id, jobHash); // cellHash = identity
      expect(j.customerName, 'Jo Smith'); // resolved from the customer cell
      expect(j.propertyAddress, '10 List Lane, Brisbane'); // from the site cell
      expect(j.description, 'Leaking tap');
      expect(j.workOrderNumber, 'WO-1');
      expect(j.hasPhotos, true);
      expect(j.photoCount, 2);
      expect(j.state, 'lead');
      expect(j.services, 'plumbing, leak');
    });

    test('point-of-contact: agent picked when there is no tenant', () async {
      final rpc = FakeRpc({
        'query jobs': jsonEncode({
          'jobs': [
            {
              'cellHash': jobHash,
              'state': 'lead',
              'customer_refs': [
                {'cell_id': agentHash, 'role': 'agent', 'primary': false},
              ],
            }
          ]
        }),
        'query sites': '{"sites":[]}',
        'query customers': jsonEncode({
          'customers': [
            {'cellHash': agentHash, 'name': 'Tanya Healy', 'role': 'agent'},
          ]
        }),
      });
      final jobs = await OperatorJobsRepository(rpc).findJobs();
      expect(jobs.first.customerName, 'Tanya Healy');
    });

    test('falls back to display_name (role suffix stripped) when unresolved',
        () async {
      final rpc = FakeRpc({
        'query jobs': jsonEncode({
          'jobs': [
            {
              'cellHash': jobHash,
              'state': 'lead',
              'display_name': 'Bob Owner (owner)',
              'customer_refs': <dynamic>[],
            }
          ]
        }),
        'query sites': '{"sites":[]}',
        'query customers': '{"customers":[]}',
      });
      final jobs = await OperatorJobsRepository(rpc).findJobs();
      expect(jobs.first.customerName, 'Bob Owner');
      expect(jobs.first.propertyAddress, '');
    });
  });
}

```
