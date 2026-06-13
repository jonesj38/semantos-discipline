---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/lib/src/whisper_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.021388+00:00
---

# platforms/flutter/whisper_cpp/lib/src/whisper_service.dart

```dart
// D-O5m.followup-3 Phase 1 — high-level whisper.cpp service.
//
// Wraps [WhisperBindings] + [WhisperModelManager] into a single
// idiomatic API the mobile voice flow consumes:
//
//     final svc = WhisperService(modelManager: ...);
//     final text = await svc.transcribe(audioBytes, language: 'en');
//
// The bindings are hidden behind [WhisperBindingsBase] so unit tests
// can inject a stub and assert the right calls happen on transcribe()
// without loading the real model.
//
// Audio decoding: Phase 1 accepts raw 16-bit-PCM mono 16kHz bytes (the
// shape `voice_memo_capture.dart` produces). Resampling/decoding from
// other formats (e.g. AAC from iOS recorder) is the caller's job; the
// recorder factory is configured to emit 16k-mono-PCM directly when
// possible.

import 'dart:typed_data';

import 'bindings.dart';
import 'model_manager.dart';

/// Failure modes for [WhisperService.transcribe]. Typed so the UI
/// layer can render specific error states without string-matching.
enum WhisperTranscriptionFailure {
  modelNotDownloaded,
  audioTooShort,
  inferenceFailed,
}

class WhisperTranscriptionError implements Exception {
  final WhisperTranscriptionFailure kind;
  final String message;
  const WhisperTranscriptionError(this.kind, this.message);

  @override
  String toString() => 'WhisperTranscriptionError(${kind.name}): $message';
}

class WhisperService {
  final WhisperModelManager modelManager;
  final WhisperBindingsBase _bindings;

  WhisperService({
    required this.modelManager,
    WhisperBindingsBase? bindings,
  }) : _bindings = bindings ?? WhisperBindings.open();

  /// Transcribe [audioBytes] to text. Audio is expected to be mono
  /// 16kHz 16-bit PCM — either raw, or wrapped in a RIFF/WAVE container
  /// (the on-device `AudioRecorder` writes WAV files; this method
  /// strips the header automatically).
  ///
  /// Throws [WhisperTranscriptionError] on failure.
  Future<String> transcribe(
    Uint8List audioBytes, {
    String language = 'en',
  }) async {
    // Recorder writes WAV files via `AudioEncoder.wav` (see
    // home_screen.dart `_RecordAdapterImpl`).  Pre-fix the entire WAV
    // including its RIFF header was fed straight into _pcm16ToFloat32,
    // which treated header bytes ("RIFF", file size, "WAVE", "fmt ",
    // "data", chunk sizes) as PCM samples.  Whisper's mel-spectrogram
    // then consumed those bogus samples and the transformer beam-search
    // walked off into adjacent memory — observed on a Samsung S20 FE as
    // `Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr
    // 0x65002e00720065` (= UTF-16 LE text "er.e" — text being deref'd
    // as a pointer is the textbook signature of buffer-overrun memory
    // corruption inside whisper.cpp).  Strip the header here so whisper
    // gets clean PCM.
    final pcmBytes = _stripWavHeader(audioBytes);
    if (pcmBytes.length < 32000) {
      // <1 second of 16kHz 16-bit PCM — likely a misfired record;
      // surface as a typed error so the UI can re-prompt.
      throw const WhisperTranscriptionError(
        WhisperTranscriptionFailure.audioTooShort,
        'audio must be at least 1 second of 16kHz 16-bit PCM',
      );
    }
    if (!await modelManager.isCached()) {
      throw const WhisperTranscriptionError(
        WhisperTranscriptionFailure.modelNotDownloaded,
        'whisper model not downloaded — call WhisperModelManager.ensureModelDownloaded() first',
      );
    }
    final modelFile = await modelManager.resolveModelFile();
    final ctx = _bindings.initFromFile(modelFile.path);
    if (ctx == 0) {
      throw const WhisperTranscriptionError(
        WhisperTranscriptionFailure.inferenceFailed,
        'whisper_init_from_file returned a null context',
      );
    }
    try {
      final samples = _pcm16ToFloat32(pcmBytes);
      final text = _bindings.runFull(
        ctxHandle: ctx,
        samples: samples,
        language: language,
      );
      return text.trim();
    } catch (e) {
      throw WhisperTranscriptionError(
        WhisperTranscriptionFailure.inferenceFailed,
        'inference failed: $e',
      );
    } finally {
      _bindings.free(ctx);
    }
  }

  /// If [bytes] starts with a RIFF/WAVE container, return the slice of
  /// its `data` chunk (the raw PCM payload).  Otherwise return [bytes]
  /// unchanged — preserves the contract for callers passing synthetic
  /// raw PCM (tests, future non-WAV recorders).
  ///
  /// Validates that the WAV is the only format whisper here accepts:
  /// PCM, mono, 16 kHz, 16-bit.  Mis-configured recorders fail fast
  /// with a typed error instead of crashing native code inside
  /// whisper.cpp's beam search.
  static Uint8List _stripWavHeader(Uint8List bytes) {
    // Need at minimum RIFF(12) + fmt-chunk-header(8) + fmt(16) +
    // data-chunk-header(8) = 44 bytes before there's any chance of
    // a complete WAV.  Shorter inputs are assumed to be raw PCM.
    if (bytes.length < 44) return bytes;
    // RIFF magic at 0..3
    final ri = bytes;
    if (ri[0] != 0x52 ||
        ri[1] != 0x49 ||
        ri[2] != 0x46 ||
        ri[3] != 0x46 ||
        // WAVE magic at 8..11
        ri[8] != 0x57 ||
        ri[9] != 0x41 ||
        ri[10] != 0x56 ||
        ri[11] != 0x45) {
      return bytes; // not a WAV
    }
    final view = ByteData.sublistView(bytes);
    int offset = 12;
    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    while (offset + 8 <= bytes.length) {
      final chunkId =
          String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = view.getUint32(offset + 4, Endian.little);
      final payloadStart = offset + 8;
      if (chunkId == 'fmt ' && chunkSize >= 16) {
        audioFormat = view.getUint16(payloadStart, Endian.little);
        channels = view.getUint16(payloadStart + 2, Endian.little);
        sampleRate = view.getUint32(payloadStart + 4, Endian.little);
        bitsPerSample = view.getUint16(payloadStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        // Validate format before handing the PCM slice over — wrong
        // format would corrupt whisper's internal state silently
        // because mel-spectrogram has no input validation.
        if (audioFormat != null && audioFormat != 1) {
          throw WhisperTranscriptionError(
            WhisperTranscriptionFailure.inferenceFailed,
            'WAV is not PCM (audioFormat=$audioFormat); whisper needs PCM',
          );
        }
        if (channels != null && channels != 1) {
          throw WhisperTranscriptionError(
            WhisperTranscriptionFailure.inferenceFailed,
            'WAV has $channels channels; whisper needs mono',
          );
        }
        if (sampleRate != null && sampleRate != 16000) {
          throw WhisperTranscriptionError(
            WhisperTranscriptionFailure.inferenceFailed,
            'WAV is $sampleRate Hz; whisper needs 16000 Hz',
          );
        }
        if (bitsPerSample != null && bitsPerSample != 16) {
          throw WhisperTranscriptionError(
            WhisperTranscriptionFailure.inferenceFailed,
            'WAV is $bitsPerSample-bit; whisper needs 16-bit',
          );
        }
        // Clamp dataLen against the actual buffer — some recorders
        // write the chunk size before knowing the final length and the
        // declared size ends up wrong.  Always trust file size over
        // header claim.
        final end =
            (payloadStart + chunkSize).clamp(0, bytes.length).toInt();
        return Uint8List.sublistView(bytes, payloadStart, end);
      }
      // Chunk sizes are padded to even.  Skip past this chunk to the
      // next one (recorders sometimes prepend a JUNK or LIST chunk).
      offset = payloadStart + chunkSize + (chunkSize & 1);
    }
    // Header looked like WAV but had no data chunk.  Caller will
    // hit the audioTooShort guard or _pcm16ToFloat32 will fail
    // cleanly — both are non-crash paths.
    return bytes;
  }

  /// Convert 16-bit signed little-endian PCM bytes to normalised
  /// float32 samples in [-1.0, 1.0]. Pure helper — exposed for tests.
  static List<double> _pcm16ToFloat32(Uint8List bytes) {
    if (bytes.length.isOdd) {
      throw ArgumentError('PCM bytes must be even-length, got ${bytes.length}');
    }
    final samples = List<double>.filled(bytes.length ~/ 2, 0.0);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < samples.length; i++) {
      final s = view.getInt16(i * 2, Endian.little);
      samples[i] = s / 32768.0;
    }
    return samples;
  }
}

```
