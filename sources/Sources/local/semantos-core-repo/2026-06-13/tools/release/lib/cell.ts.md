---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/lib/cell.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.559732+00:00
---

# tools/release/lib/cell.ts

```ts
/**
 * Release-cell construction. Thin wrapper over @semantos/cell-relay's
 * `buildChildCell` — the release pipeline is just one consumer of the
 * cell-relay protocol; cell-shape and hash-rule live in the package.
 */

import { buildChildCell } from '../../../packages/cell-relay/src';
import { RELEASE_OP, type ReleaseManifest, type SerializedCell } from './types';

export { canonicalJson } from '../../../packages/cell-relay/src';

export function buildReleaseCell(
  manifest: ReleaseManifest,
  parent: SerializedCell | null,
): SerializedCell {
  const payload = {
    ...manifest,
    parentReleaseHash: parent ? parent.stateHashHex : '',
  };
  return buildChildCell(parent, {
    patch: { op: RELEASE_OP, payload: payload as unknown as Record<string, unknown> },
    hat: manifest.hat,
    branch: 'main',
  });
}

```
