---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/sensors/gps_capture_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.913872+00:00
---

# archive/apps-semantos-monolith/test/sensors/gps_capture_test.dart

```dart
// D-O5m.followup-8 GPS + voice memo adapters — gps_capture unit tests.
//
// Drives `captureCurrentLocation` with a stub GeolocatorAdapter so
// the test runs under pure `dart test` (no Flutter SDK / geolocator
// platform binary gate).  Covers:
//   - happy path (service on + permission granted + position)
//   - service disabled → null
//   - permission denied (initial + requested) → null
//   - permission deniedForever → null
//   - transient error throw → null
//   - blob-bytes determinism: encode+decode round-trip + lex-key
//     ordering of canonical JSON

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:semantos/src/sensors/gps_capture.dart';

class _StubGeolocator implements GeolocatorAdapter {
  bool serviceEnabled;
  LocationPermission permState;
  LocationPermission? requestedPermState;
  GeolocatorPosition? position;
  Object? throwOnGet;

  int requestCalls = 0;

  _StubGeolocator({
    this.serviceEnabled = true,
    this.permState = LocationPermission.whileInUse,
    this.requestedPermState,
    this.position,
    this.throwOnGet,
  });

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permState;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCalls += 1;
    return requestedPermState ?? permState;
  }

  @override
  Future<GeolocatorPosition> getCurrentPosition() async {
    if (throwOnGet != null) throw throwOnGet!;
    return position ?? const GeolocatorPosition(latitude: 0, longitude: 0);
  }
}

void main() {
  group('captureCurrentLocation', () {
    test('happy path returns CapturedGpsPin with lat/lng/accuracy/timestamp',
        () async {
      final stub = _StubGeolocator(
        position: const GeolocatorPosition(
          latitude: -33.8688,
          longitude: 151.2093,
          accuracyMeters: 5.0,
        ),
      );
      final pin = await captureCurrentLocation(
        geolocator: stub,
        clock: () => DateTime.utc(2026, 5, 15, 14, 30, 0),
      );
      expect(pin, isNotNull);
      expect(pin!.latitude, equals(-33.8688));
      expect(pin.longitude, equals(151.2093));
      expect(pin.accuracyMeters, equals(5.0));
      expect(pin.capturedAt, equals('2026-05-15T14:30:00.000Z'));
    });

    test('returns null when location services are disabled', () async {
      final stub = _StubGeolocator(serviceEnabled: false);
      final pin = await captureCurrentLocation(geolocator: stub);
      expect(pin, isNull);
    });

    test('returns null when permission is denied even after request', () async {
      final stub = _StubGeolocator(
        permState: LocationPermission.denied,
        requestedPermState: LocationPermission.denied,
      );
      final pin = await captureCurrentLocation(geolocator: stub);
      expect(pin, isNull);
      expect(stub.requestCalls, equals(1));
    });

    test('returns null when permission is deniedForever', () async {
      final stub = _StubGeolocator(
        permState: LocationPermission.deniedForever,
      );
      final pin = await captureCurrentLocation(geolocator: stub);
      expect(pin, isNull);
      // Should not bother requesting when already deniedForever.
      expect(stub.requestCalls, equals(0));
    });

    test('returns null when getCurrentPosition throws transient', () async {
      final stub = _StubGeolocator(
        position: const GeolocatorPosition(latitude: 0, longitude: 0),
        throwOnGet: Exception('timed out'),
      );
      final pin = await captureCurrentLocation(geolocator: stub);
      expect(pin, isNull);
    });

    test('upgrades from denied → whileInUse via requestPermission', () async {
      final stub = _StubGeolocator(
        permState: LocationPermission.denied,
        requestedPermState: LocationPermission.whileInUse,
        position: const GeolocatorPosition(
          latitude: 1.0,
          longitude: 2.0,
          accuracyMeters: null,
        ),
      );
      final pin = await captureCurrentLocation(
        geolocator: stub,
        clock: () => DateTime.utc(2026, 5, 15, 14, 31, 0),
      );
      expect(pin, isNotNull);
      expect(pin!.latitude, equals(1.0));
      expect(pin.accuracyMeters, isNull);
      expect(stub.requestCalls, equals(1));
    });
  });

  group('gpsBlobBytes / decodeGpsBlob', () {
    test('encodes lex-ordered canonical JSON with all fields', () {
      final pin = const CapturedGpsPin(
        latitude: -33.8688,
        longitude: 151.2093,
        accuracyMeters: 5.0,
        capturedAt: '2026-05-15T14:30:00.000Z',
      );
      final bytes = gpsBlobBytes(pin);
      final s = utf8.decode(bytes);
      // Canonical-json key order: lex (accuracy_m, captured_at, lat, lng).
      expect(
        s,
        equals(
          '{"accuracy_m":5,"captured_at":"2026-05-15T14:30:00.000Z","lat":-33.8688,"lng":151.2093}',
        ),
      );
    });

    test('omits accuracy_m when null', () {
      final pin = const CapturedGpsPin(
        latitude: 1.5,
        longitude: 2.5,
        accuracyMeters: null,
        capturedAt: '2026-05-15T14:30:00.000Z',
      );
      final s = utf8.decode(gpsBlobBytes(pin));
      expect(
        s,
        equals(
          '{"captured_at":"2026-05-15T14:30:00.000Z","lat":1.5,"lng":2.5}',
        ),
      );
    });

    test('encode is deterministic — same input → same bytes', () {
      final pin = const CapturedGpsPin(
        latitude: -33.8688,
        longitude: 151.2093,
        accuracyMeters: 5.0,
        capturedAt: '2026-05-15T14:30:00.000Z',
      );
      final a = gpsBlobBytes(pin);
      final b = gpsBlobBytes(pin);
      expect(Uint8List.fromList(a), equals(Uint8List.fromList(b)));
    });

    test('decode round-trips through gpsBlobBytes', () {
      final pin = const CapturedGpsPin(
        latitude: -33.8688,
        longitude: 151.2093,
        accuracyMeters: 5.0,
        capturedAt: '2026-05-15T14:30:00.000Z',
      );
      final decoded = decodeGpsBlob(gpsBlobBytes(pin));
      expect(decoded, isNotNull);
      expect(decoded!.latitude, equals(pin.latitude));
      expect(decoded.longitude, equals(pin.longitude));
      expect(decoded.accuracyMeters, equals(pin.accuracyMeters));
      expect(decoded.capturedAt, equals(pin.capturedAt));
    });

    test('decode returns null on malformed bytes', () {
      expect(decodeGpsBlob(Uint8List.fromList(utf8.encode('not json'))), isNull);
      expect(
        decodeGpsBlob(Uint8List.fromList(utf8.encode('{"lat":"x"}'))),
        isNull,
      );
    });
  });
}

```
