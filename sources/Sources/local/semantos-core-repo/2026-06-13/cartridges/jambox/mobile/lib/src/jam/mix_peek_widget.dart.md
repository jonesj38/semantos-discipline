---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/jam/mix_peek_widget.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.593576+00:00
---

# cartridges/jambox/mobile/lib/src/jam/mix_peek_widget.dart

```dart
// D-G.4 — Mix peek widget: inline mixer overview for the Bass tab.
//
// Shows 4 channel faders with live level meters driven by JamEventStream.

import 'package:flutter/material.dart';

import '../repl/jam_event_stream.dart';

/// Compact mixer peek for the L2 Bass tab (and potentially Melody).
class MixPeekWidget extends StatefulWidget {
  final JamEventStream eventStream;
  const MixPeekWidget({super.key, required this.eventStream});

  @override
  State<MixPeekWidget> createState() => _MixPeekWidgetState();
}

class _MixPeekWidgetState extends State<MixPeekWidget> {
  final List<double> _levels = [0.75, 0.6, 0.8, 0.5]; // drum/bass/lead/samp
  final List<double> _meters = [0.0, 0.0, 0.0, 0.0];
  final List<String> _labels = ['Drum', 'Bass', 'Lead', 'Samp'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (int i = 0; i < 4; i++)
            _ChannelStrip(
              label: _labels[i],
              level: _levels[i],
              meter: _meters[i],
              onLevelChanged: (v) => setState(() {
                _levels[i] = v;
                widget.eventStream.dispatch({
                  'kind': 'jam.rack.macro.set',
                  'rackIndex': i,
                  'macro': 0,
                  'value': v,
                });
              }),
            ),
        ],
      ),
    );
  }
}

class _ChannelStrip extends StatelessWidget {
  final String label;
  final double level;
  final double meter;
  final ValueChanged<double> onLevelChanged;

  const _ChannelStrip({
    required this.label,
    required this.level,
    required this.meter,
    required this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8B94A8),
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  activeTrackColor: const Color(0xFF65D6F5),
                  inactiveTrackColor: const Color(0xFF2A3142),
                  thumbColor: const Color(0xFFE6E9F2),
                  overlayColor: const Color(0xFF65D6F5).withOpacity(0.2),
                ),
                child: Slider(
                  value: level,
                  onChanged: onLevelChanged,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(level * 100).toInt()}',
            style: const TextStyle(
              color: Color(0xFF8B94A8),
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

```
