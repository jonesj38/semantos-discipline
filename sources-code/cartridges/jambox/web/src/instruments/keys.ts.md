---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/instruments/keys.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.603726+00:00
---

# cartridges/jambox/web/src/instruments/keys.ts

```ts
/**
 * Computer-keyboard musical keyboard with ADSR sustain and octave shift.
 *
 * Two rows: ZSXDCVGBHNJM (lower) + QWERTYUIOP (upper).
 * Keys map to scale degrees, transposed by `octave`. Hold = sustain;
 * release on keyup. `[` / `]` shift octave down/up.
 */

import { playNote } from '../audio';

export type Scale = 'pent' | 'major' | 'minor' | 'dorian' | 'phrygian';

const SCALE_SEMITONES: Record<Scale, number[]> = {
  pent:     [0, 3, 5, 7, 10],
  major:    [0, 2, 4, 5, 7, 9, 11],
  minor:    [0, 2, 3, 5, 7, 8, 10],
  dorian:   [0, 2, 3, 5, 7, 9, 10],
  phrygian: [0, 1, 3, 5, 7, 8, 10],
};

const LOWER = ['z','s','x','d','c','v','g','b','h','n','j','m'];
const UPPER = ['q','w','e','r','t','y','u','i','o','p'];

export interface KeysOptions {
  rootHz: number;
  scale: Scale;
  octave: number;
  trackName: string;
  onNoteOn?: (semitone: number, freq: number) => void;
}

export class Keys {
  private active = new Map<string, () => void>();
  private opts: KeysOptions;
  constructor(opts: KeysOptions) { this.opts = opts; }

  setScale(s: Scale) { this.opts.scale = s; }
  setRoot(hz: number) { this.opts.rootHz = hz; }
  setOctave(o: number) { this.opts.octave = Math.max(-2, Math.min(2, o)); }
  octave(): number { return this.opts.octave; }
  setOnNoteOn(cb: (semitone: number, freq: number) => void) {
    this.opts.onNoteOn = cb;
  }

  attach(): () => void {
    const onDown = (e: KeyboardEvent) => {
      if (e.repeat || e.metaKey || e.ctrlKey || e.altKey) return;
      const k = e.key.toLowerCase();
      if (k === '[') { this.setOctave(this.opts.octave - 1); return; }
      if (k === ']') { this.setOctave(this.opts.octave + 1); return; }
      const semi = this.semitoneFor(k);
      if (semi === null) return;
      if (this.active.has(k)) return;
      const freq = this.opts.rootHz * Math.pow(2, (semi + this.opts.octave * 12) / 12);
      const release = playNote(freq, 0.7, 4.0, 0, 'self', this.opts.trackName);
      this.active.set(k, release);
      this.opts.onNoteOn?.(semi, freq);
    };
    const onUp = (e: KeyboardEvent) => {
      const k = e.key.toLowerCase();
      const release = this.active.get(k);
      if (release) { release(); this.active.delete(k); }
    };
    window.addEventListener('keydown', onDown);
    window.addEventListener('keyup', onUp);
    return () => {
      window.removeEventListener('keydown', onDown);
      window.removeEventListener('keyup', onUp);
      for (const r of this.active.values()) r();
      this.active.clear();
    };
  }

  private semitoneFor(k: string): number | null {
    const scale = SCALE_SEMITONES[this.opts.scale];
    const lo = LOWER.indexOf(k);
    if (lo >= 0) return scale[lo % scale.length] + Math.floor(lo / scale.length) * 12;
    const up = UPPER.indexOf(k);
    if (up >= 0) return scale[up % scale.length] + (Math.floor(up / scale.length) + 1) * 12;
    return null;
  }
}

```
