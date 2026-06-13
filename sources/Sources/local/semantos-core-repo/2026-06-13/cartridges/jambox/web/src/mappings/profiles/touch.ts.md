---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/touch.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.630440+00:00
---

# cartridges/jambox/web/src/mappings/profiles/touch.ts

```ts
/**
 * D-C.3 Touch / pointer built-in profile.
 *
 * Maps pointer/touch events to 8×8 pad presses.
 * The pointer-touch adapter emits pad.on/pad.off with pad index as selector.
 *
 * Touch is always loaded (default profile).
 */

import type { JamboxMappingPayload, MappingInput } from '../../semantic/objects';

function padInputs(): MappingInput[] {
  const inputs: MappingInput[] = [];
  for (let i = 0; i < 64; i++) {
    const row = Math.floor(i / 8);
    const col = i % 8;
    inputs.push({
      type: 'pad',
      selector: i,
      target: {
        kind: 'rack.trigger',
        rackId: 'jam.rack.drum-808',
        voiceId: `pad${i}`,
      },
    });
    // XY per pad
    inputs.push({
      type: 'xy',
      selector: `xy.pad${i}`,
      target: {
        kind: 'rack.macro',
        rackId: 'jam.rack.poly-keys',
        macro: row < 4 ? 0 : 1, // top half → brightness, bottom half → wobble
      },
      transform: { kind: 'linear', min: 0, max: 1 },
    });
    void col; // col used for layout only
  }
  return inputs;
}

export const TOUCH_PROFILE: JamboxMappingPayload = {
  name: 'Touch / Pointer',
  author: 'semantos-built-in',
  surfaceShape: 'touch',
  inputs: padInputs(),
  outputs: [],
  version: '1.0.0',
  license: 'personal',
};

```
