---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/lib/scale-colour.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.622923+00:00
---

# cartridges/jambox/web/src/svelte/lib/scale-colour.ts

```ts
export type ScalePalette = 'boomwhacker' | 'newton' | 'scriabin' | 'mono';
export type ScaleClass = 'root' | 'in-scale' | 'modal' | 'chromatic';
export type LabelMode = 'off' | 'number' | 'solfege' | 'note-name';
export type ScaleId =
  | 'major' | 'minor' | 'pentatonic' | 'pentatonic-minor'
  | 'dorian' | 'phrygian' | 'lydian' | 'mixolydian' | 'locrian' | 'blues';

export interface ColourSpec {
  hue: number;
  saturation: number;
  brightness: number;
  border?: 'gold-ring' | 'modal-tick';
  label?: string;
  cls: ScaleClass;
  pc: number;
}

const SCALE_INTERVALS: Record<ScaleId, number[]> = {
  major:             [0, 2, 4, 5, 7, 9, 11],
  minor:             [0, 2, 3, 5, 7, 8, 10],
  pentatonic:        [0, 2, 4, 7, 9],
  'pentatonic-minor':[0, 3, 5, 7, 10],
  dorian:            [0, 2, 3, 5, 7, 9, 10],
  phrygian:          [0, 1, 3, 5, 7, 8, 10],
  lydian:            [0, 2, 4, 6, 7, 9, 11],
  mixolydian:        [0, 2, 4, 5, 7, 9, 10],
  locrian:           [0, 1, 3, 5, 6, 8, 10],
  blues:             [0, 3, 5, 6, 7, 10],
};

const MODAL_NOTE: Partial<Record<ScaleId, number>> = {
  dorian: 9, phrygian: 1, lydian: 6, mixolydian: 10, locrian: 6,
};

const PALETTES: Record<ScalePalette, number[]> = {
  boomwhacker: [0, 14, 30, 44, 56, 132, 168, 190, 208, 228, 258, 282],
  newton:      [0, 20, 38, 55, 75, 140, 180, 210, 240, 270, 300, 330],
  scriabin:    [0, 330, 55, 210, 80, 15, 200, 30, 288, 108, 335, 165],
  mono:        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
};

const SOLFEGE = ['Do','Di','Re','Ri','Mi','Fa','Fi','Sol','Si','La','Li','Ti'];
const NOTE_NAMES = ['C','C♯','D','D♯','E','F','F♯','G','G♯','A','A♯','B'];
const DEGREE_LABELS = ['1','♭2','2','♭3','3','4','♭5','5','♭6','6','♭7','7'];

export function classifyPitch(pitch: number, scale: ScaleId, root: number): ScaleClass {
  const pc = ((pitch % 12) + 12) % 12;
  const rel = ((pc - root) % 12 + 12) % 12;
  const intervals = SCALE_INTERVALS[scale] ?? SCALE_INTERVALS.major;
  if (rel === 0) return 'root';
  if (!intervals.includes(rel)) return 'chromatic';
  if (MODAL_NOTE[scale] === rel) return 'modal';
  return 'in-scale';
}

export function colourForPitch(
  pitch: number,
  scale: ScaleId,
  root: number,
  palette: ScalePalette,
  labelMode: LabelMode,
): ColourSpec {
  const pc = ((pitch % 12) + 12) % 12;
  const cls = classifyPitch(pitch, scale, root);
  const hueArr = PALETTES[palette];
  const hue = hueArr[pc];
  const isMono = palette === 'mono';

  let saturation: number, brightness: number, border: ColourSpec['border'];

  switch (cls) {
    case 'root':
      saturation = isMono ? 0 : 0.9; brightness = 0.85; border = 'gold-ring'; break;
    case 'in-scale':
      saturation = isMono ? 0 : 0.85; brightness = 0.7; break;
    case 'modal':
      saturation = isMono ? 0 : 0.95; brightness = 0.75; border = 'modal-tick'; break;
    case 'chromatic':
    default:
      saturation = isMono ? 0 : 0.3; brightness = 0.32; break;
  }
  if (isMono && cls !== 'chromatic') brightness = cls === 'root' ? 0.85 : 0.6;

  const rel = ((pc - root) % 12 + 12) % 12;
  let label: string | undefined;
  if (labelMode === 'number') label = DEGREE_LABELS[rel];
  else if (labelMode === 'solfege') label = SOLFEGE[rel];
  else if (labelMode === 'note-name') label = NOTE_NAMES[pc];

  return { hue, saturation, brightness, border, label, cls, pc };
}

export function specToCss(spec: ColourSpec): string {
  if (spec.saturation === 0) {
    const l = Math.round(spec.brightness * 60);
    return `hsl(0 0% ${l}%)`;
  }
  const s = Math.round(spec.saturation * 100);
  const l = Math.round(spec.brightness * 50);
  return `hsl(${spec.hue} ${s}% ${l}%)`;
}

export function isLightHue(hue: number): boolean {
  return hue >= 30 && hue <= 80;
}

export { NOTE_NAMES, SOLFEGE, SCALE_INTERVALS };

```
