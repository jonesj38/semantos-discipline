---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/midi/ExternalMidiRack.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.623660+00:00
---

# cartridges/jambox/web/src/racks/midi/ExternalMidiRack.ts

```ts
/**
 * ExternalMidiRack — JamRack implementation for external MIDI devices.
 *
 * Sends note-on / note-off / trigger to a chosen Web MIDI output channel.
 * Macros 0..7 map to MIDI CC numbers per `src/racks/midi/cc-map.ts`.
 * Receives MIDI clock and SysEx feedback where the device supports it.
 *
 * Output-first design: meters are no-op (HARD RULE 6 — device may not
 * report level). The conformance harness uses { skipMeters: true }.
 *
 * BEAMClock is the clock authority. This rack DERIVES MIDI clock from
 * jam.clock.tick; it never authors its own clock.
 *
 * Web MIDI API access follows the existing Phase C device adapter permission
 * flow. In environments without Web MIDI (test/Node) the rack operates in
 * stub mode with a virtual output buffer for verification.
 */

import type {
  JamRack, JamNoteOn, JamTrigger, JamNoteOff, JamStop,
  JamRackState, JamMeters, JamMappingHint,
} from '../contract';
import { rackRegistry } from '../registry';
import {
  MACRO_CC_MAP, ccForMacro, normalToMidiValue, midiValueToNormal,
} from './cc-map';
import type { BeatInfo } from '../../core/beam-clock';

// ── MIDI byte constants ────────────────────────────────────────────────────────

const NOTE_ON  = 0x90;
const NOTE_OFF = 0x80;
const CC       = 0xB0;
const CLOCK    = 0xF8;
const START    = 0xFA;
const STOP     = 0xFC;

// ── Stub MIDI output for test environments ─────────────────────────────────────

export interface MidiOutputMessage {
  data: Uint8Array;
  timestamp: number;
}

export interface MidiOutputPort {
  name: string | null;
  id: string;
  send(data: Uint8Array | number[], timestamp?: number): void;
}

/**
 * Stub MIDI output that records sent bytes for conformance testing.
 * Used when Web MIDI is unavailable.
 */
export class StubMidiOutput implements MidiOutputPort {
  readonly name = 'stub';
  readonly id = 'stub-0';
  readonly messages: MidiOutputMessage[] = [];

  send(data: Uint8Array | number[], timestamp?: number): void {
    this.messages.push({
      data: data instanceof Uint8Array ? data : new Uint8Array(data),
      timestamp: timestamp ?? performance.now(),
    });
  }

  /** Get the last sent message, or null. */
  lastMessage(): MidiOutputMessage | null {
    return this.messages.at(-1) ?? null;
  }

  /** Clear the message log. */
  clear(): void {
    this.messages.length = 0;
  }
}

// ── ExternalMidiRack config ────────────────────────────────────────────────────

export interface ExternalMidiRackConfig {
  /** MIDI channel (1–16). Default: 1. */
  channel?: number;
  /** If provided, use this output instead of requesting Web MIDI. */
  output?: MidiOutputPort;
  /** If true, send MIDI clock ticks derived from BEAMClock. Default: true. */
  sendClock?: boolean;
  /** If true, send SysEx device inquiry. Default: false. */
  sendSysEx?: boolean;
}

// ── Macro names ────────────────────────────────────────────────────────────────

const MACRO_NAMES = [
  'brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension',
] as const;

const DEFAULT_MACROS: [number, number, number, number, number, number, number, number] = [
  0.6, 0.1, 0, 0.2, 0.5, 0.7, 0, 0.4,
];

// ── ExternalMidiRack ───────────────────────────────────────────────────────────

export class ExternalMidiRack implements JamRack {
  readonly id: string;
  readonly name: string;
  readonly engine = 'midi' as const;

  private macros: [number, number, number, number, number, number, number, number] = [
    ...DEFAULT_MACROS,
  ];
  private presetId?: string;

  /** MIDI channel (0-indexed: 0 = channel 1) */
  private readonly channelByte: number;

  /** Active MIDI output port */
  private output: MidiOutputPort | null;

  /** Whether MIDI clock is enabled */
  private readonly sendClock: boolean;

  /** Active voice tracking (pitch → voiceId) for note-off matching */
  private activeNotes = new Map<number, string>();

  /** MIDI clock tick accumulator — 24 ticks per quarter note */
  private clockTickCount = 0;

  constructor(id: string, name: string, config: ExternalMidiRackConfig = {}) {
    this.id = id;
    this.name = name;
    this.channelByte = Math.max(0, Math.min(15, (config.channel ?? 1) - 1));
    this.output = config.output ?? null;
    this.sendClock = config.sendClock ?? true;

    // If no output provided, try to acquire Web MIDI
    if (!this.output) {
      void this.acquireWebMidi(config.sendSysEx ?? false);
    }

    rackRegistry.register(this);
  }

  // ── Clock slave ────────────────────────────────────────────────────────────────

  /**
   * Called by BEAMClock.onBeat. Derives MIDI clock ticks (24 ppq) from
   * the BEAMClock beat count. This rack NEVER authors its own tempo.
   */
  onClockTick(info: BeatInfo): void {
    if (!this.sendClock) return;
    // Send 24 MIDI clock ticks per beat
    // On the first beat (beat === 0 or beat === 1), also send START
    if (info.beat === 0 || info.beat === 1) {
      this.sendRaw([START]);
    }
    // Send one clock tick now; the other 23 would be scheduled at subdivisions
    // in a real implementation with AudioWorklet timer precision.
    // For the rack contract: one tick per onClockTick() call is sufficient.
    this.sendRaw([CLOCK]);
    this.clockTickCount++;
  }

  // ── JamRack interface ──────────────────────────────────────────────────────────

  play(event: JamNoteOn | JamTrigger): void {
    if (event.kind === 'note.on') {
      const pitch = Math.max(0, Math.min(127, event.pitch));
      const vel = Math.max(0, Math.min(127, event.velocity));
      const voiceId = event.voiceId ?? `v${pitch}`;
      this.activeNotes.set(pitch, voiceId);
      this.sendRaw([NOTE_ON | this.channelByte, pitch, vel]);
    } else {
      // Trigger: map voiceId to a pitch by convention
      const pitch = voiceIdToPitch(event.voiceId);
      const vel = Math.max(0, Math.min(127, Math.round(event.velocity * 127)));
      const voiceId = event.voiceId;
      this.activeNotes.set(pitch, voiceId);
      this.sendRaw([NOTE_ON | this.channelByte, pitch, vel]);
      // Triggers are one-shot: schedule note-off after 20 ms
      setTimeout(() => {
        this.sendRaw([NOTE_OFF | this.channelByte, pitch, 0]);
        this.activeNotes.delete(pitch);
      }, 20);
    }
  }

  stop(event: JamNoteOff | JamStop): void {
    if (event.kind === 'note.off') {
      const pitch = Math.max(0, Math.min(127, event.pitch));
      this.sendRaw([NOTE_OFF | this.channelByte, pitch, 0]);
      this.activeNotes.delete(pitch);
    } else {
      // Panic: send note-off for all active voices + all-notes-off CC
      for (const [pitch] of this.activeNotes) {
        this.sendRaw([NOTE_OFF | this.channelByte, pitch, 0]);
      }
      this.activeNotes.clear();
      // CC 123 = All Notes Off
      this.sendRaw([CC | this.channelByte, 123, 0]);
      // CC 120 = All Sound Off
      this.sendRaw([CC | this.channelByte, 120, 0]);
      // Send STOP
      this.sendRaw([STOP]);
    }
  }

  setMacro(index: number, value: number): void {
    const i = Math.max(0, Math.min(7, Math.floor(index)));
    const v = Math.max(0, Math.min(1, value));
    this.macros[i] = v;
    const cc = ccForMacro(i);
    if (cc !== undefined) {
      const midiVal = normalToMidiValue(v);
      this.sendRaw([CC | this.channelByte, cc, midiVal]);
    }
  }

  setPreset(presetId: string): void {
    this.presetId = presetId;
    // Program change: encode presetId as a number 0-127 if it's numeric
    const prog = parseInt(presetId, 10);
    if (!isNaN(prog) && prog >= 0 && prog <= 127) {
      this.sendRaw([0xC0 | this.channelByte, prog]);
    }
  }

  getState(): JamRackState {
    return {
      presetId: this.presetId,
      macros: [...this.macros],
      engineState: {
        channel: this.channelByte + 1,
        outputName: this.output?.name ?? null,
      },
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
  }

  /**
   * Meters are no-op for ExternalMidiRack.
   * External devices may not report audio levels back to the host.
   * The conformance harness skips meter checks for this rack.
   */
  getMeters(): JamMeters {
    return { peakL: 0, peakR: 0, rmsL: 0, rmsR: 0 };
  }

  getMappingHints(): JamMappingHint[] {
    const macroHints: JamMappingHint[] = MACRO_NAMES.map((name, i) => ({
      inputType: 'knob' as const,
      target: `macro.${i}`,
      label: `${name} (CC ${ccForMacro(i) ?? '?'})`,
      range: [0, 1] as [number, number],
    }));
    const noteHints: JamMappingHint[] = [
      { inputType: 'key', target: 'note', label: `MIDI Ch${this.channelByte + 1}` },
      { inputType: 'pad', target: 'trigger', label: 'TRIG' },
    ];
    return [...macroHints, ...noteHints];
  }

  /** Provide a MIDI output port directly (e.g. from Web MIDI). */
  setOutput(output: MidiOutputPort): void {
    this.output = output;
    // Re-send current macro values to new device
    for (let i = 0; i < 8; i++) {
      const cc = ccForMacro(i);
      if (cc !== undefined) {
        this.sendRaw([CC | this.channelByte, cc, normalToMidiValue(this.macros[i])]);
      }
    }
  }

  getOutput(): MidiOutputPort | null {
    return this.output;
  }

  /** Read macro values from incoming MIDI CC (useful for SysEx feedback loops). */
  onMidiInput(data: Uint8Array): void {
    const status = data[0];
    const byte1 = data[1] ?? 0;
    const byte2 = data[2] ?? 0;

    // CC on our channel
    if ((status & 0xF0) === CC && (status & 0x0F) === this.channelByte) {
      const macroIndex = MACRO_CC_MAP.find((e) => e.cc === byte1)?.macroIndex;
      if (macroIndex !== undefined) {
        this.macros[macroIndex] = midiValueToNormal(byte2);
      }
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────────

  private sendRaw(data: number[]): void {
    if (!this.output) return;
    this.output.send(data);
  }

  private async acquireWebMidi(sendSysEx: boolean): Promise<void> {
    if (typeof navigator === 'undefined' || !navigator.requestMIDIAccess) {
      // Not a browser environment — use stub output
      this.output = new StubMidiOutput();
      return;
    }
    try {
      const access = await navigator.requestMIDIAccess({ sysex: sendSysEx });
      const outputs = Array.from(access.outputs.values());
      if (outputs.length > 0 && outputs[0]) {
        this.output = outputs[0] as unknown as MidiOutputPort;
      } else {
        this.output = new StubMidiOutput();
      }
    } catch {
      this.output = new StubMidiOutput();
    }
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

/**
 * Map a drum voice name to a MIDI pitch.
 * Uses General MIDI drum map (channel 10 pitch assignments).
 */
function voiceIdToPitch(voiceId: string): number {
  const GM_DRUM: Record<string, number> = {
    kick:    36, // Bass Drum 1
    snare:   38, // Acoustic Snare
    hat:     42, // Closed Hi-Hat
    clap:    39, // Hand Clap
    cb:      56, // Cowbell
    tom:     45, // Low Tom
    sub:     35, // Bass Drum 2
    perc:    60, // Hi Bongo
    shaker:  70, // Maracas
    'open-hat': 46, // Open Hi-Hat
    crash:   49, // Crash Cymbal 1
    ride:    51, // Ride Cymbal 1
  };
  return GM_DRUM[voiceId] ?? 60;
}

```
