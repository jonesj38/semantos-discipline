---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/circuit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.630154+00:00
---

# cartridges/jambox/web/src/mappings/profiles/circuit.ts

```ts
/**
 * D-C.3 Novation Circuit / Circuit Tracks built-in profile.
 *
 * Layout:
 *   4×8 grid (MIDI notes 60-91, row 0 = bottom = notes 60-67)
 *   Bottom row (notes 36-43) = mute / solo toggles
 *   Macro knobs 0..3 (CC 21-24)
 *   Transport (CC 115-117)
 *
 * Activates on detection of a device named "Circuit*".
 */

import type { JamboxMappingPayload, MappingInput, MappingOutput } from '../../semantic/objects';

function gridInputs(): MappingInput[] {
  const inputs: MappingInput[] = [];
  for (let row = 0; row < 4; row++) {
    for (let col = 0; col < 8; col++) {
      const note = 60 + row * 8 + col;
      inputs.push({
        type: 'pad',
        selector: note,
        target: {
          kind: 'rack.trigger',
          rackId: 'jam.rack.drum-808',
          voiceId: `pad${row * 8 + col}`,
        },
      });
    }
  }
  return inputs;
}

/** Bottom row: notes 36-43 → mute (rack.macro index 7 = tension as mute proxy). */
function muteInputs(): MappingInput[] {
  return Array.from({ length: 8 }, (_, i): MappingInput => ({
    type: 'pad',
    selector: 36 + i,
    target: {
      kind: 'rack.macro',
      rackId: 'jam.rack.drum-808',
      macro: 7, // tension = mute proxy
    },
  }));
}

function macroKnobInputs(): MappingInput[] {
  return Array.from({ length: 4 }, (_, i): MappingInput => ({
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

function transportInputs(): MappingInput[] {
  return [
    { type: 'transport', selector: 'cc115', target: { kind: 'transport', verb: 'stop' } },
    { type: 'transport', selector: 'cc116', target: { kind: 'transport', verb: 'play' } },
    { type: 'transport', selector: 'cc117', target: { kind: 'transport', verb: 'record' } },
  ];
}

function ledOutputs(): MappingOutput[] {
  const outputs: MappingOutput[] = [];
  for (let i = 0; i < 32; i++) {
    outputs.push({
      type: 'led',
      selector: 60 + i,
      source: 'clip.state',
      projection: 'colour',
    });
  }
  return outputs;
}

export const CIRCUIT_PROFILE: JamboxMappingPayload = {
  name: 'Novation Circuit',
  author: 'semantos-built-in',
  surfaceShape: 'circuit',
  inputs: [
    ...gridInputs(),
    ...muteInputs(),
    ...macroKnobInputs(),
    ...transportInputs(),
  ],
  outputs: ledOutputs(),
  version: '1.0.0',
  license: 'personal',
};

export const CIRCUIT_DETECT_PATTERNS = [/circuit/i];

```
