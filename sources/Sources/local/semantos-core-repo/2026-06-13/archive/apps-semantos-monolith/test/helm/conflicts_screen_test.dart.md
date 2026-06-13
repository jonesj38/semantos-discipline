---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/conflicts_screen_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.927038+00:00
---

# archive/apps-semantos-monolith/test/helm/conflicts_screen_test.dart

```dart
// D-O5m.followup-5 K1 conflict UI — ConflictsScreen behaviour test
// (pure-Dart, runnable under `dart test` without the Flutter SDK
// gate).
//
// We don't fire up the widget tree — instead we exercise the same
// surfaces the screen renders against (the `summariseEntry` helper +
// the `OutboxService.failedEntries` stream + retry/discard call-
// throughs) via DI mocks.  The brief allows widget-test-light
// approaches and explicitly prefers DI mocks where possible.
//
// Coverage:
//   - summariseEntry pulls visitId + jobId out of payload JSON;
//   - failed-entry rendering surface: kind, message, lastBrainState
//     all flow through to the OutboxFailedEntry projection that the
//     screen renders;
//   - outbox.retry(id) clears typed-failure metadata (mimics the
//     screen's Retry button);
//   - outbox.discard(id) removes the entry (mimics the Discard button);
//   - failedEntries stream emits the new state on retry / discard so
//     the AppBar indicator + screen rebuild without manual setState;
//   - state_moved_on entries surface the brain state (the View-
//     conflict button only renders for these).

import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/outbox/conflict_summary.dart';
import 'package:semantos/src/outbox/failure_messages.dart';
import 'package:semantos/src/outbox/outbox_db.dart';
import 'package:semantos/src/outbox/outbox_service.dart';
import 'package:semantos/src/repl/repl_client.dart';

Future<OutboxDb> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(),
  );
  return OutboxDb.fromDatabase(db);
}

OutboxService _service(OutboxDb db) => OutboxService(
      db: db,
      repl: ReplClient.withBearer(
        http: Dio(),
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'b' * 64,
      ),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('summariseEntry', () {
    test('extracts visitId + jobId from cell payload JSON', () {
      const entry = OutboxEntry(
        id: 7,
        cellType: 'oddjobz.attachment.v1',
        payloadJson:
            '{"cell_payload":{"visitId":"visit-abc","jobId":"job-xyz"}}',
        createdAtMs: 0,
        attemptCount: 0,
      );
      final summary = summariseEntry(entry);
      expect(summary, contains('Visit visit-abc'));
      expect(summary, contains('Job job-xyz'));
      expect(summary, contains('Attachment'));
    });

    test('falls back to entry id when no recognised IDs present', () {
      const entry = OutboxEntry(
        id: 42,
        cellType: 'oddjobz.job.v1',
        payloadJson: '{"opaque":"yes"}',
        createdAtMs: 0,
        attemptCount: 0,
      );
      expect(summariseEntry(entry), contains('entry #42'));
      expect(summariseEntry(entry), contains('Job'));
    });
  });

  group('failed-entry rendering surface', () {
    test('OutboxFailedEntry exposes the fields the row needs', () async {
      final db = await _openInMemory();
      final id = await db.enqueue(
        cellType: 'oddjobz.attachment.v1',
        payloadJson: '{}',
      );
      await db.recordTypedFailure(
        id: id,
        kind: OutboxFailureKind.signatureInvalid,
        message: 'cert revoked',
      );
      final failed = (await db.peekFailed()).first;
      expect(failed.kind, equals(OutboxFailureKind.signatureInvalid));
      expect(failed.message, equals('cert revoked'));
      expect(readableMessage(failed.kind, failed.message), contains('Re-pair'));
      await db.close();
    });

    test('state_moved_on entries surface lastBrainState (View-conflict path)',
        () async {
      final db = await _openInMemory();
      final id =
          await db.enqueue(cellType: 'oddjobz.job.v1', payloadJson: '{}');
      await db.recordTypedFailure(
        id: id,
        kind: OutboxFailureKind.stateMovedOn,
        message: 'job advanced',
        lastBrainState: 'invoiced',
      );
      final failed = (await db.peekFailed()).first;
      expect(failed.kind, equals(OutboxFailureKind.stateMovedOn));
      expect(failed.lastBrainState, equals('invoiced'));
      // The screen routes only state_moved_on rows to the View-
      // conflict dialog — assert the kind discriminator behaves.
      expect(failed.kind == OutboxFailureKind.stateMovedOn, isTrue);
      await db.close();
    });
  });

  group('OutboxService action call-throughs (Retry / Discard)', () {
    test('retry clears the typed-failure metadata + leaves entry queued',
        () async {
      final db = await _openInMemory();
      final id = await db.enqueue(
        cellType: 'oddjobz.job.v1',
        payloadJson: '{}',
      );
      await db.recordTypedFailure(
          id: id, kind: OutboxFailureKind.hashMismatch);
      final svc = _service(db);
      expect(await db.failedCount(), equals(1));

      await svc.retry(id);
      expect(await db.failedCount(), equals(0));
      expect(await db.count(), equals(1)); // entry remains queued

      await svc.dispose();
      await db.close();
    });

    test('discard removes the entry from the queue entirely', () async {
      final db = await _openInMemory();
      final id =
          await db.enqueue(cellType: 'oddjobz.job.v1', payloadJson: '{}');
      await db.recordTypedFailure(
          id: id, kind: OutboxFailureKind.networkError);
      final svc = _service(db);

      await svc.discard(id);
      expect(await db.count(), equals(0));

      await svc.dispose();
      await db.close();
    });

    test('failedEntries stream emits a fresh snapshot on retry + discard',
        () async {
      final db = await _openInMemory();
      final id1 =
          await db.enqueue(cellType: 'oddjobz.job.v1', payloadJson: '{}');
      final id2 =
          await db.enqueue(cellType: 'oddjobz.job.v1', payloadJson: '{}');
      await db.recordTypedFailure(
          id: id1, kind: OutboxFailureKind.hashMismatch);
      await db.recordTypedFailure(
          id: id2, kind: OutboxFailureKind.hashMismatch);
      final svc = _service(db);

      // Attach a listener and capture the next two emissions
      // (after retry + after discard).
      final emissions = <int>[];
      final sub = svc.failedEntries.listen((failed) {
        emissions.add(failed.length);
      });
      // Drain the priming emission before mutating.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await svc.retry(id1);
      await svc.discard(id2);
      // Give the stream a turn to flush.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      // Priming + post-retry + post-discard.  The retry drops id1
      // out of the failed set (now 1 left); discard removes id2
      // entirely (now 0).
      expect(emissions, contains(2));
      expect(emissions, contains(1));
      expect(emissions.last, equals(0));

      await svc.dispose();
      await db.close();
    });
  });

  group('AppBar indicator wiring', () {
    test('failedCount drives the red-dot path; pendingCount drives green/yellow',
        () async {
      final db = await _openInMemory();
      // Pristine outbox → both counts zero.
      expect(await db.count(), equals(0));
      expect(await db.failedCount(), equals(0));

      // Enqueue two — now pending=2, failed=0.
      await db.enqueue(cellType: 'oddjobz.job.v1', payloadJson: '{}');
      final id =
          await db.enqueue(cellType: 'oddjobz.job.v1', payloadJson: '{}');
      expect(await db.count(), equals(2));
      expect(await db.failedCount(), equals(0));

      // Record a failure on one — pending stays the same; failed=1.
      await db.recordTypedFailure(
        id: id,
        kind: OutboxFailureKind.networkError,
      );
      expect(await db.count(), equals(2));
      expect(await db.failedCount(), equals(1));

      await db.close();
    });
  });
}

```
