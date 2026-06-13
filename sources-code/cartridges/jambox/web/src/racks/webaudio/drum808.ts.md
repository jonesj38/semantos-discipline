---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/webaudio/drum808.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.626993+00:00
---

# cartridges/jambox/web/src/racks/webaudio/drum808.ts

```ts
/**
 * Drum808Rack — WebAudio rack wrapping the existing drum path in audio.ts.
 *
 * Voices: kick / snare / hat / clap / cb / tom / sub / perc / shaker
 *
 * Macro fan-out table:
 * ```
 * 0  brightness   hat/perc/shaker tone filter cutoff
 * 1  dirt         waveshaper drive amount on all drum buses
 * 2  wobble       (reserved — no LFO on drums; routes to swing via sequencer hint)
 * 3  space        reverb send amount on snare/clap/tom
 * 4  snap         kick/snare punch (attack transient emphasis)
 * 5  body         kick/sub volume mix ratio
 * 6  chaos        probability randomisation nudge (add to all step probs)
 * 7  tension      sidechain depth on bass/lead channels
 * ```
 */

import {
  playDrum,
  setTrackFilter, setTrackReverb, setTrackDrive, setTrackSidechain,
  getAnalyser,
  type DrumKind,
} from '../../audio';
import type {
  JamRack, JamNoteOn, JamTrigger, JamNoteOff, JamStop,
  JamRackState, JamMeters, JamMappingHint,
} from '../contract';
import { rackRegistry } from '../registry';

/** Canonical voice names for the 808 drum rack. */
const DRUM808_VOICES: DrumKind[] = [
  'kick', 'snare', 'hat', 'clap', 'cb', 'tom', 'sub', 'perc', 'shaker',
];

const RACK_ID = 'jam.rack.drum-808';

/** Macro names for Drum808Rack (canonical, shared vocabulary). */
const MACRO_NAMES: [string, string, string, string, string, string, string, string] = [
  'brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension',
];

/** Default macro values. */
const DEFAULT_MACROS: [number, number, number, number, number, number, number, number] = [
  0.6, 0.15, 0, 0.2, 0.5, 0.5, 0, 0.4,
];

export class Drum808Rack implements JamRack {
  readonly id = RACK_ID;
  readonly name = 'Drum 808';
  readonly engine = 'webaudio' as const;

  private macros: [number, number, number, number, number, number, number, number] = [
    ...DEFAULT_MACROS,
  ];
  private presetId?: string;
  private entityKey = 'self';

  constructor(entityKey = 'self') {
    this.entityKey = entityKey;
    rackRegistry.register(this);
  }

  play(event: JamNoteOn | JamTrigger): void {
    if (event.kind === 'trigger') {
      const voice = event.voiceId as DrumKind;
      if (!DRUM808_VOICES.includes(voice)) return;
      const vel = Math.max(0, Math.min(1, event.velocity));
      playDrum(voice, vel, 0, this.entityKey, voice);
    } else {
      // note.on: map MIDI pitch to drum voice by index (C3=kick, D3=snare, etc.)
      const voiceIdx = event.pitch % DRUM808_VOICES.length;
      const voice = DRUM808_VOICES[voiceIdx];
      if (!voice) return;
      const vel = Math.max(0, Math.min(1, event.velocity / 127));
      playDrum(voice, vel, 0, this.entityKey, voice);
    }
  }

  stop(_event: JamNoteOff | JamStop): void {
    // Drum voices are one-shot; no release needed for note.off.
    // For panic/transport stop we could mute the entity bus but
    // that's handled at the audio engine level.
  }

  setMacro(index: number, value: number): void {
    const i = Math.max(0, Math.min(7, Math.floor(index)));
    const v = Math.max(0, Math.min(1, value));
    this.macros[i] = v;
    this.applyMacro(i, v);
  }

  setPreset(presetId: string): void {
    this.presetId = presetId;
    // Preset handling reserved for Phase C.
  }

  getState(): JamRackState {
    return {
      presetId: this.presetId,
      macros: [...this.macros],
      engineState: { entityKey: this.entityKey },
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
  }

  getMeters(): JamMeters {
    return readAnalyserMeters();
  }

  getMappingHints(): JamMappingHint[] {
    const padHints: JamMappingHint[] = DRUM808_VOICES.map((voice) => ({
      inputType: 'pad' as const,
      target: voice,
      label: voice.toUpperCase(),
    }));
    const macroHints: JamMappingHint[] = MACRO_NAMES.map((name, i) => ({
      inputType: 'knob' as const,
      target: `macro.${i}`,
      label: name,
      range: [0, 1] as [number, number],
    }));
    return [...padHints, ...macroHints];
  }

  /**
   * Apply a single macro value to the underlying audio.ts parameters.
   * Fan-out table is documented in the module JSDoc.
   */
  private applyMacro(index: number, value: number): void {
    switch (index) {
      case 0: // brightness → hat/perc/shaker tone filter
        setTrackFilter(this.entityKey, 'hat',    1000 + value * 17000);
        setTrackFilter(this.entityKey, 'perc',   800  + value * 11200);
        setTrackFilter(this.entityKey, 'shaker', 1500 + value * 16500);
        break;
      case 1: // dirt → drive on snare/hat/clap
        setTrackDrive(this.entityKey, 'snare',  value * 0.8);
        setTrackDrive(this.entityKey, 'hat',    value * 0.5);
        setTrackDrive(this.entityKey, 'clap',   value * 0.6);
        break;
      case 2: // wobble — reserved for swing sequencer hint
        break;
      case 3: // space → reverb on snare/clap/tom
        setTrackReverb(this.entityKey, 'snare', value * 0.6);
        setTrackReverb(this.entityKey, 'clap',  value * 0.7);
        setTrackReverb(this.entityKey, 'tom',   value * 0.5);
        break;
      case 4: // snap → drive-based punch on kick/snare
        setTrackDrive(this.entityKey, 'kick',  value * 0.5);
        setTrackDrive(this.entityKey, 'snare', value * 0.3);
        break;
      case 5: // body → filter on kick/sub to shape low-end
        setTrackFilter(this.entityKey, 'kick', 60 + value * 140);
        setTrackFilter(this.entityKey, 'sub',  40 + value * 120);
        break;
      case 6: // chaos — hint-only; actual randomisation is in the sequencer
        break;
      case 7: // tension → sidechain depth on bass/lead
        setTrackSidechain(this.entityKey, 'bass', value > 0.5);
        setTrackSidechain(this.entityKey, 'lead', value > 0.3);
        break;
    }
  }
}

/** Read peak/RMS from the master analyser node. */
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
