---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/ios/whisper_cpp.podspec
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.018230+00:00
---

# platforms/flutter/whisper_cpp/ios/whisper_cpp.podspec

```podspec
# D-O5m.followup-3 Phase 1 — whisper.cpp Flutter FFI plugin (iOS).
#
# whisper.cpp source is fetched at pod-install time from upstream
# (NOT vendored in this repo) and pinned to the recorded commit.
# A `prepare_command` shells out to `git clone --depth 1 --branch <pin>`
# and the upstream sources land under Sources/whisper.cpp/. The cocoapod
# compiles those sources directly via `s.source_files`.

WHISPER_CPP_PIN = 'v1.6.0'

Pod::Spec.new do |s|
  s.name             = 'whisper_cpp'
  s.version          = '0.1.0'
  s.summary          = 'Flutter FFI plugin wrapping whisper.cpp for on-device STT.'
  s.description      = <<-DESC
    Flutter FFI plugin that links whisper.cpp for on-device speech-to-text.
    The whisper.cpp sources are fetched at pod-install time from the upstream
    GitHub repository (NOT vendored in semantos-core) and pinned to a specific
    tag (#{WHISPER_CPP_PIN}) for build reproducibility.
  DESC
  s.homepage         = 'https://semantos.io'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Semantos' => 'hello@semantos.io' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'

  # Fetch whisper.cpp at the pinned tag during pod install.
  s.prepare_command = <<-CMD
    set -e
    if [ ! -d "Sources/whisper.cpp" ]; then
      git clone --depth 1 --branch #{WHISPER_CPP_PIN} \
        https://github.com/ggerganov/whisper.cpp.git Sources/whisper.cpp
    fi
  CMD

  # Compile a thin shim plus the upstream whisper.cpp + ggml sources.
  s.source_files = [
    'Sources/whisper_cpp_shim.cpp',
    'Sources/whisper.cpp/whisper.cpp',
    'Sources/whisper.cpp/ggml.c',
    'Sources/whisper.cpp/ggml-alloc.c',
    'Sources/whisper.cpp/ggml-backend.c',
    'Sources/whisper.cpp/ggml-quants.c',
  ]
  s.public_header_files = []
  s.preserve_paths = 'Sources/whisper.cpp/**/*'
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Sources/whisper.cpp"',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'GGML_USE_ACCELERATE=1 WHISPER_USE_COREML=0',
    'OTHER_CFLAGS' => '-O3 -DNDEBUG',
  }
  s.frameworks = ['Accelerate']
end

```
