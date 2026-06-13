---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/scripts/__tests__/new-strategies.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.577348+00:00
---

# cartridges/aemo-dispatch/scripts/__tests__/new-strategies.test.ts

```ts
// Sanity tests for scarcity_only, band_discharge, soc_quadratic.
// Golden hex assertions catch Rúnar codegen drift; behaviour
// assertions cover the named thresholds from each strategy's
// doc-comment.

import { describe, it, expect } from 'bun:test';
import { promises as fs } from 'fs';
import * as path from 'path';
import { execute, pushSmallInt, hexToBytes, concat } from '../script-interpreter';

const STRAT_DIR = path.join(import.meta.dir, '..', '..', 'strategies');

async function loadHex(name: string): Promise<Uint8Array> {
  return hexToBytes(await fs.readFile(path.join(STRAT_DIR, `${name}.expected.hex`), 'utf-8'));
}

function decide(predicate: Uint8Array, priceCents: number, socPct: number): boolean {
  return execute(concat(pushSmallInt(priceCents), pushSmallInt(socPct), predicate)).ok;
}

describe('scarcity_only', () => {
  it('golden hex = 7c03a08601a2690114a2', async () => {
    const h = await loadHex('scarcity_only');
    expect(Array.from(h).map(b => b.toString(16).padStart(2, '0')).join('')).toBe('7c03a08601a2690114a2');
  });
  it('rejects $999/MWh @ 80% SoC (below scarcity threshold)', async () => {
    const p = await loadHex('scarcity_only');
    expect(decide(p, 99900, 80)).toBe(false);
  });
  it('accepts exactly $1000/MWh @ 20% SoC (boundary)', async () => {
    const p = await loadHex('scarcity_only');
    expect(decide(p, 100000, 20)).toBe(true);
  });
  it('rejects $5000/MWh @ 19% SoC (SoC floor)', async () => {
    const p = await loadHex('scarcity_only');
    expect(decide(p, 500000, 19)).toBe(false);
  });
  it('accepts severe scarcity $15000/MWh @ 50% SoC', async () => {
    const p = await loadHex('scarcity_only');
    expect(decide(p, 1500000, 50)).toBe(true);
  });
});

describe('band_discharge', () => {
  it('golden hex = 7c02204ea2690128a2', async () => {
    const h = await loadHex('band_discharge');
    expect(Array.from(h).map(b => b.toString(16).padStart(2, '0')).join('')).toBe('7c02204ea2690128a2');
  });
  it('accepts $200/MWh @ 40% SoC (boundary)', async () => {
    const p = await loadHex('band_discharge');
    expect(decide(p, 20000, 40)).toBe(true);
  });
  it('rejects $199.99/MWh @ 80% SoC', async () => {
    const p = await loadHex('band_discharge');
    expect(decide(p, 19999, 80)).toBe(false);
  });
  it('rejects $500/MWh @ 39% SoC (SoC floor)', async () => {
    const p = await loadHex('band_discharge');
    expect(decide(p, 50000, 39)).toBe(false);
  });
});

describe('soc_quadratic', () => {
  it('golden hex = 7c78957c95040065cd1da2', async () => {
    const h = await loadHex('soc_quadratic');
    expect(Array.from(h).map(b => b.toString(16).padStart(2, '0')).join('')).toBe('7c78957c95040065cd1da2');
  });
  it('100% SoC: accepts $500/MWh exactly', async () => {
    const p = await loadHex('soc_quadratic');
    // 50000 × 100 × 100 = 500_000_000 ✓
    expect(decide(p, 50000, 100)).toBe(true);
    expect(decide(p, 49999, 100)).toBe(false);
  });
  it('50% SoC: requires $2000/MWh', async () => {
    const p = await loadHex('soc_quadratic');
    // 200000 × 50 × 50 = 500_000_000 ✓
    expect(decide(p, 200000, 50)).toBe(true);
    expect(decide(p, 199999, 50)).toBe(false);
  });
  it('10% SoC: requires $50000/MWh (essentially never)', async () => {
    const p = await loadHex('soc_quadratic');
    // 5_000_000 × 10 × 10 = 500_000_000 ✓
    expect(decide(p, 5000000, 10)).toBe(true);
    expect(decide(p, 4999999, 10)).toBe(false);
  });
  it('0% SoC: never fires (multiplication zero-traps)', async () => {
    const p = await loadHex('soc_quadratic');
    expect(decide(p, 9999999, 0)).toBe(false);
  });
});

```
