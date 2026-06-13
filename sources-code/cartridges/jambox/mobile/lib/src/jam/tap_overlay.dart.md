---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/jam/tap_overlay.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.592083+00:00
---

# cartridges/jambox/mobile/lib/src/jam/tap_overlay.dart

```dart
import 'package:flutter/material.dart';
import '../theme/jam_colours.dart';

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
                            color: JamColours.brass.withOpacity(opacity),
                            width: 2,
                          ),
                          gradient: RadialGradient(
                            colors: [
                              JamColours.brass.withOpacity(opacity * 0.4),
                              JamColours.brass.withOpacity(0.0),
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
