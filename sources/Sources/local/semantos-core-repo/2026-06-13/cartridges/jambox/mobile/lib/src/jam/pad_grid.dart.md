---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/jam/pad_grid.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.592384+00:00
---

# cartridges/jambox/mobile/lib/src/jam/pad_grid.dart

```dart
import 'package:flutter/material.dart';
import '../theme/jam_colours.dart';

// ── Scale helpers ────────────────────────────────────────────────────────────

const Map<String, List<int>> _scaleIntervals = {
  'major':           [0, 2, 4, 5, 7, 9, 11],
  'minor':           [0, 2, 3, 5, 7, 8, 10],
  'dorian':          [0, 2, 3, 5, 7, 9, 10],
  'mixolydian':      [0, 2, 4, 5, 7, 9, 10],
  'pentatonic':      [0, 2, 4, 7, 9],
  'minor_pentatonic':[0, 3, 5, 7, 10],
  'blues':           [0, 3, 5, 6, 7, 10],
  'chromatic':       [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
  'whole_tone':      [0, 2, 4, 6, 8, 10],
  'diminished':      [0, 2, 3, 5, 6, 8, 9, 11],
};

const List<int> _scaleDegrees = [0, 2, 4, 5, 7, 9, 11, 12];

enum _ScaleClass { root, modal, chromatic }

_ScaleClass _classify(int pitch, String scale, int root) {
  final pc = (pitch - root) % 12;
  final intervals = _scaleIntervals[scale] ?? _scaleIntervals['major']!;
  if (pc == 0) return _ScaleClass.root;
  if (intervals.contains(pc)) return _ScaleClass.modal;
  return _ScaleClass.chromatic;
}

Color _colourForPitch(int pitch, String scale, int root) {
  final pc = pitch % 12;
  final cls = _classify(pitch, scale, root);
  if (cls == _ScaleClass.chromatic) return JamColours.ink3;
  return JamColours.boomwhacker[pc];
}

// ── Drum layout ──────────────────────────────────────────────────────────────

const _drumLayout = ['kick', 'snare', 'hat', 'clap', 'cb', 'tom', 'sub', 'perc'];
const _drumHues   = [30, 56, 190, 132, 282, 228, 0, 330];

// ── Pad model ────────────────────────────────────────────────────────────────

class _Pad {
  final Color bg;
  final Color border;
  final String? label;
  final bool dim;
  final bool locked;
  final bool lit;
  final bool isRoot;
  final VoidCallback onTap;

  const _Pad({
    required this.bg,
    required this.border,
    this.label,
    this.dim = false,
    this.locked = false,
    this.lit = false,
    this.isRoot = false,
    required this.onTap,
  });
}

// ── PadGrid widget ───────────────────────────────────────────────────────────

typedef DrumState = Map<String, List<int>>;

class PadGrid extends StatelessWidget {
  final String activeRack;
  final String scale;
  final int root;
  final bool scaleLock;
  final double beat;
  final DrumState drumState;
  final void Function(DrumState next) setDrumState;

  const PadGrid({
    super.key,
    required this.activeRack,
    required this.scale,
    required this.root,
    required this.scaleLock,
    required this.beat,
    required this.drumState,
    required this.setDrumState,
  });

  @override
  Widget build(BuildContext context) {
    final pads = _buildPads();
    final padSize = (MediaQuery.of(context).size.width - 24 - 7 * 6) / 8;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 1,
        ),
        itemCount: 64,
        itemBuilder: (_, i) => _PadTile(pad: pads[i], size: padSize),
      ),
    );
  }

  List<_Pad> _buildPads() {
    if (activeRack == 'rhythm') return _buildRhythm();
    if (activeRack == 'melody') return _buildNote('melody');
    return _buildBass();
  }

  List<_Pad> _buildRhythm() {
    final result = <_Pad>[];
    for (int r = 0; r < 8; r++) {
      final trk = _drumLayout[r];
      final hue = _drumHues[r];
      final tone = HSLColor.fromAHSL(1, hue.toDouble(), 0.75, 0.55).toColor();
      for (int c = 0; c < 8; c++) {
        final on = (drumState[trk]?[c] ?? 0) != 0;
        result.add(_Pad(
          bg: on ? tone : JamColours.ink3,
          border: on ? tone : JamColours.line,
          label: c == 0 ? trk.toUpperCase() : null,
          lit: on,
          onTap: () {
            final next = Map<String, List<int>>.from(drumState);
            next[trk] = List<int>.from(drumState[trk] ?? List.filled(16, 0));
            next[trk]![c] = on ? 0 : 1;
            setDrumState(next);
          },
        ));
      }
    }
    return result;
  }

  List<_Pad> _buildNote(String mode) {
    final result = <_Pad>[];
    final baseMidi = mode == 'melody' ? 60 : 36;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final pitch = baseMidi + (7 - r) * 12 + _scaleDegrees[c];
        final cls = _classify(pitch, scale, root);
        final locked = scaleLock && cls == _ScaleClass.chromatic;
        final bg = locked ? JamColours.ink3 : _colourForPitch(pitch, scale, root);
        result.add(_Pad(
          bg: bg,
          border: bg,
          dim: cls == _ScaleClass.chromatic && !locked,
          locked: locked,
          lit: cls == _ScaleClass.root,
          isRoot: cls == _ScaleClass.root,
          onTap: locked ? () {} : () {
            // Audio call goes here via platform channel in a real build
          },
        ));
      }
    }
    return result;
  }

  List<_Pad> _buildBass() {
    const perfLabels = ['SLIDE', 'ACCT', 'PROB', 'PROB', 'OCT+', 'OCT-'];
    final result = <_Pad>[];
    final notePads = _buildNote('bass');
    for (int r = 0; r < 8; r++) {
      if (r >= 6) {
        final rowIdx = r - 6;
        for (int c = 0; c < 8; c++) {
          result.add(notePads[rowIdx * 8 + c]);
        }
      } else {
        for (int c = 0; c < 8; c++) {
          result.add(_Pad(
            bg: JamColours.ink3,
            border: JamColours.line,
            label: c == 0 ? perfLabels[r] : null,
            dim: true,
            onTap: () {},
          ));
        }
      }
    }
    return result;
  }
}

// ── Single pad tile ──────────────────────────────────────────────────────────

class _PadTile extends StatelessWidget {
  final _Pad pad;
  final double size;

  const _PadTile({required this.pad, required this.size});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: pad.locked ? null : pad.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        decoration: BoxDecoration(
          color: pad.dim
              ? pad.bg.withOpacity(0.32)
              : pad.locked
                  ? pad.bg.withOpacity(0.12)
                  : pad.bg,
          border: Border.all(
            color: pad.lit
                ? pad.border
                : pad.border.withOpacity(0.5),
            width: pad.lit ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: pad.lit
              ? [BoxShadow(color: pad.bg.withOpacity(0.45), blurRadius: 10, spreadRadius: -2)]
              : null,
        ),
        child: Stack(
          children: [
            if (pad.isRoot)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: JamColours.brassBright, width: 1.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            if (pad.label != null)
              Center(
                child: Text(
                  pad.label!,
                  style: const TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

```
