---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/voice/voice_text_input_bar_controller.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.865879+00:00
---

# archive/apps-semantos-monolith/lib/src/voice/voice_text_input_bar_controller.dart

```dart
// D-O5m.followup-7 Phase B — pure-Dart state machine for the helm
// voice/text input bar.
//
// The input bar widget itself ships in `helm/voice_text_input_bar.dart`
// and only delegates to this controller — pattern mirrors
// `ratification_card_controller.dart` so unit tests stay
// Flutter-SDK-free.
//
// Lifecycle phases:
//   - idle       → text field accepting input; send + mic available
//   - sending    → spinner; field disabled
//   - success    → green inline check + summary text; auto-fades back
//                  to idle after [successDisplayDuration]
//   - refused    → red inline error; tap-to-dismiss returns to idle
//
// The controller never touches the Flutter input field directly — it
// just exposes the typed phase + result so the widget renders the
// matching state.  When the operator taps Send, the widget calls
// [submit] with the typed text; when the operator taps Mic, the widget
// opens the existing VoiceCommandSheet directly (the input bar is just
// a launcher for that sheet) and on completion calls
// [reportVoiceOutcome] with the matching success/refusal so the same
// inline feedback area renders the result.

import 'dart:async';

import '../gradient/dart_pipeline.dart';
import 'text_intent_service.dart';

/// Lifecycle phase of the input bar.
enum VoiceTextInputPhase {
  idle,
  sending,
  success,
  refused,
}

/// Successful submission — the inline feedback area renders [summary]
/// for [VoiceTextInputBarController.successDisplayDuration].
class VoiceTextInputSuccess {
  final String summary;
  const VoiceTextInputSuccess(this.summary);
}

/// Refused submission — the inline feedback area renders the structured
/// stage/reason.  Operator taps to dismiss.
class VoiceTextInputRefusal {
  /// Stage that refused — `extractor`, `pipeline-sir`, `pipeline-kernel`,
  /// `network`, `unavailable`.
  final String stage;
  final String reason;
  const VoiceTextInputRefusal({required this.stage, required this.reason});
}

class VoiceTextInputBarController {
  // 2026-05-07 — mutable so the bar can swap in the post-init
  // TextIntentService when OnDeviceVoiceFactory finishes booting.
  // Pre-fix this was `final`, so the controller froze a snapshot of
  // the empty default in initState and processText forever returned
  // TextIntentExtractorUnavailable even after the factory had
  // initialised.  See voice_text_input_bar.dart didUpdateWidget.
  TextIntentService textService;

  /// How long to render the success state before auto-fading back to
  /// idle.  Operators read the summary then return to typing.
  final Duration successDisplayDuration;

  VoiceTextInputBarController({
    required this.textService,
    this.successDisplayDuration = const Duration(seconds: 3),
  });

  VoiceTextInputPhase _phase = VoiceTextInputPhase.idle;
  VoiceTextInputSuccess? _success;
  VoiceTextInputRefusal? _refusal;
  Timer? _successTimer;

  VoiceTextInputPhase get phase => _phase;
  VoiceTextInputSuccess? get lastSuccess => _success;
  VoiceTextInputRefusal? get lastRefusal => _refusal;

  final List<void Function()> _listeners = [];
  void addListener(void Function() cb) => _listeners.add(cb);
  void removeListener(void Function() cb) => _listeners.remove(cb);
  void _notify() {
    for (final l in List<void Function()>.from(_listeners)) {
      l();
    }
  }

  /// Operator tapped Send with [text] in the field.  Drives the
  /// TextIntentService and renders the typed outcome inline.  No-op
  /// when text is empty (the widget should disable Send anyway, but
  /// belt-and-braces).
  Future<void> submit(String text) async {
    if (text.trim().isEmpty) return;
    _setSending();
    final outcome = await textService.processText(text: text);
    _applyTextOutcome(outcome);
  }

  /// Voice path completion hook — VoiceCommandSheet returns its outcome
  /// to the input bar so the same inline feedback area renders both
  /// paths uniformly.  See voice_text_input_bar.dart for the wiring.
  void reportVoiceOutcome({
    required bool success,
    String? successSummary,
    String? refusalStage,
    String? refusalReason,
  }) {
    if (success) {
      _setSuccess(successSummary ?? 'Voice command processed');
    } else {
      _setRefusal(VoiceTextInputRefusal(
        stage: refusalStage ?? 'voice',
        reason: refusalReason ?? 'voice command refused',
      ));
    }
  }

  /// Operator tapped the inline error to dismiss it.
  void dismissRefusal() {
    if (_phase != VoiceTextInputPhase.refused) return;
    _refusal = null;
    _phase = VoiceTextInputPhase.idle;
    _notify();
  }

  /// Release the success-fade timer.  Call from the widget's dispose.
  void dispose() {
    _successTimer?.cancel();
    _successTimer = null;
  }

  void _setSending() {
    _successTimer?.cancel();
    _phase = VoiceTextInputPhase.sending;
    _success = null;
    _refusal = null;
    _notify();
  }

  void _applyTextOutcome(TextIntentOutcome outcome) {
    switch (outcome) {
      case TextIntentSuccess(:final result):
        _setSuccess(_summariseSuccess(result));
      case TextIntentFailed(:final failure):
        _setRefusal(_summariseFailure(failure));
    }
  }

  void _setSuccess(String summary) {
    _success = VoiceTextInputSuccess(summary);
    _refusal = null;
    _phase = VoiceTextInputPhase.success;
    _successTimer?.cancel();
    _successTimer = Timer(successDisplayDuration, () {
      if (_phase != VoiceTextInputPhase.success) return;
      _success = null;
      _phase = VoiceTextInputPhase.idle;
      _notify();
    });
    _notify();
  }

  void _setRefusal(VoiceTextInputRefusal refusal) {
    _refusal = refusal;
    _success = null;
    _phase = VoiceTextInputPhase.refused;
    _notify();
  }

  /// Operator-readable success summary — derived from the kernel's
  /// cell id by default; the widget can override later if a richer
  /// summary becomes available.
  String _summariseSuccess(IntentSuccess result) =>
      'Cell ${_shortId(result.cell.id)} signed';

  String _shortId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}…${id.substring(id.length - 4)}';
  }

  VoiceTextInputRefusal _summariseFailure(TextIntentFailure failure) {
    switch (failure) {
      case TextIntentRefused(:final reason):
        return VoiceTextInputRefusal(stage: 'extractor', reason: reason);
      case TextIntentRejected(:final rejection):
        return VoiceTextInputRefusal(
          stage: 'pipeline-${rejection.stage}',
          reason: '${rejection.code}: ${rejection.message}',
        );
      case TextIntentExtractorUnavailable():
        return const VoiceTextInputRefusal(
          stage: 'unavailable',
          // 2026-05-07 — honest message.  Pre-fix this said
          // "Try voice instead" which was misleading because voice
          // ALSO fails when the OnDeviceVoiceFactory init fails (both
          // paths share the same factory).  Direct operator to the
          // AppBar error icon, which surfaces the actual exception.
          reason: 'Voice pipeline still initialising or failed to '
              'initialise. If you see a red ⚠ in the AppBar, tap '
              'it for the actual error.',
        );
      case TextIntentPipelineUnavailable():
        return const VoiceTextInputRefusal(
          stage: 'unavailable',
          reason: 'On-device pipeline not configured. Check the '
              'AppBar for a red ⚠ if init failed.',
        );
      case TextIntentNetworkError(:final reason):
        return VoiceTextInputRefusal(stage: 'network', reason: reason);
    }
  }
}

```
