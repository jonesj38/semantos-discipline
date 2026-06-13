---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/loop_orb.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.816116+00:00
---

# archive/packages-jam_experience/lib/src/loop_orb.dart

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'jam_colours.dart';

/// Loop-orb widget — the circular transport visualiser at the centre
/// of the jam-room HUD.
///
/// Migrated from
/// `apps/world-apps/jam-room-mobile/lib/src/jam/loop_orb.dart` to live
/// inside the `jam_experience` package. First widget pulled across as
/// the migration pattern proof for §11.5 item 6 — the rest of the
/// jam-room-mobile UI (peer rail, pad grid, mix peek, note mode, anchor
/// card, support sheet, pairing screen) follows the same shape:
///   1. Move the file under `packages/jam_experience/lib/src/`.
///   2. Replace the `../theme/jam_colours.dart` import with
///      `jam_colours.dart` (palette migrated alongside).
///   3. Export from `lib/jam_experience.dart`.
///   4. Update any jam-room-mobile call sites to import from
///      `package:jam_experience/jam_experience.dart`.
///
/// No behavioural changes — this is a packaging migration, not a
/// rewrite. The widget renders identically to its origin.
class LoopOrb extends StatelessWidget {
  final double size;
  final bool playing;

  /// Fractional beat position in [0, 16). Drives the playhead position
  /// around the track ring.
  final double beat;

  /// 16-step density boolean array — which steps are "on" right now.
  /// Drives the dot brightness around the track.
  final List<bool> density;

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
      child: CustomPaint(
        painter: _OrbPainter(playing: playing, beat: beat, density: density),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final bool playing;
  final double beat;
  final List<bool> density;

  _OrbPainter({
    required this.playing,
    required this.beat,
    required this.density,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rOuter = size.width / 2 - 4;
    final rTrack = rOuter - 8;
    final rInner = rTrack - 10;

    // Glow bg
    final glow = RadialGradient(colors: [
      JamColours.brass.withValues(alpha: 0.35),
      JamColours.brass.withValues(alpha: 0.06),
      Colors.transparent,
    ], stops: const [0.0, 0.5, 1.0]);
    canvas.drawCircle(
      Offset(cx, cy),
      rOuter,
      Paint()
        ..shader = glow.createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: rOuter),
        ),
    );

    // Track ring
    canvas.drawCircle(
      Offset(cx, cy),
      rTrack,
      Paint()
        ..color = JamColours.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
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
        Paint()
          ..color = on
              ? JamColours.brassBright.withValues(alpha: 0.9)
              : JamColours.muted2.withValues(alpha: 0.45),
      );
    }

    // Playhead
    if (playing) {
      final sweep = (beat / 16) * math.pi * 2 - math.pi / 2;
      final hx = cx + rTrack * math.cos(sweep);
      final hy = cy + rTrack * math.sin(sweep);
      canvas.drawCircle(
        Offset(hx, hy),
        5,
        Paint()
          ..color = JamColours.brassBright
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        Offset(hx, hy),
        5,
        Paint()..color = JamColours.brassBright,
      );
    }

    // Inner pulse ring
    canvas.drawCircle(
      Offset(cx, cy),
      rInner * 0.65,
      Paint()
        ..color = JamColours.brass.withValues(alpha: playing ? 0.35 : 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.playing != playing ||
      old.beat != beat ||
      old.density != density;
}

```
