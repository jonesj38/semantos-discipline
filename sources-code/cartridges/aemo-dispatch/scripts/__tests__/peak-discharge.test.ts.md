---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/scripts/__tests__/peak-discharge.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.577632+00:00
---

# cartridges/aemo-dispatch/scripts/__tests__/peak-discharge.test.ts

```ts
// Sanity tests for the peak-discharge Rúnar predicate.
//
// These verify the local Bitcoin Script interpreter agrees with the
// invariant the .runar.go source declares.  If a future Rúnar compiler
// bump produces different bytes for the same source, this test catches
// the drift before the backtest runs against stale hex.

import { describe, it, expect } from 'bun:test';
import { promises as fs } from 'fs';
import * as path from 'path';
import { execute, pushSmallInt, hexToBytes, concat } from '../script-interpreter';

const HEX_PATH = path.join(import.meta.dir, '..', '..', 'strategies', 'peak_discharge.expected.hex');

async function loadHex(): Promise<Uint8Array> {
  const raw = await fs.readFile(HEX_PATH, 'utf-8');
  return hexToBytes(raw);
}

function decide(predicate: Uint8Array, priceCents: number, socPct: number): boolean {
  const script = concat(pushSmallInt(priceCents), pushSmallInt(socPct), predicate);
  return execute(script).ok;
}

describe('peak_discharge predicate', () => {
  it('compiled hex is exactly 9 bytes (7c023075a2690132a2)', async () => {
    const hex = await loadHex();
    expect(Array.from(hex).map(b => b.toString(16).padStart(2, '0')).join('')).toBe('7c023075a2690132a2');
    expect(hex.length).toBe(9);
  });

  it('accepts: spot $400/MWh, SoC 75%', async () => {
    const p = await loadHex();
    expect(decide(p, 40000, 75)).toBe(true);
  });

  it('accepts: spot exactly $300/MWh, SoC exactly 50% (boundaries inclusive)', async () => {
    const p = await loadHex();
    expect(decide(p, 30000, 50)).toBe(true);
  });

  it('rejects: spot $299.99/MWh (price below threshold)', async () => {
    const p = await loadHex();
    expect(decide(p, 29999, 80)).toBe(false);
  });

  it('rejects: spot $1000/MWh, SoC 49% (price above but battery near empty)', async () => {
    const p = await loadHex();
    expect(decide(p, 100000, 49)).toBe(false);
  });

  it('rejects: spot $50/MWh, SoC 100% (peak hours not active)', async () => {
    const p = await loadHex();
    expect(decide(p, 5000, 100)).toBe(false);
  });

  it('accepts: very high spot (scarcity spike $5000/MWh), SoC 60%', async () => {
    const p = await loadHex();
    expect(decide(p, 500000, 60)).toBe(true);
  });

  it('handles negative spot (curtailment): always rejects regardless of SoC', async () => {
    const p = await loadHex();
    expect(decide(p, -5000, 90)).toBe(false);
  });
});

```
