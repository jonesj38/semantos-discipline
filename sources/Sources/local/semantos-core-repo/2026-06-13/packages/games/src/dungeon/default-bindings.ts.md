---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/default-bindings.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.405398+00:00
---

# packages/games/src/dungeon/default-bindings.ts

```ts
/**
 * Default boot wiring for the dungeon engine.
 *
 * Production binds the rot.js `PreciseShadowcasting` implementation
 * to `fovPort`. Tests bind their own factory before calling the
 * facade, in which case this is a no-op.
 *
 * Idempotent: safe to invoke at module load. Mirrors the pattern in
 * `apps/poker-agent/src/p2p-agent-runner/default-bindings.ts`.
 */

import ROT from 'rot-js';

import { fovPort, type FovFactory, type FovProvider } from './fov-system';

/** Bind the production rot.js FOV factory. Idempotent. */
export function bindDefaultFovProvider(): void {
  if (fovPort.isBound()) return;
  const factory: FovFactory = ({ passable }): FovProvider => {
    const fov = new ROT.FOV.PreciseShadowcasting((x, y) => passable(x, y));
    return {
      compute: (originX, originY, radius, cb) =>
        fov.compute(originX, originY, radius, cb),
    };
  };
  fovPort.bind(factory);
}

```
