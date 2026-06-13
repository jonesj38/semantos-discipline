---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/render/__tests__/singularity-to-roadmap.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.760477+00:00
---

# docs/canon/render/__tests__/singularity-to-roadmap.test.ts

```ts
/**
 * Regression test for `docs/canon/render/singularity-to-roadmap.ts`.
 *
 * Pins the field-access contract (rows under `layers:`, per-axis cells
 * under `axes:`) and the rendered-output shape so the same kind of
 * silent regression that hit matrix-to-roadmap pre-W1.5C-4 can't happen
 * here.
 *
 * Inputs: `docs/canon/singularity-matrix.yml` (live canon).
 */

import { describe, test, expect } from 'bun:test';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { emit, load } from '../singularity-to-roadmap';

const HERE = dirname(fileURLToPath(import.meta.url));
const MATRIX_FILE = resolve(HERE, '..', '..', 'singularity-matrix.yml');

describe('singularity-to-roadmap renderer', () => {
  test('loads singularity-matrix.yml and produces non-empty markdown', () => {
    const out = emit(MATRIX_FILE);
    expect(out.length).toBeGreaterThan(0);
    expect(out).toContain('# Singularity Roadmap');
    expect(out).toContain('## §2. The matrix');
    expect(out).toContain('## §3. Legend');
    expect(out).toContain('## §4. Layer notes');
  });

  test('loads the six canonical layers from `layers:` (not `substrate:`)', () => {
    const doc = load(MATRIX_FILE);
    expect(doc.layers.length).toBe(6);
    const ids = doc.layers.map((l) => l.id);
    expect(ids).toEqual(['L1', 'L2', 'L3', 'L4', 'L5', 'L6']);
  });

  test('reads per-axis cells from `axes:` (not `cells:`)', () => {
    const doc = load(MATRIX_FILE);
    // L3 Network transport — axis B is the Pi-over-IPv6mc U.2 substrate,
    // shipped 2026-05-21. If the field-name contract regresses, this
    // ✓ disappears.
    const l3 = doc.layers.find((l) => l.id === 'L3');
    expect(l3).toBeDefined();
    expect(l3!.axes).toBeDefined();
    expect(l3!.axes.B?.status).toBe('✓');
  });

  test('renders every layer id', () => {
    const out = emit(MATRIX_FILE);
    for (const id of ['L1', 'L2', 'L3', 'L4', 'L5', 'L6']) {
      expect(out).toContain(`**${id} `);
    }
  });

  test('renders 10-axis header in the canonical column order', () => {
    const out = emit(MATRIX_FILE);
    const expectedOrder = [
      'A. C6',
      'B. Pi',
      'C. Mac',
      'D. IPv6mc',
      'E. ESP-NOW',
      'F. Routing',
      'G. PubSub',
      'H. BSV',
      'I. Dash',
      'J. Crypto',
    ];
    let cursor = 0;
    for (const label of expectedOrder) {
      const idx = out.indexOf(label, cursor);
      expect(idx).toBeGreaterThanOrEqual(cursor);
      cursor = idx + label.length;
    }
  });

  test('renders all four canonical status glyphs (✓ ⚠ ✗ n/a)', () => {
    const out = emit(MATRIX_FILE);
    expect(out).toContain('✓');
    expect(out).toContain('⚠');
    expect(out).toContain('✗');
    expect(out).toContain('n/a');
  });

  test('renders cell deliverables next to status glyphs', () => {
    const out = emit(MATRIX_FILE);
    // L3 axis B is the headline U.2 cell — ✓ with deliverable D-SG-L3-B.
    expect(out).toContain('✓ D-SG-L3-B');
    // L5 axis A is the C6 secp256k1 cell — ✓ with D-SG-L5-A (PR #501).
    expect(out).toContain('✓ D-SG-L5-A');
  });

  test('emits a summary line counting cells by status', () => {
    const out = emit(MATRIX_FILE);
    // The summary line is `_N layers, M axes — X ✓ / Y ⚠ / Z ✗ / W n/a._`
    expect(out).toMatch(/_6 layers, 10 axes — \d+ ✓ \/ \d+ ⚠ \/ \d+ ✗ \/ \d+ n\/a\._/);
  });

  test('emits a per-layer notes section', () => {
    const out = emit(MATRIX_FILE);
    for (const id of ['L1', 'L2', 'L3', 'L4', 'L5', 'L6']) {
      // Notes section uses level-3 headers per layer.
      expect(out).toContain(`### ${id} `);
    }
  });
});

```
