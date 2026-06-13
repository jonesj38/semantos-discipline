---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/stt_provider.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.016384+00:00
---

# platforms/flutter/semantos_core/lib/src/stt_provider.dart

```dart
/// Speech-to-text seam.
///
/// Implementations:
///   - WhisperSttProvider (semantos_ffi) — on-device whisper.cpp for native
///     targets; works offline, deterministic, ~140MB model.
///   - WebSpeechSttProvider (semantos_web) — browser Web Speech API for PWA;
///     online-only, vendor-dependent (Chrome/Safari implementations differ).
///   - BrainSttProvider — remote STT on the paired brain; works for any
///     target but requires connectivity.
///
/// All implementations produce a [SttResult] that the conversation
/// engine feeds into the SIR extractor. The shell picks one at boot
/// via [NodeResolver].
abstract class SttProvider {
  /// Transcribe an audio sample to text + confidence.
  Future<SttResult> transcribe(SttRequest request);

  /// True if this provider runs entirely on-device (no network call).
  bool get isOnDevice;
}

class SttRequest {
  /// Raw audio bytes (16-bit PCM, 16kHz mono recommended).
  final List<int> audioPcm16;

  /// Optional locale hint (e.g. 'en-AU'). Not all providers honor this.
  final String? localeHint;

  const SttRequest({required this.audioPcm16, this.localeHint});
}

class SttResult {
  final String transcript;
  final double confidence;
  const SttResult({required this.transcript, required this.confidence});
}

```
