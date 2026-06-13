---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/sensors/camera_capture.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.870520+00:00
---

# archive/apps-semantos-monolith/lib/src/sensors/camera_capture.dart

```dart
// D-O5m.followup-8 capture+upload — Camera capture wrapper.
//
// Wraps `image_picker` behind a tiny dependency-injectable surface so
// the unit tests can swap in a fixture-image-returning function while
// production calls into the platform UIImagePickerController /
// MediaStore intent.
//
// Tests live in `test/sensors/camera_capture_test.dart` — they inject
// a `Future<XFile?> Function()` that returns a known-bytes fixture so
// the picker plugin doesn't actually need a Flutter SDK gate.
//
// iOS Info.plist + Android AndroidManifest.xml updates (`NSCamera-
// UsageDescription`, `android.permission.CAMERA`) ride alongside this
// file — see ios/Runner/Info.plist and android/app/src/main/Android-
// Manifest.xml.

import 'dart:typed_data';

/// Lightweight abstraction over the platform camera picker that doesn't
/// pull in Flutter SDK types — keeps `dart test` runs unblocked.  The
/// production wiring (in `helm_app.dart`) implements this via
/// `image_picker`'s `ImagePicker().pickImage(source: ImageSource.camera)`
/// call; tests inject a stub that returns a known fixture.
class PickedPhoto {
  /// Raw bytes — typically image/jpeg from the platform picker
  /// (image_picker re-encodes HEIC to JPEG by default).
  final Uint8List bytes;

  /// MIME type as reported by the picker.
  final String mimeType;

  const PickedPhoto({required this.bytes, required this.mimeType});
}

/// One captured photo from the device camera.  Returned by
/// [captureFromCamera]; the caller (the helm screen) hands this to
/// `attachment_builder.buildSignedAttachment` along with the visit
/// id + cert id.
class CapturedPhoto {
  final Uint8List bytes;
  final String mimeType;

  /// ISO-8601 timestamp at capture time (device clock, UTC).
  final String capturedAt;

  const CapturedPhoto({
    required this.bytes,
    required this.mimeType,
    required this.capturedAt,
  });
}

/// Pluggable picker — production wiring uses
/// `ImagePicker().pickImage(source: ImageSource.camera)` adapted via
/// [imagePickerCameraPicker] (the production seam); tests inject a
/// function returning a known fixture (or null on cancel).
typedef CameraPicker = Future<PickedPhoto?> Function();

/// Drive the platform camera; return the captured bytes + mime type
/// + timestamp, or null on cancel/error.  Errors from the picker are
/// caught + surfaced as null (the helm handles that as a "no photo
/// captured" state); the picker itself raises on permission denied
/// which the platform UI already handled.
Future<CapturedPhoto?> captureFromCamera({
  required CameraPicker picker,
  DateTime Function() clock = _systemClock,
}) async {
  PickedPhoto? file;
  try {
    file = await picker();
  } catch (_) {
    return null;
  }
  if (file == null) return null;

  final capturedAt = clock().toUtc().toIso8601String();
  return CapturedPhoto(
    bytes: file.bytes,
    mimeType: file.mimeType,
    capturedAt: capturedAt,
  );
}

DateTime _systemClock() => DateTime.now();

```
