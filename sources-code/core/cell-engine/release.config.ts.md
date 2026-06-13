---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/release.config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.805527+00:00
---

# core/cell-engine/release.config.ts

```ts
/**
 * release.config.ts — cell-engine's declaration for the repo-wide
 * release pipeline at tools/release/. Same shape as core/pask/release.config.ts;
 * the pipeline doesn't know or care which kernel is being released.
 *
 * Embedded profile only (no bsvz). Full profile would extend
 * `dependencies` with the bsvz release stateHash.
 */

import { readFileSync } from 'node:fs';
import path from 'node:path';

import type { ReleaseConfig } from '../../tools/release/lib';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const zon = readFileSync(path.join(HERE, 'build.zig.zon'), 'utf8');
const version = zon.match(/\.version\s*=\s*"([^"]+)"/)?.[1] ?? '0.0.0';

const config: ReleaseConfig = {
  name: 'cell-engine',
  room: 'release.kernel.cell-engine',
  hat: 'cell-engine-maintainer@semantos',
  version,
  description: 'Bitcoin-Script-with-linear-types VM (2-PDA cell engine).',
  artifacts: [
    { name: 'cell-engine-embedded.wasm', target: 'wasm32-freestanding', path: 'zig-out/bin/cell-engine-embedded.wasm' },
    { name: 'cell-engine-wasi-embedded.wasm', target: 'wasm32-wasi', path: 'zig-out/bin/cell-engine-wasi-embedded.wasm' },
  ],
  // No spec emitter for cell-engine yet — would slot in here.
  // No primer here yet either; this proves the optional fields work.
  dependencies: [],
};

export default config;

```
