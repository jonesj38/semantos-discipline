---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/self/self_theme.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.869290+00:00
---

# archive/apps-semantos-monolith/lib/src/self/self_theme.dart

```dart
// T7.b v0.2.0 — SelfTheme: load the cartridge.json `theme.colors`
// palette and produce a ThemeData override for the SelfNode subtree.
//
// Per SQ3 + the cherry-pick in tick 20, the self cartridge's
// theme.colors (17 entries — growth/attention/ease/acceptance/resistance/
// qse-vacuum/gold/receive/release/connection/awareness/ego/soul/creation/
// energetics/organisation/completion) drive the personal-practice UI's
// emotional palette.  This module turns that JSON into a Material 3
// ColorScheme so the user feels the practice-specific tonality every
// time they tap into the Self tab.
//
// v0.1.0 inlined the palette as Dart constants here (rather than
// asset-loading the manifest JSON at runtime, which would require a
// pubspec asset declaration and a build-step).  When the runtime
// manifest loader lands the constants become a `fallbackColors`
// constant that's used if the load fails.

import 'package:flutter/material.dart';

/// The 17 canonical self-cartridge colors, sourced from
/// `cartridges/self/cartridge.json` theme.colors (cherry-picked from
/// the legacy configs/extensions/consciousness.json in tick 20).
class SelfPalette {
  // Practice phases (cool blues for inward movement).
  static const Color growth = Color(0xFF1A5276);
  static const Color attention = Color(0xFF2471A3);
  static const Color ease = Color(0xFF5DADE2);
  static const Color acceptance = Color(0xFF82E0AA);

  // Tension / resistance markers.
  static const Color resistance = Color(0xFFE74C3C);
  static const Color qseVacuum = Color(0xFF566573);

  // Completion / integration warmth.
  static const Color gold = Color(0xFFF4D03F);
  static const Color receive = Color(0xFFAED6F1);

  // Release / connection — primary action colors.
  static const Color release = Color(0xFF2C3E50);
  static const Color connection = Color(0xFF85C1E9);

  // Reflection / awareness — soft surfaces.
  static const Color awareness = Color(0xFFD5D8DC);
  static const Color ego = Color(0xFFF39C12);
  static const Color soul = Color(0xFFF9E79F);

  // Generative / creative.
  static const Color creation = Color(0xFF58D68D);
  static const Color energetics = Color(0xFF48C9B0);
  static const Color organisation = Color(0xFFA9DFBF);
  static const Color completion = Color(0xFFF7DC6F);

  const SelfPalette._();
}

/// Wraps a child widget in a Theme that uses the self palette.
/// Render at the SelfNode root so the rest of the app keeps its
/// neutral oddjobz theme.
class SelfThemeScope extends StatelessWidget {
  final Widget child;
  final Brightness brightness;

  const SelfThemeScope({
    super.key,
    required this.child,
    this.brightness = Brightness.light,
  });

  @override
  Widget build(BuildContext context) {
    final inherited = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: SelfPalette.release,
      brightness: brightness,
      primary: SelfPalette.release,
      secondary: SelfPalette.connection,
      tertiary: SelfPalette.gold,
      error: SelfPalette.resistance,
      surfaceTint: SelfPalette.connection,
    );
    return Theme(
      data: inherited.copyWith(
        colorScheme: scheme,
        // Keep typography/density inherited so the Self tab looks
        // continuous with the rest of the app — only colors shift.
        cardTheme: inherited.cardTheme.copyWith(
          surfaceTintColor: scheme.surfaceTint,
        ),
        progressIndicatorTheme: inherited.progressIndicatorTheme.copyWith(
          color: scheme.primary,
        ),
      ),
      child: child,
    );
  }
}

```
