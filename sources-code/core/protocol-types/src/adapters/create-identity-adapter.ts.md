---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/create-identity-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.882057+00:00
---

# core/protocol-types/src/adapters/create-identity-adapter.ts

```ts
/**
 * createIdentityAdapter — runtime identity adapter selection based on mode.
 *
 * Mode resolution:
 * 1. Explicit override via options.adapter → use it directly
 * 2. mode === 'stub' (default) → StubIdentityAdapter
 * 3. mode === 'local' → not yet implemented (Phase 26B)
 * 4. mode === 'cloud' → not yet implemented (Phase 26B)
 */

import type { IdentityAdapter, IdentityConfig, IdentityMode } from '../identity';

/**
 * Resolve the identity mode from environment.
 * Reads PLEXUS_MODE env var. Defaults to 'stub' if unset or unrecognized.
 */
export function resolveIdentityMode(): IdentityMode {
  const env = (typeof process !== 'undefined' && process.env?.PLEXUS_MODE) || 'stub';
  if (env === 'stub' || env === 'local' || env === 'cloud') return env;
  return 'stub';
}

export interface CreateIdentityAdapterOptions {
  /** Use this adapter directly — bypasses mode detection. */
  adapter?: IdentityAdapter;
  /** Identity mode: 'stub' | 'local' | 'cloud'. Defaults to 'stub'. */
  mode?: IdentityMode;
  /** Endpoint for local/cloud modes. Not used by stub. */
  endpoint?: string;
  /** Enable debug logging. */
  debugLogging?: boolean;
}

export async function createIdentityAdapter(
  options?: CreateIdentityAdapterOptions,
): Promise<IdentityAdapter> {
  if (options?.adapter) {
    return options.adapter;
  }

  const config: IdentityConfig = {
    mode: options?.mode ?? resolveIdentityMode(),
    endpoint: options?.endpoint,
    debugLogging: options?.debugLogging ?? false,
  };

  switch (config.mode) {
    case 'stub': {
      const { StubIdentityAdapter } = await import('./stub-identity-adapter');
      return new StubIdentityAdapter(config);
    }

    case 'local': {
      const { LocalIdentityAdapter } = await import('../identity-adapters/LocalIdentityAdapter');
      const { createAdapter } = await import('./create-adapter');
      const storageAdapter = await createAdapter();
      return new LocalIdentityAdapter(storageAdapter, {
        debugLogging: config.debugLogging,
      });
    }

    case 'cloud':
      throw {
        code: 'MODE_NOT_AVAILABLE',
        message: '[semantos] CloudIdentityAdapter not yet implemented. See Phase 26B.',
        recoverable: false,
      };

    default:
      throw {
        code: 'INVALID_MODE',
        message: `[semantos] Unknown identity mode: ${config.mode}`,
        recoverable: false,
      };
  }
}

```
