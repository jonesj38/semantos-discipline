---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/status.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.308257+00:00
---

# runtime/node/src/commands/status.ts

```ts
/**
 * semantos status — show node status.
 *
 * Queries the admin API for node status. Falls back to systemctl.
 * Works offline for systemctl queries.
 */

export async function statusCommand(args: string[]): Promise<void> {
  const endpoint = getFlag(args, '--endpoint')
    ?? process.env.SEMANTOS_ADMIN_ENDPOINT
    ?? 'http://localhost:6443';

  const jsonMode = args.includes('--json');

  // Try admin API
  try {
    const res = await fetch(`${endpoint}/api/node/status`, {
      signal: AbortSignal.timeout(3000),
    });

    if (res.ok) {
      const envelope = await res.json() as { data: any; timestamp: number };
      if (jsonMode) {
        console.log(JSON.stringify(envelope.data, null, 2));
      } else {
        const s = envelope.data;
        console.log('Semantos Node Status');
        console.log('--------------------');
        console.log(`  Running:     ${s.running}`);
        console.log(`  Node cert:   ${s.nodeCert}`);
        console.log(`  BCA:         ${s.bcaAddress ?? 'not configured'}`);
        console.log(`  Uptime:      ${formatUptime(s.uptime)}`);
        console.log(`  Extensions:   ${s.installedExtensions?.join(', ') ?? 'none'}`);
        console.log(`  Last anchor: ${s.lastAnchor ? new Date(s.lastAnchor).toISOString() : 'never'}`);
        console.log(`  Adapters:`);
        if (s.adapters) {
          console.log(`    Storage:   ${s.adapters.storage}`);
          console.log(`    Identity:  ${s.adapters.identity}`);
          console.log(`    Anchor:    ${s.adapters.anchor}`);
          console.log(`    Network:   ${s.adapters.network}`);
        }
        if (s.diagnostics?.length) {
          console.log(`  Diagnostics: ${s.diagnostics.join(', ')}`);
        }
      }
      return;
    }
  } catch {
    // API not reachable
  }

  // Fall back to systemctl
  console.log('Admin API not reachable. Checking systemd...');
  const proc = Bun.spawn(['systemctl', 'status', 'semantos', '--no-pager'], {
    stdout: 'inherit',
    stderr: 'inherit',
  });
  await proc.exited;
}

/**
 * Query node status programmatically (used by gate tests).
 */
export async function getNodeStatus(endpoint: string): Promise<any> {
  const res = await fetch(`${endpoint}/api/node/status`, {
    signal: AbortSignal.timeout(3000),
  });
  if (!res.ok) throw new Error(`Status request failed: ${res.status}`);
  const envelope = await res.json() as { data: any };
  return envelope.data;
}

function formatUptime(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${s % 60}s`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
}

function getFlag(args: string[], flag: string): string | undefined {
  const idx = args.indexOf(flag);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

```
