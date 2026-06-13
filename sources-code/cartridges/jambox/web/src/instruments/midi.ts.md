---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/instruments/midi.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.603162+00:00
---

# cartridges/jambox/web/src/instruments/midi.ts

```ts
/**
 * Web MIDI input bridge. Forwards MIDI note-on/off + CC to callbacks
 * with channel info so the mapping layer can distinguish keyboard
 * (channel 1) from drum-pad layouts (channel 10) etc.
 *
 * Browsers gate Web MIDI behind a permission prompt. Returns null if
 * requestMIDIAccess is unavailable or denied.
 *
 * Usage: `await attachMidi({ onNoteOn, onNoteOff, onCc })` once at
 * boot. The hook surfaces all connected devices' input streams so an
 * MPK / Push / Launchkey / KeyStep just works.
 */

export interface MidiCallbacks {
  /** `note` is raw MIDI note (0..127, 60 = middle C); `vel` is 0..1; `channel` is 1..16. */
  onNoteOn: (note: number, vel: number, channel: number) => void;
  onNoteOff: (note: number, channel: number) => void;
  /** `cc` is 0..127, `value` is 0..1, `channel` is 1..16. */
  onCc?: (cc: number, value: number, channel: number) => void;
  /** Pitch-bend wheel (centered = 0, full down = -1, full up = +1). */
  onPitchBend?: (value: number, channel: number) => void;
}

export interface MidiAttachment {
  devices: string[];
}

export async function attachMidi(cb: MidiCallbacks): Promise<MidiAttachment | null> {
  const nav = navigator as Navigator & { requestMIDIAccess?: () => Promise<MIDIAccess> };
  if (!nav.requestMIDIAccess) return null;
  let access: MIDIAccess;
  try {
    access = await nav.requestMIDIAccess();
  } catch {
    return null;
  }
  const devices: string[] = [];
  const wire = (input: MIDIInput) => {
    if (devices.includes(input.name ?? input.id)) return;
    devices.push(input.name ?? input.id);
    input.onmidimessage = (e: MIDIMessageEvent) => {
      const [status, d1, d2 = 0] = e.data ?? [];
      if (status === undefined) return;
      const cmd = status & 0xf0;
      const channel = (status & 0x0f) + 1;
      if (cmd === 0x90 && d2 > 0) cb.onNoteOn(d1, d2 / 127, channel);
      else if (cmd === 0x80 || (cmd === 0x90 && d2 === 0)) cb.onNoteOff(d1, channel);
      else if (cmd === 0xb0 && cb.onCc) cb.onCc(d1, d2 / 127, channel);
      else if (cmd === 0xe0 && cb.onPitchBend) {
        const raw = (d2 << 7) | d1;     // 0..16383, center = 8192
        cb.onPitchBend((raw - 8192) / 8192, channel);
      }
    };
  };
  for (const input of access.inputs.values()) wire(input);
  access.onstatechange = (e) => {
    const port = e.port;
    if (port && port.type === 'input' && port.state === 'connected') {
      wire(port as MIDIInput);
    }
  };
  return { devices };
}

```
