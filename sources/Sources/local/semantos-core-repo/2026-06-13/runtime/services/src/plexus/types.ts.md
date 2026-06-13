---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/plexus/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.101197+00:00
---

# runtime/services/src/plexus/types.ts

```ts
/**
 * Backward-compatibility aliases — all types now live in protocol-types/src/identity.ts.
 * New code should import directly from protocol-types.
 */

export type { IdentityAdapter as PlexusAdapter } from '../../../../core/protocol-types/src/identity';
export type { IdentityMode as PlexusMode } from '../../../../core/protocol-types/src/identity';
export type { IdentityConfig as PlexusConfig } from '../../../../core/protocol-types/src/identity';
export type { IdentityError as PlexusError } from '../../../../core/protocol-types/src/identity';
export type { IdentityState as PlexusState } from '../../../../core/protocol-types/src/identity';

```
