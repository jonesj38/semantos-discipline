---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/release.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.797913+00:00
---

# core/pask/release.config.ts

```ts
/**
 * release.config.ts — pask's declaration for the repo-wide release
 * pipeline at tools/release/. The pipeline reads this file and runs
 * the build/submit/fetch flow against the artifacts it points at.
 */

import { readFileSync } from 'node:fs';
import path from 'node:path';

import type { ReleaseConfig } from '../../tools/release/lib';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const zon = readFileSync(path.join(HERE, 'build.zig.zon'), 'utf8');
const version = zon.match(/\.version\s*=\s*"([^"]+)"/)?.[1] ?? '0.0.0';

const config: ReleaseConfig = {
  name: 'pask',
  room: 'release.kernel.pask',
  hat: 'pask-maintainer@semantos',
  version,
  description: 'Paskian learning kernel — constraint-graph propagation + stability over a fixed-pool node/edge graph.',
  artifacts: [
    { name: 'pask.wasm', target: 'wasm32-freestanding', path: 'zig-out/bin/pask.wasm' },
    { name: 'pask-wasi.wasm', target: 'wasm32-wasi', path: 'zig-out/bin/pask-wasi.wasm' },
  ],
  spec: { schema: '1', path: 'zig-out/release/pask-spec.json' },
  primer: { path: 'PRIMER.md' },
  dependencies: [],
};

export default config;

```
