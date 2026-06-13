---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/clip.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.598282+00:00
---

# cartridges/jambox/web/src/clip.ts

```ts
/**
 * Clip launcher — Ableton Session-View / Blipblox-myTracks idiom.
 *
 * A pad isn't a one-shot anymore; it's a slot that holds a *clip*.
 * Pressing the pad queues the clip to start (or stop) at the next
 * bar boundary so launches always land musically. While playing, the
 * launcher fires the clip's pattern step-by-step in sync with the
 * sequencer's master clock.
 *
 * The drum-machine sequencer becomes the *workshop*: build a pattern
 * on a row, click "↗ pad" to capture it as a clip, and now you can
 * launch it from a pad live without programming in the moment.
 *
 * Pattern source extension points (TODO):
 *   • `Clip.strudelCode?: string` — interpret pattern via Strudel
 *     mini-notation (`bd*4 ~ sn ~ ...`). The Strudel runtime would
 *     drive `onClipStep` like the cell pattern does.
 *   • `Clip.pdPatch?: string` — load a PureData patch via webpd or
 *     hvcc-compiled AudioWorklet, route into the entity bus.
 *   • `Clip.notes?: NoteEvent[]` — MIDI-file-style note events with
 *     micro-timing, for imported patterns.
 *
 * The current cell-array form is the baseline and works without any
 * extra runtime.
 */

import type { Cell, TrackName } from './sequencer';

export type ClipPatternSource =
  | { kind: 'cells'; cells: Cell[] }       // current default
  | { kind: 'strudel'; code: string }      // future
  | { kind: 'pd'; patchUrl: string };      // future

export interface Clip {
  id: string;
  name: string;
  /** Which sequencer track / audio bus this clip plays through. */
  track: TrackName;
  /** Pattern length in canonical 64th steps. Typically 16 = 1 bar. */
  loopLength: number;
  /** UI tint hint (defaults derived from track if absent). */
  color?: string;
  /** Mute group: launching this stops other playing clips with the
   *  same tag. Use for kick / snare / hat lanes so you don't get
   *  double kicks when swapping patterns live. */
  muteGroup?: string;
  /** Pattern as a cell array (length === loopLength). Default form. */
  pattern: Cell[];
  /** Optional: hot-swappable Strudel mini-notation source. When set,
   *  the launcher prefers this over `pattern` (TODO: needs runtime). */
  strudelCode?: string;
  /** Optional: PureData patch URL for AudioWorklet (TODO: webpd). */
  pdPatchUrl?: string;
}

export type PadSlotKind = 'empty' | 'clip' | 'drum' | 'chord';

export interface DrumOneShot {
  kind: 'drum';
  drum: string;       // matches DrumKind from audio.ts
  name: string;
}
export interface ChordOneShot {
  kind: 'chord';
  name: string;
  intervals: number[];
}
export type PadSlot =
  | { kind: 'empty' }
  | { kind: 'clip'; clipId: string }
  | DrumOneShot
  | ChordOneShot;

export type ClipState = 'idle' | 'pending-launch' | 'playing' | 'pending-stop';

export interface ClipLauncherCallbacks {
  /** Fires when an active clip's pattern wants to play a cell. */
  onClipStep: (clip: Clip, cell: Cell, localStep: number) => void;
  /** Fires whenever a pad's clip-state changes (for UI re-render). */
  onClipState: (padIdx: number, state: ClipState) => void;
}

export class ClipLauncher {
  private slots = new Map<number, PadSlot>();
  private clips = new Map<string, Clip>();
  private active = new Set<number>();
  private pendingLaunch = new Set<number>();
  private pendingStop = new Set<number>();
  /** Where each playing clip is in its own loop (canonical 64ths). */
  private clipSteps = new Map<number, number>();
  private cb: ClipLauncherCallbacks;

  /** Bar size in canonical 64ths. The sequencer's step unit is 1/64,
   *  so 4 beats × 16 sixty-fourths-per-beat = 64 canonical steps in a
   *  4/4 bar. Earlier iterations had this wrong (=16) which played
   *  factory clips 4× too fast — a whole bar's worth of trigs
   *  compressed into a single beat. */
  static BAR_STEPS = 64;

  constructor(cb: ClipLauncherCallbacks) { this.cb = cb; }

  // ── Slot + clip registry ──────────────────────────────────────

  setSlot(idx: number, slot: PadSlot): void { this.slots.set(idx, slot); }
  getSlot(idx: number): PadSlot { return this.slots.get(idx) ?? { kind: 'empty' }; }
  allSlots(): Array<{ idx: number; slot: PadSlot }> {
    return [...Array(16).keys()].map((idx) => ({ idx, slot: this.getSlot(idx) }));
  }

  registerClip(c: Clip): void { this.clips.set(c.id, c); }
  unregisterClip(id: string): void {
    this.clips.delete(id);
    for (const [idx, slot] of this.slots) {
      if (slot.kind === 'clip' && slot.clipId === id) {
        this.slots.set(idx, { kind: 'empty' });
        this.active.delete(idx);
        this.pendingLaunch.delete(idx);
        this.pendingStop.delete(idx);
        this.cb.onClipState(idx, 'idle');
      }
    }
  }
  getClip(id: string): Clip | undefined { return this.clips.get(id); }
  allClips(): Clip[] { return [...this.clips.values()]; }

  // ── Toggle launch / stop (queues for next bar) ────────────────

  /**
   * Queue a launch (or stop) for the next bar boundary.
   * Returns false if the slot isn't a clip (caller can fall back to
   * one-shot behaviour for drum / chord pads).
   */
  toggle(padIdx: number): boolean {
    const slot = this.getSlot(padIdx);
    if (slot.kind !== 'clip') return false;

    if (this.active.has(padIdx)) {
      // Already playing → cancel any pending and queue a stop.
      this.pendingLaunch.delete(padIdx);
      this.pendingStop.add(padIdx);
      this.cb.onClipState(padIdx, 'pending-stop');
    } else if (this.pendingLaunch.has(padIdx)) {
      // Pending launch → cancel.
      this.pendingLaunch.delete(padIdx);
      this.cb.onClipState(padIdx, 'idle');
    } else if (this.pendingStop.has(padIdx)) {
      // Pending stop (was active) → cancel, keep playing.
      this.pendingStop.delete(padIdx);
      this.cb.onClipState(padIdx, 'playing');
    } else {
      // Idle → queue launch.
      this.pendingLaunch.add(padIdx);
      this.cb.onClipState(padIdx, 'pending-launch');
    }
    return true;
  }

  /** Force-stop everything (panic — used by reset). */
  stopAll(): void {
    for (const idx of this.active) this.cb.onClipState(idx, 'idle');
    for (const idx of this.pendingLaunch) this.cb.onClipState(idx, 'idle');
    for (const idx of this.pendingStop) this.cb.onClipState(idx, 'idle');
    this.active.clear();
    this.pendingLaunch.clear();
    this.pendingStop.clear();
    this.clipSteps.clear();
  }

  // ── Step driver (call from sequencer's onStep) ────────────────

  /**
   * Drive the launcher from the sequencer's master step. At each
   * canonical 64th: apply pending stops/launches if we're at a bar
   * boundary, then advance + fire active clips.
   */
  onStep(canonicalStep: number): void {
    if (canonicalStep % ClipLauncher.BAR_STEPS === 0) {
      // Apply stops first.
      for (const idx of this.pendingStop) {
        this.active.delete(idx);
        this.clipSteps.delete(idx);
        this.cb.onClipState(idx, 'idle');
      }
      this.pendingStop.clear();
      // Apply launches with mute-group exclusion.
      for (const idx of this.pendingLaunch) {
        const slot = this.getSlot(idx);
        if (slot.kind !== 'clip') continue;
        const clip = this.clips.get(slot.clipId);
        if (!clip) continue;
        if (clip.muteGroup) {
          for (const otherIdx of [...this.active]) {
            const otherSlot = this.getSlot(otherIdx);
            if (otherSlot.kind !== 'clip') continue;
            const other = this.clips.get(otherSlot.clipId);
            if (other && other.muteGroup === clip.muteGroup && otherIdx !== idx) {
              this.active.delete(otherIdx);
              this.clipSteps.delete(otherIdx);
              this.cb.onClipState(otherIdx, 'idle');
            }
          }
        }
        this.active.add(idx);
        this.clipSteps.set(idx, 0);
        this.cb.onClipState(idx, 'playing');
      }
      this.pendingLaunch.clear();
    }

    // Fire active clips' cells.
    for (const idx of this.active) {
      const slot = this.getSlot(idx);
      if (slot.kind !== 'clip') continue;
      const clip = this.clips.get(slot.clipId);
      if (!clip) continue;
      const localStep = this.clipSteps.get(idx) ?? 0;
      const cell = clip.pattern[localStep];
      if (cell?.on) {
        this.cb.onClipStep(clip, cell, localStep);
      }
      this.clipSteps.set(idx, (localStep + 1) % clip.loopLength);
    }
  }

  // ── State queries (for UI) ────────────────────────────────────

  state(idx: number): ClipState {
    if (this.pendingStop.has(idx)) return 'pending-stop';
    if (this.pendingLaunch.has(idx)) return 'pending-launch';
    if (this.active.has(idx)) return 'playing';
    return 'idle';
  }

  /** Local step within an active clip (0..loopLength-1) for visual
   *  beat-pulse on the pad. Returns null if not playing. */
  currentStep(idx: number): number | null {
    if (!this.active.has(idx)) return null;
    return this.clipSteps.get(idx) ?? 0;
  }
}

// ── Factory clip pack ────────────────────────────────────────────

/**
 * 12 starter clips so the room is *immediately musical*. Producers
 * land on the page, hit a few pads, hear something pleasing. Mute
 * groups keep a bunch of kick/hat/bass lanes from doubling: launching
 * a new kick auto-stops the old one at the next bar.
 */
export function makeFactoryClips(): Clip[] {
  // The clip's `pattern` array is in canonical 64th steps (same unit
  // the sequencer's master clock uses). One bar = 64 steps. The two
  // helpers below let us specify factory clips in producer-friendly
  // 16th-view positions (0..15) and inflate them into 64-cell arrays
  // by multiplying by 4 — no risk of accidentally writing patterns
  // that play 4× too fast.
  const cell = (on: boolean, semitone = 0, vel = 0.85): Cell =>
    on ? { on: true, vel, semitone } : { on: false, vel: 0.9, semitone: 0 };
  const BAR = 64;
  const trigs = (sixteenthSteps: number[], vel = 0.85): Cell[] => {
    const out: Cell[] = Array.from({ length: BAR }, () => cell(false));
    for (const s of sixteenthSteps) out[s * 4] = cell(true, 0, vel);
    return out;
  };
  const pitched = (notes: Array<[step: number, semi: number, vel?: number]>): Cell[] => {
    const out: Cell[] = Array.from({ length: BAR }, () => cell(false));
    for (const [s, semi, v = 0.85] of notes) out[s * 4] = cell(true, semi, v);
    return out;
  };
  return [
    { id: 'fc-kick-4floor', name: 'kick · 4-floor', track: 'kick',
      pattern: trigs([0, 4, 8, 12], 0.95), loopLength: BAR, muteGroup: 'kick' },
    { id: 'fc-kick-break',  name: 'kick · break',   track: 'kick',
      pattern: trigs([0, 6, 8, 14], 0.92), loopLength: BAR, muteGroup: 'kick' },
    { id: 'fc-snare-2-4',   name: 'snare · 2 & 4',  track: 'snare',
      pattern: trigs([4, 12]), loopLength: BAR, muteGroup: 'snare' },
    { id: 'fc-clap-2-4',    name: 'clap · 2 & 4',   track: 'clap',
      pattern: trigs([4, 12], 0.6), loopLength: BAR, muteGroup: 'snare' },
    { id: 'fc-hat-16ths',   name: 'hat · 16ths',    track: 'hat',
      pattern: trigs([0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15], 0.5),
      loopLength: BAR, muteGroup: 'hat' },
    { id: 'fc-hat-shuffle', name: 'hat · shuffle',  track: 'hat',
      pattern: trigs([2, 3, 6, 7, 10, 11, 14, 15], 0.55),
      loopLength: BAR, muteGroup: 'hat' },
    { id: 'fc-bass-pulse',  name: 'bass · pulse',   track: 'bass',
      pattern: pitched([[0, 0], [4, 0], [8, 7], [12, 0]]),
      loopLength: BAR, muteGroup: 'bass' },
    { id: 'fc-bass-walk',   name: 'bass · walk',    track: 'bass',
      pattern: pitched([[0, 0], [2, 3], [4, 5], [6, 7], [8, 0], [10, 3], [12, 5], [14, 7]]),
      loopLength: BAR, muteGroup: 'bass' },
    { id: 'fc-acid-303',    name: 'acid · 303 burble', track: 'acid',
      pattern: pitched([[0, 0, 0.9], [3, 0, 0.7], [6, 12, 0.85], [10, 0, 0.7], [13, 7, 0.9]]),
      loopLength: BAR, muteGroup: 'bass' },
    { id: 'fc-lead-riff',   name: 'lead · riff',    track: 'lead',
      pattern: pitched([[0, 12], [2, 7], [4, 5], [8, 12], [10, 14], [14, 12]]),
      loopLength: BAR },
    { id: 'fc-lead-pulse',  name: 'lead · pulse',   track: 'lead',
      pattern: pitched([[0, 12], [4, 7], [8, 12], [12, 5]]),
      loopLength: BAR },
    { id: 'fc-perc-poly',   name: 'perc · poly',    track: 'perc',
      pattern: trigs([1, 5, 7, 11, 13], 0.7), loopLength: BAR },
  ];
}

/** Default pad assignments: factory clips on pads 1-12, empty 13-16. */
export function makeFactoryPadLayout(clips: Clip[]): Map<number, PadSlot> {
  const out = new Map<number, PadSlot>();
  for (let i = 0; i < 16; i++) {
    if (i < clips.length) out.set(i, { kind: 'clip', clipId: clips[i].id });
    else out.set(i, { kind: 'empty' });
  }
  return out;
}

```
