---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/instruments/arp.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.603439+00:00
---

# cartridges/jambox/web/src/instruments/arp.ts

```ts
/**
 * Arpeggiator: latches the currently-held keys, then plays them
 * one-by-one at a tempo-locked rate. Up / down / up-down / random
 * patterns × octave range × 1/4 / 1/8 / 1/16 / 1/32 rates.
 *
 * Wraps `Keys`: when arp is on, key-down adds to the held-set
 * instead of triggering a sustained note; key-up removes. The arp
 * scheduler runs on a setTimeout loop and calls `playNote` directly.
 */

import {
  playNote, playFmNote, playSquareNote, playPulseNote,
  playSubNote, playEpianoNote, playPadNote,
} from '../audio';

export type ArpMode = 'up' | 'down' | 'updown' | 'random';
export type ArpRate = 4 | 8 | 16 | 32;

export class Arpeggiator {
  private notes: number[] = [];      // held semitones (relative)
  private idx = 0;
  private dir: 1 | -1 = 1;
  private timer: number | null = null;
  private on = false;
  private bpm = 120;
  private rate: ArpRate = 16;
  private mode: ArpMode = 'up';
  private octaveRange = 1;
  private rootHz = 220;
  private voice: 'saw' | 'fm' | 'square' | 'pulse' | 'sub' | 'epiano' | 'pad' = 'saw';

  setOn(on: boolean): void {
    this.on = on;
    if (on) this.schedule(); else this.stop();
  }
  isOn(): boolean { return this.on; }
  setMode(m: ArpMode) { this.mode = m; }
  setRate(r: ArpRate) { this.rate = r; }
  setBpm(b: number) { this.bpm = b; }
  setOctaveRange(o: number) { this.octaveRange = Math.max(1, Math.min(4, o)); }
  setRootHz(hz: number) { this.rootHz = hz; }
  setVoice(v: 'saw' | 'fm' | 'square' | 'pulse' | 'sub' | 'epiano' | 'pad') { this.voice = v; }

  noteOn(semi: number): void {
    if (!this.notes.includes(semi)) this.notes.push(semi);
    if (this.on && this.timer === null) this.schedule();
  }
  noteOff(semi: number): void {
    this.notes = this.notes.filter((n) => n !== semi);
  }

  private stop() {
    if (this.timer !== null) { clearTimeout(this.timer); this.timer = null; }
  }

  private schedule() {
    if (!this.on) return;
    if (this.notes.length === 0) {
      this.timer = window.setTimeout(() => this.schedule(), 50) as unknown as number;
      return;
    }
    const expanded: number[] = [];
    for (let oct = 0; oct < this.octaveRange; oct++) {
      for (const semi of [...this.notes].sort((a, b) => a - b)) {
        expanded.push(semi + oct * 12);
      }
    }
    let next: number;
    if (this.mode === 'random') {
      next = expanded[Math.floor(Math.random() * expanded.length)];
    } else if (this.mode === 'up') {
      next = expanded[this.idx % expanded.length];
      this.idx = (this.idx + 1) % expanded.length;
    } else if (this.mode === 'down') {
      next = expanded[(expanded.length - 1 - (this.idx % expanded.length))];
      this.idx = (this.idx + 1) % expanded.length;
    } else {
      // updown
      next = expanded[this.idx];
      this.idx += this.dir;
      if (this.idx >= expanded.length) { this.idx = expanded.length - 2; this.dir = -1; }
      if (this.idx < 0) { this.idx = 1; this.dir = 1; }
    }
    const freq = this.rootHz * Math.pow(2, next / 12);
    const stepMs = (60 / this.bpm) * (4 / this.rate) * 1000;
    const dur = stepMs / 1000 * 0.9;
    if (this.voice === 'fm') playFmNote(freq, 0.7, dur, 0, 'self', 'lead');
    else if (this.voice === 'square') playSquareNote(freq, 0.7, dur, 0, 'self', 'lead');
    else if (this.voice === 'pulse') playPulseNote(freq, 0.7, dur, 0, 'self', 'lead');
    else if (this.voice === 'sub') playSubNote(freq, 0.7, dur, 0, 'self', 'lead');
    else if (this.voice === 'epiano') playEpianoNote(freq, 0.7, dur, 0, 'self', 'lead');
    else if (this.voice === 'pad') playPadNote(freq, 0.7, dur, 0, 'self', 'lead');
    else playNote(freq, 0.7, dur, 0, 'self', 'lead');
    this.timer = window.setTimeout(() => this.schedule(), stepMs) as unknown as number;
  }
}

```
