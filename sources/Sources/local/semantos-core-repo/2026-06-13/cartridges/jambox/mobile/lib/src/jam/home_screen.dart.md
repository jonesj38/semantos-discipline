---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/jam/home_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.592699+00:00
---

# cartridges/jambox/mobile/lib/src/jam/home_screen.dart

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../identity/child_cert_store.dart';
import '../midi/controller_detection.dart';
import '../midi/midi_host.dart';
import '../repl/phoenix_jam_channel.dart';
import '../theme/jam_colours.dart';
import 'anchor_card.dart';
import 'pad_grid.dart';
import 'peer_rail.dart';
import 'rack_tab_bar.dart';
import 'support_sheet.dart';
import 'tap_overlay.dart';

// ── World endpoint ────────────────────────────────────────────────────────────

const _worldUrl = 'https://world.semantos.me';

// ── Starter kit ──────────────────────────────────────────────────────────────

final _starterKit = <String, List<int>>{
  'kick':  [1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0],
  'snare': [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
  'hat':   [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0],
  'clap':  [0,0,0,0, 0,0,0,0, 0,0,0,0, 1,0,0,0],
  'cb':    [0,0,0,0, 0,0,0,0, 0,0,0,1, 0,0,0,0],
  'tom':   List.filled(16, 0),
  'sub':   List.filled(16, 0),
  'perc':  [0,0,1,0, 0,0,0,1, 0,0,1,0, 0,1,0,0],
};

Map<String, List<int>> _emptyKit() => {
  for (final k in _starterKit.keys) k: List.filled(16, 0),
};

// ── HomeScreen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final ChildCertRecord record;
  final String roomId;
  final VoidCallback onUnpaired;

  const HomeScreen({
    super.key,
    required this.record,
    required this.roomId,
    required this.onUnpaired,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // ── identity / comms ──────────────────────────────────────────────────────
  late final PhoenixJamChannel _channel;
  late final MidiHost _midiHost;
  late final ControllerDetection _controllerDetection;

  StreamSubscription<PhoenixJamEvent>? _eventSub;
  StreamSubscription<PhoenixJamState>?  _stateSub;
  StreamSubscription<List<JamPeerInfo>>? _peerSub;

  // ── peer state ─────────────────────────────────────────────────────────────
  List<JamPeerInfo> _peers = [];

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _tapped    = false;
  bool _playing   = false;
  bool _recording = false;
  double _bpm     = 120;
  String _scene   = 'A';
  int _activeRack = 0; // 0=rhythm 1=melody 2=bass

  // ── drum / beat state ─────────────────────────────────────────────────────
  late Map<String, List<int>> _drumState;
  double _beat = 0;

  // ── transport ticker ──────────────────────────────────────────────────────
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  double _beatFrac = 0;
  int _lastStep = -1;

  // ── scale/key ─────────────────────────────────────────────────────────────
  String _scale = 'major';
  int _root = 0;
  bool _scaleLock = true;

  @override
  void initState() {
    super.initState();
    _drumState = _emptyKit();

    _channel = PhoenixJamChannel(
      worldUrl: _worldUrl,
      roomId:   widget.roomId,
      handle:   widget.record.label,
    );
    _midiHost = MidiHost();
    _controllerDetection = ControllerDetection(host: _midiHost);

    _wireChannel();
    _midiHost.start().then((_) => _controllerDetection.start());
  }

  // ── Phoenix channel ───────────────────────────────────────────────────────

  void _wireChannel() {
    _stateSub = _channel.stateStream.listen((_) => setState(() {}));
    _peerSub  = _channel.peersStream.listen((p) => setState(() => _peers = p));
    _eventSub = _channel.events.listen(_onChannelEvent);
    _channel.connect();
  }

  void _onChannelEvent(PhoenixJamEvent event) {
    switch (event.type) {
      // Late-join snapshot — merge every cell into local state.
      case 'snapshot':
        final cells = event.data['cells'];
        if (cells is! List) return;
        setState(() {
          for (final cell in cells) {
            if (cell is! Map) continue;
            _applyCell(Map<String, dynamic>.from(cell));
          }
        });

      // Live drum cell pushed by a peer.
      case 'drum':
        setState(() => _applyCell(event.data));

      // BPM broadcast.
      case 'bpm':
        final v = event.data['bpm'];
        if (v is num) setState(() => _bpm = v.toDouble());
    }
  }

  /// Merge one cell payload into local drum / BPM state.
  void _applyCell(Map<String, dynamic> cell) {
    final kind = cell['kind'] as String?;
    if (kind == 'drum') {
      final track = cell['track'] as String?;
      final steps = cell['steps'];
      if (track != null && steps is List) {
        _drumState = {
          ..._drumState,
          track: steps.map((s) => (s as num?)?.toInt() ?? 0).toList(),
        };
      }
    } else if (kind == 'bpm') {
      final v = cell['bpm'];
      if (v is num) _bpm = v.toDouble();
    }
  }

  // ── transport ─────────────────────────────────────────────────────────────

  void _startTransport() {
    _lastElapsed = Duration.zero;
    _ticker = createTicker(_onTick)..start();
  }

  void _stopTransport() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _lastElapsed = Duration.zero;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    final stepsPerSec = (_bpm / 60) * 4;
    _beatFrac = (_beatFrac + dt * stepsPerSec) % 16;

    final cur = _beatFrac.floor() % 16;
    if (cur != _lastStep) {
      _lastStep = cur;
      // TODO: trigger audio via platform channel for each active step
    }

    if (mounted) setState(() => _beat = _beatFrac);
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      if (_playing) _startTransport();
      else          _stopTransport();
    });
  }

  void _handleTap() {
    setState(() {
      _tapped    = true;
      _playing   = true;
      _drumState = { for (final e in _starterKit.entries) e.key: List<int>.from(e.value) };
      _beatFrac  = 0;
      _lastStep  = -1;
    });
    _startTransport();
    // Broadcast the starter kit to peers.
    for (final entry in _starterKit.entries) {
      _channel.commitCell({
        'kind':  'drum',
        'track': entry.key,
        'steps': entry.value,
      });
    }
  }

  // ── scene cycle ───────────────────────────────────────────────────────────

  void _cycleScene() {
    const scenes = ['A', 'B', 'C', 'D'];
    setState(() {
      _scene = scenes[(scenes.indexOf(_scene) + 1) % scenes.length];
    });
  }

  // ── derived mini-steps for rack tab bar ───────────────────────────────────

  List<int> get _rhythmLive {
    final kick  = _drumState['kick']  ?? [];
    final snare = _drumState['snare'] ?? [];
    final hat   = _drumState['hat']   ?? [];
    final clap  = _drumState['clap']  ?? [];
    return List.generate(16, (i) =>
      (i < kick.length  && kick[i]  != 0) ||
      (i < snare.length && snare[i] != 0) ||
      (i < hat.length   && hat[i]   != 0) ||
      (i < clap.length  && clap[i]  != 0) ? 1 : 0);
  }

  // ── peer rail helpers ─────────────────────────────────────────────────────

  static const _peerPalette = [
    JamColours.brass,
    JamColours.live,
    JamColours.record,
    JamColours.toneRhythm,
    JamColours.toneMelody,
    JamColours.toneBass,
  ];

  PeerInfo _toPeerInfo(JamPeerInfo p) {
    // Initials: up to 2 chars from handle.
    final h = p.handle.trim();
    final words = h.split(RegExp(r'[\s_-]+'));
    final initials = words.length >= 2
        ? '${words[0][0]}${words[1][0]}'.toUpperCase()
        : h.substring(0, h.length.clamp(0, 2)).toUpperCase();
    // Colour: hash of id into palette.
    final colorIdx = p.id.codeUnits.fold(0, (a, b) => a + b) % _peerPalette.length;
    // Drift: deterministic small phase offset.
    final drift = ((p.id.codeUnits.fold(0, (a, b) => a ^ b) % 100) / 100) - 0.5;
    return PeerInfo(
      id:       p.id,
      initials: initials,
      color:    _peerPalette[colorIdx],
      drift:    drift,
    );
  }

  // ── BSV capture ───────────────────────────────────────────────────────────

  void _handleCapture() {
    final roomUrl = '${_worldUrl.replaceFirst('https://', 'https://')}/room/${widget.roomId}';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CaptureSheet(
        roomId: widget.roomId,
        roomUrl: roomUrl,
        bpm: _bpm,
        scene: _scene,
        peerCount: _peers.length,
      ),
    );
  }

  // ── support sheet ─────────────────────────────────────────────────────────

  void _showSupportSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupportSheet(onEntry: (_) => Navigator.of(context).pop()),
    );
  }

  @override
  void dispose() {
    _stopTransport();
    _eventSub?.cancel();
    _stateSub?.cancel();
    _peerSub?.cancel();
    _channel.dispose();
    _controllerDetection.dispose();
    _midiHost.dispose();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rackIds = ['rhythm', 'melody', 'bass'];

    return Scaffold(
      backgroundColor: JamColours.ink0,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                AnchorCard(
                  playing:          _playing,
                  recording:        _recording,
                  bpm:              _bpm,
                  scene:            _scene,
                  beat:             _beat,
                  density:          _rhythmLive.map((v) => v != 0).toList(),
                  connectionState:  _channel.state,
                  onTogglePlay:     _togglePlay,
                  onToggleRec:      () => setState(() => _recording = !_recording),
                  onCapture:        _handleCapture,
                  onSceneCycle:     _cycleScene,
                  onBpmChange:      (v) {
                    setState(() => _bpm = v);
                    _channel.sendBpm(v);
                  },
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: PadGrid(
                          activeRack:    rackIds[_activeRack],
                          scale:         _scale,
                          root:          _root,
                          scaleLock:     _scaleLock,
                          beat:          _beat,
                          drumState:     _drumState,
                          setDrumState:  (s) {
                            // Find which track changed and commit it.
                            for (final track in s.keys) {
                              final prev = _drumState[track];
                              if (prev != null && s[track] != prev) {
                                _channel.commitCell({
                                  'kind':  'drum',
                                  'track': track,
                                  'steps': s[track],
                                });
                              }
                            }
                            setState(() => _drumState = s);
                          },
                        ),
                      ),
                      // Peer rail — only shown when there are peers.
                      if (_peers.isNotEmpty)
                        PeerRail(
                          bpm:   _bpm,
                          peers: _peers.map(_toPeerInfo).toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tap-to-start overlay
          if (!_tapped)
            Positioned.fill(
              child: TapOverlay(onTap: _handleTap),
            ),
        ],
      ),
      bottomNavigationBar: RackTabBar(
        activeIndex:  _activeRack,
        onTabSelected: (i) => setState(() => _activeRack = i),
        liveSteps: [
          _rhythmLive,
          List.filled(16, 0),
          List.filled(16, 0),
        ],
      ),
    );
  }
}

// ── Capture sheet ─────────────────────────────────────────────────────────────

class _CaptureSheet extends StatelessWidget {
  final String roomId;
  final String roomUrl;
  final double bpm;
  final String scene;
  final int peerCount;

  const _CaptureSheet({
    required this.roomId,
    required this.roomUrl,
    required this.bpm,
    required this.scene,
    required this.peerCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: JamColours.ink2,
        border: Border(top: BorderSide(color: JamColours.line)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: JamColours.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          const Text(
            '⌃ CAP · ANCHOR SESSION',
            style: TextStyle(
              fontFamily: 'GeistMono',
              fontSize: 11,
              color: JamColours.brassBright,
              letterSpacing: 0.16,
            ),
          ),
          const SizedBox(height: 16),

          // Session meta
          _MetaChip(label: 'room', value: roomId),
          const SizedBox(height: 6),
          Row(
            children: [
              _MetaChip(label: 'scene', value: scene),
              const SizedBox(width: 8),
              _MetaChip(label: 'bpm', value: bpm.round().toString()),
              const SizedBox(width: 8),
              _MetaChip(label: 'players', value: '$peerCount'),
            ],
          ),
          const SizedBox(height: 20),

          // Explanation
          const Text(
            'Anchoring this session to the BSV blockchain requires '
            'the desktop wallet (Metanet Desktop). Open this room on '
            'a desktop browser to sign and broadcast the anchor transaction.',
            style: TextStyle(
              fontFamily: 'GeistMono',
              fontSize: 10,
              color: JamColours.muted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),

          // Room URL
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: JamColours.ink3,
              border: Border.all(color: JamColours.line2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              roomUrl,
              style: const TextStyle(
                fontFamily: 'GeistMono',
                fontSize: 10,
                color: JamColours.brassBright,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Close button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: JamColours.ink3,
                  border: Border.all(color: JamColours.line2),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Close',
                  style: TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 11,
                    color: JamColours.paper2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;
  const _MetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: JamColours.ink3,
        border: Border.all(color: JamColours.line2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'GeistMono', fontSize: 10),
          children: [
            TextSpan(text: '$label ', style: const TextStyle(color: JamColours.muted)),
            TextSpan(text: value,    style: const TextStyle(color: JamColours.paper2)),
          ],
        ),
      ),
    );
  }
}

```
