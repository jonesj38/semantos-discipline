---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/operator_find_tab_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.457353+00:00
---

# cartridges/oddjobz/experience/test/operator_find_tab_test.dart

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/src/operator/oddjobz_rpc.dart';
import 'package:oddjobz_experience/src/operator/operator_find_tab.dart';

void main() {
  testWidgets('Find customer results open canonical detail screen', (
    tester,
  ) async {
    final rpc = _FakeOddjobzRpc({
      'jobs': const [],
      'sites': const [],
      'customers': const [
        {
          'cellHash': 'cust-1',
          'name': 'Tenant One',
          'phone': '+61400000000',
          'role': 'tenant',
          'notes': ['prefers sms'],
        },
      ],
      'visits': const [],
      'quotes': const [],
      'invoices': const [],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OperatorFindTab(rpc: rpc)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Customers'));
    await tester.pumpAndSettle();

    expect(find.text('Tenant One'), findsOneWidget);
    await tester.tap(find.text('Tenant One'));
    await tester.pumpAndSettle();

    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('CANONICAL FIELDS'), findsOneWidget);
    expect(find.text('cust-1'), findsWidgets);
    expect(find.text('role'), findsOneWidget);
    expect(find.text('tenant'), findsOneWidget);
  });
}

class _FakeOddjobzRpc implements OddjobzRpc {
  _FakeOddjobzRpc(this.rowsByNoun);

  final Map<String, List<Map<String, Object?>>> rowsByNoun;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? params,
  ]) async => <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> cellQuery(
    String typeHash, {
    Map<String, dynamic>? filter,
  }) async => <String, dynamic>{};

  @override
  Future<String> replEval(String cmd) async {
    final noun = cmd.replaceFirst('query ', '').trim();
    return jsonEncode(rowsByNoun[noun] ?? const []);
  }
}

```
