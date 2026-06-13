---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/commands/init.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.307434+00:00
---

# runtime/node/src/commands/init.ts

```ts
/**
 * semantos init — interactive node configuration.
 *
 * Prompts for node settings and writes node.json to the config path.
 * Works offline.
 */

import { writeFileSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';

export async function initCommand(args: string[]): Promise<void> {
  const configPath = getFlag(args, '--config')
    ?? process.env.SEMANTOS_CONFIG
    ?? './node.json';

  if (existsSync(configPath) && !args.includes('--force')) {
    console.log(`Config already exists at ${configPath}`);
    console.log('Use --force to overwrite.');
    return;
  }

  const cert = getFlag(args, '--cert') ?? `0x${randomHex(16)}`;
  const subnet = getFlag(args, '--subnet') ?? '2602:f9f8:0060:0001::';
  const interval = Number(getFlag(args, '--interval') ?? '600000');
  const dataDir = getFlag(args, '--data-dir') ?? '/var/semantos/data';

  const config = {
    nodeCert: cert,
    storage: { type: 'node-fs', root: dataDir },
    identity: { type: 'stub' },
    anchor: { type: 'stub', interval },
    network: { type: 'stub' },
    extensions: ['sovereignty'],
    anchorIntervalMs: interval,
    subnetPrefix: subnet,
    dataDir,
  };

  mkdirSync(dirname(configPath), { recursive: true });
  writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');

  console.log(`Node config written to ${configPath}`);
  console.log(`  Cert:     ${cert}`);
  console.log(`  Subnet:   ${subnet}`);
  console.log(`  Interval: ${interval}ms`);
  console.log(`  Data dir: ${dataDir}`);
}

function getFlag(args: string[], flag: string): string | undefined {
  const idx = args.indexOf(flag);
  if (idx === -1 || idx + 1 >= args.length) return undefined;
  return args[idx + 1];
}

function randomHex(bytes: number): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

```
