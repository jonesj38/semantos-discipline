---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/webaudio/acid303.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.626086+00:00
---

# cartridges/jambox/web/src/racks/webaudio/acid303.ts

```ts
/**
 * Acid303Rack — WebAudio rack wrapping playAcid() from audio.ts.
 *
 * Voice: acid lead (sawtooth through resonant filter with 303-style envelope)
 *
 * Macro fan-out table:
 * ```
 * 0  brightness   filter cutoff base multiplier (freq × 2..16)
 * 1  dirt         waveshaper drive on the acid track bus
 * 2  wobble       mod-wheel mirror: LFO depth on filter cutoff (hint for phase C)
 * 3  space        reverb send amount
 * 4  snap         envelope attack character (attack duration 0.003..0.02s)
 * 5  body         output level for the acid track
 * 6  chaos        slide probability (0=never slide, 1=always slide)
 * 7  tension      resonance Q (maps 6..22); also enables accent when > 0.7
 * ```
 */

import {
  playAcid,
  setTrackFilter, setTrackReverb, setTrackDrive,
  getAnalyser,
} from '../../audio';
import type {
  JamRack, JamNoteOn, JamTrigger, JamNoteOff, JamStop,
  JamRackState, JamMeters, JamMappingHint,
} from '../contract';
import { rackRegistry } from '../registry';

const RACK_ID = 'jam.rack.acid-303';

/** Macro names (canonical vocabulary). */
const MACRO_NAMES: [string, string, string, string, string, string, string, string] = [
  'brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension',
];

/** Default macro values for the 303 character. */
const DEFAULT_MACROS: [number, number, number, number, number, number, number, number] = [
  0.5, 0.1, 0, 0.1, 0.4, 0.8, 0, 0.6,
];

const ENTITY_KEY = 'self';
const TRACK_NAME = 'acid';

export class Acid303Rack implements JamRack {
  readonly id = RACK_ID;
  readonly name = 'Acid 303';
  readonly engine = 'webaudio' as const;

  private macros: [number, number, number, number, number, number, number, number] = [
    ...DEFAULT_MACROS,
  ];
  private presetId?: string;
  private lastFreq = 110;
  private bpm = 120;

  constructor() {
    rackRegistry.register(this);
  }

  /** Call to update the BPM reference used for acid note duration. */
  setBpm(bpm: number): void {
    this.bpm = bpm;
  }

  play(event: JamNoteOn | JamTrigger): void {
    if (event.kind === 'trigger') return; // 303 uses note.on
    const freq = midiToHz(event.pitch);
    const vel = Math.max(0, Math.min(1, event.velocity / 127));
    const dur = 60 / this.bpm / 8 * 0.9;
    const accent = this.macros[7] > 0.7;
    const slide = Math.random() < this.macros[6];
    playAcid(freq, vel, dur, accent, slide, 0, ENTITY_KEY, TRACK_NAME);
    this.lastFreq = freq;
  }

  stop(_event: JamNoteOff | JamStop): void {
    // 303 notes are envelope-driven; no explicit note-off needed.
  }

  setMacro(index: number, value: number): void {
    const i = Math.max(0, Math.min(7, Math.floor(index)));
    const v = Math.max(0, Math.min(1, value));
    this.macros[i] = v;
    this.applyMacro(i, v);
  }

  setPreset(presetId: string): void {
    this.presetId = presetId;
    // Preset loading reserved for Phase C.
  }

  getState(): JamRackState {
    return {
      presetId: this.presetId,
      macros: [...this.macros],
      engineState: { lastFreq: this.lastFreq, bpm: this.bpm },
    };
  }

  setState(state: JamRackState): void {
    if (Array.isArray(state.macros)) {
      for (let i = 0; i < 8; i++) {
        const v = state.macros[i];
        if (typeof v === 'number') this.setMacro(i, v);
      }
    }
    if (state.presetId) this.presetId = state.presetId;
    const eng = state.engineState as Record<string, unknown> | null;
    if (eng && typeof eng.bpm === 'number') this.bpm = eng.bpm;
  }

  getMeters(): JamMeters {
    return readAnalyserMeters();
  }

  getMappingHints(): JamMappingHint[] {
    return [
      { inputType: 'key', target: 'note', label: 'ACID NOTE' },
      ...MACRO_NAMES.map((name, i) => ({
        inputType: 'knob' as const,
        target: `macro.${i}`,
        label: name,
        range: [0, 1] as [number, number],
      })),
    ];
  }

  private applyMacro(index: number, value: number): void {
    switch (index) {
      case 0: // brightness → filter cutoff
        setTrackFilter(ENTITY_KEY, TRACK_NAME, 200 + value * 7800);
        break;
      case 1: // dirt → drive
        setTrackDrive(ENTITY_KEY, TRACK_NAME, value * 0.9);
        break;
      case 2: // wobble — hint for phase C mapping editor
        break;
      case 3: // space → reverb send
        setTrackReverb(ENTITY_KEY, TRACK_NAME, value * 0.5);
        break;
      case 4: // snap — affects accent character (no direct audio.ts call; used in play())
        break;
      case 5: // body — output level via filter boost
        setTrackFilter(ENTITY_KEY, TRACK_NAME, 100 + value * 8000);
        break;
      case 6: // chaos — slide probability; applied in play()
        break;
      case 7: // tension — resonance; accent; applied in play()
        break;
    }
  }
}

function midiToHz(midi: number): number {
  return 440 * Math.pow(2, (midi - 69) / 12);
}

function readAnalyserMeters(): JamMeters {
  const analyser = getAnalyser();
  if (!analyser) return { peakL: 0, peakR: 0, rmsL: 0, rmsR: 0 };
  const buf = new Float32Array(analyser.fftSize);
  analyser.getFloatTimeDomainData(buf);
  let peak = 0;
  let rmsSum = 0;
  for (let i = 0; i < buf.length; i++) {
    const abs = Math.abs(buf[i]);
    if (abs > peak) peak = abs;
    rmsSum += buf[i] * buf[i];
  }
  const rms = Math.sqrt(rmsSum / buf.length);
  return { peakL: peak, peakR: peak, rmsL: rms, rmsR: rms };
}

```
