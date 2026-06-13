---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/llama_cpp/lib/src/bindings.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.025871+00:00
---

# platforms/flutter/llama_cpp/lib/src/bindings.dart

```dart
// D-O5m.followup-3 Phase 2 — dart:ffi bindings to llama.cpp.
//
// Reference: upstream llama.cpp public headers — `llama.h`.  The
// bindings here cover the entry points the high-level [LlamaService]
// uses, exposed via a thin shim (`llama_cpp_shim.cpp` per-platform)
// that decouples this Dart surface from upstream's evolving C++ API:
//
//   - llama_open(model_path: char*) -> llama_handle*
//   - llama_complete(handle, prompt, grammar, max_tokens, temperature,
//                    out_buf, out_cap) -> int (bytes written, -1 fail)
//   - llama_close(handle)
//
// We DO NOT vendor llama.cpp source in the repo (~120k lines of
// C++).  Instead the platform-side build wiring (android/CMakeLists.
// txt and the iOS/macOS podspec) fetches the upstream repo at build
// time and pins to the recorded commit.  See `kLlamaCppPin` below.
//
// The base class [LlamaBindingsBase] is the seam tests inject -- a
// stub impl asserts the right calls happen on `complete()` without
// loading a multi-GiB model.

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Pinned upstream llama.cpp commit / tag.  CMake / CocoaPods
/// FetchContent stanzas reference this exact rev so a clean build is
/// reproducible.  Update via the audited `update-llama-pin` flow only
/// -- bumping this changes the C ABI surface covered by
/// [LlamaBindings].
///
/// Pin target: a stable b3000+ tagged release.  `b3500` covers GGUF
/// v3 models (which the default Llama-3.2-3B model uses) and the
/// stable grammar-constrained sampler API.
const String kLlamaCppPin = 'b3500';

/// Default model identifier -- best license + structured-output
/// tradeoff for English-only on-device use.  See [LlamaModel.llama32_3b].
/// Multilingual or larger models swap in via [LlamaModel] config.
const String kDefaultModelName = 'llama-3.2-3b-instruct-q4-k-m';

/// Abstract base -- the seam tests inject.  Production wires
/// [LlamaBindings] which loads the real dynamic library.
abstract class LlamaBindingsBase {
  /// Open a llama.cpp context from a GGUF model file at [modelPath].
  /// Returns an opaque handle (`!= 0` on success, `0` on failure).
  int open(String modelPath);

  /// Run a completion against [prompt].  When [grammarBNF] is non-null
  /// the sampler filters every token through that GBNF grammar; the
  /// model literally cannot emit a non-matching string.  [maxTokens]
  /// caps the output length; [temperature] of 0 means greedy.
  ///
  /// Returns the model's text output.  Throws on inference failure.
  String complete({
    required int handle,
    required String prompt,
    String? grammarBNF,
    int maxTokens = 512,
    double temperature = 0.0,
  });

  /// Release the context.  Safe to call with 0/null.
  void close(int handle);
}

/// Production bindings -- load the dynamic library produced by the
/// platform-side build (CMake on Android, podspec on iOS/macOS).
///
/// On Android: libllama.so in the APK's lib/<abi>/ directory.
/// On iOS / macOS: linked via the podspec's vendored framework.
class LlamaBindings extends LlamaBindingsBase {
  static const _libName = 'llama';

  late final DynamicLibrary _dylib;

  // C ABI typedefs -- match the shim in `llama_cpp_shim.cpp`.
  late final Pointer<Void> Function(Pointer<Utf8>) _open;
  late final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    int,
    double,
    Pointer<Utf8>,
    int,
  ) _complete;
  late final void Function(Pointer<Void>) _close;

  LlamaBindings._(this._dylib) {
    _open = _dylib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Utf8>)>>(
            'llama_shim_open')
        .asFunction();
    _complete = _dylib
        .lookup<
                NativeFunction<
                    Int32 Function(
                      Pointer<Void>,
                      Pointer<Utf8>,
                      Pointer<Utf8>,
                      Int32,
                      Float,
                      Pointer<Utf8>,
                      Int32,
                    )>>('llama_shim_complete')
        .asFunction();
    _close = _dylib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('llama_shim_close')
        .asFunction();
  }

  /// Open the platform's llama dynamic library.  Throws if the
  /// library could not be loaded -- usually a misconfigured podspec
  /// or missing CMake target.
  factory LlamaBindings.open() {
    DynamicLibrary lib;
    if (Platform.isIOS || Platform.isMacOS) {
      lib = DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      lib = DynamicLibrary.open('lib$_libName.so');
    } else {
      throw UnsupportedError(
          'llama_cpp does not support ${Platform.operatingSystem}');
    }
    return LlamaBindings._(lib);
  }

  @override
  int open(String modelPath) {
    final cStr = modelPath.toNativeUtf8();
    try {
      final ptr = _open(cStr);
      return ptr.address;
    } finally {
      calloc.free(cStr);
    }
  }

  @override
  String complete({
    required int handle,
    required String prompt,
    String? grammarBNF,
    int maxTokens = 512,
    double temperature = 0.0,
  }) {
    if (handle == 0) {
      throw StateError('llama_cpp: cannot complete on a null handle');
    }
    if (maxTokens <= 0) {
      throw ArgumentError(
          'llama_cpp: maxTokens must be positive, got $maxTokens');
    }
    final ctx = Pointer<Void>.fromAddress(handle);
    final pPrompt = prompt.toNativeUtf8();
    final pGrammar = (grammarBNF ?? '').toNativeUtf8();
    // Output buffer sized so even a verbose 512-token Intent fits;
    // 16 KiB covers a token-per-byte upper bound with margin.
    const cap = 16 * 1024;
    final out = calloc<Uint8>(cap).cast<Utf8>();
    try {
      final n = _complete(
        ctx,
        pPrompt,
        pGrammar,
        maxTokens,
        temperature,
        out,
        cap,
      );
      if (n < 0) {
        throw StateError('llama_cpp: completion returned $n');
      }
      // Slice the first n bytes back into Dart.
      final raw = out.cast<Uint8>().asTypedList(n);
      return String.fromCharCodes(raw);
    } finally {
      calloc.free(pPrompt);
      calloc.free(pGrammar);
      calloc.free(out);
    }
  }

  @override
  void close(int handle) {
    if (handle == 0) return;
    _close(Pointer<Void>.fromAddress(handle));
  }
}

```
