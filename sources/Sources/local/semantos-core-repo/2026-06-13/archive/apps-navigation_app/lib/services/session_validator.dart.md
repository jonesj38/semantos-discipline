---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/services/session_validator.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.747636+00:00
---

# archive/apps-navigation_app/lib/services/session_validator.dart

```dart
import 'dart:math';

/// Local pre-validation before submitting to the node.
/// The node does authoritative validation, but we catch obvious
/// issues locally to give immediate feedback and save round-trips.
///
/// The Paskian learning graph on the node does the deep validation:
/// - Pattern analysis across sessions (too regular = scripted)
/// - Content depth analysis (genuine writing has emotional variance)
/// - Timing analysis (genuine meditation has micro-variations)
/// - Cross-session coherence (insights should relate to releases)
///
/// This local validator catches the low-hanging fruit.
class SessionValidator {
  /// Minimum session durations by type (seconds)
  static const _minDurations = {
    'writing_release': 120, // 2 minutes minimum
    'meditation': 60,       // 1 minute minimum
    'vacuum_session': 60,
    'connection': 60,
    'evening_review': 30,
    'morning_intention': 15,
    'midday_pulse': 5,
  };

  /// Validate a writing release locally before node submission
  ValidationResult validateWritingRelease({
    required String text,
    required int durationSeconds,
  }) {
    final issues = <String>[];

    // Duration check
    final minDuration = _minDurations['writing_release'] ?? 120;
    if (durationSeconds < minDuration) {
      issues.add('Session too short (${durationSeconds}s, minimum ${minDuration}s)');
    }

    // Word count check — genuine stream-of-consciousness produces words
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words < 10) {
      issues.add('Too few words ($words). Let your thoughts flow freely.');
    }

    // Repetition check — copy-paste or key-mashing detection
    final repetitionScore = _calculateRepetitionScore(text);
    if (repetitionScore > 0.6) {
      issues.add('High repetition detected. Try to write authentically.');
    }

    // Emotional variance check — genuine writing has shifting sentiment
    // (This is a rough heuristic; the node does deeper NLP)
    final hasEmotionalContent = _hasEmotionalVariance(text);
    if (words > 50 && !hasEmotionalContent) {
      // Soft warning, not a block
      issues.add('Consider going deeper — what are you feeling?');
    }

    // Words-per-minute sanity check
    if (durationSeconds > 0) {
      final wpm = words / (durationSeconds / 60);
      if (wpm > 150) {
        // Probably pasted text — average typing is 40-60 WPM
        issues.add('Writing speed suggests pasted content. Write in real-time.');
      }
    }

    return ValidationResult(
      accepted: issues.where((i) => !i.startsWith('Consider')).isEmpty,
      issues: issues,
      metrics: {
        'wordCount': words,
        'durationSeconds': durationSeconds,
        'repetitionScore': repetitionScore,
        'hasEmotionalVariance': hasEmotionalContent,
      },
    );
  }

  /// Validate a meditation session
  ValidationResult validateMeditation({
    required int durationSeconds,
    required List<int> heartRateReadings, // Optional, from wearable
    required int interruptionCount, // How many times they left the app
  }) {
    final issues = <String>[];

    final minDuration = _minDurations['meditation'] ?? 60;
    if (durationSeconds < minDuration) {
      issues.add('Session too short');
    }

    // Interruption check — leaving the app during meditation is suspicious
    if (interruptionCount > 3) {
      issues.add('Multiple app switches detected during meditation');
    }

    // If we have heart rate data, check for genuine rest response
    if (heartRateReadings.length > 10) {
      final avg = heartRateReadings.reduce((a, b) => a + b) / heartRateReadings.length;
      final first5avg = heartRateReadings.take(5).reduce((a, b) => a + b) / 5;
      final last5avg = heartRateReadings.reversed.take(5).reduce((a, b) => a + b) / 5;

      // Genuine meditation typically shows HR decrease
      // Not blocking, just a metric for the Paskian graph
    }

    return ValidationResult(
      accepted: issues.where((i) => !i.startsWith('Consider')).isEmpty,
      issues: issues,
      metrics: {
        'durationSeconds': durationSeconds,
        'interruptionCount': interruptionCount,
        'hasHeartRate': heartRateReadings.isNotEmpty,
      },
    );
  }

  /// Validate a daily review
  ValidationResult validateDailyReview({
    required List<String> wins,
    required List<String> improvements,
    required String intention,
    required int durationSeconds,
  }) {
    final issues = <String>[];

    // Must have at least one win and one improvement
    final validWins = wins.where((w) => w.trim().length > 3).length;
    final validImprovements = improvements.where((i) => i.trim().length > 3).length;

    if (validWins == 0) {
      issues.add('Add at least one win — even small ones count');
    }
    if (validImprovements == 0) {
      issues.add('Add at least one area to improve');
    }
    if (intention.trim().length < 5) {
      issues.add('Set an intention for tomorrow');
    }

    // Check for copy-paste from previous reviews
    // (The node does this across days; locally we just check format)

    return ValidationResult(
      accepted: issues.isEmpty,
      issues: issues,
      metrics: {
        'winCount': validWins,
        'improvementCount': validImprovements,
        'intentionLength': intention.trim().length,
        'durationSeconds': durationSeconds,
      },
    );
  }

  /// Calculate how repetitive a text is (0 = unique, 1 = all repeated)
  double _calculateRepetitionScore(String text) {
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    if (words.length < 5) return 0.0;

    // Check 3-gram repetition
    final trigrams = <String>{};
    int repeatedTrigrams = 0;
    for (int i = 0; i < words.length - 2; i++) {
      final trigram = '${words[i]} ${words[i + 1]} ${words[i + 2]}';
      if (trigrams.contains(trigram)) {
        repeatedTrigrams++;
      } else {
        trigrams.add(trigram);
      }
    }

    return words.length > 4
        ? repeatedTrigrams / (words.length - 2)
        : 0.0;
  }

  /// Rough check for emotional content in writing
  bool _hasEmotionalVariance(String text) {
    final lower = text.toLowerCase();
    final emotionWords = [
      'feel', 'feeling', 'felt', 'angry', 'sad', 'happy', 'anxious',
      'afraid', 'love', 'hate', 'frustrated', 'grateful', 'worried',
      'excited', 'confused', 'hurt', 'joy', 'peace', 'stress',
      'overwhelm', 'calm', 'restless', 'hope', 'fear', 'shame',
      'guilt', 'proud', 'disappointed', 'relieved', 'lonely',
      'release', 'let go', 'holding', 'resist', 'accept',
    ];

    int hits = 0;
    for (final word in emotionWords) {
      if (lower.contains(word)) hits++;
    }

    return hits >= 2; // At least 2 different emotional markers
  }
}

/// Result of local pre-validation
class ValidationResult {
  final bool accepted;
  final List<String> issues;
  final Map<String, dynamic> metrics;

  ValidationResult({
    required this.accepted,
    required this.issues,
    required this.metrics,
  });
}

```
