---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/theme/jam_colours.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.588832+00:00
---

# cartridges/jambox/mobile/lib/src/theme/jam_colours.dart

```dart
import 'package:flutter/material.dart';

abstract final class JamColours {
  // Base palette — deep space-ink, warm paper
  static const ink0  = Color(0xFF08090C);
  static const ink1  = Color(0xFF0D0F14);
  static const ink2  = Color(0xFF14171F);
  static const ink3  = Color(0xFF1C2029);
  static const ink4  = Color(0xFF262B37);
  static const line  = Color(0xFF2A2F3C);
  static const line2 = Color(0xFF3A4051);
  static const paper = Color(0xFFEFEAD8);
  static const paper2 = Color(0xFFCDC8B8);
  static const muted = Color(0xFF8A8676);
  static const muted2 = Color(0xFF5E5B50);

  // Brass / brand accent
  static const brass      = Color(0xFFD4A655);
  static const brassBright = Color(0xFFF1C876);
  static const brassDeep  = Color(0xFF8A6B2E);

  // Functional
  static const record = Color(0xFFEF4D6A);
  static const live   = Color(0xFF6CDC9A);
  static const warn   = Color(0xFFFFB347);

  // Rack tones (Boomwhacker pc-2, pc-7, pc-11)
  static const toneRhythm = Color(0xFFE2821C); // orange  hsl(30 75% 55%)
  static const toneMelody = Color(0xFF4DC2D5); // cyan    hsl(190 70% 55%)
  static const toneBass   = Color(0xFF9B5FCC); // purple  hsl(282 55% 58%)

  // Boomwhacker 12 pitch classes
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

  static MaterialColor buildSwatch(Color base) {
    final hsl = HSLColor.fromColor(base);
    return MaterialColor(base.value, {
      50:  hsl.withLightness(0.95).toColor(),
      100: hsl.withLightness(0.90).toColor(),
      200: hsl.withLightness(0.80).toColor(),
      300: hsl.withLightness(0.70).toColor(),
      400: hsl.withLightness(0.60).toColor(),
      500: base,
      600: hsl.withLightness(0.40).toColor(),
      700: hsl.withLightness(0.30).toColor(),
      800: hsl.withLightness(0.20).toColor(),
      900: hsl.withLightness(0.10).toColor(),
    });
  }

  static ThemeData buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      primarySwatch: buildSwatch(brass),
      scaffoldBackgroundColor: ink0,
      colorScheme: const ColorScheme.dark(
        primary: brass,
        secondary: brassBright,
        surface: ink2,
        onSurface: paper,
        outline: line,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: paper, fontFamily: 'GeistMono'),
        labelSmall: TextStyle(color: muted, fontFamily: 'GeistMono', letterSpacing: 1.4),
      ),
      dividerColor: line,
      cardColor: ink2,
    );
  }
}

```
