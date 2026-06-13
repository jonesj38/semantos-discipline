---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/lib/whisper_cpp.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.019527+00:00
---

# platforms/flutter/whisper_cpp/lib/whisper_cpp.dart

```dart
// D-O5m.followup-3 Phase 1 — whisper.cpp Flutter FFI plugin.
//
// Top-level export. Three pieces:
//
//   - `WhisperBindings` (lib/src/bindings.dart) — dart:ffi typedefs for
//     whisper.cpp's C API (whisper_init_from_file, whisper_full,
//     whisper_full_get_segment_text, whisper_free).
//
//   - `WhisperService` (lib/src/whisper_service.dart) — high-level
//     idiomatic API: `transcribe(Uint8List audioBytes) → Future<String>`.
//     Tests inject a stub bindings impl; production wires the
//     dynamic-library bindings.
//
//   - `WhisperModelManager` (lib/src/model_manager.dart) — downloads +
//     caches + verifies SHA-256 of the whisper.base.en model on first
//     use. Models are NEVER bundled in the app binary; ~140 MiB once
//     downloaded.
//
// See `platforms/flutter/whisper_cpp/README` (forthcoming) for the
// CMake/CocoaPods FetchContent pin used to fetch the upstream
// whisper.cpp source at plugin build time.

export 'src/bindings.dart' show WhisperBindings, WhisperBindingsBase;
export 'src/model_manager.dart'
    show WhisperModelManager, WhisperModel, WhisperModelDownloadProgress;
export 'src/whisper_service.dart'
    show WhisperService, WhisperTranscriptionError;

```
