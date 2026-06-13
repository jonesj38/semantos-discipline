---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/hat_switch_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.926757+00:00
---

# archive/apps-semantos-monolith/test/helm/hat_switch_test.dart

```dart
// W1.5 — Hat switch integration tests (red → green).
//
// Tests that:
//   1. Switching from oddjobz hat to another changes the domain_flag
//      used by EventSubscriptionService (resubscribes to new URL).
//   2. The previous hat's entity cache is not visible under the new hat's
//      domain_flag after a switch (scoping isolation).
//
// These tests drive the services directly — no Flutter widget tree needed.
// HatSwitchCoordinator is a pure Dart object that HomeScreen._HomeScreenState
// delegates to for switchHat(); this keeps the logic testable without the
// Flutter widget lifecycle.

import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/repl/hat_context.dart';
import 'package:semantos/src/repl/hat_entity_repository.dart';
import 'package:semantos/src/repl/event_subscription_service.dart';

// ── Fake WebSocket channel (same pattern as event_subscription_service_test) ─

class _FakeEventChannel implements EventStreamChannel {
  final StreamController<dynamic> _toClient =
      StreamController<dynamic>.broadcast();
  final List<String> sent = <String>[];

  Uri? lastUri;

  @override
  Stream<dynamic> get stream => _toClient.stream;

  @override
  void sendText(String data) => sent.add(data);

  @override
  Future<void> close() async {
    if (!_toClient.isClosed) await _toClient.close();
  }
}

class _FakeChannelFactory {
  final List<_FakeEventChannel> created = [];
  Uri? lastUri;

  EventStreamChannel call(Uri uri) {
    lastUri = uri;
    final ch = _FakeEventChannel()..lastUri = uri;
    created.add(ch);
    return ch;
  }

  _FakeEventChannel get latest => created.last;
}

// ── In-memory repository helper ───────────────────────────────────────────

Future<HatEntityRepository> _openInMemoryRepo() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(),
  );
  return HatEntityRepository.fromDatabase(db);
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('Hat switch (W1.5)', () {
    test(
        'switching hat changes domain_flag used by EventSubscriptionService '
        '(new URL contains new hat)', () async {
      final factory = _FakeChannelFactory();

      final svc = EventSubscriptionService(
        brainWsUrl: 'ws://brain.local/api/v1',
        bearer: 'tok-abc',
        domainFlag: HatContext.oddjobz.domainFlag,
        reconnectBackoff: const [Duration(milliseconds: 1)],
        channelFactory: factory.call,
      );

      await svc.connect();
      expect(factory.created, hasLength(1));

      final firstUri = factory.lastUri!;
      expect(firstUri.queryParameters['hat'],
          equals('0x000101'),
          reason: 'initial hat should be oddjobz 0x000101');

      // Switch to a different hat (domain flag 0x000202).
      const newHat = HatContext(domainFlag: 0x000202, extensionId: 'otherjobz');
      await svc.updateHat(newHat.domainFlag);

      // A second channel must have been created for the new hat.
      expect(factory.created, hasLength(2));
      final secondUri = factory.lastUri!;
      expect(secondUri.queryParameters['hat'],
          equals('0x000202'),
          reason: 'after switch the URL should use the new domain_flag');

      await svc.dispose();
    });

    test(
        'previous hat entity cache is not visible under new hat domain_flag',
        () async {
      final repo = await _openInMemoryRepo();

      // Seed oddjobz data.
      await repo.upsert(HatEntity(
        id: 'job-oddjobz-1',
        domainFlag: HatContext.oddjobz.domainFlag,
        state: 'quoted',
        scheduledAt: '',
        entityJson: json.encode({'id': 'job-oddjobz-1'}),
        updatedAt: '2026-05-09T00:00:00Z',
      ));

      // Seed data for a second hat.
      const otherHat = HatContext(domainFlag: 0x000202, extensionId: 'otherjobz');
      await repo.upsert(HatEntity(
        id: 'job-other-1',
        domainFlag: otherHat.domainFlag,
        state: 'lead',
        scheduledAt: '',
        entityJson: json.encode({'id': 'job-other-1'}),
        updatedAt: '2026-05-09T00:00:00Z',
      ));

      // Querying by old hat's domain_flag returns ONLY old hat's data.
      final oddjobzRows =
          await repo.queryAll(domainFlag: HatContext.oddjobz.domainFlag);
      expect(oddjobzRows.map((r) => r.id), equals(['job-oddjobz-1']),
          reason: 'oddjobz hat should only see its own entities');

      // Querying by new hat's domain_flag returns ONLY new hat's data.
      final otherRows =
          await repo.queryAll(domainFlag: otherHat.domainFlag);
      expect(otherRows.map((r) => r.id), equals(['job-other-1']),
          reason: 'new hat should only see its own entities');

      await repo.close();
    });

    test('HatContext.oddjobz is the default hat with correct values', () {
      expect(HatContext.oddjobz.domainFlag, equals(0x000101));
      expect(HatContext.oddjobz.extensionId, equals('oddjobz'));
    });
  });
}

```
