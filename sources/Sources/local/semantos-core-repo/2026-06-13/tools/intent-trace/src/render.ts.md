---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/intent-trace/src/render.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.550233+00:00
---

# tools/intent-trace/src/render.ts

```ts
/**
 * RM-093 — Cascade renderer.
 *
 * Renders a single correlation group as an indented tree the
 * cartridge author reads top-to-bottom:
 *
 *   [corr-abc] 11 events · 12.3ms total · source=nl
 *   ├── intent_produced  rawInputDigest=… len=27
 *   └── reducer (10 passes)
 *       ├── grammar             1.2ms  conf=0.85
 *       ├── logic               0.8ms  conf=0.78
 *       ├── rhetoric            2.4ms  conf=0.95  alt=2
 *       ├── relation            0.3ms  conf=1.00  skip
 *       └── …
 *
 * Renderer is intentionally pure-text — no colour escapes, no tty
 * sniff. Easy to golden-file in a test (RM-093 acceptance) and easy
 * for downstream tools (web UI, `less`) to consume as-is.
 */

import type { TraceEvent } from './parse.js';

export interface RenderOptions {
  /** When true, includes the full `data.flags` array under each
   *  reducer pass. Default false (one line per pass). */
  includeFlags?: boolean;
}

const PASS_INDENT = '    ';

/** Render a single correlation group. Returns a multi-line string,
 *  no trailing newline. */
export function renderCascade(events: TraceEvent[], opts: RenderOptions = {}): string {
  if (events.length === 0) return '';
  const corr = events[0]!.correlationId;
  const totalMs = events.reduce((acc, e) => acc + e.durationMs, 0);
  const source = events[0]!.source ?? 'unknown';

  const header = `[${corr}] ${events.length} events · ${totalMs.toFixed(1)}ms total · source=${source}`;
  const lines: string[] = [header];

  const produced = events.find((e) => e.stage === 'intent_produced');
  const reducerEvents = events.filter((e) => e.stage === 'reducer_pass_completed');
  const otherEvents = events.filter(
    (e) => e.stage !== 'intent_produced' && e.stage !== 'reducer_pass_completed',
  );

  if (produced) {
    const data = produced.data as Record<string, unknown>;
    const digest = typeof data.rawInputDigest === 'string'
      ? (data.rawInputDigest as string).slice(0, 16)
      : '–';
    const len = data.rawInputLength ?? '?';
    lines.push(`├── intent_produced  rawInputDigest=${digest}  len=${len}`);
  }

  if (reducerEvents.length > 0) {
    const reducerHeader = otherEvents.length > 0 ? '├──' : '└──';
    lines.push(`${reducerHeader} reducer (${reducerEvents.length} passes)`);
    for (let i = 0; i < reducerEvents.length; i++) {
      const e = reducerEvents[i]!;
      const isLast = i === reducerEvents.length - 1;
      const branch = isLast ? '└──' : '├──';
      lines.push(`${PASS_INDENT}${branch} ${formatPass(e)}`);
      if (opts.includeFlags) {
        const flags = (e.data as { flags?: unknown[] }).flags;
        if (Array.isArray(flags) && flags.length > 0) {
          const indent = isLast ? `${PASS_INDENT}    ` : `${PASS_INDENT}│   `;
          for (const f of flags) {
            lines.push(`${indent}⚑ ${String(f)}`);
          }
        }
      }
    }
  }

  for (let i = 0; i < otherEvents.length; i++) {
    const e = otherEvents[i]!;
    const isLast = i === otherEvents.length - 1;
    const branch = isLast ? '└──' : '├──';
    lines.push(`${branch} ${formatOther(e)}`);
  }

  return lines.join('\n');
}

/** Render every correlation group in arrival order, separated by a
 *  blank line. */
export function renderAll(
  groups: Map<string, TraceEvent[]>,
  opts: RenderOptions = {},
): string {
  const blocks: string[] = [];
  for (const events of groups.values()) {
    blocks.push(renderCascade(events, opts));
  }
  return blocks.join('\n\n');
}

function formatPass(e: TraceEvent): string {
  const d = e.data as {
    pass?: string;
    confidence?: number;
    skipInComposite?: boolean;
    alternativesCount?: number;
    flags?: unknown[];
  };
  const pass = d.pass ?? '?';
  const ms = e.durationMs.toFixed(1).padStart(4, ' ');
  const conf = (d.confidence ?? 0).toFixed(2);
  const parts = [`${pass.padEnd(20, ' ')}`, `${ms}ms`, `conf=${conf}`];
  if (d.alternativesCount && d.alternativesCount > 0) {
    parts.push(`alt=${d.alternativesCount}`);
  }
  if (d.skipInComposite) parts.push('skip');
  const flagCount = Array.isArray(d.flags) ? d.flags.length : 0;
  if (flagCount > 0) parts.push(`flags=${flagCount}`);
  return parts.join('  ');
}

function formatOther(e: TraceEvent): string {
  const ms = e.durationMs.toFixed(1).padStart(4, ' ');
  // Rejection events surface their reason inline so the grep-able
  // failure marker is on one line.
  if (e.stage === 'intent_rejected') {
    const reason = (e.data as { reason?: unknown }).reason;
    return `${e.stage.padEnd(20, ' ')}  ${ms}ms  reason=${String(reason)}`;
  }
  return `${e.stage.padEnd(20, ' ')}  ${ms}ms`;
}

```
