---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/voice_text_input_bar.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.887682+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/voice_text_input_bar.dart

```dart
// D-O5m.followup-7 Phase B — persistent helm voice/text input bar.
//
// Lives at the bottom of the helm Scaffold (wired via `bottomSheet:`
// on HomeScreen — visible on every list tab except Settings).  The
// operator can:
//   - type a natural-language command + tap Send → routes through
//     TextIntentService (Intent.source = 'nl')
//   - tap Mic → opens the existing VoiceCommandSheet (post-#322); on
//     completion the sheet's outcome is reported back to this widget
//     so the inline feedback area renders the same shape as the typed
//     path.
//
// The state machine + outcome summarisation live in
// `voice/voice_text_input_bar_controller.dart`; this widget is the
// thin Flutter view layer.

import 'package:flutter/material.dart';

import '../voice/text_intent_service.dart';
import '../voice/voice_text_input_bar_controller.dart';

/// Callback the input bar invokes when the operator taps the mic
/// button.  Production wires this to a function that opens the
/// existing VoiceCommandSheet on the active visit / job.  Returns the
/// voice command's outcome — the bar reports it back to the controller
/// so the inline feedback area stays in sync with the typed path.
///
/// The closure is opaque so the input bar doesn't reach into voice/
/// command_sheet's surface directly; HomeScreen owns the wiring +
/// passes a closure that knows how to build the sheet.
typedef VoiceMicHandler = Future<VoiceTextInputVoiceOutcome?> Function(
  BuildContext context,
);

/// Outcome the mic handler returns to the input bar — the bar reports
/// this back to the controller via [reportVoiceOutcome] so success +
/// refusal both render in the same inline area.
class VoiceTextInputVoiceOutcome {
  final bool success;
  final String? summary;
  final String? refusalStage;
  final String? refusalReason;

  const VoiceTextInputVoiceOutcome.success({this.summary})
      : success = true,
        refusalStage = null,
        refusalReason = null;

  const VoiceTextInputVoiceOutcome.refused({
    required this.refusalStage,
    required this.refusalReason,
  })  : success = false,
        summary = null;
}

class VoiceTextInputBar extends StatefulWidget {
  /// Service that drives the typed-NL pipeline path.  Production wires
  /// the on-device SIR extractor + DartIntentPipeline; the dev harness
  /// constructs a no-op service that surfaces ExtractorUnavailable.
  final TextIntentService textService;

  /// Closure the bar invokes when the operator taps Mic.  Optional —
  /// when null, the mic button is disabled.
  final VoiceMicHandler? onMicTap;

  /// Hint text shown in the empty TextField.
  final String hintText;

  /// Maximum input length — defaults to 500 (mirrors the brain-side
  /// summary cap).
  final int maxLength;

  /// Optional pre-send hook. When non-null, called with the typed text
  /// before the normal intent pipeline. If it returns true, the text is
  /// consumed (input cleared) and the pipeline is skipped.
  final Future<bool> Function(String text)? onSendOverride;

  const VoiceTextInputBar({
    super.key,
    required this.textService,
    this.onMicTap,
    this.hintText = 'Speak or type a command...',
    this.maxLength = 500,
    this.onSendOverride,
  });

  @override
  State<VoiceTextInputBar> createState() => _VoiceTextInputBarState();
}

class _VoiceTextInputBarState extends State<VoiceTextInputBar> {
  late final VoiceTextInputBarController _controller;
  late final TextEditingController _textCtl;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller =
        VoiceTextInputBarController(textService: widget.textService);
    _controller.addListener(_rebuild);
    _textCtl = TextEditingController()..addListener(_onTextChanged);
  }

  // 2026-05-07 — when OnDeviceVoiceFactory finishes initialising the
  // parent (HomeScreen) rebuilds with the post-init TextIntentService.
  // Without this hook the controller stays bound to the empty default
  // captured in initState, so processText forever returns
  // TextIntentExtractorUnavailable and the operator sees the
  // "Voice pipeline still initialising or failed to initialise"
  // refusal even after init succeeded.
  @override
  void didUpdateWidget(VoiceTextInputBar old) {
    super.didUpdateWidget(old);
    if (!identical(widget.textService, old.textService)) {
      _controller.textService = widget.textService;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    _controller.dispose();
    _textCtl.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() {});
    // Clear the field on success — the operator doesn't want to re-send
    // the same line by accident.
    if (_controller.phase == VoiceTextInputPhase.success) {
      _textCtl.clear();
    }
  }

  void _onTextChanged() {
    final hasText = _textCtl.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  Future<void> _onSend() async {
    final text = _textCtl.text.trim();
    if (text.isEmpty) return;
    final override = widget.onSendOverride;
    if (override != null) {
      final handled = await override(text);
      if (handled) {
        _textCtl.clear();
        return;
      }
    }
    await _controller.submit(_textCtl.text);
  }

  Future<void> _onMicTap() async {
    final handler = widget.onMicTap;
    if (handler == null) return;
    final outcome = await handler(context);
    if (outcome == null) return;
    _controller.reportVoiceOutcome(
      success: outcome.success,
      successSummary: outcome.summary,
      refusalStage: outcome.refusalStage,
      refusalReason: outcome.refusalReason,
    );
  }

  @override
  Widget build(BuildContext context) {
    final phase = _controller.phase;
    final sending = phase == VoiceTextInputPhase.sending;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (phase == VoiceTextInputPhase.success)
              _SuccessFeedback(
                summary: _controller.lastSuccess?.summary ?? '',
              ),
            if (phase == VoiceTextInputPhase.refused)
              _RefusalFeedback(
                refusal: _controller.lastRefusal!,
                onDismiss: _controller.dismissRefusal,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _textCtl,
                    enabled: !sending,
                    maxLines: 4,
                    minLines: 1,
                    maxLength: widget.maxLength,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.hintText,
                      border: const OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) {
                      if (_hasText && !sending) _onSend();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Voice',
                  onPressed:
                      widget.onMicTap == null || sending ? null : _onMicTap,
                  icon: const Icon(Icons.mic),
                ),
                IconButton(
                  tooltip: 'Send',
                  onPressed: !_hasText || sending ? null : _onSend,
                  icon: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessFeedback extends StatelessWidget {
  final String summary;
  const _SuccessFeedback({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.green.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(summary, style: const TextStyle(color: Colors.green)),
        ),
      ]),
    );
  }
}

class _RefusalFeedback extends StatelessWidget {
  final VoiceTextInputRefusal refusal;
  final VoidCallback onDismiss;
  const _RefusalFeedback({required this.refusal, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        width: double.infinity,
        color: Colors.red.withValues(alpha: 0.1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${refusal.stage}: ${refusal.reason}',
              style: const TextStyle(color: Colors.red),
            ),
          ),
          const Icon(Icons.close, color: Colors.red, size: 16),
        ]),
      ),
    );
  }
}

```
