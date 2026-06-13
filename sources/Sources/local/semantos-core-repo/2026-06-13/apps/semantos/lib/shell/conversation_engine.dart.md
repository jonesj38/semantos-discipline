---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/conversation_engine.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.101371+00:00
---

# apps/semantos/lib/shell/conversation_engine.dart

```dart
import 'package:semantos_core/semantos_core.dart';

/// Manages the STT → extraction → dispatch pipeline for all registered
/// experience grammars.
///
/// Architecture (from PLATFORM-WALLET-ARCHITECTURE.md §4.1):
///   whisper_cpp (STT) → llama_cpp (grammar-constrained extraction)
///   → GrammarRegistry dispatch → IntentGrammar.onIntent
///
/// P4 ships the scaffold. The whisper_cpp + llama_cpp wiring and
/// grammar-constrained extraction are the next integration step.
class ConversationEngine {
  final List<IntentGrammar> _grammars;

  ConversationEngine({List<IntentGrammar> grammars = const []})
      : _grammars = List.unmodifiable(grammars);

  /// Register an [IntentGrammar] from an experience package.
  /// Call during app boot before [SemantosPlatform] is created.
  ConversationEngine withGrammar(IntentGrammar grammar) {
    return ConversationEngine(grammars: [..._grammars, grammar]);
  }

  /// All registered grammars — accessed by the GBNF composer.
  List<IntentGrammar> get grammars => _grammars;

  /// The composed GBNF grammar string for llama_cpp constrained
  /// generation. Concatenates all registered grammar fragments.
  String get composedGrammar =>
      _grammars.map((g) => g.grammarFragment).join('\n');

  /// The combined lexicon across all registered grammars.
  List<LexiconEntry> get lexicon =>
      _grammars.expand((g) => g.lexicon).toList();
}

```
