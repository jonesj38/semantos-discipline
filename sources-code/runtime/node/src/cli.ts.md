---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/cli.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.302286+00:00
---

# runtime/node/src/cli.ts

```ts
#!/usr/bin/env bun
/**
 * Semantos CLI — entry point for the `semantos` command.
 *
 * Routes node-specific commands (init, start, stop, status, etc.)
 * to local handlers, and delegates semantic object commands
 * (new, inspect, list, etc.) to the shell.
 *
 * Cross-references:
 *   packages/shell/src/shell.ts — Shell class for semantic commands
 *   packages/node/src/commands/ — command implementations
 */

import { initCommand } from './commands/init';
import { startCommand } from './commands/start';
import { stopCommand } from './commands/stop';
import { statusCommand } from './commands/status';
import { restartCommand } from './commands/restart';
import { logsCommand } from './commands/logs';
import { selfCommand } from './commands/self';
import { extensionCommand } from './commands/extension';
import { anchorCommand } from './commands/anchor';
import { identityCommand } from './commands/identity';
import { adminCommand } from './commands/admin';
import { licenseCommand } from './commands/license';

const USAGE = `
Semantos CLI v0.1.0

Usage: semantos <command> [options]

Node Lifecycle:
  init                         Initialize node configuration
  start                        Start node daemon
  stop                         Stop node daemon
  status                       Show node status
  restart                      Restart node daemon
  logs [--follow]              View node logs

Extension Management:
  install extension <name>      Install an extension
  list extensions               List installed extensions
  uninstall extension <name>    Remove an extension

Identity Management:
  identity list                List all identities
  identity create --email <e>  Register new identity
  identity export --cert-id <> Export identity
  identity revoke --cert-id <> Revoke identity

Anchoring:
  anchor now                   Trigger immediate anchor
  anchor status                Show anchor state
  anchor history               List recent proofs

Node Object:
  self                         Print node self-object

Admin (remote):
  admin --endpoint <url> <cmd> Execute command on remote node

License (Phase 35B federation):
  license mint --holder-pubkey <hex> --out <path>   Mint a dev-issued license
  license show <path>                               Inspect a license file

Options:
  --json                       Output as JSON
  --help                       Show this help
  --version                    Show version
`.trim();

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === '--help' || args[0] === '-h') {
    console.log(USAGE);
    process.exit(0);
  }

  if (args[0] === '--version' || args[0] === '-v') {
    console.log('0.1.0');
    process.exit(0);
  }

  const command = args[0];
  const rest = args.slice(1);

  try {
    switch (command) {
      case 'init':
        await initCommand(rest);
        break;
      case 'start':
        await startCommand(rest);
        break;
      case 'stop':
        await stopCommand(rest);
        break;
      case 'status':
        await statusCommand(rest);
        break;
      case 'restart':
        await restartCommand(rest);
        break;
      case 'logs':
        await logsCommand(rest);
        break;
      case 'self':
        await selfCommand(rest);
        break;
      case 'install':
        if (rest[0] === 'extension') {
          await extensionCommand(['install', ...rest.slice(1)]);
        } else {
          console.error(`Unknown install target: ${rest[0]}`);
          process.exit(1);
        }
        break;
      case 'list':
        if (rest[0] === 'extensions') {
          await extensionCommand(['list']);
        } else {
          console.error(`Unknown list target: ${rest[0]}`);
          process.exit(1);
        }
        break;
      case 'uninstall':
        if (rest[0] === 'extension') {
          await extensionCommand(['uninstall', ...rest.slice(1)]);
        } else {
          console.error(`Unknown uninstall target: ${rest[0]}`);
          process.exit(1);
        }
        break;
      case 'identity':
        await identityCommand(rest);
        break;
      case 'anchor':
        await anchorCommand(rest);
        break;
      case 'admin':
        await adminCommand(rest);
        break;
      case 'license':
        await licenseCommand(rest);
        break;
      default:
        console.error(`Unknown command: ${command}`);
        console.error('Run "semantos --help" for usage.');
        process.exit(1);
    }
  } catch (err: any) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  }
}

main();

```
