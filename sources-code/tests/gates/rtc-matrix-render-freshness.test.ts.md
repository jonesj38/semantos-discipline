---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/rtc-matrix-render-freshness.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.584724+00:00
---

# tests/gates/rtc-matrix-render-freshness.test.ts

```ts
/**
 * RTC-matrix renderer freshness gate.
 *
 * The renderer-in-loop discipline (parallel to the CC6.4 unification gate):
 * `docs/canon/rtc-matrix.yml` is the source of truth.
 * `docs/canon/render/rtc-to-roadmap.ts` renders it into the §2 tables that
 * live in `docs/prd/RTC-ROADMAP.md`. The rendered block is bounded by
 * `<!-- GENERATED:matrix-start ... -->` and `<!-- GENERATED:matrix-end -->`
 * markers; this gate re-runs the renderer at test-time and asserts the
 * marker contents match — no quiet drift between the canon YAML and the
 * rendered roadmap section.
 *
 * If this test fails:
 *   1. If the YAML moved correctly and the roadmap block is stale, run
 *      `bun docs/canon/render/rtc-to-roadmap.ts > /tmp/rtc.md` and paste the
 *      output between the markers.
 *   2. If the YAML moved unexpectedly (an accidental hand-edit), revert it.
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { emit } from '../../docs/canon/render/rtc-to-roadmap';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const ROADMAP_FILE = resolve(ROOT, 'docs/prd/RTC-ROADMAP.md');
const MATRIX_FILE = resolve(ROOT, 'docs/canon/rtc-matrix.yml');

const MARKER_START = '<!-- GENERATED:matrix-start';
const MARKER_END = '<!-- GENERATED:matrix-end -->';

function extractGeneratedBlock(roadmap: string): string {
  const startIdx = roadmap.indexOf(MARKER_START);
  expect(startIdx).toBeGreaterThan(-1);
  // The start marker has parenthetical content after the prefix; skip past
  // the closing `-->` to find where the generated body begins.
  const startMarkerEnd = roadmap.indexOf('-->', startIdx);
  expect(startMarkerEnd).toBeGreaterThan(-1);
  const bodyStart = startMarkerEnd + '-->'.length;
  const endIdx = roadmap.indexOf(MARKER_END, bodyStart);
  expect(endIdx).toBeGreaterThan(-1);
  return roadmap.slice(bodyStart, endIdx);
}

describe('RTC-matrix render freshness gate', () => {
  test('markers are present in the roadmap', () => {
    const roadmap = readFileSync(ROADMAP_FILE, 'utf-8');
    expect(roadmap).toContain(MARKER_START);
    expect(roadmap).toContain(MARKER_END);
  });

  test('§2 generated block matches the live renderer output (drift detector)', () => {
    const roadmap = readFileSync(ROADMAP_FILE, 'utf-8');
    const checkedIn = extractGeneratedBlock(roadmap);
    const fresh = emit(MATRIX_FILE);

    // The embedded block carries an inner "do not edit" HTML comment before
    // the renderer's own `## §2. The matrix` header; compare from that header
    // onward so the human-facing wrapper comment is ignored.
    const checkedInBody = checkedIn.replace(/^[\s\S]*?(?=## §2\. The matrix)/, '');
    const freshBody = fresh.replace(/^[\s\S]*?(?=## §2\. The matrix)/, '');
    expect(checkedInBody.trim()).toBe(freshBody.trim());
  });

  test('the shell-native primitive thesis is pinned in the rendered output', () => {
    // Belt-and-braces: the load-bearing claim of this matrix — that calling
    // is a shell-native primitive cartridges import (S7), not a cartridge —
    // must be visible in the rendered matrix. If S7's ShellAPI cell ever
    // loses its deliverable, this fails.
    const fresh = emit(MATRIX_FILE);
    expect(fresh).toContain('S7 Shell RTC API (rtc/index.ts)');
    expect(fresh).toContain('D-RTC-S7-H');
  });
});

```
