---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/lib/src/intents.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.448920+00:00
---

# packages/betterment_experience/lib/src/intents.dart

```dart
/// Betterment cartridge StructuredIntent hierarchy.
///
/// Each subclass corresponds to one flow in cartridges/betterment/
/// cartridge.json (and one action in betterment_experience/assets/
/// manifest.json grammar.actions). The shell's ConversationEngine
/// extracts these via constrained generation against the GBNF fragment
/// in BettermentIntentGrammar.
///
/// C2 tick 3 (2026-05-28): subset covering the C7 slice's critical path
/// (`do | betterment | release`). Remaining flows have minimal stubs
/// that fully wire in C2 tick 4+ when the matching UI surfaces land.
///
/// RENAME (2026-05-29): grammar prefix flipped `self` → `betterment`
/// across all flows; cellTypes flipped `self.*` → `betterment.*`.
library;

import 'package:semantos_core/semantos_core.dart';

/// One chronological turn in a release transcript: the operator in
/// conversation with themself after typed entry, OCR, or Whisper.
class ReleaseTurn {
  final int index;
  final String text;
  final String speaker;
  final String? startedAt;
  final String? sourcePageRef;
  final double? confidence;

  const ReleaseTurn({
    required this.index,
    required this.text,
    this.speaker = 'self',
    this.startedAt,
    this.sourcePageRef,
    this.confidence,
  });
}

/// `do | betterment | release` — operator captures a daily release transcript.
/// Mints a betterment.practice.release cell for typed text, OCR-extracted
/// handwritten pages, or a Whisper transcript from a long-form voice note.
class Release extends StructuredIntent {
  final String rawText;
  final String day;
  final List<ReleaseTurn> turns;
  final String? prompt;
  final String? source; // 'text' | 'ocr' | 'voice_transcript'
  final List<String> journalImageRefs;
  final String? whisperTranscriptRef;

  const Release({
    required this.rawText,
    required this.day,
    required this.turns,
    this.prompt,
    this.source,
    this.journalImageRefs = const [],
    this.whisperTranscriptRef,
  });
}

/// `do | betterment | intention` — operator sets a daily intention.
/// Mints a betterment.practice.intention cell.
class SetIntention extends StructuredIntent {
  final String statement;
  final List<String> dimensions; // MENTAL|PHYSICAL|SPIRITUAL|SOCIAL|VOCATIONAL|FINANCIAL|FAMILIAL

  const SetIntention({
    required this.statement,
    this.dimensions = const [],
  });
}

/// `do | betterment | evening-review` — daily review with wins, improvements, gratitude.
class EveningReview extends StructuredIntent {
  final List<String> wins;
  final List<String> improvements;
  final int? energyLevel;
  final int? moodLevel;
  final String? tomorrowIntention;
  final String? gratitude;

  const EveningReview({
    required this.wins,
    required this.improvements,
    this.energyLevel,
    this.moodLevel,
    this.tomorrowIntention,
    this.gratitude,
  });
}

/// `do | betterment | morning-intention` — morning intention setter.
class MorningIntention extends StructuredIntent {
  final String? yesterdayReview; // 'fulfilled' | 'partial' | 'missed' | 'transformed'
  final String todayIntention;
  final String concreteAction;

  const MorningIntention({
    required this.todayIntention,
    required this.concreteAction,
    this.yesterdayReview,
  });
}

```
