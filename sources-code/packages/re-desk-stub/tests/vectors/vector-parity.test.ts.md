---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/tests/vectors/vector-parity.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.537793+00:00
---

# packages/re-desk-stub/tests/vectors/vector-parity.test.ts

```ts
/**
 * D-O11 phase O11a — vector parity test.
 *
 * Loads `tests/vectors/re-desk_maintenance-request.json` and asserts:
 *  1. each vector's `packed` hex is byte-identical to a fresh
 *     `maintenanceRequestCellType.pack(input)` from the recorded input;
 *  2. each vector's `typeHash` matches the cell-type's typeHashHex;
 *  3. unpack(packed) round-trips back to the recorded input.
 *
 * Vector regeneration is `bun tools/gen-vectors.ts` from the package
 * root.
 */

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  maintenanceRequestCellType,
  type MaintenanceRequest,
} from '../../src/cell-types/index.js';

interface Vector {
  readonly name: string;
  readonly input: MaintenanceRequest;
  readonly packed: string;
  readonly typeHash: string;
  readonly linearity: 'LINEAR';
}

function fromHex(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) throw new Error(`odd hex length: ${hex.length}`);
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function toHex(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) {
    s += (bytes[i] as number).toString(16).padStart(2, '0');
  }
  return s;
}

const vectorsPath = resolve(
  import.meta.dir,
  're-desk_maintenance-request.json',
);
const vectors: Vector[] = JSON.parse(readFileSync(vectorsPath, 'utf8'));

describe('re-desk_maintenance-request.json conformance vectors', () => {
  test('vectors file is non-empty', () => {
    expect(vectors.length).toBeGreaterThan(0);
  });

  for (const vec of vectors) {
    test(`vector — ${vec.name}`, () => {
      // (2) typeHash matches.
      expect(vec.typeHash).toBe(maintenanceRequestCellType.typeHashHex);
      expect(vec.linearity).toBe('LINEAR');

      // (1) pack(input) byte-equals recorded packed.
      const repacked = toHex(maintenanceRequestCellType.pack(vec.input));
      expect(repacked).toBe(vec.packed);

      // (3) unpack(packed) round-trips back to input.
      const unpacked = maintenanceRequestCellType.unpack(fromHex(vec.packed));
      expect(unpacked).toEqual(vec.input);
    });
  }
});

```
