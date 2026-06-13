---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/models/objects.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.751715+00:00
---

# archive/apps-navigation_app/lib/models/objects.dart

```dart
import 'package:uuid/uuid.dart';
import 'semantic_types.dart';

const _uuid = Uuid();

/// Base class for all semantic objects in the Navigation system.
/// The kernel enforces consumption rules via [consumptionType].
abstract class SemanticObject {
  final String id;
  final DateTime createdAt;
  final ConsumptionType consumptionType;
  bool consumed;

  SemanticObject({
    String? id,
    DateTime? createdAt,
    required this.consumptionType,
    this.consumed = false,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson();
}

// ──────────────────────────────────────────────
// LINEAR objects — consumed once, then gone
// ──────────────────────────────────────────────

/// Stream-of-consciousness writing that gets released (consumed).
/// Once released, the kernel enforces you can't cling to it.
class Release extends SemanticObject {
  final String rawText;
  final List<String> themes;
  final double emotionalValence; // -1.0 to 1.0
  final String? processStepId;
  final Duration duration;

  Release({
    super.id,
    super.createdAt,
    required this.rawText,
    this.themes = const [],
    this.emotionalValence = 0.0,
    this.processStepId,
    this.duration = Duration.zero,
  }) : super(consumptionType: ConsumptionType.linear);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'Release',
        'rawText': rawText,
        'themes': themes,
        'emotionalValence': emotionalValence,
        'processStepId': processStepId,
        'duration': duration.inSeconds,
        'consumed': consumed,
      };
}

/// A practice session — you sit down, you do it, it's consumed.
class Session extends SemanticObject {
  final String sessionType; // meditation, writing, vacuum, connection
  final Duration duration;
  final String? processStepId;
  final Map<String, dynamic> metadata;

  Session({
    super.id,
    super.createdAt,
    required this.sessionType,
    required this.duration,
    this.processStepId,
    this.metadata = const {},
  }) : super(consumptionType: ConsumptionType.linear);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'Session',
        'sessionType': sessionType,
        'duration': duration.inSeconds,
        'processStepId': processStepId,
        'metadata': metadata,
        'consumed': consumed,
      };
}

/// QSE vacuum cleaner visualization session.
class VacuumSession extends SemanticObject {
  final String releaseTarget;
  final bool goldSealApplied;
  final String? notes;

  VacuumSession({
    super.id,
    super.createdAt,
    required this.releaseTarget,
    this.goldSealApplied = false,
    this.notes,
  }) : super(consumptionType: ConsumptionType.linear);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'VacuumSession',
        'releaseTarget': releaseTarget,
        'goldSealApplied': goldSealApplied,
        'notes': notes,
        'consumed': consumed,
      };
}

/// Daily evening review — 3 wins, 3 improvements, tomorrow's intention.
class DailyReview extends SemanticObject {
  final List<String> wins;
  final List<String> improvements;
  final String tomorrowIntention;
  final int energyLevel; // 1-10
  final int moodLevel; // 1-10
  final Map<Dimension, int> dimensionScores; // 1-10 per dimension

  DailyReview({
    super.id,
    super.createdAt,
    required this.wins,
    required this.improvements,
    required this.tomorrowIntention,
    required this.energyLevel,
    required this.moodLevel,
    this.dimensionScores = const {},
  }) : super(consumptionType: ConsumptionType.linear);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'DailyReview',
        'wins': wins,
        'improvements': improvements,
        'tomorrowIntention': tomorrowIntention,
        'energyLevel': energyLevel,
        'moodLevel': moodLevel,
        'dimensionScores':
            dimensionScores.map((k, v) => MapEntry(k.name, v)),
        'consumed': consumed,
      };
}

/// Morning intention — what you commit to today.
class MorningIntention extends SemanticObject {
  final String focusDimension;
  final String intention;
  final String concreteAction;
  final String? yesterdayReflection;

  MorningIntention({
    super.id,
    super.createdAt,
    required this.focusDimension,
    required this.intention,
    required this.concreteAction,
    this.yesterdayReflection,
  }) : super(consumptionType: ConsumptionType.linear);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'MorningIntention',
        'focusDimension': focusDimension,
        'intention': intention,
        'concreteAction': concreteAction,
        'yesterdayReflection': yesterdayReflection,
        'consumed': consumed,
      };
}

// ──────────────────────────────────────────────
// AFFINE objects — acknowledge or discard
// ──────────────────────────────────────────────

/// A choice you set. Fulfil it, transform it, or outgrow it.
class Intention extends SemanticObject {
  final String statement;
  final Dimension? dimension;
  final DateTime? deadline;
  String status; // active, fulfilled, discarded, transformed

  Intention({
    super.id,
    super.createdAt,
    required this.statement,
    this.dimension,
    this.deadline,
    this.status = 'active',
  }) : super(consumptionType: ConsumptionType.affine);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'Intention',
        'statement': statement,
        'dimension': dimension?.name,
        'deadline': deadline?.toIso8601String(),
        'status': status,
        'consumed': consumed,
      };
}

/// Quick dimension check-in (midday pulse).
class DimensionPulse extends SemanticObject {
  final Dimension dimension;
  final int score; // 1-10
  final String? note;

  DimensionPulse({
    super.id,
    super.createdAt,
    required this.dimension,
    required this.score,
    this.note,
  }) : super(consumptionType: ConsumptionType.affine);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'DimensionPulse',
        'dimension': dimension.name,
        'score': score,
        'note': note,
        'consumed': consumed,
      };
}

// ──────────────────────────────────────────────
// RELEVANT objects — persist, accumulate
// ──────────────────────────────────────────────

/// Wisdom received — persists, always accessible.
class Insight extends SemanticObject {
  final String content;
  final String source; // writing, connection, vacuum, meditation, llm
  final List<String> tags;
  final Dimension? dimension;
  final String? processStepId;

  Insight({
    super.id,
    super.createdAt,
    required this.content,
    required this.source,
    this.tags = const [],
    this.dimension,
    this.processStepId,
  }) : super(consumptionType: ConsumptionType.relevant);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'Insight',
        'content': content,
        'source': source,
        'tags': tags,
        'dimension': dimension?.name,
        'processStepId': processStepId,
        'consumed': consumed,
      };
}

/// Recurring theme extracted across releases by LLM.
class Pattern extends SemanticObject {
  final String description;
  final int occurrences;
  final List<String> sourceReleaseIds;
  final double strength; // 0.0 to 1.0

  Pattern({
    super.id,
    super.createdAt,
    required this.description,
    this.occurrences = 1,
    this.sourceReleaseIds = const [],
    this.strength = 0.5,
  }) : super(consumptionType: ConsumptionType.relevant);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'Pattern',
        'description': description,
        'occurrences': occurrences,
        'sourceReleaseIds': sourceReleaseIds,
        'strength': strength,
        'consumed': consumed,
      };
}

/// Current state of a life dimension — persists and evolves.
class DimensionState extends SemanticObject {
  final Dimension dimension;
  double score; // 0.0 to 10.0
  List<String> activeIntentionIds;
  int streakDays;
  DateTime lastPulse;

  DimensionState({
    super.id,
    super.createdAt,
    required this.dimension,
    this.score = 5.0,
    this.activeIntentionIds = const [],
    this.streakDays = 0,
    DateTime? lastPulse,
  })  : lastPulse = lastPulse ?? DateTime.now(),
        super(consumptionType: ConsumptionType.relevant);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'DimensionState',
        'dimension': dimension.name,
        'score': score,
        'activeIntentionIds': activeIntentionIds,
        'streakDays': streakDays,
        'lastPulse': lastPulse.toIso8601String(),
        'consumed': consumed,
      };
}

/// Accountability streak — tracks consecutive days of practice.
class AccountabilityStreak extends SemanticObject {
  int currentStreak;
  int longestStreak;
  DateTime lastCheckIn;
  int totalSessions;

  /// BSV-related: how much is at stake if streak breaks
  int vestedSatoshis;
  int unvestedSatoshis;

  AccountabilityStreak({
    super.id,
    super.createdAt,
    this.currentStreak = 0,
    this.longestStreak = 0,
    DateTime? lastCheckIn,
    this.totalSessions = 0,
    this.vestedSatoshis = 0,
    this.unvestedSatoshis = 0,
  })  : lastCheckIn = lastCheckIn ?? DateTime.now(),
        super(consumptionType: ConsumptionType.relevant);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': 'AccountabilityStreak',
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'lastCheckIn': lastCheckIn.toIso8601String(),
        'totalSessions': totalSessions,
        'vestedSatoshis': vestedSatoshis,
        'unvestedSatoshis': unvestedSatoshis,
        'consumed': consumed,
      };
}

```
