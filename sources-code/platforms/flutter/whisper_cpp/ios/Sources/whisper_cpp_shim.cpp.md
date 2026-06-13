---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/ios/Sources/whisper_cpp_shim.cpp
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.020219+00:00
---

# platforms/flutter/whisper_cpp/ios/Sources/whisper_cpp_shim.cpp

```cpp
// D-O5m.followup-3 Phase 1 — minimal shim around whisper.cpp (iOS).
//
// Same content as android/src/main/cpp/whisper_cpp_shim.cpp; pulled
// out here so the iOS pod compiles cleanly. Both shims should remain
// in sync — bumping `WHISPER_CPP_PIN` requires re-checking that
// `whisper_full_default_params` and `whisper_full` still expose the
// same C ABI shape.

#include "whisper.cpp/whisper.h"

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
