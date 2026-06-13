---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/bin/submit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.558597+00:00
---

# tools/release/bin/submit.ts

```ts
#!/usr/bin/env bun
/**
 * release-submit — put artifacts into the ContentStore and append a
 * signed cell to the relay's JSONL.
 *
 *   bun run tools/release/bin/submit.ts --config <release.config.ts>
 *     [--manifest <path>]   default: <pkg>/zig-out/release/<name>-<version>.json
 *     [--blobs <path>]      default: apps/demo-collab-versioning/data/blobs
 *     [--jsonl <path>]      default: apps/demo-collab-versioning/data/<room>.jsonl
 *
 * No kernel/pask-specific code. Same entrypoint for every package.
 */

import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

import {
  LocalContentStore,
  appendCell,
  buildReleaseCell,
  jsonlPathFor,
  lastReleaseCell,
  loadAllCells,
  loadConfig,
  type ReleaseManifest,
} from '../lib';

const argv = process.argv.slice(2);
function arg(flag: string, dflt?: string): string {
  const i = argv.indexOf(flag);
  if (i >= 0 && argv[i + 1]) return argv[i + 1]!;
  if (dflt !== undefined) return dflt;
  throw new Error(`missing ${flag}`);
}

const REPO_ROOT = path.resolve(import.meta.dir, '../../..');
const DEFAULT_RELAY_DATA = path.join(REPO_ROOT, 'apps/demo-collab-versioning/data');

const { config, paths } = await loadConfig(arg('--config'));
const manifestPath = arg('--manifest', path.join(paths.packageRoot, `zig-out/release/${config.name}-${config.version}.json`));
const blobsRoot = arg('--blobs', path.join(DEFAULT_RELAY_DATA, 'blobs'));
const jsonlPath = arg('--jsonl', jsonlPathFor(DEFAULT_RELAY_DATA, config.room));

if (!existsSync(manifestPath)) {
  console.error(`manifest not found: ${manifestPath}`);
  console.error('run release-build first');
  process.exit(1);
}

const manifest = JSON.parse(readFileSync(manifestPath, 'utf8')) as ReleaseManifest;
const store = new LocalContentStore(blobsRoot);

console.log(`submitting ${manifest.name}@${manifest.version} → ${config.room}`);

// Put each artifact and verify the manifest's claimed hash matches disk.
for (const a of Object.values(manifest.artifacts)) {
  const cfgArtifact = config.artifacts.find((x) => x.name === a.name);
  if (!cfgArtifact) {
    console.error(`manifest declares ${a.name} but config does not — refusing to guess path`);
    process.exit(1);
  }
  const abs = path.join(paths.packageRoot, cfgArtifact.path);
  const bytes = new Uint8Array(readFileSync(abs));
  const ref = store.put(bytes);
  if (ref.sha256 !== a.sha256) {
    console.error(`hash drift for ${a.name}: manifest=${a.sha256} disk=${ref.sha256}`);
    process.exit(1);
  }
  console.log(`  put ${a.name.padEnd(24)} → ${ref.path}`);
}

if (manifest.spec) {
  if (!config.spec) throw new Error('manifest claims spec but config does not declare one');
  const bytes = new Uint8Array(readFileSync(path.join(paths.packageRoot, config.spec.path)));
  const ref = store.put(bytes);
  if (ref.sha256 !== manifest.spec.sha256) {
    console.error(`spec hash drift: manifest=${manifest.spec.sha256} disk=${ref.sha256}`);
    process.exit(1);
  }
  console.log(`  put ${'spec'.padEnd(24)} → ${ref.path}`);
}

if (manifest.primer) {
  if (!config.primer) throw new Error('manifest claims primer but config does not declare one');
  const bytes = new Uint8Array(readFileSync(path.join(paths.packageRoot, config.primer.path)));
  const ref = store.put(bytes);
  if (ref.sha256 !== manifest.primer.sha256) {
    console.error(`primer hash drift: manifest=${manifest.primer.sha256} disk=${ref.sha256}`);
    process.exit(1);
  }
  console.log(`  put ${'primer'.padEnd(24)} → ${ref.path}`);
}

// Find prior release in the same room.
const existing = loadAllCells(jsonlPath);
const parent = lastReleaseCell(existing);
if (parent) {
  const prior = parent.patch.payload as { name?: string; version?: string };
  console.log(`  parent: ${prior.name}@${prior.version} state=${parent.stateHashHex.slice(0, 16)}...`);
} else {
  console.log('  parent: (none — first release)');
}

const cell = buildReleaseCell(manifest, parent);
appendCell(jsonlPath, cell);

console.log('');
console.log(`committed cell ${cell.stateHashHex}`);
console.log(`  → ${path.relative(process.cwd(), jsonlPath)}`);
console.log(`  depth=${cell.depth}  branch=${cell.branch}  hat=${cell.hat}`);

```
