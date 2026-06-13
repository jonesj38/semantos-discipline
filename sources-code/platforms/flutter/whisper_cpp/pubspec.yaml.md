---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.991109+00:00
---

# platforms/flutter/whisper_cpp/pubspec.yaml

```yaml
name: whisper_cpp
description: >
  Flutter FFI plugin wrapping whisper.cpp for on-device speech-to-text.
  Backs the D-O5m.followup-3 voice command pipeline; the model file is
  downloaded on first use and cached under `getApplicationSupportDirectory()`,
  the whisper.cpp source is fetched at plugin build time (NOT vendored)
  and pinned to a specific upstream commit for reproducibility.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.11.0
  flutter: ^3.41.0

dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.1.0
  path_provider: ^2.1.0
  http: ^1.2.0
  crypto: ^3.0.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  test: ^1.25.0

flutter:
  plugin:
    platforms:
      # 2026-05-07 — iOS ffi plugin temporarily disabled, paired with
      # the same change in llama_cpp/pubspec.yaml. Voice transcription
      # in iOS Simulator is unexercisable anyway (no mic), and the iOS
      # binary mismatch in llama_cpp would block build regardless.
      # Bridget hit this on iOS Simulator first-run (2026-05-07).
      # ios:
      #   ffiPlugin: true
      android:
        ffiPlugin: true
      macos:
        ffiPlugin: true

```
