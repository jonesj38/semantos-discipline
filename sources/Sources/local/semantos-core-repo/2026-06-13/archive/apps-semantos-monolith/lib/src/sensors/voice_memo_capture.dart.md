---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/sensors/voice_memo_capture.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.870228+00:00
---

# archive/apps-semantos-monolith/lib/src/sensors/voice_memo_capture.dart

```dart
// D-O5m.followup-8 GPS + voice memo adapters — Voice memo capture.
//
// Mirrors the dependency-injection shape of `camera_capture.dart` and
// `gps_capture.dart`: a thin adapter interface (`VoiceRecorderAdapter`)
// the production code wires to the `record` package, plus a
// stateful `VoiceRecorderController` driving start/stop/cancel +
// emitting a `Stream<RecordingState>` for the recording UI.
//
// On stop, the controller returns a [CapturedVoiceMemo] (recorded
// bytes + mime type + ISO-8601 capture timestamp + duration).  The
// helm feeds the bytes + `kind: voice_memo` + the recorded mime type
// into `attachment_builder.buildSignedAttachment` exactly the same
// way the camera flow feeds JPEG bytes + `kind: photo`.  No new cell
// types, no new brain endpoints — the substrate from #315 / #316
// carries this kind end-to-end without changes.
//
// Recording is capped at `maxDuration` (default 60s) as a safety
// net — the controller auto-stops on timeout and emits the bytes via
// the same `stop()` path so the UI doesn't have to special-case the
// timeout branch.
//
// iOS Info.plist + Android AndroidManifest.xml updates
// (`NSMicrophoneUsageDescription`, `android.permission.RECORD_AUDIO`)
// ride alongside this file.

import 'dart:async';
import 'dart:typed_data';

/// Recording lifecycle states surfaced by [VoiceRecorderController].
/// Mirrors the basic state machine the recording UI cares about: not-
/// started, actively recording, stopped (terminal — controller
/// disposed), cancelled (terminal — bytes discarded), error (terminal
/// — recorder threw).
enum RecordingState {
  idle,
  recording,
  stopped,
  cancelled,
  error,
}

/// One captured voice memo from the device microphone.  Returned by
/// [VoiceRecorderController.stop]; the caller (the helm screen) hands
/// the bytes + mime to `attachment_builder.buildSignedAttachment`
/// with `kind: voice_memo`.
class CapturedVoiceMemo {
  final Uint8List bytes;
  final String mimeType;

  /// ISO-8601 timestamp at recording-start time (device clock, UTC).
  final String capturedAt;

  /// Recorded clip duration in milliseconds.  Best-effort — the
  /// adapter reports the value the platform recorder surfaced, or the
  /// elapsed wall-clock between start + stop when the recorder
  /// doesn't report its own duration.
  final int durationMs;

  const CapturedVoiceMemo({
    required this.bytes,
    required this.mimeType,
    required this.capturedAt,
    required this.durationMs,
  });
}

/// Lightweight abstraction over the platform recorder (`record`
/// package on iOS + Android) that doesn't pull Flutter SDK / package
/// types into the unit-test classpath.  The production wiring (in
/// `helm_app.dart`) implements this via the `record` package's
/// `AudioRecorder().start(...)` + `.stop()` calls; tests inject a
/// stub that returns known fixture bytes.
abstract class VoiceRecorderAdapter {
  /// Begin recording.  Throws on permission denied / hardware error.
  /// Implementations may capture to a temp file or to memory; the
  /// concrete bytes are returned by [stop].
  Future<void> start();

  /// Stop recording + return the recorded bytes + mime type.  Returns
  /// null when the adapter has nothing buffered (e.g. start failed or
  /// stop was called twice).
  Future<RecordedClip?> stop();

  /// Cancel recording — discards any buffered bytes.  Idempotent.
  Future<void> cancel();
}

/// Output of [VoiceRecorderAdapter.stop].
class RecordedClip {
  final Uint8List bytes;
  final String mimeType;
  final int? reportedDurationMs;

  const RecordedClip({
    required this.bytes,
    required this.mimeType,
    this.reportedDurationMs,
  });
}

/// Stateful controller driving the recording UI.  Owns the adapter +
/// the state stream + the timeout watchdog.  One instance per active
/// recording session; call [start] to begin and [stop] / [cancel] to
/// end.  After a terminal state ([RecordingState.stopped],
/// [RecordingState.cancelled], [RecordingState.error]) the controller
/// is single-use — construct a fresh one for the next session.
class VoiceRecorderController {
  final VoiceRecorderAdapter recorder;
  final Duration maxDuration;
  final DateTime Function() clock;

  final _stateController = StreamController<RecordingState>.broadcast();
  RecordingState _state = RecordingState.idle;
  DateTime? _startedAt;
  Timer? _timeoutTimer;
  bool _disposed = false;

  VoiceRecorderController({
    required this.recorder,
    this.maxDuration = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    _stateController.add(_state);
  }

  /// Current state — synchronously readable for UI bindings that
  /// don't want to wait for the next stream tick.
  RecordingState get state => _state;

  /// Stream of state transitions for the recording UI.
  Stream<RecordingState> get stateStream => _stateController.stream;

  /// Begin recording.  Transitions: idle → recording on success, idle
  /// → error on adapter throw.  Returns true on success.
  Future<bool> start() async {
    if (_state != RecordingState.idle) return false;
    try {
      await recorder.start();
      _startedAt = clock();
      _setState(RecordingState.recording);
      _timeoutTimer = Timer(maxDuration, () async {
        if (_state == RecordingState.recording) {
          // Auto-stop on timeout.  The pending stop() call (if any)
          // from the UI will see the controller already in `stopped`
          // and short-circuit; this watchdog flushes the bytes into
          // the same captured-memo result as a manual stop would.
          await _internalStopAfterTimeout();
        }
      });
      return true;
    } catch (_) {
      _setState(RecordingState.error);
      return false;
    }
  }

  /// Stop recording + return the captured memo.  Transitions:
  /// recording → stopped on success, recording → error on throw.
  /// Returns null if not currently recording (UI should disable the
  /// button instead).
  Future<CapturedVoiceMemo?> stop() async {
    if (_state != RecordingState.recording) return null;
    _timeoutTimer?.cancel();
    try {
      final clip = await recorder.stop();
      _setState(RecordingState.stopped);
      if (clip == null) return null;
      return _buildMemo(clip);
    } catch (_) {
      _setState(RecordingState.error);
      return null;
    }
  }

  /// Discard the recording.  Transitions: recording → cancelled,
  /// idle → cancelled (no-op for already-terminal states).
  Future<void> cancel() async {
    if (_state == RecordingState.cancelled ||
        _state == RecordingState.stopped ||
        _state == RecordingState.error) {
      return;
    }
    _timeoutTimer?.cancel();
    try {
      await recorder.cancel();
    } catch (_) {
      // Cancellation must always succeed locally even if the adapter
      // throws — we discard the recording either way.
    }
    _setState(RecordingState.cancelled);
  }

  /// Release the state stream.  Safe to call after any terminal state.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timeoutTimer?.cancel();
    await _stateController.close();
  }

  Future<CapturedVoiceMemo?> _internalStopAfterTimeout() async {
    try {
      final clip = await recorder.stop();
      _setState(RecordingState.stopped);
      return clip == null ? null : _buildMemo(clip);
    } catch (_) {
      _setState(RecordingState.error);
      return null;
    }
  }

  CapturedVoiceMemo _buildMemo(RecordedClip clip) {
    final start = _startedAt;
    final now = clock();
    final elapsed = start == null
        ? 0
        : now.difference(start).inMilliseconds;
    final duration = clip.reportedDurationMs ?? elapsed;
    return CapturedVoiceMemo(
      bytes: clip.bytes,
      mimeType: clip.mimeType,
      capturedAt: (start ?? now).toUtc().toIso8601String(),
      durationMs: duration,
    );
  }

  void _setState(RecordingState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }
}

/// Convenience surface mirroring [captureCurrentLocation] for callers
/// that want the simple "open a controller, await stop, return the
/// memo" shape without managing the controller lifecycle.  The helm
/// uses the controller directly for the start/stop UI; this helper
/// is here for symmetry with the camera + GPS flows and for callers
/// like an automated bot or a "record-on-tap" mode.
Future<CapturedVoiceMemo?> recordVoiceMemo({
  required VoiceRecorderAdapter recorder,
  Duration maxDuration = const Duration(seconds: 60),
  DateTime Function()? clock,
  Future<void> Function(VoiceRecorderController) onStarted = _awaitStop,
}) async {
  final controller = VoiceRecorderController(
    recorder: recorder,
    maxDuration: maxDuration,
    clock: clock,
  );
  try {
    final ok = await controller.start();
    if (!ok) return null;
    await onStarted(controller);
    if (controller.state == RecordingState.recording) {
      return await controller.stop();
    }
    // The onStarted hook may have already stopped the controller; in
    // that case we have nothing more to return — the bytes already
    // landed via that branch's own await stop().
    return null;
  } finally {
    await controller.dispose();
  }
}

Future<void> _awaitStop(VoiceRecorderController controller) async {
  // Default behaviour: wait for the timeout watchdog to fire.  Tests
  // / production override this with a UI-driven hook that calls
  // controller.stop() when the user taps the stop button.
  await controller.stateStream.firstWhere(
    (s) => s != RecordingState.recording,
  );
}

```
