---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/release.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.441938+00:00
---

# cartridges/bsv-anchor-bundle/brain/release.config.ts

```ts
/**
 * release.config.ts — bsv-anchor-bundle's declaration for the repo-wide
 * release pipeline at tools/release/.
 *
 * Dual-artifact: ships both the TypeScript surface (the AnchorAdapter
 * delegation + capabilities) and the Zig surface (the wallet/payment/
 * headers code lifted via DLBA.2/.3/.4). Build step (run before submit):
 *
 *   cd cartridges/bsv-anchor-bundle/brain && bun run build
 *   cd cartridges/bsv-anchor-bundle/brain/zig && zig build
 */

import { readFileSync } from 'node:fs';
import path from 'node:path';

import type { ReleaseConfig } from '../../tools/release/lib';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const pkg = JSON.parse(readFileSync(path.join(HERE, 'package.json'), 'utf8'));

const config: ReleaseConfig = {
  name: 'bsv-anchor-bundle',
  room: 'release.extension.bsv-anchor-bundle',
  hat: 'bsv-anchor-bundle-maintainer@semantos',
  version: pkg.version,
  description:
    'BSV anchor backend cartridge — Phase 26C AnchorAdapter via BSV. Wallet + payment + refund + SPV headers.',
  artifacts: [
    { name: 'main.js', target: 'browser-esm', path: 'dist/index.js' },
    { name: 'bsv-anchor-bundle.wasm', target: 'wasm32-freestanding', path: 'zig/zig-out/bin/bsv-anchor-bundle.wasm' },
  ],
  dependencies: [
    // Pin protocol-types release stateHash here after each release of
    // bsv-anchor-bundle so AnchorAdapter interface compatibility is
    // explicit in the signed cell chain.
  ],
};

export default config;

```
