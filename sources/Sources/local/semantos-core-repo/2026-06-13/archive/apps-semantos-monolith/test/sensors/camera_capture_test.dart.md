---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/sensors/camera_capture_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.913595+00:00
---

# archive/apps-semantos-monolith/test/sensors/camera_capture_test.dart

```dart
// D-O5m.followup-8 capture+upload — camera_capture unit tests.
//
// Drives `captureFromCamera` with an injected picker that returns a
// known fixture (or null on cancel) so the test runs under pure
// `dart test` (no Flutter SDK / platform binary gate).

import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:semantos/src/sensors/camera_capture.dart';

void main() {
  group('captureFromCamera', () {
    test('returns null when picker returns null (user cancel)', () async {
      final result = await captureFromCamera(
        picker: () async => null,
        clock: () => DateTime.utc(2026, 5, 15, 14, 30),
      );
      expect(result, isNull);
    });

    test('returns null when picker throws', () async {
      final result = await captureFromCamera(
        picker: () async => throw Exception('no camera'),
        clock: () => DateTime.utc(2026, 5, 15, 14, 30),
      );
      expect(result, isNull);
    });

    test('returns CapturedPhoto with bytes, mime, ISO-8601 timestamp',
        () async {
      final fixture = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0x42]);
      final result = await captureFromCamera(
        picker: () async => PickedPhoto(bytes: fixture, mimeType: 'image/jpeg'),
        clock: () => DateTime.utc(2026, 5, 15, 14, 30, 0),
      );
      expect(result, isNotNull);
      expect(result!.bytes, equals(fixture));
      expect(result.mimeType, equals('image/jpeg'));
      // ISO-8601 UTC form
      expect(result.capturedAt, equals('2026-05-15T14:30:00.000Z'));
    });

    test('passes through HEIC mime when picker reports it', () async {
      final fixture = Uint8List.fromList([0xff, 0xd8]);
      final result = await captureFromCamera(
        picker: () async => PickedPhoto(bytes: fixture, mimeType: 'image/heic'),
        clock: () => DateTime.utc(2026, 5, 15, 14, 31, 0),
      );
      expect(result!.mimeType, equals('image/heic'));
    });
  });
}

```
