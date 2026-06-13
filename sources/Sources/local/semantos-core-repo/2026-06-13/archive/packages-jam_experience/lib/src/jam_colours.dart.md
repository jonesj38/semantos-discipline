---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/jam_colours.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.815759+00:00
---

# archive/packages-jam_experience/lib/src/jam_colours.dart

```dart
import 'package:flutter/material.dart';

/// Jambox palette — migrated from
/// `apps/world-apps/jam-room-mobile/lib/src/theme/jam_colours.dart`.
///
/// Lifted here so widgets that live in `jam_experience` reference a
/// palette this package owns (no dependency on the legacy
/// jam-room-mobile theme module). When the full surface migration
/// completes the legacy palette file is deleted.
abstract final class JamColours {
  // Base palette — deep space-ink, warm paper
  static const ink0 = Color(0xFF08090C);
  static const ink1 = Color(0xFF0D0F14);
  static const ink2 = Color(0xFF14171F);
  static const ink3 = Color(0xFF1C2029);
  static const ink4 = Color(0xFF262B37);
  static const line = Color(0xFF2A2F3C);
  static const line2 = Color(0xFF3A4051);
  static const paper = Color(0xFFEFEAD8);
  static const paper2 = Color(0xFFCDC8B8);
  static const muted = Color(0xFF8A8676);
  static const muted2 = Color(0xFF5E5B50);

  // Brass / brand accent
  static const brass = Color(0xFFD4A655);
  static const brassBright = Color(0xFFF1C876);
  static const brassDeep = Color(0xFF8A6B2E);

  // Functional
  static const record = Color(0xFFEF4D6A);
  static const live = Color(0xFF6CDC9A);
  static const warn = Color(0xFFFFB347);

  // Rack tones (Boomwhacker pc-2, pc-7, pc-11) — used by RackTabBar
  // + scale-channel colouring across the surface.
  static const toneRhythm = Color(0xFFE2821C); // orange  hsl(30 75% 55%)
  static const toneMelody = Color(0xFF4DC2D5); // cyan    hsl(190 70% 55%)
  static const toneBass = Color(0xFF9B5FCC); // purple  hsl(282 55% 58%)

  // Boomwhacker 12 pitch classes — indexed by `pitch % 12`. PadGrid
  // and any future scale-coloured surface read from this list.
  static const List<Color> boomwhacker = [
    Color(0xFFCC3333), // C  red
    Color(0xFFCC5522), // C#
    Color(0xFFCC7711), // D  orange
    Color(0xFFCC9922), // D#
    Color(0xFFBBBB11), // E  yellow
    Color(0xFF229944), // F  green
    Color(0xFF117766), // F#
    Color(0xFF1199BB), // G  cyan
    Color(0xFF2277BB), // G#
    Color(0xFF3355BB), // A  blue
    Color(0xFF6644BB), // A#
    Color(0xFF884499), // B  purple
  ];
}

```
