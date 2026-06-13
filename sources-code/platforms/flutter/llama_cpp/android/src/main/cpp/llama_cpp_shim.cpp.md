---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/llama_cpp/android/src/main/cpp/llama_cpp_shim.cpp
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.024847+00:00
---

# platforms/flutter/llama_cpp/android/src/main/cpp/llama_cpp_shim.cpp

```cpp
// D-O5m.followup-3 Phase 2 — minimal shim around llama.cpp (Android / iOS).
//
// Reference: platforms/flutter/whisper_cpp/ios/Sources/whisper_cpp_shim.cpp
//            (the Phase 1 sibling -- same shim layout, same
//            extern-C visibility pattern).
//
// Written for llama.cpp tag b3500 (the pinned upstream version).
// Uses the pre-chain sampling API:
//   llama_sample_temp / llama_sample_token_greedy / llama_sample_token
// and the common/grammar-parser.h BNF → llama_grammar_element conversion.
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
// fed into llama.cpp's grammar sampler — the model literally cannot
// emit tokens that violate the GBNF rules.

#include "llama.h"
#include "grammar-parser.h"
#include <cstring>
#include <string>
#include <vector>
#include <android/log.h>
#include <chrono>
#define SHIM_LOG(...) __android_log_print(ANDROID_LOG_INFO, "llama_shim", __VA_ARGS__)

namespace {

struct Handle {
    llama_model *   model = nullptr;
    llama_context * ctx   = nullptr;
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
    void *       handle,
    const char * prompt,
    const char * grammar_bnf,
    int          max_tokens,
    float        temperature,
    char *       out_buf,
    int          out_cap
) {
    auto * h = static_cast<Handle *>(handle);
    if (!h || !h->ctx || !prompt || !out_buf || out_cap <= 0) return -1;

    const struct llama_model * model = llama_get_model(h->ctx);
    const int n_vocab = llama_n_vocab(model);
    SHIM_LOG("complete: prompt.len=%zu max_tokens=%d temperature=%f n_vocab=%d",
             strlen(prompt), max_tokens, temperature, n_vocab);

    // ── Tokenise the prompt ──────────────────────────────────────────
    std::vector<llama_token> tokens(strlen(prompt) + 32);
    int n = llama_tokenize(
        model,
        prompt,
        static_cast<int>(strlen(prompt)),
        tokens.data(),
        static_cast<int>(tokens.size()),
        /*add_bos=*/ true,
        /*special=*/ false
    );
    if (n < 0) { SHIM_LOG("tokenize failed: n=%d", n); return -1; }
    tokens.resize(n);
    SHIM_LOG("tokenized: %d tokens. starting prompt decode (this is the slow part)", n);

    // ── Decode the prompt ────────────────────────────────────────────
    // pos_0 = 0 (first prompt token at KV position 0), seq_id = 0.
    auto t_decode_start = std::chrono::steady_clock::now();
    llama_batch batch = llama_batch_get_one(tokens.data(), n, 0, 0);
    int decode_rc = llama_decode(h->ctx, batch);
    auto t_decode_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - t_decode_start).count();
    SHIM_LOG("prompt decode rc=%d ms=%lld", decode_rc, (long long)t_decode_ms);
    if (decode_rc != 0) return -1;

    // ── Parse grammar (if provided) ──────────────────────────────────
    llama_grammar * grammar = nullptr;
    grammar_parser::parse_state parsed;
    if (grammar_bnf && grammar_bnf[0] != '\0') {
        parsed = grammar_parser::parse(grammar_bnf);
        if (!parsed.rules.empty()) {
            auto c_rules = parsed.c_rules();
            // The "root" symbol id is the grammar entry point.
            auto it = parsed.symbol_ids.find("root");
            if (it != parsed.symbol_ids.end()) {
                grammar = llama_grammar_init(
                    c_rules.data(),
                    c_rules.size(),
                    static_cast<size_t>(it->second)
                );
            }
        }
    }

    // ── Candidate token array (reused each step) ─────────────────────
    std::vector<llama_token_data> cand_data(static_cast<size_t>(n_vocab));
    llama_token_data_array candidates = {
        cand_data.data(),
        static_cast<size_t>(n_vocab),
        /*sorted=*/ false
    };

    // ── Sample loop ──────────────────────────────────────────────────
    std::string out;
    out.reserve(static_cast<size_t>(max_tokens) * 4);
    auto t_sample_start = std::chrono::steady_clock::now();
    SHIM_LOG("entering sample loop, max_tokens=%d", max_tokens);

    for (int i = 0; i < max_tokens; ++i) {
        if (i > 0 && (i % 8) == 0) {
            auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - t_sample_start).count();
            SHIM_LOG("  loop progress: %d/%d tokens, %lld ms (%.1f tok/s)",
                     i, max_tokens, (long long)ms,
                     ms > 0 ? (i * 1000.0 / ms) : 0.0);
        }
        // Populate logits for every vocabulary token.
        // llama_get_logits_ith(ctx, -1) returns the last decoded token's logits.
        float * logits = llama_get_logits_ith(h->ctx, -1);
        for (int v = 0; v < n_vocab; ++v) {
            cand_data[static_cast<size_t>(v)] = { v, logits[v], 0.0f };
        }
        candidates.size   = static_cast<size_t>(n_vocab);
        candidates.sorted = false;

        // Grammar filter — removes tokens that would violate the BNF.
        if (grammar) {
            llama_grammar_sample(grammar, h->ctx, &candidates);
        }

        // Sample.
        llama_token tok;
        if (temperature <= 0.0f) {
            tok = llama_sample_token_greedy(h->ctx, &candidates);
        } else {
            llama_sample_temp(h->ctx, &candidates, temperature);
            tok = llama_sample_token(h->ctx, &candidates);
        }

        // EOS / EOG — generation complete.
        if (llama_token_is_eog(model, tok)) break;

        // Convert token id to UTF-8 text piece.
        char piece[256];
        int piece_n = llama_token_to_piece(
            model, tok, piece, static_cast<int>(sizeof(piece)), 0, false
        );
        if (piece_n > 0) out.append(piece, static_cast<size_t>(piece_n));

        // Advance grammar state.
        if (grammar) {
            llama_grammar_accept_token(grammar, h->ctx, tok);
        }

        // Feed the sampled token back in to advance the KV cache.
        // pos_0 = n + i  (position of this generated token in the sequence).
        llama_batch step = llama_batch_get_one(&tok, 1, n + i, 0);
        if (llama_decode(h->ctx, step) != 0) break;
    }

    if (grammar) llama_grammar_free(grammar);

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
