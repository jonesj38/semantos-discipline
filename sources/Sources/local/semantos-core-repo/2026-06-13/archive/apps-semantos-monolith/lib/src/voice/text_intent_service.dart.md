---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/voice/text_intent_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.866779+00:00
---

# archive/apps-semantos-monolith/lib/src/voice/text_intent_service.dart

```dart
// D-O5m.followup-7 Phase B — typed-NL pipeline path.
//
// Mirrors `voice_command_service.dart`'s shape for the typed-text
// branch of the helm input bar.  The voice path captures audio →
// transcribes via whisper → runs the L1 SIR extractor → optionally
// drives the L1→L4 DartIntentPipeline; the typed-text path skips
// recording + STT entirely and feeds the operator-typed string
// straight into the same pipeline with `Intent.source = 'nl'`.
//
// On-device contract:
//
//   1. The operator types into VoiceTextInputBar's TextField.
//   2. On send-tap, VoiceTextInputBar invokes processText(text).
//   3. processText() runs the L1 SIR extractor (when configured) over
//      the typed text, producing an Intent candidate with source='nl'.
//   4. When the extractor refuses (low confidence, grammar miss, no
//      model), the service surfaces a typed [TextIntentRefused] so the
//      input bar renders the operator-readable refusal reason.
//   5. When the extractor succeeds AND a DartIntentPipeline is wired,
//      the service runs L1→L2→L3→L4 locally and surfaces the final
//      typed result on [TextIntentOutcome].
//
// Like VoiceCommandService, this never throws on an expected refusal
// — the input bar pattern-matches on the typed outcome.

import 'package:flutter/foundation.dart' show debugPrint;

import '../gradient/dart_pipeline.dart';
import '../gradient/entity_resolver.dart';
import '../gradient/intent_trace_service.dart';
import '../repl/jobs_repository.dart' show Job;
import 'sir_extractor.dart';

/// Failure surface for the typed-text path.  Typed so the input bar
/// can render path-specific recovery prompts.
sealed class TextIntentFailure {
  const TextIntentFailure();
}

/// The L1 SIR extractor refused (low confidence / grammar miss / no
/// on-device model).  In production this maps to "we couldn't confidently
/// extract an intent — please rephrase or use voice".
class TextIntentRefused extends TextIntentFailure {
  final String reason;
  const TextIntentRefused(this.reason);
}

/// The pipeline rejected at SIR-lowering or kernel stage.  Carries the
/// structured rejection so the input bar can show the K1-K4 / lowering
/// reason inline.
class TextIntentRejected extends TextIntentFailure {
  final IntentRejection rejection;
  const TextIntentRejected(this.rejection);
}

/// No SIR extractor was configured for this build (the default when
/// the operator's phone hasn't downloaded a llama.cpp model yet).
/// Surfaces as a refusal to send so the input bar can prompt the
/// operator to use voice instead of typing.
class TextIntentExtractorUnavailable extends TextIntentFailure {
  const TextIntentExtractorUnavailable();
}

/// No DartIntentPipeline was configured.  Production wires this; the
/// dev harness without semantos_ffi loaded surfaces this so the bar
/// can route to the brain-side fallback path.
class TextIntentPipelineUnavailable extends TextIntentFailure {
  const TextIntentPipelineUnavailable();
}

/// Catch-all for unexpected exceptions inside the pipeline (e.g.
/// kernel FFI threw, write_cell failed).  The bar treats this as a
/// soft error — the operator can retry.
class TextIntentNetworkError extends TextIntentFailure {
  final String reason;
  const TextIntentNetworkError(this.reason);
}

/// Result of running [TextIntentService.processText].
sealed class TextIntentOutcome {
  const TextIntentOutcome();
}

/// Full success — the local pipeline produced a signed cell.  The
/// input bar renders the success summary in its inline feedback area.
class TextIntentSuccess extends TextIntentOutcome {
  final IntentSuccess result;
  const TextIntentSuccess(this.result);
}

/// Typed failure — the input bar pattern-matches on the failure shape
/// to render the right inline message.
class TextIntentFailed extends TextIntentOutcome {
  final TextIntentFailure failure;
  const TextIntentFailed(this.failure);
}

/// Pure-Dart service mirroring VoiceCommandService for the typed-text
/// path.  No Flutter dependency — the input bar widget injects this as
/// a constructor arg so the unit-test suite can stay Flutter-SDK-free.
class TextIntentService {
  /// On-device L1 SIR extractor.  Required for the typed-text path —
  /// when null, processText surfaces [TextIntentExtractorUnavailable]
  /// and the input bar falls through to a brain-side path (or just
  /// refuses to send, depending on config).
  final SirExtractor? sirExtractor;

  /// Hat context the SIR extractor scopes Intent production to.
  /// Required when [sirExtractor] is non-null.
  final HatContext? hatContext;

  /// Extension grammar the extractor consumes.  Defaults to oddjobz.
  final ExtensionGrammar extensionGrammar;

  /// Full on-device gradient pipeline.  When non-null AND the SIR
  /// extractor produced a success, the service runs L1->L4 locally
  /// and surfaces the signed cell.  When null, processText returns
  /// [TextIntentPipelineUnavailable].
  ///
  /// 2026-05-07 — superseded by [pipelineForIntent] for the production
  /// path so the per-turn intent fields (summary/action/taxonomy) can
  /// reach the writeCell envelope.  Tests that don't need per-turn
  /// metadata still use this seam.
  final DartIntentPipeline? localPipeline;

  /// Per-turn pipeline factory — invoked once with the SIR-extracted
  /// intent so the deps can render the canonical envelope's
  /// `originalIntent` fields without re-parsing the cell bytes.  Takes
  /// precedence over [localPipeline] when both are set.  Returning
  /// null is equivalent to leaving [localPipeline] null
  /// ([TextIntentPipelineUnavailable]).
  final DartIntentPipeline? Function(Map<String, dynamic> intent)?
      pipelineForIntent;

  /// Pipeline-side hat context.  Required when [localPipeline] /
  /// [pipelineForIntent] is non-null.
  final PipelineHatContext? pipelineHatContext;

  /// Wave 9 follow-up — when supplied, every `processText` call
  /// synthesises StageEvents into the trace recorder, even for the
  /// short-circuit paths that don't reach `DartIntentPipeline`. The
  /// IntentInspectorSheet then shows the user *why* their typed input
  /// didn't fire the pipeline (extractor not loaded, hat missing,
  /// pipeline unavailable, SIR refused, etc.) instead of staying
  /// silent. Same correlationId threads through to the pipeline when
  /// it does fire.
  final IntentTraceService? traceService;

  /// Wave 9 follow-up — supplier of the operator's active jobs cache,
  /// invoked once per turn. The resolver runs over the returned list
  /// to bind `intent.target.jobId` / `customerId` before the cell is
  /// minted. Pass `null` (the default) to disable resolution — the
  /// turn proceeds with whatever `target` the extractor populated.
  final Future<List<Job>> Function()? activeJobsLoader;

  /// Wave 9 follow-up — pluggable resolver. Defaults to the standard
  /// [EntityResolver]; tests inject a deterministic stub.
  final EntityResolver resolver;

  TextIntentService({
    this.sirExtractor,
    this.hatContext,
    this.extensionGrammar = ExtensionGrammar.oddjobz,
    this.localPipeline,
    this.pipelineForIntent,
    this.pipelineHatContext,
    this.traceService,
    this.activeJobsLoader,
    EntityResolver? resolver,
  }) : resolver = resolver ?? EntityResolver();

  /// Producer-side correlationId minted once per processText call.
  /// Mirrors `produceIntent` in @semantos/intent (RM-091).
  String _mintCorrelationId() {
    // Cheap unique-ish id without pulling uuid into this file's deps.
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final rnd = identityHashCode(Object()).toRadixString(16);
    return 'corr-text-$ts-$rnd';
  }

  /// Synthesise an `intent_produced` event into the trace so the
  /// inspector picks up the turn even when the pipeline never fires.
  void _emitProduced(String cid, String text) {
    traceService?.recordEvent(PipelineStageEvent(
      correlationId: cid,
      stage: 'intent_produced',
      durationMs: 0,
      data: {
        'source': 'nl',
        'rawInputLength': text.length,
        'rawInputDigest': _digest(text),
      },
    ));
  }

  /// Synthesise an `intent_rejected` event at the producer stage with
  /// a typed reason. Used for the four short-circuit paths
  /// (extractor / hat / SIR / pipeline unavailable).
  void _emitRejected({
    required String cid,
    required String code,
    required String message,
    double durationMs = 0,
  }) {
    traceService?.recordEvent(PipelineStageEvent(
      correlationId: cid,
      stage: 'intent_rejected',
      durationMs: durationMs,
      data: {
        'stage': 'producer',
        'code': code,
        'message': message,
      },
    ));
  }

  /// Wave 9 follow-up — load active jobs and run the resolver. Patches
  /// `intent['target']` in place with `jobId` / `customerId` from the
  /// match. Emits a synthetic `entity_resolved` or `entity_unresolved`
  /// stage event into the trace so the inspector renders which job
  /// was selected (or why nothing matched).
  ///
  /// Failures (loader throws, resolver throws) are swallowed and
  /// emitted as `entity_unresolved · loader_threw` so resolution
  /// never breaks the pipeline path.
  Future<void> _runEntityResolver({
    required String cid,
    required String trimmed,
    required Map<String, dynamic> intent,
  }) async {
    final loader = activeJobsLoader;
    if (loader == null) return; // resolver disabled

    final started = DateTime.now();
    List<Job> jobs;
    try {
      jobs = await loader();
    } catch (e) {
      _recordEvent(
        cid: cid,
        stage: 'entity_unresolved',
        durationMs: _elapsedMs(started),
        data: {
          'code': 'loader_threw',
          'reason': 'activeJobsLoader threw: $e',
        },
      );
      return;
    }

    final taxonomy = intent['taxonomy'];
    final taxonomyWhere = taxonomy is Map<String, dynamic>
        ? taxonomy['where'] as String?
        : null;
    final summary = intent['summary'] as String?;
    final result = resolver.resolve(
      activeJobs: jobs,
      transcript: trimmed,
      summary: summary,
      taxonomyWhere: taxonomyWhere,
    );

    if (result is ResolutionMatched) {
      // Merge the resolved ids into target. Preserve any existing
      // target fields (amount, currency, etc.) the extractor populated.
      final existingTarget = intent['target'];
      final target = <String, dynamic>{
        if (existingTarget is Map<String, dynamic>) ...existingTarget,
        'jobId': result.jobId,
        if (result.customerId != null) 'customerId': result.customerId,
      };
      intent['target'] = target;
      _recordEvent(
        cid: cid,
        stage: 'entity_resolved',
        durationMs: _elapsedMs(started),
        data: {
          'jobId': result.jobId,
          'customerId': result.customerId,
          'score': result.score,
          'runnerUpScore': result.runnerUpScore,
          'reason': result.reason,
        },
      );
    } else if (result is ResolutionUnresolved) {
      _recordEvent(
        cid: cid,
        stage: 'entity_unresolved',
        durationMs: _elapsedMs(started),
        data: {
          'code': result.code,
          'reason': result.reason,
        },
      );
    }
  }

  /// Internal helper — emit a PipelineStageEvent on the trace recorder
  /// when one is wired. No-op otherwise.
  void _recordEvent({
    required String cid,
    required String stage,
    required double durationMs,
    required Map<String, dynamic> data,
  }) {
    traceService?.recordEvent(PipelineStageEvent(
      correlationId: cid,
      stage: stage,
      durationMs: durationMs,
      data: data,
    ));
  }

  double _elapsedMs(DateTime started) =>
      DateTime.now().difference(started).inMicroseconds / 1000.0;

  /// 16-hex-char fingerprint over the input. Same shape as RM-091's
  /// digest so traces are comparable across producer paths.
  String _digest(String s) {
    int h = 0xcbf29ce4;
    for (int i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Run the typed-text path.  Never throws — returns a typed outcome.
  Future<TextIntentOutcome> processText({required String text}) async {
    // 2026-05-07 release-active diagnostic prints — operator's release
    // APK was hanging in submit() with no [pipeline] logs, so we don't
    // know where the stall is.  These mark each phase boundary.
    debugPrint('[textintent] enter processText text.len=${text.length}');
    final trimmed = text.trim();
    final cid = _mintCorrelationId();
    _emitProduced(cid, trimmed);
    if (trimmed.isEmpty) {
      debugPrint('[textintent] empty input, refused');
      _emitRejected(
        cid: cid,
        code: 'empty_input',
        message: 'typed text was empty after trim',
      );
      return const TextIntentFailed(TextIntentRefused('empty input'));
    }
    final extractor = sirExtractor;
    final hat = hatContext;
    debugPrint('[textintent] extractor=${extractor != null} hat=${hat != null} '
        'pipelineForIntent=${pipelineForIntent != null} '
        'localPipeline=${localPipeline != null} '
        'pipelineHatContext=${pipelineHatContext != null}');
    if (extractor == null || hat == null) {
      debugPrint('[textintent] extractor or hat null → ExtractorUnavailable');
      _emitRejected(
        cid: cid,
        code: 'extractor_unavailable',
        message: extractor == null
            ? 'SIR extractor not configured — rebuild with --dart-define=ANTHROPIC_API_KEY=sk-ant-...'
            : 'hat context not bound (identity not paired?)',
      );
      return const TextIntentFailed(TextIntentExtractorUnavailable());
    }

    // L1 — extract a SIR candidate.  The extractor refuses below 0.6
    // confidence; the input bar surfaces this verbatim.
    //
    // Wave 9 PWA — emit an in-flight `sir_extracting` event BEFORE the
    // await so the inspector shows the turn is sitting in extraction.
    // Without this the trace stays silent between `intent_produced`
    // and either success/refusal/timeout, which is indistinguishable
    // from "stuck" to a user staring at the inspector.
    traceService?.recordEvent(PipelineStageEvent(
      correlationId: cid,
      stage: 'sir_extracting',
      durationMs: 0,
      data: {
        'transcriptLength': trimmed.length,
        'grammar': extensionGrammar.toString(),
      },
    ));
    SirExtractionResult sirResult;
    final extractStart = DateTime.now();
    try {
      debugPrint('[textintent] calling extractor.extract — awaiting Anthropic /v1/messages');
      sirResult = await extractor.extract(
        transcript: trimmed,
        hatContext: hat,
        grammar: extensionGrammar,
      );
      debugPrint('[textintent] extractor.extract returned: ${sirResult.runtimeType}');
      // Stamp the completion event with the actual wall-time so the
      // inspector reveals slow llama inference / brain-side fallbacks.
      traceService?.recordEvent(PipelineStageEvent(
        correlationId: cid,
        stage: 'sir_extracted',
        durationMs:
            DateTime.now().difference(extractStart).inMicroseconds / 1000.0,
        data: {
          'outcome': sirResult.runtimeType.toString(),
        },
      ));
    } catch (e) {
      debugPrint('[textintent] extractor.extract threw: $e');
      _emitRejected(
        cid: cid,
        code: 'extractor_exception',
        message: 'SIR extractor threw: $e',
        durationMs:
            DateTime.now().difference(extractStart).inMicroseconds / 1000.0,
      );
      return TextIntentFailed(TextIntentNetworkError('extractor threw: $e'));
    }
    if (sirResult is SirExtractionRefused) {
      debugPrint('[textintent] sir refused: ${sirResult.reason}');
      _emitRejected(
        cid: cid,
        code: 'sir_refused',
        message: 'SIR extractor refused: ${sirResult.reason}',
        durationMs:
            DateTime.now().difference(extractStart).inMicroseconds / 1000.0,
      );
      return TextIntentFailed(TextIntentRefused(sirResult.reason));
    }
    final extracted = sirResult as SirExtractionSuccess;
    debugPrint('[textintent] sir success — confidence=${extracted.confidence}');

    // Stamp the source as 'nl' (typed natural language) — voice path
    // sets it to 'voice'; both are valid Intent.source values.  The
    // brain audit log uses this to differentiate paths.
    final intent = Map<String, dynamic>.from(extracted.intent);
    intent['source'] = 'nl';
    // Thread the producer's correlationId so the pipeline events land
    // under the same group as the producer's `intent_produced`.
    intent['correlationId'] = cid;

    // Wave 9 follow-up — entity resolution. Run the resolver over the
    // operator's active jobs and patch `intent.target` with the
    // resolved jobId / customerId BEFORE the cell is minted. The
    // brain's intent_action_router honours target.jobId directly
    // (when present) and skips the `intent_summary` substring
    // heuristic. Emits a typed `entity_resolved` / `entity_unresolved`
    // event into the trace so the user sees WHICH job was bound (or
    // why no match) from the inspector.
    await _runEntityResolver(cid: cid, trimmed: trimmed, intent: intent);

    // 2026-05-07 — prefer the per-turn factory when set so deps can
    // close over this turn's intent metadata.  Falls back to a fixed
    // [localPipeline] for tests that don't need per-turn metadata.
    final pipeline =
        pipelineForIntent != null ? pipelineForIntent!(intent) : localPipeline;
    final pipelineHat = pipelineHatContext;
    debugPrint('[textintent] pipeline built: pipeline=${pipeline != null} '
        'pipelineHat=${pipelineHat != null}');
    if (pipeline == null || pipelineHat == null) {
      debugPrint('[textintent] pipeline or pipelineHat null → PipelineUnavailable');
      _emitRejected(
        cid: cid,
        code: 'pipeline_unavailable',
        message: pipeline == null
            ? 'pipelineForIntent returned null (kernel/outbox/hat missing)'
            : 'pipelineHatContext not bound',
      );
      return const TextIntentFailed(TextIntentPipelineUnavailable());
    }
    debugPrint('[textintent] calling pipeline.process — kernel + outbox enqueue');

    // L1 → L4 — drive the local gradient pipeline.  Expected
    // rejections (SIR-lowering / kernel) come back as IntentRejected;
    // unexpected exceptions surface as a network-style soft error so
    // the input bar can offer a retry. The pipeline emits its own
    // StageEvents through deps.emit — they share `cid` because we
    // stamped it on `intent['correlationId']` above.
    IntentResult result;
    try {
      result = await pipeline.process(
        intent: intent,
        hatContext: pipelineHat,
      );
    } catch (e, st) {
      // Capture the first 6 frames of the stack so the inspector
      // shows WHICH cast/access blew up. Without this we get
      // `type 'Null' is not a subtype of String` with no location —
      // unactionable from the UI.
      final frames = st.toString().split('\n').take(6).join('\n');
      debugPrint('[textintent] pipeline threw: $e\n$frames');
      _emitRejected(
        cid: cid,
        code: 'pipeline_threw',
        message: 'pipeline.process threw: $e\n$frames',
      );
      return TextIntentFailed(
        TextIntentNetworkError('pipeline threw: $e'),
      );
    }

    if (result is IntentRejected) {
      return TextIntentFailed(TextIntentRejected(result.rejection));
    }
    return TextIntentSuccess(result as IntentSuccess);
  }
}

```
