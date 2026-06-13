---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/logs.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.308785+00:00
---

# runtime/node/src/commands/logs.ts

```ts
/**
 * semantos logs — view node logs.
 *
 * Wraps journalctl for systemd-managed nodes.
 * Works offline.
 */

export async function logsCommand(args: string[]): Promise<void> {
  const follow = args.includes('--follow') || args.includes('-f');
  const lines = getFlag(args, '--lines') ?? '50';

  const journalArgs = ['-u', 'semantos', '-n', lines, '--no-pager'];
  if (follow) journalArgs.push('-f');

  const proc = Bun.spawn(['journalctl', ...journalArgs], {
    stdout: 'inherit',
    stderr: 'inherit',
  });
  await proc.exited;
}

function getFlag(args: string[], flag: string): string | undefined {
  const idx = args.indexOf(flag);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

```
