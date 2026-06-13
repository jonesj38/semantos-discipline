---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/sensors/gps_capture.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.869918+00:00
---

# archive/apps-semantos-monolith/lib/src/sensors/gps_capture.dart

```dart
// D-O5m.followup-8 GPS + voice memo adapters — GPS sensor adapter.
//
// Mirrors the shape of `camera_capture.dart`: a tiny dependency-
// injectable surface that drives the platform geolocator behind a
// `GeolocatorAdapter` interface so the unit tests can swap in a stub
// returning a fixture position (lat/lng/accuracy) without pulling the
// `geolocator` package's platform channels into the `dart test`
// classpath.
//
// `captureCurrentLocation` returns a [CapturedGpsPin] (lat/lng +
// optional accuracy + ISO-8601 capture timestamp) or null on
// permission denied / location services off / transient error.  The
// helm converts the typed pin to a canonical-JSON blob via
// [gpsBlobBytes] and feeds the bytes + `kind: gps_pin` +
// `mimeType: application/json` into
// `attachment_builder.buildSignedAttachment` exactly the same way the
// camera flow feeds JPEG bytes + `kind: photo` + `mimeType: image/
// jpeg`.  No new cell types, no new brain endpoints — the substrate
// shipped in #315/#316 carries this kind end-to-end without changes.
//
// iOS Info.plist + Android AndroidManifest.xml updates
// (`NSLocationWhenInUseUsageDescription`, `android.permission.
// ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`) ride alongside
// this file.

import 'dart:convert';
import 'dart:typed_data';

import '../attachments/attachment_builder.dart';

/// Permission state surfaced by [GeolocatorAdapter.checkPermission] and
/// [GeolocatorAdapter.requestPermission].  Mirrors the geolocator
/// package's `LocationPermission` enum so the production wiring can
/// pass the values through verbatim.
enum LocationPermission {
  denied,
  deniedForever,
  whileInUse,
  always,
  unableToDetermine,
}

/// Position snapshot returned by [GeolocatorAdapter.getCurrentPosition].
/// Mirrors the geolocator package's `Position` shape but trims to the
/// fields the helm cares about so tests don't need the full plugin
/// surface.
class GeolocatorPosition {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  const GeolocatorPosition({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });
}

/// Lightweight abstraction over the platform geolocator that doesn't
/// pull in Flutter SDK / `geolocator` package types — keeps `dart
/// test` runs unblocked.  The production wiring (in `helm_app.dart`)
/// implements this via the `geolocator` package's static methods;
/// tests inject a stub that returns a known fixture (or simulates
/// permission denial / service-disabled / transient errors).
abstract class GeolocatorAdapter {
  /// True when the OS-level location service is on (e.g. iOS Settings
  /// > Privacy > Location Services).
  Future<bool> isLocationServiceEnabled();

  /// Read the app's current location permission state.  Does not
  /// prompt the user.
  Future<LocationPermission> checkPermission();

  /// Prompt the user for location permission (no-op + returns the
  /// existing value if already granted).
  Future<LocationPermission> requestPermission();

  /// Read a one-shot position.  Throws on transient errors (timeout,
  /// no signal); callers treat throws as null.
  Future<GeolocatorPosition> getCurrentPosition();
}

/// One captured GPS pin from the device geolocator.  Returned by
/// [captureCurrentLocation]; the caller (the helm screen) hands the
/// canonical-JSON bytes to `attachment_builder.buildSignedAttachment`
/// with `kind: gps_pin` and `mimeType: application/json`.
class CapturedGpsPin {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  /// ISO-8601 timestamp at capture time (device clock, UTC).
  final String capturedAt;

  const CapturedGpsPin({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyMeters,
  });
}

/// Drive the platform geolocator; return the captured lat/lng +
/// accuracy + timestamp, or null on permission denied / location
/// services off / transient error.
///
/// Callers that need to distinguish the failure modes can pre-check
/// via the adapter; this convenience surface collapses everything
/// into "got a pin" vs "didn't" so the helm can render a single
/// snackbar.
Future<CapturedGpsPin?> captureCurrentLocation({
  required GeolocatorAdapter geolocator,
  DateTime Function() clock = _systemClock,
}) async {
  try {
    final serviceEnabled = await geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var perm = await geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever ||
        perm == LocationPermission.unableToDetermine) {
      return null;
    }

    final pos = await geolocator.getCurrentPosition();
    final capturedAt = clock().toUtc().toIso8601String();
    return CapturedGpsPin(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyMeters: pos.accuracyMeters,
      capturedAt: capturedAt,
    );
  } catch (_) {
    return null;
  }
}

/// Encode a [CapturedGpsPin] as the canonical-JSON blob bytes the
/// brain stores under `<sha256>.bin`.  Field set + key order match
/// the spec: `{accuracy_m?, captured_at, lat, lng}` — lex order is
/// `accuracy_m, captured_at, lat, lng`.  `accuracy_m` is omitted
/// entirely when null so the canonical bytes are deterministic for
/// pins from devices that don't report accuracy.
Uint8List gpsBlobBytes(CapturedGpsPin pin) {
  final map = <String, dynamic>{
    'captured_at': pin.capturedAt,
    'lat': pin.latitude,
    'lng': pin.longitude,
  };
  if (pin.accuracyMeters != null) {
    map['accuracy_m'] = pin.accuracyMeters;
  }
  return encodeCanonicalJson(map);
}

/// Decode the canonical-JSON GPS blob back into a [CapturedGpsPin].
/// Used by the helm UI to render lat/lng captions on the attachments
/// list (and by the audio player / map link affordances).  Returns
/// null on malformed bytes — the renderer falls back to the icon-only
/// row in that case.
CapturedGpsPin? decodeGpsBlob(Uint8List bytes) {
  try {
    final raw = json.decode(utf8.decode(bytes));
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    final capturedAt = raw['captured_at'];
    if (lat is! num || lng is! num || capturedAt is! String) {
      return null;
    }
    final accRaw = raw['accuracy_m'];
    final acc = accRaw is num ? accRaw.toDouble() : null;
    return CapturedGpsPin(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      accuracyMeters: acc,
      capturedAt: capturedAt,
    );
  } catch (_) {
    return null;
  }
}

DateTime _systemClock() => DateTime.now();

```
