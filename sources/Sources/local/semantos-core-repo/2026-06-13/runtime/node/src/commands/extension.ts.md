---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/extension.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.307170+00:00
---

# runtime/node/src/commands/extension.ts

```ts
/**
 * semantos extension commands — install, list, uninstall.
 *
 * Queries admin API for extension management.
 */

export async function extensionCommand(args: string[]): Promise<void> {
  const endpoint = process.env.SEMANTOS_ADMIN_ENDPOINT ?? 'http://localhost:6443';
  const subcommand = args[0];

  switch (subcommand) {
    case 'install':
      await installExtension(endpoint, args.slice(1));
      break;
    case 'list':
      await listExtensions(endpoint, args.slice(1));
      break;
    case 'uninstall':
      await uninstallExtension(endpoint, args.slice(1));
      break;
    default:
      console.error(`Unknown extension subcommand: ${subcommand}`);
      console.error('Usage: semantos install extension <name>');
      process.exit(1);
  }
}

async function installExtension(endpoint: string, args: string[]): Promise<void> {
  const name = args[0];
  if (!name) {
    console.error('Usage: semantos install extension <name>');
    process.exit(1);
  }

  try {
    const res = await fetch(`${endpoint}/api/node/extensions/install`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name }),
      signal: AbortSignal.timeout(5000),
    });

    const envelope = await res.json() as { data: any; error?: any };
    if (res.ok) {
      const jsonMode = args.includes('--json');
      if (jsonMode) {
        console.log(JSON.stringify(envelope.data, null, 2));
      } else {
        console.log(`Extension "${name}": ${envelope.data.status}`);
      }
    } else {
      console.error(`Failed: ${envelope.error?.message ?? res.statusText}`);
      process.exit(1);
    }
  } catch (err: any) {
    console.error(`Cannot reach node: ${err.message}`);
    process.exit(1);
  }
}

async function listExtensions(endpoint: string, args: string[]): Promise<void> {
  try {
    const res = await fetch(`${endpoint}/api/node/extensions`, {
      signal: AbortSignal.timeout(3000),
    });

    if (!res.ok) {
      console.error(`Failed: ${res.statusText}`);
      process.exit(1);
    }

    const envelope = await res.json() as { data: any[] };
    const jsonMode = args.includes('--json');
    if (jsonMode) {
      console.log(JSON.stringify(envelope.data, null, 2));
    } else {
      console.log('Installed Extensions');
      console.log('-------------------');
      for (const v of envelope.data) {
        console.log(`  ${v.name}${v.installed ? '' : ' (not installed)'}`);
      }
      if (envelope.data.length === 0) {
        console.log('  (none)');
      }
    }
  } catch (err: any) {
    console.error(`Cannot reach node: ${err.message}`);
    process.exit(1);
  }
}

async function uninstallExtension(endpoint: string, args: string[]): Promise<void> {
  const name = args[0];
  if (!name) {
    console.error('Usage: semantos uninstall extension <name>');
    process.exit(1);
  }

  try {
    const res = await fetch(`${endpoint}/api/node/extensions/${encodeURIComponent(name)}`, {
      method: 'DELETE',
      signal: AbortSignal.timeout(5000),
    });

    const envelope = await res.json() as { data: any; error?: any };
    if (res.ok) {
      console.log(`Extension "${name}" removed.`);
    } else {
      console.error(`Failed: ${envelope.error?.message ?? res.statusText}`);
      process.exit(1);
    }
  } catch (err: any) {
    console.error(`Cannot reach node: ${err.message}`);
    process.exit(1);
  }
}

```
