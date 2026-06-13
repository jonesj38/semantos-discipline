---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/anchor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.309063+00:00
---

# runtime/node/src/commands/anchor.ts

```ts
/**
 * semantos anchor — anchor management commands.
 *
 * Subcommands: now, status, history
 */

export async function anchorCommand(args: string[]): Promise<void> {
  const endpoint = process.env.SEMANTOS_ADMIN_ENDPOINT ?? 'http://localhost:6443';
  const subcommand = args[0];
  const jsonMode = args.includes('--json');

  switch (subcommand) {
    case 'now':
      await anchorNow(endpoint, jsonMode);
      break;
    case 'status':
      await anchorStatus(endpoint, jsonMode);
      break;
    case 'history':
      await anchorHistory(endpoint, jsonMode);
      break;
    default:
      console.error('Usage: semantos anchor <now|status|history>');
      process.exit(1);
  }
}

async function anchorNow(endpoint: string, jsonMode: boolean): Promise<void> {
  try {
    const res = await fetch(`${endpoint}/api/node/anchor`, {
      method: 'POST',
      signal: AbortSignal.timeout(15000),
    });

    const envelope = await res.json() as { data: any; error?: any };
    if (res.ok) {
      if (jsonMode) {
        console.log(JSON.stringify(envelope.data, null, 2));
      } else {
        const p = envelope.data;
        console.log('Anchor triggered');
        console.log(`  State hash:    ${p.stateHash}`);
        console.log(`  TX ID:         ${p.txid}`);
        console.log(`  Block height:  ${p.blockHeight}`);
        console.log(`  Timestamp:     ${new Date(p.timestamp).toISOString()}`);
      }
    } else {
      console.error(`Anchor failed: ${envelope.error?.message ?? res.statusText}`);
      process.exit(1);
    }
  } catch (err: any) {
    console.error(`Cannot reach node: ${err.message}`);
    process.exit(1);
  }
}

async function anchorStatus(endpoint: string, jsonMode: boolean): Promise<void> {
  try {
    const res = await fetch(`${endpoint}/api/node/anchor/interval`, {
      signal: AbortSignal.timeout(3000),
    });

    const envelope = await res.json() as { data: any };
    if (jsonMode) {
      console.log(JSON.stringify(envelope.data, null, 2));
    } else {
      console.log('Anchor Status');
      console.log(`  Interval: ${envelope.data.intervalMs}ms`);
    }
  } catch (err: any) {
    console.error(`Cannot reach node: ${err.message}`);
    process.exit(1);
  }
}

async function anchorHistory(endpoint: string, jsonMode: boolean): Promise<void> {
  try {
    const res = await fetch(`${endpoint}/api/node/anchors`, {
      signal: AbortSignal.timeout(3000),
    });

    const envelope = await res.json() as { data: any[] };
    if (jsonMode) {
      console.log(JSON.stringify(envelope.data, null, 2));
    } else {
      console.log('Recent Anchors');
      console.log('--------------');
      if (envelope.data.length === 0) {
        console.log('  (none)');
      }
      for (const p of envelope.data) {
        console.log(`  ${p.stateHash?.slice(0, 16)}... → block ${p.blockHeight} (${new Date(p.timestamp).toISOString()})`);
      }
    }
  } catch (err: any) {
    console.error(`Cannot reach node: ${err.message}`);
    process.exit(1);
  }
}

```
