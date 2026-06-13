---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/render/rtc-to-roadmap.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.760106+00:00
---

# docs/canon/render/rtc-to-roadmap.ts

```ts
#!/usr/bin/env bun
/**
 * rtc-to-roadmap — render `docs/canon/rtc-matrix.yml` into the §2 matrix
 * tables that go in `docs/prd/RTC-ROADMAP.md`.
 *
 * Usage:
 *   bun docs/canon/render/rtc-to-roadmap.ts          # stdout
 *   bun docs/canon/render/rtc-to-roadmap.ts > /tmp/rtc.md
 *
 * Structure parallels matrix-to-roadmap.ts (substrate + adapters), but the
 * axes are the 10 RTC conformance dimensions A..J — PKI, Signal, ICE,
 * Media, Topo, E2EE, Meter, ShellAPI, Test, Docs. Editing a cell's status
 * in the YAML auto-flows back to the rendered roadmap; the
 * rtc-matrix-render-freshness gate enforces no drift.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import { parse as parseYaml } from 'yaml';

type CellStatus = '✓' | '⚠' | '✗' | 'n/a';

interface Cell {
  // YAML quotes the status string ("✓") because some emitters mangle the
  // bare unicode tick. The renderer accepts either.
  status: CellStatus;
  deliverable?: string;
  deliverables?: string[];
  note?: string;
}

interface Row {
  id: string;
  name: string;
  /** Row-level note (the surface's role). Not rendered into the table. */
  note?: string;
  axes: Record<string, Cell>;
}

interface MatrixDoc {
  substrate: Row[];
  adapters: Row[];
}

// Column order as declared in the RTC roadmap §2.
const AXES: readonly string[] = [
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
];

const AXIS_LABELS: Record<string, string> = {
  A: 'A. PKI',
  B: 'B. Signal',
  C: 'C. ICE',
  D: 'D. Media',
  E: 'E. Topo',
  F: 'F. E2EE',
  G: 'G. Meter',
  H: 'H. ShellAPI',
  I: 'I. Test',
  J: 'J. Docs',
};

const HERE = dirname(fileURLToPath(import.meta.url));
const CANON_DIR = resolve(HERE, '..');
const MATRIX_FILE = resolve(CANON_DIR, 'rtc-matrix.yml');

export function load(matrixFile: string = MATRIX_FILE): MatrixDoc {
  const raw = readFileSync(matrixFile, 'utf-8');
  const parsed = parseYaml(raw) as MatrixDoc | null;
  if (!parsed || typeof parsed !== 'object') {
    return { substrate: [], adapters: [] };
  }
  return {
    substrate: parsed.substrate ?? [],
    adapters: parsed.adapters ?? [],
  };
}

function renderCell(cell: Cell | undefined): string {
  if (!cell) return '—';
  const status = cell.status;

  // n/a cells often carry an explanatory note; that's row-level
  // commentary, not table-cell content. Render bare to keep tables narrow.
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

function renderTable(title: string, rows: Row[]): string {
  if (rows.length === 0) {
    return `### ${title}\n\n_No rows yet — fill \`docs/canon/rtc-matrix.yml\`._\n`;
  }
  const header = ['Surface', ...AXES.map((a) => AXIS_LABELS[a] ?? a)];
  const sep = header.map(() => '---');
  const body = rows.map((r) => {
    const cells = AXES.map((a) => renderCell(r.axes?.[a]).replace(/\|/g, '\\|'));
    return `| **${r.id} ${r.name}** | ${cells.join(' | ')} |`;
  });
  return [
    `### ${title}`,
    '',
    `| ${header.join(' | ')} |`,
    `| ${sep.join(' | ')} |`,
    ...body,
  ].join('\n');
}

/** Tally cells by status across both row groups (for the summary line). */
function tally(doc: MatrixDoc): Record<CellStatus, number> {
  const counts: Record<CellStatus, number> = {
    '✓': 0,
    '⚠': 0,
    '✗': 0,
    'n/a': 0,
  };
  for (const row of [...doc.substrate, ...doc.adapters]) {
    for (const axis of AXES) {
      const cell = row.axes?.[axis];
      if (cell && counts[cell.status] !== undefined) counts[cell.status] += 1;
    }
  }
  return counts;
}

export function emit(matrixFile?: string): string {
  const doc = load(matrixFile);
  const header = [
    '## §2. The matrix',
    '',
    '> Rendered from `docs/canon/rtc-matrix.yml`. Do not edit this section',
    '> directly — edit the YAML and re-run',
    '> `bun docs/canon/render/rtc-to-roadmap.ts`.',
    '',
  ].join('\n');

  const body = [
    renderTable(
      '§2a. Substrate (the shell-native primitives — ✓ by construction is the goal)',
      doc.substrate,
    ),
    '',
    renderTable(
      '§2b. Adapters (cartridges that import the substrate — where the work concentrates)',
      doc.adapters,
    ),
  ].join('\n');

  const c = tally(doc);
  const scored = c['✓'] + c['⚠'] + c['✗'];
  const summary = [
    '',
    '',
    '---',
    '',
    `_${doc.substrate.length} substrate rows, ${doc.adapters.length} adapter rows._`,
    `_Cells: ${c['✓']} ✓ · ${c['⚠']} ⚠ · ${c['✗']} ✗ · ${c['n/a']} n/a` +
      (scored > 0
        ? ` — ${Math.round((c['✓'] / scored) * 100)}% done, ${Math.round(
            ((c['✓'] + c['⚠']) / scored) * 100,
          )}% started (of ${scored} in-scope cells)._`
        : `._`),
    '',
  ].join('\n');

  return header + body + summary;
}

// Run as a script (not under test import).
if (import.meta.main) {
  const output = emit();
  process.stdout.write(output);
  process.stdout.write('\n');
}

```
