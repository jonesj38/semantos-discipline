---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/jam/anchor_card.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.591117+00:00
---

# cartridges/jambox/mobile/lib/src/jam/anchor_card.dart

```dart
import 'package:flutter/material.dart';
import '../repl/phoenix_jam_channel.dart' show PhoenixJamState;
import '../theme/jam_colours.dart';
import 'loop_orb.dart';

class AnchorCard extends StatelessWidget {
  final bool playing;
  final bool recording;
  final double bpm;
  final String scene;
  final double beat;
  final List<bool> density;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleRec;
  final VoidCallback onCapture;
  final VoidCallback onSceneCycle;
  final ValueChanged<double> onBpmChange;
  final PhoenixJamState connectionState;

  const AnchorCard({
    super.key,
    required this.playing,
    required this.recording,
    required this.bpm,
    required this.scene,
    required this.beat,
    required this.density,
    required this.onTogglePlay,
    required this.onToggleRec,
    required this.onCapture,
    required this.onSceneCycle,
    required this.onBpmChange,
    this.connectionState = PhoenixJamState.disconnected,
  });

  @override
  Widget build(BuildContext context) {
    final bar = (beat / 16).floor() + 1;
    final step = (beat % 16).floor() + 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: JamColours.ink2,
        border: Border.all(color: JamColours.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          LoopOrb(size: 76, playing: playing, beat: beat % 16, density: density),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetaRow(scene: scene, bar: bar, step: step, onSceneCycle: onSceneCycle, connectionState: connectionState),
                const SizedBox(height: 6),
                _BpmRow(bpm: bpm, onBpmChange: onBpmChange),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _Controls(
            playing: playing,
            recording: recording,
            onTogglePlay: onTogglePlay,
            onToggleRec: onToggleRec,
            onCapture: onCapture,
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String scene;
  final int bar;
  final int step;
  final VoidCallback onSceneCycle;
  final PhoenixJamState connectionState;

  const _MetaRow({
    required this.scene,
    required this.bar,
    required this.step,
    required this.onSceneCycle,
    required this.connectionState,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onSceneCycle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: JamColours.ink3,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: JamColours.line2),
            ),
            child: Text(
              scene,
              style: const TextStyle(
                fontFamily: 'GeistMono',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: JamColours.brass,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$bar · $step',
          style: const TextStyle(
            fontFamily: 'GeistMono',
            fontSize: 11,
            color: JamColours.muted,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        _ConnectionDot(state: connectionState),
      ],
    );
  }
}

class _BpmRow extends StatelessWidget {
  final double bpm;
  final ValueChanged<double> onBpmChange;

  const _BpmRow({required this.bpm, required this.onBpmChange});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final next = (bpm + d.delta.dx * 0.5).clamp(40.0, 240.0);
        onBpmChange(next);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            bpm.round().toString(),
            style: const TextStyle(
              fontFamily: 'GeistMono',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: JamColours.paper,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'BPM',
            style: TextStyle(
              fontFamily: 'GeistMono',
              fontSize: 10,
              color: JamColours.muted,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final bool playing;
  final bool recording;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleRec;
  final VoidCallback onCapture;

  const _Controls({
    required this.playing,
    required this.recording,
    required this.onTogglePlay,
    required this.onToggleRec,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PillButton(
          label: playing ? '■' : '▶',
          color: JamColours.brassBright,
          onTap: onTogglePlay,
          wide: true,
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PillButton(
              label: '●',
              color: recording ? JamColours.record : JamColours.muted2,
              onTap: onToggleRec,
            ),
            const SizedBox(width: 5),
            _PillButton(
              label: '⬡',
              color: JamColours.muted2,
              onTap: onCapture,
            ),
          ],
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool wide;

  const _PillButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: wide ? 64 : 29,
        height: 29,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          border: Border.all(color: color.withOpacity(0.6)),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: color,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

// ── Connection status dot ─────────────────────────────────────────────────────

class _ConnectionDot extends StatefulWidget {
  final PhoenixJamState state;
  const _ConnectionDot({required this.state});

  @override
  State<_ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<_ConnectionDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _anim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(_ConnectionDot old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _updateAnimation();
  }

  void _updateAnimation() {
    final pulse = widget.state == PhoenixJamState.connecting ||
        widget.state == PhoenixJamState.reconnecting;
    if (pulse) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _dotColor => switch (widget.state) {
    PhoenixJamState.joined       => JamColours.live,
    PhoenixJamState.connecting   => JamColours.warn,
    PhoenixJamState.reconnecting => JamColours.warn,
    PhoenixJamState.disconnected => JamColours.muted2,
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: _dotColor.withOpacity(_anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

```
