---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/render/svelte-helm-to-roadmap.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.758769+00:00
---

# docs/canon/render/svelte-helm-to-roadmap.ts

```ts
#!/usr/bin/env bun
/**
 * svelte-helm-to-roadmap — render `docs/canon/svelte-helm-matrix.yml` into a
 * status roadmap at `docs/prd/SVELTE-HELM-ROADMAP.md` (SH13).
 *
 * Usage:
 *   bun docs/canon/render/svelte-helm-to-roadmap.ts > docs/prd/SVELTE-HELM-ROADMAP.md
 *
 * Parallels canonicalization-to-roadmap.ts but scoped to the SVELTE-HELM
 * pipeline: rows are tracks (SH0..SH14), columns are axes A..J.
 */

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse as parseYaml } from 'yaml';

type CellStatus = '✓' | '⚠' | '✗' | 'n/a';
interface Cell { status: CellStatus; deliverable?: string; note?: string }
interface Track { id: string; name: string; axes: Record<string, Cell>; done_when?: string }
interface Doc { tracks: Track[] }

const AXES = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'] as const;

const here = dirname(fileURLToPath(import.meta.url));
const matrixPath = resolve(here, '..', 'svelte-helm-matrix.yml');
const doc = parseYaml(readFileSync(matrixPath, 'utf8')) as Doc;

function cell(t: Track, axis: string): string {
  const c = t.axes?.[axis];
  if (!c) return '·';
  return c.status === 'n/a' ? '·' : c.status;
}

// Count axes by status across all tracks (the progress headline).
const counts: Record<CellStatus, number> = { '✓': 0, '⚠': 0, '✗': 0, 'n/a': 0 };
for (const t of doc.tracks) for (const a of AXES) {
  const s = t.axes?.[a]?.status;
  if (s) counts[s] += 1;
}
const live = counts['✓'] + counts['⚠'] + counts['✗']; // non-n/a axes
const pct = live === 0 ? 0 : Math.round((counts['✓'] / live) * 100);

const lines: string[] = [];
lines.push('# Svelte-Helm Roadmap');
lines.push('');
lines.push('> Generated from `docs/canon/svelte-helm-matrix.yml` by');
lines.push('> `docs/canon/render/svelte-helm-to-roadmap.ts` — do not edit by hand.');
lines.push('');
lines.push(`**Progress:** ${counts['✓']} ✓ · ${counts['⚠']} ⚠ · ${counts['✗']} ✗ ` +
  `(of ${live} live axes) — **${pct}% complete**.`);
lines.push('');
lines.push('## Track × axis status');
lines.push('');
lines.push(`| Track | Name | ${AXES.join(' | ')} |`);
lines.push(`|---|---|${AXES.map(() => '---').join('|')}|`);
for (const t of doc.tracks) {
  lines.push(`| ${t.id} | ${t.name} | ${AXES.map((a) => cell(t, a)).join(' | ')} |`);
}
lines.push('');
lines.push('Legend: ✓ done · ⚠ partial/in-progress · ✗ not started · · n/a.');
lines.push('Axes: A source · B wired · C tests · D brain · E helm · F wallet · G recovery · H intent · I docs · J old-code-deleted.');
lines.push('');
lines.push('## Done-when per track');
lines.push('');
for (const t of doc.tracks) {
  if (t.done_when) lines.push(`- **${t.id}** — ${t.done_when}`);
}
lines.push('');

process.stdout.write(lines.join('\n'));

```
