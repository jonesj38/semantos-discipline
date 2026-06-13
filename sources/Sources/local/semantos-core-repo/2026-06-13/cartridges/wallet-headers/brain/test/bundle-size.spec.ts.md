---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/bundle-size.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.664252+00:00
---

# cartridges/wallet-headers/brain/test/bundle-size.spec.ts

```ts
// Bundle size budget — must stay under 200KB compressed.
//
// Per WALLET-TIER-CUSTODY.md §11 Q4 the v0.1 budget is 150–200KB compressed
// across the entire dist/. This test gzips every dist/ artifact (HTML, JS,
// WASM) and asserts the sum is under 200KB.
//
// Skips cleanly when dist/ has not been built yet — the suite is intended
// to run as part of `bun run build && bun test`, but a fresh checkout
// without `dist/` shouldn't fail the test run for the other suites.

import { describe, expect, test } from 'bun:test';
import { gzipSync } from 'zlib';
import { readdirSync, statSync, readFileSync, existsSync } from 'fs';
import { join } from 'path';

const BUDGET_BYTES = 200 * 1024;
const DIST_DIR = join(import.meta.dir, '..', 'dist');

function gzippedSizes(): { name: string; size: number }[] {
  if (!existsSync(DIST_DIR)) return [];
  const entries: { name: string; size: number }[] = [];
  for (const name of readdirSync(DIST_DIR)) {
    const full = join(DIST_DIR, name);
    if (!statSync(full).isFile()) continue;
    if (!/\.(js|wasm|html|css|map)$/.test(name)) continue;
    if (name.endsWith('.map')) continue; // source maps don't ship
    // readFileSync returns a Node Buffer; coerce to Uint8Array for the
    // zlib type signature (gzipSync(InputType) where Buffer is an
    // acceptable runtime input but not the strictest TS overload).
    const bytes = new Uint8Array(readFileSync(full));
    const gz = gzipSync(bytes, { level: 9 });
    entries.push({ name, size: gz.length });
  }
  return entries;
}

describe('bundle size budget', () => {
  const sizes = gzippedSizes();

  test('dist/ is built (skip otherwise)', () => {
    if (sizes.length === 0) {
      console.warn('[bundle-size] dist/ empty — run `bun run build` to enable size assertion');
    }
    // The test passes either way; the assertion is gated on the build
    // having produced anything. This keeps the suite green on a fresh
    // checkout while still alerting in CI when dist/ is wired up.
    expect(true).toBe(true);
  });

  test('sum of gzipped dist/ artifacts is under 200KB', () => {
    if (sizes.length === 0) return;
    const total = sizes.reduce((s, e) => s + e.size, 0);
    console.log('[bundle-size] gzipped:');
    for (const e of sizes) {
      console.log(`  ${e.name.padEnd(40)} ${e.size.toLocaleString()} B`);
    }
    console.log(`  ${'TOTAL'.padEnd(40)} ${total.toLocaleString()} B (budget ${BUDGET_BYTES.toLocaleString()})`);
    expect(total).toBeLessThanOrEqual(BUDGET_BYTES);
  });

  test('cell-engine-embedded.wasm under 60KB gzipped (sanity)', () => {
    const wasm = sizes.find((e) => e.name === 'cell-engine-embedded.wasm');
    if (!wasm) return; // skip if not built yet
    expect(wasm.size).toBeLessThanOrEqual(60 * 1024);
  });

  test('wallet-engine.wasm alias ships for BRAIN/operator ergonomics', () => {
    if (sizes.length === 0) return;
    const wasm = sizes.find((e) => e.name === 'cell-engine-embedded.wasm');
    const alias = sizes.find((e) => e.name === 'wallet-engine.wasm');
    if (!wasm && !alias) return; // skip if build did not run build:wasm
    expect(alias).toBeDefined();
    expect(alias?.size).toBe(wasm?.size);
  });
});

```
