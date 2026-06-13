---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/render/matrix-to-roadmap.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.759563+00:00
---

# docs/canon/render/matrix-to-roadmap.ts

```ts
#!/usr/bin/env bun
/**
 * matrix-to-roadmap — render `docs/canon/unification-matrix.yml` into
 * the §2 matrix tables that go in
 * `docs/prd/SEMANTOS-UNIFICATION-ROADMAP.md`.
 *
 * Usage:
 *   bun docs/canon/render/matrix-to-roadmap.ts          # stdout
 *   bun docs/canon/render/matrix-to-roadmap.ts > /tmp/matrix.md
 *
 * Stage: minimal-but-working stub. Reads the canon, emits §2a (substrate)
 * + §2b (adapters) tables. Empty canon yields a "no rows yet" placeholder.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import { parse as parseYaml } from 'yaml';

type CellStatus = '✓' | '⚠' | '✗' | 'n/a';

interface Cell {
  // YAML quotes the status string ("✓") because some YAML emitters mangle
  // the bare unicode tick. The renderer accepts either.
  status: CellStatus;
  deliverable?: string;
  deliverables?: string[];
  note?: string;
}

interface Row {
  id: string;
  name: string;
  /**
   * Optional row-level note explaining the surface's role / overall state.
   * Not rendered into the table (rows are tight); used by future renderers
   * that want to emit per-row commentary.
   */
  note?: string;
  axes: Record<string, Cell>;
}

interface MatrixDoc {
  substrate: Row[];
  adapters: Row[];
}

// Column order as declared in the unification roadmap §2.
const AXES: readonly string[] = [
  'A',
  'B',
  'C',
  'D-sub',
  'D-lex',
  'D-form',
  'D-cap',
  'E',
  'F',
  'G',
];

const AXIS_LABELS: Record<string, string> = {
  A: 'A. Identity',
  B: 'B. Storage',
  C: 'C. Transport',
  'D-sub': 'D-sub',
  'D-lex': 'D-lex',
  'D-form': 'D-form',
  'D-cap': 'D-cap',
  E: 'E. Time',
  F: 'F. Recovery',
  G: 'G. Metering',
};

const HERE = dirname(fileURLToPath(import.meta.url));
const CANON_DIR = resolve(HERE, '..');
const MATRIX_FILE = resolve(CANON_DIR, 'unification-matrix.yml');

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

  // n/a cells often carry an explanatory note ("not applicable because...");
  // that's row-level commentary, not table-cell content. Render bare to keep
  // the table readable.
  if (status === 'n/a') return 'n/a';

  // Prefer the deliverable list — show all entries so a viewer can see the
  // full provenance of the axis (e.g. "CC5.B1, CC5.B2a, CC5.B2b, CC6.2"
  // documents the schema-spine + CC6 ingest landing on the same row's B axis).
  // CC6.4 — was previously truncated to deliverables[0]; switched to a join
  // because the truncation hid CC6 landing on U11 axes B and C. The plural
  // `deliverables:` carries chronological provenance; the singular
  // `deliverable:` is the single-deliverable case (one entry, same shape).
  if (cell.deliverables && cell.deliverables.length > 0) {
    return `${status} ${cell.deliverables.join(', ')}`;
  }
  if (cell.deliverable) return `${status} ${cell.deliverable}`;
  if (cell.note) {
    // Truncate prose notes to keep cells narrow; full note still lives in
    // the YAML for downstream consumers.
    const brief = cell.note.length > 28 ? `${cell.note.slice(0, 25)}…` : cell.note;
    return `${status} (${brief})`;
  }
  return status;
}

function firstLine(s: string): string {
  const line = s.split('\n', 1)[0]?.trim() ?? '';
  return line.length > 60 ? `${line.slice(0, 57)}...` : line;
}

function renderTable(title: string, rows: Row[]): string {
  if (rows.length === 0) {
    return `### ${title}\n\n_No rows yet — fill \`docs/canon/unification-matrix.yml\`._\n`;
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

export function emit(matrixFile?: string): string {
  const doc = load(matrixFile);
  const header = [
    '## §2. The matrix',
    '',
    '> Rendered from `docs/canon/unification-matrix.yml`. Do not edit this',
    '> section directly — edit the YAML and re-run',
    '> `bun docs/canon/render/matrix-to-roadmap.ts`.',
    '',
  ].join('\n');

  const body = [
    renderTable('§2a. Substrate (✓ by construction is the goal)', doc.substrate),
    '',
    renderTable('§2b. Adapters (consumers — where the work concentrates)', doc.adapters),
  ].join('\n');

  const summary = [
    '',
    '',
    '---',
    '',
    `_${doc.substrate.length} substrate rows, ${doc.adapters.length} adapter rows._`,
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
