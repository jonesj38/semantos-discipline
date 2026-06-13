---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/cartridge-scaffold/bin/scaffold.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.561211+00:00
---

# tools/cartridge-scaffold/bin/scaffold.ts

```ts
#!/usr/bin/env bun
/**
 * RM-097 — `cartridge new` CLI binary.
 *
 * Usage:
 *   cartridge new <name> [--target <dir>] [--from-trace <file>]
 *                        [--input <FixtureName>]
 *
 * Wraps `writeScaffold` from `../src/scaffold.ts`.
 */

import { writeScaffold } from '../src/scaffold.js';

const HELP = `cartridge new <name> [--target <dir>] [--from-trace <file>] [--input <FixtureName>]

Scaffold a working cartridge skeleton at <target>/<name>/.

Options:
  --target <dir>          where to create the cartridge (default: cwd)
  --from-trace <file|->   captured JSONL trace to embed as the fixture
  --input <FixtureName>   reducer fixture the regression test asserts
                          against (default: T1_REPORT_DRIPPING_TAP)
  --help, -h
`;

async function main(argv: string[]): Promise<number> {
  const args = argv.slice();
  if (args.length === 0 || args[0] === '--help' || args[0] === '-h') {
    process.stdout.write(HELP);
    return 0;
  }
  if (args[0] !== 'new') {
    process.stderr.write(`cartridge: unknown subcommand '${args[0]}'\n${HELP}`);
    return 2;
  }
  args.shift();
  const name = args.shift();
  if (!name) {
    process.stderr.write(`cartridge new: missing <name>\n${HELP}`);
    return 2;
  }
  const target = consumeOption(args, '--target') ?? process.cwd();
  const fromTrace = consumeOption(args, '--from-trace');
  const inputFixtureName = consumeOption(args, '--input');

  const traceJsonl = fromTrace
    ? fromTrace === '-'
      ? await readStdin()
      : await Bun.file(fromTrace).text()
    : undefined;

  const result = await writeScaffold({
    name,
    targetDir: target,
    ...(traceJsonl !== undefined ? { traceJsonl } : {}),
    ...(inputFixtureName !== undefined ? { inputFixtureName } : {}),
  });

  process.stdout.write(`scaffolded cartridge: ${result.root}\n`);
  for (const f of result.files) {
    process.stdout.write(`  ${f.path}\n`);
  }
  return 0;
}

async function readStdin(): Promise<string> {
  const chunks: Uint8Array[] = [];
  const decoder = new TextDecoder();
  for await (const chunk of process.stdin as unknown as AsyncIterable<Uint8Array>) {
    chunks.push(chunk);
  }
  return decoder.decode(Buffer.concat(chunks.map((c) => Buffer.from(c))));
}

function consumeOption(args: string[], name: string): string | undefined {
  const i = args.indexOf(name);
  if (i === -1) return undefined;
  const value = args[i + 1];
  args.splice(i, 2);
  return value;
}

if (import.meta.main) {
  main(process.argv.slice(2)).then((code) => {
    if (code !== 0) process.exit(code);
  });
}

```
