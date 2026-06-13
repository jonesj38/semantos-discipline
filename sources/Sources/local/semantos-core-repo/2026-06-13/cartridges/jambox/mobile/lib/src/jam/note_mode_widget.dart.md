---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/jam/note_mode_widget.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.593867+00:00
---

# cartridges/jambox/mobile/lib/src/jam/note_mode_widget.dart

```dart
// D-G.5 — Note mode widget: scale-locked melodic pad grid.
//
// Uses colourForPitch() from lib/src/colour/scale_colour.dart to paint
// each pad with the Boomwhacker scale-channel colour.  The pad grid
// honours the active scale + root received via JamEventStream.

import 'package:flutter/material.dart';

import '../colour/scale_colour.dart';
import '../repl/jam_event_stream.dart';

/// Scale-locked melodic pad grid (L2 Melody tab content).
class NoteModeWidget extends StatefulWidget {
  final JamEventStream eventStream;

  const NoteModeWidget({super.key, required this.eventStream});

  @override
  State<NoteModeWidget> createState() => _NoteModeWidgetState();
}

class _NoteModeWidgetState extends State<NoteModeWidget> {
  ScaleId _scale = ScaleId.pentatonic;
  int _root = 0; // C
  ScalePalette _palette = ScalePalette.boomwhacker;
  LabelMode _labelMode = LabelMode.number;

  // 4×8 grid of MIDI notes — root octave 4 as the base
  static const int _cols = 8;
  static const int _rows = 4;
  static const int _baseNote = 60; // Middle C

  @override
  void initState() {
    super.initState();
    widget.eventStream.events.listen(_onEvent);
  }

  void _onEvent(JamEvent ev) {
    if (ev.type == 'jam.room.broadcast.statePatch') {
      final s = ev.data['scale'];
      final r = ev.data['root'];
      if (s is String) {
        try {
          final parsed = scaleIdFromJson(s);
          setState(() => _scale = parsed);
        } catch (_) {}
      }
      if (r is int) {
        setState(() => _root = r.clamp(0, 11));
      }
    }
  }

  int _pitchForCell(int col, int row) {
    // Layout: each row = one octave up; columns = scale degrees across the row.
    // For a pentatonic scale (5 notes) × 8 cols = loop pattern.
    final intervals = _intervalsForScale(_scale);
    final noteCount = intervals.length;
    final degree = col % noteCount;
    final octave = row + col ~/ noteCount;
    return _baseNote + (octave * 12) + intervals[degree] + (_root % 12);
  }

  List<int> _intervalsForScale(ScaleId scale) {
    // Re-use the same table as scale_colour.dart — hardcoded here for
    // independence from any private member.
    switch (scale) {
      case ScaleId.major:           return [0, 2, 4, 5, 7, 9, 11];
      case ScaleId.minor:           return [0, 2, 3, 5, 7, 8, 10];
      case ScaleId.pentatonic:      return [0, 2, 4, 7, 9];
      case ScaleId.pentatonicMinor: return [0, 3, 5, 7, 10];
      case ScaleId.dorian:          return [0, 2, 3, 5, 7, 9, 10];
      case ScaleId.phrygian:        return [0, 1, 3, 5, 7, 8, 10];
      case ScaleId.lydian:          return [0, 2, 4, 6, 7, 9, 11];
      case ScaleId.mixolydian:      return [0, 2, 4, 5, 7, 9, 10];
      case ScaleId.locrian:         return [0, 1, 3, 5, 6, 8, 10];
      case ScaleId.blues:           return [0, 3, 5, 6, 7, 10];
      case ScaleId.chromatic:       return [0,1,2,3,4,5,6,7,8,9,10,11];
    }
  }

  Color _toFlutterColor(ScaleColourSpec spec) {
    // HSB → Flutter Color via HSV conversion (Flutter's HSVColor is HSB).
    final hsv = HSVColor.fromAHSV(
      1.0,
      spec.hue,
      spec.saturation,
      spec.brightness,
    );
    return hsv.toColor();
  }

  void _onPadDown(int pitch) {
    // Dispatch jam.note.on to the room.
    widget.eventStream.dispatch({
      'kind': 'jam.note.on',
      'pitch': pitch,
      'velocity': 100,
      'rackId': 'jam.rack.poly-keys',
    });
  }

  void _onPadUp(int pitch) {
    widget.eventStream.dispatch({
      'kind': 'jam.note.off',
      'pitch': pitch,
      'rackId': 'jam.rack.poly-keys',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (int row = _rows - 1; row >= 0; row--)
            Expanded(
              child: Row(
                children: [
                  for (int col = 0; col < _cols; col++)
                    Expanded(
                      child: _PadCell(
                        pitch: _pitchForCell(col, row),
                        scale: _scale,
                        root: _root,
                        palette: _palette,
                        labelMode: _labelMode,
                        toColor: _toFlutterColor,
                        onDown: _onPadDown,
                        onUp: _onPadUp,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PadCell extends StatefulWidget {
  final int pitch;
  final ScaleId scale;
  final int root;
  final ScalePalette palette;
  final LabelMode labelMode;
  final Color Function(ScaleColourSpec) toColor;
  final void Function(int) onDown;
  final void Function(int) onUp;

  const _PadCell({
    required this.pitch,
    required this.scale,
    required this.root,
    required this.palette,
    required this.labelMode,
    required this.toColor,
    required this.onDown,
    required this.onUp,
  });

  @override
  State<_PadCell> createState() => _PadCellState();
}

class _PadCellState extends State<_PadCell> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final spec = colourForPitch(
      widget.pitch,
      widget.scale,
      widget.root,
      widget.palette,
      widget.labelMode,
    );
    final base = widget.toColor(spec);
    final bg = _pressed ? base.withOpacity(1.0) : base.withOpacity(0.8);

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        widget.onDown(widget.pitch);
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onUp(widget.pitch);
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        widget.onUp(widget.pitch);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: _borderFor(spec, _pressed),
          boxShadow: _pressed
              ? [BoxShadow(color: base.withOpacity(0.5), blurRadius: 8)]
              : null,
        ),
        child: spec.label != null && spec.label!.isNotEmpty
            ? Center(
                child: Text(
                  spec.label!,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              )
            : null,
      ),
    );
  }

  BoxBorder? _borderFor(ScaleColourSpec spec, bool pressed) {
    switch (spec.border) {
      case 'gold-ring':
        return Border.all(color: const Color(0xFFFFD166), width: 2);
      case 'modal-tick':
        return Border.all(color: Colors.white70, width: 1);
      case 'chromatic-edge':
        return Border.all(color: const Color(0xFF4A5070), width: 1);
      default:
        return pressed
            ? Border.all(color: Colors.white38, width: 1)
            : null;
    }
  }
}

```
