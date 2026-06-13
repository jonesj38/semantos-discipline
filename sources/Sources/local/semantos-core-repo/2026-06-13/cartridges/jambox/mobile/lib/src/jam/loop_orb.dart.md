---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/jam/loop_orb.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.593295+00:00
---

# cartridges/jambox/mobile/lib/src/jam/loop_orb.dart

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/jam_colours.dart';

class LoopOrb extends StatelessWidget {
  final double size;
  final bool playing;
  final double beat; // fractional 0..16
  final List<bool> density; // 16 steps

  const LoopOrb({
    super.key,
    this.size = 100,
    this.playing = false,
    this.beat = 0,
    this.density = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _OrbPainter(playing: playing, beat: beat, density: density)),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final bool playing;
  final double beat;
  final List<bool> density;

  _OrbPainter({required this.playing, required this.beat, required this.density});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rOuter = size.width / 2 - 4;
    final rTrack = rOuter - 8;
    final rInner = rTrack - 10;

    // Glow bg
    final glow = RadialGradient(colors: [
      JamColours.brass.withOpacity(0.35),
      JamColours.brass.withOpacity(0.06),
      Colors.transparent,
    ], stops: const [0.0, 0.5, 1.0]);
    canvas.drawCircle(
      Offset(cx, cy), rOuter,
      Paint()..shader = glow.createShader(Rect.fromCircle(center: Offset(cx, cy), radius: rOuter)),
    );

    // Track ring
    canvas.drawCircle(
      Offset(cx, cy), rTrack,
      Paint()..color = JamColours.line..style = PaintingStyle.stroke..strokeWidth = 1,
    );

    // 16 step dots
    for (int i = 0; i < 16; i++) {
      final angle = (i / 16) * math.pi * 2 - math.pi / 2;
      final x = cx + rTrack * math.cos(angle);
      final y = cy + rTrack * math.sin(angle);
      final on = i < density.length && density[i];
      canvas.drawCircle(
        Offset(x, y),
        on ? 2.8 : 1.4,
        Paint()..color = on
            ? JamColours.brassBright.withOpacity(0.9)
            : JamColours.muted2.withOpacity(0.45),
      );
    }

    // Playhead
    if (playing) {
      final sweep = (beat / 16) * math.pi * 2 - math.pi / 2;
      final hx = cx + rTrack * math.cos(sweep);
      final hy = cy + rTrack * math.sin(sweep);
      canvas.drawCircle(
        Offset(hx, hy), 5,
        Paint()
          ..color = JamColours.brassBright
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(Offset(hx, hy), 5, Paint()..color = JamColours.brassBright);
    }

    // Inner pulse ring
    canvas.drawCircle(
      Offset(cx, cy), rInner * 0.65,
      Paint()
        ..color = JamColours.brass.withOpacity(playing ? 0.35 : 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.playing != playing || old.beat != beat || old.density != density;
}

```
