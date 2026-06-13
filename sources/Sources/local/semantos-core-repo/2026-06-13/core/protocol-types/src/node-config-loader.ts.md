---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/node-config-loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.843562+00:00
---

# core/protocol-types/src/node-config-loader.ts

```ts
/**
 * NodeConfig loader — reads JSON config, resolves adapter factories, applies CLI overrides.
 *
 * Bridges the gap between a static node-config.json file and a live NodeConfig
 * with instantiated adapter objects. Each adapter type string is mapped to its
 * concrete implementation via factory functions.
 *
 * Cross-references:
 *   node-config.ts   → NodeConfig, NodeConfigFile types
 *   adapters/        → concrete adapter implementations
 *   node.ts          → createNode() consumer of the resulting NodeConfig
 */

import type { StorageAdapter } from './storage';
import type { IdentityAdapter } from './identity';
import type { AnchorAdapter } from './anchor';
import type { NetworkAdapter } from './network';
import type { NodeConfig, NodeConfigFile } from './node-config';

/** CLI flag overrides that take precedence over JSON config values. */
export interface CliOverrides {
  cert?: string;
  bcaAddress?: string;
  subnetPrefix?: string;
  openRouterKey?: string;
  openRouterModel?: string;
  anchorIntervalMs?: number;
  dataDir?: string;
}

/**
 * Load a NodeConfig from a JSON file with optional CLI overrides.
 *
 * 1. Reads and parses the JSON file at configPath
 * 2. Resolves adapter type strings to live adapter instances
 * 3. Applies CLI overrides (take precedence over JSON values)
 * 4. Returns a fully assembled NodeConfig
 *
 * @throws Error if the file cannot be read, parsed, or contains unknown adapter types
 */
export async function loadNodeConfig(
  configPath: string,
  cliOverrides?: CliOverrides,
): Promise<NodeConfig> {
  const { readFileSync } = await import('fs');
  const raw = readFileSync(configPath, 'utf-8');
  const configFile: NodeConfigFile = JSON.parse(raw);

  const storage = await resolveStorageAdapter(configFile.storage);
  const identity = await resolveIdentityAdapter(configFile.identity, storage);
  const anchor = await resolveAnchorAdapter(configFile.anchor);
  const network = await resolveNetworkAdapter(configFile.network);

  return {
    storage,
    identity,
    anchor,
    network,
    nodeCert: cliOverrides?.cert ?? configFile.nodeCert,
    extensions: configFile.extensions,
    anchorIntervalMs: cliOverrides?.anchorIntervalMs ?? configFile.anchorIntervalMs ?? 600_000,
    bcaAddress: cliOverrides?.bcaAddress ?? configFile.bcaAddress,
    subnetPrefix: cliOverrides?.subnetPrefix ?? configFile.subnetPrefix,
    openRouterKey: cliOverrides?.openRouterKey ?? configFile.openRouterKey,
    openRouterModel: cliOverrides?.openRouterModel ?? configFile.openRouterModel,
    dataDir: cliOverrides?.dataDir ?? configFile.dataDir,
    // Phase 35B federation — propagate pass-through fields so
    // daemon.ts's license-policy gate and federation.ts's
    // startFederation actually see them. Without this they were
    // silently dead code on main.
    ...(configFile.license ? { license: configFile.license } : {}),
    ...(configFile.public ? { public: configFile.public } : {}),
    ...(configFile.locator ? { locator: configFile.locator } : {}),
  };
}

// ── Adapter Factories ─────────────────────────────────────────────

async function resolveStorageAdapter(
  spec: { type: string; [key: string]: unknown },
): Promise<StorageAdapter> {
  const { type, ...options } = spec;

  switch (type) {
    case 'memory': {
      const { MemoryAdapter } = await import('./adapters/memory-adapter');
      return new MemoryAdapter();
    }
    case 'node-fs': {
      const { NodeFsAdapter } = await import('./adapters/node-fs-adapter');
      return new NodeFsAdapter(options.root as string | undefined);
    }
    case 'opfs': {
      const { OpfsAdapter } = await import('./adapters/opfs-adapter');
      return new OpfsAdapter();
    }
    case 'indexed-db': {
      const { IndexedDbAdapter } = await import('./adapters/indexed-db-adapter');
      return new IndexedDbAdapter();
    }
    case 'bsv-overlay': {
      const { BsvOverlayAdapter } = await import('./adapters/bsv-overlay-adapter');
      return new BsvOverlayAdapter(options as any);
    }
    default:
      throw new Error(`Unknown storage adapter type: ${type}`);
  }
}

async function resolveIdentityAdapter(
  spec: { type: string; [key: string]: unknown },
  storageAdapter: StorageAdapter,
): Promise<IdentityAdapter> {
  const { type, ...options } = spec;

  switch (type) {
    case 'stub': {
      const { StubIdentityAdapter } = await import('./adapters/stub-identity-adapter');
      return new StubIdentityAdapter({ mode: 'stub', ...options });
    }
    case 'local': {
      const { LocalIdentityAdapter } = await import('./identity-adapters/LocalIdentityAdapter');
      return new LocalIdentityAdapter(storageAdapter, options as any);
    }
    default:
      throw new Error(`Unknown identity adapter type: ${type}`);
  }
}

async function resolveAnchorAdapter(
  spec: { type: string; [key: string]: unknown },
): Promise<AnchorAdapter> {
  const { type, ...options } = spec;

  switch (type) {
    case 'stub': {
      const { StubAnchorAdapter } = await import('./adapters/stub-anchor-adapter');
      return new StubAnchorAdapter(options.interval as number | undefined);
    }
    case 'bsv': {
      const { createAnchorAdapter } = await import('./anchor');
      return createAnchorAdapter({
        mode: 'bsv',
        interval: options.interval as number | undefined,
        network: options.network as 'mainnet' | 'testnet' | undefined,
        ownerKey: options.ownerKey as string | undefined,
      });
    }
    default:
      throw new Error(`Unknown anchor adapter type: ${type}`);
  }
}

async function resolveNetworkAdapter(
  spec: { type: string; [key: string]: unknown },
): Promise<NetworkAdapter> {
  const { type, ...options } = spec;

  switch (type) {
    case 'stub': {
      const { StubNetworkAdapter } = await import('./adapters/stub-network-adapter');
      return new StubNetworkAdapter(options as any);
    }
    case 'bsv-overlay': {
      const { BsvOverlayNetworkAdapter } = await import('./adapters/bsv-overlay-network-adapter');
      return new BsvOverlayNetworkAdapter(options as any);
    }
    default:
      throw new Error(`Unknown network adapter type: ${type}`);
  }
}

```
