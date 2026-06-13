---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/operator_do_board_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.459237+00:00
---

# cartridges/oddjobz/experience/test/operator_do_board_test.dart

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/src/operator/oddjobz_rpc.dart';
import 'package:oddjobz_experience/src/operator/operator_shell.dart';

void main() {
  testWidgets('Do page groups jobs by canonical FSM state lanes', (
    tester,
  ) async {
    final rpc = _FakeOddjobzRpc({
      'jobs': [
        {
          'cellHash': 'job-lead',
          'state': 'lead',
          'display_name': 'Lead Customer',
          'summary': 'Needs qualification',
        },
        {
          'cellHash': 'job-visit',
          'state': 'visit_pending',
          'display_name': 'Visit Customer',
          'summary': 'Needs a site visit',
        },
        {
          'cellHash': 'job-paid',
          'state': 'paid',
          'display_name': 'Paid Customer',
          'summary': 'Paid and ready to close',
        },
      ],
      'sites': const [],
      'customers': const [],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: OperatorShell(rpc: rpc, onMePressed: () {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Do'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Jobs grouped by FSM state. Open a card to patch the conversation or advance the job.',
      ),
      findsOneWidget,
    );
    expect(find.text('LEAD'), findsOneWidget);
    expect(find.text('VISIT PENDING'), findsOneWidget);
    expect(find.text('Lead Customer'), findsOneWidget);
    expect(find.text('Visit Customer'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('PAID'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('PAID'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Paid Customer'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Paid Customer'), findsOneWidget);
    expect(
      find.text('Quote'),
      findsNothing,
      reason: 'old pending_quote lane should not drive Do',
    );
    expect(
      rpc.commands,
      containsAll(['query jobs', 'query sites', 'query customers']),
    );
  });
}

class _FakeOddjobzRpc implements OddjobzRpc {
  _FakeOddjobzRpc(this.rowsByNoun);

  final Map<String, List<Map<String, Object?>>> rowsByNoun;
  final List<String> commands = [];

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
    commands.add(cmd);
    final noun = cmd.replaceFirst('query ', '').trim();
    return jsonEncode(rowsByNoun[noun] ?? const []);
  }
}

```
