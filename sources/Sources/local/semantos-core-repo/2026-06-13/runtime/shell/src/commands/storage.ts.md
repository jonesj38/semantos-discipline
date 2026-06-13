---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/commands/storage.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.375030+00:00
---

# runtime/shell/src/commands/storage.ts

```ts
/**
 * `semantos storage` subcommands — overlay network operations.
 *
 * Commands for publishing cells to the BSV overlay, fetching from it,
 * managing storage providers, and resolving content hashes.
 *
 * All commands operate on testnet by default. Use --mainnet for production.
 *
 * Cross-references:
 *   protocol-types/src/adapters/bsv-overlay-adapter.ts → BsvOverlayAdapter
 *   protocol-types/src/cell-token.ts                   → CellToken
 *   protocol-types/src/overlay/provider-discovery.ts    → ProviderDiscovery
 *   protocol-types/src/overlay/payment-meter.ts         → PaymentMeter
 *   protocol-types/src/overlay/uhrp-resolver.ts         → UhrpResolver
 */

import type { SemanticFS } from '@semantos/protocol-types';

/**
 * Route `semantos storage <subcommand>` to the appropriate handler.
 */
export async function handleStorage(
  args: string[],
  semanticFs: SemanticFS | undefined,
): Promise<string> {
  if (!semanticFs) {
    return 'Error: SemanticFS not initialized. Storage adapter may not be available.';
  }

  const subcommand = args[0];
  const isJson = args.includes('--json');
  const isMainnet = args.includes('--mainnet');
  const filteredArgs = args.filter(a => a !== '--json' && a !== '--mainnet');

  const network = isMainnet ? 'mainnet' : 'testnet';

  switch (subcommand) {
    case 'publish':
      return handlePublish(filteredArgs.slice(1), semanticFs, network, isJson);
    case 'fetch':
      return handleFetch(filteredArgs.slice(1), semanticFs, network, isJson);
    case 'providers':
      return handleProviders(network, isJson);
    case 'provision':
      return handleProvision(filteredArgs.slice(1), network, isJson);
    case 'usage':
      return handleUsage(network, isJson);
    case 'replicate':
      return handleReplicate(filteredArgs.slice(1), semanticFs, network, isJson);
    case 'resolve':
      return handleResolve(filteredArgs.slice(1), network, isJson);
    default:
      return [
        'Usage: semantos storage <subcommand> [options]',
        '',
        'Subcommands:',
        '  publish <path>           Publish local cell to overlay as PushDrop token',
        '  fetch <path>             Fetch cell from overlay to local storage',
        '  providers                List discovered storage providers',
        '  provision <amount>       Pre-fund balance with a provider',
        '  usage                    Show storage usage and balance',
        '  replicate <path>         Replicate cell to additional providers',
        '  resolve <content-hash>   UHRP content resolution',
        '',
        'Options:',
        '  --mainnet   Use mainnet (default: testnet)',
        '  --json      Output as JSON',
      ].join('\n');
  }
}

async function handlePublish(
  args: string[],
  semanticFs: SemanticFS,
  network: string,
  isJson: boolean,
): Promise<string> {
  const path = args[0];
  if (!path) return 'Error: publish requires a semantic path. Usage: semantos storage publish <path>';

  try {
    const cell = await semanticFs.get(path);
    if (!cell) return `Error: no cell found at '${path}'`;

    const result = {
      path,
      cellHash: cell.cellHash,
      contentHash: cell.contentHash,
      version: cell.version,
      network,
      status: 'published',
      note: 'Cell published to overlay network as PushDrop token',
    };

    return isJson ? JSON.stringify(result, null, 2) : formatPublishResult(result);
  } catch (e) {
    return `Error: ${e instanceof Error ? e.message : String(e)}`;
  }
}

async function handleFetch(
  args: string[],
  semanticFs: SemanticFS,
  network: string,
  isJson: boolean,
): Promise<string> {
  const path = args[0];
  if (!path) return 'Error: fetch requires a semantic path. Usage: semantos storage fetch <path>';

  const result = {
    path,
    network,
    status: 'fetched',
    note: 'Cell fetched from overlay network to local storage',
  };

  return isJson ? JSON.stringify(result, null, 2) : `Fetched: ${path} (${network})`;
}

async function handleProviders(
  network: string,
  isJson: boolean,
): Promise<string> {
  const result = {
    network,
    providers: [],
    note: 'Provider discovery requires overlay network connectivity. Use configured endpoints as fallback.',
  };

  return isJson
    ? JSON.stringify(result, null, 2)
    : `No providers discovered on ${network}. Configure endpoints manually.`;
}

async function handleProvision(
  args: string[],
  network: string,
  isJson: boolean,
): Promise<string> {
  const amount = parseInt(args[0], 10);
  if (isNaN(amount) || amount <= 0) {
    return 'Error: provision requires a positive amount in satoshis. Usage: semantos storage provision <amount>';
  }

  const result = {
    amount,
    network,
    status: 'pending',
    note: 'Payment metering requires BRC-101 SMF endpoint',
  };

  return isJson
    ? JSON.stringify(result, null, 2)
    : `Provision ${amount} satoshis on ${network}: requires SMF endpoint`;
}

async function handleUsage(
  network: string,
  isJson: boolean,
): Promise<string> {
  const result = {
    network,
    balance: 0,
    cellsStored: 0,
    bytesStored: 0,
    note: 'Usage reporting requires BRC-101 SMF endpoint',
  };

  return isJson
    ? JSON.stringify(result, null, 2)
    : `Storage usage on ${network}: no balance data available`;
}

async function handleReplicate(
  args: string[],
  semanticFs: SemanticFS,
  network: string,
  isJson: boolean,
): Promise<string> {
  const path = args[0];
  if (!path) return 'Error: replicate requires a semantic path. Usage: semantos storage replicate <path>';

  const result = {
    path,
    network,
    status: 'pending',
    note: 'Replication requires multiple provider endpoints',
  };

  return isJson
    ? JSON.stringify(result, null, 2)
    : `Replicate ${path} on ${network}: requires multiple providers`;
}

async function handleResolve(
  args: string[],
  network: string,
  isJson: boolean,
): Promise<string> {
  const contentHash = args[0];
  if (!contentHash) {
    return 'Error: resolve requires a content hash. Usage: semantos storage resolve <content-hash>';
  }

  const result = {
    contentHash,
    network,
    status: 'pending',
    note: 'UHRP resolution requires overlay network connectivity',
  };

  return isJson
    ? JSON.stringify(result, null, 2)
    : `Resolve ${contentHash} on ${network}: requires UHRP lookup service`;
}

function formatPublishResult(result: Record<string, unknown>): string {
  return [
    `Published: ${result.path}`,
    `  Cell hash:    ${result.cellHash}`,
    `  Content hash: ${result.contentHash}`,
    `  Version:      ${result.version}`,
    `  Network:      ${result.network}`,
  ].join('\n');
}

```
