---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/macos/whisper_cpp.podspec
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.018546+00:00
---

# platforms/flutter/whisper_cpp/macos/whisper_cpp.podspec

```podspec
# D-O5m.followup-3 Phase 1 — whisper.cpp Flutter FFI plugin (macOS).
#
# Same FetchContent-via-prepare_command pattern as the iOS podspec.
# The macOS minimum is 10.13; the Accelerate framework is available
# back to 10.6.

WHISPER_CPP_PIN = 'v1.6.0'

Pod::Spec.new do |s|
  s.name             = 'whisper_cpp'
  s.version          = '0.1.0'
  s.summary          = 'Flutter FFI plugin wrapping whisper.cpp for on-device STT.'
  s.description      = <<-DESC
    Flutter FFI plugin that links whisper.cpp for on-device speech-to-text.
    macOS variant; the iOS podspec mirrors this with `:ios` platform.
  DESC
  s.homepage         = 'https://semantos.io'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Semantos' => 'hello@semantos.io' }
  s.source           = { :path => '.' }
  s.platform         = :osx, '10.15'
  s.swift_version    = '5.0'

  s.prepare_command = <<-CMD
    set -e
    if [ ! -d "Sources/whisper.cpp" ]; then
      git clone --depth 1 --branch #{WHISPER_CPP_PIN} \
        https://github.com/ggerganov/whisper.cpp.git Sources/whisper.cpp
    fi
  CMD

  s.source_files = [
    'Sources/whisper_cpp_shim.cpp',
    'Sources/whisper.cpp/whisper.cpp',
    'Sources/whisper.cpp/ggml.c',
    'Sources/whisper.cpp/ggml-alloc.c',
    'Sources/whisper.cpp/ggml-backend.c',
    'Sources/whisper.cpp/ggml-quants.c',
  ]
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
