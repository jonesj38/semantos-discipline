---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/android/src/main/cpp/whisper_cpp_shim.cpp
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.020718+00:00
---

# platforms/flutter/whisper_cpp/android/src/main/cpp/whisper_cpp_shim.cpp

```cpp
// D-O5m.followup-3 Phase 1 — minimal shim around whisper.cpp.
//
// Re-exports the C ABI surface `lib/src/bindings.dart` consumes:
//   - whisper_init_from_file (passthrough)
//   - whisper_full_simple (wrapper that builds default params)
//   - whisper_full_get_segment_text (passthrough)
//   - whisper_free (passthrough)
//
// Wrapping `whisper_full` with a "_simple" variant keeps the Dart side
// from having to construct the (large) `whisper_full_params` struct
// across the FFI boundary.

#include <whisper.h>
#include <cstring>
#include <cstdlib>

extern "C" __attribute__((visibility("default")))
int whisper_full_simple(struct whisper_context * ctx, const float * samples,
                        int n_samples, const char * language) {
    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_progress = false;
    params.print_special  = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.translate      = false;
    params.language       = language;
    params.n_threads      = 4;
    return whisper_full(ctx, params, samples, n_samples);
}

```
