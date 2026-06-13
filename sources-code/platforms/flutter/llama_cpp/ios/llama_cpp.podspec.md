---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/llama_cpp/ios/llama_cpp.podspec
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.022371+00:00
---

# platforms/flutter/llama_cpp/ios/llama_cpp.podspec

```podspec
# D-O5m.followup-3 Phase 2 — llama.cpp Flutter FFI plugin (iOS).
#
# Reference: platforms/flutter/whisper_cpp/ios/whisper_cpp.podspec
#            (the Phase 1 sibling -- same prepare_command + GGML_USE_
#            ACCELERATE pattern).
#
# llama.cpp source is fetched at pod-install time from upstream
# (NOT vendored in this repo) and pinned to the recorded commit.
# A `prepare_command` shells out to `git clone --depth 1 --branch <pin>`
# and the upstream sources land under Sources/llama.cpp/.  The
# cocoapod compiles those sources directly via `s.source_files`.

LLAMA_CPP_PIN = 'b3500'

Pod::Spec.new do |s|
  s.name             = 'llama_cpp'
  s.version          = '0.1.0'
  s.summary          = 'Flutter FFI plugin wrapping llama.cpp for on-device LLM inference.'
  s.description      = <<-DESC
    Flutter FFI plugin that links llama.cpp for on-device LLM inference
    with grammar-constrained generation.  The llama.cpp sources are
    fetched at pod-install time from the upstream GitHub repository
    (NOT vendored in semantos-core) and pinned to a specific tag
    (#{LLAMA_CPP_PIN}) for build reproducibility.
  DESC
  s.homepage         = 'https://semantos.io'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Semantos' => 'hello@semantos.io' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'

  # Fetch llama.cpp at the pinned tag during pod install.
  s.prepare_command = <<-CMD
    set -e
    if [ ! -d "Sources/llama.cpp" ]; then
      git clone --depth 1 --branch #{LLAMA_CPP_PIN} \
        https://github.com/ggerganov/llama.cpp.git Sources/llama.cpp
    fi
  CMD

  # Compile a thin shim plus the upstream llama.cpp + ggml sources.
  # The exact source list mirrors what whisper.cpp's podspec uses --
  # grouped GGML kernels + the model-loading translation unit.
  s.source_files = [
    'Sources/llama_cpp_shim.cpp',
    'Sources/llama.cpp/src/llama.cpp',
    'Sources/llama.cpp/src/llama-vocab.cpp',
    'Sources/llama.cpp/src/llama-grammar.cpp',
    'Sources/llama.cpp/src/llama-sampling.cpp',
    'Sources/llama.cpp/src/unicode.cpp',
    'Sources/llama.cpp/src/unicode-data.cpp',
    'Sources/llama.cpp/ggml/src/ggml.c',
    'Sources/llama.cpp/ggml/src/ggml-alloc.c',
    'Sources/llama.cpp/ggml/src/ggml-backend.c',
    'Sources/llama.cpp/ggml/src/ggml-quants.c',
  ]
  s.public_header_files = []
  s.preserve_paths = 'Sources/llama.cpp/**/*'
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Sources/llama.cpp/include" "$(PODS_TARGET_SRCROOT)/Sources/llama.cpp/src" "$(PODS_TARGET_SRCROOT)/Sources/llama.cpp/ggml/include" "$(PODS_TARGET_SRCROOT)/Sources/llama.cpp/ggml/src" "$(PODS_TARGET_SRCROOT)/Sources/llama.cpp/common"',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'GGML_USE_ACCELERATE=1 GGML_USE_METAL=1',
    'OTHER_CFLAGS' => '-O3 -DNDEBUG',
  }
  s.frameworks = ['Accelerate', 'Metal', 'MetalKit', 'Foundation']
end

```
