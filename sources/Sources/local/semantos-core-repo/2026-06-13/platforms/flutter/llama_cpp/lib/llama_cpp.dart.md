---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/llama_cpp/lib/llama_cpp.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.023642+00:00
---

# platforms/flutter/llama_cpp/lib/llama_cpp.dart

```dart
// D-O5m.followup-3 Phase 2 — llama.cpp Flutter FFI plugin.
//
// Reference: platforms/flutter/whisper_cpp/lib/whisper_cpp.dart
//            (the Phase 1 sibling — same plugin layout, model-
//            manager pattern, and bindings seam);
//            apps/oddjobz-mobile/lib/src/voice/sir_extractor.dart
//            (the consumer — produces an Intent JSON via
//            grammar-constrained generation);
//            runtime/intent/assets/intent.gbnf (the grammar that
//            constrains the model's output to a valid Intent shape).
//
// Top-level export.  Three pieces:
//
//   - `LlamaBindings` (lib/src/bindings.dart) — dart:ffi typedefs for
//     the llama.cpp C API surface this plugin uses (load, complete,
//     free).  A thin shim (`llama_cpp_shim.cpp` per-platform) exposes
//     a stable C ABI on top of upstream's evolving C++ API.
//
//   - `LlamaService` (lib/src/llama_service.dart) — high-level
//     idiomatic API:
//
//         await svc.complete(
//           prompt: '...',
//           grammarBNF: kIntentGrammar,  // optional GBNF
//           maxTokens: 512,
//           temperature: 0.0,
//         );
//
//     The `grammarBNF` parameter takes a GBNF grammar string;
//     llama.cpp's sampler filters every token through the grammar
//     automaton, so a non-null grammar makes malformed output
//     literally impossible to emit.  Tests inject a stub
//     `LlamaBindingsBase` impl; production wires the dynamic-library
//     bindings.
//
//   - `LlamaModelManager` (lib/src/model_manager.dart) — downloads +
//     caches + verifies SHA-256 of the GGUF model on first use.
//     Models are NEVER bundled in the app binary; ~2 GiB once
//     downloaded for the default Llama-3.2-3B-Instruct Q4_K_M model.
//
// See `platforms/flutter/llama_cpp/README` (forthcoming) for the
// CMake/CocoaPods FetchContent pin used to fetch the upstream
// llama.cpp source at plugin build time.

export 'src/bindings.dart' show LlamaBindings, LlamaBindingsBase, kLlamaCppPin;
export 'src/model_manager.dart'
    show LlamaModelManager, LlamaModel, LlamaModelDownloadProgress;
export 'src/llama_service.dart'
    show LlamaService, LlamaCompletionError, LlamaCompletionFailure;

```
