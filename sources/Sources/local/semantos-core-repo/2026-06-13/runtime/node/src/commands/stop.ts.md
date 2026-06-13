---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/stop.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.306884+00:00
---

# runtime/node/src/commands/stop.ts

```ts
/**
 * semantos stop — stop the node.
 *
 * Sends POST /api/node/stop to the admin API, or uses systemctl.
 */

export async function stopCommand(args: string[]): Promise<void> {
  const endpoint = getFlag(args, '--endpoint')
    ?? process.env.SEMANTOS_ADMIN_ENDPOINT
    ?? 'http://localhost:6443';

  // Try admin API first
  try {
    const res = await fetch(`${endpoint}/api/node/status`, {
      signal: AbortSignal.timeout(3000),
    });
    if (res.ok) {
      console.log('Node is running. Sending stop signal via systemd...');
    }
  } catch {
    // Node not reachable via API
  }

  // Fall back to systemctl
  const proc = Bun.spawn(['systemctl', 'stop', 'semantos'], {
    stdout: 'inherit',
    stderr: 'inherit',
  });
  const exitCode = await proc.exited;

  if (exitCode === 0) {
    console.log('Node stopped.');
  } else {
    console.error('Failed to stop node. Is the service running?');
    console.error('Try: sudo systemctl stop semantos');
    process.exit(1);
  }
}

function getFlag(args: string[], flag: string): string | undefined {
  const idx = args.indexOf(flag);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

```
