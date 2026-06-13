---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/voice/text_intent_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.910706+00:00
---

# archive/apps-semantos-monolith/test/voice/text_intent_service_test.dart

```dart
// D-O5m.followup-7 Phase B — TextIntentService tests.
//
// Mirrors test/voice/voice_command_service_test.dart's posture: the
// service is exercised against a mocked SirExtractor + DartIntentPipeline
// so the typed branches (success / refused / extractor-unavailable /
// pipeline-unavailable / pipeline-rejected) all light up without
// requiring real LLM models or a kernel FFI.

import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:semantos/src/gradient/dart_pipeline.dart';
import 'package:semantos/src/voice/sir_extractor.dart';
import 'package:semantos/src/voice/text_intent_service.dart';

void main() {
  group('TextIntentService.processText', () {
    final hat = HatContext(
      hatId: 'hat-mowing',
      certId: 'cert-1',
      extensionId: 'oddjobz',
      capabilities: const [1, 2, 3],
    );
    final pipelineHat = const PipelineHatContext(
      hatId: 'hat-mowing',
      certId: 'cert-1',
      domainFlag: 1,
      maxTrustClass: 'interpretive',
      extensionId: 'oddjobz',
    );

    test('refuses empty input without calling the extractor', () async {
      final extractor = _RecordingExtractor(_canonicalSuccessIntent());
      final svc = TextIntentService(
        sirExtractor: extractor,
        hatContext: hat,
        localPipeline: _stubPipeline(),
        pipelineHatContext: pipelineHat,
      );
      final r = await svc.processText(text: '   ');
      expect(r, isA<TextIntentFailed>());
      final f = (r as TextIntentFailed).failure;
      expect(f, isA<TextIntentRefused>());
      expect((f as TextIntentRefused).reason, equals('empty input'));
      expect(extractor.callCount, equals(0));
    });

    test('surfaces TextIntentExtractorUnavailable when no extractor wired',
        () async {
      final svc = TextIntentService(
        localPipeline: _stubPipeline(),
        pipelineHatContext: pipelineHat,
      );
      final r = await svc.processText(text: 'quote the kitchen reno');
      expect(r, isA<TextIntentFailed>());
      expect((r as TextIntentFailed).failure,
          isA<TextIntentExtractorUnavailable>());
    });

    test('surfaces TextIntentRefused when the extractor refuses', () async {
      final svc = TextIntentService(
        sirExtractor: _StubExtractor(
          const SirExtractionRefused('confidence below threshold'),
        ),
        hatContext: hat,
        localPipeline: _stubPipeline(),
        pipelineHatContext: pipelineHat,
      );
      final r = await svc.processText(text: 'do a thing');
      expect(r, isA<TextIntentFailed>());
      final f = (r as TextIntentFailed).failure;
      expect(f, isA<TextIntentRefused>());
      expect((f as TextIntentRefused).reason, contains('confidence'));
    });

    test('drives pipeline with source="nl" on extractor success', () async {
      final extractor = _RecordingExtractor(_canonicalSuccessIntent());
      final pipeline = _RecordingPipeline(
        IntentSuccess(
          correlationId: 'cid-1',
          cell: PipelineCell(id: 'cell-1', bytes: Uint8List(0)),
          kernelResult: const PipelineScriptResult(
            ok: true,
            opcount: 1,
            stackDepth: 1,
            gasUsed: 1,
          ),
        ),
      );
      final svc = TextIntentService(
        sirExtractor: extractor,
        hatContext: hat,
        localPipeline: pipeline,
        pipelineHatContext: pipelineHat,
      );
      final r = await svc.processText(text: 'quote the kitchen reno');
      expect(r, isA<TextIntentSuccess>());
      expect((r as TextIntentSuccess).result.cell.id, equals('cell-1'));
      expect(pipeline.lastIntent, isNotNull);
      expect(pipeline.lastIntent!['source'], equals('nl'));
    });

    test('surfaces TextIntentRejected on SIR / kernel rejection', () async {
      final extractor = _RecordingExtractor(_canonicalSuccessIntent());
      final pipeline = _RecordingPipeline(
        const IntentRejected(
          correlationId: 'cid-1',
          rejection: IntentRejection(
            stage: 'kernel',
            code: 'k1_linearity_violation',
            message: 'cell already consumed',
          ),
        ),
      );
      final svc = TextIntentService(
        sirExtractor: extractor,
        hatContext: hat,
        localPipeline: pipeline,
        pipelineHatContext: pipelineHat,
      );
      final r = await svc.processText(text: 'quote the kitchen reno');
      expect(r, isA<TextIntentFailed>());
      final f = (r as TextIntentFailed).failure;
      expect(f, isA<TextIntentRejected>());
      expect((f as TextIntentRejected).rejection.stage, equals('kernel'));
      expect(f.rejection.code, equals('k1_linearity_violation'));
    });

    test('surfaces TextIntentPipelineUnavailable when pipeline missing',
        () async {
      final extractor = _RecordingExtractor(_canonicalSuccessIntent());
      final svc = TextIntentService(
        sirExtractor: extractor,
        hatContext: hat,
      );
      final r = await svc.processText(text: 'quote the kitchen reno');
      expect(r, isA<TextIntentFailed>());
      expect(
        (r as TextIntentFailed).failure,
        isA<TextIntentPipelineUnavailable>(),
      );
    });
  });
}

Map<String, dynamic> _canonicalSuccessIntent() => {
      'id': 'intent-1',
      'summary': 'Quote the kitchen reno',
      'category': {'lexicon': 'trades', 'name': 'quote'},
      'taxonomy': {'what': 'quote', 'how': 'manual', 'why': 'request'},
      'action': 'quote',
      'constraints': const [],
      'confidence': 0.85,
      'source': 'voice',
    };

DartIntentPipeline _stubPipeline() {
  // Returns a successful pipeline with deterministic outputs — used by
  // tests that don't want to assert on the pipeline's behaviour.
  return DartIntentPipeline(PipelineDeps(
    executeScript: (_, _) async => const PipelineScriptResult(
      ok: true,
      opcount: 1,
      stackDepth: 1,
      gasUsed: 1,
    ),
    buildCell: (bytes, _) => PipelineCell(id: 'cell-stub', bytes: bytes),
    writeCell: (_) async {},
    emit: (_) {},
    correlationIdFactory: () => 'cid-stub',
  ));
}

/// Stub extractor that always returns the supplied result.  Doesn't
/// record calls; use [_RecordingExtractor] when call-count matters.
class _StubExtractor implements SirExtractor {
  final SirExtractionResult _result;
  _StubExtractor(this._result);

  @override
  Future<SirExtractionResult> extract({
    required String transcript,
    required HatContext hatContext,
    required ExtensionGrammar grammar,
  }) async =>
      _result;

  @override
  String get intentGrammarBNF => '';
}

class _RecordingExtractor implements SirExtractor {
  final Map<String, dynamic> _intent;
  int callCount = 0;
  String? lastTranscript;

  _RecordingExtractor(this._intent);

  @override
  Future<SirExtractionResult> extract({
    required String transcript,
    required HatContext hatContext,
    required ExtensionGrammar grammar,
  }) async {
    callCount++;
    lastTranscript = transcript;
    return SirExtractionSuccess(intent: _intent, confidence: 0.85);
  }

  @override
  String get intentGrammarBNF => '';
}

class _RecordingPipeline extends DartIntentPipeline {
  final IntentResult _result;
  Map<String, dynamic>? lastIntent;

  _RecordingPipeline(this._result)
      : super(PipelineDeps(
          executeScript: (_, _) async => const PipelineScriptResult(
            ok: true,
            opcount: 1,
            stackDepth: 1,
            gasUsed: 1,
          ),
          buildCell: (bytes, _) =>
              PipelineCell(id: 'cell-recorded', bytes: bytes),
          writeCell: (_) async {},
          emit: (_) {},
          correlationIdFactory: () => 'cid-recorded',
        ));

  @override
  Future<IntentResult> process({
    required Map<String, dynamic> intent,
    required PipelineHatContext hatContext,
    String? correlationId,
  }) async {
    lastIntent = Map<String, dynamic>.from(intent);
    return _result;
  }
}

```
