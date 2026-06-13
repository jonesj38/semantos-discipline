---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/self/flow_def.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.868983+00:00
---

# archive/apps-semantos-monolith/lib/src/self/flow_def.dart

```dart
// T7.b — Self practice flow definitions.
//
// Mirrors the shape of `cartridges/self/cartridge.json` `flows[]`,
// hand-coded in Dart for v0.1.0.  A future build step (or runtime
// asset load of the manifest JSON) should replace these constants —
// for now the constants ARE the source.  Per Q17 resolution: a single
// templated FlowRunner widget consumes any FlowDef, so adding a new
// flow is a constants edit, not a new screen.
//
// Field-name → field-type mapping mirrors cartridge.json
// `cellTypes[].payloadSchema`.  The completed flow's collected fields
// map directly into a payload that satisfies the corresponding
// `self.practice.*` validator from `@semantos/self`.
//
// SQ1: schemas migrated as-is from configs/extensions/consciousness.json
// (legacy, now deleted).  v0.2.0 may refactor multi-field accountability
// flows (e.g. DailyReview's 16 fields) to array shapes.

import 'package:flutter/foundation.dart';

import 'scan_screen.dart';

/// Result from GET /api/v1/self/sweep, mapped from PaskSweepResult.
class SelfSweepResult {
  final List<PrimedThemeData> primedThemes;
  final double overallElevationEstimate;
  const SelfSweepResult({
    required this.primedThemes,
    required this.overallElevationEstimate,
  });
}

/// Callback that fetches the pask sweep result from the brain.
/// Returns null on failure (caller falls back to empty themes).
typedef SelfSweepFetcher = Future<SelfSweepResult?> Function();

/// Callback invoked when a flow or session step completes — mints a
/// self.* cell via the brain's ratification endpoint.
/// Returns the persisted cellId (64-hex sha256 of the cell bytes) on
/// success.  Throws a typed SelfMint…Error on failure.
/// Async — the UI shows a spinner during the call.
typedef SelfFlowMinter = Future<String> Function(
  String cellTypeName,
  Map<String, String> fields,
);

/// What kind of input the step needs from the user.
enum FlowFieldKind {
  /// Free-form multi-line text (release writing, reflections, intentions).
  longText,

  /// Single-line text (statement, target labels).
  shortText,

  /// One choice from a fixed list (source, prompt template, dimension).
  enumChoice,

  /// Photo / file capture (journal image, attachment).
  photo,
}

/// One step in a self-practice flow.
@immutable
class FlowStep {
  /// Stable step id — matches cartridge.json `flows[].steps[].id`.
  final String id;

  /// Operator-facing prompt rendered above the input.
  final String prompt;

  /// Field name the captured value lands under.  Matches the cellType's
  /// payloadSchema key (e.g. `rawText`, `statement`, `releaseIntentions`).
  final String field;

  final FlowFieldKind kind;

  /// For `enumChoice` kind: allowed values, in display order.  Each
  /// becomes a choice chip.
  final List<String>? enumChoices;

  /// True if this step must be completed before the flow can finish.
  /// False = skippable.
  final bool required;

  const FlowStep({
    required this.id,
    required this.prompt,
    required this.field,
    required this.kind,
    this.enumChoices,
    this.required = true,
  });
}

/// What to do when the flow completes — typically mint a cell.
@immutable
class FlowOnComplete {
  /// Canonical cell-type name (e.g. `self.practice.release`).
  final String cellTypeName;

  const FlowOnComplete({required this.cellTypeName});
}

/// A complete self-practice flow definition.
@immutable
class FlowDef {
  /// Stable flow id — matches cartridge.json `flows[].id`.
  final String id;

  /// Display label rendered in the flow chooser.
  final String name;

  /// Lexicon category from `SelfLexicon` (`release`, `intention`, ...).
  /// Used by intent-parser to route natural-language triggers here.
  final String triggerCategory;

  /// Ordered steps.  FlowRunner walks them in sequence.
  final List<FlowStep> steps;

  final FlowOnComplete onComplete;

  /// Short description shown under the flow card.
  final String? description;

  const FlowDef({
    required this.id,
    required this.name,
    required this.triggerCategory,
    required this.steps,
    required this.onComplete,
    this.description,
  });
}

// ─── Canonical self-practice flows (3 of the 12 ship in v0.1.0) ─────────
//
// Per SQ3 — practice cells get UI surface first.  The remaining 9 flows
// (capture-journal, start-session, gold-seal, connection-receive,
// resistance-inquiry, discernment-check, evening-review,
// morning-intention, dimension-pulse) follow the same shape — adding
// them is a constants edit, no new widget code.

const FlowDef dailyReleaseFlow = FlowDef(
  id: 'daily-release',
  name: 'Daily Release Writing',
  triggerCategory: 'release',
  description: 'Stream-of-consciousness writing — release whatever needs to come out.',
  steps: [
    FlowStep(
      id: 'source',
      prompt: 'How are you releasing today?',
      field: 'source',
      kind: FlowFieldKind.enumChoice,
      enumChoices: ['voice', 'keyboard', 'photo'],
    ),
    FlowStep(
      id: 'prompt-choice',
      prompt: 'Start with a prompt, or go freeform?',
      field: 'prompt',
      kind: FlowFieldKind.enumChoice,
      enumChoices: ['I feel...', 'I release...', 'I am...', 'I choose...', 'freeform'],
      required: false,
    ),
    FlowStep(
      id: 'write',
      prompt: 'Keep the pen moving. Express whatever needs to come out — no judgment, no editing.',
      field: 'rawText',
      kind: FlowFieldKind.longText,
    ),
  ],
  onComplete: FlowOnComplete(cellTypeName: 'self.practice.release'),
);

const FlowDef setIntentionFlow = FlowDef(
  id: 'set-intention',
  name: 'Set Intention',
  triggerCategory: 'intention',
  description: 'Choose a direction — name the dimension it targets.',
  steps: [
    FlowStep(
      id: 'statement',
      prompt: 'What do you choose? State your intention.',
      field: 'statement',
      kind: FlowFieldKind.shortText,
    ),
    FlowStep(
      id: 'dimension',
      prompt: 'Which dimension does this intention target?',
      field: 'dimensions',
      kind: FlowFieldKind.enumChoice,
      enumChoices: ['MENTAL', 'PHYSICAL', 'SPIRITUAL', 'SOCIAL', 'VOCATIONAL', 'FINANCIAL', 'FAMILIAL'],
      required: false,
    ),
  ],
  onComplete: FlowOnComplete(cellTypeName: 'self.practice.intention'),
);

const FlowDef vacuumSessionFlow = FlowDef(
  id: 'vacuum-session',
  name: 'QSE Vacuum Cleaner',
  triggerCategory: 'vacuum',
  description: 'Release everything except your highest authentic expression. Then integrate.',
  steps: [
    FlowStep(
      id: 'invoke',
      prompt:
          'Invoke quantum source energy between your hands. '
          'Were you attentive throughout? Do you feel a shift?',
      field: 'releaseIntentions',
      kind: FlowFieldKind.longText,
      required: false,
    ),
    FlowStep(
      id: 'release',
      prompt:
          'Visualize the clear tube coming down over your head, connected to the source. '
          'What do you wish to release?',
      field: 'releaseIntentions',
      kind: FlowFieldKind.longText,
    ),
    FlowStep(
      id: 'integrate',
      prompt:
          'Now the opaque tube. What do you wish to integrate? '
          'Fill the space that was created. Reinforce the boundaries.',
      field: 'integrateIntentions',
      kind: FlowFieldKind.longText,
    ),
  ],
  onComplete: FlowOnComplete(cellTypeName: 'self.practice.vacuum'),
);

// ─── Remaining 9 flows landed in v0.2.0 (tick 26) ───────────────────────

const FlowDef captureJournalFlow = FlowDef(
  id: 'capture-journal',
  name: 'Capture Journal Photo',
  triggerCategory: 'release',
  description: 'Upload a photo of your handwritten journal page.',
  steps: [
    FlowStep(
      id: 'upload',
      prompt: 'Upload a photo of your handwritten journal page.',
      field: 'journalImageRef',
      kind: FlowFieldKind.photo,
    ),
  ],
  onComplete: FlowOnComplete(cellTypeName: 'self.practice.release'),
);

const FlowDef startSessionFlow = FlowDef(
  id: 'start-session',
  name: 'Start Daily Session',
  triggerCategory: 'session',
  description: 'A pre-session check-in. Bring attention to yourself before you begin.',
  steps: [
    FlowStep(
      id: 'check-in',
      prompt: 'Before we begin — how are you arriving? Can you bring your attention to yourself right now?',
      field: 'reflection',
      kind: FlowFieldKind.longText,
      required: false,
    ),
  ],
  onComplete: FlowOnComplete(cellTypeName: 'self.practice.session'),
);

const FlowDef goldSealFlow = FlowDef(
  id: 'gold-seal',
  name: 'Gold Seal Integration',
  triggerCategory: 'seal',
  description: 'Invoke gold between your hands. Seal yourself. Breathe it in.',
  steps: [
    FlowStep(
      id: 'visualize',
      prompt:
          'Invoke gold between your hands. How do you see it — light, powder, ointment, molten gold, a block?',
      field: 'sealVisualization',
      kind: FlowFieldKind.enumChoice,
      enumChoices: ['light', 'powder', 'ointment', 'block', 'molten', 'custom'],
    ),
  ],
  onComplete: FlowOnComplete(cellTypeName: 'self.practice.seal'),
);

const FlowDef connectionReceiveFlow = FlowDef(
  id: 'connection-receive',
  name: 'Connect & Receive Intelligence',
  triggerCategory: 'connect',
  description: 'Connect to a higher source. What information is available?',
  steps: [
    FlowStep(
      id: 'target',
      prompt:
          'What do you wish to connect to? Your highest authentic expression? Your inner child? '
          'Your future self? Your ancestors? What\'s in your highest good?',
      field: 'target',
      kind: FlowFieldKind.enumChoice,
      enumChoices: [
        'highest-expression',
        'inner-child',
        'future-self',
        'ancestors',
        'highest-good',
        'custom',
      ],
    ),
    FlowStep(
      id: 'question',
      prompt: 'What information is available for you to receive?',
      field: 'question',
      kind: FlowFieldKind.longText,
      required: false,
    ),
    FlowStep(
      id: 'receive',
      prompt:
          'Document the intelligence you receive. Write it down — the writing process supports this receiving.',
      field: 'receivedIntelligence',
      kind: FlowFieldKind.longText,
    ),
  ],
  onComplete: FlowOnComplete(cellTypeName: 'self.practice.connection'),
);

const FlowDef resistanceInquiryFlow = FlowDef(
  id: 'resistance-inquiry',
  name: 'Resistance Inquiry',
  triggerCategory: 'inquire',
  description: 'Where is the resistance? What is competing for your attention?',
  steps: [
    FlowStep(
      id: 'identify',
      prompt:
          'Where is the resistance? What is competing for your attention? '
          'Why are you unable to maintain ease?',
      field: 'rawText',
      kind: FlowFieldKind.longText,
    ),
  ],
  // resistance-inquiry produces a release cell — same shape as a written
  // release, just with the inquiry prompt as the source prompt.
  onComplete: FlowOnComplete(cellTypeName: 'self.practice.release'),
);

const FlowDef discernmentCheckFlow = FlowDef(
  id: 'discernment-check',
  name: 'Discernment Check',
  triggerCategory: 'inquire',
  description: 'A quick insight capture — what just became clear?',
  steps: [
    FlowStep(
      id: 'present',
      prompt: 'What is present for you right now? What just became clear?',
      field: 'content',
      kind: FlowFieldKind.shortText,
    ),
  ],
  onComplete: FlowOnComplete(cellTypeName: 'self.practice.insight'),
);

const FlowDef eveningReviewFlow = FlowDef(
  id: 'evening-review',
  name: 'Evening Review',
  triggerCategory: 'review',
  description: 'Day in review — wins, improvements, tomorrow.',
  steps: [
    FlowStep(
      id: 'wins',
      prompt: 'Three wins from today (one per line, or comma-separated).',
      field: 'wins',
      kind: FlowFieldKind.shortText,
    ),
    FlowStep(
      id: 'improvements',
      prompt: 'Three improvements for tomorrow (one per line, or comma-separated).',
      field: 'improvements',
      kind: FlowFieldKind.shortText,
    ),
    FlowStep(
      id: 'energy-mood',
      prompt: 'How was your energy and mood today?',
      field: 'energyLevel',
      kind: FlowFieldKind.longText,
    ),
    FlowStep(
      id: 'tomorrow',
      prompt: 'Single intention for tomorrow.',
      field: 'tomorrowIntention',
      kind: FlowFieldKind.shortText,
    ),
    FlowStep(
      id: 'gratitude',
      prompt: 'One thing you\'re grateful for today (optional).',
      field: 'gratitude',
      kind: FlowFieldKind.shortText,
      required: false,
    ),
  ],
  // v0.1.0: 16-field DailyReview schema simplified to 5 fields in this
  // flow (per SQ1 — refactor to array shapes in v0.2.0 when PWA usage
  // matures).  The 'wins' / 'improvements' fields are comma-delimited
  // strings that downstream code can split on need.
  onComplete: FlowOnComplete(cellTypeName: 'self.accountability.review'),
);

const FlowDef morningIntentionFlow = FlowDef(
  id: 'morning-intention',
  name: 'Morning Intention',
  triggerCategory: 'morning',
  description: 'Set today\'s direction. How did yesterday land?',
  steps: [
    FlowStep(
      id: 'yesterday-check',
      prompt: 'How did yesterday\'s intention land?',
      field: 'yesterdayReview',
      kind: FlowFieldKind.enumChoice,
      enumChoices: ['fulfilled', 'partial', 'missed', 'transformed'],
    ),
    FlowStep(
      id: 'today-intention',
      prompt: 'Today\'s intention — single statement.',
      field: 'todayIntention',
      kind: FlowFieldKind.shortText,
    ),
    FlowStep(
      id: 'concrete-action',
      prompt: 'One concrete action you\'ll take today to fulfil this intention.',
      field: 'concreteAction',
      kind: FlowFieldKind.shortText,
    ),
  ],
  onComplete: FlowOnComplete(cellTypeName: 'self.accountability.morning'),
);

const FlowDef dimensionPulseFlow = FlowDef(
  id: 'dimension-pulse',
  name: 'Dimension Pulse',
  triggerCategory: 'pulse',
  description: 'Quick 1-tap check-in on one of the seven life dimensions.',
  steps: [
    FlowStep(
      id: 'quick-check',
      prompt: 'Which dimension are you checking in on right now?',
      field: 'dimension',
      kind: FlowFieldKind.enumChoice,
      enumChoices: [
        'MENTAL',
        'PHYSICAL',
        'SPIRITUAL',
        'SOCIAL',
        'VOCATIONAL',
        'FINANCIAL',
        'FAMILIAL',
      ],
    ),
  ],
  onComplete: FlowOnComplete(cellTypeName: 'self.accountability.pulse'),
);

/// All 12 v0.2.0 flows in chooser display order.  Adding a flow = append
/// to this list; FlowRunner renders it without code changes per Q17.
const List<FlowDef> selfFlows = [
  dailyReleaseFlow,
  captureJournalFlow,
  setIntentionFlow,
  startSessionFlow,
  vacuumSessionFlow,
  goldSealFlow,
  connectionReceiveFlow,
  resistanceInquiryFlow,
  discernmentCheckFlow,
  eveningReviewFlow,
  morningIntentionFlow,
  dimensionPulseFlow,
];

```
