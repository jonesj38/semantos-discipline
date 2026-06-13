---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/midi/controller_detection.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.587203+00:00
---

# cartridges/jambox/mobile/lib/src/midi/controller_detection.dart

```dart
// D-G.6 — Controller detection: watches for new MIDI ports and applies
// the matching Phase C profile JSON.
//
// Profile JSON is UNCHANGED from the desktop format — no Dart-specific
// fields.  The same JSON blob that describes an MPK49 mapping on the
// desktop jam-room works on the Flutter shell.

import 'dart:async';
import 'dart:convert';

import 'midi_host.dart';

/// Built-in profile name → surface shape mapping.
/// Mirrors the Phase C built-in profiles from
/// apps/world-apps/jam-room/src/mappings/profiles/.
const Map<String, String> _knownDeviceProfiles = {
  'MPK49':      'mpk49',
  'MPK225':     'mpk49',   // Same profile family
  'Launchpad':  'launchpad',
  'Circuit':    'circuit',
  'Push':       'push',
  'MIDI Mix':   'grid-4x8',
};

/// A resolved controller profile: device info + the matching profile
/// surface shape (or null if no built-in profile matched).
class ControllerProfile {
  final MidiDeviceInfo device;

  /// Surface shape string (e.g. 'mpk49', 'launchpad') or null if
  /// no built-in profile matched and the user hasn't supplied a custom one.
  final String? surfaceShape;

  /// Decoded profile payload (JSON). Null until loaded.
  final Map<String, dynamic>? profilePayload;

  const ControllerProfile({
    required this.device,
    this.surfaceShape,
    this.profilePayload,
  });
}

/// Watches for new MIDI device connections and resolves them against the
/// Phase C profile registry.
///
/// Emits [ControllerProfile] when a device connects (or is already
/// connected at start).  Consumer (typically the routing layer) applies
/// the profile's input/output mappings to the room's dispatch pipeline.
class ControllerDetection {
  final MidiHost _host;
  final Map<String, Map<String, dynamic>> _customProfiles;

  final StreamController<ControllerProfile> _profileCtl =
      StreamController<ControllerProfile>.broadcast();

  StreamSubscription<MidiDeviceEvent>? _deviceSub;

  /// Stream of resolved controller profiles as devices connect.
  Stream<ControllerProfile> get profiles => _profileCtl.stream;

  ControllerDetection({
    required MidiHost host,
    /// Optional map of deviceName → profileJson string loaded from the
    /// room's cell-relay (same JSON format as desktop profiles).
    Map<String, String>? customProfilesJson,
  })  : _host = host,
        _customProfiles = _parseCustomProfiles(customProfilesJson ?? {});

  static Map<String, Map<String, dynamic>> _parseCustomProfiles(
    Map<String, String> raw,
  ) {
    final result = <String, Map<String, dynamic>>{};
    for (final entry in raw.entries) {
      try {
        final decoded = json.decode(entry.value) as Map<String, dynamic>;
        result[entry.key.toLowerCase()] = decoded;
      } catch (_) {
        // Ignore malformed profile JSON.
      }
    }
    return result;
  }

  /// Start watching for device events.
  void start() {
    _deviceSub = _host.deviceEvents.listen((ev) {
      if (ev.connected) {
        _resolveAndEmit(ev.device);
      }
    });
  }

  /// Stop watching and release the subscription.
  Future<void> stop() async {
    await _deviceSub?.cancel();
    _deviceSub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _profileCtl.close();
  }

  void _resolveAndEmit(MidiDeviceInfo device) {
    // 1. Check custom profiles (supplied by the room's cell-relay).
    final nameLower = device.name.toLowerCase();
    final custom = _customProfiles[nameLower];
    if (custom != null) {
      _profileCtl.add(ControllerProfile(
        device: device,
        surfaceShape: custom['surfaceShape'] as String?,
        profilePayload: custom,
      ));
      return;
    }

    // 2. Match against known built-in profiles by device name prefix.
    String? matchedShape;
    for (final known in _knownDeviceProfiles.entries) {
      if (device.name.contains(known.key)) {
        matchedShape = known.value;
        break;
      }
    }

    _profileCtl.add(ControllerProfile(
      device: device,
      surfaceShape: matchedShape,
      profilePayload: matchedShape != null
          ? {'surfaceShape': matchedShape, 'name': device.name}
          : null,
    ));
  }
}

```
