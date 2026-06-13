---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/launchpad.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.630728+00:00
---

# cartridges/jambox/web/src/mappings/profiles/launchpad.ts

```ts
/**
 * D-C.3 Novation Launchpad / Launchpad Mini / Launchpad X built-in profile.
 *
 * Layout:
 *   8×8 pad grid (MIDI notes 11–88, bottom-left = 11, top-right = 88)
 *   Right column (notes 19, 29, 39, 49, 59, 69, 79, 89) = scene launch
 *   Top row (CC 91–98) = mode row (Rhythm / Melody / Bass / Seq / Mix / Session / Arrange / Custom)
 *
 * Activates on detection of a device named "Launchpad*".
 */

import type { JamboxMappingPayload, MappingInput, MappingOutput } from '../../semantic/objects';

/** Launchpad Pro/X MIDI note for grid pad (row 0-7 from bottom, col 0-7 from left). */
function padNote(row: number, col: number): number {
  return (row + 1) * 10 + (col + 1); // Launchpad grid layout
}

function gridInputs(): MappingInput[] {
  const inputs: MappingInput[] = [];

  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 7; col++) {
      const note = padNote(row, col);
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
    // Right column (col 8) = scene launch (notes: 19, 29, ... 89)
    const sceneNote = (row + 1) * 10 + 9;
    inputs.push({
      type: 'pad',
      selector: sceneNote,
      target: {
        kind: 'scene.launch',
        sceneId: `scene-${row}`,
      },
    });
  }

  // Top row (CC 91-98) = mode row shortcuts
  const topRowModes: Array<import('../../semantic/objects').GridModeKind> = [
    'step', 'note', 'mix', 'param', 'session', 'arrangement', 'custom', 'global',
  ];
  for (let i = 0; i < 8; i++) {
    inputs.push({
      type: 'knob', // Launchpad sends CC for top-row buttons
      selector: `cc${91 + i}`,
      target: { kind: 'mode', mode: topRowModes[i]! },
    });
  }

  return inputs;
}

function ledOutputs(): MappingOutput[] {
  const outputs: MappingOutput[] = [];
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const note = padNote(row, col);
      outputs.push({
        type: 'led',
        selector: note,
        source: 'clip.state',
        projection: 'colour',
      });
    }
  }
  return outputs;
}

export const LAUNCHPAD_PROFILE: JamboxMappingPayload = {
  name: 'Launchpad',
  author: 'semantos-built-in',
  surfaceShape: 'launchpad',
  inputs: gridInputs(),
  outputs: ledOutputs(),
  version: '1.0.0',
  license: 'personal',
};

/** Device name patterns that match Launchpad (but not Pro). */
export const LAUNCHPAD_DETECT_PATTERNS = [
  /launchpad(?! pro)/i,
  /launchpad mini/i,
  /launchpad x/i,
];

```
