---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/tap_overlay.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.814098+00:00
---

# archive/packages-jam_experience/lib/src/tap_overlay.dart

```dart
import 'package:flutter/material.dart';

import 'jam_colours.dart';

/// TapOverlay — full-screen "TAP TO START" splash used to bootstrap the
/// audio context after a user gesture. Migrated from
/// `apps/world-apps/jam-room-mobile/lib/src/jam/tap_overlay.dart`.
class TapOverlay extends StatefulWidget {
  final VoidCallback onTap;

  const TapOverlay({super.key, required this.onTap});

  @override
  State<TapOverlay> createState() => _TapOverlayState();
}

class _TapOverlayState extends State<TapOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  bool _fading = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_fading) return;
    setState(() => _fading = true);
    Future.delayed(const Duration(milliseconds: 400), widget.onTap);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _fading ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: _handleTap,
        child: Container(
          color: JamColours.ink0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final scale = 0.85 + _pulse.value * 0.15;
                    final opacity = 0.3 + _pulse.value * 0.35;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: JamColours.brass.withValues(alpha: opacity),
                            width: 2,
                          ),
                          gradient: RadialGradient(
                            colors: [
                              JamColours.brass.withValues(alpha: opacity * 0.4),
                              JamColours.brass.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.music_note_rounded,
                          size: 40,
                          color: JamColours.brassBright,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                const Text(
                  'TAP TO START',
                  style: TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: JamColours.muted,
                    letterSpacing: 3.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

```
