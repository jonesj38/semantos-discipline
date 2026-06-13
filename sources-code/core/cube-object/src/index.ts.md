---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cube-object/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.010554+00:00
---

# core/cube-object/src/index.ts

```ts
/**
 * @semantos/cube-object — the cube as a renderable semantic object.
 *
 * Two surfaces:
 *
 *   import { CubeMesh } from '@semantos/cube-object';        // Three.js renderer
 *   import { Linearity, linearityColor, ... } from
 *     '@semantos/cube-object/linearity';                     // pure types/colors
 *
 * The Three.js dependency is a peer — apps that just need the typed
 * primitives (e.g. server-side tests, identity-only flows) can import
 * `@semantos/cube-object/linearity` without pulling THREE in.
 */

export {
  type Linearity,
  type LinearityClass,
  linearityName,
  linearityColor,
  linearityClassColor,
  linearityClassToNumeric,
  linearityToClass,
} from './linearity.js';

export { CubeMesh, type CubeInit } from './cube-mesh.js';

export { pickCubeColor, certColor, AVATAR_PALETTE } from './color.js';

```
