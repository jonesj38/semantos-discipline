---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/receipt_ocr_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.892284+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/receipt_ocr_service.dart

```dart
// Receipt OCR service — photo → QuoteLineItems via brain LLM.
//
// ReceiptOcrService sends a photo of a hardware/materials receipt to the
// brain's `llm vision oddjobz-internal` endpoint and returns a structured
// List<QuoteLineItem> ready to insert into the quote or invoice editor.
//
// The image is base64-encoded and forwarded to Anthropic Vision by the brain
// on rbs — the phone never calls Anthropic directly.  No compile-time
// ANTHROPIC_API_KEY dart-define is required.
//
// Usage:
//   final svc = ReceiptOcrService(replClient: replClient);
//   final items = await svc.fromPhoto(xFile);
//
// Wire format:
//   cmd = 'llm vision oddjobz-internal $b64'
//   b64 = base64(jsonEncode({
//     image_b64: <photo bytes as base64>,
//     media_type: "image/jpeg" | "image/png" | "image/webp" | "image/gif",
//     system_prompt: <_kSystemPrompt>,
//     max_tokens: 1024,
//   }))
//   Response: {"text":"...","model":"...","tokens_used":N}
//
// P2a/P2b of OJT-UNIFIED-QUOTE-INVOICE-PLAN.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';

import '../repl/repl_client.dart';
import 'quote_document.dart';

class ReceiptOcrService {
  final ReplClient replClient;

  static const _kScope = 'oddjobz-internal';
  static const _kMaxTokens = 1024;

  const ReceiptOcrService({required this.replClient});

  /// Extract quote line items from a receipt photo.
  ///
  /// [photo] is the XFile returned by image_picker.  The image is
  /// read as bytes, base64-encoded, and forwarded to Anthropic Vision
  /// via the brain's `llm vision` REPL verb.  Returns an empty list on
  /// any error so the caller degrades gracefully.
  Future<List<QuoteLineItem>> fromPhoto(XFile photo) async {
    try {
      final bytes = await File(photo.path).readAsBytes();
      final imageB64 = base64Encode(bytes);
      // Detect media type from file extension; default to jpeg.
      final ext = photo.path.split('.').last.toLowerCase();
      final mediaType = switch (ext) {
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

      // Encode the vision args payload as base64 so it survives the REPL
      // whitespace tokeniser as a single argument.
      final visionArgs = {
        'image_b64': imageB64,
        'media_type': mediaType,
        'system_prompt': _kSystemPrompt,
        'max_tokens': _kMaxTokens,
      };
      final b64 = base64.encode(utf8.encode(jsonEncode(visionArgs)));
      final cmd = 'llm vision $_kScope $b64';

      // Vision LLM calls with image data can take 20–45s — override global timeout.
      final ok = await replClient.send(
        cmd,
        receiveTimeout: const Duration(seconds: 90),
      );
      // ok.result is the JSON string: {"text":"...","model":"...","tokens_used":N}
      final outerMap = jsonDecode(ok.result) as Map<String, dynamic>;
      final raw = (outerMap['text'] as String?) ?? '';
      if (raw.isEmpty) {
        debugPrint('[ReceiptOcr] brain LLM returned empty text');
        return [];
      }
      return _parse(raw);
    } catch (e) {
      debugPrint('[ReceiptOcr] error: $e');
      return [];
    }
  }

  // ── Private ──────────────────────────────────────────────────────────

  static const _kSystemPrompt =
      'You are a materials/parts receipt parser for a Queensland sole-trader handyman.\n'
      '\n'
      'Given a photo of a hardware or materials receipt, extract every line item.\n'
      '\n'
      'Return ONLY a JSON object — no markdown, no explanation:\n'
      '{\n'
      '  "items": [\n'
      '    { "description": "string", "quantity": 1.0, "unit_cents": 0 }\n'
      '  ]\n'
      '}\n'
      '\n'
      'Rules:\n'
      '- description: concise item name (e.g. "Brass tap washer 13mm", "PVC joiner 20mm")\n'
      '- quantity: decimal number from the receipt (e.g. 2, 1.5, 4)\n'
      r'- unit_cents: unit price in Australian CENTS (e.g. $4.50 → 450, $12.99 → 1299)'
      '\n'
      '- If the receipt shows a line total (not unit price), divide by quantity\n'
      '- Skip subtotals, totals, GST lines, and store name / address lines\n'
      '- If a price is unclear or absent, use 0 for unit_cents\n'
      '- Always output valid JSON; if nothing useful is visible, output {"items":[]}';

  List<QuoteLineItem> _parse(String raw) {
    try {
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
      debugPrint('[ReceiptOcr] parsed ${items.length} items');
      return items;
    } catch (e) {
      debugPrint('[ReceiptOcr] parse error: $e\nraw: $raw');
      return [];
    }
  }
}

```
