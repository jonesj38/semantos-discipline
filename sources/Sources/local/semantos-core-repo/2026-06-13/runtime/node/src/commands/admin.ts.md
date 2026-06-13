---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/admin.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.307981+00:00
---

# runtime/node/src/commands/admin.ts

```ts
/**
 * semantos admin — remote admin operations via endpoint flag.
 *
 * Usage: semantos admin --endpoint https://node:6443 status
 */

export async function adminCommand(args: string[]): Promise<void> {
  const endpoint = getFlag(args, '--endpoint');
  if (!endpoint) {
    console.error('Usage: semantos admin --endpoint <url> <command>');
    console.error('Commands: status, install-extension <name>');
    process.exit(1);
  }

  // Remove --endpoint and its value from args
  const remaining = args.filter((_, i) => {
    const prev = args[i - 1];
    return args[i] !== '--endpoint' && prev !== '--endpoint';
  });

  const subcommand = remaining[0];

  switch (subcommand) {
    case 'status': {
      const res = await fetch(`${endpoint}/api/node/status`, {
        signal: AbortSignal.timeout(5000),
      });
      const envelope = await res.json();
      console.log(JSON.stringify(envelope, null, 2));
      break;
    }
    case 'install-extension': {
      const name = remaining[1];
      if (!name) {
        console.error('Usage: semantos admin --endpoint <url> install-extension <name>');
        process.exit(1);
      }
      const res = await fetch(`${endpoint}/api/node/extensions/install`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name }),
        signal: AbortSignal.timeout(5000),
      });
      const envelope = await res.json();
      console.log(JSON.stringify(envelope, null, 2));
      break;
    }
    default:
      console.error(`Unknown admin command: ${subcommand}`);
      process.exit(1);
  }
}

function getFlag(args: string[], flag: string): string | undefined {
  const idx = args.indexOf(flag);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

```
