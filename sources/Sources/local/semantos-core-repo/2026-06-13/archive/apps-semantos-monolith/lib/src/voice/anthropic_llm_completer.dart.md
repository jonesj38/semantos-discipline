---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/voice/anthropic_llm_completer.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.866480+00:00
---

# archive/apps-semantos-monolith/lib/src/voice/anthropic_llm_completer.dart

```dart
// Wave 9 PWA — Anthropic-backed L1 SIR extractor.
//
// Drop-in `LlmCompleter` that calls Claude's /v1/messages endpoint
// instead of running llama.cpp on-device. Substrate-clean: the
// substrate's no-AI rule (`semantos_no_ai_in_substrate.md`) is about
// pask/brain/cells — the SIR extractor sits at the *edge* (L1 intent
// parser). LLM-at-the-edge is explicitly allowed; this just swaps one
// edge LLM (on-device llama) for another (cloud Claude).
//
// Tradeoffs vs llama.cpp:
//   - ✓ Sub-second roundtrip vs 5-minute on-device inference on
//     mid-range Android (S20FE-class). Makes the dev loop actually
//     usable.
//   - ✗ Typed text leaves the device. For Todd's own dev workflow
//     this is fine; production cartridges with PII should stay on the
//     llama path (or opt-in explicitly).
//   - ✗ Needs internet to api.anthropic.com:443 (Anthropic endpoints
//     are typically reachable when local brain endpoints aren't).
//   - ✗ Grammar (GBNF) constraints are dropped — Anthropic doesn't
//     support them. We compensate via a strict system prompt + clamped
//     `max_tokens` + temperature=0.
//
// API key delivery:
//   - Build-time via `--dart-define=ANTHROPIC_API_KEY=sk-ant-...`.
//     Easiest for the dev loop; key is baked into the APK (so don't
//     commit prod keys this way).
//   - Runtime via the constructor `apiKey:` argument — pass from
//     flutter_secure_storage or a settings screen when one exists.
//
// Network failure modes (timeouts, 4xx, 5xx) bubble out as
// `Exception`s. The caller (`SirExtractor`) catches them and the
// outer `TextIntentService.processText` synthesises an
// `intent_rejected · extractor_exception` event into the inspector
// — exactly the same surface as a llama.cpp throw.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'sir_extractor.dart' show LlmCompleter;

/// LlmCompleter that proxies to Anthropic's /v1/messages endpoint.
class AnthropicLlmCompleter implements LlmCompleter {
  /// Bearer key. Required. Get one from console.anthropic.com.
  final String apiKey;

  /// Model id. Default is the latest Sonnet — fast + cheap enough
  /// for L1 extraction. Override for Opus / Haiku as needed.
  final String model;

  /// Network roundtrip cap. Default 30s; below the Whisper / brain
  /// fallback timeouts already in play elsewhere in the app.
  final Duration timeout;

  /// Injection seam for tests.
  final Dio _dio;

  AnthropicLlmCompleter({
    required this.apiKey,
    this.model = 'claude-sonnet-4-6',
    this.timeout = const Duration(seconds: 30),
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    if (apiKey.isEmpty) {
      throw ArgumentError('AnthropicLlmCompleter: apiKey must be non-empty');
    }
  }

  @override
  Future<String> complete({
    required String prompt,
    String? grammarBNF,
    int maxTokens = 512,
    double temperature = 0.0,
  }) async {
    // The SirExtractor builds a prompt that embeds the GBNF grammar
    // as guidance text, but Claude doesn't constrain output against
    // it — we lean on the prompt's existing "respond with JSON only"
    // discipline. The grammarBNF arg is intentionally ignored.
    if (grammarBNF != null && grammarBNF.isNotEmpty) {
      debugPrint(
        '[anthropic-llm] grammarBNF supplied (${grammarBNF.length} chars) — '
        'ignored; Claude is constrained by prompt only',
      );
    }

    debugPrint(
      '[anthropic-llm] complete model=$model maxTokens=$maxTokens '
      'temp=$temperature prompt.len=${prompt.length}',
    );
    final started = DateTime.now();

    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        'https://api.anthropic.com/v1/messages',
        options: Options(
          headers: <String, String>{
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          sendTimeout: timeout,
          receiveTimeout: timeout,
          responseType: ResponseType.json,
        ),
        data: <String, Object>{
          'model': model,
          'max_tokens': maxTokens,
          'temperature': temperature,
          'messages': <Map<String, Object>>[
            {'role': 'user', 'content': prompt},
          ],
        },
      );
    } on DioException catch (e) {
      // Surface the underlying status + body so the inspector's
      // extractor_exception detail line is actionable.
      final status = e.response?.statusCode;
      final body = e.response?.data;
      throw Exception(
        'anthropic /messages failed: '
        '${e.type.name}${status != null ? ' status=$status' : ''}'
        '${body != null ? ' body=${jsonEncode(body)}' : ''}',
      );
    }

    final elapsed = DateTime.now().difference(started).inMilliseconds;
    final body = response.data;
    if (body == null) {
      throw Exception('anthropic /messages: empty response body');
    }

    final content = body['content'];
    if (content is! List || content.isEmpty) {
      throw Exception(
        'anthropic /messages: unexpected content shape, '
        'body=${jsonEncode(body)}',
      );
    }

    // Concatenate every text block — usually one, but be defensive.
    final buf = StringBuffer();
    for (final block in content) {
      if (block is Map && block['type'] == 'text' && block['text'] is String) {
        buf.write(block['text']);
      }
    }
    final raw = buf.toString();
    debugPrint(
      '[anthropic-llm] complete returned ${raw.length} chars in ${elapsed}ms',
    );
    if (raw.isEmpty) {
      throw Exception('anthropic /messages: no text blocks in content');
    }
    return raw;
  }
}

```
