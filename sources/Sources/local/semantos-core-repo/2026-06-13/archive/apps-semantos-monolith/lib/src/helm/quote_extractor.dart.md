---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/quote_extractor.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.891373+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/quote_extractor.dart

```dart
// Quote extractor — AI-assisted line item extraction.
//
// QuoteExtractorService sends job context + conversation turns to the brain
// (`llm complete oddjobz-internal`) and returns a structured
// List<QuoteLineItem>.  All AI calls route through the always-on brain on
// rbs — the phone never calls Anthropic directly.
//
// Two extraction modes:
//   fromConversation — reads the conversation turns for a job and
//     extracts items from what was discussed with the customer.
//   fromText — parses a freehand description the operator typed
//     ("fix leaking tap, 2hrs labour, replace washers x3").
//
// Both modes use the operator's QuoteCatalogueService as pricing context
// so the model can anchor to standard rates rather than guessing.
//
// The ReplClient supplies the brain base URL + bearer token.  No
// compile-time secrets are embedded in the APK.

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../repl/conversation_turns_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/repl_client.dart';
import 'quote_catalogue.dart';
import 'quote_document.dart';

/// Result from the extractor — line items + optional scope notes.
class QuoteExtractionResult {
  final List<QuoteLineItem> items;
  final String notes; // scope summary; empty string if none

  const QuoteExtractionResult({required this.items, required this.notes});
}

class QuoteExtractorService {
  final ReplClient replClient;
  final QuoteCatalogueService catalogue;

  static const _kScope = 'oddjobz-internal';
  static const _kMaxTokens = 1024;

  QuoteExtractorService({
    required this.replClient,
    required this.catalogue,
  });

  /// Extract line items from the job's conversation thread.
  ///
  /// Uses [job.cellId] as the entityRef if present; falls back to [job.id].
  Future<QuoteExtractionResult> fromConversation({
    required Job job,
    required ConversationTurnsRepository turnsRepo,
  }) async {
    final entityRef =
        (job.cellId?.isNotEmpty ?? false) ? job.cellId! : job.id;
    List<ConversationTurn> turns = [];
    try {
      turns = await turnsRepo.fetchTurns(entityRef: entityRef, limit: 40);
    } catch (_) {}

    final turnText = turns.isEmpty
        ? '(no conversation recorded for this job yet)'
        : turns
            .map((t) {
              final role =
                  t.participantRole == 'operator' ? 'Operator' : 'Customer';
              return '$role: ${t.bodyText}';
            })
            .join('\n');

    final userMsg = _buildConversationPrompt(job: job, turnText: turnText);
    return _extract(userMsg);
  }

  /// Parse a freehand description typed by the operator.
  ///
  /// e.g. "2hrs labour, replace tap washer, silicone bath"
  Future<QuoteExtractionResult> fromText(String text) async {
    final userMsg = '''
Parse the following operator notes into quote line items.

${catalogue.toPromptContext()}

Operator notes:
$text''';
    return _extract(userMsg);
  }

  // ── Private ─────────────────────────────────────────────────────────

  String _buildConversationPrompt({
    required Job job,
    required String turnText,
  }) {
    final parts = <String>[];
    final desc = job.description ?? '';
    final addr = job.propertyAddress ?? '';
    final wo = job.workOrderNumber ?? '';
    final svc = job.services ?? '';

    if (desc.isNotEmpty) parts.add('Job description: $desc');
    if (addr.isNotEmpty) parts.add('Address: $addr');
    if (wo.isNotEmpty) parts.add('Work order: $wo');
    if (svc.isNotEmpty) parts.add('Services scope: $svc');
    parts.add('');
    parts.add(catalogue.toPromptContext());
    parts.add('');
    parts.add('Conversation:');
    parts.add(turnText);
    return parts.join('\n');
  }

  static const _kSystemPrompt = '''
You are a quote-building assistant for Odd Job Todd, a Queensland sole-trader handyman (maintenance and general property repairs).

Given a job description and conversation, extract structured quote line items.

Return ONLY a JSON object — no markdown, no explanation:
{
  "items": [
    { "description": "string", "quantity": 1.0, "unit_cents": 0 }
  ],
  "notes": "scope summary (empty string if nothing to add)"
}

Rules:
- description: clear professional trade language (e.g. "Labour — replace tap washer", not "fix the dripping thing")
- quantity: decimal — hours for labour, count for materials/jobs
- unit_cents: price in Australian CENTS for ONE unit (e.g. \$95/hr = 9500, \$90 callout = 9000, \$45 washer = 4500)
- Use catalogue items and pricing wherever the work matches — prefer exact names and rates
- Always include callout / site visit fee for on-site jobs unless the conversation explicitly waives it
- For items not in the catalogue, estimate reasonable Queensland 2025 trade rates
- Only include work clearly needed — do not pad the quote with speculative items
- If prices or amounts are mentioned in the conversation, use those figures
- notes: 1–3 sentences covering scope of work, inclusions, exclusions — empty string if nothing meaningful to add
- If the conversation is empty or vague, return a minimal quote with callout + labour placeholder''';

  Future<QuoteExtractionResult> _extract(String userContent) async {
    // Encode the full prompt payload as base64 so it survives the REPL
    // whitespace tokeniser as a single argument.
    final promptArgs = {
      'prompt': userContent,
      'system_prompt': _kSystemPrompt,
      'max_tokens': _kMaxTokens,
      'temperature': 0,
    };
    final b64 = base64.encode(utf8.encode(jsonEncode(promptArgs)));
    final cmd = 'llm complete $_kScope $b64';

    try {
      // LLM calls can take 15–45s — override the global 10s Dio timeout.
      final ok = await replClient.send(
        cmd,
        receiveTimeout: const Duration(seconds: 90),
      );
      // ok.result is the JSON string: {"text":"...","model":"...","tokens_used":N}
      final outerMap =
          jsonDecode(ok.result) as Map<String, dynamic>;
      final raw = (outerMap['text'] as String?) ?? '';
      if (raw.isEmpty) {
        debugPrint('[QuoteExtractor] brain LLM returned empty text');
        return const QuoteExtractionResult(items: [], notes: '');
      }
      return _parse(raw);
    } catch (e) {
      debugPrint('[QuoteExtractor] brain LLM error: $e');
      rethrow;
    }
  }

  QuoteExtractionResult _parse(String raw) {
    try {
      // Strip accidental markdown fences
      final cleaned = raw
          .replaceAll(RegExp(r'```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'```\s*', multiLine: true), '')
          .trim();
      final obj = jsonDecode(cleaned) as Map<String, dynamic>;
      final items = (obj['items'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((j) => QuoteLineItem(
                    description: (j['description'] ?? '').toString(),
                    quantity: (j['quantity'] as num?)?.toDouble() ?? 1.0,
                    unitCents: (j['unit_cents'] as num?)?.toInt() ?? 0,
                  ))
              .where((i) => i.description.isNotEmpty)
              .toList() ??
          [];
      final notes = (obj['notes'] as String?) ?? '';
      debugPrint('[QuoteExtractor] parsed ${items.length} items');
      return QuoteExtractionResult(items: items, notes: notes);
    } catch (e) {
      debugPrint('[QuoteExtractor] parse error: $e\nraw: $raw');
      return const QuoteExtractionResult(items: [], notes: '');
    }
  }
}

```
