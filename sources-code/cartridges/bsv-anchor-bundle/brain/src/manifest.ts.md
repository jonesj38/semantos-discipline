---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/src/manifest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.444368+00:00
---

# cartridges/bsv-anchor-bundle/brain/src/manifest.ts

```ts
/**
 * BSV Anchor Bundle — in-code manifest.
 *
 * TypeScript companion to `manifest.json`. Provides a typed manifest
 * object that brain-side TS code (the `bsv-anchor-adapter.ts` delegation
 * shim per DLBA.1c) and the eventual brain-Zig capability-mint pass
 * (DLO.1b) both consume.
 *
 * Mirrors `extensions/oddjobz/src/manifest.ts` shape for cross-cartridge
 * parity. The §O3-style acceptance gate (the test that asserts the Zig
 * mirror matches the TS canonical) extends to this cartridge once
 * DLO.1b lands.
 */

import {
  BSV_ANCHOR_CAPABILITIES,
  BSV_ANCHOR_CAP_NAMES,
  BSV_ANCHOR_DOMAIN_FLAG_RANGE,
  type BsvAnchorCapability,
} from './capabilities.js';

export interface ExtensionManifest {
  /** Stable extension id — matches `<id>` in `extensions/<id>/` + `manifest.json`. */
  readonly id: string;
  /** Semver version. */
  readonly version: string;
  /** Human-readable description. */
  readonly description: string;
  /** Declared capabilities — minted into operator-root cert at first boot per §O3 pattern. */
  readonly capabilities: readonly BsvAnchorCapability[];
  /** Substrate adapter interfaces this cartridge implements. */
  readonly provides: readonly string[];
  /** Substrate adapter interfaces this cartridge consumes. */
  readonly consumes: Record<string, string>;
}

export const BSV_ANCHOR_MANIFEST: ExtensionManifest = {
  id: 'bsv-anchor-bundle',
  version: '0.0.1',
  description:
    'BSV anchor backend cartridge — implements Phase 26C AnchorAdapter using BSV as the timestamping + verification chain.',
  capabilities: BSV_ANCHOR_CAPABILITIES,
  provides: ['@semantos/protocol-types/anchor'],
  consumes: {
    StorageAdapter: 'required — output-store + derivation-state + header storage',
    IdentityAdapter: 'required — BRC-42 derivation under operator identity cert',
    wssSubprotocolRegistry: 'required — registers wallet.v1 against substrate WSS transport',
  },
};

export {
  BSV_ANCHOR_CAPABILITIES,
  BSV_ANCHOR_CAP_NAMES,
  BSV_ANCHOR_DOMAIN_FLAG_RANGE,
  type BsvAnchorCapability,
};

```
