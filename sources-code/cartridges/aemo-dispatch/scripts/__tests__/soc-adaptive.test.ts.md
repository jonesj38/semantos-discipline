---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/scripts/__tests__/soc-adaptive.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.577055+00:00
---

# cartridges/aemo-dispatch/scripts/__tests__/soc-adaptive.test.ts

```ts
// Sanity tests for the SoC-adaptive Rúnar predicate.
//
// Single-line predicate: priceCents * socPct >= 2_500_000
//
// Discharge thresholds at sample SoCs (verify against intent):
//   100% SoC  → discharge at  $250/MWh  (priceCents >= 25000)
//    75% SoC  → discharge at  $333/MWh  (priceCents >= 33334)
//    50% SoC  → discharge at  $500/MWh  (priceCents >= 50000)
//    25% SoC  → discharge at $1000/MWh  (priceCents >= 100000)
//    10% SoC  → discharge at $2500/MWh  (priceCents >= 250000)

import { describe, it, expect } from 'bun:test';
import { promises as fs } from 'fs';
import * as path from 'path';
import { execute, pushSmallInt, hexToBytes, concat } from '../script-interpreter';

const HEX_PATH = path.join(import.meta.dir, '..', '..', 'strategies', 'soc_adaptive.expected.hex');

async function loadHex(): Promise<Uint8Array> {
  const raw = await fs.readFile(HEX_PATH, 'utf-8');
  return hexToBytes(raw);
}

function decide(predicate: Uint8Array, priceCents: number, socPct: number): boolean {
  const script = concat(pushSmallInt(priceCents), pushSmallInt(socPct), predicate);
  return execute(script).ok;
}

describe('soc_adaptive predicate', () => {
  it('compiled hex is exactly 6 bytes (9503a02526a2)', async () => {
    const hex = await loadHex();
    expect(Array.from(hex).map(b => b.toString(16).padStart(2, '0')).join('')).toBe('9503a02526a2');
    expect(hex.length).toBe(6);
  });

  it('full battery (100%) accepts modest peak: $250/MWh ✓', async () => {
    const p = await loadHex();
    expect(decide(p, 25000, 100)).toBe(true);
    expect(decide(p, 24999, 100)).toBe(false);
  });

  it('half battery (50%) requires double the peak: $500/MWh ✓, $499 ✗', async () => {
    const p = await loadHex();
    expect(decide(p, 50000, 50)).toBe(true);
    expect(decide(p, 49999, 50)).toBe(false);
  });

  it('quarter battery (25%) requires $1000/MWh', async () => {
    const p = await loadHex();
    expect(decide(p, 100000, 25)).toBe(true);
    expect(decide(p, 99999, 25)).toBe(false);
  });

  it('near-empty battery (10%) only fires at scarcity ($2500/MWh)', async () => {
    const p = await loadHex();
    expect(decide(p, 250000, 10)).toBe(true);
    expect(decide(p, 249999, 10)).toBe(false);
  });

  it('5% battery requires severe scarcity ($5000/MWh)', async () => {
    const p = await loadHex();
    expect(decide(p, 500000, 5)).toBe(true);
    expect(decide(p, 499999, 5)).toBe(false);
  });

  it('0% battery never fires (multiplication zero-traps)', async () => {
    const p = await loadHex();
    expect(decide(p, 1500000, 0)).toBe(false); // even $15k/MWh, empty = no
  });

  it('negative price (curtailment) never fires regardless of SoC', async () => {
    const p = await loadHex();
    // Negative * positive = negative, less than 2_500_000.
    expect(decide(p, -5000, 100)).toBe(false);
    expect(decide(p, -1, 100)).toBe(false);
  });

  it('zero price never fires', async () => {
    const p = await loadHex();
    expect(decide(p, 0, 100)).toBe(false);
  });

  it('extreme scarcity spike fires even at low SoC: $15k/MWh @ 17%', async () => {
    const p = await loadHex();
    // 1500000 * 17 = 25_500_000 >= 2_500_000 ✓
    expect(decide(p, 1500000, 17)).toBe(true);
  });
});

```
