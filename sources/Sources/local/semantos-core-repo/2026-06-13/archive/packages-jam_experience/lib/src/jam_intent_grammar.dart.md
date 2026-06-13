---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/jam_intent_grammar.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.813263+00:00
---

# archive/packages-jam_experience/lib/src/jam_intent_grammar.dart

```dart
import 'package:semantos_core/semantos_core.dart';

import 'intents.dart';

/// [IntentGrammar] implementation for the jambox extension.
///
/// Mirrors the OddjobzIntentGrammar in `oddjobz_experience` — declarative
/// grammar fragment + lexicon entries the shell's ConversationEngine
/// composes into its GBNF + prompt. The action handlers in [onIntent]
/// dispatch to local UI / brain via the [IntentContext] surfaces.
///
/// The grammar fragment + lexicon below intentionally mirror what the
/// `manifest.json` declares — divergence is a deployment bug, not a
/// runtime concern. Future work will generate this Dart-side fragment
/// from the manifest so it's never hand-edited; today it's parallel
/// to keep the API stable for the shell.
class JamboxIntentGrammar implements IntentGrammar {
  const JamboxIntentGrammar();

  @override
  String get grammarFragment => r'''
# jambox grammar fragment — recognized verb shapes for the LLM extractor.
# Composed by ConversationEngine alongside other registered grammars.
jam_action  ::= "launch_clip" | "stop_clip" | "launch_scene"
              | "record_take" | "promote_take" | "capture_gesture"
              | "edit_pattern" | "twist_macro"
              | "mute_track" | "unmute_track"
              | "set_tempo" | "set_key"
              | "grant_permission" | "revoke_permission" | "invite_player"
''';

  @override
  List<LexiconEntry> get lexicon => const [
        LexiconEntry(
          term: 'clip',
          description: 'A launchable musical fragment in the jam session.',
          synonyms: ['loop', 'fragment', 'cell'],
        ),
        LexiconEntry(
          term: 'scene',
          description: 'A row of clips that launch together.',
          synonyms: ['row', 'preset', 'snapshot'],
        ),
        LexiconEntry(
          term: 'take',
          description: 'A recorded performance pass available for review.',
          synonyms: ['recording', 'pass'],
        ),
        LexiconEntry(
          term: 'pattern',
          description: 'A drum or melodic step pattern.',
          synonyms: ['sequence', 'beat', 'rhythm'],
        ),
        LexiconEntry(
          term: 'arrangement',
          description: 'A timeline of scenes forming a song structure.',
          synonyms: ['timeline', 'song', 'session'],
        ),
        LexiconEntry(
          term: 'macro',
          description: 'A live-twistable parameter group.',
          synonyms: ['dial', 'knob', 'control'],
        ),
        LexiconEntry(
          term: 'gesture',
          description: 'A captured controller input pass for replay.',
          synonyms: ['motion', 'performance'],
        ),
        LexiconEntry(
          term: 'tempo',
          description: 'The session global beats-per-minute.',
          synonyms: ['bpm', 'speed', 'rate'],
        ),
      ];

  @override
  Future<bool> onIntent(StructuredIntent intent, IntentContext ctx) async {
    // Jam intents are predominantly UI / transport state changes, not
    // wallet operations — the shell renders them locally and (in a
    // future iteration) emits the matching cell write via the brain's
    // verb.dispatch primitive. For the prototype this returns true on
    // recognized intents to acknowledge registration without
    // performing on-chain work.
    if (intent is LaunchClip ||
        intent is StopClip ||
        intent is LaunchScene ||
        intent is RecordTake ||
        intent is PromoteTake ||
        intent is TwistMacro ||
        intent is SetTempo ||
        intent is MuteTrack ||
        intent is UnmuteTrack) {
      return true;
    }
    return false;
  }
}

```
