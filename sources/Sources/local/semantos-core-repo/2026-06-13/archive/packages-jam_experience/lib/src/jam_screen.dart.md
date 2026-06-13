---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/jam_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.814372+00:00
---

# archive/packages-jam_experience/lib/src/jam_screen.dart

```dart
import 'package:flutter/material.dart';

import 'jam_colours.dart';
import 'loop_orb.dart';

/// Jambox experience root screen.
///
/// Renders the `LoopOrb` migrated from
/// `apps/world-apps/jam-room-mobile/lib/src/jam/loop_orb.dart` as
/// proof-of-pattern for §11.5 item 6. The remaining widgets (peer rail,
/// pad grid, mix peek, note mode, anchor card, support sheet, pairing
/// screen) follow the same migration shape; this screen will grow into
/// the full jam-room HUD as those land.
class JamboxScreen extends StatefulWidget {
  const JamboxScreen({super.key});

  @override
  State<JamboxScreen> createState() => _JamboxScreenState();
}

class _JamboxScreenState extends State<JamboxScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat;
  bool _playing = false;
  // 16-step pattern; alternating + accent for visual interest. In the
  // real surface this comes from the active jam.pattern cell.
  static const List<bool> _demoDensity = [
    true, false, false, true,
    false, true, false, false,
    true, false, true, false,
    false, true, false, true,
  ];

  @override
  void initState() {
    super.initState();
    _beat = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JamColours.ink0,
      appBar: AppBar(
        backgroundColor: JamColours.ink1,
        foregroundColor: JamColours.paper,
        title: const Text('Jam Room'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _beat,
              builder: (context, _) {
                return LoopOrb(
                  size: 240,
                  playing: _playing,
                  beat: _beat.value * 16,
                  density: _demoDensity,
                );
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
              label: Text(_playing ? 'Stop' : 'Play'),
              style: ElevatedButton.styleFrom(
                backgroundColor: JamColours.brass,
                foregroundColor: JamColours.ink0,
              ),
              onPressed: () => setState(() => _playing = !_playing),
            ),
            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'LoopOrb migrated from jam-room-mobile as proof-of-pattern.\n\n'
                'Remaining widgets (peer rail, pad grid, mix peek, note mode, '
                'anchor card, support sheet, pairing screen) follow the same '
                'shape — pure file move + palette import swap.',
                textAlign: TextAlign.center,
                style: TextStyle(color: JamColours.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

```
