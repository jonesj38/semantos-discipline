---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/webaudio/bassMono.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.627302+00:00
---

# cartridges/jambox/web/src/racks/webaudio/bassMono.ts

```ts
/**
 * BassMonoRack — WebAudio rack wrapping the bass synth path in audio.ts.
 *
 * Voice: monophonic bass (routed through the 'bass' track bus)
 * Uses playMelodic() with the active synth voice for the bass track.
 *
 * Macro fan-out table:
 * ```
 * 0  brightness   filter cutoff (100..8000 Hz) on the bass track bus
 * 1  dirt         drive + bitcrush amount on bass track
 * 2  wobble       LFO depth hint — routes to filter mod (phase C mapping)
 * 3  space        reverb send amount
 * 4  snap         attack envelope shaping (shorter attack = snappier)
 * 5  body         low-shelf boost / sub-octave mix via track volume
 * 6  chaos        random semitone drift (hint; actual implementation in sequencer)
 * 7  tension      sidechain amount from kick; filter resonance
 * ```
 */

import {
  playNote, playFmNote, playSquareNote, playPulseNote,
  playSubNote, playEpianoNote, playPadNote,
  setTrackFilter, setTrackReverb, setTrackDrive, setTrackBitcrush,
  setTrackSidechain,
  getAnalyser,
} from '../../audio';
import type {
  JamRack, JamNoteOn, JamTrigger, JamNoteOff, JamStop,
  JamRackState, JamMeters, JamMappingHint,
} from '../contract';
import { rackRegistry } from '../registry';
import type { SynthVoice } from '../../sequencer';

const RACK_ID = 'jam.rack.bass-mono';

/** Macro names (canonical vocabulary). */
const MACRO_NAMES: [string, string, string, string, string, string, string, string] = [
  'brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension',
];

/** Default macro values for a classic deep bass sound. */
const DEFAULT_MACROS: [number, number, number, number, number, number, number, number] = [
  0.35, 0.1, 0, 0.05, 0.4, 0.7, 0, 0.6,
];

const ENTITY_KEY = 'self';
const TRACK_NAME = 'bass';

export class BassMonoRack implements JamRack {
  readonly id = RACK_ID;
  readonly name = 'Bass Mono';
  readonly engine = 'webaudio' as const;

  private macros: [number, number, number, number, number, number, number, number] = [
    ...DEFAULT_MACROS,
  ];
  private presetId?: string;
  private voice: SynthVoice = 'saw';
  private bpm = 120;
  private activeNotes = new Set<number>();

  constructor() {
    rackRegistry.register(this);
  }

  /** Select the synth voice for the bass track. */
  setVoice(v: SynthVoice): void {
    this.voice = v;
  }

  setBpm(bpm: number): void {
    this.bpm = bpm;
  }

  play(event: JamNoteOn | JamTrigger): void {
    if (event.kind === 'trigger') return;
    const freq = midiToHz(event.pitch);
    const vel = Math.max(0, Math.min(1, event.velocity / 127));
    const dur = 60 / this.bpm / 4 * 0.9;
    playMelodicVoice(this.voice, freq, vel, dur, 0, ENTITY_KEY, TRACK_NAME);
    this.activeNotes.add(event.pitch);
  }

  stop(event: JamNoteOff | JamStop): void {
    if (event.kind === 'note.off') {
      this.activeNotes.delete(event.pitch);
    } else {
      // Panic: clear all active notes (WebAudio self-terminates via envelopes)
      this.activeNotes.clear();
    }
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
    // Common presets: 'deep-sub', 'bouncy-saw', 'moog-square', 'fm-bass'.
    if (presetId === 'deep-sub') this.setVoice('sub');
    else if (presetId === 'moog-square') this.setVoice('square');
    else if (presetId === 'fm-bass') this.setVoice('fm');
    else this.setVoice('saw');
  }

  getState(): JamRackState {
    return {
      presetId: this.presetId,
      macros: [...this.macros],
      engineState: { voice: this.voice, bpm: this.bpm },
    };
  }

  setState(state: JamRackState): void {
    if (Array.isArray(state.macros)) {
      for (let i = 0; i < 8; i++) {
        const v = state.macros[i];
        if (typeof v === 'number') this.setMacro(i, v);
      }
    }
    if (state.presetId) this.setPreset(state.presetId);
    const eng = state.engineState as Record<string, unknown> | null;
    if (eng && typeof eng.bpm === 'number') this.bpm = eng.bpm;
    if (eng && typeof eng.voice === 'string') this.voice = eng.voice as SynthVoice;
  }

  getMeters(): JamMeters {
    return readAnalyserMeters();
  }

  getMappingHints(): JamMappingHint[] {
    return [
      { inputType: 'key', target: 'note', label: 'BASS NOTE' },
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
        setTrackFilter(ENTITY_KEY, TRACK_NAME, 80 + value * 7920);
        break;
      case 1: // dirt → drive + bitcrush
        setTrackDrive(ENTITY_KEY, TRACK_NAME, value * 0.85);
        // bitcrush: 64 (clean) → 2 (full crush) as dirt increases
        setTrackBitcrush(ENTITY_KEY, TRACK_NAME, Math.max(2, Math.round(64 * (1 - value * 0.9))));
        break;
      case 2: // wobble — mapping hint only
        break;
      case 3: // space → reverb
        setTrackReverb(ENTITY_KEY, TRACK_NAME, value * 0.4);
        break;
      case 4: // snap — affects attack; no direct call, used in play() duration
        break;
      case 5: // body — filter boost for sub presence
        setTrackFilter(ENTITY_KEY, TRACK_NAME, 40 + value * 160);
        break;
      case 6: // chaos — hint only
        break;
      case 7: // tension → sidechain duck from kick
        setTrackSidechain(ENTITY_KEY, TRACK_NAME, value > 0.4);
        break;
    }
  }
}

function midiToHz(midi: number): number {
  return 440 * Math.pow(2, (midi - 69) / 12);
}

function playMelodicVoice(
  voice: SynthVoice, freq: number, vel: number, dur: number, panX: number,
  entityKey: string, trackName: string,
): void {
  if (voice === 'fm') { playFmNote(freq, vel, dur, panX, entityKey, trackName); return; }
  if (voice === 'square') { playSquareNote(freq, vel, dur, panX, entityKey, trackName); return; }
  if (voice === 'pulse') { playPulseNote(freq, vel, dur, panX, entityKey, trackName); return; }
  if (voice === 'sub') { playSubNote(freq, vel, dur, panX, entityKey, trackName); return; }
  if (voice === 'epiano') { playEpianoNote(freq, vel, dur, panX, entityKey, trackName); return; }
  if (voice === 'pad') { playPadNote(freq, vel, dur, panX, entityKey, trackName); return; }
  playNote(freq, vel, dur, panX, entityKey, trackName);
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
