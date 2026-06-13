---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cube-object/src/color.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.010280+00:00
---

# core/cube-object/src/color.ts

```ts
/**
 * Color resolution — pure functions, no THREE / DOM dependencies.
 *
 * Three sources of color, in priority order:
 *   1. Explicit per-cube override (`init.color`, e.g. server-supplied avatar hue)
 *   2. Identity-bound color derived from a `PlexusCert`'s public key
 *   3. Linearity-typed default (the LINEAR/AFFINE/RELEVANT palette)
 *
 * Source 2 mirrors `runtime/world-beam/apps/world_host/lib/world_host/avatar.ex:starting_color/1`
 * so client-only (single-player) avatars and server-coloured world avatars
 * pick the same palette and look consistent.
 */

import type { PlexusCert } from '@plexus/contracts';

import { type Linearity, linearityColor as defaultLinearityColor } from './linearity.js';

/**
 * 12-color avatar palette. Distinct from the LINEARITY palette so that
 * cert-bound avatars don't accidentally adopt the LINEAR teal etc.
 * Mirrors the world-host server (`avatar.ex`).
 */
export const AVATAR_PALETTE: readonly number[] = [
  0xe74c3c, 0xf39c12, 0xf1c40f, 0x9ccc65, 0x3498db, 0x9b59b6, 0xe91e63, 0xff6f61,
  0xffe66d, 0xc44569, 0xfb923c, 0x6366f1,
];

/**
 * Hash a cert's public-key hex to a palette index. The hash is
 * intentionally simple — it just needs to spread cert ids across the
 * palette deterministically; not security-bearing.
 */
export function certColor(cert: PlexusCert): number {
  let h = 0;
  for (let i = 0; i < cert.publicKey.length; i++) {
    h = (h * 31 + cert.publicKey.charCodeAt(i)) >>> 0;
  }
  return AVATAR_PALETTE[h % AVATAR_PALETTE.length]!;
}

/**
 * Pick the body color for a cube given the three possible inputs.
 * Returns a 24-bit RGB int (Three.js color shape).
 */
export function pickCubeColor(args: {
  /** Highest priority — explicit override (e.g. avatar color from server). */
  explicit: number | null;
  /** Middle priority — identity-bound color via cert public key hash. */
  cert: PlexusCert | null;
  /** Fallback — color from the linearity class. */
  linearity: Linearity;
}): number {
  if (args.explicit !== null && args.explicit !== undefined) return args.explicit;
  if (args.cert) return certColor(args.cert);
  return defaultLinearityColor(args.linearity);
}

```
