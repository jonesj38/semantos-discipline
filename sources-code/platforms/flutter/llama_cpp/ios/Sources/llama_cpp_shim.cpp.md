---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/llama_cpp/ios/Sources/llama_cpp_shim.cpp
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.024328+00:00
---

# platforms/flutter/llama_cpp/ios/Sources/llama_cpp_shim.cpp

```cpp
// D-O5m.followup-3 Phase 2 — minimal shim around llama.cpp (iOS / macOS).
//
// Reference: platforms/flutter/whisper_cpp/ios/Sources/whisper_cpp_shim.cpp
//            (the Phase 1 sibling -- same shim layout, same
//            extern-C visibility pattern).
//
// Same content as android/src/main/cpp/llama_cpp_shim.cpp; pulled
// out here so the iOS pod compiles cleanly.  Both shims should
// remain in sync -- bumping `LLAMA_CPP_PIN` requires re-checking
// that `llama_init_from_file`, `llama_sample_token`, and the
// grammar-constrained sampler still expose the same C ABI shape.
//
// Three entry points the dart:ffi side calls:
//
//   - llama_shim_open(model_path) -> handle
//   - llama_shim_complete(handle, prompt, grammar_bnf, max_tokens,
//                         temperature, out_buf, out_cap) -> bytes
//                         written or -1 on failure
//   - llama_shim_close(handle)
//
// The shim owns the model + context lifecycle behind a single opaque
// handle so the Dart side doesn't need to model llama.cpp's internal
// model/context split.  The grammar parameter (when non-empty) is
// fed into llama.cpp's grammar sampler -- the model literally cannot
// emit tokens that violate the GBNF rules.

#include "llama.h"
#include <cstring>
#include <string>
#include <vector>

namespace {

struct Handle {
    llama_model *  model = nullptr;
    llama_context * ctx  = nullptr;
};

}  // namespace

extern "C" __attribute__((visibility("default")))
void * llama_shim_open(const char * model_path) {
    if (!model_path) return nullptr;
    auto * h = new Handle();
    llama_model_params mparams = llama_model_default_params();
    h->model = llama_load_model_from_file(model_path, mparams);
    if (!h->model) {
        delete h;
        return nullptr;
    }
    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx     = 2048;
    cparams.n_threads = 4;
    h->ctx = llama_new_context_with_model(h->model, cparams);
    if (!h->ctx) {
        llama_free_model(h->model);
        delete h;
        return nullptr;
    }
    return h;
}

extern "C" __attribute__((visibility("default")))
int llama_shim_complete(
    void * handle,
    const char * prompt,
    const char * grammar_bnf,
    int max_tokens,
    float temperature,
    char * out_buf,
    int out_cap
) {
    auto * h = static_cast<Handle *>(handle);
    if (!h || !h->ctx || !prompt || !out_buf || out_cap <= 0) return -1;

    // Tokenise the prompt.  Phase 2 keeps this naive -- a real
    // production path would batch via llama_decode in chunks; for
    // 512-token Intent JSON outputs over a 2k-context window this
    // is fine.
    std::vector<llama_token> tokens(strlen(prompt) + 32);
    int n = llama_tokenize(
        llama_get_model(h->ctx),
        prompt,
        static_cast<int>(strlen(prompt)),
        tokens.data(),
        static_cast<int>(tokens.size()),
        true,
        false
    );
    if (n < 0) return -1;
    tokens.resize(n);

    // Decode the prompt.
    llama_batch batch = llama_batch_get_one(tokens.data(), n);
    if (llama_decode(h->ctx, batch) != 0) return -1;

    // Build the grammar-aware sampler chain.  Empty grammar -> no
    // grammar filter (free-form completion); non-empty -> every
    // token is filtered through the GBNF automaton.
    auto sparams = llama_sampler_chain_default_params();
    llama_sampler * sampler = llama_sampler_chain_init(sparams);
    if (grammar_bnf && grammar_bnf[0] != '\0') {
        llama_sampler_chain_add(
            sampler,
            llama_sampler_init_grammar(
                llama_get_model(h->ctx),
                grammar_bnf,
                "root"
            )
        );
    }
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(1234));

    // Sample tokens until EOS or max_tokens.
    std::string out;
    out.reserve(static_cast<size_t>(max_tokens) * 4);
    for (int i = 0; i < max_tokens; ++i) {
        llama_token tok = llama_sampler_sample(sampler, h->ctx, -1);
        if (llama_token_is_eog(llama_get_model(h->ctx), tok)) break;
        char piece_buf[256];
        int piece_n = llama_token_to_piece(
            llama_get_model(h->ctx),
            tok,
            piece_buf,
            sizeof(piece_buf),
            0,
            false
        );
        if (piece_n > 0) out.append(piece_buf, static_cast<size_t>(piece_n));

        // Feed the sampled token back in to advance the context.
        llama_batch step = llama_batch_get_one(&tok, 1);
        if (llama_decode(h->ctx, step) != 0) break;
        llama_sampler_accept(sampler, tok);
    }
    llama_sampler_free(sampler);

    int copy = static_cast<int>(out.size());
    if (copy >= out_cap) copy = out_cap - 1;
    if (copy > 0) memcpy(out_buf, out.data(), static_cast<size_t>(copy));
    out_buf[copy] = '\0';
    return copy;
}

extern "C" __attribute__((visibility("default")))
void llama_shim_close(void * handle) {
    auto * h = static_cast<Handle *>(handle);
    if (!h) return;
    if (h->ctx)   llama_free(h->ctx);
    if (h->model) llama_free_model(h->model);
    delete h;
}

```
