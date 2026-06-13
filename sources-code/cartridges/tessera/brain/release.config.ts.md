---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/release.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.634019+00:00
---

# cartridges/tessera/brain/release.config.ts

```ts
/**
 * release.config.ts — tessera's declaration for the repo-wide release
 * pipeline at tools/release/.
 *
 * Dual-artifact: ships both the TypeScript surface (capability
 * declarations, lexicon re-export, AnchorAdapter / NetworkAdapter
 * consumer wiring) and the Zig surface (FSM walkers, StorageAdapter-
 * consumer stores, WASM module). Build step (run before submit):
 *
 *   cd cartridges/tessera/brain && bun run build
 *   cd cartridges/tessera/brain/zig && zig build
 *
 * Tessera is NOT in the D-Distro-default-install bundle — that bundle
 * is reserved for substrate-exposing cartridges (identity/hat-setup,
 * peer-pair, status-dashboard, minimal-talk). Tessera is a domain
 * cartridge; it installs separately via `semantos vertical install
 * tessera` once a deployment elects it.
 */

import { readFileSync } from 'node:fs';
import path from 'node:path';

import type { ReleaseConfig } from '../../tools/release/lib';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const pkg = JSON.parse(readFileSync(path.join(HERE, 'package.json'), 'utf8'));

const config: ReleaseConfig = {
  name: 'tessera',
  room: 'release.extension.tessera',
  hat: 'tessera-maintainer@semantos',
  version: pkg.version,
  description:
    'Care-chain provenance cartridge — Phase 36A operational/FSM cartridge consuming Storage/Identity/Anchor/Network adapters.',
  artifacts: [
    { name: 'main.js', target: 'browser-esm', path: 'dist/index.js' },
    { name: 'tessera.wasm', target: 'wasm32-freestanding', path: 'zig/zig-out/bin/tessera.wasm' },
  ],
  dependencies: [
    // Pin core/protocol-types release stateHash here after each tessera release
    // so adapter-interface compatibility is explicit in the signed cell chain.
    // Optional: pin bsv-anchor-bundle stateHash if a deployment requires the
    // BSV AnchorAdapter impl rather than the stub.
  ],
};

export default config;

```
