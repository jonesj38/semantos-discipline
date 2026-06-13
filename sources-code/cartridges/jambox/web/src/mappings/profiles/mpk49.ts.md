---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/mpk49.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.629277+00:00
---

# cartridges/jambox/web/src/mappings/profiles/mpk49.ts

```ts
/**
 * D-C.3 Akai MPK49 built-in profile.
 *
 * Layout (subsumes the existing midi-map.ts MPK49 defaults — same CC numbers):
 *   Keys (ch 1, notes 0-127)   = note-mode pitch
 *   Pads (ch 10, notes 36-47)  = drum rack triggers
 *   8 knobs K1-K8 (CC 21-28)  = rack macros 0-7
 *   8 faders S1-S8 (CC 11-18) = mix volume fader per track
 *   Transport (CC 115-119)    = play/stop/record/overdub/tap
 *
 * Activates on detection of a device named "MPK*" or "Akai*".
 */

import type { JamboxMappingPayload, MappingInput, MappingOutput } from '../../semantic/objects';

/** Keys: MIDI notes on ch 1 → rack.note. */
function keyInputs(): MappingInput[] {
  // We represent the keyboard as a single selector pattern 'key.*' — the
  // web-midi adapter will emit note numbers; the router matches by selector.
  // For simplicity we enumerate the common playable range 36-96.
  const inputs: MappingInput[] = [];
  for (let note = 36; note <= 96; note++) {
    inputs.push({
      type: 'pad', // MIDI keys come in as pad.on/off
      selector: note,
      target: {
        kind: 'rack.note',
        rackId: 'jam.rack.poly-keys',
      },
    });
  }
  return inputs;
}

/** Drum pads: MIDI notes 36-47 on ch 10 → drum rack triggers. */
function drumPadInputs(): MappingInput[] {
  return Array.from({ length: 12 }, (_, i): MappingInput => ({
    type: 'pad',
    selector: `ch10.${36 + i}`, // channel-qualified selector
    target: {
      kind: 'rack.trigger',
      rackId: 'jam.rack.drum-808',
      voiceId: `pad${i}`,
    },
  }));
}

/** 8 knobs K1-K8 → rack macros 0-7 (CC 21-28). */
function knobInputs(): MappingInput[] {
  return Array.from({ length: 8 }, (_, i): MappingInput => ({
    type: 'knob',
    selector: `cc${21 + i}`,
    target: {
      kind: 'rack.macro',
      rackId: 'jam.rack.poly-keys',
      macro: i,
    },
    transform: { kind: 'linear', min: 0, max: 1 },
  }));
}

/** 8 faders S1-S8 → mix volume (CC 11-18). */
function faderInputs(): MappingInput[] {
  const rackIds = [
    'jam.rack.drum-808',
    'jam.rack.bass-mono',
    'jam.rack.poly-keys',
    'jam.rack.acid-303',
    'jam.rack.drum-808', // duplicated for now — future racks expand this
    'jam.rack.bass-mono',
    'jam.rack.poly-keys',
    'jam.rack.acid-303',
  ];
  return Array.from({ length: 8 }, (_, i): MappingInput => ({
    type: 'fader',
    selector: `cc${11 + i}`,
    target: {
      kind: 'rack.macro',
      rackId: rackIds[i]!,
      macro: 5, // macro 5 = body = volume proxy
    },
    transform: { kind: 'linear', min: 0, max: 1 },
  }));
}

function transportInputs(): MappingInput[] {
  return [
    { type: 'transport', selector: 'cc117', target: { kind: 'transport', verb: 'play' } },
    { type: 'transport', selector: 'cc116', target: { kind: 'transport', verb: 'stop' } },
    { type: 'transport', selector: 'cc119', target: { kind: 'transport', verb: 'record' } },
    { type: 'transport', selector: 'cc118', target: { kind: 'transport', verb: 'overdub' } },
    { type: 'transport', selector: 'cc89',  target: { kind: 'transport', verb: 'tap' } },
  ];
}

function motorFaderOutputs(): MappingOutput[] {
  return Array.from({ length: 8 }, (_, i): MappingOutput => ({
    type: 'motor-fader',
    selector: `cc${11 + i}`,
    source: 'rack.macro',
    projection: 'value',
  }));
}

export const MPK49_PROFILE: JamboxMappingPayload = {
  name: 'Akai MPK49',
  author: 'semantos-built-in',
  surfaceShape: 'mpk49',
  inputs: [
    ...keyInputs(),
    ...drumPadInputs(),
    ...knobInputs(),
    ...faderInputs(),
    ...transportInputs(),
  ],
  outputs: motorFaderOutputs(),
  version: '1.0.0',
  license: 'personal',
};

export const MPK49_DETECT_PATTERNS = [/mpk/i, /akai/i];

```
