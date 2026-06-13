---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/scripts/gen-scale-colour-parity.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.597342+00:00
---

# cartridges/jambox/web/scripts/gen-scale-colour-parity.ts

```ts
/**
 * D-G.5 — Generate scale-colour-parity.json fixture.
 *
 * Runs colourForPitch for 100+ pitch/scale/root combinations and writes the
 * results as a portable JSON fixture at:
 *   apps/world-apps/jam-room/src/colour/scale-colour-parity.json
 *
 * The Flutter parity test (test/scale_colour_parity_test.dart) loads the same
 * JSON and asserts byte-for-byte identical output from the Dart port.
 *
 * Usage (from the jam-room package root):
 *   bun run scripts/gen-scale-colour-parity.ts
 */

import { colourForPitch, classifyPitch } from '../src/colour/scale-colour';
import type { ScaleId, ScalePalette } from '../src/colour/scale-colour';
import { writeFileSync } from 'fs';
import { join } from 'path';

const SCALES: ScaleId[] = [
  'major', 'minor', 'pentatonic', 'pentatonic-minor',
  'dorian', 'phrygian', 'lydian', 'mixolydian', 'locrian', 'blues', 'chromatic',
];
const PALETTES: ScalePalette[] = ['boomwhacker', 'newton', 'scriabin'];
const LABEL_MODES = ['off', 'number', 'solfege', 'note-name', 'fingering'] as const;
const ROOTS = [0, 2, 5, 7, 9]; // C, D, F, G, A

interface ParityEntry {
  pitch: number;
  scale: ScaleId;
  root: number;
  palette: ScalePalette;
  labelMode: typeof LABEL_MODES[number];
  scaleClass: string;
  hue: number;
  saturation: number;
  brightness: number;
  border: string | null;
  label: string | null;
}

const entries: ParityEntry[] = [];

// Generate a thorough matrix: all scales × all palettes × a root set ×
// representative pitches (one full octave + a few cross-octave checks).
const PITCHES = [
  // One full chromatic octave
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
  // Cross-octave spot checks
  12, 24, 36, 60, 72, 84, 96, 127,
  // Edge values
  -1, -12,
];

for (const scale of SCALES) {
  for (const root of ROOTS) {
    for (const pitch of PITCHES) {
      for (const palette of PALETTES) {
        for (const labelMode of LABEL_MODES) {
          const scaleClass = classifyPitch(pitch, scale, root);
          const spec = colourForPitch(pitch, scale, root, palette, labelMode);
          entries.push({
            pitch,
            scale,
            root,
            palette,
            labelMode,
            scaleClass,
            hue: spec.hue,
            saturation: spec.saturation,
            brightness: spec.brightness,
            border: spec.border ?? null,
            label: spec.label ?? null,
          });
        }
      }
    }
  }
}

const outPath = join(import.meta.dir, '..', 'src', 'colour', 'scale-colour-parity.json');
writeFileSync(outPath, JSON.stringify({ version: 1, entries }, null, 2));
console.log(`Wrote ${entries.length} parity entries to ${outPath}`);

```
