---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/geometry-pass.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.349926+00:00
---

# runtime/intent/src/reducer/geometry-pass.ts

```ts
/**
 * I-6 — Quadrivium pass 2: Geometry.
 *
 * Maps location fields → taxonomy.where + spatial constraints.
 *
 * The geometry pass resolves the spatial coordinate from suburb, location,
 * and any geo-tagged facts. It does not call an external geocoder —
 * it composes a `where` string from available text signals and relies
 * on downstream taxonomy resolution to map it to a canonical node.
 */

import type { PassFn, PassResult } from './types';

export const geometryPass: PassFn = async (accumulated, ctx): Promise<PassResult> => {
  const { state } = ctx;
  const flags: string[] = [];

  // Build where coordinate from best available location signal
  let where: string | undefined;
  let confidence = 0.4;

  if (state.location) {
    where = normaliseLocation(state.location);
    confidence = 0.8;
  } else if (state.suburb) {
    where = `suburb.${normaliseLocation(state.suburb)}`;
    confidence = 0.65;
  }

  if (!where) {
    flags.push('geometry: no location signal present; where coordinate omitted');
    confidence = 1.0; // vacuously satisfied — no location to get wrong
  }

  return {
    pass: 'geometry',
    contribution: {
      taxonomy: {
        what: accumulated.taxonomy?.what ?? '',
        how: accumulated.taxonomy?.how ?? '',
        why: accumulated.taxonomy?.why ?? '',
        ...(where ? { where } : {}),
      },
    },
    confidence,
    flags,
  };
};

function normaliseLocation(raw: string): string {
  return raw
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-');
}

```
