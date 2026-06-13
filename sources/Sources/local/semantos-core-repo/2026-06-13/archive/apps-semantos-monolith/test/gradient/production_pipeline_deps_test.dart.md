---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/gradient/production_pipeline_deps_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.917526+00:00
---

# archive/apps-semantos-monolith/test/gradient/production_pipeline_deps_test.dart

```dart
// 2026-05-07 — production wiring of `DartIntentPipeline.PipelineDeps`.
// These tests use a stub `SemantosKernel` (via the
// `SemantosKernel.withBindings` test seam) and an in-memory FFI
// sqflite-backed `OutboxDb` to exercise the full deps pipeline
// without loading the real FFI shim or a SQLite file from disk.
//
// The contract pinned here:
//
//  - executeScript routes through `SemantosKernel.executeScript` and
//    maps `ScriptResult` → `PipelineScriptResult` field-for-field.
//  - buildCell derives the cell id deterministically from the opcode
//    bytes via `deriveCellId`.
//  - writeCell renders the canonical envelope shape per
//    `docs/spec/oddjobz-intent-cell-v1.md` and enqueues with
//    `cellType: 'oddjobz.intent_cell.v1'`.
//  - emit forwards stage events as structured strings.
//  - correlationIdFactory threads the same uuid through every callback
//    that needs one.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/gradient/dart_pipeline.dart' as pipe;
import 'package:semantos/src/gradient/production_pipeline_deps.dart';
import 'package:semantos/src/outbox/outbox_db.dart';
import 'package:semantos_ffi/semantos_ffi.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<OutboxDb> _openInMemoryOutbox() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(),
  );
  return OutboxDb.fromDatabase(db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  group('buildProductionPipelineDeps', () {
    late OutboxDb db;

    setUp(() async {
      db = await _openInMemoryOutbox();
    });

    tearDown(() async {
      await db.close();
    });

    test('writeCell renders canonical envelope + enqueues with intentCellType',
        () async {
      // Stub kernel-execute: we never actually call executeScript
      // in this test (we drive writeCell directly), so a no-op
      // closure is fine.
      Future<ScriptResult> stubExecute({
        required Uint8List bytes,
        ScriptContext? ctx,
      }) async =>
          const ScriptResult(ok: true, opcount: 0, stackDepth: 0, gasUsed: 0);

      var uuidCounter = 0;
      String fixedUuid() {
        uuidCounter += 1;
        // 36-char canonical uuid shape so deriveCellId's
        // dash-stripping path works the same as production.
        return '00000000-0000-0000-0000-${uuidCounter.toString().padLeft(12, '0')}';
      }

      final deps = buildProductionPipelineDeps(
        kernelExecute: stubExecute,
        outboxDb: db,
        hatId: 'hat-deadbeef',
        certId: 'cert-cafef00d',
        intentSummary: 'Find the wattle street job',
        intentAction: 'find',
        intentTaxonomyJson: '{"what":"jobs","how":"find","why":"navigate"}',
        uuid: fixedUuid,
      );

      final bytes = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01]);
      final cell = deps.buildCell(
        bytes,
        const pipe.PipelineScriptResult(
          ok: true,
          opcount: 5,
          stackDepth: 1,
          gasUsed: 7,
        ),
      );
      // First uuid call drives the cell id; trailing 8 chars stripped
      // + lower-cased.
      expect(cell.id.startsWith('cell-000006-deadbeef-'), isTrue,
          reason: cell.id);

      await deps.writeCell(cell);

      final rows = await db.peek();
      expect(rows.length, equals(1));
      final entry = rows.first;
      expect(entry.cellType, equals(intentCellType));

      final envelope = jsonDecode(entry.payloadJson) as Map<String, dynamic>;
      expect(envelope['kind'], equals('oddjobz.intent_cell.v1'));
      expect(envelope['version'], equals(1));
      expect(envelope['cellId'], equals(cell.id));
      expect(envelope['hatId'], equals('hat-deadbeef'));
      expect(envelope['certId'], equals('cert-cafef00d'));
      expect(envelope['opcodeBytes'], equals(base64Encode(bytes)));
      // No prior executeScript run — deps fall back to the safe
      // ok-shape claim documented in production_pipeline_deps.dart.
      final kr = envelope['kernelResult'] as Map<String, dynamic>;
      expect(kr['ok'], equals(true));
      expect(kr['opcount'], equals(0));
      final orig = envelope['originalIntent'] as Map<String, dynamic>;
      expect(orig['summary'], equals('Find the wattle street job'));
      expect(orig['action'], equals('find'));
      expect(
        orig['taxonomyJson'],
        equals('{"what":"jobs","how":"find","why":"navigate"}'),
      );
    });

    test(
        'emit fires structured strings (correlation + stage + ms + data)',
        () async {
      Future<ScriptResult> stubExecute({
        required Uint8List bytes,
        ScriptContext? ctx,
      }) async =>
          const ScriptResult(ok: true, opcount: 0, stackDepth: 0, gasUsed: 0);
      final emitted = <String>[];

      final deps = buildProductionPipelineDeps(
        kernelExecute: stubExecute,
        outboxDb: db,
        hatId: 'h',
        certId: 'c',
        intentSummary: 's',
        intentAction: 'note',
        intentTaxonomyJson: '{}',
        uuid: () => '11111111-2222-3333-4444-555555555555',
        audit: emitted.add,
      );

      deps.emit(pipe.PipelineStageEvent(
        correlationId: 'cid-1',
        stage: 'sir_built',
        durationMs: 12.34,
        data: {'k': 'v'},
      ));

      expect(emitted.single, contains('[pipeline]'));
      expect(emitted.single, contains('cid=cid-1'));
      expect(emitted.single, contains('stage=sir_built'));
      expect(emitted.single, contains('ms=12.34'));
      expect(emitted.single, contains('data={"k":"v"}'));
    });

    test(
        'kernelResult captured in executeScript surfaces in writeCell envelope',
        () async {
      Future<ScriptResult> verdictExecute({
        required Uint8List bytes,
        ScriptContext? ctx,
      }) async =>
          ScriptResult(
            ok: true,
            opcount: 12,
            stackDepth: 3,
            gasUsed: 17,
            traceCorrelationId: ctx?.traceCorrelationId,
          );

      final deps = buildProductionPipelineDeps(
        kernelExecute: verdictExecute,
        outboxDb: db,
        hatId: 'h',
        certId: 'c',
        intentSummary: 'summary',
        intentAction: 'find',
        intentTaxonomyJson: '{}',
        uuid: () => '22222222-3333-4444-5555-666666666666',
      );

      // Drive executeScript first so the deps' captured-claim closure
      // sees a real verdict, then writeCell.
      final scriptResult = await deps.executeScript(
        Uint8List.fromList([0x01, 0x02]),
        'cid-A',
      );
      expect(scriptResult.opcount, equals(12));
      expect(scriptResult.stackDepth, equals(3));
      expect(scriptResult.gasUsed, equals(17));

      final cell = deps.buildCell(
        Uint8List.fromList([0x01, 0x02]),
        scriptResult,
      );
      await deps.writeCell(cell);

      final rows = await db.peek();
      final envelope = jsonDecode(rows.first.payloadJson)
          as Map<String, dynamic>;
      final kr = envelope['kernelResult'] as Map<String, dynamic>;
      expect(kr['ok'], equals(true));
      expect(kr['opcount'], equals(12));
      expect(kr['stackDepth'], equals(3));
      expect(kr['gasUsed'], equals(17));
    });
  });

  group('renderIntentCellReplLine', () {
    test('base64-wraps the payload as the --envelope arg', () {
      final line = renderIntentCellReplLine('{"hello":"world"}');
      expect(
        line,
        equals('submit-intent-cell --envelope ${base64Encode(utf8.encode('{"hello":"world"}'))}'),
      );
    });
  });
}


```
