---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/llama_cpp/lib/src/llama_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.025575+00:00
---

# platforms/flutter/llama_cpp/lib/src/llama_service.dart

```dart
// D-O5m.followup-3 Phase 2 — high-level llama.cpp service.
//
// Reference: platforms/flutter/whisper_cpp/lib/src/whisper_service.dart
//            (the Phase 1 sibling -- same shape, same model-cache
//            preflight pattern);
//            apps/oddjobz-mobile/lib/src/voice/sir_extractor.dart
//            (the consumer -- builds an Intent JSON via grammar-
//            constrained generation).
//
// Wraps [LlamaBindings] + [LlamaModelManager] into a single
// idiomatic API the on-device SIR extractor consumes:
//
//     final svc = LlamaService(modelManager: ...);
//     final json = await svc.complete(
//       prompt: '...',
//       grammarBNF: kIntentGrammar,
//     );
//
// The bindings are hidden behind [LlamaBindingsBase] so unit tests
// can inject a stub and assert the right calls happen on `complete()`
// without loading a multi-GiB GGUF file.
//
// 2026-05-07 — production path now runs the FFI work on a background
// isolate via `Isolate.run`.  llama.cpp inference for a 3B model is a
// 2-30s synchronous CPU burn; before the isolate split it ran on the
// UI thread and froze the helm completely while the operator waited
// for "Find me the wattle street job" to come back.  Test path stays
// on the current isolate (injected stub bindings aren't sendable
// across isolates).

import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint;

import 'bindings.dart';
import 'model_manager.dart';

/// Failure modes for [LlamaService.complete].  Typed so the UI layer
/// can render specific error states without string-matching.
enum LlamaCompletionFailure {
  modelNotDownloaded,
  inferenceFailed,
}

class LlamaCompletionError implements Exception {
  final LlamaCompletionFailure kind;
  final String message;
  const LlamaCompletionError(this.kind, this.message);

  @override
  String toString() => 'LlamaCompletionError(${kind.name}): $message';
}

class LlamaService {
  final LlamaModelManager modelManager;
  final LlamaBindingsBase _bindings;

  /// True when the service should spawn a background isolate per
  /// `complete()` call.  Defaults to true in production (no [bindings]
  /// arg supplied) so the FFI call doesn't block the UI thread for
  /// the duration of llama.cpp inference; tests that inject a stub
  /// run synchronously on the current isolate because mock objects
  /// aren't sendable cross-isolate.
  final bool _useIsolate;

  LlamaService({
    required this.modelManager,
    LlamaBindingsBase? bindings,
  })  : _bindings = bindings ?? LlamaBindings.open(),
        _useIsolate = bindings == null;

  /// Run a completion against [prompt].  When [grammarBNF] is non-null
  /// llama.cpp's sampler filters every emitted token through that
  /// GBNF grammar; non-matching strings are unsamplable.  This is the
  /// load-bearing primitive the SIR extractor uses to guarantee the
  /// output is a valid Intent JSON regardless of model accuracy.
  ///
  /// Throws [LlamaCompletionError] on failure.
  Future<String> complete({
    required String prompt,
    String? grammarBNF,
    int maxTokens = 512,
    double temperature = 0.0,
  }) async {
    debugPrint('[llama] complete: prompt.len=${prompt.length} '
        'grammar.len=${grammarBNF?.length ?? 0} maxTokens=$maxTokens '
        'useIsolate=$_useIsolate');
    final cached = await modelManager.isCached();
    debugPrint('[llama] modelManager.isCached() → $cached');
    if (!cached) {
      throw const LlamaCompletionError(
        LlamaCompletionFailure.modelNotDownloaded,
        'llama model not downloaded -- call LlamaModelManager.ensureModelDownloaded() first',
      );
    }
    final modelFile = await modelManager.resolveModelFile();
    final modelPath = modelFile.path;
    debugPrint('[llama] modelPath=$modelPath '
        'fileExists=${await modelFile.exists()} '
        'fileSize=${(await modelFile.exists()) ? await modelFile.length() : -1}');

    if (!_useIsolate) {
      debugPrint('[llama] running on current isolate (test path)');
      return _runComplete(
        bindings: _bindings,
        modelPath: modelPath,
        prompt: prompt,
        grammarBNF: grammarBNF,
        maxTokens: maxTokens,
        temperature: temperature,
      );
    }

    debugPrint('[llama] spawning Isolate.run — about to load lib + model');
    final result = await Isolate.run(() {
      // We can't capture debugPrint cleanly across isolate boundary
      // for prints inside the closure (Flutter's debugPrint isn't
      // isolate-safe by default).  Use bare print() so output reaches
      // logcat.
      // ignore: avoid_print
      print('[llama:isolate] inside Isolate.run, opening LlamaBindings');
      final bindings = LlamaBindings.open();
      // ignore: avoid_print
      print('[llama:isolate] LlamaBindings opened, calling _runComplete');
      final out = _runComplete(
        bindings: bindings,
        modelPath: modelPath,
        prompt: prompt,
        grammarBNF: grammarBNF,
        maxTokens: maxTokens,
        temperature: temperature,
      );
      // ignore: avoid_print
      print('[llama:isolate] _runComplete returned, len=${out.length}');
      return out;
    });
    debugPrint('[llama] Isolate.run completed, result.len=${result.length}');
    return result;
  }
}

/// Pure (top-level) entry the production isolate worker + the in-
/// process test path both call.  Top-level so the closure passed to
/// `Isolate.run` doesn't capture the [LlamaService] instance (which
/// holds non-sendable references in tests).
String _runComplete({
  required LlamaBindingsBase bindings,
  required String modelPath,
  required String prompt,
  String? grammarBNF,
  int maxTokens = 512,
  double temperature = 0.0,
}) {
  // ignore: avoid_print
  print('[llama:run] bindings.open($modelPath) — about to mmap GGUF (~1-3s on phone)');
  final handle = bindings.open(modelPath);
  // ignore: avoid_print
  print('[llama:run] bindings.open returned handle=$handle');
  if (handle == 0) {
    throw const LlamaCompletionError(
      LlamaCompletionFailure.inferenceFailed,
      'llama_open returned a null handle',
    );
  }
  try {
    // ignore: avoid_print
    print('[llama:run] bindings.complete() — start inference');
    final t = DateTime.now();
    final out = bindings.complete(
      handle: handle,
      prompt: prompt,
      grammarBNF: grammarBNF,
      maxTokens: maxTokens,
      temperature: temperature,
    );
    final ms = DateTime.now().difference(t).inMilliseconds;
    // ignore: avoid_print
    print('[llama:run] bindings.complete returned len=${out.length} ms=$ms');
    return out;
  } catch (e) {
    // ignore: avoid_print
    print('[llama:run] bindings.complete threw: $e');
    if (e is LlamaCompletionError) rethrow;
    throw LlamaCompletionError(
      LlamaCompletionFailure.inferenceFailed,
      'inference failed: $e',
    );
  } finally {
    bindings.close(handle);
  }
}

```
