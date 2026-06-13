---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/render/canonicalization-to-roadmap.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.759829+00:00
---

# docs/canon/render/canonicalization-to-roadmap.ts

```ts
#!/usr/bin/env bun
/**
 * canonicalization-to-roadmap — render `docs/canon/canonicalization-matrix.yml`
 * into the §2 consolidation matrix tables that go in
 * `docs/prd/CANONICALIZATION-ROADMAP.md`.
 *
 * Usage:
 *   bun docs/canon/render/canonicalization-to-roadmap.ts
 *   bun docs/canon/render/canonicalization-to-roadmap.ts > docs/prd/CANONICALIZATION-ROADMAP.md
 *
 * Structure parallels singularity-to-roadmap.ts. Rows are the 8 canonicalization
 * tracks (C1 Primitive Forklift .. C8 Relic Archival); axes are the 10
 * conformance dimensions A..J spanning extraction, wiring, tests, brain-side,
 * PWA-side, wallet integration, recovery envelope, intent pathway, docs, and
 * legacy-code deletion.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import { parse as parseYaml } from 'yaml';

type CellStatus = '✓' | '⚠' | '✗' | 'n/a';

interface Cell {
  status: CellStatus;
  deliverable?: string;
  deliverables?: string[];
  note?: string;
}

interface Track {
  id: string;
  name: string;
  note?: string;
  axes: Record<string, Cell>;
}

interface CanonicalizationDoc {
  tracks: Track[];
}

const AXES: readonly string[] = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'];

const AXIS_LABELS: Record<string, string> = {
  A: 'A. Extract',
  B: 'B. Wired',
  C: 'C. Tests',
  D: 'D. Brain',
  E: 'E. PWA',
  F: 'F. Wallet',
  G: 'G. Recov',
  H: 'H. Intent',
  I: 'I. Docs',
  J: 'J. Deleted',
};

const HERE = dirname(fileURLToPath(import.meta.url));
const CANON_DIR = resolve(HERE, '..');
const MATRIX_FILE = resolve(CANON_DIR, 'canonicalization-matrix.yml');

export function load(matrixFile: string = MATRIX_FILE): CanonicalizationDoc {
  const raw = readFileSync(matrixFile, 'utf-8');
  const parsed = parseYaml(raw) as CanonicalizationDoc | null;
  if (!parsed || typeof parsed !== 'object') {
    return { tracks: [] };
  }
  return { tracks: parsed.tracks ?? [] };
}

function renderCell(cell: Cell | undefined): string {
  if (!cell) return '—';
  const status = cell.status;
  if (status === 'n/a') return 'n/a';
  if (cell.deliverables && cell.deliverables.length > 0) {
    return `${status} ${cell.deliverables.join(', ')}`;
  }
  if (cell.deliverable) return `${status} ${cell.deliverable}`;
  if (cell.note) {
    const brief = cell.note.length > 28 ? `${cell.note.slice(0, 25)}…` : cell.note;
    return `${status} (${brief})`;
  }
  return status;
}

function renderTable(tracks: Track[]): string {
  if (tracks.length === 0) {
    return `_No tracks yet — fill \`docs/canon/canonicalization-matrix.yml\`._\n`;
  }
  const header = ['Track', ...AXES.map((a) => AXIS_LABELS[a] ?? a)];
  const sep = header.map(() => '---');
  const body = tracks.map((t) => {
    const cells = AXES.map((a) => renderCell(t.axes?.[a]).replace(/\|/g, '\\|'));
    return `| **${t.id} ${t.name}** | ${cells.join(' | ')} |`;
  });
  return [
    `| ${header.join(' | ')} |`,
    `| ${sep.join(' | ')} |`,
    ...body,
  ].join('\n');
}

function countStatuses(tracks: Track[]): Record<CellStatus, number> {
  const counts: Record<CellStatus, number> = { '✓': 0, '⚠': 0, '✗': 0, 'n/a': 0 };
  for (const t of tracks) {
    for (const a of AXES) {
      const cell = t.axes?.[a];
      if (!cell) continue;
      const s = cell.status;
      if (s in counts) counts[s as CellStatus]++;
    }
  }
  return counts;
}

function renderLegend(): string {
  return [
    '### Axis legend',
    '',
    '- **A. Extract** — source files moved or created at target location',
    '- **B. Wired** — imports, registries, dispatch tables hooked up at target',
    '- **C. Tests** — existing test surface green in new location',
    '- **D. Brain** — companion brain-side change landed (if applicable)',
    '- **E. PWA** — companion PWA-side change landed (if applicable)',
    '- **F. Wallet** — wallet-headers/headless-wallet integration wired (C6 surface)',
    '- **G. Recov** — plexusRecoveryEnvelope coverage for the unit',
    '- **H. Intent** — gradient pipeline (SIR→OIR→opcode→kernel) flows through',
    '- **I. Docs** — CLAUDE.md / module README / canon doc updated',
    '- **J. Deleted** — zero remaining references to legacy path',
    '',
    '### Status legend',
    '',
    '- ✓ implemented, tested, verifiable',
    '- ⚠ partial / in progress / unverified',
    '- ✗ not started',
    '- n/a not applicable for this (track, axis) pair',
  ].join('\n');
}

function renderTrackNotes(tracks: Track[]): string {
  if (tracks.length === 0) return '';
  const sections = tracks.map((t) => {
    const note = (t.note ?? '').trim();
    if (!note) return `### ${t.id} ${t.name}\n\n_(no note)_`;
    return `### ${t.id} ${t.name}\n\n${note}`;
  });
  return sections.join('\n\n');
}

export function emit(matrixFile?: string): string {
  const doc = load(matrixFile);
  const counts = countStatuses(doc.tracks);

  const header = [
    '# Canonicalization Roadmap — collapsing to two canonical units',
    '',
    '> Rendered from `docs/canon/canonicalization-matrix.yml`. Do not edit this',
    '> document directly — edit the YAML and re-run',
    '> `bun docs/canon/render/canonicalization-to-roadmap.ts > docs/prd/CANONICALIZATION-ROADMAP.md`.',
    '',
    'Companion document: [`docs/prd/CANONICALIZATION-BRIEF.md`](./CANONICALIZATION-BRIEF.md).',
    '',
    '## §1. The thesis',
    '',
    'Semantos collapses into exactly **two canonical units**: a neutral PWA',
    '(`apps/semantos`) and a neutral brain (`runtime/semantos-brain`). Both',
    'ship the substrate primitives — contacts/PKI, conversation, pask,',
    'wallet-headers + headless-wallet, key REPL, gradient intent pipeline,',
    'identity + plexus recovery — and load cartridges as plugins. Together',
    'they are primed for voice→economic execution with recoverable',
    'Root-Operator onboarding.',
    '',
    'The matrix below tracks the **8 consolidation tracks × 10 conformance',
    'axes**. Each ✓ cell is a verifiable claim that the (track, axis) pair',
    'is done.',
    '',
    '## §2. The matrix',
    '',
    '',
  ].join('\n');

  const body = renderTable(doc.tracks);

  const summary = [
    '',
    '',
    `_${doc.tracks.length} tracks, ${AXES.length} axes — ` +
      `${counts['✓']} ✓ / ${counts['⚠']} ⚠ / ${counts['✗']} ✗ / ${counts['n/a']} n/a._`,
    '',
    '## §3. Legend',
    '',
    renderLegend(),
    '',
    '## §4. Track notes',
    '',
    renderTrackNotes(doc.tracks),
    '',
  ].join('\n');

  return header + body + summary;
}

if (import.meta.main) {
  const output = emit();
  process.stdout.write(output);
  process.stdout.write('\n');
}

```
