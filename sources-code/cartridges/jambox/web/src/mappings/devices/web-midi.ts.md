---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/devices/web-midi.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.631082+00:00
---

# cartridges/jambox/web/src/mappings/devices/web-midi.ts

```ts
/**
 * D-C.2 Web MIDI device adapter.
 *
 * Wraps the existing midi.ts scaffolding and emits normalised DeviceEvents.
 * The existing MidiMap (midi-map.ts) still works — this adapter routes through
 * the new 5-layer pipeline in parallel (subsumes, does not replace).
 *
 * Hard rule: only emits DeviceEvent — never jam.* cells directly.
 */

import type { DeviceEvent } from '../router';

export type WebMidiDeviceListener = (event: DeviceEvent, deviceName: string) => void;

export interface WebMidiAdapterOptions {
  /** Called for every normalised DeviceEvent. */
  onEvent: WebMidiDeviceListener;
  /** Called when a new MIDI input device connects. */
  onDeviceConnect?: (deviceName: string) => void;
  /** Called when a MIDI input device disconnects. */
  onDeviceDisconnect?: (deviceName: string) => void;
}

/**
 * Attach to all available MIDI inputs and emit normalised DeviceEvents.
 *
 * Returns a cleanup function.  Permission is requested once on first call;
 * subsequent calls reuse the MIDIAccess without a second prompt.
 */
export async function attachWebMidiAdapter(
  opts: WebMidiAdapterOptions,
): Promise<{ devices: string[]; detach: () => void } | null> {
  const nav = navigator as Navigator & { requestMIDIAccess?: (opts?: { sysex: boolean }) => Promise<MIDIAccess> };
  if (!nav.requestMIDIAccess) return null;

  let access: MIDIAccess;
  try {
    access = await nav.requestMIDIAccess({ sysex: false });
  } catch {
    return null;
  }

  const devices: string[] = [];
  const detachFns: Array<() => void> = [];

  const wireInput = (input: MIDIInput) => {
    const name = input.name ?? input.id;
    if (devices.includes(name)) return;
    devices.push(name);
    opts.onDeviceConnect?.(name);

    const handler = (e: MIDIMessageEvent) => {
      const data = e.data;
      if (!data || data.length < 2) return;
      const status = data[0]!;
      const d1 = data[1]!;
      const d2 = data[2] ?? 0;
      const cmd = status & 0xf0;
      const channel = (status & 0x0f) + 1;
      const ts = Date.now();

      if (cmd === 0x90 && d2 > 0) {
        // Note On
        opts.onEvent({
          kind: 'pad.on',
          selector: d1,
          value: d2 / 127,
          channel,
          deviceName: name,
          ts,
        }, name);
      } else if (cmd === 0x80 || (cmd === 0x90 && d2 === 0)) {
        // Note Off
        opts.onEvent({
          kind: 'pad.off',
          selector: d1,
          value: 0,
          channel,
          deviceName: name,
          ts,
        }, name);
      } else if (cmd === 0xb0) {
        // CC
        opts.onEvent({
          kind: 'knob',
          selector: `cc${d1}`,
          value: d2 / 127,
          channel,
          deviceName: name,
          ts,
        }, name);
      } else if (cmd === 0xe0) {
        // Pitch bend: 14-bit, centered at 8192
        const raw = (d2 << 7) | d1;
        const normalised = (raw - 8192) / 8192; // -1..1
        opts.onEvent({
          kind: 'fader',
          selector: 'pitch-bend',
          value: (normalised + 1) / 2, // remap to 0..1 for the pipeline
          channel,
          deviceName: name,
          ts,
        }, name);
      }
    };

    input.addEventListener('midimessage', handler as EventListener);
    detachFns.push(() => input.removeEventListener('midimessage', handler as EventListener));
  };

  for (const input of access.inputs.values()) wireInput(input);

  const stateHandler = (e: MIDIConnectionEvent) => {
    const port = e.port;
    if (!port) return;
    if (port.type === 'input' && port.state === 'connected') {
      wireInput(port as MIDIInput);
    } else if (port.type === 'input' && port.state === 'disconnected') {
      const name = port.name ?? port.id;
      opts.onDeviceDisconnect?.(name);
    }
  };

  access.addEventListener('statechange', stateHandler as EventListener);
  detachFns.push(() => access.removeEventListener('statechange', stateHandler as EventListener));

  return {
    devices,
    detach: () => { for (const fn of detachFns) fn(); },
  };
}

```
