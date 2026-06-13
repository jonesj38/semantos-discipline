---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/intent-trace/src/cli.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.549408+00:00
---

# tools/intent-trace/src/cli.ts

```ts
#!/usr/bin/env bun
/**
 * RM-093 — `intent-trace` CLI.
 *
 * Subcommands:
 *   - `cascade <file>` — render every correlation group as an indented tree.
 *   - `show <correlationId> <file>` — render only the group matching one id.
 *   - `tail <file|->` — stream events as they arrive, rendering one
 *     line per event (single-shot for files, follow-mode for `-`).
 *
 * Usage:
 *   bun run tools/intent-trace/src/cli.ts cascade trace.jsonl
 *   cat trace.jsonl | bun run tools/intent-trace/src/cli.ts cascade -
 *
 * No external deps — uses Bun's `Bun.file` + `process.stdin` directly.
 */

import { parseTrace, groupByCorrelation, parseLine } from './parse.js';
import { renderAll, renderCascade } from './render.js';
import { jsonlToFixtureTest } from './to-fixture.js';

const HELP = `intent-trace — render @semantos/intent JSONL traces

Usage:
  intent-trace cascade <file|->
  intent-trace show <correlationId> <file|->
  intent-trace tail <file|->            [single-shot when file path is given]
  intent-trace fixturize <file|-> --input <FixtureName> [--correlation <id>]
  intent-trace --help

Options:
  --flags         include each reducer pass's flags (cascade / show only)
  --input <name>  name of the reducer fixture to assert against (fixturize)
  --correlation   correlationId filter (fixturize only; defaults to first)

The "<file|->" form reads from stdin when the argument is "-".
`;

export async function main(argv: ReadonlyArray<string>): Promise<number> {
  const args = argv.slice();
  if (args.length === 0 || args[0] === '--help' || args[0] === '-h') {
    process.stdout.write(HELP);
    return 0;
  }

  const cmd = args.shift()!;
  const includeFlags = consumeFlag(args, '--flags');

  switch (cmd) {
    case 'cascade': {
      const path = args.shift();
      if (!path) return usageErr('cascade requires a file path or "-"');
      const text = await readAll(path);
      const events = parseTrace(text);
      const groups = groupByCorrelation(events);
      const out = renderAll(groups, { includeFlags });
      process.stdout.write(out + '\n');
      return 0;
    }
    case 'show': {
      const corrId = args.shift();
      const path = args.shift();
      if (!corrId || !path) {
        return usageErr('show requires <correlationId> <file|->');
      }
      const text = await readAll(path);
      const events = parseTrace(text).filter((e) => e.correlationId === corrId);
      if (events.length === 0) {
        process.stderr.write(`intent-trace: no events for correlationId '${corrId}'\n`);
        return 1;
      }
      process.stdout.write(renderCascade(events, { includeFlags }) + '\n');
      return 0;
    }
    case 'tail': {
      const path = args.shift();
      if (!path) return usageErr('tail requires a file path or "-"');
      if (path === '-') {
        await tailStdin();
      } else {
        // Single-shot: read the whole file and render one line per event.
        const text = await readAll(path);
        for (const line of text.split(/\r?\n/)) {
          const ev = parseLine(line);
          if (ev) process.stdout.write(formatLine(ev) + '\n');
        }
      }
      return 0;
    }
    case 'fixturize': {
      const path = args.shift();
      const inputFixtureName = consumeOption(args, '--input');
      const correlationId = consumeOption(args, '--correlation');
      if (!path) return usageErr('fixturize requires a file path or "-"');
      if (!inputFixtureName) {
        return usageErr('fixturize requires --input <FixtureName>');
      }
      const text = await readAll(path);
      const ts = jsonlToFixtureTest(text, {
        inputFixtureName,
        ...(correlationId !== undefined ? { correlationId } : {}),
      });
      process.stdout.write(ts);
      return 0;
    }
    default:
      return usageErr(`unknown subcommand '${cmd}'`);
  }
}

function consumeOption(args: string[], name: string): string | undefined {
  const i = args.indexOf(name);
  if (i === -1) return undefined;
  const value = args[i + 1];
  args.splice(i, 2);
  return value;
}

async function readAll(path: string): Promise<string> {
  if (path === '-') return await readStdin();
  const file = Bun.file(path);
  return await file.text();
}

async function readStdin(): Promise<string> {
  const chunks: Uint8Array[] = [];
  const decoder = new TextDecoder();
  for await (const chunk of process.stdin as unknown as AsyncIterable<Uint8Array>) {
    chunks.push(chunk);
  }
  return decoder.decode(Buffer.concat(chunks.map((c) => Buffer.from(c))));
}

async function tailStdin(): Promise<void> {
  let buffer = '';
  const decoder = new TextDecoder();
  for await (const chunk of process.stdin as unknown as AsyncIterable<Uint8Array>) {
    buffer += decoder.decode(chunk, { stream: true });
    let nl = buffer.indexOf('\n');
    while (nl !== -1) {
      const line = buffer.slice(0, nl);
      buffer = buffer.slice(nl + 1);
      const ev = parseLine(line);
      if (ev) process.stdout.write(formatLine(ev) + '\n');
      nl = buffer.indexOf('\n');
    }
  }
}

function formatLine(e: { ts: string; correlationId: string; stage: string; durationMs: number }): string {
  return `${e.ts}  ${e.correlationId.slice(0, 16).padEnd(16, ' ')}  ${e.stage.padEnd(28, ' ')}  ${e.durationMs.toFixed(1)}ms`;
}

function usageErr(msg: string): number {
  process.stderr.write(`intent-trace: ${msg}\n${HELP}`);
  return 2;
}

function consumeFlag(args: string[], name: string): boolean {
  const i = args.indexOf(name);
  if (i === -1) return false;
  args.splice(i, 1);
  return true;
}

// Run when invoked directly.
if (import.meta.main) {
  main(process.argv.slice(2)).then((code) => {
    if (code !== 0) process.exit(code);
  });
}

```
