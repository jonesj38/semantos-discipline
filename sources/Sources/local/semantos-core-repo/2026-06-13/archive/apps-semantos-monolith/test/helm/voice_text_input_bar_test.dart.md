---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/voice_text_input_bar_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.925036+00:00
---

# archive/apps-semantos-monolith/test/helm/voice_text_input_bar_test.dart

```dart
// D-O5m.followup-7 Phase B — VoiceTextInputBarController tests.
//
// Pure-Dart against the controller (the widget is a thin wrapper).
// The controller's submit() routes typed text through TextIntentService;
// reportVoiceOutcome() lets the voice path feed the same inline
// feedback area.  These tests pin the state-machine transitions for
// every typed outcome + the timer-driven success-fade.

import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:semantos/src/gradient/dart_pipeline.dart';
import 'package:semantos/src/voice/sir_extractor.dart';
import 'package:semantos/src/voice/text_intent_service.dart';
import 'package:semantos/src/voice/voice_text_input_bar_controller.dart';

void main() {
  group('VoiceTextInputBarController', () {
    test('initial phase is idle', () {
      final controller =
          VoiceTextInputBarController(textService: _stubService());
      expect(controller.phase, equals(VoiceTextInputPhase.idle));
      expect(controller.lastSuccess, isNull);
      expect(controller.lastRefusal, isNull);
    });

    test('submit() with empty text is a no-op', () async {
      final svc = _RecordingService();
      final controller = VoiceTextInputBarController(textService: svc);
      await controller.submit('   ');
      expect(controller.phase, equals(VoiceTextInputPhase.idle));
      expect(svc.calls, equals(0));
    });

    test('submit() success transitions through sending → success', () async {
      final svc = _RecordingService(
        outcome: TextIntentSuccess(
          IntentSuccess(
            correlationId: 'cid-1',
            cell: PipelineCell(id: 'abcdef0123456', bytes: Uint8List(0)),
            kernelResult: const PipelineScriptResult(
              ok: true,
              opcount: 1,
              stackDepth: 1,
              gasUsed: 1,
            ),
          ),
        ),
      );
      final controller = VoiceTextInputBarController(textService: svc);
      final phases = <VoiceTextInputPhase>[];
      controller.addListener(() => phases.add(controller.phase));
      await controller.submit('quote the kitchen reno');
      expect(phases, contains(VoiceTextInputPhase.sending));
      expect(controller.phase, equals(VoiceTextInputPhase.success));
      expect(controller.lastSuccess!.summary, contains('Cell'));
      expect(svc.calls, equals(1));
    });

    test('success state auto-fades back to idle after the timer', () async {
      final svc = _RecordingService(
        outcome: TextIntentSuccess(
          IntentSuccess(
            correlationId: 'cid-1',
            cell: PipelineCell(id: 'abc', bytes: Uint8List(0)),
            kernelResult: const PipelineScriptResult(
              ok: true,
              opcount: 1,
              stackDepth: 1,
              gasUsed: 1,
            ),
          ),
        ),
      );
      final controller = VoiceTextInputBarController(
        textService: svc,
        successDisplayDuration: const Duration(milliseconds: 5),
      );
      await controller.submit('do a thing');
      expect(controller.phase, equals(VoiceTextInputPhase.success));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.phase, equals(VoiceTextInputPhase.idle));
      expect(controller.lastSuccess, isNull);
    });

    test('submit() refused renders a typed refusal', () async {
      final svc = _RecordingService(
        outcome: const TextIntentFailed(
          TextIntentRefused('confidence below threshold'),
        ),
      );
      final controller = VoiceTextInputBarController(textService: svc);
      await controller.submit('garbled');
      expect(controller.phase, equals(VoiceTextInputPhase.refused));
      expect(controller.lastRefusal!.stage, equals('extractor'));
      expect(controller.lastRefusal!.reason, contains('confidence'));
    });

    test('dismissRefusal() clears the refused state', () async {
      final svc = _RecordingService(
        outcome: const TextIntentFailed(TextIntentRefused('garbage in')),
      );
      final controller = VoiceTextInputBarController(textService: svc);
      await controller.submit('garbled');
      expect(controller.phase, equals(VoiceTextInputPhase.refused));
      controller.dismissRefusal();
      expect(controller.phase, equals(VoiceTextInputPhase.idle));
      expect(controller.lastRefusal, isNull);
    });

    test('reportVoiceOutcome(success) renders the success state', () {
      final controller =
          VoiceTextInputBarController(textService: _stubService());
      controller.reportVoiceOutcome(
        success: true,
        successSummary: 'Job 12345 quoted',
      );
      expect(controller.phase, equals(VoiceTextInputPhase.success));
      expect(controller.lastSuccess!.summary, equals('Job 12345 quoted'));
    });

    test('reportVoiceOutcome(refused) renders the refusal state', () {
      final controller =
          VoiceTextInputBarController(textService: _stubService());
      controller.reportVoiceOutcome(
        success: false,
        refusalStage: 'voice-stt',
        refusalReason: 'no audio captured',
      );
      expect(controller.phase, equals(VoiceTextInputPhase.refused));
      expect(controller.lastRefusal!.stage, equals('voice-stt'));
      expect(controller.lastRefusal!.reason, equals('no audio captured'));
    });

    // 2026-05-07 — regression test: the bar swaps in the post-init
    // TextIntentService when OnDeviceVoiceFactory finishes booting.
    // Pre-fix the controller froze a snapshot of the empty default in
    // initState, so processText forever returned ExtractorUnavailable
    // even after the factory had initialised.  The widget's
    // didUpdateWidget now writes through to controller.textService —
    // this test pins that the underlying field is mutable AND that
    // submit() routes through the latest reference, not the original.
    test('textService swap routes subsequent submit() to the new service',
        () async {
      final preInitSvc = _RecordingService();
      final postInitSvc = _RecordingService(
        outcome: TextIntentSuccess(
          IntentSuccess(
            correlationId: 'cid-2',
            cell: PipelineCell(id: 'cafef00d', bytes: Uint8List(0)),
            kernelResult: const PipelineScriptResult(
              ok: true,
              opcount: 1,
              stackDepth: 1,
              gasUsed: 1,
            ),
          ),
        ),
      );
      final controller =
          VoiceTextInputBarController(textService: preInitSvc);

      // Simulate the parent rebuilding with the post-init service —
      // this is what voice_text_input_bar.dart's didUpdateWidget does.
      controller.textService = postInitSvc;

      await controller.submit('find me the wattle street job');

      expect(preInitSvc.calls, equals(0),
          reason: 'submit should not hit the pre-init service');
      expect(postInitSvc.calls, equals(1),
          reason: 'submit should route through the post-init service');
      expect(controller.phase, equals(VoiceTextInputPhase.success));
    });
  });
}

TextIntentService _stubService() => TextIntentService();

class _RecordingService implements TextIntentService {
  final TextIntentOutcome? _outcome;
  int calls = 0;
  String? lastText;

  _RecordingService({TextIntentOutcome? outcome}) : _outcome = outcome;

  @override
  Future<TextIntentOutcome> processText({required String text}) async {
    calls++;
    lastText = text;
    return _outcome ??
        const TextIntentFailed(TextIntentExtractorUnavailable());
  }

  @override
  ExtensionGrammar get extensionGrammar => ExtensionGrammar.oddjobz;

  @override
  HatContext? get hatContext => null;

  @override
  DartIntentPipeline? get localPipeline => null;

  @override
  DartIntentPipeline? Function(Map<String, dynamic> intent)?
      get pipelineForIntent => null;

  @override
  PipelineHatContext? get pipelineHatContext => null;

  @override
  SirExtractor? get sirExtractor => null;
}

```
