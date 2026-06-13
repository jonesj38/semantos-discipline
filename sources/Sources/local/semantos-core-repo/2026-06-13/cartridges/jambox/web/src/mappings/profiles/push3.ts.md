---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/push3.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.628361+00:00
---

# cartridges/jambox/web/src/mappings/profiles/push3.ts

```ts
/**
 * D-C.3 Ableton Push 3 built-in profile.
 *
 * Layout:
 *   8×8 grid (MIDI notes 36-99, row 0 = bottom = notes 36-43)
 *   8 macro knobs (CC 71-78)
 *   Transport row (CC 116, 117, 118, 119)
 *
 * Activates on detection of a device named "Push*".
 */

import type { JamboxMappingPayload, MappingInput, MappingOutput } from '../../semantic/objects';

function gridInputs(): MappingInput[] {
  const inputs: MappingInput[] = [];
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const note = 36 + row * 8 + col;
      inputs.push({
        type: 'pad',
        selector: note,
        target: {
          kind: 'rack.note',
          rackId: 'jam.rack.poly-keys',
        },
      });
    }
  }
  return inputs;
}

function macroKnobInputs(): MappingInput[] {
  return Array.from({ length: 8 }, (_, i): MappingInput => ({
    type: 'knob',
    selector: `cc${71 + i}`,
    target: {
      kind: 'rack.macro',
      rackId: 'jam.rack.poly-keys',
      macro: i,
    },
    transform: { kind: 'linear', min: 0, max: 1 },
  }));
}

function transportInputs(): MappingInput[] {
  return [
    { type: 'transport', selector: 'cc116', target: { kind: 'transport', verb: 'stop' } },
    { type: 'transport', selector: 'cc117', target: { kind: 'transport', verb: 'play' } },
    { type: 'transport', selector: 'cc118', target: { kind: 'transport', verb: 'overdub' } },
    { type: 'transport', selector: 'cc119', target: { kind: 'transport', verb: 'record' } },
    { type: 'transport', selector: 'cc85',  target: { kind: 'transport', verb: 'capture' } },
    { type: 'transport', selector: 'cc87',  target: { kind: 'transport', verb: 'quantize' } },
    { type: 'transport', selector: 'cc83',  target: { kind: 'transport', verb: 'undo' } },
    { type: 'transport', selector: 'cc84',  target: { kind: 'transport', verb: 'redo' } },
  ];
}

function ledOutputs(): MappingOutput[] {
  const outputs: MappingOutput[] = [];
  for (let i = 0; i < 64; i++) {
    outputs.push({
      type: 'led',
      selector: 36 + i,
      source: 'scale.degree',
      projection: 'colour',
    });
  }
  return outputs;
}

export const PUSH3_PROFILE: JamboxMappingPayload = {
  name: 'Ableton Push 3',
  author: 'semantos-built-in',
  surfaceShape: 'push',
  inputs: [
    ...gridInputs(),
    ...macroKnobInputs(),
    ...transportInputs(),
  ],
  outputs: ledOutputs(),
  version: '1.0.0',
  license: 'personal',
};

export const PUSH3_DETECT_PATTERNS = [/push/i];

```
