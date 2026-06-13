---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/llama_cpp/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.991499+00:00
---

# platforms/flutter/llama_cpp/pubspec.yaml

```yaml
name: llama_cpp
description: >
  Flutter FFI plugin wrapping llama.cpp for on-device LLM inference
  with grammar-constrained generation.  Backs the D-O5m.followup-3
  Phase 2 voice → L1 SIR extraction pipeline; the model file is
  downloaded on first use and cached under `getApplicationSupportDirectory()`,
  the llama.cpp source is fetched at plugin build time (NOT vendored)
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
      # 2026-05-07 — iOS ffi plugin temporarily disabled. The vendored
      # iOS-linked llama.cpp library is older than the headers expected
      # by `llama_cpp_shim.cpp` (new sampler API: `llama_sampler*`,
      # `llama_batch_get_one` signature change). Compilation fails on
      # iOS only; Dart-side imports still resolve. Restore by either
      # rebuilding the iOS xcframework against the current llama.cpp
      # head, or pinning `llama_cpp_shim.cpp` to the older API surface.
      # Bridget hit this on iOS Simulator first-run (2026-05-07).
      # ios:
      #   ffiPlugin: true
      android:
        ffiPlugin: true
      macos:
        ffiPlugin: true

```
