---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/models/semantic_types.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.752289+00:00
---

# archive/apps-navigation_app/lib/models/semantic_types.dart

```dart
/// Core semantic consumption types from the Semantos kernel.
/// These enforce the personal development metaphor:
/// - LINEAR: consumed once (releases, sessions) — you let go, it's gone
/// - AFFINE: acknowledge or discard (intentions) — fulfil or outgrow
/// - RELEVANT: persists, accumulates (insights, patterns) — wisdom that stays
enum ConsumptionType { linear, affine, relevant }

/// The seven life dimensions for tracking growth
enum Dimension {
  mental,
  physical,
  spiritual,
  social,
  vocational,
  financial,
  familial;

  String get label => switch (this) {
        mental => 'Mental',
        physical => 'Physical',
        spiritual => 'Spiritual',
        social => 'Social',
        vocational => 'Vocational',
        financial => 'Financial',
        familial => 'Familial',
      };

  String get subtitle => switch (this) {
        mental => 'Knowledge & Wisdom',
        physical => 'Body & Health',
        spiritual => 'Divine Connection',
        social => 'Peer Relationships',
        vocational => 'Meaningful Work',
        financial => 'Wealth Systems',
        familial => 'Family & Tribe',
      };

  String get emoji => switch (this) {
        mental => '🧠',
        physical => '💪',
        spiritual => '🙏',
        social => '👥',
        vocational => '💼',
        financial => '💰',
        familial => '👨‍👩‍👧‍👦',
      };
}

/// The navigation process is NOT a linear tower.
/// It's a set of nested process cycles that build on each other,
/// with recursive release/receive patterns at each depth.
///
/// Structure from the Quantum Movement diagram:
///
///   FOUNDATION
///     Growth → Attention → Ease
///
///   CYCLE 1: Energetic Release
///     QSE Vacuum (release) → Resistance → Acceptance
///     → QSE Integrate (receive) → Gold seal
///
///   CYCLE 2: Conscious Release
///     Release → Awareness → Connection
///     → Release → Receive (deeper pass)
///
///   DISCERNMENT
///     Degrees of Authenticity
///     → Ego (Belief ↔ Knowledge)
///     → Soul (Discernment ↔ Wisdom)
///
///   APPLICATION
///     Understanding → Creation (7 dimensions) → Completion

/// A process cycle — a self-contained release/receive loop
enum ProcessCycle {
  foundation,
  energeticRelease,
  consciousRelease,
  discernment,
  application;

  String get label => switch (this) {
        foundation => 'Foundation',
        energeticRelease => 'Energetic Release',
        consciousRelease => 'Conscious Release',
        discernment => 'Discernment',
        application => 'Application',
      };

  String get description => switch (this) {
        foundation => 'Build the base: willingness to grow, command of attention, finding ease',
        energeticRelease => 'Clear what doesn\'t serve you through the QSE vacuum, meet resistance, accept, integrate, seal with gold',
        consciousRelease => 'Deeper release through writing and awareness. Connect, release again, receive at a new level',
        discernment => 'Distinguish ego from soul. Belief vs knowledge. Discernment vs wisdom. Degrees of authenticity',
        application => 'Apply understanding across all seven dimensions. Create. Complete.',
      };

  String get inquiry => switch (this) {
        foundation => 'WHO am I?',
        energeticRelease => 'WHAT am I holding?',
        consciousRelease => 'WHEN do I release?',
        discernment => 'WHY do I believe this?',
        application => 'WHERE & HOW do I create?',
      };
}

/// Steps within each process cycle
class ProcessStep {
  final String id;
  final String label;
  final ProcessCycle cycle;
  final bool isRelease; // Part of a release phase
  final bool isReceive; // Part of a receive phase
  final String description;

  const ProcessStep({
    required this.id,
    required this.label,
    required this.cycle,
    this.isRelease = false,
    this.isReceive = false,
    required this.description,
  });
}

/// All steps in the navigation process
const allProcessSteps = [
  // Foundation
  ProcessStep(
    id: 'growth',
    label: 'Growth',
    cycle: ProcessCycle.foundation,
    description: 'The willingness to grow. Everything begins here.',
  ),
  ProcessStep(
    id: 'attention',
    label: 'Attention',
    cycle: ProcessCycle.foundation,
    description: 'Master the command of your attention. Where it goes, energy flows.',
  ),
  ProcessStep(
    id: 'ease',
    label: 'Ease',
    cycle: ProcessCycle.foundation,
    description: 'Find ease in the process. Growth doesn\'t require struggle.',
  ),

  // Cycle 1: Energetic Release
  ProcessStep(
    id: 'qse_vacuum',
    label: 'QSE Vacuum',
    cycle: ProcessCycle.energeticRelease,
    isRelease: true,
    description: 'Invoke quantum source energy. Clear tube. Release everything except your highest authentic expression.',
  ),
  ProcessStep(
    id: 'resistance',
    label: 'Resistance',
    cycle: ProcessCycle.energeticRelease,
    description: 'Meet what resists the release. What are you holding onto?',
  ),
  ProcessStep(
    id: 'acceptance',
    label: 'Acceptance',
    cycle: ProcessCycle.energeticRelease,
    description: 'Accept what is. Stop fighting the resistance itself.',
  ),
  ProcessStep(
    id: 'qse_integrate',
    label: 'QSE Integrate',
    cycle: ProcessCycle.energeticRelease,
    isReceive: true,
    description: 'Replace the clear tube with opaque. Integrate your highest expression.',
  ),
  ProcessStep(
    id: 'gold',
    label: 'Gold',
    cycle: ProcessCycle.energeticRelease,
    description: 'Seal with gold. Permanence. Walk forward.',
  ),

  // Cycle 2: Conscious Release
  ProcessStep(
    id: 'release_1',
    label: 'Release',
    cycle: ProcessCycle.consciousRelease,
    isRelease: true,
    description: 'Write, speak, move — let the content flow out without judgment.',
  ),
  ProcessStep(
    id: 'awareness',
    label: 'Awareness',
    cycle: ProcessCycle.consciousRelease,
    description: 'Expanded awareness of what you just released. What patterns emerge?',
  ),
  ProcessStep(
    id: 'connection',
    label: 'Connection',
    cycle: ProcessCycle.consciousRelease,
    description: 'Connect to highest expression, inner child, future self, ancestors.',
  ),
  ProcessStep(
    id: 'release_2',
    label: 'Release',
    cycle: ProcessCycle.consciousRelease,
    isRelease: true,
    description: 'Deeper release — informed by what awareness and connection revealed.',
  ),
  ProcessStep(
    id: 'receive',
    label: 'Receive',
    cycle: ProcessCycle.consciousRelease,
    isReceive: true,
    description: 'What intelligence is available? What wisdom wants to land?',
  ),

  // Discernment
  ProcessStep(
    id: 'degrees_authenticity',
    label: 'Degrees of Authenticity',
    cycle: ProcessCycle.discernment,
    description: 'Not binary. How authentic are you being right now? Honestly.',
  ),
  ProcessStep(
    id: 'ego_belief_knowledge',
    label: 'Ego: Belief ↔ Knowledge',
    cycle: ProcessCycle.discernment,
    description: 'Ego operates between belief and knowledge. Which is driving you?',
  ),
  ProcessStep(
    id: 'soul_discernment_wisdom',
    label: 'Soul: Discernment ↔ Wisdom',
    cycle: ProcessCycle.discernment,
    description: 'Soul operates between discernment and wisdom. Trust the difference.',
  ),

  // Application
  ProcessStep(
    id: 'understanding',
    label: 'Understanding',
    cycle: ProcessCycle.application,
    isReceive: true,
    description: 'Integrate what you\'ve learned across all cycles into understanding.',
  ),
  ProcessStep(
    id: 'creation',
    label: 'Creation',
    cycle: ProcessCycle.application,
    description: 'Create across all seven dimensions of life.',
  ),
  ProcessStep(
    id: 'completion',
    label: 'Completion',
    cycle: ProcessCycle.application,
    description: 'Manifest and release your creations into the world. Complete the cycle.',
  ),
];

```
