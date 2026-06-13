---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/launchpad-pro.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.628659+00:00
---

# cartridges/jambox/web/src/mappings/profiles/launchpad-pro.ts

```ts
/**
 * D-C.3 Novation Launchpad Pro built-in profile.
 *
 * Extends the standard Launchpad profile with:
 *   - Programmer-mode SysEx for full RGB per-pad LED feedback
 *   - Scale-degree colour channel (source: 'scale.degree') via MappingOutput
 *   - Additional side buttons (left column / bottom row) for transport
 */

import type { JamboxMappingPayload, MappingInput, MappingOutput } from '../../semantic/objects';
import { LAUNCHPAD_PROFILE } from './launchpad';

function padNote(row: number, col: number): number {
  return (row + 1) * 10 + (col + 1);
}

/** Override LED outputs to use scale.degree for full RGB colouring. */
function rgbLedOutputs(): MappingOutput[] {
  const outputs: MappingOutput[] = [];
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const note = padNote(row, col);
      outputs.push({
        type: 'led',
        selector: note,
        source: 'scale.degree',   // §C.2a: full scale-channel colour
        projection: 'colour',
      });
    }
  }
  // Right column: scene state
  for (let row = 0; row < 8; row++) {
    outputs.push({
      type: 'led',
      selector: (row + 1) * 10 + 9,
      source: 'scene.state',
      projection: 'colour',
    });
  }
  return outputs;
}

/** Transport buttons on the Pro: bottom row CCs. */
function transportInputs(): MappingInput[] {
  return [
    { type: 'knob', selector: 'cc116', target: { kind: 'transport', verb: 'stop' } },
    { type: 'knob', selector: 'cc117', target: { kind: 'transport', verb: 'play' } },
    { type: 'knob', selector: 'cc119', target: { kind: 'transport', verb: 'record' } },
    { type: 'knob', selector: 'cc114', target: { kind: 'transport', verb: 'capture' } },
    { type: 'knob', selector: 'cc115', target: { kind: 'transport', verb: 'quantize' } },
  ];
}

export const LAUNCHPAD_PRO_PROFILE: JamboxMappingPayload = {
  name: 'Launchpad Pro',
  author: 'semantos-built-in',
  surfaceShape: 'launchpad',
  inputs: [
    ...LAUNCHPAD_PROFILE.inputs,
    ...transportInputs(),
  ],
  outputs: rgbLedOutputs(),
  version: '1.0.0',
  license: 'personal',
  // Declares this mapping requires chromatic permission (Pro users playing
  // in programmer mode expect full note range)
  constraints: [],
};

export const LAUNCHPAD_PRO_DETECT_PATTERNS = [/launchpad pro/i];

```
