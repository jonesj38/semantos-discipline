---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/instruments/midi-map.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.602862+00:00
---

# cartridges/jambox/web/src/instruments/midi-map.ts

```ts
/**
 * MIDI mapping layer.
 *
 *   incoming MIDI msg ─→ MidiMap.dispatch
 *                          ├─ if learn mode is awaiting a target:
 *                          │     bind this msg to that target, persist
 *                          ├─ for each binding matching the msg:
 *                          │     invoke the registered handler with the value
 *                          └─ else: noop (return false so caller can fallback)
 *
 * Targets are identified by stable string ids so saved bindings
 * survive UI re-renders. main.ts registers a handler for each id at
 * boot (`mm.register('mixerFader.0', v => setEntityGain(...))`).
 *
 * UI controls expose themselves as learnable by having
 * `data-midi-target="<id>"` and (optionally) a small "⊕" button next
 * to them. Clicking the button calls `mm.beginLearn(targetId)` and
 * the next MIDI input message becomes the binding.
 *
 * Bindings persist to `localStorage[jamMidiMapV1]` so producers map
 * once and forget.
 *
 * The default mapping ships with sensible MPK49 defaults — keyboard
 * notes on channel 1, drum pads on channel 10 (notes 36..47), eight
 * sliders on CC 11..18, eight rotary encoders on CC 21..28, and
 * common transport CCs.
 */

export type MidiMsgType = 'note' | 'cc';

export interface MidiTrigger {
  ch: number;       // 1..16
  type: MidiMsgType;
  n: number;        // note 0..127 or cc 0..127
}

export interface MidiBinding {
  trigger: MidiTrigger;
  target: string;
  /** Human-friendly label saved alongside the binding. */
  label?: string;
}

const STORAGE_KEY = 'jamMidiMapV1';

/** Default MPK49 mapping. Most MPK49 defaults follow this convention. */
const MPK49_DEFAULT_BINDINGS: MidiBinding[] = [
  // Drum pads (channel 10, MIDI notes 36..47 = standard GM drum range)
  ...Array.from({ length: 12 }, (_, i): MidiBinding => ({
    trigger: { ch: 10, type: 'note', n: 36 + i },
    target: `mpkPad.${i % 16}`,
    label: `pad ${i + 1}`,
  })),
  // Sliders S1..S8 → mixer faders + master + perf-FX (CC 11..18)
  { trigger: { ch: 1, type: 'cc', n: 11 }, target: 'mixerFader.0', label: 'S1 → mix1' },
  { trigger: { ch: 1, type: 'cc', n: 12 }, target: 'mixerFader.1', label: 'S2 → mix2' },
  { trigger: { ch: 1, type: 'cc', n: 13 }, target: 'mixerFader.2', label: 'S3 → mix3' },
  { trigger: { ch: 1, type: 'cc', n: 14 }, target: 'mixerFader.3', label: 'S4 → mix4' },
  { trigger: { ch: 1, type: 'cc', n: 15 }, target: 'perfFilter',   label: 'S5 → filter' },
  { trigger: { ch: 1, type: 'cc', n: 16 }, target: 'gateDepth',    label: 'S6 → gate depth' },
  { trigger: { ch: 1, type: 'cc', n: 17 }, target: 'masterCeil',   label: 'S7 → ceiling' },
  { trigger: { ch: 1, type: 'cc', n: 18 }, target: 'crossfader',   label: 'S8 → xfader' },
  // Rotary encoders K1..K8 → per-track FX of selected track (CC 21..28)
  { trigger: { ch: 1, type: 'cc', n: 21 }, target: 'selTrack.cut',     label: 'K1 → cutoff' },
  { trigger: { ch: 1, type: 'cc', n: 22 }, target: 'selTrack.rev',     label: 'K2 → reverb' },
  { trigger: { ch: 1, type: 'cc', n: 23 }, target: 'selTrack.dly',     label: 'K3 → delay' },
  { trigger: { ch: 1, type: 'cc', n: 24 }, target: 'selTrack.drv',     label: 'K4 → drive' },
  { trigger: { ch: 1, type: 'cc', n: 25 }, target: 'selTrack.crsh',    label: 'K5 → bitcrush' },
  { trigger: { ch: 1, type: 'cc', n: 26 }, target: 'selTrack.swing',   label: 'K6 → swing' },
  { trigger: { ch: 1, type: 'cc', n: 27 }, target: 'selTrack.bpm',     label: 'K7 → bpm' },
  { trigger: { ch: 1, type: 'cc', n: 28 }, target: 'selTrack.echo',    label: 'K8 → echo throw' },
  // Transport — typical MPK49 transport CCs
  { trigger: { ch: 1, type: 'cc', n: 117 }, target: 'play',   label: 'play' },
  { trigger: { ch: 1, type: 'cc', n: 116 }, target: 'stop',   label: 'stop' },
  { trigger: { ch: 1, type: 'cc', n: 119 }, target: 'record', label: 'record' },
];

function defaultBindings(): MidiBinding[] {
  return JSON.parse(JSON.stringify(MPK49_DEFAULT_BINDINGS));
}

export class MidiMap {
  private bindings: MidiBinding[] = defaultBindings();
  private handlers = new Map<string, (val: number) => void>();
  private targetLabels = new Map<string, string>();
  private learnPending: string | null = null;
  private listeners = new Set<() => void>();

  constructor() { this.load(); }

  /** Register a handler for a target id. `val` is 0..1 (CC) or 0..1 vel (note). */
  register(targetId: string, handler: (val: number) => void, label?: string): void {
    this.handlers.set(targetId, handler);
    if (label) this.targetLabels.set(targetId, label);
  }

  registeredTargets(): Array<{ id: string; label: string }> {
    return [...this.handlers.keys()].map((id) => ({
      id, label: this.targetLabels.get(id) ?? id,
    }));
  }

  bindingsList(): MidiBinding[] { return this.bindings.slice(); }

  /** Subscribe to binding-list changes (for the panel UI). */
  onChange(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
  private emitChange(): void { for (const fn of this.listeners) fn(); }

  /** Tell the map: the next MIDI msg should bind to this target id. */
  beginLearn(targetId: string): void {
    this.learnPending = targetId;
    this.emitChange();
  }
  cancelLearn(): void { this.learnPending = null; this.emitChange(); }
  isLearning(): boolean { return this.learnPending !== null; }
  learningTarget(): string | null { return this.learnPending; }

  /** Drop a binding for `targetId` (or all bindings if no id given). */
  unbind(targetId: string): void {
    this.bindings = this.bindings.filter((b) => b.target !== targetId);
    this.save();
    this.emitChange();
  }
  resetToDefaults(): void {
    this.bindings = defaultBindings();
    this.save();
    this.emitChange();
  }

  /** Process an incoming MIDI message. Returns true if it matched a binding. */
  dispatch(ch: number, type: MidiMsgType, n: number, value: number): boolean {
    if (this.learnPending) {
      const target = this.learnPending;
      const label = this.targetLabels.get(target) ?? target;
      this.bindings = this.bindings.filter((b) => b.target !== target);
      this.bindings.push({
        trigger: { ch, type, n },
        target,
        label: `${label} ← ${type === 'cc' ? `CC${n}` : `note${n}`}@ch${ch}`,
      });
      this.learnPending = null;
      this.save();
      this.emitChange();
      return true;
    }
    let matched = false;
    for (const b of this.bindings) {
      if (b.trigger.ch === ch && b.trigger.type === type && b.trigger.n === n) {
        const handler = this.handlers.get(b.target);
        if (handler) {
          handler(value);
          matched = true;
        }
      }
    }
    return matched;
  }

  private load(): void {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return;
      const parsed = JSON.parse(raw) as MidiBinding[];
      if (Array.isArray(parsed)) this.bindings = parsed;
    } catch { /* ignore */ }
  }
  private save(): void {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(this.bindings)); }
    catch { /* ignore */ }
  }
}

```
