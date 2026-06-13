---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/plexus/config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.100637+00:00
---

# runtime/services/src/plexus/config.ts

```ts
/**
 * Plexus environment configuration and adapter factory.
 *
 * Switches between stub/local/cloud modes via PLEXUS_MODE env var.
 * No code changes required to switch — only the env var.
 */

import type { PlexusAdapter, PlexusConfig } from './types';
import { StubPlexusAdapter } from './stub';
import { resolveIdentityMode } from '../../../../core/protocol-types/src/adapters/create-identity-adapter';

/**
 * Resolve the Plexus mode from environment.
 * Delegates to resolveIdentityMode() in protocol-types.
 */
export const resolveMode = resolveIdentityMode;

/**
 * Factory: create the appropriate PlexusAdapter based on config mode.
 *
 * - stub: in-memory deterministic adapter (always available)
 * - local: real BRC-42 crypto + SQLite (requires bun:sqlite)
 * - cloud: not yet available (Phase 16+)
 *
 * The local/cloud adapter is loaded dynamically to avoid bundling
 * bun:sqlite and @plexus/* in browser builds that only use stub mode.
 */
export function createAdapter(config: PlexusConfig): PlexusAdapter {
  switch (config.mode) {
    case 'stub':
      return new StubPlexusAdapter(config);

    case 'local': {
      // Dynamic require to avoid bundling @plexus/* when in stub mode
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const { RealPlexusAdapter } = require('./real');
      return new RealPlexusAdapter(config);
    }

    case 'cloud':
      throw {
        code: 'MODE_NOT_AVAILABLE',
        message: "Cloud mode requires Plexus Network SDK (Phase 16+)",
        recoverable: false,
      };

    default:
      throw {
        code: 'INVALID_MODE',
        message: `Unknown Plexus mode: ${config.mode}`,
        recoverable: false,
      };
  }
}

```
