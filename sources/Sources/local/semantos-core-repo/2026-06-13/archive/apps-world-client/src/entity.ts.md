---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/entity.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.822744+00:00
---

# archive/apps-world-client/src/entity.ts

```ts
/**
 * Thin adapter wrapping `@semantos/cube-object`'s `CubeMesh` with the
 * world-host wire format. The cube renderer itself lives in
 * `core/cube-object/src/cube-mesh.ts` — extracted so the single-player
 * object demo (`apps/demo-wasm-threejs/`) and this multi-player world
 * client share the same THREE.js Mesh + identity-aware coloring.
 *
 * What this adapter still owns:
 *   - mapping `EntityDelta.spatial.position` → `CubeInit.position` /
 *     `applyAuthoritative.position`
 *   - threading `EntityDelta.color` (the server-supplied avatar hue)
 *     into the cube as the explicit color override
 *   - capturing `state_hash` and `version` from the wire frame
 *
 * Everything else — geometry, material, label, shake/flash, prediction,
 * dispose — comes from `CubeMesh` directly.
 */

import { CubeMesh } from '@semantos/cube-object';
import type { EntityDelta } from './types';

export class EntityMesh extends CubeMesh {
  constructor(id: string, initial: EntityDelta, ownerCertId: string | null = null) {
    super({
      id,
      linearity: initial.linearity,
      position: initial.spatial.position,
      // When this entity belongs to the local player, use the certId for
      // identity-bound color (AVATAR_PALETTE). For other entities, fall back
      // to the server-supplied color field.
      certId: ownerCertId ?? undefined,
      color: ownerCertId ? null : (initial.color ?? null),
    });
    this.lastStateHash = initial.state_hash;
    this.version = initial.version;
  }

  /**
   * World-host wire-format wrapper around `CubeMesh.applyAuthoritative`.
   * Kept as a separate method (rather than an override) so the adapter is
   * the only place that knows about `EntityDelta` shape.
   */
  applyAuthoritativeDelta(delta: EntityDelta): void {
    this.applyAuthoritative({
      position: delta.spatial.position,
      version: delta.version,
      state_hash: delta.state_hash,
    });
  }
}

```
