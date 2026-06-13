---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/sensors/voice_memo_capture_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.914160+00:00
---

# archive/apps-semantos-monolith/test/sensors/voice_memo_capture_test.dart

```dart
// D-O5m.followup-8 GPS + voice memo adapters — voice_memo_capture
// unit tests.
//
// Drives `VoiceRecorderController` with a stub VoiceRecorderAdapter
// so the test runs under pure `dart test` (no Flutter SDK / `record`
// package platform binary gate).  Covers:
//   - state-machine transitions: idle → recording → stopped
//   - start failure: idle → error
//   - cancel: recording → cancelled (bytes discarded)
//   - stop returns CapturedVoiceMemo with bytes + mime + timestamp
//   - duration falls back to wall-clock when adapter doesn't report
//   - timeout watchdog auto-stops at maxDuration
//   - double-stop is a no-op (returns null)

import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:semantos/src/sensors/voice_memo_capture.dart';

class _StubRecorder implements VoiceRecorderAdapter {
  final RecordedClip? clip;
  final Object? throwOnStart;
  final Object? throwOnStop;
  bool started = false;
  bool stopped = false;
  bool cancelled = false;

  _StubRecorder({this.clip, this.throwOnStart, this.throwOnStop});

  @override
  Future<void> start() async {
    if (throwOnStart != null) throw throwOnStart!;
    started = true;
  }

  @override
  Future<RecordedClip?> stop() async {
    if (throwOnStop != null) throw throwOnStop!;
    stopped = true;
    return clip;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

void main() {
  group('VoiceRecorderController', () {
    test('happy path: idle → recording → stopped emits memo bytes', () async {
      final fixture = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final stub = _StubRecorder(
        clip: RecordedClip(
          bytes: fixture,
          mimeType: 'audio/m4a',
          reportedDurationMs: 1234,
        ),
      );
      final transitions = <RecordingState>[];
      var ticks = 0;
      final controller = VoiceRecorderController(
        recorder: stub,
        clock: () => DateTime.utc(2026, 5, 15, 14, 30, 0)
            .add(Duration(milliseconds: 100 * ticks++)),
      );
      controller.stateStream.listen(transitions.add);

      expect(await controller.start(), isTrue);
      expect(controller.state, equals(RecordingState.recording));
      expect(stub.started, isTrue);

      final memo = await controller.stop();
      expect(memo, isNotNull);
      expect(memo!.bytes, equals(fixture));
      expect(memo.mimeType, equals('audio/m4a'));
      expect(memo.durationMs, equals(1234));
      expect(memo.capturedAt, equals('2026-05-15T14:30:00.000Z'));
      expect(controller.state, equals(RecordingState.stopped));
      expect(stub.stopped, isTrue);

      await controller.dispose();
      // Drain remaining state events.
      await Future<void>.delayed(Duration.zero);
      expect(transitions, contains(RecordingState.recording));
      expect(transitions, contains(RecordingState.stopped));
    });

    test('start failure transitions to error', () async {
      final stub = _StubRecorder(throwOnStart: Exception('mic denied'));
      final controller = VoiceRecorderController(recorder: stub);

      expect(await controller.start(), isFalse);
      expect(controller.state, equals(RecordingState.error));
      await controller.dispose();
    });

    test('cancel transitions to cancelled and discards bytes', () async {
      final fixture = Uint8List.fromList([0xff]);
      final stub = _StubRecorder(
        clip: RecordedClip(bytes: fixture, mimeType: 'audio/m4a'),
      );
      final controller = VoiceRecorderController(recorder: stub);

      expect(await controller.start(), isTrue);
      await controller.cancel();
      expect(controller.state, equals(RecordingState.cancelled));
      expect(stub.cancelled, isTrue);
      // After cancel, stop() returns null — no bytes leak through.
      final memo = await controller.stop();
      expect(memo, isNull);
      await controller.dispose();
    });

    test('duration falls back to wall-clock elapsed when adapter omits',
        () async {
      final stub = _StubRecorder(
        clip: RecordedClip(
          bytes: Uint8List.fromList([0xaa]),
          mimeType: 'audio/m4a',
          // reportedDurationMs intentionally null
        ),
      );
      var tick = 0;
      // Each clock() advance is +500ms; start@0, stop@1500.
      final controller = VoiceRecorderController(
        recorder: stub,
        clock: () => DateTime.utc(2026, 5, 15, 14, 30, 0)
            .add(Duration(milliseconds: 500 * tick++)),
      );
      await controller.start();
      final memo = await controller.stop();
      expect(memo, isNotNull);
      // tick=0 (start), 1 (stop start.elapsed measure pulls clock at
      // memo build), so elapsed ≥ 500ms.
      expect(memo!.durationMs, greaterThanOrEqualTo(500));
      await controller.dispose();
    });

    test('double stop is a no-op: second call returns null', () async {
      final stub = _StubRecorder(
        clip: RecordedClip(
          bytes: Uint8List.fromList([0x01]),
          mimeType: 'audio/m4a',
          reportedDurationMs: 100,
        ),
      );
      final controller = VoiceRecorderController(recorder: stub);
      await controller.start();
      final first = await controller.stop();
      final second = await controller.stop();
      expect(first, isNotNull);
      expect(second, isNull);
      await controller.dispose();
    });

    test('timeout watchdog auto-stops at maxDuration', () async {
      final stub = _StubRecorder(
        clip: RecordedClip(
          bytes: Uint8List.fromList([0xbe, 0xef]),
          mimeType: 'audio/m4a',
          reportedDurationMs: 50,
        ),
      );
      final controller = VoiceRecorderController(
        recorder: stub,
        maxDuration: const Duration(milliseconds: 50),
      );
      await controller.start();
      // Wait long enough for the watchdog to fire.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(controller.state, equals(RecordingState.stopped));
      // Subsequent manual stop returns null (already stopped).
      final memo = await controller.stop();
      expect(memo, isNull);
      await controller.dispose();
    });
  });

  group('recordVoiceMemo helper', () {
    test('drives controller via onStarted hook + returns memo', () async {
      final stub = _StubRecorder(
        clip: RecordedClip(
          bytes: Uint8List.fromList([0x10, 0x20]),
          mimeType: 'audio/m4a',
          reportedDurationMs: 250,
        ),
      );
      // The onStarted hook stops the controller after a short delay.
      // recordVoiceMemo's outer await-stop branch then returns null
      // because onStarted already stopped (and consumed the bytes via
      // its own controller.stop() call).  We capture the bytes from
      // inside the hook for assertion.
      CapturedVoiceMemo? captured;
      await recordVoiceMemo(
        recorder: stub,
        onStarted: (c) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          captured = await c.stop();
        },
      );
      expect(captured, isNotNull);
      expect(captured!.bytes, equals(Uint8List.fromList([0x10, 0x20])));
      expect(captured!.durationMs, equals(250));
    });
  });
}

```
