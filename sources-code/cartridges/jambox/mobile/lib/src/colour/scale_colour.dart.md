---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/colour/scale_colour.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.596205+00:00
---

# cartridges/jambox/mobile/lib/src/colour/scale_colour.dart

```dart
// D-G.5 — Scale-colour Dart port.
//
// Port of apps/world-apps/jam-room/src/colour/scale-colour.ts.
//
// MUST produce byte-for-byte identical output to the TypeScript version
// for all pitch/scale/root/palette/labelMode combinations in the shared
// parity fixture at:
//   apps/world-apps/jam-room/src/colour/scale-colour-parity.json
//
// The parity test (test/scale_colour_parity_test.dart) asserts this.
//
// Algorithm is pure and deterministic: no random, no IO, no Flutter deps.

/// Supported colour palettes.
enum ScalePalette { boomwhacker, newton, scriabin }

/// Scale classification for a pitch within a scale context.
enum ScaleClass { root, inScale, modal, chromatic }

/// Supported scale types.
enum ScaleId {
  major,
  minor,
  pentatonic,
  pentatonicMinor,
  dorian,
  phrygian,
  lydian,
  mixolydian,
  locrian,
  blues,
  chromatic,
}

/// Label mode for pad annotation.
enum LabelMode { off, number, solfege, noteName, fingering }

/// Parsed colour specification for one pitch.
class ScaleColourSpec {
  /// Hue 0-360.
  final double hue;

  /// Saturation 0-1.
  final double saturation;

  /// Brightness 0-1.
  final double brightness;

  /// Optional border treatment.
  final String? border; // 'gold-ring' | 'modal-tick' | 'chromatic-edge' | null

  /// Optional label text.
  final String? label;

  const ScaleColourSpec({
    required this.hue,
    required this.saturation,
    required this.brightness,
    this.border,
    this.label,
  });

  @override
  bool operator ==(Object other) =>
      other is ScaleColourSpec &&
      other.hue == hue &&
      other.saturation == saturation &&
      other.brightness == brightness &&
      other.border == border &&
      other.label == label;

  @override
  int get hashCode =>
      Object.hash(hue, saturation, brightness, border, label);

  @override
  String toString() =>
      'ScaleColourSpec(hue=$hue, sat=$saturation, bri=$brightness, '
      'border=$border, label=$label)';
}

// ─── Scale interval definitions (semitones above root, 0-based) ───────────────

const Map<ScaleId, List<int>> _scaleIntervals = {
  ScaleId.major:            [0, 2, 4, 5, 7, 9, 11],
  ScaleId.minor:            [0, 2, 3, 5, 7, 8, 10],
  ScaleId.pentatonic:       [0, 2, 4, 7, 9],
  ScaleId.pentatonicMinor:  [0, 3, 5, 7, 10],
  ScaleId.dorian:           [0, 2, 3, 5, 7, 9, 10],
  ScaleId.phrygian:         [0, 1, 3, 5, 7, 8, 10],
  ScaleId.lydian:           [0, 2, 4, 6, 7, 9, 11],
  ScaleId.mixolydian:       [0, 2, 4, 5, 7, 9, 10],
  ScaleId.locrian:          [0, 1, 3, 5, 6, 8, 10],
  ScaleId.blues:            [0, 3, 5, 6, 7, 10],
  ScaleId.chromatic:        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
};

/// Modal characteristic note per scale (semitones above root).
const Map<ScaleId, int> _modalCharacteristic = {
  ScaleId.dorian:     9,
  ScaleId.phrygian:   1,
  ScaleId.lydian:     6,
  ScaleId.mixolydian: 10,
  ScaleId.locrian:    6,
};

// ─── classifyPitch ────────────────────────────────────────────────────────────

/// Classify a MIDI pitch relative to a scale and root.
///
/// Matches the TypeScript `classifyPitch` function exactly.
ScaleClass classifyPitch(int pitch, ScaleId scale, int root) {
  final pc = ((pitch % 12) + 12) % 12;
  final rel = ((pc - root) % 12 + 12) % 12;
  final intervals = _scaleIntervals[scale]!;

  if (rel == 0) return ScaleClass.root;
  if (!intervals.contains(rel)) return ScaleClass.chromatic;

  final modal = _modalCharacteristic[scale];
  if (modal != null && rel == modal) return ScaleClass.modal;

  return ScaleClass.inScale;
}

// ─── Palette hue tables ───────────────────────────────────────────────────────

const Map<int, double> _boomwhackerHue = {
  0:  0,
  1:  14,
  2:  33,
  3:  54,
  4:  70,
  5:  120,
  6:  150,
  7:  210,
  8:  240,
  9:  270,
  10: 300,
  11: 340,
};

const Map<int, double> _newtonHue = {
  0:  0,
  1:  15,
  2:  30,
  3:  52,
  4:  60,
  5:  120,
  6:  150,
  7:  210,
  8:  240,
  9:  265,
  10: 285,
  11: 300,
};

const Map<int, double> _scrabinaHue = {
  0:  0,
  1:  213,
  2:  213,
  3:  270,
  4:  60,
  5:  180,
  6:  0,
  7:  210,
  8:  330,
  9:  60,
  10: 30,
  11: 213,
};

double _paletteHue(int pitchClass, ScalePalette palette) {
  switch (palette) {
    case ScalePalette.boomwhacker:
      return _boomwhackerHue[pitchClass] ?? 0;
    case ScalePalette.newton:
      return _newtonHue[pitchClass] ?? 0;
    case ScalePalette.scriabin:
      return _scrabinaHue[pitchClass] ?? 0;
  }
}

// ─── Class modifiers ─────────────────────────────────────────────────────────

class _Mods {
  final double satMod;
  final double briMod;
  final String? border;
  const _Mods(this.satMod, this.briMod, this.border);
}

const Map<ScaleClass, _Mods> _classMods = {
  ScaleClass.root:      _Mods(0,     0,     'gold-ring'),
  ScaleClass.inScale:   _Mods(0,     0,     null),
  ScaleClass.modal:     _Mods(0.1,   0.05,  'modal-tick'),
  ScaleClass.chromatic: _Mods(-0.5,  -0.3,  'chromatic-edge'),
};

// ─── Label helpers ────────────────────────────────────────────────────────────

const List<String> _noteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
];
const List<String> _solfegeNames = [
  'Do', 'Di', 'Re', 'Ri', 'Mi', 'Fa', 'Fi', 'Sol', 'Si', 'La', 'Li', 'Ti'
];
const List<String> _solfegeInScale = [
  'Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Ti'
];

String _buildLabel(
  int pitch,
  int root,
  ScaleId scale,
  ScaleClass scaleClass,
  LabelMode labelMode,
) {
  if (labelMode == LabelMode.off) return '';

  final pc = ((pitch % 12) + 12) % 12;
  final octave = (pitch / 12).floor() - 1;

  if (labelMode == LabelMode.noteName) {
    return '${_noteNames[pc]}$octave';
  }

  if (labelMode == LabelMode.number) {
    if (scaleClass == ScaleClass.chromatic) return '';
    final rel = ((pc - root) % 12 + 12) % 12;
    final intervals = _scaleIntervals[scale]!;
    final degree = intervals.indexOf(rel);
    return degree >= 0 ? '${degree + 1}' : '';
  }

  if (labelMode == LabelMode.solfege) {
    final rel = ((pc - root) % 12 + 12) % 12;
    final intervals = _scaleIntervals[scale]!;
    final degree = intervals.indexOf(rel);
    if (degree >= 0 && degree < _solfegeInScale.length) {
      return _solfegeInScale[degree];
    }
    return _solfegeNames[pc];
  }

  if (labelMode == LabelMode.fingering) {
    final rel = ((pc - root) % 12 + 12) % 12;
    final intervals = _scaleIntervals[scale]!;
    final degree = intervals.indexOf(rel);
    if (degree < 0) return '';
    return '${(degree % 5) + 1}';
  }

  return '';
}

// ─── colourForPitch ───────────────────────────────────────────────────────────

/// Return a complete colour specification for a pitch in a given scale context.
///
/// Results MUST match the TypeScript [colourForPitch] function byte-for-byte
/// on the shared parity fixture.
ScaleColourSpec colourForPitch(
  int pitch,
  ScaleId scale,
  int root,
  ScalePalette palette,
  LabelMode labelMode,
) {
  final pc = ((pitch % 12) + 12) % 12;
  final scaleClass = classifyPitch(pitch, scale, root);
  final mods = _classMods[scaleClass]!;

  final hue = _paletteHue(pc, palette);

  final double baseSat;
  switch (palette) {
    case ScalePalette.boomwhacker:
      baseSat = 0.9;
    case ScalePalette.newton:
      baseSat = 0.85;
    case ScalePalette.scriabin:
      baseSat = 0.8;
  }
  final baseBri = scaleClass == ScaleClass.chromatic ? 0.3 : 0.85;

  final saturation = (baseSat + mods.satMod).clamp(0.0, 1.0);
  final brightness = (baseBri + mods.briMod).clamp(0.0, 1.0);

  final labelStr = _buildLabel(pitch, root, scale, scaleClass, labelMode);

  return ScaleColourSpec(
    hue: hue,
    saturation: saturation,
    brightness: brightness,
    border: mods.border,
    label: labelStr.isEmpty ? null : labelStr,
  );
}

// ─── JSON string helpers (for parity test fixture parsing) ───────────────────

/// Parse a ScaleId from its JSON string representation.
/// Matches the TypeScript enum keys.
ScaleId scaleIdFromJson(String s) {
  switch (s) {
    case 'major':           return ScaleId.major;
    case 'minor':           return ScaleId.minor;
    case 'pentatonic':      return ScaleId.pentatonic;
    case 'pentatonic-minor':return ScaleId.pentatonicMinor;
    case 'dorian':          return ScaleId.dorian;
    case 'phrygian':        return ScaleId.phrygian;
    case 'lydian':          return ScaleId.lydian;
    case 'mixolydian':      return ScaleId.mixolydian;
    case 'locrian':         return ScaleId.locrian;
    case 'blues':           return ScaleId.blues;
    case 'chromatic':       return ScaleId.chromatic;
    default:
      throw ArgumentError('Unknown scale: $s');
  }
}

/// Parse a ScalePalette from its JSON string representation.
ScalePalette paletteFromJson(String s) {
  switch (s) {
    case 'boomwhacker': return ScalePalette.boomwhacker;
    case 'newton':      return ScalePalette.newton;
    case 'scriabin':    return ScalePalette.scriabin;
    default:
      throw ArgumentError('Unknown palette: $s');
  }
}

/// Parse a LabelMode from its JSON string representation.
LabelMode labelModeFromJson(String s) {
  switch (s) {
    case 'off':       return LabelMode.off;
    case 'number':    return LabelMode.number;
    case 'solfege':   return LabelMode.solfege;
    case 'note-name': return LabelMode.noteName;
    case 'fingering': return LabelMode.fingering;
    default:
      throw ArgumentError('Unknown labelMode: $s');
  }
}

```
