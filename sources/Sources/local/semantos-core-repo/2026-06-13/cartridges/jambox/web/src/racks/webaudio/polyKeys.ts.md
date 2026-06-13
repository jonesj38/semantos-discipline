---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/webaudio/polyKeys.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.626396+00:00
---

# cartridges/jambox/web/src/racks/webaudio/polyKeys.ts

```ts
/**
 * PolyKeysRack — WebAudio rack wrapping the lead/keys/arp path in audio.ts.
 *
 * Voices: lead (all synth voices: saw / fm / square / pulse / sub / epiano / pad)
 * Polyphonic — multiple notes can play simultaneously.
 *
 * Macro fan-out table:
 * ```
 * 0  brightness   filter cutoff (200..12000 Hz) on the lead track bus
 * 1  dirt         drive amount (0..0.8) on lead track
 * 2  wobble       LFO depth hint — routes to filter mod depth (phase C)
 * 3  space        reverb send amount; also delay send at > 0.7
 * 4  snap         attack duration (short = percussive; long = pad)
 * 5  body         voice mix: < 0.3 = pure lead; > 0.7 = pad/epiano blend
 * 6  chaos        random detune amount on lead oscillators (hint for phase D)
 * 7  tension      resonance + sidechain from kick when > 0.5
 * ```
 */

import {
  playNote, playFmNote, playSquareNote, playPulseNote,
  playSubNote, playEpianoNote, playPadNote,
  setTrackFilter, setTrackReverb, setTrackDrive, setTrackDelay,
  setTrackSidechain,
  getAnalyser,
} from '../../audio';
import type {
  JamRack, JamNoteOn, JamTrigger, JamNoteOff, JamStop,
  JamRackState, JamMeters, JamMappingHint,
} from '../contract';
import { rackRegistry } from '../registry';
import type { SynthVoice } from '../../sequencer';

const RACK_ID = 'jam.rack.poly-keys';

/** Macro names (canonical vocabulary). */
const MACRO_NAMES: [string, string, string, string, string, string, string, string] = [
  'brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension',
];

/** Default macro values — bright, clean, lush. */
const DEFAULT_MACROS: [number, number, number, number, number, number, number, number] = [
  0.65, 0.05, 0, 0.3, 0.5, 0.5, 0, 0.3,
];

const ENTITY_KEY = 'self';
const TRACK_NAME = 'lead';

export class PolyKeysRack implements JamRack {
  readonly id = RACK_ID;
  readonly name = 'Poly Keys';
  readonly engine = 'webaudio' as const;

  private macros: [number, number, number, number, number, number, number, number] = [
    ...DEFAULT_MACROS,
  ];
  private presetId?: string;
  private voice: SynthVoice = 'saw';
  private bpm = 120;
  /** Active note pitches for polyphonic tracking. */
  private activeNotes = new Set<number>();

  constructor() {
    rackRegistry.register(this);
  }

  /** Select the synth voice. */
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
      // Panic: envelopes self-terminate in WebAudio.
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
    // Common presets: 'saw-lead', 'fm-bell', 'epiano', 'lush-pad', 'pulse-arp'.
    if (presetId === 'fm-bell') this.setVoice('fm');
    else if (presetId === 'epiano') this.setVoice('epiano');
    else if (presetId === 'lush-pad') this.setVoice('pad');
    else if (presetId === 'pulse-arp') this.setVoice('pulse');
    else if (presetId === 'square-lead') this.setVoice('square');
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
      { inputType: 'key', target: 'note', label: 'KEYS' },
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
        setTrackFilter(ENTITY_KEY, TRACK_NAME, 200 + value * 11800);
        break;
      case 1: // dirt → drive
        setTrackDrive(ENTITY_KEY, TRACK_NAME, value * 0.8);
        break;
      case 2: // wobble — hint only (phase C)
        break;
      case 3: // space → reverb + delay at high values
        setTrackReverb(ENTITY_KEY, TRACK_NAME, value * 0.7);
        if (value > 0.7) setTrackDelay(ENTITY_KEY, TRACK_NAME, (value - 0.7) / 0.3 * 0.4);
        else setTrackDelay(ENTITY_KEY, TRACK_NAME, 0);
        break;
      case 4: // snap — attack shaping; applied in play()
        break;
      case 5: // body — voice blend hint; no direct call
        break;
      case 6: // chaos — detune hint
        break;
      case 7: // tension → sidechain + filter resonance hint
        setTrackSidechain(ENTITY_KEY, TRACK_NAME, value > 0.5);
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
