---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/voice_command_sheet.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.896005+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/voice_command_sheet.dart

```dart
// D-O5m.followup-3 Phase 1 — Voice command modal sheet.
//
// 6-state machine surfaced as a modal bottom sheet from
// VisitDetailScreen's "Voice command" CTA:
//
//   recording      → mic icon pulses, stop button live
//   transcribing   → spinner + "Transcribing..."
//   review         → recognised text + [Send] [Re-record] [Cancel]
//   sending        → spinner + "Processing..."
//   done           → outcome message + [Close]
//   failed         → typed reason + [Retry] [Cancel]
//
// On Send the recording is POSTed via [VoiceExtractUploader]; on
// network failure the call enqueues to the outbox under
// `oddjobz.voice_extract.v1` and the sheet transitions to a "queued
// offline" Done state.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../gradient/dart_pipeline.dart';
import '../gradient/oddjobz_extension_context.dart' show kOddjobzDomainFlag;
import '../outbox/outbox_db.dart';
import '../repl/conversation_turns_repository.dart';
import '../sensors/voice_memo_capture.dart';
import '../voice/sir_extractor.dart';
import '../voice/voice_command_service.dart';
import '../voice/voice_extract_uploader.dart';

enum _SheetPhase { recording, transcribing, review, sending, done, failed }

class VoiceCommandSheet extends StatefulWidget {
  /// Recorder factory — same shape as the existing voice-memo-capture
  /// flow uses; passes a single-use [VoiceRecorderAdapter] per
  /// recording.
  final VoiceRecorderAdapter Function() recorderFactory;
  final VoiceCommandService commandService;
  final VoiceExtractUploader uploader;
  final OutboxDb outboxDb;
  final String visitId;
  final String hatContext;
  final String Function() correlationIdFactory;

  /// Cap recording at 30 seconds — Phase 1 STT tolerates short
  /// commands; longer takes inflate the brain-side shellout cost.
  final Duration maxDuration;

  /// Phase 5 — D-OJ-conv-voice-intake.  When [jobCellId] and
  /// [turnsRepository] are both set, a successful send also submits
  /// the transcript as a ConversationTurn anchored to the job.  This
  /// is best-effort (failure is silently swallowed) so the main voice
  /// pipeline result is unaffected.
  final String? jobCellId;
  final ConversationTurnsRepository? turnsRepository;

  const VoiceCommandSheet({
    super.key,
    required this.recorderFactory,
    required this.commandService,
    required this.uploader,
    required this.outboxDb,
    required this.visitId,
    required this.hatContext,
    required this.correlationIdFactory,
    this.maxDuration = const Duration(seconds: 30),
    this.jobCellId,
    this.turnsRepository,
  });

  @override
  State<VoiceCommandSheet> createState() => _VoiceCommandSheetState();
}

class _VoiceCommandSheetState extends State<VoiceCommandSheet> {
  _SheetPhase _phase = _SheetPhase.recording;
  late final VoiceRecorderController _recorder;
  Timer? _maxTimer;
  Timer? _ticker;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  StreamSubscription<RecordingState>? _stateSub;

  // Review-phase state.
  VoiceCommandRecording? _recording;

  // Done / failed-phase state.
  String _outcomeMessage = '';
  String _failureReason = '';

  @override
  void initState() {
    super.initState();
    _recorder = VoiceRecorderController(recorder: widget.recorderFactory());
    _stateSub = _recorder.stateStream.listen((s) {
      if (!mounted) return;
      if (s == RecordingState.error && _phase == _SheetPhase.recording) {
        setState(() {
          _phase = _SheetPhase.failed;
          _failureReason = 'Recorder failed to start.';
        });
      }
    });
    _startRecording();
  }

  @override
  void dispose() {
    _maxTimer?.cancel();
    _ticker?.cancel();
    _stateSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    // Check / request microphone permission before touching the recorder.
    // Without this, AudioRecorder.start() throws a PlatformException on
    // first run (or after the user denies), leaving the sheet in a failed
    // state whose text is invisible against the transparent background.
    final micStatus = await Permission.microphone.request();
    if (!mounted) return;
    if (!micStatus.isGranted) {
      setState(() {
        _phase = _SheetPhase.failed;
        _failureReason = micStatus.isPermanentlyDenied
            ? 'Microphone permission permanently denied.\n'
                'Enable it in Settings → Apps → oddjobz → Permissions.'
            : 'Microphone permission denied — tap Retry to re-prompt.';
      });
      return;
    }

    final ok = await _recorder.start();
    if (!ok) {
      if (!mounted) return;
      setState(() {
        _phase = _SheetPhase.failed;
        _failureReason = 'Could not start recorder.';
      });
      return;
    }
    if (!mounted) return;
    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() {
        _elapsed = DateTime.now().difference(_startedAt!);
      });
    });
    _maxTimer = Timer(widget.maxDuration, _onStopPressed);
  }

  Future<void> _onStopPressed() async {
    if (_phase != _SheetPhase.recording) return;
    _maxTimer?.cancel();
    _ticker?.cancel();
    setState(() => _phase = _SheetPhase.transcribing);
    final memo = await _recorder.stop();
    if (memo == null) {
      if (!mounted) return;
      setState(() {
        _phase = _SheetPhase.failed;
        _failureReason = 'Recorder produced no audio.';
      });
      return;
    }
    final outcome = await widget.commandService.processRecording(
      recordedBytes: memo.bytes,
      mimeType: memo.mimeType,
      durationMs: memo.durationMs,
    );
    if (!mounted) return;
    if (outcome is VoiceCommandReady) {
      setState(() {
        _phase = _SheetPhase.review;
        _recording = outcome.recording;
      });
    } else if (outcome is VoiceCommandFailed) {
      setState(() {
        _phase = _SheetPhase.failed;
        _failureReason = _failureLabel(outcome.failure);
      });
    }
  }

  String _failureLabel(VoiceCommandFailure f) {
    switch (f) {
      case VoiceCommandRecorderUnavailable(:final reason):
        return 'Recorder unavailable: $reason';
      case VoiceCommandTranscriptionFailed(:final reason):
        return 'Transcription failed: $reason';
      case VoiceCommandNotPaired():
        return 'Device not paired — pair the device before voice commands.';
      case VoiceCommandCancelled():
        return 'Cancelled.';
    }
  }

  /// D-O5m.followup-1 — render an operator-friendly message for a typed
  /// pipeline rejection. K1-K4 violations get specific guidance ("the
  /// cell was already used", "switch to the right hat"); other
  /// rejections fall through to the generic stage+message format.
  String _rejectionMessage(IntentRejection r) {
    if (r.stage == 'kernel' && r.kernelViolation != null) {
      switch (r.kernelViolation!) {
        case PipelineKernelViolation.k1Linearity:
          return "K1 violation: cell already used. Refresh and retry.";
        case PipelineKernelViolation.k2Auth:
          return "K2 violation: signature couldn't be verified. Re-pair your device.";
        case PipelineKernelViolation.k3Domain:
          return "K3 violation: hat doesn't have access. Switch to the right hat.";
        case PipelineKernelViolation.k4Atomicity:
          return "K4 violation: transition aborted. State was rolled back.";
        case PipelineKernelViolation.scriptInvalid:
          return "Refused (local): the gradient produced bytes the kernel can't run.";
        case PipelineKernelViolation.unknown:
          // Fall through to the generic message below.
          break;
      }
    }
    return "Couldn't apply: ${r.stage} — ${r.message}";
  }

  /// Phase 5 — best-effort ConversationTurn anchor.  Fire-and-forget:
  /// never throws, so the main pipeline result is unaffected.
  void _submitVoiceNoteIfAnchored(
    String transcript, {
    double? durationSeconds,
  }) {
    final repo = widget.turnsRepository;
    final cellId = widget.jobCellId;
    if (repo == null || cellId == null || cellId.isEmpty) return;
    repo
        .submitVoiceNote(
          transcript: transcript,
          entityId: cellId,
          entityKind: 'job',
          capturedAt: DateTime.now().toUtc().toIso8601String(),
          durationSeconds: durationSeconds,
        )
        // ignore errors — the ConversationTurn is supplementary to the
        // main voice pipeline; a failure must not surface to the operator.
        .catchError((_) => '');
  }

  Future<void> _onSendPressed() async {
    final r = _recording;
    if (r == null) return;
    setState(() => _phase = _SheetPhase.sending);

    // Phase 3 — local-pipeline fast path. When the on-device
    // gradient already produced a typed result, we surface it
    // directly:
    //   - IntentSuccess: cell already signed locally; the outbox
    //     carries it to the brain via the existing signed-cell path.
    //   - IntentRejected: surface the structured rejection so the
    //     operator gets a named reason instead of an opaque error.
    final local = r.localPipelineResult;
    if (local is IntentSuccess) {
      // The cell is signed + locally persisted by the pipeline; the
      // outbox flushes it on next sync. Audio + transcript travel
      // alongside as attachments (the audit-trail link).
      final metadata = VoiceExtractMetadata(
        visitId: widget.visitId,
        hatContext: widget.hatContext,
        clientCorrelationId: local.correlationId,
      );
      await _enqueueOffline(r, metadata);
      // Phase 5 — also anchor as ConversationTurn when in job context.
      _submitVoiceNoteIfAnchored(
        r.transcript.text,
        durationSeconds:
            r.audioBytes.isNotEmpty ? _elapsed.inMilliseconds / 1000.0 : null,
      );
      if (!mounted) return;
      setState(() {
        _phase = _SheetPhase.done;
        _outcomeMessage =
            'Done (signed locally; syncing to brain) — cell ${local.cell.id}';
      });
      return;
    }
    if (local is IntentRejected) {
      if (!mounted) return;
      setState(() {
        _phase = _SheetPhase.failed;
        _failureReason = _rejectionMessage(local.rejection);
      });
      return;
    }

    // Phase 1/2 fallback path — POST to brain.
    final metadata = VoiceExtractMetadata(
      visitId: widget.visitId,
      hatContext: widget.hatContext,
      clientCorrelationId: widget.correlationIdFactory(),
    );
    final result = await widget.uploader.upload(
      audioBytes: r.audioBytes,
      mimeType: r.mimeType,
      transcript: r.transcript,
      metadata: metadata,
      sirCandidate: r.sirCandidate,
    );
    if (!mounted) return;
    if (result is VoiceExtractSuccess) {
      // Phase 5 — anchor transcript as ConversationTurn when in job context.
      _submitVoiceNoteIfAnchored(
        r.transcript.text,
        durationSeconds:
            r.audioBytes.isNotEmpty ? _elapsed.inMilliseconds / 1000.0 : null,
      );
      setState(() {
        _phase = _SheetPhase.done;
        _outcomeMessage = '${result.operatorSummary} (brain confirmed)';
      });
    } else if (result is VoiceExtractNetworkError) {
      // Enqueue to the outbox for offline flush.
      await _enqueueOffline(r, metadata);
      setState(() {
        _phase = _SheetPhase.done;
        _outcomeMessage = 'Voice command queued (offline) — will send on reconnect.';
      });
    } else if (result is VoiceExtractFailed) {
      setState(() {
        _phase = _SheetPhase.failed;
        _failureReason = '${result.reason}${result.message == null ? '' : ' (${result.message})'}';
      });
    }
  }

  Future<void> _enqueueOffline(
      VoiceCommandRecording r, VoiceExtractMetadata metadata) async {
    // W1.2 — blob_path is obsolete; audio bytes are no longer persisted
    // separately.  The envelope JSON (transcript + metadata) is the payload.
    final envelope = {
      'transcript': r.transcript.toJson(),
      'metadata': metadata.toJson(),
    };
    // W1.2 — cellType/payloadJson/blobPath replaced with cell-envelope schema.
    // Generate a random 32-byte cellId; the envelope JSON becomes the payload.
    final cellId32 = Uint8List(32);
    final rng = Random.secure();
    for (var i = 0; i < 32; i++) {
      cellId32[i] = rng.nextInt(256);
    }
    await widget.outboxDb.enqueue(
      cellId: cellId32,
      domainFlag: kOddjobzDomainFlag,
      payload: Uint8List.fromList(utf8.encode(_jsonEncode(envelope))),
    );
  }

  void _onCancelPressed() {
    Navigator.of(context).pop();
  }

  void _onClosePressed() {
    Navigator.of(context).pop();
  }

  Future<void> _onRetryPressed() async {
    setState(() {
      _phase = _SheetPhase.recording;
      _recording = null;
      _failureReason = '';
      _elapsed = Duration.zero;
      _startedAt = null;
    });
    // Re-construct a fresh recorder; the old one is single-use.
    await _recorder.cancel();
    _stateSub?.cancel();
    _maxTimer?.cancel();
    _ticker?.cancel();
    setState(() {});
    // Caller must re-open the sheet to get a fresh adapter; for now
    // simply close.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Material wraps the content so the sheet has a visible surface even
    // when the caller passes backgroundColor: Colors.transparent to
    // showModalBottomSheet.  Without this, error/recording text is
    // rendered on a transparent-over-dark-barrier background and is
    // invisible to the operator.
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _buildPhase(context),
          ),
        ),
      ),
    );
  }

  Widget _buildPhase(BuildContext context) {
    switch (_phase) {
      case _SheetPhase.recording:
        return _buildRecording();
      case _SheetPhase.transcribing:
        return _buildSpinner('Transcribing…');
      case _SheetPhase.review:
        return _buildReview();
      case _SheetPhase.sending:
        return _buildSpinner('Processing…');
      case _SheetPhase.done:
        return _buildDone();
      case _SheetPhase.failed:
        return _buildFailed();
    }
  }

  Widget _buildRecording() => Column(
        key: const ValueKey('recording'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic, size: 64, color: Colors.red),
          const SizedBox(height: 12),
          Text('Recording — ${_fmt(_elapsed)}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                onPressed: _onCancelPressed,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: _onStopPressed,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
        ],
      );

  Widget _buildSpinner(String label) => Column(
        key: ValueKey(label),
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(fontSize: 16)),
        ],
      );

  Widget _buildReview() {
    final r = _recording;
    return Column(
      key: const ValueKey('review'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Recognised:',
            style: TextStyle(fontSize: 14, color: Colors.black54)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            r?.transcript.text ?? '(no text)',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        const SizedBox(height: 12),
        // Phase 2 — surface the on-device extracted SIR (or a
        // fallback note when extraction was refused / unavailable).
        _buildSirSummary(r),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            OutlinedButton.icon(
              onPressed: _onCancelPressed,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: _onRetryPressed,
              icon: const Icon(Icons.replay),
              label: const Text('Re-record'),
            ),
            ElevatedButton.icon(
              onPressed: _onSendPressed,
              icon: const Icon(Icons.send),
              label: const Text('Send'),
            ),
          ],
        ),
      ],
    );
  }

  /// Phase 2 — render the SIR summary in plain English.  Three
  /// branches: success (show extracted Intent verbs), refused (note
  /// fallback to brain-side), unavailable (no extractor configured /
  /// no model on disk -> brain handles everything).
  Widget _buildSirSummary(VoiceCommandRecording? r) {
    final sir = r?.sirExtractionResult;
    if (sir is SirExtractionSuccess) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('On-device extraction (confidence ${sir.confidence.toStringAsFixed(2)}):',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Text(_summariseIntent(sir.intent),
                style: const TextStyle(fontSize: 14)),
          ],
        ),
      );
    }
    if (sir is SirExtractionRefused) {
      return Text(
        'Brain will extract intent (on-device extractor refused: ${sir.reason})',
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      );
    }
    return const Text(
      'Brain will extract intent.',
      style: TextStyle(fontSize: 12, color: Colors.black54),
    );
  }

  /// Render an Intent map as plain English for operator review.
  /// Covers the common oddjobz Intent shape: action verb + target
  /// object + category.  Falls back to the action verb alone if no
  /// target is present.
  static String _summariseIntent(Map<String, dynamic> intent) {
    final action = intent['action']?.toString() ?? 'do';
    final cat = intent['category'];
    final categoryName = (cat is Map) ? cat['category']?.toString() : null;
    final target = intent['target'];
    final objectId = (target is Map) ? target['objectId']?.toString() : null;
    if (objectId != null && objectId.isNotEmpty && categoryName != null) {
      return 'Will: $action $categoryName for $objectId';
    }
    if (categoryName != null) {
      return 'Will: $action $categoryName';
    }
    return 'Will: $action';
  }

  Widget _buildDone() => Column(
        key: const ValueKey('done'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 64, color: Colors.green),
          const SizedBox(height: 12),
          Text(_outcomeMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _onClosePressed,
            child: const Text('Close'),
          ),
        ],
      );

  Widget _buildFailed() => Column(
        key: const ValueKey('failed'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.orange),
          const SizedBox(height: 12),
          Text(_failureReason,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                onPressed: _onCancelPressed,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: _onRetryPressed,
                icon: const Icon(Icons.replay),
                label: const Text('Retry'),
              ),
            ],
          ),
        ],
      );

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

String _jsonEncode(Object o) => json.encode(o);

```
