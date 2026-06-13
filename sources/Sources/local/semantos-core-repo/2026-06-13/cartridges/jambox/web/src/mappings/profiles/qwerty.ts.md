---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/qwerty.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.629856+00:00
---

# cartridges/jambox/web/src/mappings/profiles/qwerty.ts

```ts
/**
 * D-C.3 QWERTY keyboard built-in profile.
 *
 * Layout (matches instruments/keys.ts keyboard layout + Phase B mode shortcuts):
 *   Z–M (12 keys) = bottom row of Note mode (scale degrees 0-11)
 *   A–L (8 keys)  = upper row (scale degrees 12-19)
 *   1–8           = mode shortcuts (Alt+1/2/3 for L2 buttons; kept compatible)
 *   [ / ]         = octave down / up
 *
 * QWERTY is always loaded (default profile).
 */

import type { JamboxMappingPayload, MappingInput } from '../../semantic/objects';

const LOWER_KEYS = ['z','s','x','d','c','v','g','b','h','n','j','m'] as const;
const UPPER_KEYS = ['a','q','w','e','r','t','y','u','i','o','p','l'] as const;

function noteInputs(): MappingInput[] {
  const inputs: MappingInput[] = [];

  // Bottom row: Z–M → rack.note (scale degree encoded as value via selector)
  for (let i = 0; i < LOWER_KEYS.length; i++) {
    inputs.push({
      type: 'key',
      selector: LOWER_KEYS[i]!,
      target: {
        kind: 'rack.note',
        rackId: 'jam.rack.poly-keys',
      },
      // Transform: map key index to MIDI note (relative — the router adds root + octave)
      transform: {
        kind: 'linear',
        min: i / 127,
        max: i / 127,
      },
    });
  }

  // Upper row: A–L → rack.note
  for (let i = 0; i < UPPER_KEYS.length; i++) {
    inputs.push({
      type: 'key',
      selector: UPPER_KEYS[i]!,
      target: {
        kind: 'rack.note',
        rackId: 'jam.rack.poly-keys',
      },
      transform: {
        kind: 'linear',
        min: (i + 12) / 127,
        max: (i + 12) / 127,
      },
    });
  }

  // Mode shortcuts 1–3 (non-Alt; Alt+1/2/3 is handled by mode-row.ts)
  // We map to mode targets; the router will call surface.setMode
  const modeKeys: Array<[string, import('../../semantic/objects').GridModeKind]> = [
    ['1', 'step'],
    ['2', 'note'],
    ['3', 'mix'],
    ['4', 'session'],
    ['5', 'arrangement'],
  ];
  for (const [key, mode] of modeKeys) {
    inputs.push({
      type: 'key',
      selector: key,
      target: { kind: 'mode', mode },
    });
  }

  // Octave: treated as transport-style control
  inputs.push({
    type: 'key',
    selector: '[',
    target: { kind: 'transport', verb: 'undo' }, // placeholder: router handles octave via notes
  });
  inputs.push({
    type: 'key',
    selector: ']',
    target: { kind: 'transport', verb: 'redo' },
  });

  return inputs;
}

export const QWERTY_PROFILE: JamboxMappingPayload = {
  name: 'QWERTY Keyboard',
  author: 'semantos-built-in',
  surfaceShape: 'qwerty',
  inputs: noteInputs(),
  outputs: [],
  version: '1.0.0',
  license: 'personal',
};

```
