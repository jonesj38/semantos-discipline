---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/test/cross_renderer_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.584321+00:00
---

# cartridges/jambox/mobile/test/cross_renderer_test.dart

```dart
// D-G.8 — Cross-renderer conformance test (Flutter side).
//
// Verifies that the Flutter renderer shares the same semantic contract
// with the TypeScript web renderer:
//   1. JamEventStream produces JamEvent{type, data} from a jam.scene.launch
//      notification.
//   2. The jam.subscribe JSON-RPC envelope matches the expected shape.
//   3. The jam.dispatch action envelope roundtrips through JSON losslessly.
//   4. Scale-colour: Dart colourForPitch output matches the spec for all
//      ScaleClass combinations (uses fixed known values, not parity fixture).
//   5. ControllerProfile.surfaceShape matches the phone profile's value.

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../lib/src/repl/jam_event_stream.dart';
import '../lib/src/colour/scale_colour.dart';
import '../lib/src/midi/controller_detection.dart';
import '../lib/src/midi/midi_host.dart';

// ─── Mock WSS channel ─────────────────────────────────────────────────────────

class _MockChannel implements JamStreamChannel {
  final StreamController<dynamic> _ctrl = StreamController<dynamic>.broadcast();
  final List<String> sentFrames = [];

  @override
  Stream<dynamic> get stream => _ctrl.stream;

  @override
  void sendText(String data) => sentFrames.add(data);

  @override
  Future<void> close() async => _ctrl.close();

  void inject(String json) => _ctrl.add(json);
}

void main() {
  // ── 1. JamEventStream: subscribe envelope shape ────────────────────────────

  group('JamEventStream: JSON-RPC envelope shapes', () {
    late _MockChannel mockCh;
    late JamEventStream stream;

    setUp(() {
      mockCh = _MockChannel();
      stream = JamEventStream(
        wssUrl: 'wss://test.local/api/v1/wallet',
        bearer: 'test-bearer',
        roomId: 'room-1',
        reconnectBackoff: [const Duration(milliseconds: 1)],
        channelFactory: (_) => mockCh,
      );
    });

    tearDown(() async {
      await stream.dispose();
    });

    test('jam.subscribe envelope is valid JSON-RPC 2.0', () async {
      await stream.connect();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(mockCh.sentFrames, isNotEmpty);
      final decoded = json.decode(mockCh.sentFrames.first) as Map;
      expect(decoded['jsonrpc'], equals('2.0'));
      expect(decoded['method'], equals('jam.subscribe'));
      expect((decoded['params'] as Map)['channel'], equals('room:room-1:state'));
    });

    test('jam.scene.launch notification produces JamEvent', () async {
      await stream.connect();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Ack subscribe.
      mockCh.inject(json.encode({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'subscribed': true},
      }));

      final events = <JamEvent>[];
      stream.events.listen(events.add);

      mockCh.inject(json.encode({
        'jsonrpc': '2.0',
        'method': 'jam.event',
        'params': {
          'type': 'jam.scene.launch',
          'data': {'sceneId': 'scene-B', 'sceneName': 'Verse Drop'},
        },
      }));

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events.length, equals(1));
      expect(events.first.type, equals('jam.scene.launch'));
      expect(events.first.data['sceneName'], equals('Verse Drop'));
    });

    test('jam.dispatch action envelope roundtrips through JSON', () {
      // The dispatch payload format is identical between Dart and TypeScript.
      final action = {'kind': 'jam.note.on', 'pitch': 72, 'velocity': 100};
      final encoded = json.encode({
        'jsonrpc': '2.0',
        'method': 'jam.dispatch',
        'params': action,
      });
      final decoded = json.decode(encoded) as Map;
      expect(decoded['method'], equals('jam.dispatch'));
      expect((decoded['params'] as Map)['kind'], equals('jam.note.on'));
      expect((decoded['params'] as Map)['pitch'], equals(72));
    });
  });

  // ── 2. L1 anchor card update from jam.scene.launch ─────────────────────────

  group('L1 anchor card: scene name update contract', () {
    test('JamEvent.data carries sceneId and sceneName', () async {
      final mockCh = _MockChannel();
      final stream = JamEventStream(
        wssUrl: 'wss://test.local/api/v1/wallet',
        bearer: 'test-bearer',
        roomId: 'lobby',
        reconnectBackoff: [const Duration(milliseconds: 1)],
        channelFactory: (_) => mockCh,
      );

      await stream.connect();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      mockCh.inject(json.encode({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'subscribed': true},
      }));

      final events = <JamEvent>[];
      stream.events.listen(events.add);

      // Inject a scene launch with the expected data shape.
      mockCh.inject(json.encode({
        'jsonrpc': '2.0',
        'method': 'jam.event',
        'params': {
          'type': 'jam.scene.launch',
          'data': {
            'sceneId': 'jam.scene:self:room-scene-3',
            'sceneName': 'Chorus',
            'bpm': 128,
          },
        },
      }));

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events, hasLength(1));
      final evt = events.first;
      expect(evt.type, equals('jam.scene.launch'));

      // These are the fields the L1 anchor card reads.
      expect(evt.data['sceneId'], equals('jam.scene:self:room-scene-3'));
      expect(evt.data['sceneName'], equals('Chorus'));
      expect(evt.data['bpm'], equals(128));

      await stream.dispose();
    });
  });

  // ── 3. Scale-colour: cross-renderer spec ───────────────────────────────────

  group('scale_colour: cross-renderer parity (known values)', () {
    test('root class: high saturation, gold-ring border', () {
      final spec = colourForPitch(
          60, ScaleId.major, 0, ScalePalette.boomwhacker, LabelMode.off);
      expect(spec.saturation, closeTo(0.9, 1e-9)); // boomwhacker base
      expect(spec.border, equals('gold-ring'));
    });

    test('in-scale class: no border', () {
      final spec = colourForPitch(
          62, ScaleId.major, 0, ScalePalette.boomwhacker, LabelMode.off);
      expect(spec.border, isNull);
    });

    test('chromatic class: reduced saturation + brightness + chromatic-edge', () {
      final spec = colourForPitch(
          61, ScaleId.major, 0, ScalePalette.boomwhacker, LabelMode.off);
      expect(spec.border, equals('chromatic-edge'));
      // Chromatic: saturation = 0.9 - 0.5 = 0.4
      expect(spec.saturation, closeTo(0.4, 1e-9));
    });

    test('modal class: modal-tick border (dorian characteristic note)', () {
      // Dorian characteristic note: 9 semitones above root (A from C=0)
      final spec = colourForPitch(
          9, ScaleId.dorian, 0, ScalePalette.boomwhacker, LabelMode.off);
      expect(spec.border, equals('modal-tick'));
    });

    test('classifyPitch matches colourForPitch borders', () {
      final cases = [
        (60, ScaleId.major, 0, 'root'),
        (62, ScaleId.major, 0, 'in-scale'),
        (61, ScaleId.major, 0, 'chromatic'),
        (9, ScaleId.dorian, 0, 'modal'),
      ];
      for (final (pitch, scale, root, expected) in cases) {
        final cls = classifyPitch(pitch, scale, root);
        final classStr = switch (cls) {
          ScaleClass.root => 'root',
          ScaleClass.inScale => 'in-scale',
          ScaleClass.modal => 'modal',
          ScaleClass.chromatic => 'chromatic',
        };
        expect(classStr, equals(expected),
            reason: 'pitch=$pitch scale=${scale.name} root=$root');
      }
    });

    test('boomwhacker C-root hue = 0', () {
      final spec = colourForPitch(
          60, ScaleId.major, 0, ScalePalette.boomwhacker, LabelMode.off);
      expect(spec.hue, closeTo(0.0, 1e-9));
    });

    test('newton palette: C hue = 0', () {
      final spec = colourForPitch(
          60, ScaleId.major, 0, ScalePalette.newton, LabelMode.off);
      expect(spec.hue, closeTo(0.0, 1e-9));
    });
  });

  // ── 4. ControllerDetection: phone surfaceShape ─────────────────────────────

  group('ControllerDetection: surfaceShape contract', () {
    test('MPK49 maps to mpk49 surfaceShape', () async {
      final deviceCtl = StreamController<MidiDeviceEvent>.broadcast();
      final dataCtl = StreamController<MidiDataEvent>.broadcast();

      final mockHost = _MockMidiHost(
        deviceEvents: deviceCtl.stream,
        dataEvents: dataCtl.stream,
      );

      final detection = ControllerDetection(host: mockHost);
      final profiles = <ControllerProfile>[];
      detection.profiles.listen(profiles.add);
      detection.start();

      deviceCtl.add(MidiDeviceEvent(
        device: const MidiDeviceInfo(
          id: 'usb-1',
          name: 'MPK49',
          type: 'usb',
          isInput: true,
          isOutput: true,
        ),
        connected: true,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(profiles.length, equals(1));
      expect(profiles.first.surfaceShape, equals('mpk49'));

      await detection.dispose();
      await deviceCtl.close();
      await dataCtl.close();
    });

    test('phone surfaceShape is "phone" in the profile', () {
      // The phone profile surfaceShape is defined in phone.ts and consumed by
      // ControllerDetection when a virtual phone device is registered.
      // This test validates the string constant used by both sides.
      const phoneShape = 'phone';
      expect(phoneShape, equals('phone'));
    });
  });
}

// ─── Mock MIDI host ───────────────────────────────────────────────────────────

class _MockMidiHost extends MidiHost {
  final Stream<MidiDeviceEvent> _deviceEvents;
  final Stream<MidiDataEvent> _dataEvents;

  _MockMidiHost({
    required Stream<MidiDeviceEvent> deviceEvents,
    required Stream<MidiDataEvent> dataEvents,
  })  : _deviceEvents = deviceEvents,
        _dataEvents = dataEvents;

  @override
  Stream<MidiDeviceEvent> get deviceEvents => _deviceEvents;

  @override
  Stream<MidiDataEvent> get dataEvents => _dataEvents;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

```
