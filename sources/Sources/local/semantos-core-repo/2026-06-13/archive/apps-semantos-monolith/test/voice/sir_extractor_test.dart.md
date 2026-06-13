---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/voice/sir_extractor_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.910421+00:00
---

# archive/apps-semantos-monolith/test/voice/sir_extractor_test.dart

```dart
// D-O5m.followup-3 Phase 2 — sir_extractor unit tests.
//
// Reference: apps/oddjobz-mobile/lib/src/voice/sir_extractor.dart
//            (the unit under test);
//            runtime/intent/src/sir-builder.ts::candidateTrustClass
//            (the host-side confidence-to-trust-tier mapping the
//            extractor mirrors).

import 'package:test/test.dart';

import 'package:semantos/src/voice/sir_extractor.dart';

class _FakeCompleter implements LlmCompleter {
  String returns;
  bool throws;
  String? lastPrompt;
  String? lastGrammar;

  _FakeCompleter({this.returns = '', this.throws = false});

  @override
  Future<String> complete({
    required String prompt,
    String? grammarBNF,
    int maxTokens = 512,
    double temperature = 0.0,
  }) async {
    if (throws) throw StateError('forced failure');
    lastPrompt = prompt;
    lastGrammar = grammarBNF;
    return returns;
  }
}

final _hat = HatContext(
  hatId: 'operator',
  certId: 'a' * 64,
  extensionId: 'oddjobz',
  capabilities: const [0x00010101],
);

const _grammarStub = 'root ::= "{" .* "}"';

const _validIntentJson = '''
{
  "id": "i-001",
  "summary": "job 12345 is invoiced",
  "category": {"lexicon": "jural", "category": "transfer"},
  "taxonomy": {"what": "maintenance.invoice", "how": "how.commercial.transfer", "why": "why.commercial.payment"},
  "action": "issue_invoice",
  "constraints": [{"kind": "value", "field": "amount", "op": "=", "value": 85000}],
  "confidence": 0.85,
  "source": "voice"
}
''';

void main() {
  group('SirExtractor.extract', () {
    test('happy path returns success with computed confidence', () async {
      final llm = _FakeCompleter(returns: _validIntentJson);
      final extractor = SirExtractor(
        completer: llm,
        intentGrammarBNF: _grammarStub,
      );
      final r = await extractor.extract(
        transcript: 'job 12345 is invoiced',
        hatContext: _hat,
        grammar: ExtensionGrammar.oddjobz,
      );
      expect(r, isA<SirExtractionSuccess>());
      final s = r as SirExtractionSuccess;
      expect(s.intent['action'], equals('issue_invoice'));
      expect(s.intent['source'], equals('voice'));
      expect(s.confidence, greaterThanOrEqualTo(0.6));
      // Prompt was built with the transcript text + extension verbs.
      expect(llm.lastPrompt, contains('job 12345 is invoiced'));
      expect(llm.lastPrompt, contains('issue_invoice'));
      expect(llm.lastGrammar, equals(_grammarStub));
    });

    test('grammar violation -> refused', () async {
      // Output is valid JSON but missing required fields.
      final llm = _FakeCompleter(
        returns: '{"id": "i-001", "summary": "job 12345"}',
      );
      final extractor = SirExtractor(
        completer: llm,
        intentGrammarBNF: _grammarStub,
      );
      final r = await extractor.extract(
        transcript: 'job 12345 is invoiced',
        hatContext: _hat,
        grammar: ExtensionGrammar.oddjobz,
      );
      expect(r, isA<SirExtractionRefused>());
      expect((r as SirExtractionRefused).reason,
          contains('missing field'));
    });

    test('non-JSON output -> refused', () async {
      final llm = _FakeCompleter(returns: 'not even json');
      final extractor = SirExtractor(
        completer: llm,
        intentGrammarBNF: _grammarStub,
      );
      final r = await extractor.extract(
        transcript: 'hi',
        hatContext: _hat,
        grammar: ExtensionGrammar.oddjobz,
      );
      expect(r, isA<SirExtractionRefused>());
    });

    test('low confidence -> refused', () async {
      // Action verb not in extension's allowed set + invalid
      // constraint kind -> confidence drops below 0.6.
      final llm = _FakeCompleter(returns: '''
        {
          "id": "i-001",
          "summary": "do thing",
          "category": {"lexicon": "jural", "category": "declaration"},
          "taxonomy": {"what": "maintenance.job", "how": "how.lifecycle.create", "why": "why.integration.property-management"},
          "action": "frobnicate",
          "constraints": [{"kind": "ohnoesnotreal"}],
          "confidence": 0.99,
          "source": "voice"
        }
      ''');
      final extractor = SirExtractor(
        completer: llm,
        intentGrammarBNF: _grammarStub,
      );
      final r = await extractor.extract(
        transcript: 'do thing',
        hatContext: _hat,
        grammar: ExtensionGrammar.oddjobz,
      );
      expect(r, isA<SirExtractionRefused>());
      expect((r as SirExtractionRefused).reason,
          contains('confidence'));
    });

    test('disallowed lexicon -> refused', () async {
      final llm = _FakeCompleter(returns: '''
        {
          "id": "i-001",
          "summary": "ack alarm",
          "category": {"lexicon": "control-systems", "category": "acknowledgement"},
          "taxonomy": {"what": "alarm", "how": "how.technical.acknowledge", "why": "why.operational.acknowledge"},
          "action": "acknowledge_alarm",
          "constraints": [],
          "confidence": 0.9,
          "source": "voice"
        }
      ''');
      final extractor = SirExtractor(
        completer: llm,
        intentGrammarBNF: _grammarStub,
      );
      final r = await extractor.extract(
        transcript: 'ack the alarm',
        hatContext: _hat,
        grammar: ExtensionGrammar.oddjobz,
      );
      expect(r, isA<SirExtractionRefused>());
      expect((r as SirExtractionRefused).reason,
          contains('lexicon'));
    });

    test('LLM exception surfaces as refused', () async {
      final llm = _FakeCompleter(throws: true);
      final extractor = SirExtractor(
        completer: llm,
        intentGrammarBNF: _grammarStub,
      );
      final r = await extractor.extract(
        transcript: 'hi',
        hatContext: _hat,
        grammar: ExtensionGrammar.oddjobz,
      );
      expect(r, isA<SirExtractionRefused>());
      expect((r as SirExtractionRefused).reason,
          contains('llm completion failed'));
    });

    test('multi-object output: only first balanced JSON object is parsed', () async {
      // Llama 3B sometimes emits one complete object then continues
      // with '\n\nIntent: {' garbage when max_tokens budget remains.
      // _extractFirstJsonObject must discard the tail.
      final garbage = _validIntentJson.trim() +
          '\n\nIntent: {"id": "GARBAGE", "summary": "second spurious object"';
      final llm = _FakeCompleter(returns: garbage);
      final extractor = SirExtractor(
        completer: llm,
        intentGrammarBNF: _grammarStub,
      );
      final r = await extractor.extract(
        transcript: 'job 12345 is invoiced',
        hatContext: _hat,
        grammar: ExtensionGrammar.oddjobz,
      );
      expect(r, isA<SirExtractionSuccess>());
      final s = r as SirExtractionSuccess;
      expect(s.intent['id'], equals('i-001'));
      expect(s.intent['id'], isNot(equals('GARBAGE')));
    });

    test('leading whitespace before first JSON object is skipped', () async {
      final padded = '\n   \n' + _validIntentJson;
      final llm = _FakeCompleter(returns: padded);
      final extractor = SirExtractor(
        completer: llm,
        intentGrammarBNF: _grammarStub,
      );
      final r = await extractor.extract(
        transcript: 'job 12345 is invoiced',
        hatContext: _hat,
        grammar: ExtensionGrammar.oddjobz,
      );
      expect(r, isA<SirExtractionSuccess>());
    });

    test('canonicaliseIntent reorders keys to TS Intent declaration order',
        () async {
      final llm = _FakeCompleter(returns: _validIntentJson);
      final extractor = SirExtractor(
        completer: llm,
        intentGrammarBNF: _grammarStub,
      );
      final r = await extractor.extract(
        transcript: 'job 12345 is invoiced',
        hatContext: _hat,
        grammar: ExtensionGrammar.oddjobz,
      );
      final s = r as SirExtractionSuccess;
      // Keys should appear in canonical order:
      // id, summary, category, taxonomy, action, constraints, confidence, source.
      final keys = s.intent.keys.toList();
      expect(keys.first, equals('id'));
      // confidence appears after constraints.
      final ci = keys.indexOf('constraints');
      final ki = keys.indexOf('confidence');
      expect(ki > ci, isTrue);
      // source appears last among the populated.
      final si = keys.indexOf('source');
      expect(si > ki, isTrue);
    });
  });

  group('SirExtractor.computeHostConfidence', () {
    test('all required fields + valid action + valid constraints scores high',
        () {
      final intent = {
        'id': 'i-001',
        'summary': 'job 12345 is invoiced',
        'category': {'lexicon': 'jural', 'category': 'transfer'},
        'taxonomy': {'what': 'maintenance.invoice', 'how': 'how.commercial.transfer', 'why': 'why.commercial.payment'},
        'action': 'issue_invoice',
        'constraints': [
          {'kind': 'value', 'field': 'amount', 'op': '=', 'value': 85000}
        ],
      };
      final c = SirExtractor.computeHostConfidence(
        intent: intent,
        grammar: ExtensionGrammar.oddjobz,
      );
      expect(c, equals(1.0));
    });

    test('unknown action verb scores moderate', () {
      final intent = {
        'id': 'i-001',
        'summary': 's',
        'category': {'lexicon': 'jural', 'category': 'transfer'},
        'taxonomy': {'what': 'maintenance.job', 'how': 'how.lifecycle.create', 'why': 'why.integration.property-management'},
        'action': 'xyzunknown',
        'constraints': [],
      };
      final c = SirExtractor.computeHostConfidence(
        intent: intent,
        grammar: ExtensionGrammar.oddjobz,
      );
      // 1.0 (fields) + 0.5 (verb) + 1.0 (constraints) = 2.5/3 ~= 0.83
      expect(c, closeTo(0.833, 0.01));
    });

    test('invalid constraint kind drops score below threshold', () {
      final intent = {
        'id': 'i-001',
        'summary': 's',
        'category': {'lexicon': 'jural', 'category': 'transfer'},
        'taxonomy': {'what': 'maintenance.invoice', 'how': 'how.commercial.transfer', 'why': 'why.commercial.payment'},
        'action': 'issue_invoice',
        'constraints': [
          {'kind': 'made_up_kind'}
        ],
      };
      final c = SirExtractor.computeHostConfidence(
        intent: intent,
        grammar: ExtensionGrammar.oddjobz,
      );
      // 1.0 (fields) + 1.0 (verb) + 0 (constraints) = 2.0/3 ~= 0.667
      expect(c, closeTo(0.667, 0.01));
    });
  });
}

```
