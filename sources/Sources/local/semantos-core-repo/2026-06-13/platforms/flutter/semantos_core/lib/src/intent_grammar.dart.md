---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/intent_grammar.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.017560+00:00
---

# platforms/flutter/semantos_core/lib/src/intent_grammar.dart

```dart
import 'wallet_service.dart';

/// A vocabulary entry for the LexiconRegistry.
class LexiconEntry {
  final String term;
  final String description;
  final List<String> synonyms;
  const LexiconEntry({
    required this.term,
    required this.description,
    this.synonyms = const [],
  });
}

/// A resolved structured intent dispatched from the ConversationEngine.
/// Experience packages define their own subtypes (e.g. PayMilestone).
abstract class StructuredIntent {
  const StructuredIntent();
}

/// Context provided to [IntentGrammar.onIntent] — gives the grammar
/// access to wallet operations without importing the impl.
abstract class IntentContext {
  WalletService get wallet;
}

/// Extension point for experience packages.
///
/// An experience registers one [IntentGrammar] with the shell's
/// ConversationEngine at boot. The shell composes all registered
/// grammar fragments and lexicons into a single llama_cpp GBNF
/// grammar for constrained extraction.
///
/// Implement this in your experience package and register it via
/// [ConversationEngine.registerGrammar].
abstract class IntentGrammar {
  /// GBNF grammar fragment for llama_cpp constrained generation.
  /// The shell concatenates all registered fragments.
  String get grammarFragment;

  /// Domain vocabulary loaded into the LexiconRegistry.
  List<LexiconEntry> get lexicon;

  /// Handle a dispatched [StructuredIntent]. Return [true] if handled.
  /// The grammar may call [ctx.wallet] to perform on-chain operations.
  Future<bool> onIntent(StructuredIntent intent, IntentContext ctx);
}

```
