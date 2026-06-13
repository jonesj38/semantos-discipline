---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/self.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.308522+00:00
---

# runtime/node/src/commands/self.ts

```ts
/**
 * semantos self — display node self-object.
 *
 * Queries admin API for the sovereignty.node RELEVANT object.
 */

export async function selfCommand(args: string[]): Promise<void> {
  const endpoint = getFlag(args, '--endpoint')
    ?? process.env.SEMANTOS_ADMIN_ENDPOINT
    ?? 'http://localhost:6443';

  const jsonMode = args.includes('--json');

  try {
    const res = await fetch(`${endpoint}/api/node/self`, {
      signal: AbortSignal.timeout(3000),
    });

    if (!res.ok) {
      console.error(`Failed to fetch self-object: ${res.status}`);
      process.exit(1);
    }

    const envelope = await res.json() as { data: any };
    if (jsonMode) {
      console.log(JSON.stringify(envelope.data, null, 2));
    } else {
      const obj = envelope.data;
      console.log('Node Self-Object');
      console.log('----------------');
      console.log(`  Path:       ${obj.path}`);
      console.log(`  Linearity:  ${obj.linearity}`);
      if (obj.payload) {
        console.log(`  Cert:       ${obj.payload.nodeCert}`);
        console.log(`  Running:    ${obj.payload.running}`);
        console.log(`  Version:    ${obj.payload.version}`);
        console.log(`  Extensions:  ${obj.payload.extensions?.join(', ')}`);
        console.log(`  BCA:        ${obj.payload.bcaAddress ?? 'not set'}`);
        if (obj.payload.adapters) {
          console.log(`  Adapters:`);
          console.log(`    Storage:  ${obj.payload.adapters.storage}`);
          console.log(`    Identity: ${obj.payload.adapters.identity}`);
          console.log(`    Anchor:   ${obj.payload.adapters.anchor}`);
          console.log(`    Network:  ${obj.payload.adapters.network}`);
        }
      }
    }
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
