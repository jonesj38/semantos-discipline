---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/render/singularity-to-roadmap.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.758240+00:00
---

# docs/canon/render/singularity-to-roadmap.ts

```ts
#!/usr/bin/env bun
/**
 * singularity-to-roadmap — render `docs/canon/singularity-matrix.yml` into
 * the §2 layer-collapse matrix tables that go in
 * `docs/prd/SINGULARITY-ROADMAP.md`.
 *
 * Usage:
 *   bun docs/canon/render/singularity-to-roadmap.ts          # stdout
 *   bun docs/canon/render/singularity-to-roadmap.ts > /tmp/sg.md
 *
 * Structure parallels matrix-to-roadmap.ts, but the rows are 6 layers
 * (L1 Storage .. L6 Money) and the axes are 10 conformance dimensions
 * A..J spanning the three hardware classes, two radio transports, the
 * routing & overlay regions, the chain anchor, the dashboard, and the
 * crypto-invariants axis.
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

interface Layer {
  id: string;
  name: string;
  note?: string;
  axes: Record<string, Cell>;
}

interface SingularityDoc {
  layers: Layer[];
}

const AXES: readonly string[] = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'];

const AXIS_LABELS: Record<string, string> = {
  A: 'A. C6',
  B: 'B. Pi',
  C: 'C. Mac',
  D: 'D. IPv6mc',
  E: 'E. ESP-NOW',
  F: 'F. Routing',
  G: 'G. PubSub',
  H: 'H. BSV',
  I: 'I. Dash',
  J: 'J. Crypto',
};

const HERE = dirname(fileURLToPath(import.meta.url));
const CANON_DIR = resolve(HERE, '..');
const MATRIX_FILE = resolve(CANON_DIR, 'singularity-matrix.yml');

export function load(matrixFile: string = MATRIX_FILE): SingularityDoc {
  const raw = readFileSync(matrixFile, 'utf-8');
  const parsed = parseYaml(raw) as SingularityDoc | null;
  if (!parsed || typeof parsed !== 'object') {
    return { layers: [] };
  }
  return { layers: parsed.layers ?? [] };
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

function renderTable(layers: Layer[]): string {
  if (layers.length === 0) {
    return `_No layers yet — fill \`docs/canon/singularity-matrix.yml\`._\n`;
  }
  const header = ['Layer', ...AXES.map((a) => AXIS_LABELS[a] ?? a)];
  const sep = header.map(() => '---');
  const body = layers.map((l) => {
    const cells = AXES.map((a) => renderCell(l.axes?.[a]).replace(/\|/g, '\\|'));
    return `| **${l.id} ${l.name}** | ${cells.join(' | ')} |`;
  });
  return [
    `| ${header.join(' | ')} |`,
    `| ${sep.join(' | ')} |`,
    ...body,
  ].join('\n');
}

function countStatuses(layers: Layer[]): Record<CellStatus, number> {
  const counts: Record<CellStatus, number> = { '✓': 0, '⚠': 0, '✗': 0, 'n/a': 0 };
  for (const l of layers) {
    for (const a of AXES) {
      const cell = l.axes?.[a];
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
    '- **A. C6** — ESP32-C6 ($4, 160 MHz RISC-V, 512 KB SRAM, ESP-NOW radio)',
    '- **B. Pi** — Orange Pi Prime H5 ($5, 1 GHz Cortex-A53 quad, 2 GB RAM)',
    '- **C. Mac** — MacBook (M-series Apple Silicon, operator-class)',
    '- **D. IPv6mc** — IPv6 multicast transport (ff15::5e:1, U.2 substrate)',
    '- **E. ESP-NOW** — ESP-NOW radio broadcast between C6s',
    '- **F. Routing** — Type-path source routing via routing region in cell header',
    '- **G. PubSub** — Paid publish/subscribe overlay (relays advertise subscriber sets)',
    '- **H. BSV** — Pushdrop UTXO + on-chain anchoring + nLockTime refund txs',
    '- **I. Dash** — Dashboard / observability surface',
    '- **J. Crypto** — Crypto invariants (secp256k1, HMAC, BCA derivation)',
    '',
    '### Status legend',
    '',
    '- ✓ implemented, tested, verifiable',
    '- ⚠ partial / in progress / unverified',
    '- ✗ not started',
    '- n/a not applicable for this (layer, axis) pair',
  ].join('\n');
}

function renderLayerNotes(layers: Layer[]): string {
  if (layers.length === 0) return '';
  const sections = layers.map((l) => {
    const note = (l.note ?? '').trim();
    if (!note) return `### ${l.id} ${l.name}\n\n_(no note)_`;
    return `### ${l.id} ${l.name}\n\n${note}`;
  });
  return sections.join('\n\n');
}

export function emit(matrixFile?: string): string {
  const doc = load(matrixFile);
  const counts = countStatuses(doc.layers);

  const header = [
    '# Singularity Roadmap — the layer-collapse demo matrix',
    '',
    '> Rendered from `docs/canon/singularity-matrix.yml`. Do not edit this',
    '> document directly — edit the YAML and re-run',
    '> `bun docs/canon/render/singularity-to-roadmap.ts > docs/prd/SINGULARITY-ROADMAP.md`.',
    '',
    'Companion document: [`docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md`](./MNCA-LAYER-COLLAPSE-BRIEF.md).',
    '',
    '## §1. The thesis',
    '',
    'One 1024-byte canonical cell traverses every system layer — storage,',
    'memory, network transport, compute, identity, money — on three hardware',
    'classes (ESP32-C6, Orange Pi Prime H5, MacBook), without ever being',
    'decoded into a different representation. The matrix below tracks the',
    '**6 layers × 10 conformance axes**; each ✓ cell is a verifiable claim',
    'that the layer-collapse thesis holds for that (layer, axis) pair.',
    '',
    '## §2. The matrix',
    '',
    '',
  ].join('\n');

  const body = renderTable(doc.layers);

  const summary = [
    '',
    '',
    `_${doc.layers.length} layers, ${AXES.length} axes — ` +
      `${counts['✓']} ✓ / ${counts['⚠']} ⚠ / ${counts['✗']} ✗ / ${counts['n/a']} n/a._`,
    '',
    '## §3. Legend',
    '',
    renderLegend(),
    '',
    '## §4. Layer notes',
    '',
    renderLayerNotes(doc.layers),
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
