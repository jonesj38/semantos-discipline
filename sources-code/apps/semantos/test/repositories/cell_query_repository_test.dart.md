---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/repositories/cell_query_repository_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.130501+00:00
---

# apps/semantos/test/repositories/cell_query_repository_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/repositories/cell_query_repository.dart';
import 'package:semantos/src/rpc/brain_rpc_client.dart';

class FakeRpc implements RpcCaller {
  String? lastType;
  Map<String, dynamic>? lastFilter;
  Map<String, dynamic> result;
  FakeRpc(this.result);

  @override
  Future<Map<String, dynamic>> cellQuery(String typeHash, {Map<String, dynamic>? filter}) async {
    lastType = typeHash;
    lastFilter = filter;
    return result;
  }

  @override
  Future<String> replEval(String cmd) async => '';
  @override
  Future<Map<String, dynamic>> call(String method, [Map<String, dynamic>? params]) async => {};
}

void main() {
  test('list pulls rows from a customers envelope (collection key agnostic)', () async {
    final rpc = FakeRpc({
      'customers': [
        {'id': 'c1', 'display_name': 'Acme'},
        {'id': 'c2', 'display_name': 'Globex'},
      ],
    });
    final rows = await CellQueryRepository(rpc).list('oddjobz.customer.v2');
    expect(rpc.lastType, 'oddjobz.customer.v2');
    expect(rows.length, 2);
    expect(rows.first['display_name'], 'Acme');
  });

  test('list works for a different collection key (quotes) without code change', () async {
    final rpc = FakeRpc({
      'quotes': [
        {'id': 'q1', 'cost_min': 100},
      ],
    });
    final rows = await CellQueryRepository(rpc).list('oddjobz.quote.v2');
    expect(rows.single['cost_min'], 100);
  });

  test('passes a filter through', () async {
    final rpc = FakeRpc({'jobs': []});
    await CellQueryRepository(rpc).list('oddjobz.job.v2', filter: {'state': 'lead'});
    expect(rpc.lastFilter, {'state': 'lead'});
  });

  test('empty / no-list envelope yields []', () async {
    expect(await CellQueryRepository(FakeRpc({})).list('x'), isEmpty);
    expect(await CellQueryRepository(FakeRpc({'count': 0})).list('x'), isEmpty);
  });

  test('non-map rows are skipped', () async {
    final rpc = FakeRpc({
      'jobs': [
        {'id': 'j1'},
        'garbage',
        42,
      ],
    });
    final rows = await CellQueryRepository(rpc).list('oddjobz.job.v2');
    expect(rows.length, 1);
    expect(rows.single['id'], 'j1');
  });
}

```
