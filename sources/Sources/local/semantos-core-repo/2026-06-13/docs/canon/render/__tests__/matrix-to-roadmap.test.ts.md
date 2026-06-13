---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/render/__tests__/matrix-to-roadmap.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.760755+00:00
---

# docs/canon/render/__tests__/matrix-to-roadmap.test.ts

```ts
/**
 * Regression test for `docs/canon/render/matrix-to-roadmap.ts`.
 *
 * Pre-W1.5C-4 the renderer accessed `r.cells[a]` while the canon YAML
 * declares each row's per-axis cells under `axes:` (per
 * `docs/canon/README.md#unification-matrixyml`, schema-of-record).
 * The mismatch silently produced empty tables. This test pins the
 * field-access contract and the rendered-output shape so a future
 * field rename can't regress to an empty table without flagging it.
 *
 * Inputs: `docs/canon/unification-matrix.yml` (the live canon).
 *
 * Note: the canon is a scaffold-stage import — only a subset of the
 * §2 rows from `docs/prd/UNIFICATION-ROADMAP.md` are present
 * (U3, U5 substrate; A1, A2, A3, A4, A5, A7, A8 adapters). Filling
 * the rest is tracked as a separate canon-hydration task; this test
 * verifies what's present and the renderer's structural invariants.
 */

import { describe, test, expect } from 'bun:test';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { emit, load } from '../matrix-to-roadmap';

const HERE = dirname(fileURLToPath(import.meta.url));
const MATRIX_FILE = resolve(HERE, '..', '..', 'unification-matrix.yml');

describe('matrix-to-roadmap renderer', () => {
  test('loads unification-matrix.yml and produces non-empty markdown', () => {
    const out = emit(MATRIX_FILE);
    expect(out.length).toBeGreaterThan(0);
    expect(out).toContain('## §2. The matrix');
    expect(out).toContain('§2a. Substrate');
    expect(out).toContain('§2b. Adapters');
  });

  test('reads each row\'s per-axis cells from `axes:` (not `cells:`)', () => {
    // Load directly via the renderer's loader; spot-check a row whose
    // axes-block is non-empty in canon. If the renderer ever regresses
    // back to `r.cells[a]`, every cell renders as `—` and the assertion
    // on the actual deliverable id fails.
    const doc = load(MATRIX_FILE);
    const u3 = doc.substrate.find((r) => r.id === 'U3');
    expect(u3).toBeDefined();
    expect(u3!.axes).toBeDefined();
    expect(u3!.axes.A?.status).toBe('✓');

    const a1 = doc.adapters.find((r) => r.id === 'A1');
    expect(a1).toBeDefined();
    expect(a1!.axes).toBeDefined();
  });

  test('renders the substrate row ids that are present in canon', () => {
    // Canon currently holds U3 and U5 (per scaffold stage). Filling
    // U1, U2, U4, U6-U10 is a separate canon-hydration task. When that
    // lands, this list extends; the test still passes for the present rows.
    const out = emit(MATRIX_FILE);
    const presentSubstrateIds = ['U3', 'U5'];
    for (const id of presentSubstrateIds) {
      expect(out).toContain(`**${id} `);
    }
  });

  test('renders the adapter row ids that are present in canon', () => {
    // Canon currently holds A1, A2, A3, A4, A5, A7, A8 (A6 absent —
    // Settlement was mostly-✓ in §2 and not yet imported). Filling A6
    // is a separate canon-hydration task.
    const out = emit(MATRIX_FILE);
    const presentAdapterIds = ['A1', 'A2', 'A3', 'A4', 'A5', 'A7', 'A8'];
    for (const id of presentAdapterIds) {
      expect(out).toContain(`**${id} `);
    }
  });

  test('renders all four canonical status glyphs (✓ ⚠ ✗ n/a)', () => {
    // Post-Wave-1.5 the matrix has all four — A's are ✓, B/C/D-lex are
    // ⚠, F/G are ✗, D-form is n/a in many adapters. Pin the
    // status-glyph rendering so a future renderer change that drops
    // (say) n/a falls over here.
    const out = emit(MATRIX_FILE);
    expect(out).toContain('✓');
    expect(out).toContain('⚠');
    expect(out).toContain('✗');
    expect(out).toContain('n/a');
  });

  test('renders 10-axis header in the canonical column order', () => {
    const out = emit(MATRIX_FILE);
    // Header line includes all ten axes in the §2 order.
    const expectedOrder = [
      'A. Identity',
      'B. Storage',
      'C. Transport',
      'D-sub',
      'D-lex',
      'D-form',
      'D-cap',
      'E. Time',
      'F. Recovery',
      'G. Metering',
    ];
    let cursor = 0;
    for (const label of expectedOrder) {
      const idx = out.indexOf(label, cursor);
      expect(idx).toBeGreaterThanOrEqual(cursor);
      cursor = idx + label.length;
    }
  });

  test('cell with deliverable renders status + deliverable id', () => {
    const out = emit(MATRIX_FILE);
    // A1 axis A is ✓ with deliverables [D-V3, D-A1]; the renderer takes
    // the first when `deliverables:` (plural) is used. A2 axis A is
    // ✓ D-A2 (singular `deliverable:`).
    expect(out).toContain('✓ D-A2');
    expect(out).toContain('✓ D-A5');
    expect(out).toContain('✓ D-A6');
    expect(out).toContain('✓ D-A7');
  });
});

```
