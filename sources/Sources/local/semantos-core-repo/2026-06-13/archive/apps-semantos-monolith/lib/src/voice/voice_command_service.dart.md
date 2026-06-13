---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/voice/voice_command_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.866184+00:00
---

# archive/apps-semantos-monolith/lib/src/voice/voice_command_service.dart

```dart
// D-O5m.followup-3 — voice-command orchestrator.
//
// Drives the full mobile-side flow for a voice command:
//
//   1. Records audio via the existing #317 voice_memo_capture infra
//      (a single-shot recorder with a 30-second cap — caps are short
//      because the brain-side STT shellout is the dominant cost).
//   2. Transcribes the recorded audio via WhisperService (whisper_cpp
//      Flutter FFI plugin).
//   3. Creates a cert-bound VoiceSession + signs the resulting
//      Transcript via voice_session_service.
//   4. Phase 2: optionally runs on-device L1 SIR extraction via
//      llama.cpp (SirExtractor seam) when a model is available
//      locally; refusals fall through to the Phase 1 brain-side path.
//   5. Returns a [VoiceCommandRecording] for the UI to display +
//      operator-review before posting to the brain.
//
// The result is consumed by:
//   - voice_command_sheet.dart (operator review UI), then
//   - voice_extract_uploader.dart (multipart POST to the brain), with
//     fallback enqueue to the outbox when offline.
//
// When [sirExtractor] is non-null and the on-device extraction
// succeeds, the produced Intent travels alongside the audio +
// transcript in the multipart POST as the `sir_candidate` part.
// The brain skips its L0->L1 producer adapter; L2-L4 still run.
// Phase 3 ports L2-L4 on-device, at which point the brain shellout
// disappears entirely.

import 'dart:async';
import 'dart:typed_data';

import '../gradient/dart_pipeline.dart';
import '../identity/child_cert_store.dart';
import 'sir_extractor.dart';
import 'voice_session_service.dart';

/// Abstract STT seam — production wires `WhisperService` from the
/// `whisper_cpp` plugin; tests inject a stub returning fixture text.
abstract class VoiceTranscriber {
  Future<String> transcribe(Uint8List pcmAudioBytes,
      {String language = 'en'});
}

/// One end-to-end captured + transcribed voice command, ready to
/// present to the operator and POST to the brain (Phase 1/2) or
/// flush as a locally-signed cell (Phase 3).
class VoiceCommandRecording {
  final Uint8List audioBytes;
  final String mimeType;
  final Transcript transcript;
  final int durationMs;

  /// Phase 2 — on-device extracted SIR candidate.  Null when the
  /// extractor was unavailable, refused, or not configured.  When
  /// non-null, [VoiceExtractUploader] sends it as the
  /// `sir_candidate` multipart part and the brain skips L0->L1.
  /// When null the brain runs the full Phase 1 path.
  final SirExtractionResult? sirExtractionResult;

  /// Phase 3 — outcome of the on-device L1->L4 pipeline, when the
  /// service is configured with a [DartIntentPipeline] AND the SIR
  /// extractor produced a candidate AND the local pipeline didn't
  /// throw. Null in any of these failure modes; the caller falls back
  /// to the Phase 1/2 brain-side path. When non-null and successful,
  /// the cell is already signed + locally persisted; the outbox just
  /// flushes the cell to the brain when connectivity returns.
  final IntentResult? localPipelineResult;

  const VoiceCommandRecording({
    required this.audioBytes,
    required this.mimeType,
    required this.transcript,
    required this.durationMs,
    this.sirExtractionResult,
    this.localPipelineResult,
  });

  /// Convenience: the underlying Intent map when extraction
  /// succeeded; null otherwise.  Uploader uses this to decide
  /// whether to include the `sir_candidate` multipart part.
  Map<String, dynamic>? get sirCandidate {
    final r = sirExtractionResult;
    return r is SirExtractionSuccess ? r.intent : null;
  }

  /// Phase 3 convenience: did the local pipeline produce a signed
  /// cell? When true the operator UI shows the "signed locally;
  /// syncing to brain" path; when false (or null) the
  /// [VoiceExtractUploader] takes the brain-side path.
  bool get hasLocalSuccess => localPipelineResult is IntentSuccess;
}

/// Failure surface for the orchestrator. Typed so the UI can render
/// specific recovery prompts.
sealed class VoiceCommandFailure {
  const VoiceCommandFailure();
}

class VoiceCommandRecorderUnavailable extends VoiceCommandFailure {
  final String reason;
  const VoiceCommandRecorderUnavailable(this.reason);
}

class VoiceCommandTranscriptionFailed extends VoiceCommandFailure {
  final String reason;
  const VoiceCommandTranscriptionFailed(this.reason);
}

class VoiceCommandNotPaired extends VoiceCommandFailure {
  const VoiceCommandNotPaired();
}

class VoiceCommandCancelled extends VoiceCommandFailure {
  const VoiceCommandCancelled();
}

/// Result type — either a recording ready for review, or a typed
/// failure for the UI to render.
sealed class VoiceCommandOutcome {
  const VoiceCommandOutcome();
}

class VoiceCommandReady extends VoiceCommandOutcome {
  final VoiceCommandRecording recording;
  const VoiceCommandReady(this.recording);
}

class VoiceCommandFailed extends VoiceCommandOutcome {
  final VoiceCommandFailure failure;
  const VoiceCommandFailed(this.failure);
}

/// Orchestrator. The recorder is owned by the caller (so the
/// recording sheet UI can stop/cancel mid-flow); this service threads
/// through the transcribe + sign + (Phase 2) SIR-extract steps.
class VoiceCommandService {
  final ChildCertStore certStore;
  final VoiceTranscriber transcriber;

  /// Phase 2 — on-device L1 SIR extractor.  When non-null + the
  /// underlying llama.cpp model is reachable, the orchestrator runs
  /// extraction after transcribe + sign and surfaces the result on
  /// [VoiceCommandRecording.sirExtractionResult].  Null = Phase 1
  /// fallback (brain-side extraction).
  final SirExtractor? sirExtractor;

  /// Hat context the SIR extractor scopes Intent production to.
  /// Required when [sirExtractor] is non-null; ignored otherwise.
  final HatContext? hatContext;

  /// Extension grammar the extractor consumes.  Defaults to the
  /// oddjobz trades-lexicon shape; multi-extension deployments
  /// inject a different one.
  final ExtensionGrammar extensionGrammar;

  /// Phase 3 — full on-device gradient pipeline.  When non-null AND
  /// [sirExtractor] produced a SirExtractionSuccess, the orchestrator
  /// runs L1->L4 locally and surfaces the signed cell on
  /// [VoiceCommandRecording.localPipelineResult].  Null leaves the
  /// flow on the Phase 2 fallback path (brain-side L2->L4).
  final DartIntentPipeline? localPipeline;

  /// Pipeline-side hat context. Mirrors [hatContext] but in the
  /// Phase-3 [PipelineHatContext] shape (richer trust + domain
  /// surface). Required when [localPipeline] is non-null.
  final PipelineHatContext? pipelineHatContext;

  VoiceCommandService({
    required this.certStore,
    required this.transcriber,
    this.sirExtractor,
    this.hatContext,
    this.extensionGrammar = ExtensionGrammar.oddjobz,
    this.localPipeline,
    this.pipelineHatContext,
  });

  /// Convert a recorded clip into a signed transcript + (Phase 2)
  /// optional SIR candidate.  Returns a typed [VoiceCommandOutcome]
  /// — never throws.
  ///
  /// [recordedBytes] / [mimeType] / [durationMs] come from
  /// `VoiceRecorderController.stop()` (the same shape the existing
  /// voice_memo_capture flow uses).
  Future<VoiceCommandOutcome> processRecording({
    required Uint8List recordedBytes,
    required String mimeType,
    required int durationMs,
    String language = 'en',
    int sequence = 0,
  }) async {
    final record = await certStore.read();
    if (record == null) {
      return const VoiceCommandFailed(VoiceCommandNotPaired());
    }
    final String text;
    try {
      text = await transcriber.transcribe(recordedBytes, language: language);
    } catch (e) {
      return VoiceCommandFailed(
          VoiceCommandTranscriptionFailed(e.toString()));
    }
    if (text.trim().isEmpty) {
      return const VoiceCommandFailed(
          VoiceCommandTranscriptionFailed('empty transcript'));
    }
    final session = await createVoiceSession(certStore: certStore);
    final priv = _hexToBytes(record.devicePrivHex);
    final signer = makeCellSignerVoiceSigner(
      devicePrivBytes: priv,
      certId: session.certId,
    );
    final transcript = addTranscript(
      session: session,
      text: text,
      signer: signer,
      sequence: sequence,
    );

    // Phase 2 — on-device SIR extraction.  Refusals (low confidence,
    // grammar miss, no model) fall through to brain-side extraction
    // by leaving sirExtractionResult unset.  Exceptions are caught
    // and wrapped as refusals so a buggy extractor never tanks the
    // full voice flow -- the operator can still send the transcript.
    SirExtractionResult? sirResult;
    if (sirExtractor != null && hatContext != null) {
      try {
        sirResult = await sirExtractor!.extract(
          transcript: text,
          hatContext: hatContext!,
          grammar: extensionGrammar,
        );
      } catch (e) {
        sirResult = SirExtractionRefused('extractor threw: $e');
      }
    }

    // Phase 3 — full on-device L1->L4 pipeline.  Runs only when the
    // SIR extractor succeeded (we have a candidate Intent to feed
    // through the gradient) AND the orchestrator + hat are wired.
    // Failures here don't tank the recording -- the operator can
    // still send the brain-side fallback path.
    IntentResult? local;
    if (localPipeline != null &&
        pipelineHatContext != null &&
        sirResult is SirExtractionSuccess) {
      try {
        local = await localPipeline!.process(
          intent: sirResult.intent,
          hatContext: pipelineHatContext!,
        );
      } catch (e) {
        // Don't let pipeline-internal exceptions kill the flow;
        // fallback to Phase 2 path leaves localPipelineResult null.
        local = null;
      }
    }

    return VoiceCommandReady(VoiceCommandRecording(
      audioBytes: recordedBytes,
      mimeType: mimeType,
      transcript: transcript,
      durationMs: durationMs,
      sirExtractionResult: sirResult,
      localPipelineResult: local,
    ));
  }
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

```
