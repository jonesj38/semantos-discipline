---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/release.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.579629+00:00
---

# cartridges/jambox/web/release.config.ts

```ts
/**
 * release.config.ts — jam-room's declaration for the repo-wide release
 * pipeline at tools/release/.
 *
 * Build step (run before submit):
 *   cd apps/world-apps/jam-room && bun run build:bundle
 */

import { readFileSync } from 'node:fs';
import path from 'node:path';

import type { ReleaseConfig } from '../../../tools/release/lib';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const pkg = JSON.parse(readFileSync(path.join(HERE, 'package.json'), 'utf8'));

const config: ReleaseConfig = {
  name: 'world-app-jam-room',
  room: 'release.app.jam-room',
  hat: 'jam-room-maintainer@semantos',
  version: pkg.version,
  description: 'Jam Room world app — collaborative music sequencer backed by the cell-relay and world-beam runtime.',
  artifacts: [
    { name: 'main.js', target: 'browser-esm', path: 'public/main.js' },
  ],
  dependencies: [
    // Pin world-sdk and world-beam release stateHashes here after each release.
  ],
};

export default config;

```
