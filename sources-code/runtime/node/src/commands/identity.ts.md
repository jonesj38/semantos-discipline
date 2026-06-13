---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/identity.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.306342+00:00
---

# runtime/node/src/commands/identity.ts

```ts
/**
 * semantos identity — identity management commands.
 *
 * Subcommands: list, create, export, revoke
 */

export async function identityCommand(args: string[]): Promise<void> {
  const endpoint = process.env.SEMANTOS_ADMIN_ENDPOINT ?? 'http://localhost:6443';
  const subcommand = args[0];
  const jsonMode = args.includes('--json');

  switch (subcommand) {
    case 'list':
      await identityList(endpoint, jsonMode);
      break;
    case 'create':
      await identityCreate(endpoint, args.slice(1), jsonMode);
      break;
    case 'export':
      await identityExport(endpoint, args.slice(1), jsonMode);
      break;
    case 'revoke':
      await identityRevoke(endpoint, args.slice(1));
      break;
    default:
      console.error('Usage: semantos identity <list|create|export|revoke>');
      process.exit(1);
  }
}

async function identityList(endpoint: string, jsonMode: boolean): Promise<void> {
  try {
    const res = await fetch(`${endpoint}/api/node/identities`, {
      signal: AbortSignal.timeout(3000),
    });
    const envelope = await res.json() as { data: any[] };

    if (jsonMode) {
      console.log(JSON.stringify(envelope.data, null, 2));
    } else {
      console.log('Identities');
      console.log('----------');
      for (const id of envelope.data) {
        console.log(`  ${id.certId}${id.email ? ` (${id.email})` : ''}`);
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

async function identityCreate(
  endpoint: string,
  args: string[],
  jsonMode: boolean,
): Promise<void> {
  const email = getFlag(args, '--email');
  if (!email) {
    console.error('Usage: semantos identity create --email <email>');
    process.exit(1);
  }

  try {
    const res = await fetch(`${endpoint}/api/node/identities`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email }),
      signal: AbortSignal.timeout(5000),
    });

    const envelope = await res.json() as { data: any; error?: any };
    if (res.ok) {
      if (jsonMode) {
        console.log(JSON.stringify(envelope.data, null, 2));
      } else {
        console.log(`Identity created:`);
        console.log(`  Cert ID:    ${envelope.data.certId}`);
        console.log(`  Public key: ${envelope.data.publicKey?.slice(0, 40)}...`);
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

async function identityExport(
  endpoint: string,
  args: string[],
  jsonMode: boolean,
): Promise<void> {
  const certId = getFlag(args, '--cert-id');
  if (!certId) {
    console.error('Usage: semantos identity export --cert-id <id>');
    process.exit(1);
  }

  try {
    const res = await fetch(
      `${endpoint}/api/node/identities/${encodeURIComponent(certId)}`,
      { signal: AbortSignal.timeout(3000) },
    );
    const envelope = await res.json() as { data: any };

    if (jsonMode) {
      console.log(JSON.stringify(envelope.data, null, 2));
    } else {
      console.log(JSON.stringify(envelope.data, null, 2));
    }
  } catch (err: any) {
    console.error(`Cannot reach node: ${err.message}`);
    process.exit(1);
  }
}

async function identityRevoke(endpoint: string, args: string[]): Promise<void> {
  const certId = getFlag(args, '--cert-id');
  if (!certId) {
    console.error('Usage: semantos identity revoke --cert-id <id>');
    process.exit(1);
  }

  try {
    const res = await fetch(
      `${endpoint}/api/node/identities/${encodeURIComponent(certId)}/revoke`,
      { method: 'POST', signal: AbortSignal.timeout(5000) },
    );
    const envelope = await res.json() as { data: any };
    console.log(`Identity ${certId}: ${envelope.data.status}`);
  } catch (err: any) {
    console.error(`Cannot reach node: ${err.message}`);
    process.exit(1);
  }
}

function getFlag(args: string[], flag: string): string | undefined {
  const idx = args.indexOf(flag);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

```
