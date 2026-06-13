---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/start.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.306617+00:00
---

# runtime/node/src/commands/start.ts

```ts
/**
 * semantos start — start the node daemon in-process.
 *
 * Loads config, creates node, starts admin API.
 * Blocks until SIGINT/SIGTERM.
 */

import { createDaemon } from '../daemon';

export async function startCommand(args: string[]): Promise<void> {
  const configPath = getFlag(args, '--config')
    ?? process.env.SEMANTOS_CONFIG
    ?? './node.json';

  const certsDir = getFlag(args, '--certs')
    ?? process.env.SEMANTOS_CERTS_DIR;

  const port = Number(getFlag(args, '--port') ?? process.env.SEMANTOS_ADMIN_PORT ?? '6443');

  await createDaemon({ configPath, certsDir, adminPort: port });
  // createDaemon registers SIGINT/SIGTERM handlers and keeps the process alive
}

function getFlag(args: string[], flag: string): string | undefined {
  const idx = args.indexOf(flag);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

```
