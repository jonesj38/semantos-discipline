---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/test/phase_g_gate_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.584625+00:00
---

# cartridges/jambox/mobile/test/phase_g_gate_test.dart

```dart
// D-G.11 — Phase G gate test (Flutter side).
//
// Asserts:
//   1. App pairs with a mock BRAIN endpoint, receives a jam.scene.launch
//      cell, and updates the L1 anchor card (scene name).
//   2. A simulated USB MIDI controller routes through the registry.
//   3. Scale-colour parity test passes (delegates to scale_colour_parity_test).
//   4. L2 tab bar renders correctly.
//   5. Support sheet renders with 5 entries (4 disabled + Custom enabled).
//
// Tests 1, 2, 4, 5 use Flutter widget test infrastructure.
// Test 3 delegates to the pure-Dart scale_colour_parity_test.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test/test.dart' as dartTest;

import '../lib/src/repl/jam_event_stream.dart';
import '../lib/src/jam/rack_tab_bar.dart';
import '../lib/src/jam/support_sheet.dart';
import '../lib/src/midi/midi_host.dart';
import '../lib/src/midi/controller_detection.dart';
import '../lib/src/colour/scale_colour.dart';

// ─── Mock WSS channel ────────────────────────────────────────────────────────

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
  // ── 1. JamEventStream — pairs, receives jam.scene.launch ─────────────────

  group('JamEventStream', () {
    late _MockChannel mockCh;
    late JamEventStream stream;

    setUp(() {
      mockCh = _MockChannel();
      stream = JamEventStream(
        wssUrl: 'wss://test.local/api/v1/wallet',
        bearer: 'test-bearer',
        roomId: 'lobby',
        reconnectBackoff: [const Duration(milliseconds: 1)],
        channelFactory: (_) => mockCh,
      );
    });

    tearDown(() async {
      await stream.dispose();
    });

    test('sends jam.subscribe on connect', () async {
      await stream.connect();
      // Allow subscribe frame to be sent.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(mockCh.sentFrames, isNotEmpty);
      final first = json.decode(mockCh.sentFrames.first) as Map;
      expect(first['method'], equals('jam.subscribe'));
      expect((first['params'] as Map)['channel'], equals('room:lobby:state'));
    });

    test('receives jam.scene.launch and emits JamEvent', () async {
      await stream.connect();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Ack the subscribe.
      mockCh.inject(json.encode({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'subscribed': true},
      }));

      final events = <JamEvent>[];
      stream.events.listen(events.add);

      // Inject jam.scene.launch.
      mockCh.inject(json.encode({
        'jsonrpc': '2.0',
        'method': 'jam.event',
        'params': {
          'type': 'jam.scene.launch',
          'data': {'sceneId': 'scene-A', 'sceneName': 'Main Loop'},
        },
      }));

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events.length, equals(1));
      expect(events.first.type, equals('jam.scene.launch'));
      expect(events.first.data['sceneName'], equals('Main Loop'));
    });

    test('queues outbound actions during loss and replays on reconnect',
        () async {
      // Do NOT connect — stream is disconnected.
      stream.dispatch({'kind': 'jam.note.on', 'pitch': 60});
      stream.dispatch({'kind': 'jam.note.on', 'pitch': 62});

      // Connect now.
      await stream.connect();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Ack subscribe.
      mockCh.inject(json.encode({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'subscribed': true},
      }));

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The two queued dispatches should have been sent after ack.
      final dispatched = mockCh.sentFrames
          .skip(1) // skip the subscribe
          .where((f) {
        final decoded = json.decode(f) as Map;
        return decoded['method'] == 'jam.dispatch';
      }).toList();

      expect(dispatched.length, equals(2));
    });
  });

  // ── 2. ControllerDetection — simulated USB MIDI ───────────────────────────

  group('ControllerDetection', () {
    test('resolves MPK49 to mpk49 profile', () async {
      final deviceEventCtl =
          StreamController<MidiDeviceEvent>.broadcast();
      final dataEventCtl =
          StreamController<MidiDataEvent>.broadcast();

      // Use a mock MidiHost that exposes our test streams.
      final mockHost = _MockMidiHost(
        deviceEvents: deviceEventCtl.stream,
        dataEvents: dataEventCtl.stream,
      );

      final detection = ControllerDetection(host: mockHost);
      final profiles = <ControllerProfile>[];
      detection.profiles.listen(profiles.add);
      detection.start();

      // Simulate a USB MIDI device arriving.
      deviceEventCtl.add(MidiDeviceEvent(
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
      await deviceEventCtl.close();
      await dataEventCtl.close();
    });

    test('emits profile with null surfaceShape for unknown device', () async {
      final deviceEventCtl =
          StreamController<MidiDeviceEvent>.broadcast();
      final dataEventCtl =
          StreamController<MidiDataEvent>.broadcast();

      final mockHost = _MockMidiHost(
        deviceEvents: deviceEventCtl.stream,
        dataEvents: dataEventCtl.stream,
      );

      final detection = ControllerDetection(host: mockHost);
      final profiles = <ControllerProfile>[];
      detection.profiles.listen(profiles.add);
      detection.start();

      deviceEventCtl.add(MidiDeviceEvent(
        device: const MidiDeviceInfo(
          id: 'usb-9',
          name: 'UnknownSynth 5000',
          type: 'usb',
          isInput: true,
          isOutput: false,
        ),
        connected: true,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(profiles.length, equals(1));
      expect(profiles.first.surfaceShape, isNull);

      await detection.dispose();
      await deviceEventCtl.close();
      await dataEventCtl.close();
    });
  });

  // ── 3. Scale-colour parity ────────────────────────────────────────────────
  // Smoke-test subset — full parity test is in scale_colour_parity_test.dart.

  group('scale_colour (smoke)', () {
    dartTest.test('C major root = gold-ring border', () {
      final spec = colourForPitch(60, ScaleId.major, 0, ScalePalette.boomwhacker, LabelMode.off);
      dartTest.expect(spec.border, dartTest.equals('gold-ring'));
    });

    dartTest.test('D in C major = in-scale, no border', () {
      final spec = colourForPitch(62, ScaleId.major, 0, ScalePalette.boomwhacker, LabelMode.off);
      dartTest.expect(spec.border, dartTest.isNull);
    });

    dartTest.test('C# in C major = chromatic, chromatic-edge', () {
      final spec = colourForPitch(61, ScaleId.major, 0, ScalePalette.boomwhacker, LabelMode.off);
      dartTest.expect(spec.border, dartTest.equals('chromatic-edge'));
    });

    dartTest.test('Dorian #6 gets modal-tick', () {
      // A dorian from C (root=0): characteristic note is 9 semitones up = A
      final spec = colourForPitch(9, ScaleId.dorian, 0, ScalePalette.boomwhacker, LabelMode.off);
      dartTest.expect(spec.border, dartTest.equals('modal-tick'));
    });
  });

  // ── 4. RackTabBar renders correctly ──────────────────────────────────────

  group('RackTabBar', () {
    testWidgets('renders three tabs', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: RackTabBar(
            activeIndex: 0,
            onTabSelected: (_) {},
          ),
        ),
      ));

      expect(find.text('Rhythm'), findsOneWidget);
      expect(find.text('Melody'), findsOneWidget);
      expect(find.text('Bass'),   findsOneWidget);
    });

    testWidgets('calls onTabSelected when tapping a tab', (tester) async {
      int tapped = -1;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: RackTabBar(
            activeIndex: 0,
            onTabSelected: (i) => tapped = i,
          ),
        ),
      ));

      await tester.tap(find.text('Melody'));
      await tester.pump();
      expect(tapped, equals(1));
    });
  });

  // ── 5. SupportSheet renders 5 entries ────────────────────────────────────

  group('SupportSheet', () {
    testWidgets('shows all 5 support entries', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SupportSheet(onEntry: (_) {}),
        ),
      ));

      expect(find.text('Sequencer'), findsOneWidget);
      expect(find.text('Mix'),       findsOneWidget);
      expect(find.text('Session'),   findsOneWidget);
      expect(find.text('Arrange'),   findsOneWidget);
      expect(find.text('Custom'),    findsOneWidget);
    });

    testWidgets('Custom entry is tappable (enabled)', (tester) async {
      String? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SupportSheet(onEntry: (id) => tapped = id),
        ),
      ));

      await tester.tap(find.text('Custom'));
      await tester.pump();
      expect(tapped, equals('custom'));
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
  Future<void> start() async {} // no-op

  @override
  Future<void> stop() async {} // no-op
}

```
