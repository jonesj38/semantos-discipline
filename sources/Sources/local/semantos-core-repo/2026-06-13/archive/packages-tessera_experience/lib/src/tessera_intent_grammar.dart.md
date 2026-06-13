---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-tessera_experience/lib/src/tessera_intent_grammar.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.828471+00:00
---

# archive/packages-tessera_experience/lib/src/tessera_intent_grammar.dart

```dart
import 'package:semantos_core/semantos_core.dart';

import 'intents.dart';
import 'tessera_client.dart';

/// Tessera IntentGrammar implementation.
///
/// Registers a grammar fragment + the tessera lexicon with the
/// shell's ConversationEngine and handles dispatched tessera intents.
///
/// Architecture:
///   shell (STT → llama_cpp extraction) → dispatches StructuredIntent
///   → TesseraIntentGrammar.onIntent handles it
///   → if a [TesseraClient] is wired in, the matching brain verb is
///     dispatched via `verb.dispatch(extensionId="tessera", verb=…)`
///   → if no client is wired (unit tests, bootstrap before transport),
///     the grammar recognises the intent shape and returns true
///     (acknowledged, no-op) — preserves the existing scaffold
///     behaviour so the conversation-engine wiring stays exercisable.
///
/// Tessera does NOT move money — there is no wallet path. Every intent
/// is a cell-transition request the brain's tessera walkers service.
/// After the P3/P4 wave (universal boot + cartridge_boot + mint +
/// consume), every dispatched walker mints real substrate cells and
/// enforces LINEAR consumption when CellStore is bound.
class TesseraIntentGrammar implements IntentGrammar {
  final TesseraClient? _client;

  /// Construct without a brain client — onIntent acknowledges
  /// recognised intents but performs no dispatch (the existing
  /// pre-wire scaffold behaviour).
  const TesseraIntentGrammar() : _client = null;

  /// Construct with a brain client — onIntent dispatches matching
  /// intents through it. The client is the only required dependency
  /// for tessera; there is no wallet path.
  const TesseraIntentGrammar.withClient(TesseraClient client) : _client = client;

  @override
  String get grammarFragment => r'''
# tessera intents (GBNF fragment for llama_cpp constrained generation)
tessera-intent     ::= harvest | bottle | transfer-custody | record-care-event | consumer-scan | mark-tamper
harvest             ::= "harvest" ws "{" ws harvest-fields ws "}"
bottle              ::= "bottle" ws "{" ws bottle-fields ws "}"
transfer-custody    ::= "transfer_custody" ws "{" ws transfer-custody-fields ws "}"
record-care-event   ::= "record_care_event" ws "{" ws record-care-event-fields ws "}"
consumer-scan       ::= "consumer_scan" ws "{" ws consumer-scan-fields ws "}"
mark-tamper         ::= "mark_tamper" ws "{" ws mark-tamper-fields ws "}"
ws                  ::= [ \t\n]*
''';

  @override
  List<LexiconEntry> get lexicon => const [
        LexiconEntry(
          term: 'grape lot',
          description: 'An AFFINE origin cell — partial consumption into barrels',
          synonyms: ['lot', 'pick', 'harvest batch'],
        ),
        LexiconEntry(
          term: 'barrel',
          description: 'A LINEAR cell consumed entirely at bottling',
          synonyms: ['cask', 'vat'],
        ),
        LexiconEntry(
          term: 'bottle',
          description: 'A LINEAR cell; one tamper-break ends its open trajectory',
        ),
        LexiconEntry(
          term: 'case',
          description: 'A LINEAR cell assembled from N bottles via SemanticRelation',
        ),
        LexiconEntry(
          term: 'custody',
          description: 'The single open custodian of a case/pallet/shipment (V5.5)',
          synonyms: ['handoff', 'chain of custody'],
        ),
        LexiconEntry(
          term: 'care event',
          description: 'An AFFINE logger reading or manual flag against a shipment',
          synonyms: ['excursion', 'reading'],
        ),
        LexiconEntry(
          term: 'tamper loop',
          description: 'The physical NFC seal; once broken, stays broken (V5.2)',
        ),
        LexiconEntry(
          term: 'care score',
          description: 'Lean-proven monotonic derivation over a bottle care chain (V5.3)',
        ),
      ];

  @override
  Future<bool> onIntent(StructuredIntent intent, IntentContext ctx) async {
    // Phase 1 (no client) — recognise shape, no-op. Preserves the
    // existing scaffold behaviour for unit tests that exercise the
    // conversation-engine wiring without a brain transport.
    final client = _client;
    if (client == null) {
      if (intent is Harvest ||
          intent is Bottle ||
          intent is TransferCustody ||
          intent is RecordCareEvent ||
          intent is ConsumerScan ||
          intent is MarkTamper) {
        return true;
      }
      return false;
    }

    // Phase 2 (with brain client) — dispatch the matching tessera verb.
    // Two intent shapes (`ConsumerScan`, `MarkTamper`) map cleanly to
    // the brain walker contracts; the other four (`Harvest`, `Bottle`,
    // `TransferCustody`, `RecordCareEvent`) have intent-shape gaps the
    // brain doesn't yet have a defaulting policy for (e.g. `Harvest`
    // carries `block / brixAtPick / tonnage` but the brain wants
    // `grower / volumeMl`). For those we recognise + acknowledge here
    // and leave the actual dispatch to a richer intent shape — direct
    // callers can still use [TesseraClient] today.
    if (intent is ConsumerScan) {
      await client.consumerScan(bottleId: intent.bottleId);
      return true;
    }
    if (intent is MarkTamper) {
      await client.tamper(bottleId: intent.bottleId);
      return true;
    }
    if (intent is Bottle) {
      // Best-effort dispatch: generate sequential bottle ids when the
      // intent only carries a count. Production callers should pass
      // explicit bottle ids via TesseraClient directly.
      final ids = List<String>.generate(
        intent.count,
        (i) => '${intent.barrelId}-bottle-${i + 1}',
        growable: false,
      );
      await client.bottle(barrelId: intent.barrelId, bottleIds: ids);
      return true;
    }
    // Acknowledge the remaining shapes without dispatch — the brain
    // verbs require fields the intent doesn't carry today.
    if (intent is Harvest ||
        intent is TransferCustody ||
        intent is RecordCareEvent) {
      return true;
    }
    return false;
  }
}

```
