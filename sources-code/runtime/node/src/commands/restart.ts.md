---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/restart.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.306055+00:00
---

# runtime/node/src/commands/restart.ts

```ts
/**
 * semantos restart — restart the node.
 */

export async function restartCommand(_args: string[]): Promise<void> {
  const proc = Bun.spawn(['systemctl', 'restart', 'semantos'], {
    stdout: 'inherit',
    stderr: 'inherit',
  });
  const exitCode = await proc.exited;

  if (exitCode === 0) {
    console.log('Node restarted.');
  } else {
    console.error('Failed to restart node.');
    console.error('Try: sudo systemctl restart semantos');
    process.exit(1);
  }
}

```
