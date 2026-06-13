---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/cc6-4-matrix-render-freshness.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.578074+00:00
---

# tests/gates/cc6-4-matrix-render-freshness.test.ts

```ts
/**
 * CC6.4 — Unification-matrix renderer freshness gate.
 *
 * Per `docs/design/CC6-SOURCE-ADAPTER-IMPL-SPEC.md` §6 row CC6.4:
 *
 *   > Matrix row columns via renderer-in-loop; spec status → DONE
 *   > generated; no hand-edit of `unification-matrix.yml`; roadmap
 *   > regenerates
 *
 * The renderer-in-loop discipline: `docs/canon/unification-matrix.yml`
 * is the source of truth. `docs/canon/render/matrix-to-roadmap.ts`
 * renders it into the §2 tables that live in
 * `docs/prd/UNIFICATION-ROADMAP.md`. The rendered block in the roadmap
 * is bounded by `<!-- GENERATED:matrix-start ... -->` and
 * `<!-- GENERATED:matrix-end -->` markers; this gate re-runs the
 * renderer at test-time and asserts the marker contents match.
 *
 * If this test fails the workflow is:
 *
 *   1. Inspect the diff. If the YAML moved correctly and the roadmap
 *      block is stale, run `bun docs/canon/render/matrix-to-roadmap.ts
 *      > /tmp/matrix.md` and paste the output between the markers.
 *   2. If the YAML moved unexpectedly (e.g. an accidental hand-edit),
 *      revert that hand-edit and re-run.
 *
 * This gate enforces the discipline mechanically — no quiet drift
 * between the canon YAML and the rendered roadmap section.
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { emit } from '../../docs/canon/render/matrix-to-roadmap';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const ROADMAP_FILE = resolve(ROOT, 'docs/prd/UNIFICATION-ROADMAP.md');
const MATRIX_FILE = resolve(ROOT, 'docs/canon/unification-matrix.yml');

const MARKER_START = '<!-- GENERATED:matrix-start';
const MARKER_END = '<!-- GENERATED:matrix-end -->';

function extractGeneratedBlock(roadmap: string): string {
  const startIdx = roadmap.indexOf(MARKER_START);
  expect(startIdx).toBeGreaterThan(-1);
  // The start marker has parenthetical content after the prefix — skip past
  // the closing `-->` to find where the generated body begins.
  const startMarkerEnd = roadmap.indexOf('-->', startIdx);
  expect(startMarkerEnd).toBeGreaterThan(-1);
  const bodyStart = startMarkerEnd + '-->'.length;
  const endIdx = roadmap.indexOf(MARKER_END, bodyStart);
  expect(endIdx).toBeGreaterThan(-1);
  return roadmap.slice(bodyStart, endIdx);
}

describe('CC6.4 — unification-matrix render freshness gate', () => {
  test('markers are present in the roadmap', () => {
    const roadmap = readFileSync(ROADMAP_FILE, 'utf-8');
    expect(roadmap).toContain(MARKER_START);
    expect(roadmap).toContain(MARKER_END);
  });

  test('§2 generated block matches the live renderer output (drift detector)', () => {
    const roadmap = readFileSync(ROADMAP_FILE, 'utf-8');
    const checkedIn = extractGeneratedBlock(roadmap);

    // Re-run the renderer at test-time. `emit` reads
    // `docs/canon/unification-matrix.yml` from the canonical path (the
    // module computes its own location); we pass MATRIX_FILE explicitly
    // for robustness against worktree relocation.
    const fresh = emit(MATRIX_FILE);

    // The roadmap embeds the renderer output between an inner HTML comment
    // (the "do not edit" instruction) and the closing marker. The
    // explanatory comment we wrap around the renderer output for human
    // readers lives BETWEEN the start-marker and the renderer's own header.
    // Strip a tolerated leading-whitespace differential by normalising
    // line endings and comparing the renderer's body verbatim.
    const checkedInBody = checkedIn.replace(/^[\s\S]*?(?=## §2\. The matrix)/, '');
    const freshBody = fresh.replace(/^[\s\S]*?(?=## §2\. The matrix)/, '');
    expect(checkedInBody.trim()).toBe(freshBody.trim());
  });

  test('U11 axes B and C cite CC6.2 in the rendered output (CC6 closure visible)', () => {
    // Belt-and-braces: even if the equality check above somehow shifts
    // semantics, the load-bearing claim of CC6.4 — that U11 axes B and C
    // visibly cite CC6.2 deliverable in the rendered matrix — is pinned
    // separately. If this assertion ever fails, the U11 row YAML has
    // drifted away from acknowledging CC6's deliverables.
    const fresh = emit(MATRIX_FILE);
    // U11 axis B includes the CC5 trio AND CC6.2.
    expect(fresh).toContain('✓ CC5.B1, CC5.B2a, CC5.B2b, CC6.2');
    // U11 axis C includes verb-dispatch lineage AND CC6.2 (configs-as-intents).
    expect(fresh).toContain('✓ CC0, CC2, DLO.1c, CC6.2');
  });
});

```
