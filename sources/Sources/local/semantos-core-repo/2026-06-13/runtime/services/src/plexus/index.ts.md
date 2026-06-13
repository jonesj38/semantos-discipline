---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/plexus/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.100912+00:00
---

# runtime/services/src/plexus/index.ts

```ts
/**
 * Plexus adapter barrel — the workbench's containment boundary.
 *
 * Everything the workbench needs from the identity/graph layer
 * is exported from here. No @plexus/* imports leak beyond this directory.
 */

export type {
  PlexusAdapter,
  PlexusMode,
  PlexusConfig,
  PlexusError,
  PlexusState,
} from './types';

export { StubPlexusAdapter } from './stub';
export { RealPlexusAdapter } from './real';
export { createAdapter, resolveMode } from './config';
export { PlexusService, initializePlexusService, getPlexusService } from './PlexusService';

// Canonical names from protocol-types
export type { IdentityAdapter, IdentityConfig, IdentityError, IdentityMode, IdentityState } from '../../../../core/protocol-types/src/identity';
export { StubIdentityAdapter } from '../../../../core/protocol-types/src/adapters/stub-identity-adapter';
export { createIdentityAdapter } from '../../../../core/protocol-types/src/adapters/create-identity-adapter';

```
