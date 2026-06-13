---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/gradient/dart_pipeline_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.917239+00:00
---

# archive/apps-semantos-monolith/test/gradient/dart_pipeline_test.dart

```dart
// D-O5m.followup-3 Phase 3 — DartIntentPipeline orchestrator tests.
//
// Reference: apps/oddjobz-mobile/lib/src/gradient/dart_pipeline.dart
//            (the unit under test, mirrors runtime/intent/src/
//            pipeline.ts:processIntent stage-for-stage);
//            apps/oddjobz-mobile/test/fixtures/end-to-end-pipeline-fixture.json
//            (the cross-language fixture for the end-to-end flow).

import 'dart:convert' show jsonDecode;
import 'dart:io';
import 'dart:typed_data';

import 'package:semantos/src/gradient/dart_pipeline.dart';
import 'package:test/test.dart';

class _Recorder {
  final events = <PipelineStageEvent>[];
  final cells = <PipelineCell>[];
  int counter = 0;

  PipelineDeps deps({
    Future<PipelineScriptResult> Function(Uint8List, String)? executeOverride,
  }) {
    return PipelineDeps(
      executeScript: executeOverride ??
          ((bytes, cid) async => PipelineScriptResult(
                ok: true,
                opcount: 1,
                stackDepth: 1,
                gasUsed: 0,
                traceCorrelationId: cid,
              )),
      buildCell: (bytes, k) => PipelineCell(
        id: 'cell-${counter++}',
        bytes: bytes,
      ),
      writeCell: (cell) async {
        cells.add(cell);
      },
      emit: events.add,
      correlationIdFactory: () => 'cid-test-fixed',
    );
  }
}

Map<String, dynamic> _intent({
  String category = 'permission',
}) {
  return {
    'id': 'i-1',
    'summary': 'demo',
    'category': category,
    'taxonomy': const {'what': 'demo', 'how': 'demo', 'why': 'demo'},
    'action': 'demo',
    'constraints': const [
      {'kind': 'capability', 'required': 5, 'name': 'TEST'},
    ],
    'confidence': 1.0,
    'source': 'voice',
  };
}

const _hat = PipelineHatContext(
  hatId: 'operator',
  certId: 'cert',
  domainFlag: 0x1234,
  maxTrustClass: 'interpretive',
  extensionId: 'oddjobz',
);

void main() {
  group('DartIntentPipeline.process', () {
    test('happy path runs all stages with consistent correlationId', () async {
      final rec = _Recorder();
      final pipe = DartIntentPipeline(rec.deps());
      final result = await pipe.process(intent: _intent(), hatContext: _hat);

      expect(result, isA<IntentSuccess>());
      final cid = (result as IntentSuccess).correlationId;
      expect(cid, equals('cid-test-fixed'));

      // Events fire in order. The pipeline emits 6 happy-path
      // stages: sir_built, sir_lowered, ir_emitted, script_executed,
      // cell_written, intent_completed.
      final stages = rec.events.map((e) => e.stage).toList();
      expect(
          stages,
          equals([
            'sir_built',
            'sir_lowered',
            'ir_emitted',
            'script_executed',
            'cell_written',
            'intent_completed',
          ]));
      // Every event tagged with the same correlationId.
      for (final ev in rec.events) {
        expect(ev.correlationId, equals(cid));
      }
      // The cell was written.
      expect(rec.cells, hasLength(1));
      expect(rec.cells.first.id, equals('cell-0'));
    });

    test('kernel rejection without errorKind falls back to numeric code',
        () async {
      // Legacy WASM path — no errorKind. Pipeline falls back to the
      // numeric errorCode as the rejection.code, and tags the typed
      // kernelViolation as `unknown` so consumers can spot schema drift.
      final rec = _Recorder();
      final pipe = DartIntentPipeline(rec.deps(
        executeOverride: (bytes, cid) async => PipelineScriptResult(
          ok: false,
          opcount: 0,
          stackDepth: 0,
          gasUsed: 0,
          errorCode: 99,
          errorMessage: 'kernel test rejection',
          traceCorrelationId: cid,
        ),
      ));
      final result = await pipe.process(intent: _intent(), hatContext: _hat);
      expect(result, isA<IntentRejected>());
      final r = result as IntentRejected;
      expect(r.rejection.stage, equals('kernel'));
      expect(r.rejection.code, equals('99'));
      expect(r.rejection.message, contains('kernel test rejection'));
      expect(r.rejection.kernelViolation,
          equals(PipelineKernelViolation.unknown));
      // The emitted bytes are attached so the operator can see what
      // the SIR/OIR produced.
      expect(r.bytes, isNotNull);
      expect(r.kernelResult, isNotNull);
      // No cell was written.
      expect(rec.cells, isEmpty);
      // intent_rejected event present, intent_completed absent.
      final stages = rec.events.map((e) => e.stage).toSet();
      expect(stages, contains('intent_rejected'));
      expect(stages, isNot(contains('intent_completed')));
    });

    // ── D-O5m.followup-1 — typed K1-K4 violation routing ─────────────

    PipelineDeps depsForViolation(_Recorder rec, String errorKind, int code) {
      return rec.deps(
        executeOverride: (bytes, cid) async => PipelineScriptResult(
          ok: false,
          opcount: 1,
          stackDepth: 0,
          gasUsed: 0,
          errorCode: code,
          errorKind: errorKind,
          errorMessage: '$errorKind at byte 0',
          traceCorrelationId: cid,
        ),
      );
    }

    test('K1 kernel violation surfaces PipelineKernelViolation.k1Linearity',
        () async {
      final rec = _Recorder();
      final pipe = DartIntentPipeline(
          depsForViolation(rec, 'k1_linearity_violation', 10));
      final r = await pipe.process(intent: _intent(), hatContext: _hat);
      expect(r, isA<IntentRejected>());
      final rej = (r as IntentRejected).rejection;
      expect(rej.stage, equals('kernel'));
      expect(rej.kernelViolation,
          equals(PipelineKernelViolation.k1Linearity));
      expect(rej.code, equals('k1_linearity_violation'));
    });

    test('K2 kernel violation surfaces PipelineKernelViolation.k2Auth',
        () async {
      final rec = _Recorder();
      final pipe =
          DartIntentPipeline(depsForViolation(rec, 'k2_auth_failed', 11));
      final r = await pipe.process(intent: _intent(), hatContext: _hat);
      final rej = (r as IntentRejected).rejection;
      expect(rej.kernelViolation, equals(PipelineKernelViolation.k2Auth));
      expect(rej.code, equals('k2_auth_failed'));
    });

    test('K3 kernel violation surfaces PipelineKernelViolation.k3Domain',
        () async {
      final rec = _Recorder();
      final pipe = DartIntentPipeline(
          depsForViolation(rec, 'k3_domain_mismatch', 12));
      final r = await pipe.process(intent: _intent(), hatContext: _hat);
      final rej = (r as IntentRejected).rejection;
      expect(rej.kernelViolation, equals(PipelineKernelViolation.k3Domain));
      expect(rej.code, equals('k3_domain_mismatch'));
    });

    test('K4 kernel violation surfaces PipelineKernelViolation.k4Atomicity',
        () async {
      final rec = _Recorder();
      final pipe = DartIntentPipeline(
          depsForViolation(rec, 'k4_atomicity_violation', 13));
      final r = await pipe.process(intent: _intent(), hatContext: _hat);
      final rej = (r as IntentRejected).rejection;
      expect(rej.kernelViolation,
          equals(PipelineKernelViolation.k4Atomicity));
      expect(rej.code, equals('k4_atomicity_violation'));
    });

    test('script_invalid kernel violation surfaces scriptInvalid',
        () async {
      final rec = _Recorder();
      final pipe =
          DartIntentPipeline(depsForViolation(rec, 'script_invalid', 14));
      final r = await pipe.process(intent: _intent(), hatContext: _hat);
      final rej = (r as IntentRejected).rejection;
      expect(rej.kernelViolation,
          equals(PipelineKernelViolation.scriptInvalid));
      expect(rej.code, equals('script_invalid'));
    });

    test('correlationId taken from intent when present', () async {
      final rec = _Recorder();
      final pipe = DartIntentPipeline(rec.deps());
      final intent = _intent();
      intent['correlationId'] = 'cid-from-intent';
      final result = await pipe.process(intent: intent, hatContext: _hat);
      expect((result as IntentSuccess).correlationId,
          equals('cid-from-intent'));
    });

    test('hat trust ceiling clamps the candidate trustClass', () async {
      final rec = _Recorder();
      final pipe = DartIntentPipeline(rec.deps());
      const lowHat = PipelineHatContext(
        hatId: 'operator',
        certId: 'cert',
        domainFlag: 0x1234,
        maxTrustClass: 'cosmetic',
      );
      // confidence 1.0 + voice -> candidate 'interpretive', ceiling
      // 'cosmetic' -> trust clamped to 'cosmetic'.
      final result =
          await pipe.process(intent: _intent(), hatContext: lowHat);
      expect(result, isA<IntentSuccess>());
      final sirBuilt = rec.events.firstWhere((e) => e.stage == 'sir_built');
      expect(sirBuilt.data['trustClass'], equals('cosmetic'));
    });

    test('every stage event carries durationMs >= 0', () async {
      final rec = _Recorder();
      final pipe = DartIntentPipeline(rec.deps());
      await pipe.process(intent: _intent(), hatContext: _hat);
      for (final e in rec.events) {
        expect(e.durationMs, greaterThanOrEqualTo(0));
      }
    });
  });

  group('DartIntentPipeline — end-to-end fixture parity', () {
    test('pipeline reaches kernel with non-empty opcode bytes for fixture intent',
        () async {
      // The byte-identical α-equivalence claim for SIR->OIR->bytes
      // is asserted exhaustively in oir_to_bytes_test.dart against
      // the cross-language fixture. Here we assert the orchestrator
      // produces a non-empty byte stream and reaches the kernel
      // surface for a representative fixture-shaped intent. This
      // closes the loop on the end-to-end flow without
      // duplicating the byte-parity oracle.
      final fixturePath = _findFixture('end-to-end-pipeline-fixture.json');
      final fixture = jsonDecode(File(fixturePath).readAsStringSync())
          as Map<String, dynamic>;
      final expected =
          fixture['expectedKernelResult'] as Map<String, dynamic>;

      Uint8List? capturedBytes;
      final rec = _Recorder();
      final pipe = DartIntentPipeline(rec.deps(
        executeOverride: (bytes, cid) async {
          capturedBytes = Uint8List.fromList(bytes);
          return PipelineScriptResult(
            ok: expected['ok'] as bool,
            opcount: (expected['opcount'] as num).toInt(),
            stackDepth: (expected['stackDepth'] as num).toInt(),
            gasUsed: (expected['gasUsed'] as num).toInt(),
            traceCorrelationId: cid,
          );
        },
      ));
      final intent = {
        'id': 'i-fixture',
        'summary': 'demo',
        'category': 'permission',
        'taxonomy': const {'what': 'demo', 'how': 'demo', 'why': 'demo'},
        'action': 'demo',
        'constraints': const [
          {'kind': 'capability', 'required': 5, 'name': 'METERING'},
        ],
        'confidence': 1.0,
        'source': 'voice',
      };
      final r = await pipe.process(intent: intent, hatContext: _hat);
      expect(r, isA<IntentSuccess>());
      expect(capturedBytes, isNotNull);
      expect(capturedBytes!.length, greaterThan(0));
    });
  });
}

String _findFixture(String filename) {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final p =
        '${dir.path}/apps/oddjobz-mobile/test/fixtures/$filename';
    if (File(p).existsSync()) return p;
    final localP = '${dir.path}/test/fixtures/$filename';
    if (File(localP).existsSync()) return localP;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('fixture $filename not found from ${Directory.current.path}');
}

```
