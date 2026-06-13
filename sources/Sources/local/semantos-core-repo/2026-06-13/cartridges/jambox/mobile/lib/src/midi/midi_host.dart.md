---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/midi/midi_host.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.587509+00:00
---

# cartridges/jambox/mobile/lib/src/midi/midi_host.dart

```dart
// D-G.6 — MIDI host: wraps flutter_midi_command.
//
// Detects USB OTG (Android) and CoreMIDI (iOS) ports and emits
// MidiDeviceEvent notifications. The Phase C profile JSON is consumed
// unchanged from the desktop format (no Dart-specific fields).

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';

/// A detected MIDI device on the platform.
class MidiDeviceInfo {
  final String id;
  final String name;
  final String type; // 'usb' | 'ble' | 'coremidi' | 'virtual'
  final bool isInput;
  final bool isOutput;

  const MidiDeviceInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.isInput,
    required this.isOutput,
  });

  @override
  String toString() =>
      'MidiDeviceInfo(id=$id, name=$name, type=$type, '
      'in=$isInput, out=$isOutput)';
}

/// Lifecycle event for a MIDI device.
class MidiDeviceEvent {
  final MidiDeviceInfo device;
  final bool connected; // true = arrived, false = removed

  const MidiDeviceEvent({required this.device, required this.connected});
}

/// MIDI data received from a connected device.
class MidiDataEvent {
  final String deviceId;
  final List<int> bytes;
  final DateTime timestamp;

  MidiDataEvent({
    required this.deviceId,
    required this.bytes,
  }) : timestamp = DateTime.now();
}

/// Wraps flutter_midi_command to provide device-connection events and
/// incoming MIDI data as typed streams.
///
/// Usage:
///   final host = MidiHost();
///   await host.start();
///   host.deviceEvents.listen(...);
///   host.dataEvents.listen(...);
///   await host.stop();
class MidiHost {
  final MidiCommand _midi = MidiCommand();

  final StreamController<MidiDeviceEvent> _deviceCtl =
      StreamController<MidiDeviceEvent>.broadcast();
  final StreamController<MidiDataEvent> _dataCtl =
      StreamController<MidiDataEvent>.broadcast();

  StreamSubscription<MidiPacket>? _dataSub;
  StreamSubscription<String>? _setupSub;

  /// Stream of device connect/disconnect events.
  Stream<MidiDeviceEvent> get deviceEvents => _deviceCtl.stream;

  /// Stream of raw MIDI data packets from all connected devices.
  Stream<MidiDataEvent> get dataEvents => _dataCtl.stream;

  /// Start the MIDI host: scan for existing devices, subscribe to
  /// hot-plug events and incoming data.
  Future<void> start() async {
    // Subscribe to setup change events (device connect/disconnect).
    _setupSub = _midi.onMidiSetupChanged?.listen((_) async {
      await _refreshDevices();
    });

    // Subscribe to incoming MIDI packets.
    _dataSub = _midi.onMidiDataReceived?.listen((packet) {
      _dataCtl.add(MidiDataEvent(
        deviceId: packet.device.id,
        bytes: packet.data,
      ));
    });

    // Scan existing devices.
    await _refreshDevices();
  }

  /// Stop the MIDI host and release all resources.
  Future<void> stop() async {
    await _setupSub?.cancel();
    await _dataSub?.cancel();
    _setupSub = null;
    _dataSub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _deviceCtl.close();
    await _dataCtl.close();
  }

  /// Send raw bytes to a specific output device.
  void send(String deviceId, List<int> bytes) {
    try {
      _midi.sendData(
        Uint8List.fromList(bytes),
        deviceId: deviceId,
      );
    } catch (_) {
      // Device may have disconnected; ignore.
    }
  }

  // ─── Internals ────────────────────────────────────────────────────────────

  Future<void> _refreshDevices() async {
    try {
      final devices = await _midi.devices ?? [];
      for (final d in devices) {
        final info = _deviceInfoFrom(d);
        _deviceCtl.add(MidiDeviceEvent(device: info, connected: true));
      }
    } catch (_) {
      // flutter_midi_command may not be available in test environments.
    }
  }

  MidiDeviceInfo _deviceInfoFrom(MidiDevice d) {
    final type = _inferType(d.type);
    return MidiDeviceInfo(
      id: d.id,
      name: d.name,
      type: type,
      isInput: d.inputPorts.isNotEmpty,
      isOutput: d.outputPorts.isNotEmpty,
    );
  }

  String _inferType(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'ble':
      case 'bluetooth':
        return 'ble';
      case 'usb':
        return 'usb';
      case 'network':
        return 'coremidi';
      default:
        return 'virtual';
    }
  }
}

```
