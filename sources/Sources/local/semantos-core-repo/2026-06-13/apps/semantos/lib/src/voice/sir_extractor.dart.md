---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/voice/sir_extractor.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.111032+00:00
---

# apps/semantos/lib/src/voice/sir_extractor.dart

```dart
// D-O5m.followup-3 Phase 2 — on-device L1 SIR extractor.
//
// Reference: runtime/intent/src/types.ts (the canonical Intent type
//            this extractor produces);
//            runtime/intent/src/sir-builder.ts:candidateTrustClass
//            (the host-computed confidence-to-trust-tier mapping
//            this extractor mirrors -- the model never self-reports
//            its trust-tier; it's computed on the host from
//            structural properties of the produced Intent);
//            docs/papers/Semantos-A1-Compression-Gradient-DRAFT.md
//            §4.2 (the "pleb model is sufficient because the
//            gradient does the structural work" claim this Phase 2
//            operationalises);
//            runtime/intent/assets/intent.gbnf (the grammar that
//            constrains the model's output to a valid Intent shape).
//
// The flow on a phone with an llama.cpp model available:
//
//     transcript text + grammar → LlmCompleter.complete()
//                              → JSON string (grammar-guaranteed
//                                structurally valid)
//                              → SirExtractionResult.success(Intent,
//                                                            confidence)
//                              | SirExtractionResult.refused(reason)
//
// Refusal cases:
//
//   - the JSON parses but doesn't match the Intent shape (rare,
//     since the grammar enforces structure -- only a degenerate
//     grammar bug or a buggy model would slip through)
//   - the populated-fields ratio + action-verb match yields
//     confidence < 0.6 (sub-cosmetic; sir-builder would cap to
//     'cosmetic' anyway, but Phase 2 refuses earlier so the brain
//     sees less noise)
//
// On refusal the voice flow falls back to brain-side extraction
// (the Phase 1 path) -- the phone uploads the transcript without a
// sir_candidate part, the brain runs its full L0->L4 pipeline.

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:semantos_core/semantos_core.dart' as core
    show ExtensionGrammarSpec, ExtensionManifest;

/// Seam onto an LLM completer.  Production wires
/// `LlamaService.complete()` from the `llama_cpp` plugin; tests
/// inject a fake returning a fixture JSON.
abstract class LlmCompleter {
  /// Return a string completion of [prompt].  When [grammarBNF] is
  /// non-null the completer constrains output to that GBNF grammar;
  /// the result is guaranteed structurally valid by construction.
  Future<String> complete({
    required String prompt,
    String? grammarBNF,
    int maxTokens = 512,
    double temperature = 0.0,
  });
}

/// The `extension grammar` -- a small descriptor the extractor uses
/// to (a) shape the system prompt with extension-specific verbs and
/// (b) compute the host-side confidence score.  The actual GBNF
/// grammar string the model is constrained against lives in
/// [SirExtractor.intentGrammarBNF] (loaded from the bundled asset).
class ExtensionGrammar {
  /// Short identifier (e.g. `oddjobz`).
  final String name;

  /// Allowed `category.lexicon` values for this extension.  Used by
  /// the host-side validator to refuse Intents that escape the
  /// extension's lexicon.
  final List<String> allowedLexicons;

  /// Allowed action verbs for this extension.  Used by the host-side
  /// confidence calculation -- an Intent whose `action` is in this
  /// list scores higher than one with a free-form verb.
  final List<String> actionVerbs;

  const ExtensionGrammar({
    required this.name,
    required this.allowedLexicons,
    required this.actionVerbs,
  });

  /// Build an [ExtensionGrammar] from a manifest-loaded
  /// [core.ExtensionGrammarSpec]. Closes the divergence between the
  /// previously hand-maintained [oddjobz] constant and TRADES_GRAMMAR_SPEC
  /// in extensions/oddjobz/src/conversation/trades-grammar-spec.ts —
  /// both sides now consume the same manifest JSON.
  factory ExtensionGrammar.fromManifestSpec(
    core.ExtensionGrammarSpec spec, {
    String? name,
  }) {
    // Strip the extension id of its trailing version segments (oddjobz-v2
    // → oddjobz) so the descriptor matches the historical short id used
    // in voice prompts. The grammar layer below us treats this as a label.
    final fallbackName = spec.extensionId.split('-').first;
    return ExtensionGrammar(
      name: name ?? fallbackName,
      allowedLexicons: [spec.lexicon.name],
      actionVerbs: spec.actionVerbs,
    );
  }

  /// Convenience: build an [ExtensionGrammar] from a full
  /// [core.ExtensionManifest]. Equivalent to
  /// [fromManifestSpec] with the manifest's id as the descriptor name.
  factory ExtensionGrammar.fromManifest(core.ExtensionManifest manifest) {
    return ExtensionGrammar.fromManifestSpec(
      manifest.grammar,
      name: manifest.id,
    );
  }

  /// Default extension grammar for oddjobz — jural lexicon, canonical
  /// action verbs matching TRADES_GRAMMAR_SPEC in
  /// extensions/oddjobz/src/conversation/trades-grammar-spec.ts.
  ///
  /// **DEPRECATED**: this constant is the historical hand-mirror of
  /// the TS spec. Prefer [fromManifest] / [fromManifestSpec] which read
  /// the same JSON that the brain reducer consumes — eliminating the
  /// divergence risk. Kept here so existing tests + opt-out call sites
  /// compile while migration completes.
  @Deprecated('Use ExtensionGrammar.fromManifest(...) — load via '
      'OddjobzManifestLoader.load() at boot. This constant is the '
      'pre-manifest hand-mirror and will be removed when all call '
      'sites have migrated.')
  static const oddjobz = ExtensionGrammar(
    name: 'oddjobz',
    allowedLexicons: ['jural'],
    actionVerbs: [
      'report_issue',
      'request_photos',
      'attach_photos',
      'request_quote',
      'submit_quote',
      'approve_quote',
      'schedule_visit',
      'mark_work_complete',
      'issue_invoice',
      'pay_invoice',
    ],
  );
}

/// Hat context shape -- a flat surface so the extractor doesn't need
/// to import the full HatContext type from runtime/intent.  The
/// brain re-derives the real HatContext from the cert binding when
/// the produced Intent reaches it.
class HatContext {
  final String hatId;
  final String? certId;
  final String extensionId;
  final List<int> capabilities;

  const HatContext({
    required this.hatId,
    required this.certId,
    required this.extensionId,
    required this.capabilities,
  });
}

/// Result type for [SirExtractor.extract].
sealed class SirExtractionResult {
  const SirExtractionResult();
}

/// Successful extraction -- the Intent JSON parsed, validated, and
/// scored ≥ the minimum confidence threshold.  Brain receives this
/// in the `sir_candidate` multipart part and skips L0->L1.
class SirExtractionSuccess extends SirExtractionResult {
  /// Canonical Intent JSON shape -- matches `runtime/intent/src/
  /// types.ts::Intent` field-for-field.  Carried as a Map (not a
  /// typed Intent class) so the Dart side stays loose; the brain
  /// re-validates with full type-checking.
  final Map<String, dynamic> intent;

  /// Host-computed confidence in [0, 1].  Same scoring logic as
  /// `runtime/intent/src/sir-builder.ts::candidateTrustClass`:
  ///   - 0.9+ -> interpretive trust class
  ///   - 0.6+ -> cosmetic
  ///   - <0.6 -> refuse here rather than emit a noisy candidate
  final double confidence;

  const SirExtractionSuccess({
    required this.intent,
    required this.confidence,
  });
}

/// Refused -- the extractor produced output but it failed validation
/// or scored below the confidence threshold.  Phone falls back to
/// the Phase 1 brain-side path (no `sir_candidate` part).
class SirExtractionRefused extends SirExtractionResult {
  final String reason;
  const SirExtractionRefused(this.reason);
}

/// Minimum confidence to emit a SirExtractionSuccess -- below this
/// the extractor refuses and the phone falls back to brain-side.
/// Matches `sir-builder.ts::candidateTrustClass`'s 0.6 cosmetic
/// floor; sub-cosmetic Intents would be capped to 'cosmetic' by
/// the brain anyway, so refusing here saves a round-trip.
const double kMinConfidence = 0.6;

class SirExtractor {
  final LlmCompleter _llm;

  /// The GBNF grammar that constrains the LLM's output to a valid
  /// Intent shape.  Loaded once from the bundled asset (see
  /// `apps/oddjobz-mobile/assets/llama/intent.gbnf`).  Tests
  /// pass an inline grammar.
  final String intentGrammarBNF;

  const SirExtractor({
    required LlmCompleter completer,
    required this.intentGrammarBNF,
  }) : _llm = completer;

  /// Run the L1 SIR extraction over [transcript] for the actor in
  /// [hatContext] using [grammar]'s vocabulary.  Returns a typed
  /// [SirExtractionResult].
  Future<SirExtractionResult> extract({
    required String transcript,
    required HatContext hatContext,
    required ExtensionGrammar grammar,
  }) async {
    final prompt = _buildPrompt(
      transcript: transcript,
      hatContext: hatContext,
      grammar: grammar,
    );
    debugPrint('[sir] built prompt, len=${prompt.length} grammar.len=${intentGrammarBNF.length}');
    // 2026-05-08 — DIAG: bypass GBNF grammar to test if llama.cpp's
    // grammar sampler is what's stalling the inference loop on the
    // S20 FE.  The grammar is 3.3KB and overly constraining grammars
    // are a known cause of llama.cpp hangs (sampler can't find a
    // valid token).  If this returns successfully (even with garbage
    // output), grammar is the culprit.  Revert this once we've
    // localised the hang.
    const kDiagDisableGrammar = bool.fromEnvironment('SIR_DIAG_NO_GRAMMAR', defaultValue: false);
    // 2026-05-08 — default 256 tokens.  Empirically a complete intent
    // JSON is ~50 tokens; 256 leaves headroom + lets the grammar
    // sampler hit EOS naturally.  Operator's S20 FE runs at ~0.5
    // tok/s so this is ~8 minutes worst case — set
    // SIR_DIAG_MAX_TOKENS=128 for faster turnaround during debug.
    const kDiagMaxTokens = int.fromEnvironment('SIR_DIAG_MAX_TOKENS', defaultValue: 256);
    final useGrammar = !kDiagDisableGrammar;
    debugPrint('[sir] grammar enabled=$useGrammar (set SIR_DIAG_NO_GRAMMAR=true to bypass)');
    debugPrint('[sir] maxTokens=$kDiagMaxTokens (set SIR_DIAG_MAX_TOKENS=N to override)');
    String raw;
    try {
      debugPrint('[sir] calling _llm.complete (await)');
      raw = await _llm.complete(
        prompt: prompt,
        grammarBNF: useGrammar ? intentGrammarBNF : null,
        maxTokens: kDiagMaxTokens,
        temperature: 0.0,
      );
      final head = raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
      debugPrint('[sir] _llm.complete returned, raw.len=${raw.length} '
          'raw.head=$head');
    } catch (e) {
      debugPrint('[sir] _llm.complete threw: $e');
      return SirExtractionRefused('llm completion failed: $e');
    }

    // 2026-05-08 — extract the first balanced JSON object from the
    // raw output before parsing.  llama 3.2 3B (with our current
    // grammar) sometimes emits a complete intent object followed by
    // garbage like a second `Intent: {` continuation when there's
    // remaining max_tokens budget.  The first object is what we
    // want; the rest is just the model rambling.  This makes the
    // pipeline robust to "almost JSON" outputs.
    final firstObject = _extractFirstJsonObject(raw);
    Map<String, dynamic> parsed;
    try {
      final decoded = json.decode(firstObject);
      if (decoded is! Map<String, dynamic>) {
        return SirExtractionRefused(
            'llm output decoded to ${decoded.runtimeType}, expected object');
      }
      parsed = decoded;
    } catch (e) {
      // Should not happen when the grammar constrains output, but
      // defends against degenerate grammar bugs and surrogate-pair
      // edge cases.
      return SirExtractionRefused('llm output not valid JSON: $e');
    }

    final shapeError = _validateShape(parsed, grammar);
    if (shapeError != null) {
      return SirExtractionRefused('shape validation failed: $shapeError');
    }

    final confidence = computeHostConfidence(intent: parsed, grammar: grammar);
    if (confidence < kMinConfidence) {
      return SirExtractionRefused(
          'confidence ${confidence.toStringAsFixed(2)} below threshold '
          '${kMinConfidence.toStringAsFixed(2)}');
    }

    // Stamp the host-computed confidence into the produced Intent
    // -- the brain consumes this field directly via
    // `sir-builder.ts::candidateTrustClass`.  This is also what
    // makes the round-trip fixture byte-identical: the host (TS in
    // the fixture generator, Dart here) computes the same value
    // from the same inputs.
    parsed['confidence'] = confidence;
    parsed['source'] = 'voice';

    return SirExtractionSuccess(
      intent: canonicaliseIntent(parsed),
      confidence: confidence,
    );
  }

  /// Build the system prompt + transcript framing the LLM consumes.
  /// Phase 2 keeps the prompt structural and brief -- the grammar
  /// does the heavy lifting on output shape; the prompt only needs
  /// to seed the right fields with task-relevant content.
  String _buildPrompt({
    required String transcript,
    required HatContext hatContext,
    required ExtensionGrammar grammar,
  }) {
    final verbs = grammar.actionVerbs.join(', ');
    final lexicons = grammar.allowedLexicons.join(' | ');
    // Wave 9 PWA — the on-device llama path is constrained by a GBNF
    // grammar (assets/llama/intent.gbnf), which guarantees the output
    // shape regardless of how vague the prompt is. The Anthropic
    // completer doesn't honour GBNF, so we describe the schema inline
    // — concrete example + per-field rules. Both backends consume the
    // same prompt; llama just ignores the extra schema text.
    return '''You are an Intent extractor for the ${grammar.name} extension.
Convert the operator's transcript into a structural Intent JSON object.

Allowed action verbs: $verbs
Allowed category.lexicon values: $lexicons
Operator's hat: ${hatContext.hatId} (extension ${hatContext.extensionId})

Output EXACTLY one JSON object matching this schema. No surrounding
text, no markdown fences, no commentary. All fields below are
REQUIRED unless marked optional.

  {
    "id": "<uuid-v4 or short stable id like 'turn-<short-uuid>'>",
    "summary": "<one-line operator-readable summary of the action>",
    "category": {
      "lexicon": "<one of: $lexicons>",
      "category": "<extension-specific subcategory>"
    },
    "taxonomy": {
      "what":  "<what is being acted on>",
      "how":   "<which lifecycle / mechanism>",
      "why":   "<why this is being done>",
      "where": "<optional location string, omit when not relevant>",
      "who":   "<optional subject — customer/contact/operator name as
                spoken in the transcript; omit when not implied. Free
                text only; the resolver upgrades it to a customer
                cellId downstream.>",
      "when":  "<optional temporal coordinate — ISO 8601 when explicit,
                or a natural-language bucket like 'tomorrow morning' /
                'thursday afternoon' when relative. Omit when no time
                is implied.>"
    },
    "action": "<one of the allowed action verbs>",
    "constraints": [],
    "target": {
      "amount":   <optional number — smallest unit; e.g. AUD cents.
                   Hoist out of summary when the transcript implies a
                   price/cost/quote/invoice amount>,
      "currency": "<optional ISO code: AUD, USD, etc. Default AUD
                   for unmarked Australian operator transcripts>"
    },
    "confidence": <number in [0,1]; 0.85 for clear single-action
                   transcripts, lower for ambiguous ones>,
    "source": "nl"
  }

CRITICAL — strict rules:
1. `action` MUST be exactly one verb from the allowed list above.
   Do NOT compose verbs ("submit_quote" is WRONG — use just "quote").
   Do NOT invent new verbs.
2. `constraints` MUST be an empty list `[]`. The downstream pipeline
   computes value / temporal / capability constraints from the parsed
   intent on its own. Do NOT translate numerical values into constraints.
3. `target.amount` MUST be an integer in the smallest unit of
   `target.currency`. For AUD/USD this is CENTS (e.g. \$1000 → 100000).
   For sats this is satoshis. Omit `target.amount` when the action is
   amount-less (close, schedule with no quoted price).
4. Omit the entire `target` block when neither amount nor currency
   apply.

Example A — transcript "quote 750 for the pergola job":
  {
    "id": "turn-001",
    "summary": "quote \$750 for the pergola job",
    "category": { "lexicon": "${grammar.allowedLexicons.first}", "category": "quote" },
    "taxonomy": { "what": "pergola.job", "how": "lifecycle.quote", "why": "operational" },
    "action": "quote",
    "constraints": [],
    "target": { "amount": 75000, "currency": "AUD" },
    "confidence": 0.85,
    "source": "nl"
  }

Example B — transcript "schedule the wattle street visit for tomorrow morning":
  {
    "id": "turn-002",
    "summary": "schedule wattle street visit for tomorrow morning",
    "category": { "lexicon": "${grammar.allowedLexicons.first}", "category": "schedule" },
    "taxonomy": { "what": "site.visit", "how": "lifecycle.schedule", "why": "operational", "where": "wattle street" },
    "action": "schedule",
    "constraints": [],
    "confidence": 0.85,
    "source": "nl"
  }

Transcript: "$transcript"

Intent:''';
  }

  /// Lightweight shape check -- the grammar enforces structural
  /// validity so this only runs for defence-in-depth.  Returns null
  /// on success or an error description.
  String? _validateShape(Map<String, dynamic> intent, ExtensionGrammar g) {
    for (final field in const [
      'id',
      'summary',
      'category',
      'taxonomy',
      'action',
      'constraints',
      'confidence',
      'source',
    ]) {
      if (!intent.containsKey(field)) return 'missing field: $field';
    }
    final cat = intent['category'];
    if (cat is! Map ||
        cat['lexicon'] is! String ||
        !g.allowedLexicons.contains(cat['lexicon'])) {
      return 'category.lexicon not in allowed set ${g.allowedLexicons}';
    }
    final tax = intent['taxonomy'];
    if (tax is! Map ||
        tax['what'] is! String ||
        tax['how'] is! String ||
        tax['why'] is! String) {
      return 'taxonomy missing required what/how/why';
    }
    if (intent['constraints'] is! List) {
      return 'constraints not a list';
    }
    if (intent['action'] is! String ||
        (intent['action'] as String).isEmpty) {
      return 'action empty or non-string';
    }
    return null;
  }

  /// Host-side confidence computation.  Mirrors the brain-side
  /// scoring at `runtime/intent/src/sir-builder.ts::candidateTrust
  /// Class` -- required-fields ratio + constraint-pass ratio +
  /// action-verb match -- so the same Intent yields the same
  /// trust-tier whether scored on phone or brain.
  ///
  /// Three sub-scores, equally weighted, in [0, 1]:
  ///
  ///   1. populated_required_fields / total_required_fields
  ///   2. action verb in extension's action_verbs list (1 if so, 0.5
  ///      if not)
  ///   3. constraint structural validity -- 1 if all constraints
  ///      have valid `kind`s, 0 otherwise
  ///
  /// The model's own confidence value (when provided) is folded in
  /// as a 0.5 baseline so a confident model can't override a
  /// structurally-incomplete Intent.
  static double computeHostConfidence({
    required Map<String, dynamic> intent,
    required ExtensionGrammar grammar,
  }) {
    // Sub-score 1: required fields populated + non-empty.
    const required = <String>[
      'id',
      'summary',
      'category',
      'taxonomy',
      'action',
    ];
    var populated = 0;
    for (final f in required) {
      final v = intent[f];
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      if (v is Map && v.isEmpty) continue;
      populated++;
    }
    final fieldScore = populated / required.length;

    // Sub-score 2: action verb match.
    final action = intent['action'];
    final verbScore = (action is String && grammar.actionVerbs.contains(action))
        ? 1.0
        : 0.5;

    // Sub-score 3: constraint structural validity.
    final constraints = intent['constraints'];
    var constraintScore = 1.0;
    if (constraints is List) {
      const validKinds = <String>{
        'capability',
        'domain',
        'identity',
        'temporal',
        'value',
        'state',
        'interlock',
        'composite',
      };
      for (final c in constraints) {
        if (c is! Map || c['kind'] is! String) {
          constraintScore = 0;
          break;
        }
        if (!validKinds.contains(c['kind'])) {
          constraintScore = 0;
          break;
        }
      }
    } else {
      constraintScore = 0;
    }

    // Average + clamp.
    final raw = (fieldScore + verbScore + constraintScore) / 3.0;
    return raw.clamp(0.0, 1.0);
  }
}

/// 2026-05-08 — extract the first balanced JSON object substring.
/// Llama 3.2 3B (with our current grammar) sometimes emits one valid
/// object then continues into garbage when there's max_tokens budget
/// remaining — e.g. `{...} \n\n Intent: {` (cut off mid-second).
/// We just want the first object.
///
/// Skips leading whitespace.  Returns the original input if no '{' is
/// found (the json.decode call below will surface the real error).
String _extractFirstJsonObject(String raw) {
  final start = raw.indexOf('{');
  if (start < 0) return raw;
  var depth = 0;
  var inString = false;
  var escape = false;
  for (var i = start; i < raw.length; i++) {
    final c = raw[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (c == '\\' && inString) {
      escape = true;
      continue;
    }
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return raw.substring(start, i + 1);
    }
  }
  return raw.substring(start);
}

/// Canonicalise an Intent map -- emits a new Map with keys in the
/// canonical order that matches the TS `Intent` declaration order.
/// Used to ensure the Dart-emitted SIR's JSON encoding is
/// byte-identical to the TS reference (asserted in the cross-
/// language roundtrip fixture).
Map<String, dynamic> canonicaliseIntent(Map<String, dynamic> intent) {
  // Order matches `runtime/intent/src/types.ts::Intent`.  Optional
  // fields are emitted only when present so the canonicaliser
  // doesn't introduce phantom nulls.
  const order = <String>[
    'id',
    'correlationId',
    'companionOf',
    'summary',
    'category',
    'taxonomy',
    'action',
    'constraints',
    'target',
    'transferTo',
    'fulfillment',
    'confidence',
    'source',
    'producerMeta',
  ];
  final out = <String, dynamic>{};
  for (final k in order) {
    if (intent.containsKey(k) && intent[k] != null) {
      out[k] = intent[k];
    }
  }
  // Allow unknown fields through at the end so we don't silently
  // drop producer-specific metadata if upstream adds new fields.
  for (final entry in intent.entries) {
    if (!out.containsKey(entry.key) && entry.value != null) {
      out[entry.key] = entry.value;
    }
  }
  return out;
}

/// JSON-encode an Intent map with the canonical ordering applied.
/// Pure helper -- exposed for the brain-side serializer + the
/// cross-language fixture test.
String encodeCanonicalIntent(Map<String, dynamic> intent) {
  return json.encode(canonicaliseIntent(intent));
}

```
