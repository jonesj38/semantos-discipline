---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/rx2.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.628972+00:00
---

# cartridges/jambox/web/src/mappings/profiles/rx2.ts

```ts
/**
 * D-C.3 Numark RX2 built-in profile.
 *
 * Layout:
 *   Deck A (ch 1) buttons/pads    = scene A launch
 *   Deck B (ch 2) buttons/pads    = scene B launch
 *   Crossfader (CC 8 ch 1)        = scene morph macro
 *   Jog wheel left (CC 33/34 ch 1)  = nudge / scrub
 *   Jog wheel right (CC 35/36 ch 2) = nudge / scrub
 *   FX pads deck A (notes 48-55) = gestures
 *
 * Activates on detection of a device named "*RX2*" or "*Numark*".
 */

import type { JamboxMappingPayload, MappingInput, MappingOutput } from '../../semantic/objects';

function deckInputs(): MappingInput[] {
  const inputs: MappingInput[] = [];

  // Deck A transport buttons → scene A launch
  for (let i = 0; i < 8; i++) {
    inputs.push({
      type: 'pad',
      selector: 48 + i,
      target: { kind: 'scene.launch', sceneId: 'scene-0' },
    });
  }

  // Deck B transport buttons → scene B launch
  for (let i = 0; i < 8; i++) {
    inputs.push({
      type: 'pad',
      selector: `ch2.${48 + i}`,
      target: { kind: 'scene.launch', sceneId: 'scene-1' },
    });
  }

  return inputs;
}

function crossfaderInput(): MappingInput {
  return {
    type: 'fader',
    selector: 'cc8',
    target: {
      kind: 'rack.macro',
      rackId: 'jam.rack.poly-keys',
      macro: 6, // chaos = scene morph
    },
    transform: { kind: 'linear', min: 0, max: 1 },
  };
}

function jogInputs(): MappingInput[] {
  return [
    {
      type: 'knob',
      selector: 'cc33',
      target: { kind: 'transport', verb: 'nudge' as 'tap' }, // closest available verb
      transform: { kind: 'linear', min: -1, max: 1 },
    },
    {
      type: 'knob',
      selector: 'cc34',
      target: { kind: 'transport', verb: 'tap' }, // scrub
    },
    {
      type: 'knob',
      selector: 'cc35',
      target: { kind: 'transport', verb: 'tap' },
    },
    {
      type: 'knob',
      selector: 'cc36',
      target: { kind: 'transport', verb: 'tap' },
    },
  ];
}

function fxPadInputs(): MappingInput[] {
  // FX pads → gestures via macro 6/7
  return Array.from({ length: 8 }, (_, i): MappingInput => ({
    type: 'pad',
    selector: 56 + i,
    target: {
      kind: 'rack.macro',
      rackId: 'jam.rack.poly-keys',
      macro: i < 4 ? 6 : 7, // chaos / tension
    },
  }));
}

function transportInputs(): MappingInput[] {
  return [
    { type: 'transport', selector: 'cc116', target: { kind: 'transport', verb: 'play' } },
    { type: 'transport', selector: 'cc117', target: { kind: 'transport', verb: 'stop' } },
  ];
}

function ledOutputs(): MappingOutput[] {
  return [
    { type: 'led', selector: 'scene-a', source: 'scene.state', projection: 'colour' },
    { type: 'led', selector: 'scene-b', source: 'scene.state', projection: 'colour' },
  ];
}

export const RX2_PROFILE: JamboxMappingPayload = {
  name: 'Numark RX2',
  author: 'semantos-built-in',
  surfaceShape: 'dj-deck',
  inputs: [
    ...deckInputs(),
    crossfaderInput(),
    ...jogInputs(),
    ...fxPadInputs(),
    ...transportInputs(),
  ],
  outputs: ledOutputs(),
  version: '1.0.0',
  license: 'personal',
};

export const RX2_DETECT_PATTERNS = [/rx2/i, /numark/i];

```
