---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/src/manifest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.638741+00:00
---

# cartridges/tessera/brain/src/manifest.ts

```ts
/**
 * Tessera — in-code manifest.
 *
 * TypeScript companion to `manifest.json`. Provides a typed manifest
 * object that brain-side TS code and the eventual brain-Zig capability-
 * mint pass (DLO.1b) both consume.
 *
 * Mirrors `extensions/bsv-anchor-bundle/src/manifest.ts` shape for
 * cross-cartridge parity. The §O3-style acceptance gate (the test that
 * asserts the Zig mirror matches the TS canonical) extends to this
 * cartridge once DLO.1b lands.
 */

import {
  TESSERA_CAPABILITIES,
  TESSERA_CAP_NAMES,
  TESSERA_DOMAIN_FLAG_RANGE,
  type TesseraCapability,
} from './capabilities.js';

export interface ExtensionManifest {
  /** Stable extension id — matches `<id>` in `extensions/<id>/` + `manifest.json`. */
  readonly id: string;
  /** Semver version. */
  readonly version: string;
  /** Human-readable description. */
  readonly description: string;
  /** Declared capabilities — minted into operator-root cert at first boot per §O3 pattern. */
  readonly capabilities: readonly TesseraCapability[];
  /** Substrate adapter interfaces this cartridge implements (tessera implements none — it consumes). */
  readonly provides: readonly string[];
  /** Substrate adapter interfaces this cartridge consumes. */
  readonly consumes: Record<string, string>;
}

export const TESSERA_MANIFEST: ExtensionManifest = {
  id: 'tessera',
  version: '0.0.1',
  description:
    'Care-chain provenance cartridge — grape-to-glass-shaped traceability over physically handed-off objects via the four Phase-26 adapter interfaces.',
  capabilities: TESSERA_CAPABILITIES,
  provides: [],
  consumes: {
    StorageAdapter: 'required — bottle / case / pallet / shipment / care-event cell stores',
    IdentityAdapter: 'required — BCA derivation + BRC-52 cert binding on every patch',
    AnchorAdapter: 'required — SPV-verifiable cell anchoring for consumer scan budget',
    NetworkAdapter: 'required — cross-operator SignedBundle<TesseraPatch> federation',
  },
};

export {
  TESSERA_CAPABILITIES,
  TESSERA_CAP_NAMES,
  TESSERA_DOMAIN_FLAG_RANGE,
  type TesseraCapability,
};

```
