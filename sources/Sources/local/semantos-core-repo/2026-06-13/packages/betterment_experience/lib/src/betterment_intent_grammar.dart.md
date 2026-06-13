---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/lib/src/betterment_intent_grammar.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.449475+00:00
---

# packages/betterment_experience/lib/src/betterment_intent_grammar.dart

```dart
/// Betterment IntentGrammar implementation.
///
/// Registers grammar fragment + lexicon + intent handlers with the
/// shell's ConversationEngine at boot. Mirrors OddjobzIntentGrammar
/// pattern.
///
/// C2 tick 3 (2026-05-28): grammar fragment + lexicon + intent type
/// hierarchy + stub onIntent handler. Real onIntent handling lands in
/// C2 tick 4 once the canonical PWA wires BettermentIntentGrammar
/// into the ConversationEngine and the BrainVerbDispatchClient is
/// available. The current stub returns false (unhandled) for every
/// intent so the shell's fallback dispatch (verb.dispatch → brain)
/// takes over.
///
/// RENAME (2026-05-29): class previously SelfIntentGrammar; grammar
/// rule names previously prefixed `self-*`.
library;

import 'package:semantos_core/semantos_core.dart';

import 'intents.dart';

class BettermentIntentGrammar extends IntentGrammar {
  @override
  String get grammarFragment => r'''
# betterment intents (GBNF fragment for llama_cpp constrained generation)
betterment-intent ::= release-intent | set-intention-intent | evening-review-intent | morning-intention-intent
release-intent    ::= "release" ws "{" ws release-fields ws "}"
release-fields    ::= "\"rawText\"" ws ":" ws string ws "," ws "\"day\"" ws ":" ws string (ws "," ws "\"prompt\"" ws ":" ws string)? (ws "," ws "\"source\"" ws ":" ws source-enum)?
source-enum       ::= "\"text\"" | "\"ocr\"" | "\"voice_transcript\""

set-intention-intent ::= "set_intention" ws "{" ws "\"statement\"" ws ":" ws string (ws "," ws "\"dimensions\"" ws ":" ws dimension-list)? ws "}"
dimension-list    ::= "[" ws (dimension-enum (ws "," ws dimension-enum)*)? ws "]"
dimension-enum    ::= "\"MENTAL\"" | "\"PHYSICAL\"" | "\"SPIRITUAL\"" | "\"SOCIAL\"" | "\"VOCATIONAL\"" | "\"FINANCIAL\"" | "\"FAMILIAL\""

evening-review-intent ::= "evening_review" ws "{" ws evening-review-fields ws "}"
evening-review-fields ::= "\"wins\"" ws ":" ws string-list ws "," ws "\"improvements\"" ws ":" ws string-list
string-list       ::= "[" ws (string (ws "," ws string)*)? ws "]"

morning-intention-intent ::= "morning_intention" ws "{" ws "\"todayIntention\"" ws ":" ws string ws "," ws "\"concreteAction\"" ws ":" ws string ws "}"

string            ::= "\"" [^"]* "\""
ws                ::= [ \t\n]*
''';

  @override
  List<LexiconEntry> get lexicon => const [
        LexiconEntry(
          term: 'release',
          description: 'Daily release writing — capture and let go of emotional content',
          synonyms: ['journal', 'release writing', 'let go', 'process', 'ocr', 'voice note', 'whisper transcript'],
        ),
        LexiconEntry(
          term: 'intention',
          description: 'A held statement of what the operator chooses to focus on',
          synonyms: ['focus', 'aim', 'target'],
        ),
        LexiconEntry(
          term: 'session',
          description: 'A daily practice session — attention + presence + reflection',
          synonyms: ['practice', 'check-in'],
        ),
        LexiconEntry(
          term: 'vacuum',
          description: 'QSE vacuum cleaner — release + integrate cycle',
          synonyms: ['cleanse', 'reset'],
        ),
        LexiconEntry(
          term: 'evening review',
          description: 'End-of-day reflection with wins, improvements, gratitude',
          synonyms: ['daily review', 'end of day'],
        ),
        LexiconEntry(
          term: 'morning intention',
          description: 'Start-of-day intention setting',
          synonyms: ['morning practice', 'day plan'],
        ),
        LexiconEntry(
          term: 'pattern',
          description: 'A recurring tendency noticed across releases',
        ),
        LexiconEntry(
          term: 'insight',
          description: 'Intelligence worth keeping, captured from a release or connection',
          synonyms: ['realization', 'understanding'],
        ),
        LexiconEntry(
          term: 'gold seal',
          description: 'Visualization sealing the practice — gold light/ointment/molten',
          synonyms: ['seal'],
        ),
        LexiconEntry(
          term: 'dimension',
          description: 'One of MENTAL/PHYSICAL/SPIRITUAL/SOCIAL/VOCATIONAL/FINANCIAL/FAMILIAL',
        ),
      ];

  @override
  Future<bool> onIntent(StructuredIntent intent, IntentContext ctx) async {
    // C2 tick 3 stub: return false so the shell's fallback dispatch
    // (verb.dispatch → brain) handles the intent. Real handlers (which
    // would mint cells via the wallet) land in C2 tick 4 once the
    // canonical PWA wires the WalletService and brain dispatch client.
    if (intent is Release) return false;
    if (intent is SetIntention) return false;
    if (intent is EveningReview) return false;
    if (intent is MorningIntention) return false;
    return false;
  }
}

```
